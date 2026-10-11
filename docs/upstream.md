# Giving back: upstream backlog

Things avanti-luanti found or needs that belong upstream, not in a fork. Per [ai-policy.md](ai-policy.md), a human files each of them in their own words. Status: 💡 idea, 📝 evidence collected (notes and patches are prepared locally by `/avanti:give-back` in `drafts/`), 📮 filed (link), ✅ done.

## ContentDB ([luanti-org/contentdb](https://github.com/luanti-org/contentdb))

| Status | Item | Why |
|---|---|---|
| 💡 | Help fix the daily dump ([#694](https://github.com/luanti-org/contentdb/issues/694)) and include `depends`/`optional_depends` in it | A complete dump would make crawling unnecessary for every dependency tool |
| 💡 | JSON reverse-dependency endpoint for mod names (related: #347, #391, #576) | `/modnames/<name>/` exists only as HTML |
| 💡 | Per-mod dependencies inside modpacks (#560) | Removes false cycles and makes game support more accurate; luanti-depgraph already computes this from sources |
| 💡 | Make the `game=` package filter follow aliases | `game=Minetest/minetest_game` returns 0 mods today |
| 💡 | Expose game-support detection errors and confidence via the API | Lets authors and tools see why support was or wasn't detected |
| 📝 patch ready | **Root cause found:** `app/tasks/importtasks.py` only calls `game_support_update` after releases of `PackageType.MOD`, so a game release that adds or drops a mod name never re-checks the mods that depend on it (verified live 2026-10-10: Miniontoby/doorbell lists codecube, which no longer provides `default`). A three-line fix plus one "update all game support" run. Stored game support goes stale when a *game's* provides change. Examples: doorbell still lists codecube, which no longer provides `default`; adventurelands, lean_core and gaifa_al_cubo now provide `default` but aren't listed for mods that depend on it. On 2026-10-10, 40 of 60 sampled mods were affected (`scripts/crosscheck_game_support.py` in luanti-depgraph). A periodic full recompute, or recomputing dependents when a game's provides change, would fix it (related: #573). | Correct "works with" lists on every package page |
| 💡 | Optionally snapshot dependencies per release | Enables "since which release did X depend on Y" |

## Tooling

| Status | Project | Item |
|---|---|---|
| 💡 | [lunarmodules/luacheck](https://github.com/lunarmodules/luacheck) | A release that ships the `luanti` std (only on main since 2024) |
| 💡 | [luanti-org/flint](https://github.com/luanti-org/flint) | An "undeclared dependency" lint rule like LDG001–LDG003; ask maintainers about AI policy first |
| 💡 | [luanti-org/luma](https://github.com/luanti-org/luma) | Offer the resolver rules or the nightly snapshot for dependency-aware installs |
| 📝 repro ready | [zvec-ai/zvec-grep](https://github.com/zvec-ai/zvec-grep) | 0.2.2 silently indexes 0 files from git repositories nested below the index root (a root that is itself a repo works; `--no-ignore` and `--hidden` don't help). A hint in the output or an option would help multi-repo workspaces. avanti works around it with a text-only mirror. |
| 💡 | [Voxrame/luanti-ide-helper](https://github.com/Voxrame/luanti-ide-helper) | Report annotation gaps found while building mods |

## Games and mods

| Status | Target | Item |
|---|---|---|
| 📝 patch ready | [Mineclonia](https://codeberg.org/mineclonia/mineclonia) | **Root cause found:** `mcl_villages/schemgen.lua` checks its loot tables at load time, before undeclared item mods (`mcl_buckets`, `mcl_fishing`, `mcl_flowers`, `mcl_throwing`) may have loaded, which logs false `Item does not exist` errors under random load order. Fix: run the check in `core.register_on_mods_loaded`. |
| 📝 patch ready | [mt-mods/pipeworks](https://github.com/mt-mods/pipeworks) | `mcl_furnaces.lua` copies `mcl_blast_furnace`/`mcl_smoker` nodes without declaring those mods. A latent bug: not reproduced in ~10 random-order Mineclonia runs, because pipeworks usually sorts late. Fix: add both to `optional_depends`. |
| 💡 | [mt-mods/xcompat](https://github.com/mt-mods/xcompat) | Extend coverage where `avanti test` shows gaps |
| 💡 | [mt-mods/xcompat](https://github.com/mt-mods/xcompat) | `src/gameid.lua` forces `gameid = "minetest"` whenever a `default` mod exists, even if `get_game_info().id` names another game. A game that ships a partial `default` would get MTG materials and sounds. Trusting `get_game_info()` first would be safer. See [default-dependency.md](default-dependency.md). |
| 💡 | [mt-mods/xcompat](https://github.com/mt-mods/xcompat) | Mineclonia stairs use the game-agnostic fallback (xcompat's own nodebox nodes), not `mcl_stairs`. Development Test maps no `steel_block`, so mods must check keys (it crashed hammermod 4c118c9). Possibly document per-game key coverage. |
| 💡 | Popular mods | Undeclared dependencies found by `ldg sql "select * from v_undeclared_refs where kind = 'global' and guarded = 0 and same_package = 0"`. Verify each by reading the code before reporting. |
