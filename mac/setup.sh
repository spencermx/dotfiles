#!/usr/bin/env bash
#
# Provisions a macOS machine from this repo.
#
# Installs applications, wires PATH, links dotfiles out of this repo into their
# live locations, applies macOS settings, and builds out the editor toolchain.
#
# Every phase is idempotent, so re-running only changes what is actually out of
# date. Safe to run repeatedly as the repo evolves.
#
# Phases are isolated: if one fails the others still run, and the script exits
# non-zero listing what failed.
#
#   ./setup.sh --dry-run          show what would change, touch nothing
#   ./setup.sh                    do it
#   ./setup.sh --phase links      run one phase (repeatable, or comma-separated)
#   ./setup.sh --fix-paths        also remove the broken /etc/paths.d entries
#                                 (needs sudo; see the paths phase)
#
# NOTE: keep this file bash 3.2 compatible. macOS ships bash 3.2.57 and always
# has -- there is no associative array (`declare -A`), no `mapfile`, and an
# empty array expanded under `set -u` is an error rather than nothing. Pairs
# are therefore encoded as "left|right" strings and split by hand. Homebrew's
# bash 5 is not a solution: a fresh machine runs this script before brew
# exists.
#
# ZONE RULE: mac/ is self-contained. Every file this script links is under
# mac/config/, and nothing here reads or writes any sibling OS directory.

set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../dotfiles/mac

# Configs byte-identical across zones live in common/ instead of being kept in
# sync by hand. This is the only path that reaches outside the zone, so this
# zone no longer provisions a machine alone -- it needs common/ beside it.
SHARED_ROOT="$(dirname "$REPO_ROOT")/common"                # .../dotfiles/common

#---------------------------------------------------------------------------
# Configuration
#---------------------------------------------------------------------------

# Homebrew formulae. Curated -- what you would deliberately install on a fresh
# machine, not a dump of `brew leaves`.
FORMULAE=(
    # shell and cli
    gh
    lsd
    htop
    tmux
    tree
    fzf
    zoxide
    ripgrep
    fd
    jq

    # editor toolchain
    #
    # cmake and luarocks are here for Mason, which builds some of its packages
    # from source. go provides gofumpt. node is deliberately absent -- it comes
    # from nvm in the tools phase, which is what .zshrc sources.
    neovim
    luarocks
    cmake
    go

    # rustup: Mason has rust-analyzer and codelldb installed and the nvim config
    # ships rust_prettifier_for_lldb.py, but this machine had no cargo and no
    # rustc. The editor was configured for a toolchain that was never there.
    rustup

    # yazi and its previewers. Each of these backs a specific file type in the
    # preview pane, which is why the list is this long for one file manager.
    yazi
    ffmpeg-full
    sevenzip
    poppler
    resvg
    imagemagick-full

    # recovery
    ddrescue
    testdisk

    # media
    yt-dlp
)

# Installed on this machine, deliberately NOT provisioned:
#
#   ffmpeg        superseded by ffmpeg-full, which is declared above. Both are
#                 currently installed; only one is needed.
#   mingw-w64     one-off cross-compiler experiment
#   whisky        one-off, and it wraps wine-stable
#   wine-stable   one-off
#
# Nothing removes them. They are recorded here so a future reader knows they
# were considered and skipped rather than forgotten.

CASKS=(
    # window manager and keys. These two are ONE unit -- see
    # notes/karabiner-aerospace.md. Do not install one without the other.
    aerospace
    karabiner-elements

    # fonts. font-symbols-only backs the glyphs yazi and the nvim statusline
    # draw; jetbrains-mono-nerd-font is the terminal font.
    font-jetbrains-mono-nerd-font
    font-symbols-only-nerd-font

    # runtimes
    dotnet-sdk

    # apps
    1password
    google-chrome
    docker-desktop
    visual-studio-code
    claude
    chatgpt
    teamviewer
    mullvad-browser
)

# Declared packages that are installed but never auto-upgraded.
#
# Chrome and 1Password ship their own updaters -- Chrome's keystone agents are
# in ~/Library/LaunchAgents right now. Letting brew upgrade them too means two
# mechanisms fighting over the same app bundle. They are still reported as
# outdated by the health check, just not acted on.
NO_AUTO_UPGRADE=(
    google-chrome
    1password
)

