# Interactive shell config. PATH and login-time environment live in .zprofile.

# .zprofile only runs for login shells. Terminal.app and tmux both start one,
# but some editors' embedded terminals do not -- and without it every alias
# below points at a Homebrew binary that is not on PATH yet.
if [ -z "$HOMEBREW_PREFIX" ] && [ -r "$HOME/.zprofile" ]; then
	source "$HOME/.zprofile"
fi

alias ll='lsd -la'
alias ls='lsd -l'
alias cls='clear'
alias vim=nvim
alias poweroff='sudo shutdown -h now'
alias laude='clear && claude'

# yazi, then follow it to wherever you quit. A child process cannot change its
# parent's directory, so yazi writes its exit directory to a temp file and the
# function does the cd itself.
function e() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	command yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}

# open Finder here
function fe() {
	open "${1:-.}"
}

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"                    # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# zoxide and fzf were both installed as deliberate brew leaves and neither was
# ever initialised, so neither was reachable through the interface it exists
# for -- `z` for zoxide, ctrl-r / ctrl-t for fzf.
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"

# fzf's key-bindings.zsh calls `setopt` on zle options, which do not exist when
# there is no terminal -- an interactive shell driven by a script (zsh -i in a
# pipe) then prints "can't change option: zle" twice on every start. Guard on a
# real tty rather than on interactivity.
if [ -t 0 ]; then
	[ -r "$HOMEBREW_PREFIX/opt/fzf/shell/key-bindings.zsh" ] && source "$HOMEBREW_PREFIX/opt/fzf/shell/key-bindings.zsh"
	[ -r "$HOMEBREW_PREFIX/opt/fzf/shell/completion.zsh" ] && source "$HOMEBREW_PREFIX/opt/fzf/shell/completion.zsh"
fi

# >>> grok installer >>>
export PATH="$HOME/.grok/bin:$PATH"
fpath=(~/.grok/completions/zsh $fpath)
autoload -Uz compinit && compinit -C
# <<< grok installer <<<

# --- Repo commands -----------------------------------------------------------
#
# Deliberately below the grok block: that is where compinit runs, and compdef
# does not exist until it has. Everything else here would work anywhere in the
# file; the completion at the bottom would silently not register.
#
# One word for everything that touches repos. There is no second word.
#
#   repo             where every repo below here stands. No network.
#   repo <branch>    checkout <branch> and pull, in every repo that has it
#   repo <number>    review that PR of the repo you are standing in
#   repo <url>       review that PR, any repo
#   repo -l          every review clone and its state
#
# Digits and URLs are pull requests; anything else is a branch name. Nothing to
# recall, nothing to disambiguate, and one word total.
#
# This is a guess, and guessing is refused further down -- a branch that does
# not exist is a skip with a reason, never a silent switch to another one. The
# difference is what a wrong guess costs. A branch name cannot be read as a PR
# because branch names are not bare digits, and a *typo'd* branch name is read
# as exactly what it is: a fetch and a "no such branch" skip in every repo,
# which changes nothing. The two readings also cannot reach each other's trees
# -- the PR path only ever writes under $_repo_prroot.
#
# What is deliberately not merged is the two implementations. They are opposite
# on purpose: the PR path checks out --force because the review tree is not
# yours, the branch path skips on tracked changes because those trees are.
# Folding them together would put a force-checkout over your own work one flag
# away. Only the front door is shared.
#
# This is a port of the same function in windows/config/, and like every other
# config living in two zones it is a separate copy. A change there does not
# arrive here.

# Colours as plain ANSI rather than print -P's %F{...}: branch names, paths and
# PR titles are interpolated into these lines, and a literal % in one would be
# read as a prompt escape. 90 is bright black, which is what DarkGray renders as.
typeset -g _repo_key=$'\e[36m'     _repo_red=$'\e[31m'   _repo_yellow=$'\e[33m'
typeset -g _repo_magenta=$'\e[35m' _repo_green=$'\e[32m' _repo_dim=$'\e[90m'
typeset -g _repo_off=$'\e[0m'

