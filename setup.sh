#!/usr/bin/env bash
# setup.sh: set up an avanti-luanti workstation (macOS with Homebrew, or Linux). Safe to re-run.
#
#   ./setup.sh             full setup: tools, ldg, games, corpus (top 300 packages), search index, plugin
#   ./setup.sh --minimal   tools, ldg, games and plugin only (no package corpus, no index)
#   ./setup.sh --dev       install the Claude Code plugin from this checkout instead of GitHub
#   ./setup.sh --top N     corpus size (packages with sources fetched for analysis and search)
#   ./setup.sh --yes       don't ask before installing the Luanti app
#   ./setup.sh --secrets   also set up accounts and tokens (ContentDB, Sketchfab, Smithsonian)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP=300 MINIMAL=0 DEV=0 YES=0 SECRETS=0
LDG_SOURCE="${LDG_SOURCE:-luanti-depgraph[search] @ git+https://github.com/culmat/luanti-depgraph}"

while [[ $# -gt 0 ]]; do
	case "$1" in
	--minimal) MINIMAL=1 ;;
	--dev) DEV=1 ;;
	--yes | -y) YES=1 ;;
	--secrets) SECRETS=1 ;;
	--top) TOP="$2"; shift ;;
	-h | --help) sed -n '2,10p' "$0"; exit 0 ;;
	*) echo "unknown option $1" >&2; exit 1 ;;
	esac
	shift
done

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
# The startup file your login shell reads, for PATH additions.
shell_rc() {
	case "${SHELL##*/}" in
	zsh) echo "$HOME/.zshrc" ;;
	bash) if [[ "$(uname -s)" == Darwin ]]; then echo "$HOME/.bash_profile"; else echo "$HOME/.bashrc"; fi ;;
	*) echo "$HOME/.profile" ;;
	esac
}
# path_add DIR WHY: offer to put DIR on your PATH in your shell's startup file.
path_add() {
	local dir="$1" why="$2" rc short line
	case ":$USER_PATH:" in *":$dir:"*) return 0 ;; esac
	rc="$(shell_rc)" short="${dir/#$HOME/\$HOME}"
	line="export PATH=\"$short:\$PATH\""
	if [[ -f "$rc" ]] && grep -qF "$line" "$rc"; then
		echo "ok  $dir is on PATH in $rc"
		USER_PATH="$dir:$USER_PATH" NEW_TERMINAL="$rc"
	elif ask "$dir ($why) is not on your PATH. Add it in $rc?"; then
		printf '\n# added by avanti-luanti setup.sh\n%s\n' "$line" >>"$rc"
		echo "added to $rc"
		USER_PATH="$dir:$USER_PATH" NEW_TERMINAL="$rc"
	else
		echo "add to $rc yourself: $line"
	fi
}
ask() { [[ $YES -eq 1 ]] && return 0; read -r -p "$1 [Y/n] " reply; [[ -z "$reply" || "$reply" =~ ^[Yy] ]]; }

OS="$(uname -s)"
# PATH as your shell has it; the final doctor runs with it, so it reports what you will see.
USER_PATH="$PATH" NEW_TERMINAL=""

step "System tools"
if [[ "$OS" == Darwin ]]; then
	have brew || { echo "Homebrew is required: https://brew.sh" >&2; exit 1; }
	for formula in git jq uv node luajit lua-language-server luarocks stylua; do
		if brew list --formula "$formula" >/dev/null 2>&1 || have "$formula"; then
			echo "ok  $formula"
		else
			brew install "$formula"
		fi
	done
