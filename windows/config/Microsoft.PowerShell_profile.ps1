# PowerShell profile. The only shell profile in this repo -- the cmd and Git
# Bash equivalents were deleted when this machine moved to PowerShell 7.
#
# setup.ps1 links this into both profile folders:
#   <Documents>\WindowsPowerShell\   PowerShell 5.1
#   <Documents>\PowerShell\          PowerShell 7
# so either shell behaves identically.

# Browse with drift, then follow it to wherever you quit.
# drift writes the directory it exited in to %TEMP%\browser_lastdir.txt; a child
# process cannot change its parent's directory, so the cd has to happen here.
function e {
    $lastdir = Join-Path $env:TEMP 'browser_lastdir.txt'

    # Clear it first. drift only writes this on a clean exit, and never clears
    # it, so a crash or a kill would leave the previous run's directory sitting
    # there and we would jump somewhere unrelated. Deleting up front means a
    # failed run does nothing instead of doing the wrong thing.
    Remove-Item -LiteralPath $lastdir -Force -ErrorAction SilentlyContinue

    drift.exe

    if (Test-Path -LiteralPath $lastdir) {
        $cwd = (Get-Content -LiteralPath $lastdir -Raw).Trim()
        if ($cwd -and $cwd -ne $PWD.Path) {
            Set-Location -LiteralPath $cwd
        }
    }
}

function ll { Get-ChildItem -Force @args }

function fe {
    param([string] $Path = '.')
    explorer.exe $Path
}

# Load the Visual Studio developer environment into THIS session -- the
# PowerShell equivalent of VsDevCmd.bat. Only needed for command-line builds
# (cl, link, nmake). Opening a solution does not need this: devenv.exe and
# msbuild.exe are on PATH already, so `devenv foo.sln` just works.
#
# Visual Studio is located with vswhere rather than a hardcoded version path,
# so this survives upgrades and works on any edition.
function vsdev {
    $vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) {
        Write-Error 'vswhere not found -- is Visual Studio installed?'
        return
    }

    $root = & $vswhere -latest -property installationPath 2>$null | Select-Object -First 1
    if (-not $root) {
        Write-Error 'vswhere found no Visual Studio installation'
        return
    }

    $launch = Join-Path $root 'Common7\Tools\Launch-VsDevShell.ps1'
    if (-not (Test-Path $launch)) {
        Write-Error "Launch-VsDevShell.ps1 not found under $root"
        return
    }

    # -SkipAutomaticLocation keeps the current directory instead of jumping to
    # the VS install root, which is what the old vs_init.cmd restored by hand.
    & $launch -SkipAutomaticLocation
}

# --- Repo commands -----------------------------------------------------------

