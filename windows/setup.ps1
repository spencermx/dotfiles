<#
.SYNOPSIS
    Provisions a Windows machine from this repo.

.DESCRIPTION
    Installs applications, sets environment variables, extends PATH, and links
    dotfiles out of this repo into their live locations.

    Every phase is idempotent, so re-running only changes what is actually out
    of date. Safe to run repeatedly as the repo evolves.

    Phases are isolated: if one fails the others still run, and the script
    exits non-zero listing what failed.

    NOTE: keep this file ASCII-only. Windows PowerShell 5.1 reads .ps1 as the
    system ANSI codepage when there is no BOM, and a mis-decoded multi-byte
    character can produce a smart quote that PowerShell treats as a string
    delimiter, breaking the parse far from the actual line.

.PARAMETER Phase
    Which phases to run. Defaults to all of them.
      Packages  winget installs the applications listed in this file
      Env       user environment variables
      Path      user PATH entries
      Links     symlinks from the home directory into this repo

.PARAMETER DryRun
    Print what would change without changing anything.

.EXAMPLE
    .\setup.ps1 -DryRun
    .\setup.ps1
    .\setup.ps1 -Phase Links,Path

.NOTES
    The Links phase creates symbolic links, which require either an elevated
    prompt or Developer Mode. Unelevated, it falls back to copying.
    Everything else runs fine without elevation.

    If the script will not start at all, execution policy is blocking it:
      powershell -ExecutionPolicy Bypass -File .\setup.ps1
#>

[CmdletBinding()]
param(
    [ValidateSet('Packages', 'Env', 'Path', 'Links')]
    [string[]] $Phase = @('Packages', 'Env', 'Path', 'Links'),

    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Resolve Documents properly. On a machine with OneDrive Known Folder Move this
# is NOT %USERPROFILE%\Documents, and hardcoding it would put the PowerShell
# profile somewhere PowerShell never looks.
$MyDocuments = [Environment]::GetFolderPath('MyDocuments')
if (-not $MyDocuments) { $MyDocuments = Join-Path $env:USERPROFILE 'Documents' }

#--------------------------------------------------------------------------
# Configuration
#--------------------------------------------------------------------------

# Applications, by winget package ID.
#
# Runtimes and redistributables (VCRedist, VCLibs, WindowsAppRuntime, UI.Xaml,
# .NET Native) are deliberately absent -- they arrive as dependencies of the
# packages below. setup\winget-export.json holds the full raw snapshot of this
# machine if you need to see everything.
$Packages = @(
    # shell and editors
    #
    # No vim entry: Git for Windows bundles vim 9.2 at Git\usr\bin, which is
    # already in $PathEntries. The winget vim.vim package installs to
    # %LOCALAPPDATA%\Programs\Vim and creates no shim, so it was never on PATH
    # and Git's copy won anyway. One vim, one owner.
    'Git.Git'
    'GitHub.cli'
    'Microsoft.WindowsTerminal'
    'Microsoft.PowerShell'          # PowerShell 7. Windows ships 5.1 and never updates it.
    'Microsoft.VisualStudioCode'

    # dev toolchain
    'Microsoft.VisualStudio.Community'
    'Microsoft.WindowsSDK.10.0.26100'
    'Rustlang.Rustup'
    'Microsoft.WSL'

    # claude
    'Anthropic.Claude'

    # recovery and disk
    'CGSecurity.TestDisk'
    'Piriform.Recuva'
    'DiskInternals.LinuxReader'

    # virtualization
    'Oracle.VirtualBox'

    # security
    'Yubico.Authenticator'
    'Yubico.YubikeyManager'

    # database
    'Microsoft.CLRTypesSQLServer.2019'

    # comms and peripherals
    'Microsoft.Teams'
    'TeamViewer.TeamViewer'
    'WhirlwindFX.SignalRgb'
)

# Environment variables, set at user scope. Values expand at run time, so
# nothing here hardcodes a username.
$EnvVars = [ordered]@{
    '_NT_SYMBOL_PATH' = 'cache*C:\symbols;srv*https://msdl.microsoft.com/download/symbols'
    'sqlpath'         = "$env:USERPROFILE\data\sql"
}

# PATH entries. Anything not present on disk is skipped rather than added, so
# stale tool paths degrade quietly instead of poisoning PATH.
$PathEntries = @(
    # drift is put on PATH where it was built. There is no copy and no install
    # step -- one binary, in the directory that produced it, so there is never a
    # question of which one you are running. Resolved relative to this repo so
    # moving the whole tree keeps working. If drift2 is not cloned this fails
    # the Test-Path check below and is skipped, like any other absent tool.
    [IO.Path]::GetFullPath("$RepoRoot\..\..\drift2\build")

    "$env:USERPROFILE\.dotnet\tools"    # dotnet tool install -g lands here
    "$env:USERPROFILE\.local\bin"       # loose personal binaries
    'C:\Program Files\Git\usr\bin'      # vim, sed, grep, ssh
    'C:\Program Files (x86)\Microsoft Visual Studio\Installer'                  # vswhere
    'C:\Program Files (x86)\Microsoft SDKs\Windows\v10.0A\bin\NETFX 4.8 Tools'  # ildasm, sn
    'C:\Program Files\Notepad++'
)

# Find Visual Studio with vswhere instead of hardcoding a version path, so this
# survives VS upgrades and works on any edition.
$VsRoot = $null
$VsWhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path -LiteralPath $VsWhere) {
    $VsRoot = & $VsWhere -latest -property installationPath 2>$null | Select-Object -First 1
}

