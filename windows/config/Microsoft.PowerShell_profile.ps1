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
#   prs https://github.com/owner/repo/pull/123  any repo, cloned on first use
#   prs 123                                     the repo you are standing in
#   prs -List                                   every review clone and its state
#   prs                                         help, since bare is not an error
#
# The stash / checkout / unstash dance is not a git problem, it is a problem of
# reviewing inside the tree you work in. A repo gets cloned under $PrRoot once,
# and every later review of it is a fetch and a checkout in a tree that has
# never held anything worth keeping.
#
# Nothing here is disposable in the sense of being deleted -- the clones are the
# point and they stay. It is the *contents* that are disposable, which is what
# lets the checkout below be unconditional.
function prs {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string] $Ref,
        [switch] $List,
        [switch] $Help
    )

    # Bare `prs` prints help rather than failing. Reviews come in bursts weeks
    # apart, so the thing worth being reminded of is not the syntax -- it is
    # that the review tree throws your edits away. Following drift: say only
    # what you could not have guessed.
    if ($Help -or (-not $Ref -and -not $List)) {
        $k = 'Cyan'
        Write-Host ''
        Write-Host '  prs' -ForegroundColor $k -NoNewline
        Write-Host ' -- review a pull request in a clone kept only for reviewing'
        Write-Host ''
        Write-Host '    prs <url>       ' -ForegroundColor $k -NoNewline
        Write-Host '    full PR URL, any repo'
        Write-Host '    prs <number>    ' -ForegroundColor $k -NoNewline
        Write-Host '    that PR in the repo you are standing in'
        Write-Host '    prs -List       ' -ForegroundColor $k -NoNewline
        Write-Host '    every review clone, what it is on, and where'
        Write-Host '    prs -Help       ' -ForegroundColor $k -NoNewline
        Write-Host '    this'
        Write-Host ''
        Write-Host "  Each repo clones once to $script:PrRoot\<owner>-<repo> and stays."
        Write-Host '  Later reviews of it fetch and check out in place, so the clones you'
        Write-Host '  actually work in are never touched and never need stashing.'
        Write-Host ''
        Write-Host '  The review tree is not yours.' -ForegroundColor Yellow -NoNewline
        Write-Host ' Uncommitted changes to tracked files are'
        Write-Host '  discarded on every checkout, so do not leave anything in one. Untracked'
        Write-Host '  files survive on purpose: node_modules and obj carry over, and the'
        Write-Host '  second review of a repo skips the rebuild.'
        Write-Host ''
        Write-Host '    git diff origin/<base>...HEAD' -ForegroundColor $k -NoNewline
        Write-Host '    what the author changed; three dots'
        Write-Host '                                     excludes what landed on base since'
        Write-Host '    gh pr diff <number>          ' -ForegroundColor $k -NoNewline
        Write-Host '    read one without cloning at all'
        Write-Host ''
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
        Write-Error "Could not read '$Ref' as a PR URL or number -- see prs -Help"
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
