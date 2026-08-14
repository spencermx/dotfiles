# dotfiles

Four self-contained OS zones — `archlinux/`, `debian/`, `mac/`, `windows/` — in
one repository, each provisioning a machine from scratch with one script.
[README.md](README.md) and the per-zone READMEs are current; read the relevant
one before changing how a setup script works.

## The zones share only `common/`

A zone reads from its own directory and from `common/`, and writes only inside
`$HOME`. `common/` holds every config that is not OS-specific, reached through
`$SHARED_ROOT` in each setup script and `$SharedRoot` in `windows/setup.ps1`:

| `config/nvim/` | `config/.vimrc` | `config/.tmux.conf` |
| `config/claude/` | `config/vscode/` | `config/git/ignore` |
| `config/shell/repo.bash` — bash only, see below | | |
| `config/.gitconfig` — the shared half only, see below | | |

The test is "is this OS-specific", not "is this currently duplicated". A file
used by one zone today still belongs in `common/` if nothing in it is tied to
an OS — the VS Code settings live there while only Windows links them, so the
config is already correct the day another zone installs VS Code. Where only the
*location* differs, the zone script varies the link target, not the file.

`config/.gitconfig` is split rather than shared whole: identity, `init` and
`core.excludesfile` are in `common/`, linked to `~/.gitconfig.common`, and each
zone's own `.gitconfig` pulls it in with `[include]` before adding its
credential helper. Note that `git config --global <key>` will not show included
values — `--includes` defaults off when scoped to a file. Drop `--global` to
check one.

`config/shell/repo.bash` is the `repo` command, sourced by the `archlinux/` and
`debian/` bashrcs from `~/.bashrc.repo`. It is shared because it is git, `gh`
and bash builtins with nothing OS-specific in it — but only those two zones can
read it, so `windows/config/Microsoft.PowerShell_profile.ps1` and
`mac/config/.zshrc` still hold their own ports of the same command, and a change
here does not reach them. The one thing the zones disagree about is what to open
the review clone with; that is `$REPO_OPEN`, set by each zone's bashrc, so the
shared file carries no conditional. It is *not* the shared half of a bashrc —
the two bashrcs agree on much more than this and are still separate copies on
purpose.

Nothing else is shared, and one zone still must not point at another. That
coupling existed and was removed deliberately: a mac edit silently changed the
Linux config, and `mac/setup.sh` could not run unless `archlinux/` existed.
`common/` is a third location both zones read, not a dependency between them.

Two costs were accepted knowingly. A zone no longer provisions a machine on its
own — it needs `common/` beside it. And an edit under `common/` changes every
OS at once, which is the point and also the risk. A file belongs in `common/`
only while it is byte-identical everywhere it appears; the moment one OS needs
it to differ, copy it back into that zone rather than adding a conditional.

## Editing a config here takes effect immediately

`$LINKS` symlinks point *into* the repo, so files under `config/` are the live
configuration on a provisioned machine — there is nothing to re-copy. That
includes `mac/config/claude/CLAUDE.md`, which is `~/.claude/CLAUDE.md`.

## Line endings

Before staging, compare `git diff --stat` against
`git diff --stat --ignore-cr-at-eol`. If they disagree, an edit has rewritten
LF files as CRLF and a small change is about to land as a whole-file diff.
Convert back before committing. `.gitattributes` pins `.ps1` to CRLF under
`windows/` and `.sh` to LF under `mac/`, scoped so the two cannot fight.

## bash 3.2

`mac/setup.sh` targets bash 3.2.57, which is what macOS ships. No `declare -A`,
no `mapfile`. Homebrew's bash 5 is not a way out — a fresh machine runs this
script before brew exists. `archlinux/setup.sh` has no such constraint.

## Nothing here is sensitive

Configuration only, plus a GitHub noreply address that appears in every commit
anyway. Personal documents, identity information, and anything describing how
accounts are protected live in a separate private repo. That property is worth
keeping — check before adding a file that came off a machine rather than out of
an editor.

## Commits

No AI attribution: no `Co-Authored-By: Claude`, no "Generated with Claude
Code", in a commit message, PR body, or file.
