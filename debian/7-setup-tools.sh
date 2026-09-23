#!/usr/bin/env bash
# Install Aivim, activate the Claude configuration, then apply Sway settings.
# Run as yourself: ./7-setup-tools.sh
# Also runs as part of ./run-all.sh; step 1 supplies rustup and build tools.

set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
    echo "run this as yourself, not as root" >&2
    exit 1
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS="$(dirname "$(dirname "$HERE")")"
TOOLS_REPO="${TOOLS_REPO:-$REPOS/tools}"
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# Pin the compiler and use Aivim's Cargo.lock when building below.
RUST_VERSION="1.98.1"
if ! command -v rustup >/dev/null; then
    echo "rustup is missing; run 1-install-debian-packages.sh first" >&2
    exit 1
fi
if ! rustup run "$RUST_VERSION" rustc --version >/dev/null 2>&1; then
    rustup toolchain install "$RUST_VERSION" --profile minimal
fi

# An existing working checkout is the source of truth. Never pull over or
# reset edits while setting up the machine.
if [ ! -e "$TOOLS_REPO" ]; then
    git clone https://github.com/spencermx/tools.git "$TOOLS_REPO"
fi
if [ ! -f "$TOOLS_REPO/aivim/Cargo.toml" ]; then
    echo "missing Aivim source: $TOOLS_REPO/aivim/Cargo.toml" >&2
    exit 1
fi

# Build separately from configuration: tools/install.sh combines both, which
# would change the old Claude settings before step 2 can back them up.
# Install where the shared Claude settings expect the executable.
rustup run "$RUST_VERSION" cargo install --locked --force \
    --path "$TOOLS_REPO/aivim" --root "$HOME/.local"

# Activate the dotfiles only after the build succeeds, then configure Aivim
# against those final settings. Step 2 backs up any files it replaces.
"$HERE/2-link-dotfiles.sh" --claude
"$HOME/.local/bin/aivim" --install

# Check the settings actually used by Claude, including every expected hook.
if ! jq -e '
    . as $settings |
    ($settings.statusLine.type == "command") and
    ($settings.statusLine.command == "~/.local/bin/aivim --statusline") and
    all(["UserPromptSubmit", "Stop", "Notification", "SessionStart", "SessionEnd"][];
        . as $event |
        [$settings.hooks[$event][]?.hooks[]? |
            select(.type == "command" and .command == "~/.local/bin/aivim --hook")]
        | length == 1)
' "$HOME/.claude/settings.json" >/dev/null; then
    echo "Claude's Aivim hooks or status line are not configured correctly." >&2
    exit 1
fi

for timer in aivim-sweep.timer aivim-usage.timer; do
    if ! systemctl --user is-enabled --quiet "$timer" ||
        ! systemctl --user is-active --quiet "$timer"; then
        echo "$timer must be enabled and active; check the systemd user session." >&2
        exit 1
    fi
    case "$(systemctl --user show --property=SubState --value "$timer")" in
        waiting|running) ;;
        *) echo "$timer has no scheduled run; Aivim setup is incomplete." >&2; exit 1 ;;
    esac
done

# The config is linked by step 2. Reloading applies bindings and window rules
# to the current desktop; on a fresh login Sway loads them normally.
if [ -n "${SWAYSOCK:-}" ]; then
    sway --validate --config "$HOME/.config/sway/config"
    swaymsg reload >/dev/null
fi
echo "ok         aivim installed, Claude config linked, hooks verified, timers scheduled"
