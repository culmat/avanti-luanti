#!/usr/bin/env bash
# PostToolUse hook: quick feedback after Claude edits Luanti files. Never blocks.
#   *.lua                        -> luacheck + stylua --check on that file
#   mod.conf/modpack.conf/game.conf -> ldg lint --quick on the package
set -uo pipefail

input="$(cat)"
file="$(jq -r '.tool_input.file_path // empty' <<<"$input" 2>/dev/null)"
[[ -n "$file" && -f "$file" ]] || exit 0

# Nearest directory up the tree that holds Luanti metadata.
package_root() {
	local dir
	dir="$(cd "$(dirname "$1")" && pwd)"
	while [[ "$dir" != "/" ]]; do
		if [[ -f "$dir/mod.conf" || -f "$dir/modpack.conf" || -f "$dir/game.conf" || -f "$dir/init.lua" ]]; then
			echo "$dir"
			return 0
		fi
		dir="$(dirname "$dir")"
	done
	return 1
}

report=""
case "$file" in
*.lua)
	root="$(package_root "$file")" || exit 0
	if command -v luacheck >/dev/null; then
		out="$(cd "$root" && luacheck --no-color --formatter plain "$file" 2>&1)" ||
			report+="luacheck found problems in ${file#"$root"/}:"$'\n'"$out"$'\n'
	fi
	if command -v stylua >/dev/null && [[ -f "$root/.stylua.toml" ]]; then
		stylua --check "$file" >/dev/null 2>&1 ||
			report+="stylua: ${file#"$root"/} is not formatted (run: stylua \"$file\")."$'\n'
	fi
	;;
*/mod.conf | */modpack.conf | */game.conf)
	if command -v ldg >/dev/null; then
		root="$(dirname "$file")"
		out="$(ldg lint "$root" --quick --json 2>/dev/null | jq -r '.findings[] | select(.severity != "info")
			| "\(.severity) \(.code) [\(.mod)] \(.file // "")\(if .line then ":\(.line)" else "" end) \(.message)"')"
		[[ -n "$out" ]] && report+="ldg lint after editing ${file##*/}:"$'\n'"$out"$'\n'
	fi
	;;
esac

[[ -n "$report" ]] || exit 0
jq -n --arg ctx "${report:0:9000}" \
	'{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
