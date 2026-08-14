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
# --- Why this one file is in common/ -----------------------------------------
#
# Everything below is git, gh and bash builtins. None of it is OS-specific, so
# by this repo's own test it belongs here rather than in a zone -- and it is
# byte-identical on archlinux and debian, which is the condition for staying.
# Each zone's .bashrc sources it from ~/.bashrc.repo, the same include pattern
# .tmux.conf and .gitconfig already use.
#
# The zones' .bashrc files are NOT shared and this is not a step toward that.
# They agree on far more than one function -- aliases, e(), ts() -- and are
# still separate copies on purpose. This file is one function that happens to
# be identical, not the shared half of a bashrc.
#
# $REPO_OPEN is the one thing the two zones disagree about: what to launch on
# the review clone once a PR is checked out. Arch opens VS Code; debian is a
# text console and opens the editor it has. That is set by the zone before
# sourcing this, so no OS conditional lives in here -- and it is checked with
# command -v before it runs, so an arch box without VS Code installed still
# does the checkout instead of erroring on the last line.
#
# Ports of this exist in windows/config/Microsoft.PowerShell_profile.ps1 and
# mac/config/.zshrc. Like every other config living in more than one zone they
# are separate copies -- PowerShell and zsh cannot read this file -- so a change
# here does not arrive there.

# Colours as plain ANSI. 90 is bright black, which is what PowerShell's DarkGray
# renders as.
_repo_key=$'\e[36m'     ; _repo_red=$'\e[31m'   ; _repo_yellow=$'\e[33m'
_repo_magenta=$'\e[35m' ; _repo_green=$'\e[32m' ; _repo_dim=$'\e[90m'
_repo_off=$'\e[0m'

# One directory holding a permanent clone of every repo ever reviewed, named
# <owner>-<repo>. Deliberately separate from the clones under source/repos, and
# deliberately duplicated: the disk is worth less than never having to think
# about which working tree a review is about to disturb.
#
# Not /tmp -- systemd-tmpfiles clears that on a schedule, and these are meant to
# outlive every review that uses them.
_repo_prroot="$HOME/.prs"

# What to open the review clone with. The zone sets this; empty means the
# checkout happens and nothing is launched.
: "${REPO_OPEN:=}"