# One directory holding a permanent clone of every repo ever reviewed, named
# <owner>-<repo>. Deliberately separate from the clones under source/repos, and
# deliberately duplicated: the disk is worth less than never having to think
# about which working tree a review is about to disturb.
#
# Not /tmp -- macOS empties that periodically, and these are meant to outlive
# every review that uses them.
typeset -g _repo_prroot="$HOME/.prs"

function repo() {
	local a forced=''
	local -a rest

	# Help wins wherever it appears, so `repo develop --help` answers with help
	# instead of checking out develop. The implementations below carry no help
	# of their own -- there is one help, and this is what reaches it.
	for a in "$@"; do
		case ${(L)a} in
			-h|--h|-help|--help) _repo_help; return 0 ;;
		esac
	done

	# Both spellings are accepted. -List and -Branch are what the PowerShell
	# copy takes, and typing one here after a day on the other should not fail.
	while (( $# )); do
		case ${(L)1} in
			-l|-list|--list)
				_repo_list
				return $?
				;;
			# The escape hatch for the one case the shape rule gets wrong: a
			# branch actually named with digits. It is the only thing here you
			# will never type.
			-b|-branch|--branch)
				if [[ -z $2 ]]; then
					print -ru2 -- "${_repo_red}repo: -b needs a branch name${_repo_off}"
					return 2
				fi
				forced=$2
				shift 2
				;;
			*)
				rest+=("$1")
				shift
				;;
		esac
	done

	[[ -n $forced ]] && { _repo_pull "$forced"; return $? }
	(( ${#rest} )) || { _repo_pull; return $? }

	# <-> is zsh's "any run of digits", so this is the shape rule itself and
	# not a regex approximating it.
	case $rest[1] in
		<->|\#<->)          _repo_pr "$rest[1]" ;;
		http://*|https://*) _repo_pr "$rest[1]" ;;
		*)                  _repo_pull "$rest[1]" ;;
	esac
}

function _repo_help() {
	local k=$_repo_key o=$_repo_off d=$_repo_dim
	print -r -- ""
	print -r -- "  ${k}repo${o} -- one word for every git repo below here. There is no second word."
	print -r -- ""
	print -r -- "    ${k}repo${o}             where they all stand. No network, changes nothing."
	print -r -- "    ${k}repo <branch>${o}    checkout <branch> and pull, in every repo that has it"
	print -r -- "    ${k}repo <number>${o}    review that PR of the repo you are standing in"
	print -r -- "    ${k}repo <url>${o}       review that PR, any repo"
	print -r -- "    ${k}repo -l${o}          every review clone, what it is on, and where"
	print -r -- ""
	print -r -- "  Digits and URLs are pull requests, anything else is a branch. So there"
	print -r -- "  is nothing to remember past the word itself, and ${k}repo <tab>${o} completes"
	print -r -- "  branch names across every repo below here."
	print -r -- ""
	print -r -- "  ${k}Branches.${o} Repos are found at depth 1 and 2, so this works from the folder"
	print -r -- "  holding your project folders as well as from inside one. A repo is skipped"
	print -r -- "  when it has tracked changes, is on a detached HEAD, or has no such branch."
	print -r -- "  Untracked files block nothing."
	print -r -- ""
	print -r -- "  ${k}Reviews.${o} Each repo clones once to $_repo_prroot/<owner>-<repo> and stays,"
	print -r -- "  so the clones you actually work in are never touched and never need stashing."
	print -r -- ""
	print -r -- "  ${_repo_yellow}The review tree is not yours.${o} Tracked changes there are discarded on every"
	print -r -- "  checkout, so leave nothing in one. Untracked files survive on purpose:"
	print -r -- "  node_modules and obj carry over, so the second review skips the rebuild."
	print -r -- ""
	print -r -- "    ${k}git diff origin/<base>...HEAD${o}    what the author changed; three dots"
	print -r -- "                                     exclude what landed on base since"
	print -r -- "    ${k}gh pr diff <number>${o}          read one without cloning at all"
	print -r -- ""
	print -r -- "  ${d}-b <name> forces the branch reading, for a branch actually named"
	print -r -- "  with digits -- the one case the shape rule gets wrong.${o}"
	print -r -- ""
}

# --- Reviewing pull requests -------------------------------------------------

# Check out someone else's PR, in a clone that exists only for reviewing.
#
# The stash / checkout / unstash dance is not a git problem, it is a problem of
# reviewing inside the tree you work in. A repo gets cloned under $_repo_prroot
# once, and every later review of it is a fetch and a checkout in a tree that
# has never held anything worth keeping.
#
# Nothing here is disposable in the sense of being deleted -- the clones are the
# point and they stay. It is the *contents* that are disposable, which is what
# lets the checkout below be unconditional.
function _repo_pr() {
	local ref=$1 slug num base title author clone meta

	# Resolve to owner/repo plus number. A bare number means the repo we are
	# standing in, which is the same thing gh assumes when given no --repo.
	#
	# No lazy quantifier for the optional .git -- =~ is ERE here, not PCRE, so
	# the suffix comes off with a parameter expansion instead.
	if [[ $ref =~ '^https?://[^/]+/([^/]+)/([^/]+)/pull/([0-9]+)' ]]; then
		slug="${match[1]}/${match[2]%.git}"
		num="${match[3]}"
	elif [[ $ref =~ '^#?([0-9]+)$' ]]; then
		num="${match[1]}"
		slug=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
		if [[ -z $slug ]]; then
			print -ru2 -- "${_repo_red}Not inside a GitHub repo -- pass the full PR URL.${_repo_off}"
			return 1
		fi
	else
		print -ru2 -- "${_repo_red}Could not read '$ref' as a PR URL or number -- see repo --help${_repo_off}"
		return 1
	fi

	# One round trip for all three fields. gh has jq built in, so @tsv here
	# costs nothing and saves two more calls; jq escapes any tab inside a title.
	meta=$(gh pr view "$num" --repo "$slug" --json baseRefName,title,author \
		-q '[.baseRefName, .title, .author.login] | @tsv' 2>/dev/null)
	if [[ -z $meta ]]; then
		print -ru2 -- "${_repo_red}Could not read $slug#$num -- is gh authenticated for that host?${_repo_off}"
		return 1
	fi
	IFS=$'\t' read -r base title author <<< "$meta"

	clone="$_repo_prroot/${slug//\//-}"

	if [[ ! -d $clone ]]; then
		print -r -- "First review of $slug -- cloning to $clone"
		if ! gh repo clone "$slug" "$clone"; then
			print -ru2 -- "${_repo_red}Clone of $slug failed.${_repo_off}"
			return 1
		fi
	fi

	# Both refs in one round trip. The base comes along so the diff below is
	# against where base is now rather than whenever this clone last saw it.
	#
	# refs/pull/<n>/head is materialized by GitHub on the base repo even when
	# the PR comes from a fork, so fork PRs need no extra remote. head rather
	# than merge: head is what the author wrote, merge is a commit GitHub
	# synthesized and may have computed against a stale base.
	#
	# ${base} is braced on both sides of the colon. Bare $base: is read by zsh
	# as a history modifier -- $base:refs/... applies :r and pastes the rest on
	# as literal text, producing a refspec git cannot resolve.
	if ! git -C "$clone" fetch --quiet origin \
		"+refs/pull/$num/head:refs/remotes/origin/pr/$num" \
		"+refs/heads/${base}:refs/remotes/origin/${base}"; then
		print -ru2 -- "${_repo_red}Could not fetch $slug#$num.${_repo_off}"
		return 1
	fi

	# --force discards local modifications to tracked files, which is what makes
	# this never fail the way switching branches in your own tree does: whatever
	# the last review left behind is not worth a prompt. It does not touch
	# untracked files, so node_modules, obj and the IDE index survive and the
	# second review of a repo does not pay for a full rebuild.
	#
	# --detach because reviewing does not commit, and because a detached HEAD
	# cannot block the next force-fetch of a ref it happens to have checked out.
	if ! git -C "$clone" checkout --quiet --force --detach "refs/remotes/origin/pr/$num"; then
		print -ru2 -- "${_repo_red}Could not check out $slug#$num.${_repo_off}"
		return 1
	fi

	print -r -- ""
	print -r -- "  $slug#$num  $title"
	print -r -- "  by $author into $base"
	print -r -- ""
	# Three dots, not two: it diffs from the merge base, so the review shows what
	# the author changed and not whatever landed on base in the meantime.
	print -r -- "  ${_repo_key}git diff origin/$base...HEAD${_repo_off}"
	print -r -- ""

	builtin cd -- "$clone" && code "$clone"
}

function _repo_list() {
	if [[ ! -d $_repo_prroot ]]; then
		print -r -- 'No review clones yet.'
		return 0
	fi

	local -a clones
	clones=($_repo_prroot/*(N/))
	if (( ${#clones} == 0 )); then
		print -r -- 'No review clones yet.'
		return 0
	fi

	# The path is the one column that has to stay complete enough to copy, so
	# it must never be what gets truncated. Give the name and the path their
	# full width and hand whatever is left to the subject.
	local c at w=0 pw=0
	for c in $clones; do
		(( ${#${c:t}} > w ))  && w=${#${c:t}}
		(( ${#c} > pw ))      && pw=${#c}
	done

	local cols=${COLUMNS:-120}
	(( cols < 40 )) && cols=120
	local room=$(( cols - w - pw - 6 ))

	for c in $clones; do
		at=$(git -C "$c" log -1 --format='%h %s' 2>/dev/null)
		if (( room < 8 )); then
			printf '  %-*s  %s\n' $w "${c:t}" "$c"
		else
			(( ${#at} > room )) && at="${at[1,room-3]}..."
			printf '  %-*s  %-*s  %s\n' $w "${c:t}" $room "$at" "$c"
		fi
	done
}

# --- Bulk repo status and update ---------------------------------------------

# Every git repo at depth 1 or 2 below the current directory, into the global
# $_repo_found. Depth 2 is what makes `repo` work from the folder holding
# folder-a/ and folder-b/; stopping there keeps it out of node_modules and
# vendored trees. A directory that is itself a repo is not descended into, so
# submodules do not show up as peers.
#
# (N-/) is nullglob plus "directories, following symlinks" -- a bare (/) would
# skip a repo reached through a symlinked directory. Leading dots are not
# matched, which is also what keeps .git itself out of the walk.
function _repo_find() {
	local d s
	typeset -ga _repo_found=()
	for d in *(N-/); do
		if [[ -e $d/.git ]]; then
			_repo_found+=("$PWD/${d%/}")
			continue
		fi
		for s in $d/*(N-/); do
			[[ -e $s/.git ]] && _repo_found+=("$PWD/${s%/}")
		done
	done
}

# Read one repo's local state into the globals below. Deliberately no network:
# branch name and dirtiness both come off disk, so the bare `repo` view over 20
# repos costs milliseconds. --untracked-files=normal stops git recursing into
# untracked directories, which is what makes this fast in a repo carrying
# node_modules or obj.
#
# The parameter is $dir and not $path: zsh ties `path` to PATH as an array, so
# `local path=$1` here would replace PATH with one directory for the length of
# the call and git would stop resolving.
function _repo_state() {
	local dir=$1 out line
	local -a porcelain

	_repo_branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
	[[ -n $_repo_branch ]] || _repo_branch='?'
	[[ $_repo_branch == HEAD ]] && _repo_detached=1 || _repo_detached=0

	out=$(git -C "$dir" status --porcelain --untracked-files=normal 2>/dev/null)
	porcelain=()
	[[ -n $out ]] && porcelain=("${(@f)out}")

	# Untracked and modified are counted separately on purpose. Untracked files
	# are permanent residents of half these repos (build output, node_modules)
	# and must not make a repo look dirty -- only tracked changes block a
	# checkout, so only tracked changes cause a skip.
	#
	# '??' is quoted so it matches two literal question marks. Unquoted, ? is a
	# single-character wildcard here exactly as it is in PowerShell's -like,
	# and the test would match every status line instead of the untracked ones.
	_repo_untracked=0
	for line in $porcelain; do
		[[ $line == '??'* ]] && (( _repo_untracked += 1 ))
	done
	_repo_tracked=$(( ${#porcelain} - _repo_untracked ))
}

# Colour by what you would have to do about it, not by severity:
#   red     tracked changes -- blocks a checkout, needs you
#   yellow  untracked only  -- harmless, but worth seeing
#   magenta detached HEAD   -- not on a branch at all
#   green   clean
function _repo_color() {
	(( _repo_detached ))      && { print -rn -- $_repo_magenta; return }
	(( _repo_tracked > 0 ))   && { print -rn -- $_repo_red;     return }
	(( _repo_untracked > 0 )) && { print -rn -- $_repo_yellow;  return }
	print -rn -- $_repo_green
}

function _repo_note() {
	(( _repo_detached )) && { print -rn -- 'detached'; return }
	local -a bits
	(( _repo_tracked > 0 ))   && bits+=("$_repo_tracked changed")
	(( _repo_untracked > 0 )) && bits+=("$_repo_untracked untracked")
	(( ${#bits} )) || { print -rn -- 'clean'; return }
	print -rn -- "${(j:, :)bits}"
}

# Show every repo below here, or move them all onto a branch.
#
# There is no fallback between branch names. Asking for develop in a repo that
# only has main is a skip with a reason, not a silent switch to something else
# -- guessing is how you end up on a branch you did not intend across 20 repos
# and cannot tell which.
function _repo_pull() {
	local branch=$1

	_repo_find
	local -a repos=($_repo_found)
	if (( ${#repos} == 0 )); then
		print -r -- "${_repo_yellow}No git repos found below here.${_repo_off}"
		return 1
	fi

	local r name w=0
	for r in $repos; do
		(( ${#${r:t}} > w )) && w=${#${r:t}}
	done

	#-- status only ----------------------------------------------------------
	if [[ -z $branch ]]; then
		print -r -- ""
		for r in $repos; do
			_repo_state "$r"
			printf '  %-*s  ' $w "${r:t}"
			printf '%s%-22s%s' $_repo_key "$_repo_branch" $_repo_off
			print -r -- "$(_repo_color)$(_repo_note)$_repo_off"
		done
		print -r -- ""
		print -r -- "  ${_repo_dim}${#repos} repo(s). Nothing was changed.${_repo_off}"

		# The footer is the whole discoverability fix, so it hangs off bare
		# `repo` -- the one form reached without thinking -- rather than off
		# --help, which is exactly the thing nobody types when they have already
		# forgotten there was something to ask about.
		print -r -- "  ${_repo_dim}repo <branch> to move them  |  repo <number|url> to review a PR  |  repo --help${_repo_off}"
		print -r -- ""
		return 0
	fi

	#-- checkout and pull ----------------------------------------------------
	local -a rep_name rep_was rep_now rep_result
	local was now before after

	for r in $repos; do
		name=${r:t}
		_repo_state "$r"
		was=$_repo_branch

		printf '  %-*s  ' $w "$name"

		if (( _repo_tracked > 0 )); then
			print -r -- "${_repo_red}skipped -- $_repo_tracked tracked change(s)${_repo_off}"
			rep_name+=("$name"); rep_was+=("$was"); rep_now+=("$was"); rep_result+=('skipped: dirty')
			continue
		fi

		if (( _repo_detached )); then
			print -r -- "${_repo_magenta}skipped -- detached HEAD${_repo_off}"
			rep_name+=("$name"); rep_was+=('(detached)'); rep_now+=('(detached)'); rep_result+=('skipped: detached')
			continue
		fi

		# Fetch before deciding whether the branch exists. A repo cloned when it
		# only had master has no refs/remotes/origin/develop until something
		# fetches, so checking first would report "no such branch" for a branch
		# that is plainly on the server. The network cost is already being paid
		# by the pull below.
		git -C "$r" fetch --quiet origin 2>/dev/null

		local has_local=0 has_remote=0
		git -C "$r" rev-parse --verify --quiet "refs/heads/$branch" >/dev/null 2>&1 && has_local=1
		git -C "$r" rev-parse --verify --quiet "refs/remotes/origin/$branch" >/dev/null 2>&1 && has_remote=1

		if (( ! has_local && ! has_remote )); then
			print -r -- "${_repo_dim}skipped -- no '$branch' branch${_repo_off}"
			rep_name+=("$name"); rep_was+=("$was"); rep_now+=("$was"); rep_result+=("skipped: no $branch")
			continue
		fi

		if [[ $was != $branch ]]; then
			if ! git -C "$r" checkout --quiet "$branch" 2>/dev/null; then
				print -r -- "${_repo_red}FAILED -- could not check out $branch${_repo_off}"
				rep_name+=("$name"); rep_was+=("$was"); rep_now+=("$was"); rep_result+=('failed: checkout')
				continue
			fi
		fi

		before=$(git -C "$r" rev-parse --short HEAD 2>/dev/null)
		local pull_ok=1
		git -C "$r" pull >/dev/null 2>&1 || pull_ok=0
		after=$(git -C "$r" rev-parse --short HEAD 2>/dev/null)
		now=$(git -C "$r" rev-parse --abbrev-ref HEAD 2>/dev/null)

		if (( ! pull_ok )); then
			# The common cause is a diverged branch: local commits on $branch
			# that were never pushed. git refuses rather than merging, which is
			# the right outcome -- that repo needs a human, not a bulk tool.
			print -r -- "${_repo_red}FAILED -- pull refused (diverged?)${_repo_off}"
			rep_name+=("$name"); rep_was+=("$was"); rep_now+=("$now"); rep_result+=('failed: pull')
		elif [[ $before == $after ]]; then
			print -r -- "${_repo_dim}$was -> $now  already current${_repo_off}"
			rep_name+=("$name"); rep_was+=("$was"); rep_now+=("$now"); rep_result+=('already current')
		else
			print -r -- "${_repo_green}$was -> $now  updated $before..$after${_repo_off}"
			rep_name+=("$name"); rep_was+=("$was"); rep_now+=("$now"); rep_result+=("updated $before..$after")
		fi
	done

	print -r -- ""
	print -r -- "  ${_repo_key}---- report ----${_repo_off}"

	local i nw=4 ww=3 aw=3
	for (( i = 1; i <= ${#rep_name}; i++ )); do
		(( ${#rep_name[i]}   > nw )) && nw=${#rep_name[i]}
		(( ${#rep_was[i]}    > ww )) && ww=${#rep_was[i]}
		(( ${#rep_now[i]}    > aw )) && aw=${#rep_now[i]}
	done
	printf '  %-*s  %-*s  %-*s  %s\n' $nw 'Repo' $ww 'Was' $aw 'Now' 'Result'
	printf '  %-*s  %-*s  %-*s  %s\n' $nw '----' $ww '---' $aw '---' '------'
	for (( i = 1; i <= ${#rep_name}; i++ )); do
		printf '  %-*s  %-*s  %-*s  %s\n' \
			$nw "$rep_name[i]" $ww "$rep_was[i]" $aw "$rep_now[i]" "$rep_result[i]"
	done

	local updated=0 skipped=0 failed=0
	for i in $rep_result; do
		case $i in
			updated*) (( updated += 1 )) ;;
			skipped*) (( skipped += 1 )) ;;
			failed*)  (( failed += 1 )) ;;
		esac
	done
	print -r -- ""
	print -r -- "  ${_repo_dim}$updated updated, $skipped skipped, $failed failed, ${#rep_name} total${_repo_off}"
	print -r -- ""
}

# Branch names, deduped across every repo below here. This is the only
# completion worth having now that there are no verbs to enumerate: the
# argument is a branch name nearly every time, and completing it means even
# that does not have to be remembered.
function _repo() {
	local -a names
	local r line full short
	_repo_find
	for r in $_repo_found; do
		for line in ${(f)"$(git -C "$r" for-each-ref \
			--format='%(refname)|%(refname:short)' refs/heads refs/remotes/origin 2>/dev/null)"}; do
			full=${line%%|*}
			short=${line#*|}
			# refs/remotes/origin/HEAD is a symref at the default branch, and
			# git shortens it to a bare "origin" that cannot be checked out.
			# Dropped on the full refname rather than the short one, so a branch
			# someone really did name "origin" still completes.
			[[ $full == */HEAD ]] && continue
			short=${short#origin/}
			[[ -n $short ]] && names+=("$short")
		done
	done
	# (u) uniques, (o) sorts. Without the uniquing every branch arrives at least
	# twice -- once from refs/heads and once from refs/remotes/origin -- and
	# once more for every additional repo that has it.
	names=(${(uo)names})
	_describe -t branches 'branch' names
}

(( $+functions[compdef] )) && compdef _repo repo