# Directories that must exist for a PATH entry or a link target to mean
# anything. Created before anything checks for them.
ENSURE_DIRS=(
    "$HOME/.local/bin"
    "$HOME/.dotnet/tools"
    "$HOME/.config"
    "$HOME/.config/karabiner"
    "$HOME/.config/git"
    "$HOME/.claude"
)

# "link location|file in this repo"
#
# Targets are under mac/config/, except those marked SHARED_ROOT, which are
# under common/config/ because every zone uses the same file.
LINKS=(
    "$HOME/.zprofile|$REPO_ROOT/config/.zprofile"
    "$HOME/.zshrc|$REPO_ROOT/config/.zshrc"
    "$HOME/.gitconfig|$REPO_ROOT/config/.gitconfig"
    "$HOME/.gitconfig.common|$SHARED_ROOT/config/.gitconfig"
    "$HOME/.tmux.conf|$SHARED_ROOT/config/.tmux.conf"
    "$HOME/.aerospace.toml|$REPO_ROOT/config/.aerospace.toml"
    "$HOME/.config/karabiner/karabiner.json|$REPO_ROOT/config/karabiner.json"
    "$HOME/.config/git/ignore|$SHARED_ROOT/config/git/ignore"

    # The file is shared; only the location VS Code reads it from is per-OS.
    "$HOME/Library/Application Support/Code/User/settings.json|$SHARED_ROOT/config/vscode/settings.json"

    # Claude Code's per-directory memory does not carry between sibling working
    # directories, so instructions that must always apply cannot live there.
    # This file loads in every session whatever the cwd, which is the only
    # place a rule like "no AI attribution in commits" actually holds. The mac
    # had neither of these files -- that rule was enforced on Windows only.
    "$HOME/.claude/CLAUDE.md|$SHARED_ROOT/config/claude/CLAUDE.md"
    "$HOME/.claude/settings.json|$SHARED_ROOT/config/claude/settings.json"

    "$HOME/.config/nvim|$SHARED_ROOT/config/nvim"
    "$HOME/.vimrc|$SHARED_ROOT/config/.vimrc"
)

# Links that used to exist and should not any more. Removed only if they are
# symlinks pointing where this table says -- a real file of the same name, or a
# link somewhere else, is left alone.
#
# Empty because the one entry it held has been applied: ~/.config/alacritty
# pointed at an alacritty config in the old repo, and alacritty is not
# installed on this machine. Add an entry here when a link stops being wanted,
# so it gets cleaned up on every machine rather than just the one you noticed
# it on.
STALE_LINKS=()

# Per-app menu shortcut overrides: "menu item title|key".
# @ = cmd, ~ = option, ^ = ctrl, $ = shift.
#
# These are the "Keyboard Shortcuts -> App Shortcuts" entries from System
# Settings. mac/README.md documented two of the three; "New Window" was set on
# the machine and written down nowhere.
CHROME_SHORTCUTS=(
    "New Window|~c"
    "Select Next Tab|@]"
    "Select Previous Tab|@["
)

# Mason packages, installed headless. This list matched the machine exactly
# when it was transcribed -- it was just being applied by hand through the
# Mason UI, one checkbox at a time.
MASON_PACKAGES=(
    # lsp
    bash-language-server
    lua-language-server
    omnisharp
    pyright
    rust-analyzer
    typescript-language-server

    # dap
    codelldb
    debugpy

    # formatters
    shfmt
    htmlbeautifier
    prettier
    gofumpt
    csharpier
    luaformatter
)

# tmux plugins, cloned into ~/.tmux/plugins as "name|url". tpm itself has to be
# cloned before it can install anything, so it is listed like any other plugin.
TMUX_PLUGINS=(
    "tpm|https://github.com/tmux-plugins/tpm"
    "tmux-resurrect|https://github.com/tmux-plugins/tmux-resurrect"
)

# Commands that must resolve once everything is applied.
EXPECTED_COMMANDS=(brew git gh nvim tmux yazi lsd fzf zoxide rg fd jq node aerospace go cargo dotnet)

