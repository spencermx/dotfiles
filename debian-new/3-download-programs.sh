#!/usr/bin/env bash
# Step 3: download programs that do not come from Debian.
#
# Run as yourself, NOT as root:   ./3-download-programs.sh
#
# Every program here is PINNED: an exact version, and the sha256 its download
# must match. If the hash is wrong, nothing is installed. Running this again
# never brings newer code. A program only moves when you edit its three lines
# below (version, url, sha256) and run this again.
#
# So far: Neovim, yazi, tree-sitter, Node.

set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
    echo "run this as yourself, not as root" >&2
    exit 1
fi

mkdir -p "$HOME/.local/bin" "$HOME/.local/share"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# download_checked <url> <sha256> <file>
# Downloads over https, then checks the sha256. Wrong hash: stop, install nothing.
download_checked() {
    curl -fsSL --proto '=https' "$1" -o "$3"
    if ! echo "$2  $3" | sha256sum --check --quiet; then
        echo "$3: the download does not match its sha256. NOT installing." >&2
        exit 1
    fi
}

#---------------------------------------------------------------------------
# Neovim. Debian ships 0.10; your config needs 0.11 or newer.
#---------------------------------------------------------------------------
NVIM_VERSION="0.12.5"        # released 2026-08-23
NVIM_URL="https://github.com/neovim/neovim/releases/download/v0.12.5/nvim-linux-x86_64.tar.gz"
NVIM_SHA256="bce0f56eda1f1b1db6eee8f4133d7a38813ea07933837dd1777411ca384c6875"

if [ -x "$HOME/.local/bin/nvim" ] && "$HOME/.local/bin/nvim" --version | head -1 | grep -qxF "NVIM v$NVIM_VERSION"; then
    echo "ok         nvim $NVIM_VERSION"
else
    download_checked "$NVIM_URL" "$NVIM_SHA256" "$tmp/nvim.tar.gz"
    tar -xzf "$tmp/nvim.tar.gz" -C "$tmp"
    rm -rf "$HOME/.local/share/nvim-dist"
    mv "$tmp/nvim-linux-x86_64" "$HOME/.local/share/nvim-dist"
    ln -sf "$HOME/.local/share/nvim-dist/bin/nvim" "$HOME/.local/bin/nvim"
    echo "installed  nvim $NVIM_VERSION"
fi

#---------------------------------------------------------------------------
# yazi, the file manager. Not in Debian at all.
#---------------------------------------------------------------------------
YAZI_VERSION="26.9.1"        # released 2026-09-01
YAZI_URL="https://github.com/sxyazi/yazi/releases/download/v26.9.1/yazi-x86_64-unknown-linux-gnu.zip"
YAZI_SHA256="a02fe91d3304294048c681f010f1100856872a4e98ecf6927328e888d40a6ad2"

if [ -x "$HOME/.local/bin/yazi" ] && "$HOME/.local/bin/yazi" --version | head -1 | grep -qF "Yazi $YAZI_VERSION "; then
    echo "ok         yazi $YAZI_VERSION"
else
    download_checked "$YAZI_URL" "$YAZI_SHA256" "$tmp/yazi.zip"
    unzip -q "$tmp/yazi.zip" -d "$tmp"
    cp "$tmp/yazi-x86_64-unknown-linux-gnu/yazi" "$tmp/yazi-x86_64-unknown-linux-gnu/ya" "$HOME/.local/bin/"
    chmod +x "$HOME/.local/bin/yazi" "$HOME/.local/bin/ya"
    echo "installed  yazi $YAZI_VERSION"
fi

#---------------------------------------------------------------------------
# tree-sitter CLI. Neovim uses it to build syntax highlighting.
# Debian ships 0.22, which is too old for your nvim-treesitter config.
#---------------------------------------------------------------------------
TREESITTER_VERSION="0.27.0"  # released 2026-08-30
TREESITTER_URL="https://github.com/tree-sitter/tree-sitter/releases/download/v0.27.0/tree-sitter-linux-x64.gz"
TREESITTER_SHA256="20a1f39ec1c45f2211492dcb8881c802b643b554bb196869a29ac3778277fa77"

if [ -x "$HOME/.local/bin/tree-sitter" ] && "$HOME/.local/bin/tree-sitter" --version | head -1 | grep -qF "tree-sitter $TREESITTER_VERSION"; then
    echo "ok         tree-sitter $TREESITTER_VERSION"
else
    download_checked "$TREESITTER_URL" "$TREESITTER_SHA256" "$tmp/tree-sitter.gz"
    gunzip -c "$tmp/tree-sitter.gz" > "$HOME/.local/bin/tree-sitter"
    chmod +x "$HOME/.local/bin/tree-sitter"
    echo "installed  tree-sitter $TREESITTER_VERSION"
fi

#---------------------------------------------------------------------------
# Node.js 22 (long-term support). npm comes inside it. Three of your Neovim
# language servers run on it. Debian's npm would pull in 362 packages.
#---------------------------------------------------------------------------
NODE_VERSION="22.23.2"       # released 2026-07-28
NODE_URL="https://nodejs.org/dist/v22.23.2/node-v22.23.2-linux-x64.tar.xz"
NODE_SHA256="d60acfe00a2932254bb0ad20e01b0d74397a0875595de719654b214f4b03f307"

if [ -x "$HOME/.local/bin/node" ] && [ "$("$HOME/.local/bin/node" --version)" = "v$NODE_VERSION" ]; then
    echo "ok         node $NODE_VERSION"
else
    download_checked "$NODE_URL" "$NODE_SHA256" "$tmp/node.tar.xz"
    tar -xJf "$tmp/node.tar.xz" -C "$tmp"
    rm -rf "$HOME/.local/share/node-dist"
    mv "$tmp/node-v$NODE_VERSION-linux-x64" "$HOME/.local/share/node-dist"
    ln -sf "$HOME/.local/share/node-dist/bin/node" "$HOME/.local/bin/node"
    ln -sf "$HOME/.local/share/node-dist/bin/npm"  "$HOME/.local/bin/npm"
    ln -sf "$HOME/.local/share/node-dist/bin/npx"  "$HOME/.local/bin/npx"
    echo "installed  node $NODE_VERSION"
fi