# One word for everything that touches repos. There is no second word.
#
# These used to be two top-level commands, `prs` and `pull`: unrelated names,
# no shared prefix, neither one tab-completing into the other. Reviews come in
# bursts weeks apart, and by the time one was wanted again both names were gone.
#
# The obvious fix -- `repo pull` and `repo pr` -- is not a fix. It leaves both
# old words in your memory and charges you a third one to reach them. So there
# are no subcommands. What you type after `repo` identifies itself:
#
#   repo             where every repo below here stands. No network.
#   repo <branch>    checkout <branch> and pull, in every repo that has it
#   repo <number>    review that PR of the repo you are standing in
#   repo <url>       review that PR, any repo
#   repo -List       every review clone and its state
#
# Digits and URLs are pull requests; anything else is a branch name. Nothing to
# recall, nothing to disambiguate, and one word total.
#
# This is a guess, and guessing was refused a few lines down -- a branch that
# does not exist is a skip with a reason, never a silent switch to another one.
# The difference is what a wrong guess costs. A branch name cannot be read as a
# PR because branch names are not bare digits, and a *typo'd* branch name is
# read as exactly what it is: a fetch and a "no such branch" skip in every repo,
# which changes nothing. The two readings also cannot reach each other's trees
# -- the PR path only ever writes under $PrRoot.
#
# What is deliberately not merged is the two implementations. They are opposite
# on purpose: the PR path checks out --force because the review tree is not
# yours, the branch path skips on tracked changes because those trees are.
# Folding them together would put a force-checkout over your own work one flag
# away. Only the front door is shared.
function repo {
    # A simple function, not [CmdletBinding()]. An advanced function rejects
    # named arguments it does not declare, so `repo -List` would fail to bind
    # here before ever reaching the implementation -- ValueFromRemainingArguments
    # only collects positional leftovers. With a simple param block the extras
    # land in $args and splat through with their switches intact.
    #
    # -Branch is the escape hatch for the one case the shape rule gets wrong: a
    # branch actually named with digits. It is declared rather than sniffed so
    # it binds properly, and it is the only thing here you will never type.
    param([string] $Arg, [string] $Branch)

    if ($Branch) { Invoke-RepoPull $Branch; return }

    # A bare flag never reaches $Arg -- it is not a declared parameter, so it
    # lands in $args instead. Checked before $Arg rather than only when $Arg is
    # empty, so `repo develop -Help` answers with help instead of trying to
    # check out develop: the implementations below carry no -Help of their own.
    if (@($args | Where-Object { $_ -match '^-?-?(h|help)$' })) { Show-RepoHelp; return }

    if (-not $Arg) {
        if (@($args | Where-Object { $_ -match '^-?list$' })) { Invoke-RepoPr -List; return }
        Invoke-RepoPull @args
        return
    }

    switch -Regex ($Arg) {
        # Help is not vocabulary -- every command has it, so it costs nothing to
        # keep. It is matched here as well as above because it reaches $Arg when
        # passed as a value (repo $x) and $args when typed as a literal flag.
        '^-?-?(h|help)$' { Show-RepoHelp;             return }
        '^#?\d+$'        { Invoke-RepoPr   $Arg @args; return }
        '^https?://'     { Invoke-RepoPr   $Arg @args; return }
        default          { Invoke-RepoPull $Arg @args; return }
    }
}