else
	missing=()
	for tool in git jq curl perl rsync; do have "$tool" || missing+=("$tool"); done
	if [[ ${#missing[@]} -gt 0 ]]; then
		echo "Please install: ${missing[*]} (e.g. sudo apt install ${missing[*]})" >&2
		exit 1
	fi
	have uv || curl -LsSf https://astral.sh/uv/install.sh | sh
	for tool in node luarocks stylua lua-language-server; do
		have "$tool" || echo "optional: $tool not found (see README for install hints)"
	done
fi
# luacheck 1.2.0 doesn't run on Lua 5.5 (Homebrew's default for luarocks), so build it for
# LuaJIT, the Lua 5.1 dialect Luanti itself uses.
export PATH="$HOME/.luarocks/bin:$PATH"
if have luarocks && ! luacheck --version >/dev/null 2>&1; then
	if [[ "$OS" == Darwin ]]; then
		luarocks --lua-version=5.1 --lua-dir="$(brew --prefix luajit)" install --local luacheck
	else
		luarocks --lua-version=5.1 install --local luacheck
	fi
fi
[[ -x "$HOME/.luarocks/bin/luacheck" ]] && path_add "$HOME/.luarocks/bin" "luacheck"

step "Luanti engine (native, for fast local tests)"
if [[ "$OS" == Darwin ]]; then
	if [[ -x /Applications/Luanti.app/Contents/MacOS/luanti ]] || have luantiserver; then
		echo "ok  Luanti"
	elif ask "Install the Luanti app (brew install --cask luanti)?"; then
		brew install --cask luanti
	fi
else
	have luantiserver || have luanti || echo "Install luantiserver (flatpak/PPA) or use Docker: avanti test --runner docker"
fi

step "luanti-depgraph (ldg)"
uv tool install --quiet --upgrade --force "$LDG_SOURCE"
echo "ok  ldg $("$HOME/.local/bin/ldg" version 2>/dev/null || true)"
mkdir -p "$HOME/.local/bin"
ln -sf "$REPO/plugins/avanti/bin/avanti" "$HOME/.local/bin/avanti"
path_add "$HOME/.local/bin" "avanti, ldg"
export PATH="$HOME/.local/bin:$HOME/.luarocks/bin:$PATH"

step "zvec-grep (local semantic code search)"
if have node && [[ "$(node -p 'process.versions.node.split(".")[0]')" -ge 22 ]]; then
	have zg || npm install -g @zvec/zvec-grep
	echo "ok  zg $(zg --version 2>/dev/null | head -1)"
else
	echo "Node 22+ is needed for zvec-grep; skipping"
fi

step "Dependency database and code search index"
if ! ldg update; then
	echo "No published snapshot reachable; building from ContentDB (about a minute)"
	ldg build
fi
ldg code update || echo "No published code index; run 'ldg code index' after 'avanti corpus sync'"

step "Reference games and corpus"
if [[ $MINIMAL -eq 1 ]]; then
	avanti games sync
else
	avanti corpus sync --top "$TOP"
fi

step "Docker images (optional, for the engine matrix)"
if have docker && docker info >/dev/null 2>&1; then
	docker pull --quiet ghcr.io/luanti-org/luanti:5.17.0 || true
else
	echo "docker not running; skipping (native tests still work)"
fi

step "Claude Code plugin"
if have claude; then
	if [[ $DEV -eq 1 ]]; then
		claude plugin marketplace add "$REPO" || true
	else
		claude plugin marketplace add culmat/avanti-luanti || true
	fi
	# install is a no-op when the plugin is already installed; update brings it to the latest version
	claude plugin install avanti@avanti-luanti || true
	claude plugin update avanti@avanti-luanti || true
	claude plugin install lua-lsp@claude-plugins-official || true
else
	echo "Claude Code CLI not found; install it from https://code.claude.com, then re-run."
fi

step "Accounts and tokens (optional)"
echo "Contributors: SKETCHFAB_TOKEN and SI_API_KEY let 'sagas scout' search more model sources."
echo "Maintainers: CONTENTDB_TOKEN releases packages; 'avanti secrets push OWNER/REPO' hands tokens to CI."
if [[ $SECRETS -eq 0 ]] && avanti secrets status --quiet; then
	echo "ok  all tokens set ('avanti secrets status' checks them with the services)"
elif [[ $SECRETS -eq 1 ]] || { [[ $YES -eq 0 && -t 0 ]] && ask "Set up accounts and tokens now?"; }; then
	avanti secrets setup
else
	echo "skipped; run 'avanti secrets setup' any time"
fi

step "Doctor"
PATH="$USER_PATH" "$REPO/plugins/avanti/bin/avanti" doctor
if [[ -n "$NEW_TERMINAL" ]]; then
	printf '\n\033[1mThis terminal has the old PATH: open a new terminal, or run: source %s\033[0m\n' "$NEW_TERMINAL"
fi