if ($VsRoot) {
    # devenv.exe. Opening a solution with `devenv foo.sln` does not need the
    # full developer environment -- it only needs this directory on PATH.
    # Command-line builds (cl, link, msbuild) still want `vsdev`, the function
    # in config\Microsoft.PowerShell_profile.ps1.
    $PathEntries += "$VsRoot\Common7\IDE"
    $PathEntries += "$VsRoot\MSBuild\Current\Bin"
}

# Directories that have to exist for the PATH entries referencing them to mean
# anything. Created if absent, before the PATH prune runs. Nothing here is
# "expected to be missing" -- if a directory belongs on PATH, the script makes
# it real and then puts it on PATH. Anything listed here that is meant to be
# reachable must also appear in $PathEntries above; creating a directory the
# shell cannot find is pointless.
$EnsureDirs = @(
    "$env:USERPROFILE\.dotnet\tools"
    "$env:USERPROFILE\.local\bin"
)

# .NET global tools, installed with `dotnet tool install -g`. Installing any of
# these is also what populates ~\.dotnet\tools.
$DotnetTools = @(
    # 'dotnet-ef'
    # 'dotnet-outdated-tool'
)

# Declared packages that are installed but never auto-upgraded. Everything else
# is brought current on every run; these are too large for that to be a
# reasonable side effect of running setup.
#
# Microsoft.VisualStudio.Community is also an unversioned id pointing at the
# current major (2026 / 18.x today). An automatic upgrade could therefore carry
# a major-version jump, which would break commands\vs2026.cmd -- it hardcodes
# the \18\Community\ path.
#
# They are still reported as outdated by the health check, just not acted on.
$NoAutoUpgrade = @(
    'Microsoft.VisualStudio.Community'
)

# Commands that must resolve once everything is applied. Checked by the final
# health check against the registry PATH, not this process's stale copy.
$ExpectedCommands = @('git', 'gh', 'vim', 'drift', 'code', 'winget', 'devenv', 'msbuild')

