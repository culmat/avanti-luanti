---
name: luanti-testing
description: Test Luanti (Minetest) mods - luacheck config, ldg lint, writing mtt integration tests, running `avanti test` headlessly across games and engine versions (native or Docker), reading results and server logs, and play-testing with `avanti serve`.
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

`avanti serve --game mineclonia` starts a server on 127.0.0.1:30000 with a persistent world in `~/.avanti/worlds/`. Join it from the Luanti client to check what tests can't: visuals, sounds, formspec layout.