# Broken PATH sources this script knows about. Reported always, removed only
# with --fix-paths, because both need sudo and both are outside the mac zone.
BROKEN_PATH_FILES=(
    # Contains the literal text "~/.dotnet/tools". path_helper does not expand
    # ~, so this has always produced a dead relative entry. config/.zprofile
    # adds the real path.
    "/etc/paths.d/dotnet-cli-tools"

    # Puts /opt/homebrew/bin on PATH, but path_helper appends /etc/paths.d
    # AFTER /usr/bin -- so brew's jq, python3, pip3 and openssl all lose to the
    # macOS copies. config/.zprofile runs `brew shellenv`, which prepends.
    "/etc/paths.d/homebrew"
)

#---------------------------------------------------------------------------
# Helpers
#---------------------------------------------------------------------------

if [ -t 1 ]; then
    C_STEP=$'\033[36m'; C_ADD=$'\033[32m'; C_SKIP=$'\033[90m'
    C_WARN=$'\033[33m'; C_OFF=$'\033[0m'
else
    C_STEP=''; C_ADD=''; C_SKIP=''; C_WARN=''; C_OFF=''
fi

step()   { printf '\n%s== %s%s\n' "$C_STEP" "$*" "$C_OFF"; }
change() { printf '%s   + %s%s\n' "$C_ADD"  "$*" "$C_OFF"; }
skip()   { printf '%s   . %s%s\n' "$C_SKIP" "$*" "$C_OFF"; }
warn()   { printf '%s   ! %s%s\n' "$C_WARN" "$*" "$C_OFF"; }

DRY_RUN=0
FIX_PATHS=0
PHASES="packages paths links defaults tools"
FAILED_PHASES=""
PROBLEM_COUNT=0

# Phase names are tracked as a space-delimited string rather than an array so
# membership is a substring test -- bash 3.2 has no associative arrays and this
# is checked often enough that a loop would be noise.
fail_phase() {
    case " $FAILED_PHASES " in
        *" $1 "*) ;;
        *) FAILED_PHASES="$FAILED_PHASES $1" ;;
    esac
}

wants_phase() {
    case " $PHASES " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

# Split "left|right" into $PAIR_L and $PAIR_R. Stands in for the associative
# arrays bash 3.2 does not have.
PAIR_L=""; PAIR_R=""
split_pair() {
    PAIR_L="${1%%|*}"
    PAIR_R="${1#*|}"
}

# Shorten $HOME to ~ for display. Written as a case rather than ${x/#.../\~}
# because the escaped tilde in a bash 3.2 pattern substitution comes out
# literally, as "\~".
tilde() {
    case "$1" in
        "$HOME") printf '~' ;;
        "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
        *) printf '%s' "$1" ;;
    esac
}

has() { command -v "$1" >/dev/null 2>&1; }

in_list() {
    local needle=$1; shift
    local x
    for x in "$@"; do [ "$x" = "$needle" ] && return 0; done
    return 1
}

problem() { PROBLEM_COUNT=$((PROBLEM_COUNT + 1)); }

#---------------------------------------------------------------------------
# Argument parsing
#---------------------------------------------------------------------------

parse_args() {
    local phases_set=0 p
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run|-n) DRY_RUN=1 ;;
            --fix-paths)  FIX_PATHS=1 ;;
            --phase|-p)
                shift
                [ $# -gt 0 ] || { echo "--phase needs a value" >&2; exit 2; }
                if [ "$phases_set" -eq 0 ]; then PHASES=""; phases_set=1; fi
                PHASES="$PHASES $(printf '%s' "$1" | tr ',' ' ')"
                ;;
            --help|-h)
                sed -n '2,29p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,2\} \{0,1\}//'
                exit 0
                ;;
            *) echo "unknown argument: $1" >&2; exit 2 ;;
        esac
        shift
    done

    for p in $PHASES; do
        case "$p" in
            packages|paths|links|defaults|tools) ;;
            *) echo "unknown phase: $p (packages paths links defaults tools)" >&2; exit 2 ;;
        esac
    done
}

#---------------------------------------------------------------------------
# Phase: packages
#---------------------------------------------------------------------------