repo() {
	local a forced=''
	local -a rest=()

	# Help wins wherever it appears, so `repo develop --help` answers with help
	# instead of checking out develop. The implementations below carry no help
	# of their own -- there is one help, and this is what reaches it.
	for a in "$@"; do
		case ${a,,} in
			-h|--h|-help|--help) _repo_help; return 0 ;;
		esac
	done

	# Both spellings are accepted. -List and -Branch are what the PowerShell
	# copy takes, and typing one here after a day on the other should not fail.
	while (( $# )); do
		case ${1,,} in
			-l|-list|--list)
				_repo_list
				return $?
				;;
			# The escape hatch for the one case the shape rule gets wrong: a
			# branch actually named with digits. It is the only thing here you
			# will never type.
			-b|-branch|--branch)
				if [ -z "$2" ]; then
					printf '%srepo: -b needs a branch name%s\n' "$_repo_red" "$_repo_off" >&2
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

	[ -n "$forced" ] && { _repo_pull "$forced"; return $?; }
	(( ${#rest[@]} )) || { _repo_pull; return $?; }

	# The shape rule. zsh spells "any run of digits" as a glob and PowerShell as
	# -match; bash has neither, so it is a regex here and the URL case stays a
	# glob so the two do not have to agree on escaping.
	case ${rest[0]} in
		http://*|https://*) _repo_pr "${rest[0]}"; return $? ;;
	esac
	if [[ ${rest[0]} =~ ^#?[0-9]+$ ]]; then
		_repo_pr "${rest[0]}"
	else
		_repo_pull "${rest[0]}"
	fi
}

_repo_help() {
	local k=$_repo_key o=$_repo_off d=$_repo_dim y=$_repo_yellow
	printf '\n'
	printf '  %srepo%s -- one word for every git repo below here. There is no second word.\n' "$k" "$o"
	printf '\n'
	printf '    %srepo%s             where they all stand. No network, changes nothing.\n' "$k" "$o"
	printf '    %srepo <branch>%s    checkout <branch> and pull, in every repo that has it\n' "$k" "$o"
	printf '    %srepo <number>%s    review that PR of the repo you are standing in\n' "$k" "$o"
	printf '    %srepo <url>%s       review that PR, any repo\n' "$k" "$o"
	printf '    %srepo -l%s          every review clone, what it is on, and where\n' "$k" "$o"
	printf '\n'
	printf '  Digits and URLs are pull requests, anything else is a branch. So there\n'
	printf '  is nothing to remember past the word itself, and %srepo <tab>%s completes\n' "$k" "$o"
	printf '  branch names across every repo below here.\n'
	printf '\n'
	printf '  %sBranches.%s Repos are found at depth 1 and 2, so this works from the folder\n' "$k" "$o"
	printf '  holding your project folders as well as from inside one. A repo is skipped\n'
	printf '  when it has tracked changes, is on a detached HEAD, or has no such branch.\n'
	printf '  Untracked files block nothing.\n'
	printf '\n'
	printf '  %sReviews.%s Each repo clones once to %s/<owner>-<repo> and stays,\n' "$k" "$o" "$_repo_prroot"
	printf '  so the clones you actually work in are never touched and never need stashing.\n'
	printf '\n'
	printf '  %sThe review tree is not yours.%s Tracked changes there are discarded on every\n' "$y" "$o"
	printf '  checkout, so leave nothing in one. Untracked files survive on purpose:\n'
	printf '  node_modules and obj carry over, so the second review skips the rebuild.\n'
	printf '\n'
	printf '    %sgit diff origin/<base>...HEAD%s    what the author changed; three dots\n' "$k" "$o"
	printf '                                     exclude what landed on base since\n'
	printf '    %sgh pr diff <number>%s          read one without cloning at all\n' "$k" "$o"
	printf '\n'
	printf '  %s-b <name> forces the branch reading, for a branch actually named\n' "$d"
	printf '  with digits -- the one case the shape rule gets wrong.%s\n' "$o"
	printf '\n'
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
_repo_pr() {
	local ref=$1 slug num base title author clone meta re

	# Resolve to owner/repo plus number. A bare number means the repo we are
	# standing in, which is the same thing gh assumes when given no --repo.
	#
	# The pattern goes through a variable rather than sitting inline: bash quotes
	# the right-hand side of =~ as a literal string the moment any of it is
	# quoted, and a variable is the one form that is unambiguously a regex.
	#
	# No lazy quantifier for the optional .git -- this is ERE, not PCRE, so the
	# suffix comes off with a parameter expansion instead.
	re='^https?://[^/]+/([^/]+)/([^/]+)/pull/([0-9]+)'
	if [[ $ref =~ $re ]]; then
		slug="${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"
		num="${BASH_REMATCH[3]}"
	elif [[ $ref =~ ^#?([0-9]+)$ ]]; then
		num="${BASH_REMATCH[1]}"
		slug=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
		if [ -z "$slug" ]; then
			printf '%sNot inside a GitHub repo -- pass the full PR URL.%s\n' \
				"$_repo_red" "$_repo_off" >&2
			return 1
		fi
	else
		printf "%sCould not read '%s' as a PR URL or number -- see repo --help%s\n" \
			"$_repo_red" "$ref" "$_repo_off" >&2
		return 1
	fi

	# One round trip for all three fields. gh has jq built in, so @tsv here
	# costs nothing and saves two more calls; jq escapes any tab inside a title.
	meta=$(gh pr view "$num" --repo "$slug" --json baseRefName,title,author \
		-q '[.baseRefName, .title, .author.login] | @tsv' 2>/dev/null)
	if [ -z "$meta" ]; then
		printf '%sCould not read %s#%s -- is gh authenticated for that host?%s\n' \
			"$_repo_red" "$slug" "$num" "$_repo_off" >&2
		return 1
	fi
	IFS=$'\t' read -r base title author <<< "$meta"

	clone="$_repo_prroot/${slug//\//-}"

	# No mkdir -p for $_repo_prroot: git clone creates the leading directories
	# of its destination itself.
	if [ ! -d "$clone" ]; then
		printf 'First review of %s -- cloning to %s\n' "$slug" "$clone"
		if ! gh repo clone "$slug" "$clone"; then
			printf '%sClone of %s failed.%s\n' "$_repo_red" "$slug" "$_repo_off" >&2
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
	if ! git -C "$clone" fetch --quiet origin \
		"+refs/pull/$num/head:refs/remotes/origin/pr/$num" \
		"+refs/heads/$base:refs/remotes/origin/$base"; then
		printf '%sCould not fetch %s#%s.%s\n' "$_repo_red" "$slug" "$num" "$_repo_off" >&2
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
		printf '%sCould not check out %s#%s.%s\n' "$_repo_red" "$slug" "$num" "$_repo_off" >&2
		return 1
	fi

	printf '\n'
	printf '  %s#%s  %s\n' "$slug" "$num" "$title"
	printf '  by %s into %s\n' "$author" "$base"
	printf '\n'
	# Three dots, not two: it diffs from the merge base, so the review shows what
	# the author changed and not whatever landed on base in the meantime.
	printf '  %sgit diff origin/%s...HEAD%s\n' "$_repo_key" "$base" "$_repo_off"
	printf '\n'

	builtin cd -- "$clone" || return 1

	# The checkout is the point and it has already happened, so a missing or
	# unset $REPO_OPEN is not a failure -- you are simply standing in the tree.
	if [ -n "$REPO_OPEN" ] && command -v "$REPO_OPEN" >/dev/null 2>&1; then
		"$REPO_OPEN" "$clone"
	fi
	return 0
}

_repo_list() {
	if [ ! -d "$_repo_prroot" ]; then
		printf 'No review clones yet.\n'
		return 0
	fi

	local -a clones=()
	local c n at glob w=0 pw=0 cols room

	# nullglob so an empty $_repo_prroot yields no entries rather than the
	# literal pattern, and restored afterwards because this runs in the
	# interactive shell and the setting is not ours to keep.
	glob=$(shopt -p nullglob)
	shopt -s nullglob
	for c in "$_repo_prroot"/*/; do
		clones+=("${c%/}")
	done
	eval "$glob"

	if (( ${#clones[@]} == 0 )); then
		printf 'No review clones yet.\n'
		return 0
	fi

	# The path is the one column that has to stay complete enough to copy, so
	# it must never be what gets truncated. Give the name and the path their
	# full width and hand whatever is left to the subject.
	#
	# Through $n rather than ${#c##*/}: bash does not nest a length with a
	# substitution the way zsh's ${#${c:t}} does, and says "bad substitution".
	for c in "${clones[@]}"; do
		n=${c##*/}
		(( ${#n} > w ))  && w=${#n}
		(( ${#c} > pw )) && pw=${#c}
	done

	cols=${COLUMNS:-120}
	(( cols < 40 )) && cols=120
	room=$(( cols - w - pw - 6 ))

	for c in "${clones[@]}"; do
		at=$(git -C "$c" log -1 --format='%h %s' 2>/dev/null)
		if (( room < 8 )); then
			printf '  %-*s  %s\n' "$w" "${c##*/}" "$c"
		else
			(( ${#at} > room )) && at="${at:0:room-3}..."
			printf '  %-*s  %-*s  %s\n' "$w" "${c##*/}" "$room" "$at" "$c"
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
# The trailing slash on the glob is what restricts it to directories, and it
# follows symlinks -- so a repo reached through a symlinked directory is still
# found. Leading dots are not matched, which is also what keeps .git itself out
# of the walk.
_repo_found=()
_repo_find() {
	local d s glob
	_repo_found=()

	glob=$(shopt -p nullglob)
	shopt -s nullglob
	for d in */; do
		d=${d%/}
		if [ -e "$d/.git" ]; then
			_repo_found+=("$PWD/$d")
			continue
		fi
		for s in "$d"/*/; do
			s=${s%/}
			[ -e "$s/.git" ] && _repo_found+=("$PWD/$s")
		done
	done
	eval "$glob"
}

# Read one repo's local state into the globals below. Deliberately no network:
# branch name and dirtiness both come off disk, so the bare `repo` view over 20
# repos costs milliseconds. --untracked-files=normal stops git recursing into
# untracked directories, which is what makes this fast in a repo carrying
# node_modules or obj.
_repo_state() {
	local dir=$1 out line

	_repo_branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
	[ -n "$_repo_branch" ] || _repo_branch='?'
	if [ "$_repo_branch" = HEAD ]; then _repo_detached=1; else _repo_detached=0; fi

	out=$(git -C "$dir" status --porcelain --untracked-files=normal 2>/dev/null)

	# Untracked and modified are counted separately on purpose. Untracked files
	# are permanent residents of half these repos (build output, node_modules)
	# and must not make a repo look dirty -- only tracked changes block a
	# checkout, so only tracked changes cause a skip.
	#
	# '??' is quoted so it matches two literal question marks. Unquoted, ? is a
	# single-character wildcard in a case pattern exactly as it is in
	# PowerShell's -like, and every status line would count as untracked.
	#
	# Counted with an explicit if rather than `[[ ... ]] && (( n++ )) || (( m++ ))`:
	# post-increment evaluates to the value *before* the increment, so the first
	# untracked file would make the arithmetic return 0, bash would read that as
	# false, and the || arm would count the same line a second time.
	_repo_untracked=0
	_repo_tracked=0
	if [ -n "$out" ]; then
		while IFS= read -r line; do
			case $line in
				'??'*) _repo_untracked=$(( _repo_untracked + 1 )) ;;
				*)     _repo_tracked=$(( _repo_tracked + 1 )) ;;
			esac
		done <<< "$out"
	fi
}

# Colour by what you would have to do about it, not by severity:
#   red     tracked changes -- blocks a checkout, needs you
#   yellow  untracked only  -- harmless, but worth seeing
#   magenta detached HEAD   -- not on a branch at all
#   green   clean
_repo_color() {
	if   (( _repo_detached ));      then printf '%s' "$_repo_magenta"
	elif (( _repo_tracked > 0 ));   then printf '%s' "$_repo_red"
	elif (( _repo_untracked > 0 )); then printf '%s' "$_repo_yellow"
	else                                 printf '%s' "$_repo_green"
	fi
}

# Joined by hand rather than through an array and IFS: bash's "${bits[*]}" uses
# only the FIRST character of IFS as the separator, so the ", " that zsh's
# ${(j:, :)bits} produces would come out as a bare comma here.
_repo_note() {
	if (( _repo_detached )); then printf 'detached'; return 0; fi
	local out=''
	(( _repo_tracked > 0 )) && out="$_repo_tracked changed"
	if (( _repo_untracked > 0 )); then
		[ -n "$out" ] && out="$out, "
		out="$out$_repo_untracked untracked"
	fi
	[ -n "$out" ] || out='clean'
	printf '%s' "$out"
}

# Show every repo below here, or move them all onto a branch.
#
# There is no fallback between branch names. Asking for develop in a repo that
# only has main is a skip with a reason, not a silent switch to something else
# -- guessing is how you end up on a branch you did not intend across 20 repos
# and cannot tell which.
_repo_pull() {
	local branch=$1

	_repo_find
	local -a repos=("${_repo_found[@]}")
	if (( ${#repos[@]} == 0 )); then
		printf '%sNo git repos found below here.%s\n' "$_repo_yellow" "$_repo_off"
		return 1
	fi

	local r name w=0
	for r in "${repos[@]}"; do
		name=${r##*/}
		(( ${#name} > w )) && w=${#name}
	done

	#-- status only ----------------------------------------------------------
	if [ -z "$branch" ]; then
		printf '\n'
		for r in "${repos[@]}"; do
			_repo_state "$r"
			printf '  %-*s  ' "$w" "${r##*/}"
			printf '%s%-22s%s' "$_repo_key" "$_repo_branch" "$_repo_off"
			printf '%s%s%s\n' "$(_repo_color)" "$(_repo_note)" "$_repo_off"
		done
		printf '\n'
		printf '  %s%d repo(s). Nothing was changed.%s\n' \
			"$_repo_dim" "${#repos[@]}" "$_repo_off"

		# The footer is the whole discoverability fix, so it hangs off bare
		# `repo` -- the one form reached without thinking -- rather than off
		# --help, which is exactly the thing nobody types when they have already
		# forgotten there was something to ask about.
		printf '  %srepo <branch> to move them  |  repo <number|url> to review a PR  |  repo --help%s\n' \
			"$_repo_dim" "$_repo_off"
		printf '\n'
		return 0
	fi

	#-- checkout and pull ----------------------------------------------------
	local -a rep_name=() rep_was=() rep_now=() rep_result=()
	local was now before after has_local has_remote pull_ok i

	for r in "${repos[@]}"; do
		name=${r##*/}
		_repo_state "$r"
		was=$_repo_branch

		printf '  %-*s  ' "$w" "$name"

		if (( _repo_tracked > 0 )); then
			printf '%sskipped -- %d tracked change(s)%s\n' \
				"$_repo_red" "$_repo_tracked" "$_repo_off"
			rep_name+=("$name"); rep_was+=("$was"); rep_now+=("$was"); rep_result+=('skipped: dirty')
			continue
		fi

		if (( _repo_detached )); then
			printf '%sskipped -- detached HEAD%s\n' "$_repo_magenta" "$_repo_off"
			rep_name+=("$name"); rep_was+=('(detached)'); rep_now+=('(detached)'); rep_result+=('skipped: detached')
			continue
		fi

		# Fetch before deciding whether the branch exists. A repo cloned when it
		# only had master has no refs/remotes/origin/develop until something
		# fetches, so checking first would report "no such branch" for a branch
		# that is plainly on the server. The network cost is already being paid
		# by the pull below.
		git -C "$r" fetch --quiet origin 2>/dev/null

		has_local=0; has_remote=0
		git -C "$r" rev-parse --verify --quiet "refs/heads/$branch" >/dev/null 2>&1 && has_local=1
		git -C "$r" rev-parse --verify --quiet "refs/remotes/origin/$branch" >/dev/null 2>&1 && has_remote=1

		if (( ! has_local && ! has_remote )); then
			printf "%sskipped -- no '%s' branch%s\n" "$_repo_dim" "$branch" "$_repo_off"
			rep_name+=("$name"); rep_was+=("$was"); rep_now+=("$was"); rep_result+=("skipped: no $branch")
			continue
		fi

		if [ "$was" != "$branch" ]; then
			if ! git -C "$r" checkout --quiet "$branch" 2>/dev/null; then
				printf '%sFAILED -- could not check out %s%s\n' "$_repo_red" "$branch" "$_repo_off"
				rep_name+=("$name"); rep_was+=("$was"); rep_now+=("$was"); rep_result+=('failed: checkout')
				continue
			fi
		fi

		before=$(git -C "$r" rev-parse --short HEAD 2>/dev/null)
		pull_ok=1
		git -C "$r" pull >/dev/null 2>&1 || pull_ok=0
		after=$(git -C "$r" rev-parse --short HEAD 2>/dev/null)
		now=$(git -C "$r" rev-parse --abbrev-ref HEAD 2>/dev/null)

		if (( ! pull_ok )); then
			# The common cause is a diverged branch: local commits on $branch
			# that were never pushed. git refuses rather than merging, which is
			# the right outcome -- that repo needs a human, not a bulk tool.
			printf '%sFAILED -- pull refused (diverged?)%s\n' "$_repo_red" "$_repo_off"
			rep_name+=("$name"); rep_was+=("$was"); rep_now+=("$now"); rep_result+=('failed: pull')
		elif [ "$before" = "$after" ]; then
			printf '%s%s -> %s  already current%s\n' "$_repo_dim" "$was" "$now" "$_repo_off"
			rep_name+=("$name"); rep_was+=("$was"); rep_now+=("$now"); rep_result+=('already current')
		else
			printf '%s%s -> %s  updated %s..%s%s\n' \
				"$_repo_green" "$was" "$now" "$before" "$after" "$_repo_off"
			rep_name+=("$name"); rep_was+=("$was"); rep_now+=("$now"); rep_result+=("updated $before..$after")
		fi
	done

	printf '\n'
	printf '  %s---- report ----%s\n' "$_repo_key" "$_repo_off"

	local nw=4 ww=3 aw=3
	for (( i = 0; i < ${#rep_name[@]}; i++ )); do
		(( ${#rep_name[i]} > nw )) && nw=${#rep_name[i]}
		(( ${#rep_was[i]}  > ww )) && ww=${#rep_was[i]}
		(( ${#rep_now[i]}  > aw )) && aw=${#rep_now[i]}
	done
	printf '  %-*s  %-*s  %-*s  %s\n' "$nw" 'Repo' "$ww" 'Was' "$aw" 'Now' 'Result'
	printf '  %-*s  %-*s  %-*s  %s\n' "$nw" '----' "$ww" '---' "$aw" '---' '------'
	for (( i = 0; i < ${#rep_name[@]}; i++ )); do
		printf '  %-*s  %-*s  %-*s  %s\n' \
			"$nw" "${rep_name[i]}" "$ww" "${rep_was[i]}" "$aw" "${rep_now[i]}" "${rep_result[i]}"
	done

	local updated=0 skipped=0 failed=0
	for i in "${rep_result[@]}"; do
		case $i in
			updated*) updated=$(( updated + 1 )) ;;
			skipped*) skipped=$(( skipped + 1 )) ;;
			failed*)  failed=$(( failed + 1 )) ;;
		esac
	done
	printf '\n'
	printf '  %s%d updated, %d skipped, %d failed, %d total%s\n' \
		"$_repo_dim" "$updated" "$skipped" "$failed" "${#rep_name[@]}" "$_repo_off"
	printf '\n'
}

# Branch names, deduped across every repo below here. This is the only
# completion worth having now that there are no verbs to enumerate: the
# argument is a branch name nearly every time, and completing it means even
# that does not have to be remembered.
_repo_complete() {
	local cur=${COMP_WORDS[COMP_CWORD]}
	local r line full short
	local -a names=()

	# Only the first word after `repo` is ever a branch name.
	(( COMP_CWORD > 1 )) && return 0

	_repo_find
	for r in "${_repo_found[@]}"; do
		while IFS= read -r line; do
			full=${line%%|*}
			short=${line#*|}
			# refs/remotes/origin/HEAD is a symref at the default branch, and
			# git shortens it to a bare "origin" that cannot be checked out.
			# Dropped on the full refname rather than the short one, so a branch
			# someone really did name "origin" still completes.
			[[ $full == */HEAD ]] && continue
			short=${short#origin/}
			[ -n "$short" ] && names+=("$short")
		done < <(git -C "$r" for-each-ref \
			--format='%(refname)|%(refname:short)' refs/heads refs/remotes/origin 2>/dev/null)
	done
	(( ${#names[@]} )) || return 0

	# sort -u rather than a shell loop: without the uniquing every branch
	# arrives at least twice -- once from refs/heads and once from
	# refs/remotes/origin -- and once more for every additional repo that has
	# it. Splitting on newlines alone is safe because git refuses to create a
	# ref containing whitespace.
	local IFS=$'\n'
	mapfile -t COMPREPLY < <(compgen -W "$(printf '%s\n' "${names[@]}" | sort -u)" -- "$cur")
	return 0
}

complete -F _repo_complete repo
