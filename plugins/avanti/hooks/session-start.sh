#!/usr/bin/env bash
# SessionStart hook: in a Luanti project, tell Claude what kind of package this is and
# which avanti tooling is missing or stale. Silent everywhere else.
set -uo pipefail

dir="${CLAUDE_PROJECT_DIR:-$PWD}"
kind=""
for f in game.conf modpack.conf mod.conf; do
	if [[ -f "$dir/$f" ]]; then
		kind="${f%.conf}"
		break
	fi
done
if [[ -z "$kind" ]]; then
	nested="$(find "$dir" -maxdepth 3 \( -name mod.conf -o -name game.conf -o -name modpack.conf \) \
		-not -path '*/.git/*' 2>/dev/null | head -1)"
	[[ -n "$nested" ]] || exit 0
	kind="workspace with Luanti content (e.g. ${nested#"$dir"/})"
fi

avanti="${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}/bin/avanti"
problems="$("$avanti" doctor --quiet 2>&1 | head -20)"
context="Luanti project detected ($kind). The avanti plugin provides /avanti:new-mod, /avanti:deps, /avanti:compat, /avanti:test, /avanti:release and /avanti:give-back, the \`avanti\` and \`ldg\` CLIs, and the luanti-depgraph and zvec-grep MCP servers."
if [[ -n "$problems" ]]; then
	context+=$'\n'"avanti doctor reports:"$'\n'"$problems"
fi
jq -n --arg ctx "$context" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
