# shellcheck shell=bash
# Accounts and tokens for avanti and projects built with it (sourced by common.sh).
#
# Tokens live in one file, readable only by you: ${XDG_CONFIG_HOME:-~/.config}/avanti/secrets.env,
# as NAME=value lines. The file is parsed (never sourced) and only the names below are read;
# variables already set in the environment win. `avanti secrets setup` fills it interactively,
# `avanti secrets push OWNER/REPO` copies the tokens into a GitHub repository's Actions secrets.

AVANTI_SECRETS="${AVANTI_SECRETS:-${XDG_CONFIG_HOME:-$HOME/.config}/avanti/secrets.env}"

# name | who needs it | what it is for | where to get it | validation kind
AVANTI_SECRET_SPECS="CONTENTDB_TOKEN|maintainers|ContentDB releases (avanti cdb release, release workflows)|https://content.luanti.org/user/tokens/|contentdb
SKETCHFAB_TOKEN|contributors, optional|searching Sketchfab for models (sagas scout)|https://sketchfab.com/settings/password|sketchfab
SI_API_KEY|contributors, optional|searching the Smithsonian Open Access API (sagas scout)|https://api.data.gov/signup/|si"
AVANTI_SECRET_NAMES="CONTENTDB_TOKEN AVANTI_CONTENTDB_USER SKETCHFAB_TOKEN SI_API_KEY"

secrets_load() {
	[[ -f "$AVANTI_SECRETS" ]] || return 0
	local line name value
	while IFS= read -r line || [[ -n "$line" ]]; do
		[[ "$line" =~ ^([A-Z_][A-Z0-9_]*)=(.*)$ ]] || continue
		name="${BASH_REMATCH[1]}"
		value="${BASH_REMATCH[2]}"
		case " $AVANTI_SECRET_NAMES " in *" $name "*) ;; *) continue ;; esac
		[[ -n "${!name:-}" ]] && continue
		printf -v "$name" '%s' "$value"
		export "${name?}"
	done <"$AVANTI_SECRETS"
}

# secrets_store NAME VALUE: replace NAME in the file (created with mode 600).
secrets_store() {
	local name="$1" value="$2" dir tmp
	dir="$(dirname "$AVANTI_SECRETS")"
	mkdir -p "$dir"
	chmod 700 "$dir" 2>/dev/null || true
	tmp="$(mktemp "$dir/.secrets.XXXXXX")"
	chmod 600 "$tmp"
	if [[ -f "$AVANTI_SECRETS" ]]; then
		grep -v "^$name=" "$AVANTI_SECRETS" >"$tmp" || true
	fi
	printf '%s=%s\n' "$name" "$value" >>"$tmp"
	mv "$tmp" "$AVANTI_SECRETS"
}

# secrets_check KIND VALUE: 0 if the service accepts the token. Tokens go to curl through a
# config on stdin, so they never show up in the process list.
secrets_check() {
	local kind="$1" value="$2"
	case "$kind" in
	contentdb)
		curl -sS --fail -A "$CDB_USER_AGENT" -K - "$AVANTI_CONTENTDB_URL/api/whoami/" <<EOF | jq -e '.username' >/dev/null
header = "Authorization: Bearer $value"
EOF
		;;
	sketchfab)
		curl -sS --fail -A "$CDB_USER_AGENT" -o /dev/null -K - "https://api.sketchfab.com/v3/me" <<EOF
header = "Authorization: Token $value"
EOF
		;;
	si)
		curl -sS --fail -A "$CDB_USER_AGENT" -o /dev/null -K - <<EOF
url = "https://api.si.edu/openaccess/api/v1.0/stats?api_key=$value"
EOF
		;;
	*) return 0 ;;
	esac
}

secrets_open() {
	if [[ "$(uname -s)" == Darwin ]]; then open "$1" 2>/dev/null || true
	elif have xdg-open; then xdg-open "$1" >/dev/null 2>&1 || true
	fi
}

secrets_usage() {
	cat <<'EOF'
Usage: avanti secrets setup           Create accounts and paste tokens (opens the token pages)
       avanti secrets status [--quiet] Which tokens are set, and whether the services accept them
                                      (--quiet: no output; exit 0 only if all are set)
       avanti secrets push OWNER/REPO [--environment NAME]
                                      Copy the tokens into the repository's GitHub Actions secrets

Tokens are stored in ${XDG_CONFIG_HOME:-~/.config}/avanti/secrets.env (mode 600); environment
variables of the same name take precedence. Contributors usually only need SKETCHFAB_TOKEN
(scouting); maintainers who release need CONTENTDB_TOKEN. `push` puts CONTENTDB_TOKEN into a
deployment environment (default "contentdb") that requires your approval before every release.
EOF
}

