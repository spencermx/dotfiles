#!/usr/bin/env bash
# Build and configure your tools, then apply the Sway desktop configuration.
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

# Pin the compiler as well as the Cargo.lock used by tools/install.sh.
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
if [ ! -x "$TOOLS_REPO/install.sh" ]; then
    echo "missing tools installer: $TOOLS_REPO/install.sh" >&2
    exit 1
fi
RUSTUP_TOOLCHAIN="$RUST_VERSION" "$TOOLS_REPO/install.sh" aivim
"$TOOLS_REPO/install.sh" --check

for timer in aivim-sweep.timer aivim-usage.timer; do
    systemctl --user is-enabled --quiet "$timer"
    systemctl --user is-active --quiet "$timer"
done

# The config is linked by step 2. Reloading applies bindings and window rules
# to the current desktop; on a fresh login Sway loads them normally.
if [ -n "${SWAYSOCK:-}" ]; then
    sway --validate --config "$HOME/.config/sway/config"
    swaymsg reload >/dev/null
fi
echo "ok         aivim installed, hooks configured, timers enabled"