ensure_homebrew() {
    has brew && return 0

    # A fresh machine reaches here with no brew at all. The installer is
    # interactive (it prompts for sudo), which is why this is not silent.
    if [ "$DRY_RUN" -eq 1 ]; then
        change "would install Homebrew"
        return 1
    fi

    change "installing Homebrew"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
        warn "Homebrew install failed"
        return 1
    }

    local p
    for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$p" ]; then eval "$("$p" shellenv)"; break; fi
    done

    has brew
}

phase_packages() {
    step 'Packages'

    if ! ensure_homebrew; then
        warn 'Homebrew unavailable -- skipping every package.'
        fail_phase packages
        return
    fi

    # One `brew list` up front. Asking brew about each package individually
    # costs a Ruby startup per query and turns this phase into minutes.
    local installed_f installed_c f c
    installed_f=" $(brew list --formula 2>/dev/null | tr '\n' ' ') "
    installed_c=" $(brew list --cask    2>/dev/null | tr '\n' ' ') "

    for f in "${FORMULAE[@]}"; do
        case "$installed_f" in
            *" $f "*) skip "$f already installed"; continue ;;
        esac
        if [ "$DRY_RUN" -eq 1 ]; then change "would install $f"; continue; fi
        change "installing $f"
        brew install --formula "$f" || warn "$f failed -- continuing"
    done

    for c in "${CASKS[@]}"; do
        case "$installed_c" in
            *" $c "*) skip "$c already installed"; continue ;;
        esac
        if [ "$DRY_RUN" -eq 1 ]; then change "would install cask $c"; continue; fi

        # --adopt matters on this machine specifically: 1Password, Chrome,
        # Docker, VS Code, Claude, ChatGPT, TeamViewer and Mullvad were all
        # installed by hand from downloads. Without it brew refuses to install
        # over an app bundle it does not own; with it, brew takes ownership of
        # what is already there instead of reinstalling.
        change "installing cask $c"
        brew install --cask --adopt "$c" || warn "$c failed -- continuing"
    done

    phase_upgrades
}

# Declared packages that brew reports an upgrade for, one per line.
outdated_declared() {
    local out_f out_c x
    out_f=" $(brew outdated --formula --quiet 2>/dev/null | tr '\n' ' ') "
    out_c=" $(brew outdated --cask --quiet --greedy 2>/dev/null | tr '\n' ' ') "

    for x in "${FORMULAE[@]}"; do
        case "$out_f" in *" $x "*) echo "$x" ;; esac
    done
    for x in "${CASKS[@]}"; do
        case "$out_c" in *" $x "*) echo "$x" ;; esac
    done
}

# Every run brings declared packages up to date. Installing what is missing is
# only half the job -- a machine pinned to whatever version happened to be
# current on provisioning day is not "set up". This machine had 103 outdated
# formulae when this script was written, because nothing ever upgraded them.
phase_upgrades() {
    step 'Upgrades'

    local outdated x found=0
    outdated="$(outdated_declared)"

    if [ -z "$outdated" ]; then
        skip 'everything declared is current'
        return
    fi

    for x in $outdated; do
        found=1
        if in_list "$x" "${NO_AUTO_UPGRADE[@]}"; then
            skip "$x is behind, but excluded from auto-upgrade"
            skip "  it ships its own updater; upgrade deliberately if you mean to"
            continue
        fi
        if [ "$DRY_RUN" -eq 1 ]; then change "would upgrade $x"; continue; fi
        change "upgrading $x"
        brew upgrade "$x" || warn "$x upgrade failed -- continuing"
    done

    [ "$found" -eq 0 ] && skip 'everything declared is current'
    return 0
}

#---------------------------------------------------------------------------
# Phase: paths
#---------------------------------------------------------------------------

phase_dirs() {
    step 'Directories'

    local d
    for d in "${ENSURE_DIRS[@]}"; do
        if [ -d "$d" ]; then skip "$(tilde "$d") exists"; continue; fi
        if [ "$DRY_RUN" -eq 1 ]; then change "would create $(tilde "$d")"; continue; fi
        mkdir -p "$d" && change "created $(tilde "$d")"
    done
}