secrets_setup() {
	local name who what url kind value reply current
	info "Accounts can't be created by a script; this opens each sign-up/token page and stores what you paste."
	info "Tokens go to $AVANTI_SECRETS (only you can read it)."
	while IFS='|' read -r name who what url kind; do
		current="${!name:-}"
		printf '\n%s%s%s (%s): %s\n' "$C_BOLD" "$name" "$C_OFF" "$who" "$what"
		if [[ -n "$current" ]]; then
			read -r -p "  already set; replace it? [y/N] " reply </dev/tty
			[[ "$reply" =~ ^[Yy] ]] || continue
		else
			read -r -p "  set it up now? [y/N] " reply </dev/tty
			[[ "$reply" =~ ^[Yy] ]] || continue
		fi
		echo "  Sign in (or create a free account), create a token, then paste it here."
		echo "  $url"
		secrets_open "$url"
		read -r -s -p "  $name (input hidden): " value </dev/tty
		echo
		[[ -n "$value" ]] || { echo "  skipped"; continue; }
		if secrets_check "$kind" "$value"; then
			echo "  ${C_GREEN}accepted${C_OFF}"
		else
			read -r -p "  the service did not accept it; store anyway? [y/N] " reply </dev/tty
			[[ "$reply" =~ ^[Yy] ]] || continue
		fi
		secrets_store "$name" "$value"
		printf -v "$name" '%s' "$value"
		if [[ "$name" == CONTENTDB_TOKEN ]]; then
			local user
			user="$(CONTENTDB_TOKEN="$value" cdb_whoami 2>/dev/null || true)"
			[[ -n "$user" ]] && secrets_store AVANTI_CONTENTDB_USER "$user" && echo "  ContentDB user: $user"
		fi
	done <<<"$AVANTI_SECRET_SPECS"
	if have gh && ! gh auth status >/dev/null 2>&1; then
		echo
		info "GitHub CLI is not logged in; run 'gh auth login' to push secrets or open pull requests."
	fi
	echo
	secrets_status
}

secrets_status() {
	local name who what url kind value state
	if [[ "${1:-}" == --quiet ]]; then # exit 0 if every token is set; no output, no network
		while IFS='|' read -r name _; do
			[[ -n "${!name:-}" ]] || return 1
		done <<<"$AVANTI_SECRET_SPECS"
		return 0
	fi
	while IFS='|' read -r name who what url kind; do
		value="${!name:-}"
		if [[ -z "$value" ]]; then
			state="${C_YELLOW}not set${C_OFF} ($who)"
		elif secrets_check "$kind" "$value" 2>/dev/null; then
			state="${C_GREEN}ok${C_OFF}"
		else
			state="${C_RED}rejected by the service${C_OFF}"
		fi
		printf '  %-22s %s\n' "$name" "$state"
	done <<<"$AVANTI_SECRET_SPECS"
	[[ -n "${AVANTI_CONTENTDB_USER:-}" ]] && printf '  %-22s %s\n' AVANTI_CONTENTDB_USER "$AVANTI_CONTENTDB_USER"
	printf '  file: %s\n' "$AVANTI_SECRETS"
}

secrets_push() {
	local repo="" envname="contentdb" uid
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--environment) envname="$2"; shift 2 ;;
		-h | --help) secrets_usage; return 0 ;;
		-*) die "unknown option $1" ;;
		*) repo="$1"; shift ;;
		esac
	done
	[[ "$repo" == */* ]] || die "usage: avanti secrets push OWNER/REPO [--environment NAME]"
	have gh || die "the GitHub CLI (gh) is required"
	gh auth status >/dev/null 2>&1 || die "run 'gh auth login' first"
	local name
	for name in SKETCHFAB_TOKEN SI_API_KEY; do
		if [[ -n "${!name:-}" ]]; then
			printf '%s' "${!name}" | gh secret set "$name" -R "$repo" >/dev/null && echo "  $name -> $repo"
		fi
	done
	if [[ -n "${CONTENTDB_TOKEN:-}" ]]; then
		uid="$(gh api user --jq .id)"
		jq -n --argjson id "$uid" '{reviewers: [{type: "User", id: $id}], deployment_branch_policy: null}' |
			gh api -X PUT "repos/$repo/environments/$envname" --input - >/dev/null
		printf '%s' "$CONTENTDB_TOKEN" | gh secret set CONTENTDB_TOKEN -R "$repo" --env "$envname" >/dev/null
		echo "  CONTENTDB_TOKEN -> $repo, environment $envname (releases wait for your approval)"
		if [[ -n "${AVANTI_CONTENTDB_USER:-}" ]]; then
			gh variable set CONTENTDB_USER -R "$repo" --body "$AVANTI_CONTENTDB_USER" >/dev/null
			echo "  CONTENTDB_USER = $AVANTI_CONTENTDB_USER (variable)"
		fi
	fi
}

cmd_secrets() {
	local sub="${1:-}"
	shift || true
	case "$sub" in
	setup) secrets_setup ;;
	status) secrets_status "$@" ;;
	push) secrets_push "$@" ;;
	-h | --help | help | "") secrets_usage ;;
	*) secrets_usage; exit 1 ;;
	esac
}

secrets_load
