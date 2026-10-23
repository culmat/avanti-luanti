---
name: luanti-testing
description: Test Luanti (Minetest) mods - luacheck config, ldg lint, writing mtt integration tests, running `avanti test` headlessly across games and engine versions (native or Docker), reading results and server logs, surveying what a mapgen mod places with `avanti survey`, and play-testing with `avanti play`/`avanti serve`.
when_to_use: Before declaring mod work done, when adding tests, when `avanti test` or CI fails, or when asked to verify a mod works in a game.
---

# Testing Luanti mods

## The loop

```sh
avanti test                       # lint + headless run in every game from supported_games
avanti test --game mineclonia     # one game
avanti test --runner docker --engine 5.10.0 --engine 5.17.0   # engine matrix, like CI
avanti test --keep                # keep the throwaway world and debug.txt even on PASS
```

**What `avanti test` does:**
1. **Lint.** Runs `luacheck`, `stylua --check` (if `.stylua.toml` exists) and `ldg lint --strict`. Lint errors fail the run.
2. **Build a world for each game × engine.** It contains the mod and the dependencies `ldg install` resolves for that game, with exactly those mods enabled. It also contains either the `avanti_smoke` mod (loads, emerges an area, shuts down) or `mtt` if the mod lists mtt in `optional_depends`.
3. **Run the server headlessly** with `random_mod_load_order = true`. Native uses the local Luanti app or `luantiserver`; Docker uses the official `ghcr.io/luanti-org/luanti:<version>` image.
4. **Report one status per run:**