phase_paths() {
    phase_dirs
    step 'PATH'

    # The .zprofile that fixes all of this is installed by the links phase --
    # this phase only reports on, and optionally removes, the broken sources it
    # supersedes. Both live in /etc, outside the mac zone, and need sudo.
    local f found=0
    for f in "${BROKEN_PATH_FILES[@]}"; do
        if [ ! -e "$f" ]; then skip "$f already gone"; continue; fi
        found=1

        if [ "$FIX_PATHS" -eq 0 ]; then
            warn "$f still present"
            case "$f" in
                */dotnet-cli-tools) warn '  contains a literal ~ that path_helper never expands' ;;
                */homebrew)         warn '  puts brew AFTER /usr/bin; .zprofile prepends instead' ;;
            esac
            continue
        fi

        if [ "$DRY_RUN" -eq 1 ]; then change "would remove $f (sudo)"; continue; fi
        change "removing $f (sudo)"
        sudo rm -f "$f" || { warn "could not remove $f"; fail_phase paths; }
    done

    if [ "$found" -eq 1 ] && [ "$FIX_PATHS" -eq 0 ]; then
        warn 'run with --fix-paths to remove them (needs sudo, and a new login shell)'
    fi

    # A literal ~ anywhere in PATH is always a bug -- nothing expands it at
    # lookup time, so it silently resolves relative to the cwd.
    case ":$PATH:" in
        *":~"*) warn 'current PATH contains a literal ~ entry (new shells will not, once fixed)' ;;
    esac
}

#---------------------------------------------------------------------------
# Phase: links
#---------------------------------------------------------------------------

link_one() {
    local link=$1 target=$2 short
    short="$(tilde "$link")"

    if [ ! -e "$target" ]; then
        warn "target missing, skipping: $(tilde "$target")"
        fail_phase links
        return
    fi

    if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then
        skip "$short already linked"
        return
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        if [ -e "$link" ] || [ -L "$link" ]; then
            change "would replace $short -> $(tilde "$target")"
        else
            change "would link $short -> $(tilde "$target")"
        fi
        return
    fi

    mkdir -p "$(dirname "$link")"

    # A real file gets backed up before it is replaced. A symlink does not --
    # copying one copies its target's content, which is wrong, and pointless
    # when the thing it pointed at is still on disk.
    if [ -e "$link" ] && [ ! -L "$link" ]; then
        if cp -R "$link" "$link.bak"; then
            warn "backed up existing file to $short.bak"
        else
            warn "could not back up $short -- skipping it to be safe"
            fail_phase links
            return
        fi
    fi

    rm -rf "$link"
    if ln -s "$target" "$link"; then
        change "$short -> $(tilde "$target")"
    else
        warn "FAILED: $short"
        if [ -e "$link.bak" ]; then
            cp -R "$link.bak" "$link" && warn "  restored from $short.bak"
        fi
        fail_phase links
    fi
}

phase_links() {
    step 'Links'

    local entry
    for entry in "${LINKS[@]}"; do
        split_pair "$entry"
        link_one "$PAIR_L" "$PAIR_R"
    done

    # Stale links from an earlier layout.
    for entry in "${STALE_LINKS[@]}"; do
        split_pair "$entry"
        [ -L "$PAIR_L" ] || continue
        [ "$(readlink "$PAIR_L")" = "$PAIR_R" ] || continue
        if [ "$DRY_RUN" -eq 1 ]; then
            change "would remove stale link $(tilde "$PAIR_L")"
            continue
        fi
        rm -f "$PAIR_L" && change "removed stale link $(tilde "$PAIR_L")"
    done
}

#---------------------------------------------------------------------------
# Phase: defaults
#---------------------------------------------------------------------------

# Merge one app-menu shortcut into a domain's NSUserKeyEquivalents dict.
# -dict-add replaces the single key and leaves the rest of the dict alone, so
# shortcuts set by hand and never written down here survive.
set_menu_shortcut() {
    local domain=$1 item=$2 key=$3 current

    current="$(defaults read "$domain" NSUserKeyEquivalents 2>/dev/null |
               sed -n "s/^ *\"\{0,1\}${item}\"\{0,1\} = \"\{0,1\}\([^\";]*\)\"\{0,1\};/\1/p" |
               head -1)"

    if [ "$current" = "$key" ]; then
        skip "$domain: $item = $key"
        return
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        change "would set $domain: $item = $key"
        return
    fi
    defaults write "$domain" NSUserKeyEquivalents -dict-add "$item" "$key" &&
        change "$domain: $item = $key"
}

