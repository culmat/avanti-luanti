#!/usr/bin/env bash
# setup.sh: set up an avanti-luanti workstation (macOS with Homebrew, or Linux). Safe to re-run.
#
#   ./setup.sh             full setup: tools, ldg, games, corpus (top 300 packages), search index, plugin
#   ./setup.sh --minimal   tools, ldg, games and plugin only (no package corpus, no index)
#   ./setup.sh --dev       install the Claude Code plugin from this checkout instead of GitHub
#   ./setup.sh --top N     corpus size (packages with sources fetched for analysis and search)
#   ./setup.sh --yes       don't ask before installing the Luanti app
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AVANTI_HOME="${AVANTI_HOME:-$HOME/.avanti}"
export LDG_HOME="${LDG_HOME:-$AVANTI_HOME/depgraph}"
TOP=300 MINIMAL=0 DEV=0 YES=0
LDG_SOURCE="${LDG_SOURCE:-git+https://github.com/culmat/luanti-depgraph}"

while [[ $# -gt 0 ]]; do
	case "$1" in
	--minimal) MINIMAL=1 ;;
	--dev) DEV=1 ;;
	--yes | -y) YES=1 ;;
	--top) TOP="$2"; shift ;;
	-h | --help) sed -n '2,9p' "$0"; exit 0 ;;
	*) echo "unknown option $1" >&2; exit 1 ;;
	esac
	shift
done

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
ask() { [[ $YES -eq 1 ]] && return 0; read -r -p "$1 [Y/n] " reply; [[ -z "$reply" || "$reply" =~ ^[Yy] ]]; }

OS="$(uname -s)"

step "System tools"
if [[ "$OS" == Darwin ]]; then
	have brew || { echo "Homebrew is required: https://brew.sh" >&2; exit 1; }
	for formula in git jq uv node lua-language-server luarocks stylua; do
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
if have luarocks && ! have luacheck; then
	luarocks install --local luacheck
	echo "luacheck installed to ~/.luarocks/bin; make sure it is on your PATH"
fi

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
uv tool install --upgrade --force "$LDG_SOURCE"
mkdir -p "$HOME/.local/bin"
ln -sf "$REPO/plugins/avanti/bin/avanti" "$HOME/.local/bin/avanti"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "add ~/.local/bin to your PATH" ;; esac
export PATH="$HOME/.local/bin:$HOME/.luarocks/bin:$PATH"

step "zvec-grep (local semantic code search)"
if have node && [[ "$(node -p 'process.versions.node.split(".")[0]')" -ge 22 ]]; then
	have zg || npm install -g @zvec/zvec-grep
	echo "ok  zg $(zg --version 2>/dev/null | head -1)"
else
	echo "Node 22+ is needed for zvec-grep; skipping"
fi

step "Dependency database"
if ! ldg update; then
	echo "No published snapshot reachable; building from ContentDB (about a minute)"
	ldg build
fi

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
	claude plugin install avanti@avanti-luanti || claude plugin update avanti@avanti-luanti || true
	claude plugin install lua-lsp@claude-plugins-official || true
else
	echo "Claude Code CLI not found; install it from https://code.claude.com, then re-run."
fi

step "Doctor"
avanti doctor
