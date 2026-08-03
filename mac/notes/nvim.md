# Neovim on macOS

The config lives at `config/nvim/` and is linked to `~/.config/nvim` by
`setup.sh`. It is mac's own copy — 33 files, ~1900 lines — not a link into any
other OS directory.

It still carries a `Darwin` branch in `config/nvim/lua/plugins/formatter.lua`,
which picks the right `shfmt` binary per architecture. That was written when
this config was shared; on a mac-only copy the `Darwin.*arm` / `Darwin.*x86`
split still matters (Apple Silicon vs Intel), but the non-Darwin fallback is
now dead code. Harmless, and worth knowing before you read it and wonder.

## What setup.sh does for you

The `tools` phase does all of this, and every step is a no-op when already
satisfied:

1. installs `nvm`, then `node` — several LSP servers are npm packages, so node
   is a hard dependency of the editor rather than an optional extra
2. clones `lazy.nvim` into `~/.local/share/nvim/site/pack/lazy/start/`
3. runs `nvim --headless '+Lazy! sync' +qa`
4. installs any missing Mason package headless, from `$MASON_PACKAGES`

Step 4 replaces working through the Mason UI checkbox by checkbox. The list in
`setup.sh` is the same 14 packages that were being installed by hand:

| kind | packages |
|------|----------|
| lsp | `bash-language-server` `lua-language-server` `omnisharp` `pyright` `rust-analyzer` `typescript-language-server` |
| dap | `codelldb` `debugpy` |
| formatters | `shfmt` `htmlbeautifier` `prettier` `gofumpt` `csharpier` `luaformatter` |

## Toolchains those packages need

Declared in `$FORMULAE` / `$CASKS`, because a language server with no
toolchain behind it is half installed:

| | |
|-|-|
| `rustup` | `rust-analyzer` and `codelldb`. **This was the gap** — both Mason packages were installed on a machine with no `cargo` and no `rustc`. |
| `go` | `gofumpt` |
| `dotnet-sdk` | `omnisharp`, `csharpier` |
| `luarocks`, `cmake` | Mason builds some packages from source |
| node (via nvm) | the four npm-based servers above |

`rustup` installs the tool, not the toolchain. After the first install:

```sh
rustup default stable
```

`setup.sh`'s health check looks for `cargo` and will keep reporting it until
you do.

## Adding a package

Add it to `$MASON_PACKAGES` in `setup.sh` and re-run — don't install it through
the UI, or the next fresh machine won't have it.