phase_defaults() {
    step 'macOS defaults'

    local entry
    for entry in "${CHROME_SHORTCUTS[@]}"; do
        split_pair "$entry"
        set_menu_shortcut com.google.Chrome "$PAIR_L" "$PAIR_R"
    done

    phase_terminal_profile
}

# Terminal.app's "Clear Dark" profile -- the full ANSI palette plus the Nerd
# Font. It lived only in com.apple.Terminal and nowhere in the repo; the
# README's entire coverage of it was "In terminal change font to nerdfont".
#
# Re-export after changing it in the UI:
#   /usr/libexec/PlistBuddy -x -c "Print :'Window Settings':'Clear Dark'" \
#       ~/Library/Preferences/com.apple.Terminal.plist > defaults/terminal-clear-dark.plist
phase_terminal_profile() {
    local profile='Clear Dark'
    local src="$REPO_ROOT/defaults/terminal-clear-dark.plist"
    local plist="$HOME/Library/Preferences/com.apple.Terminal.plist"
    local cur

    if [ ! -f "$src" ]; then skip 'no exported Terminal profile'; return; fi

    if /usr/libexec/PlistBuddy -c "Print :'Window Settings':'$profile'" "$plist" >/dev/null 2>&1; then
        skip "Terminal profile '$profile' present"
    elif [ "$DRY_RUN" -eq 1 ]; then
        change "would import Terminal profile '$profile'"
        return
    else
        /usr/libexec/PlistBuddy -c "Add :'Window Settings':'$profile' dict" "$plist" >/dev/null 2>&1
        if /usr/libexec/PlistBuddy -c "Merge '$src' :'Window Settings':'$profile'" "$plist" >/dev/null 2>&1; then
            change "imported Terminal profile '$profile'"
            # Terminal rewrites this plist when it quits, so an import done
            # while it is running gets overwritten. Say so rather than let the
            # profile quietly vanish.
            warn '  quit and reopen Terminal for this to stick'
        else
            warn "could not import Terminal profile '$profile'"
            fail_phase defaults
            return
        fi
    fi

    cur="$(defaults read com.apple.Terminal 'Default Window Settings' 2>/dev/null)"
    if [ "$cur" = "$profile" ]; then
        skip "Terminal default profile is '$profile'"
    elif [ "$DRY_RUN" -eq 1 ]; then
        change "would set Terminal default profile to '$profile'"
    else
        defaults write com.apple.Terminal 'Default Window Settings' -string "$profile"
        defaults write com.apple.Terminal 'Startup Window Settings'  -string "$profile"
        change "Terminal default profile = '$profile'"
    fi
}

#---------------------------------------------------------------------------
# Phase: tools
#---------------------------------------------------------------------------

