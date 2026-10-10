# Giving back: upstream backlog

Things avanti-luanti found or needs that belong upstream, not in a fork. Per [ai-policy.md](ai-policy.md), a human files each of them in their own words. Status: 💡 idea, 📝 evidence collected, 📮 filed (link), ✅ done.

## ContentDB ([luanti-org/contentdb](https://github.com/luanti-org/contentdb))

| Status | Item | Why |
|---|---|---|
| 💡 | Help fix the daily dump ([#694](https://github.com/luanti-org/contentdb/issues/694)) and include `depends`/`optional_depends` in it | A complete dump would make crawling unnecessary for every dependency tool |
| 💡 | JSON reverse-dependency endpoint for mod names (related: #347, #391, #576) | `/modnames/<name>/` exists only as HTML |
| 💡 | Per-mod dependencies inside modpacks (#560) | Removes false cycles and makes game support more accurate; luanti-depgraph already computes this from sources |
| 💡 | Make the `game=` package filter follow aliases | `game=Minetest/minetest_game` returns 0 mods today |
| 💡 | Expose game-support detection errors and confidence via the API | Lets authors and tools see why support was or wasn't detected |
| 💡 | Optionally snapshot dependencies per release | Enables "since which release did X depend on Y" |

## Tooling

| Status | Project | Item |
|---|---|---|
| 💡 | [lunarmodules/luacheck](https://github.com/lunarmodules/luacheck) | A release that ships the `luanti` std (only on main since 2024) |
| 💡 | [luanti-org/flint](https://github.com/luanti-org/flint) | An "undeclared dependency" lint rule like LDG001–LDG003; ask maintainers about AI policy first |
| 💡 | [luanti-org/luma](https://github.com/luanti-org/luma) | Offer the resolver rules or the nightly snapshot for dependency-aware installs |
| 📝 | [zvec-ai/zvec-grep](https://github.com/zvec-ai/zvec-grep) | 0.2.2 silently indexes 0 files from git repositories nested below the index root (a root that is itself a repo works; `--no-ignore` and `--hidden` don't help). A hint in the output or an option would help multi-repo workspaces. avanti works around it with a text-only mirror. |
| 💡 | [Voxrame/luanti-ide-helper](https://github.com/Voxrame/luanti-ide-helper) | Report annotation gaps found while building mods |

## Games and mods

| Status | Target | Item |
|---|---|---|
| 📝 | [Mineclonia](https://codeberg.org/mineclonia/mineclonia) | With `random_mod_load_order = true`, runs intermittently log `Item does not exist: …`, suggesting undeclared load-order dependencies inside the game. Seen 2026-10-10: `mcl_buckets:bucket_empty`, `mcl_buckets:bucket_water`, `mcl_fishing:fish_raw`, `mcl_fishing:salmon_raw` (native, 5.17.0) and `mcl_flowers:fern`, `double_fern`, `tallgrass`, `double_grass`, `dandelion` (Docker, 5.10.0, culmat/avanti_hello CI). Next step: find the registering mod for these lookups (`zvec_grep_search` over the game), confirm the missing `depends`, then file with the exact log. |
| 💡 | [mt-mods/xcompat](https://github.com/mt-mods/xcompat) | Extend coverage where `avanti test` shows gaps |
| 💡 | Popular mods | Undeclared dependencies found by `ldg sql "select * from v_undeclared_refs where kind = 'global' and guarded = 0 and same_package = 0"`. Verify each by reading the code before reporting. |
