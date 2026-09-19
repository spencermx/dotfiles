#!/usr/bin/env bash
# Step 6: language servers (completion, go-to-definition, errors as you type).
#
# Run as yourself, NOT as root:   ./6-language-servers.sh
# Run steps 1 to 5 first. This needs nvim with its plugins, and node.
#
# They are installed through Mason, a Neovim plugin, each at ONE exact version.
# Running this again never brings newer code. To move one, change its version
# in SERVERS below and run this again.
#
# IMPORTANT: your nvim config lists these same six under `ensure_installed`
# (common/config/nvim/lua/plugins/mason-lspconfig.lua). That setting installs
# any server that is MISSING, at the NEWEST version, the first time you open a
# file. Installing all six here first means it finds them present and does
# nothing. If you delete a server from this list, delete it from that list too,
# or it comes back unpinned.

set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
    echo "run this as yourself, not as root" >&2
    exit 1
fi

# nvim, node and npm live here, and a fresh shell may not have it on PATH yet.
export PATH="$HOME/.local/bin:$PATH"

SERVERS=(
    "lua-language-server@3.19.1"          # Lua          released 2026-08-13
    "pyright@1.1.412"                     # Python       released 2026-08-12   (from npm)
    "bash-language-server@5.6.0"          # Bash         released 2025-04-13   (from npm)
    "omnisharp@v1.39.15"                  # C#           released 2025-11-14
    "rust-analyzer@2026-08-31"            # Rust         released 2026-08-31
    "typescript-language-server@6.0.0"    # TypeScript   released 2026-08-20   (from npm)
)

MASON_DIR="$HOME/.local/share/nvim/mason/packages"

if ! command -v nvim >/dev/null || [ ! -d "$HOME/.local/share/nvim/lazy/mason.nvim" ]; then
    echo "nvim or its plugins are missing. Run steps 3, 4 and 5 first." >&2
    exit 1
fi
if ! command -v npm >/dev/null; then
    echo "npm not found. Run ./3-download-programs.sh first (it installs node)." >&2
    exit 1
fi

# The version Mason recorded for an installed server, or nothing if it is not installed.
installed_version() {
    local receipt="$MASON_DIR/$1/mason-receipt.json"
    [ -f "$receipt" ] || return 0
    jq -r '.source.id // .primary_source.id // empty' "$receipt" | sed 's/.*@//'
}

#---------------------------------------------------------------------------
# 1. npm must never run a package's install scripts. Three of these servers
#    come from npm, and the credential-stealing npm worms of 2025-26 ran from
#    exactly those scripts. None of these servers needs one. This writes one
#    line to your own ~/.npmrc (which is not part of this repo).
#---------------------------------------------------------------------------
if [ "$(npm config get ignore-scripts --location=user)" = "true" ]; then
    echo "ok         npm ignore-scripts is on"
else
    npm config set ignore-scripts true --location=user
    echo "set        npm ignore-scripts = true"
fi

#---------------------------------------------------------------------------
# 2. Install every server that is missing or on the wrong version.
#---------------------------------------------------------------------------
to_install=()
for server in "${SERVERS[@]}"; do
    name="${server%%@*}"; version="${server#*@}"
    [ "$(installed_version "$name")" = "$version" ] || to_install+=("$server")
done

if [ ${#to_install[@]} -gt 0 ]; then
    echo "installing: ${to_install[*]}"
    nvim --headless -c "MasonInstall ${to_install[*]}" -c qall
fi

#---------------------------------------------------------------------------
# 3. Check the result ourselves and show the list.
#---------------------------------------------------------------------------
wrong=0
for server in "${SERVERS[@]}"; do
    name="${server%%@*}"; version="${server#*@}"; have="$(installed_version "$name")"
    if [ "$have" = "$version" ]; then
        printf '  ok     %-30s %s\n' "$name" "$version"
    else
        wrong=$((wrong + 1))
        printf '  WRONG  %-30s is %s, pinned at %s\n' "$name" "${have:-not installed}" "$version"
    fi
done
[ "$wrong" -eq 0 ]