phase_tools() {
    step 'Node'

    local nvm_dir="$HOME/.nvm"
    if [ ! -s "$nvm_dir/nvm.sh" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
            change 'would install nvm'
        else
            change 'installing nvm'
            curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash ||
                { warn 'nvm install failed'; fail_phase tools; }
        fi
    else
        skip 'nvm present'
    fi

    if [ -s "$nvm_dir/nvm.sh" ]; then
        # shellcheck disable=SC1091
        export NVM_DIR="$nvm_dir"; . "$nvm_dir/nvm.sh"
        if has node; then
            skip "node $(node --version) present"
        elif [ "$DRY_RUN" -eq 1 ]; then
            change 'would install node'
        else
            change 'installing node'
            nvm install node || { warn 'node install failed'; fail_phase tools; }
        fi
    fi

    step 'Neovim'

    # lazy.nvim bootstraps itself into the start pack, where nvim loads it
    # before any plugin spec is read.
    local lazy="$HOME/.local/share/nvim/site/pack/lazy/start/lazy.nvim"
    if [ -d "$lazy" ]; then
        skip 'lazy.nvim present'
    elif [ "$DRY_RUN" -eq 1 ]; then
        change 'would clone lazy.nvim'
    else
        change 'cloning lazy.nvim'
        git clone --filter=blob:none https://github.com/folke/lazy.nvim "$lazy" ||
            { warn 'lazy.nvim clone failed'; fail_phase tools; }
    fi

    local missing="" count=0 p
    if ! has nvim; then
        warn 'nvim not installed -- skipping plugin and LSP setup'
        fail_phase tools
    elif [ "$DRY_RUN" -eq 1 ]; then
        change 'would run Lazy! sync'
        change "would ensure ${#MASON_PACKAGES[@]} Mason packages"
    else
        change 'syncing plugins'
        nvim --headless '+Lazy! sync' +qa 2>/dev/null || warn 'Lazy sync reported errors -- continuing'

        # Everything below was a checkbox in the Mason UI. MasonInstall is a
        # no-op for packages already present, so this is safe to re-run.
        for p in "${MASON_PACKAGES[@]}"; do
            if [ ! -d "$HOME/.local/share/nvim/mason/packages/$p" ]; then
                missing="$missing $p"
                count=$((count + 1))
            fi
        done

        if [ "$count" -eq 0 ]; then
            skip "all ${#MASON_PACKAGES[@]} Mason packages present"
        else
            change "installing $count Mason package(s):$missing"
            nvim --headless "+MasonInstall$missing" +qa 2>/dev/null ||
                warn 'MasonInstall reported errors -- check :Mason in nvim'
        fi
    fi

    step 'tmux plugins'

    local entry dest
    for entry in "${TMUX_PLUGINS[@]}"; do
        split_pair "$entry"
        dest="$HOME/.tmux/plugins/$PAIR_L"
        if [ -d "$dest" ]; then skip "$PAIR_L present"; continue; fi
        if [ "$DRY_RUN" -eq 1 ]; then change "would clone $PAIR_L"; continue; fi
        change "cloning $PAIR_L"
        git clone "$PAIR_R" "$dest" || warn "$PAIR_L clone failed"
    done
}

#---------------------------------------------------------------------------
# Health check
#---------------------------------------------------------------------------

verify() {
    step 'Health check'

    local entry link target short d f
    for entry in "${LINKS[@]}"; do
        split_pair "$entry"
        link="$PAIR_L"; target="$PAIR_R"
        short="$(tilde "$link")"
        if [ -L "$link" ]; then
            if [ ! -e "$link" ]; then
                problem; warn "DANGLING           $short -> $(readlink "$link")"
            elif [ "$(readlink "$link")" != "$target" ]; then
                problem; warn "WRONG TARGET       $short -> $(readlink "$link")"
            else
                skip "link ok            $short"
            fi
        elif [ -e "$link" ]; then
            problem; warn "NOT A LINK         $short"
        else
            problem; warn "missing            $short"
        fi
    done

    for d in "${ENSURE_DIRS[@]}"; do
        if [ -d "$d" ]; then skip "dir ok             $(tilde "$d")"
        else problem; warn "MISSING DIR        $(tilde "$d")"; fi
    done

    # PATH is checked against a FRESH login shell, not this process -- a shell
    # started before .zprofile landed still carries the old copy and would
    # report failures that a new terminal would not have.
    local fresh_path prefix brew_pos usr_pos i p
    fresh_path="$(zsh -lc 'printf %s "$PATH"' 2>/dev/null)"
    if [ -n "$fresh_path" ]; then
        case ":$fresh_path:" in
            *":~"*) problem; warn 'BAD PATH ENTRY     a literal ~ survives in a new login shell' ;;
            *)      skip 'PATH ok            no literal ~ entries' ;;
        esac

        # Homebrew must come before /usr/bin, or every formula that shadows a
        # system binary is dead weight -- brew's jq lost to /usr/bin/jq here.
        prefix="${HOMEBREW_PREFIX:-/opt/homebrew}"
        brew_pos=-1; usr_pos=-1; i=0
        for p in $(printf '%s' "$fresh_path" | tr ':' ' '); do
            if [ "$p" = "$prefix/bin" ] && [ "$brew_pos" -lt 0 ]; then brew_pos=$i; fi
            if [ "$p" = "/usr/bin" ]    && [ "$usr_pos"  -lt 0 ]; then usr_pos=$i;  fi
            i=$((i + 1))
        done
        if [ "$brew_pos" -lt 0 ]; then
            problem; warn "NOT ON PATH        $prefix/bin"
        elif [ "$usr_pos" -ge 0 ] && [ "$brew_pos" -gt "$usr_pos" ]; then
            problem
            warn "PATH ORDER         $prefix/bin is after /usr/bin -- brew formulae are shadowed"
        else
            skip 'PATH order ok      brew ahead of /usr/bin'
        fi
    fi

    for f in "${BROKEN_PATH_FILES[@]}"; do
        [ -e "$f" ] && warn "still present      $f  (--fix-paths removes it)"
    done

    if has brew; then
        local installed_f installed_c x missing="" mcount=0 behind="" bcount=0
        installed_f=" $(brew list --formula 2>/dev/null | tr '\n' ' ') "
        installed_c=" $(brew list --cask    2>/dev/null | tr '\n' ' ') "

        for x in "${FORMULAE[@]}"; do
            case "$installed_f" in
                *" $x "*) ;;
                *) missing="$missing $x"; mcount=$((mcount + 1)) ;;
            esac
        done
        for x in "${CASKS[@]}"; do
            case "$installed_c" in
                *" $x "*) ;;
                *) missing="$missing $x"; mcount=$((mcount + 1)) ;;
            esac
        done

        if [ "$mcount" -gt 0 ]; then
            problem; warn "$mcount declared package(s) missing:$missing"
        else
            skip 'all declared packages installed'
        fi

        for x in $(outdated_declared); do
            if in_list "$x" "${NO_AUTO_UPGRADE[@]}"; then
                skip "behind by design   $x  (ships its own updater)"
            else
                behind="$behind $x"; bcount=$((bcount + 1))
            fi
        done
        if [ "$bcount" -gt 0 ]; then
            problem; warn "$bcount package(s) still behind:$behind"
            wants_phase packages || warn '                     (packages phase was not run)'
        fi
    fi

    # Resolved against a fresh login shell for the same reason as PATH above.
    local c where
    for c in "${EXPECTED_COMMANDS[@]}"; do
        where="$(zsh -lc "command -v $c" 2>/dev/null)"
        if [ -n "$where" ]; then skip "command ok         $c  ($where)"
        else problem; warn "NOT ON PATH        $c"; fi
    done

    [ "$PROBLEM_COUNT" -gt 0 ] && fail_phase verify
    return 0
}

