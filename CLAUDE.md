# dotfiles

Four self-contained OS zones — `archlinux/`, `debian/`, `mac/`, `windows/` — in
one repository, each provisioning a machine from scratch with one script.
[README.md](README.md) and the per-zone READMEs are current; read the relevant
one before changing how a setup script works.

## The zones do not share files

Anything run from a zone writes only inside that zone and `$HOME`, and reads
only from that zone. A config appearing in two zones is two copies, and a
change to one does not propagate — `archlinux/config/nvim` and `mac/config/nvim`
are the same 33 files kept in sync by hand.

Do not "deduplicate" them by pointing one zone at another. That coupling
existed and was removed deliberately: it meant a mac edit silently changed the
Linux config, and `mac/setup.sh` could not run unless `archlinux/` existed. When a
change should apply to more than one OS, make it in each zone separately.

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