# Branch names, deduped across every repo below here. This is the only
# completion worth having now that there are no verbs to enumerate: the
# argument is a branch name nearly every time, and completing it means even
# that does not have to be remembered.
Register-ArgumentCompleter -CommandName repo -ParameterName Arg -ScriptBlock {
    param($cmd, $param, $word)
    $names = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($r in Find-Repos) {
        foreach ($n in & git -C $r for-each-ref --format='%(refname)|%(refname:short)' `
                            refs/heads refs/remotes/origin 2>$null) {
            $full, $short = $n -split '\|', 2
            # refs/remotes/origin/HEAD is a symref at the default branch, and
            # git shortens it to a bare "origin" that cannot be checked out.
            # Dropped on the full refname rather than the short one, so a branch
            # someone really did name "origin" still completes.
            if ($full -like '*/HEAD') { continue }
            $short = $short -replace '^origin/', ''
            if ($short) { [void] $names.Add($short) }
        }
    }
    $names | Sort-Object | Where-Object { $_ -like "$word*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

function Show-RepoHelp {
    $k = 'Cyan'
    Write-Host ''
    Write-Host '  repo' -ForegroundColor $k -NoNewline
    Write-Host ' -- one word for every git repo below here. There is no second word.'
    Write-Host ''
    Write-Host '    repo             ' -ForegroundColor $k -NoNewline
    Write-Host 'where they all stand. No network, changes nothing.'
    Write-Host '    repo <branch>    ' -ForegroundColor $k -NoNewline
    Write-Host 'checkout <branch> and pull, in every repo that has it'
    Write-Host '    repo <number>    ' -ForegroundColor $k -NoNewline
    Write-Host 'review that PR of the repo you are standing in'
    Write-Host '    repo <url>       ' -ForegroundColor $k -NoNewline
    Write-Host 'review that PR, any repo'
    Write-Host '    repo -List       ' -ForegroundColor $k -NoNewline
    Write-Host 'every review clone, what it is on, and where'
    Write-Host ''
    Write-Host '  Digits and URLs are pull requests, anything else is a branch. So there'
    Write-Host '  is nothing to remember past the word itself, and ' -NoNewline
    Write-Host 'repo <tab>' -ForegroundColor $k -NoNewline
    Write-Host ' completes'
    Write-Host '  branch names across every repo below here.'
    Write-Host ''
    Write-Host '  Branches. ' -ForegroundColor $k -NoNewline
    Write-Host 'Repos are found at depth 1 and 2, so this works from the folder'
    Write-Host '  holding your project folders as well as from inside one. A repo is skipped'
    Write-Host '  when it has tracked changes, is on a detached HEAD, or has no such branch.'
    Write-Host '  Untracked files block nothing.'
    Write-Host ''
    Write-Host '  Reviews. ' -ForegroundColor $k -NoNewline
    Write-Host "Each repo clones once to $script:PrRoot\<owner>-<repo> and stays,"
    Write-Host '  so the clones you actually work in are never touched and never need stashing.'
    Write-Host ''
    Write-Host '  The review tree is not yours.' -ForegroundColor Yellow -NoNewline
    Write-Host ' Tracked changes there are discarded on every'
    Write-Host '  checkout, so leave nothing in one. Untracked files survive on purpose:'
    Write-Host '  node_modules and obj carry over, so the second review skips the rebuild.'
    Write-Host ''
    Write-Host '    git diff origin/<base>...HEAD' -ForegroundColor $k -NoNewline
    Write-Host '    what the author changed; three dots'
    Write-Host '                                     exclude what landed on base since'
    Write-Host '    gh pr diff <number>          ' -ForegroundColor $k -NoNewline
    Write-Host '    read one without cloning at all'
    Write-Host ''
    Write-Host '  ' -NoNewline
    Write-Host '-Branch <name>' -ForegroundColor DarkGray -NoNewline
    Write-Host ' forces the branch reading, for a branch actually named' -ForegroundColor DarkGray
    Write-Host '  with digits -- the one case the shape rule gets wrong.' -ForegroundColor DarkGray
    Write-Host ''
}

# --- Reviewing pull requests -------------------------------------------------

# One directory holding a permanent clone of every repo ever reviewed, named
# <owner>-<repo>. Deliberately separate from the clones under source\repos, and
# deliberately duplicated: the disk is worth less than never having to think
# about which working tree a review is about to disturb.
#
# Not %TEMP% -- Storage Sense and Disk Cleanup empty that on a schedule, and
# these are meant to outlive every review that uses them.
$script:PrRoot = Join-Path $HOME '.prs'

# Check out someone else's PR, in a clone that exists only for reviewing.
#
#   repo https://github.com/owner/repo/pull/123  any repo, cloned on first use
#   repo 123                                     the repo you are standing in
#   repo -List                                   every review clone and its state
#
# Reached only through `repo`, which is why there is no help of its own here --
# there is one help, and `repo -Help` is it.
#
# The stash / checkout / unstash dance is not a git problem, it is a problem of
# reviewing inside the tree you work in. A repo gets cloned under $PrRoot once,
# and every later review of it is a fetch and a checkout in a tree that has
# never held anything worth keeping.
#
# Nothing here is disposable in the sense of being deleted -- the clones are the
# point and they stay. It is the *contents* that are disposable, which is what
# lets the checkout below be unconditional.
function Invoke-RepoPr {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string] $Ref,
        [switch] $List
    )

    if (-not $Ref -and -not $List) {
        Write-Error 'No PR given -- see repo -Help'
        return
    }

    if ($List) {
        if (-not (Test-Path -LiteralPath $script:PrRoot)) {
            Write-Host 'No review clones yet.'
            return
        }
        $rows = @(Get-ChildItem -LiteralPath $script:PrRoot -Directory | ForEach-Object {
            [pscustomobject]@{
                Repo = $_.Name
                At   = (& git -C $_.FullName log -1 --format='%h %s' 2>$null)
                Path = $_.FullName
            }
        })
        if (-not $rows) {
            Write-Host 'No review clones yet.'
            return
        }

        # Format-Table truncates the rightmost column when it runs out of room,
        # and the rightmost column here is the path -- the one thing that has to
        # stay complete enough to copy. So the subject is what flexes: give Repo
        # and Path their full width, then hand whatever is left to At.
        $width = try { $Host.UI.RawUI.WindowSize.Width } catch { 120 }
        if (-not $width -or $width -lt 40) { $width = 120 }
        $room = $width -
                (($rows.Repo | Measure-Object -Property Length -Maximum).Maximum) -
                (($rows.Path | Measure-Object -Property Length -Maximum).Maximum) - 6
        foreach ($r in $rows) {
            if (-not $r.At) { continue }
            if ($room -lt 8)            { $r.At = ''; continue }
            if ($r.At.Length -gt $room) { $r.At = $r.At.Substring(0, $room - 3) + '...' }
        }
        $rows
        return
    }

    # Resolve to owner/repo plus number. A bare number means the repo we are
    # standing in, which is the same thing gh assumes when given no --repo.
    if ($Ref -match '^https?://[^/]+/([^/]+)/([^/]+?)(?:\.git)?/pull/(\d+)') {
        $slug = "$($Matches[1])/$($Matches[2])"
        $num  = $Matches[3]
    }
    elseif ($Ref -match '^#?(\d+)$') {
        $num  = $Matches[1]
        $slug = & gh repo view --json nameWithOwner -q .nameWithOwner 2>$null
        if (-not $slug) {
            Write-Error 'Not inside a GitHub repo -- pass the full PR URL.'
            return
        }
    }
    else {
        Write-Error "Could not read '$Ref' as a PR URL or number -- see repo -Help"
        return
    }

    $meta = & gh pr view $num --repo $slug --json baseRefName,title,author 2>$null |
        ConvertFrom-Json
    if (-not $meta) {
        Write-Error "Could not read $slug#$num -- is gh authenticated for that host?"
        return
    }
    $base  = $meta.baseRefName
    $clone = Join-Path $script:PrRoot ($slug -replace '/', '-')

    if (-not (Test-Path -LiteralPath $clone)) {
        Write-Host "First review of $slug -- cloning to $clone"
        & gh repo clone $slug $clone
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Clone of $slug failed."
            return
        }
    }

    # Both refs in one round trip. The base comes along so the diff below is
    # against where base is now rather than whenever this clone last saw it.
    #
    # refs/pull/<n>/head is materialized by GitHub on the base repo even when
    # the PR comes from a fork, so fork PRs need no extra remote. head rather
    # than merge: head is what the author wrote, merge is a commit GitHub
    # synthesized and may have computed against a stale base.
    & git -C $clone fetch --quiet origin `
        "+refs/pull/$num/head:refs/remotes/origin/pr/$num" `
        "+refs/heads/${base}:refs/remotes/origin/$base"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Could not fetch $slug#$num."
        return
    }

    # --force discards local modifications to tracked files, which is what makes
    # this never fail the way switching branches in your own tree does: whatever
    # the last review left behind is not worth a prompt. It does not touch
    # untracked files, so node_modules, obj and the IDE index survive and the
    # second review of a repo does not pay for a full rebuild.
    #
    # --detach because reviewing does not commit, and because a detached HEAD
    # cannot block the next force-fetch of a ref it happens to have checked out.
    & git -C $clone checkout --quiet --force --detach "refs/remotes/origin/pr/$num"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Could not check out $slug#$num."
        return
    }

    Write-Host ''
    Write-Host "  $slug#$num  $($meta.title)"
    Write-Host "  by $($meta.author.login) into $base"
    Write-Host ''
    # Three dots, not two: it diffs from the merge base, so the review shows what
    # the author changed and not whatever landed on base in the meantime.
    Write-Host "  git diff origin/$base...HEAD"
    Write-Host ''

    Set-Location -LiteralPath $clone
    & code $clone
}

# --- Bulk repo status and update ---------------------------------------------

# Read one repo's local state. Deliberately no network: branch name and dirtiness
# both come off disk, so the bare `repo` view over 20 repos costs milliseconds.
# --untracked-files=normal stops git recursing into untracked directories, which
# is what makes this fast in a repo carrying node_modules or obj.
function Get-RepoState {
    param([string] $Path)

    $branch = & git -C $Path rev-parse --abbrev-ref HEAD 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $branch) { $branch = '?' }

    $porcelain = @(& git -C $Path status --porcelain --untracked-files=normal 2>$null)

    # Untracked and modified are counted separately on purpose. Untracked files
    # are permanent residents of half these repos (build output, node_modules)
    # and must not make a repo look dirty -- only tracked changes block a
    # checkout, so only tracked changes cause a skip.
    $untracked = @($porcelain | Where-Object { $_ -like '??*' }).Count
    $tracked   = $porcelain.Count - $untracked

    [pscustomobject]@{
        Branch    = $branch
        Detached  = ($branch -eq 'HEAD')
        Tracked   = $tracked
        Untracked = $untracked
    }
}

# Colour by what you would have to do about it, not by severity:
#   red     tracked changes -- blocks a checkout, needs you
#   yellow  untracked only  -- harmless, but worth seeing
#   magenta detached HEAD   -- not on a branch at all
#   green   clean
function Get-StateColor {
    param($State)
    if ($State.Detached)      { return 'Magenta' }
    if ($State.Tracked -gt 0) { return 'Red' }
    if ($State.Untracked -gt 0) { return 'Yellow' }
    return 'Green'
}

function Format-StateNote {
    param($State)
    if ($State.Detached) { return 'detached' }
    $bits = @()
    if ($State.Tracked -gt 0)   { $bits += "$($State.Tracked) changed" }
    if ($State.Untracked -gt 0) { $bits += "$($State.Untracked) untracked" }
    if ($bits.Count -eq 0) { return 'clean' }
    return ($bits -join ', ')
}

# Every git repo at depth 1 or 2 below the current directory. Depth 2 is what
# makes `repo` work from the folder holding folder-a\ and folder-b\; stopping
# there keeps it out of node_modules and vendored trees. A directory that is
# itself a repo is not descended into, so submodules do not show up as peers.
function Find-Repos {
    $found = @()
    foreach ($d in Get-ChildItem -Directory -ErrorAction SilentlyContinue) {
        if (Test-Path -LiteralPath (Join-Path $d.FullName '.git')) {
            $found += $d.FullName
            continue
        }
        foreach ($s in Get-ChildItem -Directory -LiteralPath $d.FullName -ErrorAction SilentlyContinue) {
            if (Test-Path -LiteralPath (Join-Path $s.FullName '.git')) {
                $found += $s.FullName
            }
        }
    }
    return $found
}

# Show every repo below here, or move them all onto a branch.
#
#   repo           status of every repo -- no network, changes nothing
#   repo develop   checkout develop and pull, in every repo that has it
#   repo main      same for any other branch name
#
# There is no fallback between branch names. Asking for develop in a repo that
# only has main is a skip with a reason, not a silent switch to something else
# -- guessing is how you end up on a branch you did not intend across 20 repos
# and cannot tell which.
#
# Reached only through `repo`, which is why there is no help of its own here --
# there is one help, and `repo -Help` is it.
function Invoke-RepoPull {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string] $Branch
    )

    $repos = Find-Repos
    if ($repos.Count -eq 0) {
        Write-Host 'No git repos found below here.' -ForegroundColor Yellow
        return
    }

    $width = 0
    foreach ($r in $repos) {
        $n = (Split-Path -Leaf $r).Length
        if ($n -gt $width) { $width = $n }
    }

    #-- status only ----------------------------------------------------------
    if (-not $Branch) {
        Write-Host ''
        foreach ($r in $repos) {
            $s = Get-RepoState $r
            Write-Host ('  {0}  ' -f (Split-Path -Leaf $r).PadRight($width)) -NoNewline
            Write-Host $s.Branch.PadRight(22) -ForegroundColor Cyan -NoNewline
            Write-Host (Format-StateNote $s) -ForegroundColor (Get-StateColor $s)
        }
        Write-Host ''
        Write-Host ("  {0} repo(s). Nothing was changed." -f $repos.Count) -ForegroundColor DarkGray

        # The footer is the whole discoverability fix, so it hangs off bare
        # `repo` -- the one form reached without thinking -- rather than off
        # -Help, which is exactly the thing nobody types when they have already
        # forgotten there was something to ask about.
        Write-Host '  repo <branch>' -ForegroundColor DarkGray -NoNewline
        Write-Host ' to move them  |  ' -ForegroundColor DarkGray -NoNewline
        Write-Host 'repo <number|url>' -ForegroundColor DarkGray -NoNewline
        Write-Host ' to review a PR  |  ' -ForegroundColor DarkGray -NoNewline
        Write-Host 'repo -Help' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    #-- checkout and pull ----------------------------------------------------
    $report = @()

    foreach ($r in $repos) {
        $name  = Split-Path -Leaf $r
        $state = Get-RepoState $r
        $was   = $state.Branch

        Write-Host ('  {0}  ' -f $name.PadRight($width)) -NoNewline

        if ($state.Tracked -gt 0) {
            Write-Host ("skipped -- {0} tracked change(s)" -f $state.Tracked) -ForegroundColor Red
            $report += [pscustomobject]@{ Repo=$name; Was=$was; Now=$was; Result='skipped: dirty' }
            continue
        }

        if ($state.Detached) {
            Write-Host 'skipped -- detached HEAD' -ForegroundColor Magenta
            $report += [pscustomobject]@{ Repo=$name; Was='(detached)'; Now='(detached)'; Result='skipped: detached' }
            continue
        }

        # Fetch before deciding whether the branch exists. A repo cloned when it
        # only had master has no refs/remotes/origin/develop until something
        # fetches, so checking first would report "no such branch" for a branch
        # that is plainly on the server. The network cost is already being paid
        # by the pull below.
        & git -C $r fetch --quiet origin 2>$null

        & git -C $r rev-parse --verify --quiet ("refs/heads/" + $Branch) > $null 2>&1
        $hasLocal = ($LASTEXITCODE -eq 0)
        & git -C $r rev-parse --verify --quiet ("refs/remotes/origin/" + $Branch) > $null 2>&1
        $hasRemote = ($LASTEXITCODE -eq 0)

        if (-not $hasLocal -and -not $hasRemote) {
            Write-Host ("skipped -- no '{0}' branch" -f $Branch) -ForegroundColor DarkGray
            $report += [pscustomobject]@{ Repo=$name; Was=$was; Now=$was; Result="skipped: no $Branch" }
            continue
        }

        if ($was -ne $Branch) {
            & git -C $r checkout --quiet $Branch 2>$null
            if ($LASTEXITCODE -ne 0) {
                Write-Host ("FAILED -- could not check out {0}" -f $Branch) -ForegroundColor Red
                $report += [pscustomobject]@{ Repo=$name; Was=$was; Now=$was; Result='failed: checkout' }
                continue
            }
        }

        $before = & git -C $r rev-parse --short HEAD 2>$null
        $out = & git -C $r pull 2>&1
        $pullOk = ($LASTEXITCODE -eq 0)
        $after = & git -C $r rev-parse --short HEAD 2>$null
        $now = & git -C $r rev-parse --abbrev-ref HEAD 2>$null

        if (-not $pullOk) {
            # The common cause is a diverged branch: local commits on $Branch
            # that were never pushed. git refuses rather than merging, which is
            # the right outcome -- that repo needs a human, not a bulk tool.
            Write-Host 'FAILED -- pull refused (diverged?)' -ForegroundColor Red
            $report += [pscustomobject]@{ Repo=$name; Was=$was; Now=$now; Result='failed: pull' }
        }
        elseif ($before -eq $after) {
            Write-Host ("{0} -> {1}  already current" -f $was, $now) -ForegroundColor DarkGray
            $report += [pscustomobject]@{ Repo=$name; Was=$was; Now=$now; Result='already current' }
        }
        else {
            Write-Host ("{0} -> {1}  updated {2}..{3}" -f $was, $now, $before, $after) -ForegroundColor Green
            $report += [pscustomobject]@{ Repo=$name; Was=$was; Now=$now; Result="updated $before..$after" }
        }
    }

    Write-Host ''
    Write-Host '  ---- report ----' -ForegroundColor Cyan
    $report | Format-Table -AutoSize Repo, Was, Now, Result

    $updated = @($report | Where-Object { $_.Result -like 'updated*' }).Count
    $skipped = @($report | Where-Object { $_.Result -like 'skipped*' }).Count
    $failed  = @($report | Where-Object { $_.Result -like 'failed*' }).Count
    Write-Host ("  {0} updated, {1} skipped, {2} failed, {3} total" -f `
        $updated, $skipped, $failed, $report.Count) -ForegroundColor DarkGray
    Write-Host ''
}