#---------------------------------------------------------------------------
# Main
#---------------------------------------------------------------------------

main() {
    parse_args "$@"

    if [ "$(uname -s)" != "Darwin" ]; then
        echo "this is the mac setup; uname says $(uname -s). Refusing to run." >&2
        exit 2
    fi

    printf '%smac setup - %s%s\n' "$C_STEP" "$REPO_ROOT" "$C_OFF"
    [ "$DRY_RUN" -eq 1 ] && printf '%sDRY RUN - nothing will be changed%s\n' "$C_WARN" "$C_OFF"

    wants_phase packages && phase_packages
    wants_phase paths    && phase_paths
    wants_phase links    && phase_links
    wants_phase defaults && phase_defaults
    wants_phase tools    && phase_tools

    # Always verify, whatever ran. Reports the real state of the machine, so a
    # problem gets named instead of sitting silently until something breaks.
    verify

    if [ -n "$FAILED_PHASES" ]; then
        printf '\n%sFinished with problems in:%s%s\n' "$C_WARN" "$FAILED_PHASES" "$C_OFF"
        if [ "$DRY_RUN" -eq 1 ]; then
            printf '%sThis was a dry run -- the health check reports the CURRENT state,%s\n' "$C_WARN" "$C_OFF"
            printf '%sso anything above may be what a real run would fix.%s\n' "$C_WARN" "$C_OFF"
        else
            printf '%sEverything else was applied. Fix the above and re-run.%s\n' "$C_WARN" "$C_OFF"
        fi
        exit 1
    fi

    printf '\n%sAll good.%s\n' "$C_STEP" "$C_OFF"
    printf '%sOpen a new shell to pick up PATH changes.%s\n' "$C_SKIP" "$C_OFF"
    exit 0
}

main "$@"
