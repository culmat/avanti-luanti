# Luanti primer: engine, games, mods and dependencies

What you need to know to build mods for [Luanti](https://www.luanti.org) (formerly Minetest), and why dependencies are hard to reason about. Facts were checked against the engine source and docs at 5.17.0 (released 2026-08-20) and against ContentDB in October 2026. Links point to the authoritative sources.

## The pieces

| Piece | What it is | Where |
|---|---|---|
| **Engine** | C++ voxel engine with a Lua modding API. The client and server are one binary (`luanti`, `luanti --server`); there is also a headless `luantiserver`. | [luanti-org/luanti](https://github.com/luanti-org/luanti), API reference in [doc/lua_api.md](https://github.com/luanti-org/luanti/blob/master/doc/lua_api.md) |
| **Game** | A directory with `game.conf` and a `mods/` folder. Nearly all gameplay lives in mods. | e.g. [Minetest Game](https://github.com/luanti-org/minetest_game), [Mineclonia](https://codeberg.org/mineclonia/mineclonia), [VoxeLibre](https://git.minetest.land/VoxeLibre/VoxeLibre) |
| **Mod** | A directory with `init.lua` (and ideally `mod.conf`) | ContentDB, GitHub, Codeberg, … |
| **Modpack** | A directory with `modpack.conf` containing mods (it can nest) | |
| **Texture pack** | Replacement textures (`texture_pack.conf`) | |
| **ContentDB** | The package registry the main menu installs from | [content.luanti.org](https://content.luanti.org), source [luanti-org/contentdb](https://github.com/luanti-org/contentdb) |

The luanti-org GitHub org also hosts `minetest_game`, `contentdb`, `docs.luanti.org`, `serverlist`, `modtools` (translation tooling), and two new tools that are good contribution targets: **`flint`** (Rust linter/formatter for mods) and **`luma`** (Go CLI package manager for ContentDB).

## Metadata files

### `mod.conf`

```ini
name = mymod                  # overrides the folder name; [a-z0-9_]+
title = My Mod
description = One sentence.
depends = default, xcompat    # hard: the world won't start without them
optional_depends = mtt        # loaded first *if present*
supported_games = minetest, mineclonia   # ContentDB only; "*" = all games
unsupported_games = nodecore             # ContentDB only
min_minetest_version = 5.10              # ContentDB only
```

- The engine strips all whitespace and splits on commas.
- The legacy `depends.txt` (one name per line, `?` for optional) is used only when `mod.conf` has neither `depends` nor `optional_depends`. The engine plans to drop it.
- `supported_games`, `unsupported_games` and `min/max_minetest_version` are **ignored by the engine**; only ContentDB reads them.

### `game.conf`

- `title` is required.
- Other keys: `description`, `author`, `first_mod` and `last_mod`, `allowed_mapgens` and `disallowed_mapgens`, `default_mapgen` (5.15+), `disabled_settings`, `map_persistent`, and `aliases` (old game IDs, 5.16+).
- **The game ID is the folder name with a trailing `_game` removed.** `minetest_game` → `minetest`, and VoxeLibre's ID is still `mineclone2`.

### `.cdb.json` (optional, ContentDB only)

Package metadata kept in the repo: `type`, `title`, `short_description`, `license`, `media_license`, **`ai_disclosure`** (`NONE` / `ASSISTED` / `GENERATED`), `dev_state`, `tags`, `repo`, and so on. The schema is at https://content.luanti.org/api/cdb_schema/.

## How the engine loads mods

From `src/server/mods.cpp` and `src/content/mod_configuration.cpp`:

1. **Game mods** (everything in `games/<id>/mods`) are always loaded and can't be disabled.
2. **World mods** (`<world>/worldmods/`) are always loaded.
3. **User mods** (the `mods/` folder, `LUANTI_MOD_PATH`) load only if `world.mt` has `load_mod_<name> = true`, or the mod's path, which the menu writes to pick between two same-named mods.
4. **Name conflicts:**
   - If the same name appears at a *later* level, it replaces the earlier one with only a log warning. A user mod called `default` silently replaces the game's `default`.
   - Two mods with the same name at the *same* level is a fatal error.
5. **Dependency resolution** is a topological sort.
   - Optional dependencies count only when present.
   - A missing hard dependency is fatal: "Some mods have unsatisfied dependencies".
   - The order of independent mods is unspecified. `random_mod_load_order = true` shuffles it, which exists precisely so developers find their undeclared dependencies.
6. Each `init.lua` runs, then the `core.register_on_mods_loaded` callbacks run.

Mod security is on by default (`secure.enable_security`). Unsafe APIs need explicit opt-in by the server owner: `secure.trusted_mods` for `core.request_insecure_environment()` and `secure.http_mods` for `core.request_http_api()`.

## Why dependencies are hard to reason about

1. **A dependency names a mod *name*, which stands for an API, not a package.**
   - On ContentDB, `default` is provided by **37 games and no standalone mod**, and `player_api` by 62 games.
   - `depends = default` therefore means "only in games that bundle a mod named `default`". Minetest Game qualifies; Mineclonia and VoxeLibre don't.
2. **Same name, different API.**
   - Games reuse each other's mod names: Mineclonia ships its own `screwdriver`, several games ship MTG-derived `default`s.
   - ContentDB policy 3.2 allows same-name "drop-in replacements", but nothing checks that the API matches. ContentDB even hard-codes a list of games whose bundled MTG copies it ignores.
3. **Games bundle mods, and the player can't remove them.** Whether a dependency is met depends on which game the world runs.
4. **Undeclared dependencies are everywhere.**
   - Code calls `default.node_sound_stone_defaults()` or uses `"default:stone"` in recipes without declaring `default`.
   - It works in one game by luck of load order, and crashes or silently loses recipes in another.
5. **Optional dependencies move the problem to runtime.** `if core.get_modpath("default") then … elseif core.get_modpath("mcl_core") then … end` is the recommended pattern, and it multiplies the code paths to test.
6. **Item names and groups are part of the contract.** Recipes reference `default:steel_ingot` or `mcl_core:iron_ingot`; games are encouraged to provide aliases and standard groups, but not all do.
7. **Declared support is advisory**, and ContentDB's detection only looks at hard dependencies (see [contentdb.md](contentdb.md)).

### What helps

- **Fewer hard dependencies**, and game-agnostic libraries such as [xcompat](https://github.com/mt-mods/xcompat), which maps materials, sounds, textures, player and stairs across MTG, Mineclonia, VoxeLibre, Farlands Reloaded, Hades and more.
- **Optional dependencies with guards**, always declared so load order holds.
- **Groups in recipes, and aliases for renamed items.**
- **Testing in every target game with random load order.** That's `avanti test`.
- **Tools that show the graph:** `ldg providers`, `resolve`, `compat`, `lint` and `rdeps` from [luanti-depgraph](https://github.com/culmat/luanti-depgraph).

## The games that matter most

Ranked by ContentDB score and downloads:

| Game | ID | API family | Notes |
|---|---|---|---|
| Minetest Game | `minetest` | `default`, `stairs`, `farming`, `player_api`, … | Maintenance-only; the de facto "MTG API" many mods assume |
| Mineclonia | `mineclonia` | `mcl_*` | Fork of MineClone2, diverging (e.g. its own `mcl_redstone`) |
| VoxeLibre (ex-MineClone2) | `mineclone2` | `mcl_*` | |
| Asuna, Dreambuilder, … | | MTG-derived `default` | |
| NodeCore, Exile, Repixture | | Own APIs (`nc_*`, `rp_*`, …) | Few mods work unchanged |

## Writing good mods: the short version

The [Luanti Modding Book](https://rubenwardy.com/minetest_modding_book/) (source on [GitLab](https://gitlab.com/rubenwardy/minetest_modding_book)) is the canonical guide. Its chapters are vendored into `~/.avanti/corpus/vendor/modding_book` by `avanti corpus sync`. Key rules:

- Use `core.*`. Have one global named after the mod, and locals everywhere else.
- Registrations are `modname:thing`, made at load time only.
- `S = core.get_translator(modname)` for every player-facing string.
- Never trust formspec input. Re-check privileges and distance on submit.
- Prefer node timers over ABMs, and VoxelManip for bulk map edits.
- Don't hold ObjectRefs across callbacks. Write ItemStack changes back.
- Use luacheck. Test with [mtt](https://github.com/BuckarooBanzay/mtt) (in-engine) or [mineunit](https://github.com/S-S-X/mineunit) (unit tests).

## Contributing a mod to the community

- **Hosting:** publish on ContentDB (see [contentdb.md](contentdb.md) for policy and the release flow). Source on GitHub, Codeberg or GitLab.
- **Forum:** optionally post a topic in "WIP Mods", later "Mod Releases", titled `[Mod] Title [modname]`.
- **Community orgs:** [minetest-mods](https://minetest-mods.github.io/) and [mt-mods](https://github.com/mt-mods) maintain popular mods collectively. Contributing upstream is preferred over forking.
- **AI-assisted work:**
  - ContentDB requires `ai_disclosure`.
  - The engine forbids "vibe-coded" contributions and AI-written issue or PR text ([ai_policy.md](https://github.com/luanti-org/luanti/blob/master/doc/developing/ai_policy.md)).
  - avanti-luanti's own rules are in [ai-policy.md](ai-policy.md).
