# shellcheck shell=bash disable=SC2034  # variables are used by the scripts that source this
# Shared helpers for the avanti CLI. Sourced, not executed.

AVANTI_HOME="${AVANTI_HOME:-$HOME/.avanti}"
AVANTI_CORPUS="$AVANTI_HOME/corpus"
AVANTI_GAMES="$AVANTI_CORPUS/games"
AVANTI_ENGINE_SRC="$AVANTI_CORPUS/engine"
AVANTI_VENDOR="$AVANTI_CORPUS/vendor"
AVANTI_ENGINE_VERSION="${AVANTI_ENGINE_VERSION:-5.17.0}"
AVANTI_PLUGIN_ROOT="$(cd "$AVANTI_LIB/.." && pwd)"
export LDG_HOME="${LDG_HOME:-$AVANTI_HOME/depgraph}"
export LDG_CORPUS="${LDG_CORPUS:-$AVANTI_CORPUS/packages}"

if [[ -t 1 ]]; then
	C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_DIM=$'\e[2m' C_BOLD=$'\e[1m' C_OFF=$'\e[0m'
else
	C_RED="" C_GREEN="" C_YELLOW="" C_DIM="" C_BOLD="" C_OFF=""
fi

info() { printf '%s\n' "$*" >&2; }
note() { printf '%s%s%s\n' "$C_DIM" "$*" "$C_OFF" >&2; }
warn() { printf '%swarning:%s %s\n' "$C_YELLOW" "$C_OFF" "$*" >&2; }
die() {
	printf '%serror:%s %s\n' "$C_RED" "$C_OFF" "$*" >&2
	exit 1
}
have() { command -v "$1" >/dev/null 2>&1; }

# Lines of games.tsv without comments: "id folder source".
games_table() { grep -v '^#' "$AVANTI_LIB/games.tsv" | grep -v '^$'; }

game_field() { # game_field <id-or-folder> <column 1..3>
	games_table | awk -F'\t' -v g="$1" -v c="$2" '$1 == g || $2 == g { print $c; exit }'
}

# Directory of a synced game, or empty.
game_dir() {
	local folder source
	folder="$(game_field "$1" 2)"
	source="$(game_field "$1" 3)"
	[[ -n "$folder" ]] || return 0
	if [[ "$source" == engine:* ]]; then
		[[ -d "$AVANTI_ENGINE_SRC/${source#engine:}" ]] && echo "$AVANTI_ENGINE_SRC/${source#engine:}"
	else
		[[ -d "$AVANTI_GAMES/$folder" ]] && echo "$AVANTI_GAMES/$folder"
	fi
	return 0
}

# The game id the engine uses (folder name minus a trailing _game).
game_id() {
	local id
	id="$(game_field "$1" 1)"
	echo "${id:-$1}"
}

# Native engine binary: LUANTI_BIN, luantiserver, luanti, the macOS app, legacy names.
luanti_bin() {
	local candidate
	for candidate in "${LUANTI_BIN:-}" luantiserver luanti \
		/Applications/Luanti.app/Contents/MacOS/luanti minetestserver; do
		[[ -n "$candidate" ]] || continue
		if [[ -x "$candidate" ]]; then
			echo "$candidate"
			return 0
		elif have "$candidate"; then
			command -v "$candidate"
			return 0
		fi
	done
	return 1
}

luanti_version() { # luanti_version <binary> -> 5.17.0
	"$1" --version 2>/dev/null | awk 'NR == 1 { print $2 }'
}

version_lt() { # version_lt 5.10.0 5.11.0 -> true
	[[ "$1" != "$2" ]] && [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" == "$1" ]]
}

# Official server image for an engine version (images before 5.11 live under minetest/).
engine_image() {
	if version_lt "$1" "5.11.0"; then
		echo "ghcr.io/minetest/minetest:$1"
	else
		echo "ghcr.io/luanti-org/luanti:$1"
	fi
}

docker_ready() { have docker && docker info >/dev/null 2>&1; }

# run_with_timeout <seconds> <cmd...>: coreutils timeout if present, else perl alarm.
run_with_timeout() {
	local seconds="$1"
	shift
	if have timeout; then
		timeout "$seconds" "$@"
	elif have gtimeout; then
		gtimeout "$seconds" "$@"
	else
		perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "$seconds" "$@"
	fi
}

json_escape() { python3 -c 'import json, sys; print(json.dumps(sys.stdin.read().rstrip("\n")))'; }
