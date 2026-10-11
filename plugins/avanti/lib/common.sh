# shellcheck shell=bash disable=SC2034  # variables are used by the scripts that source this
# Shared helpers for the avanti CLI. Sourced, not executed.

AVANTI_HOME="${AVANTI_HOME:-$HOME/.avanti}"
AVANTI_CORPUS="$AVANTI_HOME/corpus"
AVANTI_GAMES="$AVANTI_CORPUS/games"
AVANTI_ENGINE_SRC="$AVANTI_CORPUS/engine"
AVANTI_VENDOR="$AVANTI_CORPUS/vendor"
# Text-only mirror of the corpus without .git, indexed by zvec-grep (which skips nested git repos).
AVANTI_SEARCH="$AVANTI_HOME/search"
AVANTI_ENGINE_VERSION="${AVANTI_ENGINE_VERSION:-5.17.0}"
AVANTI_PLUGIN_ROOT="$(cd "$AVANTI_LIB/.." && pwd)"
# ldg keeps its database in its own home (LDG_HOME, default ~/.local/share/luanti-depgraph),
# shared with every other ldg user on this machine. Only the package sources avanti fetches
# for search go into the avanti corpus.
AVANTI_PACKAGES="$AVANTI_CORPUS/packages"

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

# ContentDB API. Identify ourselves and stay polite: no crawling, bulk data comes from ldg.
AVANTI_CONTENTDB_URL="${AVANTI_CONTENTDB_URL:-https://content.luanti.org}"
CDB_USER_AGENT="avanti (+https://github.com/culmat/avanti-luanti)"

# cdb_request <method> <path> [json-body]: prints the response body, fails on HTTP errors.
# With CDB_AUTH=1 the token goes in through a curl config on stdin (a heredoc), so it shows up
# neither in the process list nor in xtrace output.
cdb_request() {
	local method="$1" path="$2" body="${3:-}"
	local args=(-sS --fail-with-body -X "$method" -A "$CDB_USER_AGENT" -H 'Accept: application/json')
	[[ -n "$body" ]] && args+=(-H 'Content-Type: application/json' --data-binary "$body")
	if [[ "${CDB_AUTH:-0}" -eq 1 ]]; then
		[[ -n "${CONTENTDB_TOKEN:+set}" ]] ||
			die "CONTENTDB_TOKEN is not set: create a token scoped to the package at $AVANTI_CONTENTDB_URL/user/tokens/"
		curl "${args[@]}" -K - "$AVANTI_CONTENTDB_URL$path" <<EOF
header = "Authorization: Bearer $CONTENTDB_TOKEN"
EOF
	else
		curl "${args[@]}" "$AVANTI_CONTENTDB_URL$path"
	fi
}
cdb_get() { cdb_request GET "$1"; }

# cdb_upload <path> <zip> <title> [notes-file]: create a release from a zip (multipart form) and print
# the response body. The token goes in through a curl config on stdin, like cdb_request.
cdb_upload() {
	local path="$1" zip="$2" title="$3" notes="${4:-}"
	local args=(-sS --fail-with-body -X POST -A "$CDB_USER_AGENT" -H 'Accept: application/json'
		-F "title=$title" -F "file=@$zip;type=application/zip")
	[[ -n "$notes" ]] && args+=(-F "release_notes=<$notes")
	[[ -n "${CONTENTDB_TOKEN:+set}" ]] ||
		die "CONTENTDB_TOKEN is not set: create a token scoped to the package at $AVANTI_CONTENTDB_URL/user/tokens/"
	curl "${args[@]}" -K - "$AVANTI_CONTENTDB_URL$path" <<CURLCONFIG
header = "Authorization: Bearer $CONTENTDB_TOKEN"
CURLCONFIG
}

# Accounts and tokens (avanti secrets); loads the secrets file into the environment.
# shellcheck source=secrets.sh
source "$(dirname "${BASH_SOURCE[0]}")/secrets.sh"
