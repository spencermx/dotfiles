#!/usr/bin/env bash
# Step 3: download programs and fonts that do not come from Debian.
#
# Run as yourself, NOT as root:   ./3-download-programs.sh
#
# Every program here is PINNED: an exact version, and the sha256 its download
# must match. If the hash is wrong, nothing is installed. Running this again
# never brings newer code. A program only moves when you edit its three lines
# below (version, url, sha256) and run this again.
#
# So far: Neovim, yazi, tree-sitter, Node, gh, JetBrainsMono Nerd Font.

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

if [ -x "$HOME/.local/bin/yazi" ] && "$HOME/.local/bin/yazi" --version | grep -qF "Version: $YAZI_VERSION "; then
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

#---------------------------------------------------------------------------
# gh, the GitHub CLI. Your `repo` command and git logins use it.
# Debian ships 2.46, which is missing 8 security fixes (token leaks among them).
# Every advisory gh has published is fixed by 2.98.0.
#---------------------------------------------------------------------------
GH_VERSION="2.100.0"         # released 2026-09-03
GH_URL="https://github.com/cli/cli/releases/download/v2.100.0/gh_2.100.0_linux_amd64.tar.gz"
GH_SHA256="e4d4bb4498e8d007abe545b6568926793ace1b6447da598294a610018cb164be"

if [ -x "$HOME/.local/bin/gh" ] && "$HOME/.local/bin/gh" --version | head -1 | grep -qF "gh version $GH_VERSION "; then
    echo "ok         gh $GH_VERSION"
else
    download_checked "$GH_URL" "$GH_SHA256" "$tmp/gh.tar.gz"
    tar -xzf "$tmp/gh.tar.gz" -C "$tmp"
    cp "$tmp/gh_${GH_VERSION}_linux_amd64/bin/gh" "$HOME/.local/bin/gh"
    chmod +x "$HOME/.local/bin/gh"
    echo "installed  gh $GH_VERSION"
fi

#---------------------------------------------------------------------------
# JetBrainsMono Nerd Font: the same terminal font as Arch, including icons.
# Release and checksum: https://github.com/ryanoasis/nerd-fonts/releases/tag/v3.5.1
#---------------------------------------------------------------------------
NERD_FONT_VERSION="3.5.1"    # released 2026-08-21
NERD_FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/JetBrainsMono.tar.xz"
NERD_FONT_SHA256="04d5e8f903693f9dd13e16f867e994834e681eb3c72c0d337a770dcda09010cf"
NERD_FONT_DIR="$HOME/.local/share/fonts/JetBrainsMonoNerdFont"
NERD_FONT_FILES=(JetBrainsMonoNerdFont-{Regular,Bold,Italic,BoldItalic}.ttf)

font_ready=true
[ "$(cat "$NERD_FONT_DIR/.version" 2>/dev/null)" = "$NERD_FONT_VERSION" ] || font_ready=false
for font in "${NERD_FONT_FILES[@]}"; do
    [ -s "$NERD_FONT_DIR/$font" ] || font_ready=false
done

if "$font_ready"; then
    echo "ok         JetBrainsMono Nerd Font $NERD_FONT_VERSION"
else
    download_checked "$NERD_FONT_URL" "$NERD_FONT_SHA256" "$tmp/nerd-font.tar.xz"
    mkdir -p "$tmp/nerd-font" "$NERD_FONT_DIR"
    tar -xJf "$tmp/nerd-font.tar.xz" -C "$tmp/nerd-font"
    for font in "${NERD_FONT_FILES[@]}" OFL.txt; do
        install -m 644 "$tmp/nerd-font/$font" "$NERD_FONT_DIR/$font"
    done
    fc-cache -f "$NERD_FONT_DIR"
    printf '%s\n' "$NERD_FONT_VERSION" > "$NERD_FONT_DIR/.version"
    echo "installed  JetBrainsMono Nerd Font $NERD_FONT_VERSION"
fi
