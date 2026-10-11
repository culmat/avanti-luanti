---
name: luanti-dependencies
description: Reason correctly about dependencies between Luanti (Minetest) mods, modpacks and games, and make mods work across games. Covers how the engine resolves mod names, why `depends = default` means "Minetest Game-like games only", the ldg/luanti-depgraph tools (providers, deps, resolve, compat, lint, rdeps), and cross-game patterns (optional_depends + guards, xcompat, aliases, groups, supported_games).
when_to_use: Choosing or declaring depends/optional_depends, "will this work in Mineclonia/VoxeLibre/...", "who provides X", undeclared-dependency warnings, LDG lint findings, failing games in avanti test, or picking a library mod.
---

# Luanti dependencies

## Mental model (get this right first)

1. **A dependency names a *mod name*, which stands for an API, not a package.** `depends = default` is satisfied by *any* loaded mod called `default`.
   - On ContentDB, 37 games bundle a `default` mod and **no standalone package provides it**.
   - So `depends = default` effectively means "only in games that bundle it". Mineclonia and VoxeLibre (`mineclone2`) don't.
2. **Games bundle mods, and those are always loaded.** A mod name the game provides is satisfied by the game. Anything else must be installed by the player. Games are never installed as dependencies.
3. **The same name doesn't guarantee the same API.** A game may ship its own `screwdriver` or `default` that only partly matches Minetest Game's. ContentDB even keeps a list of games whose bundled MTG copies don't count.
4. **Load order:**
   - Hard and optional dependencies (if present) load first.
   - Otherwise the order is undefined. With `random_mod_load_order = true` (which `avanti test` sets), undeclared dependencies break visibly.
   - A missing hard dependency stops the world from starting.
5. **A user mod with the same name as a game mod silently replaces it.** There's only a log warning. Never reuse a game's mod name unless you're writing a drop-in replacement.
   - **Never write a `default` shim** for Mineclonia or other games. Mods (and xcompat) detect Minetest Game with `get_modpath("default")`, so a shim would switch working mods onto their MTG code path. Port the mod to xcompat instead (see below).
6. **Declared game support is advisory.** `supported_games` and `unsupported_games` in `mod.conf` feed ContentDB's game-support data; the engine ignores them. ContentDB also auto-detects support from *hard* dependencies only.

## Tools

Use the `luanti-depgraph` MCP tools (`mcp__plugin_avanti_luanti-depgraph__*`) or the `ldg` CLI. A target is `author/name` or a local path.

| Question | MCP tool | CLI |
|---|---|---|
| Who provides mod name X? | `providers` | `ldg providers X` |
| What does it need, and who can provide each piece? | `deps` | `ldg deps T [--tree]` |
| Can it run in game G? What to install? Why not? | `resolve` | `ldg resolve T --game G` |
| Which games work? | `compat` | `ldg compat T [--games a,b]` |
| Does my code use undeclared mods? | `lint_mod` | `ldg lint PATH` |
| Who would I break by changing X? | `rdeps` | `ldg rdeps X [--transitive]` |
| Is my mod name free? | `name_check` | `ldg name-check X` |
| Which names keep the most mods out of game G? (ldg ≥ 0.3.0) | `blockers` | `ldg blockers --game G` |
| Anything else | `query_sql`, `query_cypher` | `ldg sql`, `ldg cypher` |

How to read the results:

| Result | Meaning |
|---|---|
| `only_in_games` / "bundled in N games" | No standalone mod provides the name. Depending on it ties you to those games. |
| `compat` status `ok` | Dependencies are satisfiable, and the code doesn't touch undeclared mods missing in that game. |
| `compat` status `risky` | Installable, but the code references mods missing in that game without declaring or guarding them. Expect runtime errors. |
| `compat` status `unsatisfiable` | A hard dependency can't be met there. |
| `ldg lint` LDG001 | Uses another mod's API undeclared. This is an error. |
| `ldg lint` LDG002 | Checks for a mod but doesn't list it in `optional_depends`. Load order is not guaranteed. |
| `ldg lint` LDG003 | Uses another mod's item names undeclared. |

For a visual overview, or a link to share with other modders, use the dependency explorer at https://culmat.github.io/luanti-depgraph/ (graph, per-game coloring, dependency trees, SQL in the browser). Package pages are at `#/p/<author>/<name>`, mod names at `#/m/<name>`.

`ldg info` shows the database age; run `ldg update` if it's more than a week old. Static analysis is heuristic (tree-sitter, conservative). Confirm conclusions with `avanti test`.

## Making a mod work across games

1. **Minimize hard dependencies.** Every hard dependency on a game mod (`default`, `mcl_core`, `player_api`, `farming`, …) restricts the games you run in. Check with `ldg providers <name>`.
2. **Prefer game-agnostic library mods** that exist as standalone packages.
   - `xcompat` (mt-mods) provides materials, sounds, textures, player and stairs helpers across MTG, Mineclonia, VoxeLibre and others.
   - Read its API in the corpus: `~/.avanti/corpus/packages/mt-mods/xcompat`, or search with zvec-grep.
   - **To replace `default` in an existing mod, follow [xcompat-porting.md](xcompat-porting.md):** call-by-call and item-by-item mapping, the gaps, and how to stay compatible with existing worlds.
3. **For game-specific integrations, use optional dependencies plus guards.** Always list the mod in `optional_depends` so it loads first:
   ```lua
   if core.get_modpath("default") then
       sounds = default.node_sound_stone_defaults()
   elseif core.get_modpath("mcl_sounds") then
       sounds = mcl_sounds.node_sound_stone_defaults()
   end
   ```
   `core.get_game_info().id` tells you the game when you really need it. Prefer feature checks (`get_modpath`) over game checks.
4. **Recipes:**
   - Use groups (`group:wood`, `group:stick` where available) where the games agree.
   - Otherwise keep one recipe table per game behind guards.
   - Never hard-code `default:*` item names unguarded.
5. **Aliases:** when you rename items, `core.register_alias` the old names. Never register items into another mod's namespace unless you're deliberately overriding them.
6. **Declare the truth:**
   - `supported_games` lists the games you test in CI (`avanti test` reads it).
   - `unsupported_games` lists the games you know fail.
   - Keep `depends` minimal and exact; `optional_depends` covers everything you integrate with.

## When something fails in one game

1. `ldg resolve PATH --game G` shows whether the dependencies are met.
2. `ldg lint PATH` shows what the code uses undeclared.
3. `avanti test PATH --game G --keep`, then read the kept `debug.txt`. Errors that name your mod are yours. Errors from other mods are reported as WARN and are usually game load-order bugs, which are worth reporting upstream with `/avanti:give-back`.
4. For deeper digging, use the `compat-investigator` agent.