# link location -> file in this repo
$Links = [ordered]@{
    "$env:USERPROFILE\.gitconfig"                              = "$RepoRoot\config\.gitconfig"
    "$env:USERPROFILE\.vimrc"                                  = "$RepoRoot\config\.vimrc"
    "$env:USERPROFILE\AppData\Roaming\Code\User\settings.json" = "$RepoRoot\config\vscode\settings.json"
    # Claude Code's per-directory memory does not carry between sibling working
    # directories, so instructions that must always apply cannot live there.
    # This file loads in every session whatever the cwd, which is the only
    # place a rule like "no AI attribution in commits" actually holds.
    "$env:USERPROFILE\.claude\CLAUDE.md"                       = "$RepoRoot\config\claude\CLAUDE.md"
    # attribution.commit/pr are set to "" here, which is what actually stops the
    # Co-Authored-By trailer being generated. The CLAUDE.md rule above still
    # says so in words, but this is the half that does not depend on it being
    # read. permissions.allow covers the read-only and routine-workflow commands
    # so they stop prompting; see the ask/deny lists for what still stops.
    "$env:USERPROFILE\.claude\settings.json"                   = "$RepoRoot\config\claude\settings.json"
    # PowerShell 5.1 and PowerShell 7 read profiles from different folders --
    # WindowsPowerShell\ and PowerShell\ respectively. Link both to the same
    # file so either shell behaves identically.
    "$MyDocuments\WindowsPowerShell\Microsoft.PowerShell_profile.ps1" = "$RepoRoot\config\Microsoft.PowerShell_profile.ps1"
    "$MyDocuments\PowerShell\Microsoft.PowerShell_profile.ps1"        = "$RepoRoot\config\Microsoft.PowerShell_profile.ps1"
}

#--------------------------------------------------------------------------
# Helpers
#--------------------------------------------------------------------------

function Write-Step   { param($m) Write-Host "`n== $m" -ForegroundColor Cyan }
function Write-Change { param($m) Write-Host "   + $m" -ForegroundColor Green }
function Write-Skip   { param($m) Write-Host "   . $m" -ForegroundColor DarkGray }
function Write-Warn   { param($m) Write-Host "   ! $m" -ForegroundColor Yellow }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$script:FailedPhases = @()

# Run a phase so that a failure inside it does not take down the rest of the
# script. Without this, ErrorActionPreference=Stop means one bad file aborts
# everything, potentially half-applied.
function Invoke-Phase {
    param([string] $Name, [scriptblock] $Body)
    try {
        & $Body
    }
    catch {
        Write-Warn "phase aborted: $($_.Exception.Message)"
        $script:FailedPhases += $Name
    }
}

#--------------------------------------------------------------------------
# Phases
#--------------------------------------------------------------------------

