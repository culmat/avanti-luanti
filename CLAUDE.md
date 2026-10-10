# avanti-luanti: notes for agents working on this repo

This repo is the **factory**: developer tooling for building Luanti mods. It isn't a Luanti mod itself. The "plugin" here is a *Claude Code* plugin.

## Layout

| Path | What |
|---|---|
| `plugins/avanti/` | The Claude Code plugin. Everything the plugin needs at runtime must live inside this directory: installed plugins can't reach files outside it. |
| `plugins/avanti/bin/avanti` | The `avanti` CLI (Bash). It sources `../lib/common.sh`. `bin/` is on the Bash tool's PATH when the plugin is enabled. |
| `plugins/avanti/lib/` | `games.tsv` (the reference games), `avanti_smoke/` (the headless smoke-test mod) |
| `plugins/avanti/templates/mod/` | The mod template. `{{placeholders}}` are filled by `avanti new`. |
| `plugins/avanti/skills/`, `agents/`, `hooks/`, `.mcp.json` | Plugin components |
| `.github/workflows/mod-ci.yml` | Reusable CI that mod repos call (`@v1`). Keep its inputs backwards compatible. |
| `docs/` | Primer, ContentDB notes, AI policy, upstream backlog. Keep facts sourced and dated. |

The dependency graph lives in the sibling repo [culmat/luanti-depgraph](https://github.com/culmat/luanti-depgraph) (`ldg`). Fix graph or lint logic there, not here.

## Conventions

- **Bash must run on macOS's bash 3.2:**
  - no associative arrays, `mapfile` or `${x,,}`;
  - guard empty arrays under `set -u` with `${arr[@]+"${arr[@]}"}`;
  - prefer portable `grep -E` over `\b`.
- **Shellcheck clean:** `shellcheck -x setup.sh plugins/avanti/bin/avanti plugins/avanti/lib/common.sh plugins/avanti/hooks/*.sh`.
- **Plugin validates strictly:** `claude plugin validate . --strict && claude plugin validate plugins/avanti --strict`.
- **Skills state facts that can be checked.** Verify API names against `~/.avanti/corpus/engine/doc/lua_api.md` before writing them into a skill.
- **Hooks never block.** They return `additionalContext` only, and stay silent outside Luanti projects.

## Testing changes

```sh
export PATH="$PWD/plugins/avanti/bin:$PATH"
avanti doctor
avanti new avanti_scratch --dir "$TMPDIR" --owner culmat && avanti test "$TMPDIR/avanti_scratch"
```

- For a negative test, add an undeclared `default.node_sound_stone_defaults()` call. Expect `ldg lint` LDG001, plus FAIL in mineclonia and mineclone2 and PASS in minetest.
- For the Docker path, start Docker (`colima start` on this machine) and add `--runner docker --engine 5.17.0`.

## Rules

Follow [docs/ai-policy.md](docs/ai-policy.md):
- Never publish anything without explicit approval from the user in the session: no ContentDB, forum, upstream issue or PR, or git tag push.
- AI-generated media must be disclosed.
- Luanti engine repos accept no AI-written text.