| Status | Meaning |
|---|---|
| PASS | Clean |
| WARN | Errors in the log, but none mention your mod. Usually a game load-order bug. |
| FAIL | Errors naming your mod, a crash, a timeout, or unresolvable dependencies |
| BROKEN | The game itself failed to start on that engine version (errors only in the game's files). Not counted as a failure; worth reporting to the game. |
| SKIP | Game not synced (`avanti games sync <id>`), or the engine is older than the game's `min_minetest_version`. |

Logs are in `debug.txt` under the run's temp directory (printed for FAIL and WARN). Use `--fixed-order` to rule out load-order flakiness, and `--json` for machine-readable output.

**Reference game IDs:**

| ID | Game |
|---|---|
| `minetest` | Minetest Game |
| `mineclonia` | Mineclonia |
| `mineclone2` | VoxeLibre |
| `asuna` | Asuna (Minetest Game based). Always runs with a fixed mod load order: the game itself breaks under a random one. |
| `devtest` | The engine's test game |

## Writing mtt tests

[mtt](https://github.com/BuckarooBanzay/mtt) runs tests inside the engine. The server exits 0 when all of them pass.

```lua
-- init.lua: only load tests when mtt is present and enabled
if core.get_modpath("mtt") and mtt.enabled then
    dofile(core.get_modpath(core.get_current_modname()) .. "/test/mtt.lua")
end
```

```lua
-- test/mtt.lua
mtt.register("chest keeps items", function(callback)
    local pos = {x = 0, y = 0, z = 0}
    core.set_node(pos, {name = "mymod:chest"})
    local inv = core.get_meta(pos):get_inventory()
    inv:add_item("main", "mymod:chest 2")
    assert(inv:contains_item("main", "mymod:chest 2"))
    callback()
end)

mtt.register_with_area("builds in an emerged area", {size = {x = 10, y = 10, z = 10}, emerged = true},
    function(pos1, pos2, callback)
        -- operate inside pos1..pos2
        callback()
    end)
```

- Call `callback()` on success. Use `callback("message")` or `error(...)` on failure.
- The default timeout is 10 s; set `timeout = n` in a definition table for slower tests.
- `mtt.join_player(name)` simulates a player and is experimental; it needs `fakelib`.
- Test behaviour across games by guarding game-specific assertions with `core.get_modpath(...)`.

## luacheck

The template's `.luacheckrc` uses `std = "luajit"` and lists the engine globals (`core`, `vector`, `ItemStack`, …) and builtin helpers (`table.copy`, `string.split`, …) explicitly, so it works with every luacheck version. Older distro packages don't know the `minetest` std. The mod's own global goes in `globals`, other mods' globals in `read_globals`. Regenerate the latter with `ldg globals .` after changing dependencies.

**Typical findings:**
- **Setting non-standard global:** you leaked a global. Make it `local`.
- **Accessing undefined variable X:** either a typo, or a dependency whose global isn't in `read_globals`. If it's a dependency, it must also be in `depends` or `optional_depends`.

## Reading failures

| Log line | Usual cause → fix |
|---|---|
| `attempt to index global 'X' (a nil value)` | Uses mod X, which isn't loaded (or loads later) → declare it, guard it, or drop it for that game |
| `Some mods have unsatisfied dependencies` | A hard dependency is missing in that game → `ldg resolve PATH --game G` |
| `Undeclared global variable "X" accessed` | Same as above, or a typo |
| `Item does not exist: other:item` (no mention of your mod) | The game's own load-order bug → WARN; consider `/avanti:give-back` |
| Timeout | An infinite loop at load time, or a very slow mapgen. Rerun with `--timeout 400 --keep`. |

## Play-testing

`avanti play --game mineclonia` opens the Luanti client straight into a creative world (`<repo>/.dev/worlds/<game>`, gitignore `/.dev/`) to check what tests can't: visuals, sounds, formspec layout. The mod is symlinked into the world's `worldmods/`, so the world always runs the working copy; never copy mods into the Luanti mods folder for testing.

It is a debug tool: the player starts flying fast and has every privilege (`settime`, `teleport`, `give`, `noclip`, `server`, ...). The helper mod `avanti_play`, linked into the world's worldmods, grants them on join, because singleplayer lacks them in most games, even in creative mode.

`--lite` renders the 3D world at half resolution (`undersampling = 2`), with view range 120 and simple leaves; the rest of the user's `minetest.conf` stays. Suggest it on integrated graphics or 4K screens, where camera movement otherwise stutters.

Luanti has no hot reload: Lua state is built once at startup, and schematics loaded from a file stay cached until the server restarts (`core.place_schematic` in `lua_api.md`). After a change, quit and rerun `avanti play`; `--fresh` starts a new map.

`avanti serve --game mineclonia` runs the same world setup as a server on 127.0.0.1:30000 (world in `~/.avanti/worlds/`), for joining from another client or with several players.

## Mapgen mods: survey, then visit

Mods that place structures during map generation need a different question answered: across a real
map, how many appear, how close do copies sit, and in which biomes? `avanti survey` answers it headlessly.

```sh
avanti survey --game minetest                       # ~1800 mapchunks (~5.8 km2), seed "avanti"
avanti survey --game mineclonia --chunks 600 --keep  # smaller, and keep the world to visit
avanti survey --spacing 2000                         # tiles 2 km apart: more biomes, no spacing data
avanti survey --set mymod_debug=true --json          # pass the mod's own settings; full JSON report
```

- **How it works.** The helper mod `avanti_survey` grows the map in square rings of 3x3-mapchunk tiles
  (two chunk layers around sea level, so mountain tops above ~127 are not covered). A mapchunk is
  80x80x80 nodes, so 1 km2 is about 156 chunks per layer.
- **What it reports.**
  - Surface biome shares.
  - Per structure: count, per km2, average and minimum distance to the nearest copy, and top biomes.
  - Structures are found generically: `core.place_schematic`/`place_schematic_on_vmanip` calls by schematic file, and named schematic decorations (through gennotify), counting only schematics at least 10 nodes wide and 4 high. No mod changes are needed.
  - Not seen: structures placed in the mapgen environment (`core.register_mapgen_script`).
- **Bridge mods.** A mod can ship a development-only bridge in `PATH/tools/survey/` (`optional_depends = avanti_survey`, inert without it, kept out of releases with `export-ignore`). It reports its own features and findings:
  - `avanti_survey.report(kind, id, pos, extra)`
  - `avanti_survey.register_on_finish(fn)`: `fn(ctx)` gets `surface_km2` and the features, and returns a table stored under `mods.<modname>`. A string field `report` is printed.
  - `avanti_survey.finding(level, code, message)`
  - `avanti_survey.ignore(pattern)`: its own schematics aren't counted twice.

  luanti-sagas' `mods/tools/survey` is the reference bridge.
- **Speed** (Intel Mac, native, with the sagas bridge and its site probe, 2026-10-17):

  | Game | Mapchunks per second |
  |---|---|
  | Minetest Game | about 8 |
  | Mineclonia | about 2.5 |

  Use `--chunks 600` or fewer in Mineclonia for quick runs. The default timeout is one second per mapchunk, at least 600 s.
- **Visiting.** With `--keep` the world stays in `~/.avanti/worlds/survey-<name>-<game>-<seed>/world`, and `avanti play PATH --game G --world <that> --lite` opens it. A new `--keep` run deletes the previous world of the same name, game and seed. The mod's own teleport or tour commands then visit the placements. This opens the Luanti window: ask the user first.

Balance rules of thumb for structure mods:
- Big or detailed builds should rarely repeat (aim for 2 km or more between copies).
- "Network" builds (watchtowers, lighthouses) may repeat at regular distances.
- Light sources stay sparse (about 0.5 lit structures per km2 or fewer), so nights in survival stay dark.