function Invoke-Packages {
    Write-Step 'Packages'

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warn 'winget not found -- skipping every package.'
        Write-Warn 'Install "App Installer" from the Microsoft Store, or grab it from'
        Write-Warn 'https://aka.ms/getwinget, then re-run: .\setup.ps1 -Phase Packages'
        $script:FailedPhases += 'Packages'
        return
    }

    foreach ($id in $Packages) {
        # Do not trust the exit code alone -- some winget versions return 0 with
        # "No installed package found". Require the id to appear in the output.
        $listed = $null
        try {
            $listed = winget list --id $id --exact --accept-source-agreements 2>&1 | Out-String
        }
        catch {
            $listed = ''
        }

        if ($LASTEXITCODE -eq 0 -and $listed -match [regex]::Escape($id)) {
            Write-Skip "$id already installed"
            continue
        }

        if ($DryRun) {
            Write-Change "would install $id"
            continue
        }

        Write-Change "installing $id"
        winget install --id $id --exact --silent `
            --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            # Keep going. One unavailable package should not stop the rest.
            Write-Warn "$id failed (exit $LASTEXITCODE) -- continuing"
        }
    }

    Invoke-Upgrades
}

# Returns the declared package ids that winget reports an upgrade for.
function Get-OutdatedPackages {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return @() }

    $out = ''
    try { $out = winget upgrade --include-unknown 2>&1 | Out-String } catch { return @() }

    return @($Packages | Where-Object { $out -match ('(?m)^\S.*\s' + [regex]::Escape($_) + '\s') })
}

# Every run brings declared packages up to date. Installing what is missing is
# only half the job -- a machine pinned to whatever version happened to be
# current on provisioning day is not "set up". Note this can be slow: a Visual
# Studio update is measured in gigabytes.
function Invoke-Upgrades {
    Write-Step 'Upgrades'

    $outdated = Get-OutdatedPackages
    if ($outdated.Count -eq 0) {
        Write-Skip 'everything declared is current'
        return
    }

    foreach ($id in @($outdated | Where-Object { $NoAutoUpgrade -contains $_ })) {
        Write-Skip "$id is behind, but excluded from auto-upgrade"
        Write-Skip "  upgrade it deliberately: winget upgrade --id $id --exact"
    }

    foreach ($id in @($outdated | Where-Object { $NoAutoUpgrade -notcontains $_ })) {
        if ($DryRun) {
            Write-Change "would upgrade $id"
            continue
        }
        Write-Change "upgrading $id"
        winget upgrade --id $id --exact --silent `
            --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "$id upgrade failed (exit $LASTEXITCODE) -- continuing"
        }
    }
}

function Invoke-Dirs {
    Write-Step 'Directories'

    foreach ($d in $EnsureDirs) {
        if (Test-Path -LiteralPath $d) {
            Write-Skip "$d exists"
            continue
        }
        if ($DryRun) {
            Write-Change "would create $d"
            continue
        }
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Write-Change "created $d"
    }
}

function Invoke-DotnetTools {
    if ($DotnetTools.Count -eq 0) { return }

    Write-Step '.NET global tools'

    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        Write-Warn 'dotnet not found -- skipping global tools'
        $script:FailedPhases += 'Packages'
        return
    }

    $installed = ''
    try { $installed = dotnet tool list -g 2>&1 | Out-String } catch { $installed = '' }

    foreach ($t in $DotnetTools) {
        if ($installed -match [regex]::Escape($t)) {
            Write-Skip "$t already installed"
            continue
        }
        if ($DryRun) {
            Write-Change "would install $t"
            continue
        }
        Write-Change "installing $t"
        dotnet tool install -g $t
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "$t failed (exit $LASTEXITCODE) -- continuing"
        }
    }
}

function Invoke-Env {
    Write-Step 'Environment variables'

    foreach ($name in $EnvVars.Keys) {
        $want = $EnvVars[$name]
        $have = [Environment]::GetEnvironmentVariable($name, 'User')

        if ($have -eq $want) {
            Write-Skip "$name already set"
            continue
        }

        if ($DryRun) {
            Write-Change "would set $name = $want"
            continue
        }

        [Environment]::SetEnvironmentVariable($name, $want, 'User')
        Write-Change "$name = $want"
    }
}

function Invoke-Path {
    Write-Step 'PATH'

    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($null -eq $current) { $current = '' }
    $parts = @($current.Split(';') | Where-Object { $_ })
    $added = @()
    $pruned = @()

    # Compare on a normalized form so a stray trailing backslash doesn't read
    # as a different entry and produce a duplicate.
    $normalized = @($parts | ForEach-Object { $_.TrimEnd('\') })

    foreach ($entry in $PathEntries) {
        if (-not (Test-Path -LiteralPath $entry)) {
            Write-Skip "$entry (not on disk)"
            continue
        }
        if ($normalized -contains $entry.TrimEnd('\')) {
            Write-Skip "$entry already on PATH"
            continue
        }
        if ($DryRun) {
            Write-Change "would add $entry"
            continue
        }
        $added += $entry
    }

    # Prune entries pointing at nothing. A dead entry is dead weight -- it slows
    # every command lookup and hides typos. Anything that should exist was
    # already created by Invoke-Dirs, so whatever is still missing is genuinely
    # stale.
    foreach ($p in $parts) {
        if (Test-Path -LiteralPath $p -ErrorAction SilentlyContinue) { continue }
        if ($DryRun) {
            Write-Change "would prune dead entry $p"
            continue
        }
        $pruned += $p
    }

    if ($added.Count -eq 0 -and $pruned.Count -eq 0) { return }

    $kept = @($parts | Where-Object { $pruned -notcontains $_ })
    $new  = (($kept + $added) -join ';')

    # SetEnvironmentVariable always writes REG_SZ. If the current PATH is
    # REG_EXPAND_SZ holding %VAR% references, rewriting it would freeze them as
    # literal text and silently break every path that used one. Refuse instead.
    if ($current -match '%') {
        Write-Warn 'current PATH contains %VAR% references.'
        Write-Warn 'Rewriting it would stop them expanding, so leaving PATH alone.'
        Write-Warn 'Add these by hand (System Properties > Environment Variables):'
        $added | ForEach-Object { Write-Warn "    $_" }
        $script:FailedPhases += 'Path'
        return
    }

    # The registry value is capped. Truncating PATH is destructive and hard to
    # notice, so stop well short of the limit rather than risk it.
    if ($new.Length -gt 2000) {
        Write-Warn "PATH would become $($new.Length) chars, too close to the limit."
        Write-Warn 'Refusing to write it. Prune PATH, then re-run.'
        $script:FailedPhases += 'Path'
        return
    }

    [Environment]::SetEnvironmentVariable('Path', $new, 'User')
    $added  | ForEach-Object { Write-Change $_ }
    $pruned | ForEach-Object { Write-Change "pruned dead entry $_" }
}

function Invoke-Links {
    Write-Step 'Links'

    $admin = Test-Admin
    if (-not $admin) {
        Write-Warn 'Not elevated. Symlinks need admin or Developer Mode.'
        Write-Warn 'Falling back to copies. Re-run elevated for real links.'
    }

    foreach ($link in $Links.Keys) {
        $target = $Links[$link]

        if (-not (Test-Path -LiteralPath $target)) {
            Write-Warn "target missing, skipping: $target"
            continue
        }

        $existing = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue

        if ($existing -and $existing.LinkType -eq 'SymbolicLink') {
            if (@($existing.Target)[0] -eq $target) {
                Write-Skip "$link already linked"
                continue
            }
        }

        # Unelevated we can only copy, and a copy has no LinkType to compare.
        # Treat a byte-identical copy as already correct, so re-runs don't
        # churn the file or clobber a real .bak with an identical one.
        $identicalCopy = $false
        if ($existing -and -not $existing.LinkType -and -not $admin) {
            try {
                $a = (Get-FileHash -LiteralPath $link   -Algorithm SHA256).Hash
                $b = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
                $identicalCopy = ($a -eq $b)
            }
            catch {
                # Unreadable or locked -- fall through and replace it.
                $identicalCopy = $false
            }
        }
        if ($identicalCopy) {
            Write-Skip "$link already current (copy)"
            continue
        }

        if ($DryRun) {
            if ($admin) { Write-Change "would link $link -> $target" }
            else        { Write-Change "would copy $target -> $link" }
            continue
        }

        $parent = Split-Path -Parent $link
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }

        # New-Item -Force will not turn an existing file into a symlink, so the
        # old item has to come out first. That opens a window where the file is
        # gone and the replacement has not been made yet -- so capture enough to
        # put it back if the create fails.
        $backup        = $null
        $oldLinkTarget = $null

        if ($existing) {
            if ($existing.LinkType) {
                # Copying a symlink copies its target's content, which is wrong
                # (and impossible if it dangles). Remember where it pointed.
                $oldLinkTarget = @($existing.Target)[0]
            }
            else {
                $backup = "$link.bak"
                try {
                    Copy-Item -LiteralPath $link -Destination $backup -Force
                    Write-Warn "backed up existing file to $backup"
                }
                catch {
                    Write-Warn "could not back up $link -- skipping it to be safe"
                    continue
                }
            }
            Remove-Item -LiteralPath $link -Force -Confirm:$false
        }

        try {
            if ($admin) {
                New-Item -ItemType SymbolicLink -Path $link -Target $target -Force -ErrorAction Stop | Out-Null
                Write-Change "$link -> $target"
            }
            else {
                Copy-Item -LiteralPath $target -Destination $link -Force -ErrorAction Stop
                Write-Change "$link (copy)"
            }
        }
        catch {
            Write-Warn "FAILED: $link"
            Write-Warn "  $($_.Exception.Message)"

            if ($backup -and (Test-Path -LiteralPath $backup)) {
                Copy-Item -LiteralPath $backup -Destination $link -Force
                Write-Warn "  restored the original from $backup"
            }
            elseif ($oldLinkTarget) {
                try {
                    New-Item -ItemType SymbolicLink -Path $link -Target $oldLinkTarget -Force | Out-Null
                    Write-Warn "  restored the previous link -> $oldLinkTarget"
                }
                catch {
                    Write-Warn "  COULD NOT RESTORE. $link is now missing."
                    Write-Warn "  it previously pointed at $oldLinkTarget"
                }
            }
            $script:FailedPhases += 'Links'
        }
    }
}

#--------------------------------------------------------------------------
# Health check
#--------------------------------------------------------------------------

# Resolve a command against the CURRENT registry PATH rather than this
# process's environment. A shell started before the PATH was updated still
# carries the old copy, so Get-Command would report false failures.
function Resolve-OnFreshPath {
    param([string] $Name)

    $dirs = @()
    foreach ($scope in 'Machine', 'User') {
        $v = [Environment]::GetEnvironmentVariable('Path', $scope)
        if ($v) { $dirs += @($v.Split(';') | Where-Object { $_ }) }
    }

    $exts = @('.exe', '.cmd', '.bat', '.ps1', '')
    foreach ($d in $dirs) {
        foreach ($e in $exts) {
            $candidate = Join-Path $d ($Name + $e)
            if (Test-Path -LiteralPath $candidate -ErrorAction SilentlyContinue) {
                return $d
            }
        }
    }
    return $null
}

function Invoke-Verify {
    Write-Step 'Health check'
    $problems = @()

    # --- links ---
    foreach ($link in $Links.Keys) {
        $short = $link.Replace($env:USERPROFILE, '~')
        $i = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
        if ($null -eq $i) {
            $problems += "missing: $short"
            Write-Warn "missing            $short"
        }
        elseif ($i.LinkType -ne 'SymbolicLink') {
            Write-Warn "copy, not a link   $short  (re-run elevated)"
        }
        elseif (-not (Test-Path -LiteralPath @($i.Target)[0] -ErrorAction SilentlyContinue)) {
            $problems += "dangling: $short"
            Write-Warn "DANGLING           $short -> $(@($i.Target)[0])"
        }
        else {
            Write-Skip "link ok            $short"
        }
    }

    # --- environment variables ---
    foreach ($name in $EnvVars.Keys) {
        if ([Environment]::GetEnvironmentVariable($name, 'User') -eq $EnvVars[$name]) {
            Write-Skip "env ok             $name"
        }
        else {
            $problems += "env not set: $name"
            Write-Warn "env NOT SET        $name"
        }
    }

    # --- directories that must exist ---
    foreach ($d in $EnsureDirs) {
        if (Test-Path -LiteralPath $d) {
            Write-Skip "dir ok             $($d.Replace($env:USERPROFILE,'~'))"
        }
        else {
            $problems += "missing dir: $d"
            Write-Warn "MISSING DIR        $($d.Replace($env:USERPROFILE,'~'))"
        }
    }

    # --- dead PATH entries ---
    $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    $deadFound = $false
    foreach ($p in @($u.Split(';') | Where-Object { $_ })) {
        if (Test-Path -LiteralPath $p -ErrorAction SilentlyContinue) { continue }
        $problems += "dead PATH entry: $p"
        Write-Warn "dead PATH entry    $p"
        $deadFound = $true
    }
    if (-not $deadFound) { Write-Skip 'PATH has no dead entries' }

    # --- outdated packages ---
    # Packages in $NoAutoUpgrade are behind on purpose, so they are reported but
    # do not fail the run. Anything else still behind means an upgrade failed or
    # the phase was skipped, which is a real problem.
    $outdated = Get-OutdatedPackages
    $excluded = @($outdated | Where-Object { $NoAutoUpgrade -contains $_ })
    $unwanted = @($outdated | Where-Object { $NoAutoUpgrade -notcontains $_ })

    foreach ($id in $excluded) {
        Write-Skip "behind by design    $id  (excluded from auto-upgrade)"
    }

    if ($unwanted.Count -gt 0) {
        $problems += "outdated: $($unwanted -join ', ')"
        Write-Warn "$($unwanted.Count) package(s) still behind after upgrade:"
        $unwanted | ForEach-Object { Write-Warn "                     $_" }
        if ($Phase -notcontains 'Packages') {
            Write-Warn '                     (Packages phase was not run)'
        }
    }
    elseif ($excluded.Count -eq 0) {
        Write-Skip 'all declared packages current'
    }

    # --- commands ---
    foreach ($c in $ExpectedCommands) {
        $where = Resolve-OnFreshPath $c
        if ($where) {
            Write-Skip "command ok         $c  ($where)"
        }
        else {
            $problems += "command not found: $c"
            Write-Warn "NOT ON PATH        $c"
        }
    }

    if ($problems.Count -gt 0) {
        $script:FailedPhases += 'Verify'
    }
}

#--------------------------------------------------------------------------
# Main
#--------------------------------------------------------------------------

Write-Host "windows setup - $RepoRoot" -ForegroundColor White
if ($DryRun) { Write-Host 'DRY RUN - nothing will be changed' -ForegroundColor Yellow }

if ($Phase -contains 'Packages') { Invoke-Phase 'Packages' { Invoke-Packages; Invoke-DotnetTools } }
if ($Phase -contains 'Env')      { Invoke-Phase 'Env'      { Invoke-Env } }
# Dirs first: PATH prunes anything that does not exist, so the directories that
# should exist have to be made before that runs.
if ($Phase -contains 'Path')     { Invoke-Phase 'Path'     { Invoke-Dirs; Invoke-Path } }
if ($Phase -contains 'Links')    { Invoke-Phase 'Links'    { Invoke-Links } }

# Always verify, whatever ran. Reports the real state of the machine, so a
# problem gets named instead of sitting silently until something breaks.
Invoke-Phase 'Verify' { Invoke-Verify }

$failed = @($script:FailedPhases | Select-Object -Unique)

if ($failed.Count -gt 0) {
    Write-Host "`nFinished with problems in: $($failed -join ', ')" -ForegroundColor Yellow
    if ($DryRun) {
        Write-Host 'This was a dry run -- the health check reports the CURRENT state,' -ForegroundColor Yellow
        Write-Host 'so anything above may be what a real run would fix.' -ForegroundColor Yellow
    }
    else {
        Write-Host 'Everything else was applied. Fix the above and re-run.' -ForegroundColor Yellow
    }
    exit 1
}

Write-Host "`nAll good." -ForegroundColor White
if (-not $DryRun -and ($Phase -contains 'Env' -or $Phase -contains 'Path')) {
    Write-Host 'Open a new shell to pick up environment changes.' -ForegroundColor DarkGray
}
exit 0
