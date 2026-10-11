# The `default` dependency: why so many mods don't install in Mineclonia

Many ContentDB mods can't be installed in Mineclonia or VoxeLibre because they declare `depends = default`. This page explains:
- what `default` is;
- how big the problem is across ContentDB;
- why a "`default` shim" mod would make things worse;
- what to do instead.

**Sources:**
- the luanti-depgraph database built 2026-10-10 (3184 mods, 181 games, sources of 297 top packages, 2270 scanned mods);
- the local corpus: minetest_game at c42e4d0 (2026-08-16), xcompat at 758684d (2026-09-06).

The commands to reproduce every number are at the end.

## What `default` is

`default` is the core mod of [Minetest Game](https://github.com/luanti-org/minetest_game) (MTG). It provides:
- **Base items:** `default:stone`, `default:dirt`, `default:steel_ingot`, `default:chest`, `default:mese_crystal`, …
- **Sound helpers:** `default.node_sound_stone_defaults()` and eleven more.
- **Formspec strings:** `default.gui_bg`, `gui_bg_img` and `gui_slots`, which are legacy empty strings (`mods/default/legacy.lua`), plus `default.get_hotbar_bg()`.
- **Helpers:**
  - trees and saplings (`grow_tree`, `sapling_on_place`, `can_grow`);
  - `register_leafdecay`;
  - fences (`register_fence`, `register_fence_rail`);
  - `register_mesepost`;
  - `can_interact_with_node`;
  - constants such as `LIGHT_MAX`.

A dependency names a *mod name*, not a package (see [luanti-primer.md](luanti-primer.md)). Anything called `default` satisfies `depends = default`.
- On ContentDB, **37 games bundle a `default` mod** (MTG and derivatives such as Asuna, Dreambuilder and Capture the Flag), and **no standalone package provides it**.
- So `depends = default` means "only in those games".
- Mineclonia and VoxeLibre implement the same ideas in their own mods (`mcl_core`, `mcl_sounds`, …). Of MTG's mod names, Mineclonia bundles only `screwdriver`, and VoxeLibre only `screwdriver` and `xpanes`.

## How big the problem is

`ldg blockers --game G` resolves every ContentDB mod in game G with ContentDB's rules and ranks the mod names that make mods uninstallable:
- *root cause* is the deepest name that no standalone mod provides;
- *sole* counts the mods for which it is the only root cause.

| Game | Mods that can't be installed | Downloads of those mods | Top root causes |
|---|---|---|---|
| Mineclonia | 1274 of 3184 (40%) | 6.0M | `default` 1074 (sole 760), `dye` 95, `player_api` 89, `wool` 68, `fire` 62 |
| VoxeLibre (`mineclone2`) | 1279 (40%) | 5.9M | `default` 1074 (sole 769), `dye` 95, `player_api` 89, `wool` 68 |
| NodeCore | 1369 (43%) | 6.4M | `default` 1074 (sole 742), `dye` 95, `player_api` 89, `mcl_core` 82 |
| Repixture | 1401 (44%) | 5.6M | `default` 1074 (sole 774), `dye` 95, `mcl_core` 82 |
| Minetest Game | 272 (9%) | 0.5M | `mcl_core` 82, `nc_api_all` 61 (mods written for other games) |

- 1016 mods (32%) declare `depends = default` directly. Together they have 4.7M downloads.
- Another 58 mods are blocked through a dependency that itself needs `default`, for example a library mod.
- 470 mods list `default` only in `optional_depends`. That's the cross-game pattern, and those mods install everywhere.
- `player_api` counts as missing in Mineclonia although Mineclonia bundles a mod of that name. ContentDB keeps a list of games whose copies of MTG mods don't implement the MTG API, and Mineclonia is on it.

**What `default`-dependent code actually uses.** Counts are packages in the corpus:

- **API:** 819 distinct `default.*` symbols. The head is short:
  - `node_sound_wood_defaults` 102, `…_stone_…` 82, `…_leaves_…` 70, `…_metal_…` 60, `…_dirt_…` 54, `…_glass_…` 53;
  - `gui_bg_img` 38, `gui_bg` 37, `gui_slots` 34;
  - `register_leafdecay` 24, `register_fence` 24, `get_hotbar_bg` 23, `sapling_on_place` 22, `can_grow` 20, `register_mesepost` 17.

  Then comes a long tail of tree growing, chests, player models and constants.
- **Items:** 640 distinct `default:*` item names. The most used are `steel_ingot` 153, `water_source` 119, `dirt` 118, `stone` 117, `sand` 96 and `chest` 94.
- **A sample of 40 mods** that are blocked by `default` alone and have scanned sources:
  - 26 use both the API and item names;
  - 12 use only item names;
  - 2 use nothing from `default`, so the dependency is just stale.

## Why not a `default` shim?

The obvious idea is a standalone mod named `default` that maps the MTG API onto Mineclonia. It would do more harm than good:

1. **It breaks mods that work today.**
   - 122 scanned mods detect the game with `core.get_modpath("default")`, and 65 of them also have an `mcl_*` branch for Mineclonia.
   - xcompat itself sets `gameid = "minetest"` whenever `default` exists (`src/gameid.lua`).
   - With a shim installed, all of them, plus the 50 mods that use xcompat, would take their MTG code path inside Mineclonia and fail.
2. **ContentDB would use it everywhere.**
   - Once a standalone package provides `default`, ContentDB's installer and its game-support detection count it as a provider.
   - The shim would then be offered for all 1016 mods in every game without `default`: NodeCore, Repixture, Exile and others, not only Mineclonia.
   - Game-support pages would claim support where the mods are broken.
3. **The name isn't free.**
   - Minetest Game owns the technical name `default` (ContentDB policy 3.1, "right to a name").
   - The exception in 3.2 covers forks and drop-in replacements, and a partial Mineclonia mapping isn't a drop-in replacement.
4. **The engine replaces silently.** A user mod with the same name as a game mod replaces it, with only a log warning. Installed into an MTG world by mistake, a shim would replace the real `default`.
5. **The API is too large to map faithfully.**
   - 819 symbols and 640 items. Mese, tin and bronze have no Mineclonia counterpart.
   - Formspec, tree and fence helpers behave differently in each game.

## What to do instead

- **Port mods to [xcompat](https://content.luanti.org/packages/mt-mods/xcompat/)** (mt-mods, 110k downloads).
  - It's a game-agnostic library: `xcompat.materials`, `.sounds`, `.textures`, `.player`, `.stairs`, `.functions`, `.gameid`.
  - It has per-game backends for MTG, MineClone2/VoxeLibre/Mineclonia, Hades Revisited, Farlands Reloaded, Exile, KSurvive 2, Forgotten Lands and Development Test.
  - In Mineclonia, materials, sounds and player are native. Textures and stairs use xcompat's game-agnostic fallback, which registers its own nodebox stairs instead of using `mcl_stairs`.
  - Only 50 mods use xcompat today (30 hard, 20 optional).
  - The mapping, the gaps and a checklist are in the avanti skill reference [xcompat-porting.md](../plugins/avanti/skills/luanti-dependencies/xcompat-porting.md).
- **For what xcompat doesn't cover** (leafdecay, fences, tree growth, mese posts), use `optional_depends` plus `core.get_modpath` guards, with a Mineclonia branch where it matters.
- **Don't break existing worlds.** When you update a published mod, add xcompat to `optional_depends` and keep the old code as the fallback. Worlds created before the update don't have xcompat enabled, and a new hard dependency would stop them from loading.

**Worked example: [cultom/hammermod](https://github.com/cultom/hammermod), commits 4c118c9 and 5fa0944, 2026-10-11.**
- **Before:** it already ran in MTG and the MineClone games through `get_modpath` guards on `mcl_core` and `default`.
- **Change:** the recipe now takes stick, steel ingot and steel block from `xcompat.materials` when xcompat maps all three, with the old branches as fallback. xcompat is in `optional_depends`. A new mtt test checks that the recipe exists and uses registered items.
- **Lesson:** xcompat's tables differ per game.
  - Development Test has no `steel_block`, so the first version (4c118c9) passed `nil` to `register_craft`, and the mod failed to load in devtest when xcompat was installed.
  - 5fa0944 checks every key before using it. Test the games you *don't* target too.
- **Result:**
  - `avanti test` passes in minetest_game, mineclonia, mineclone2 and devtest on Luanti 5.17.0, both with and without xcompat;
  - with xcompat the recipe is identical in those games (`default:steel_ingot` / `mcl_core:iron_ingot`, …);
  - Hades Revisited and Farlands Reloaded gain a recipe, since xcompat maps all three items there.

## Reproduce

```sh
ldg update && ldg info                                 # database age
ldg blockers --game mineclonia                         # ldg >= 0.3.0
ldg providers default                                  # 37 games, 0 mods
ldg rdeps default --hard-only                          # mods that hard-depend on default
```

With older ldg, use SQL. This counts the mods each game blocks through a direct hard dependency. It's a simpler rule than `blockers`, which also follows providers transitively and applies ContentDB's rule for nonstandard MTG copies:

```sh
ldg sql "WITH g AS (SELECT modname FROM provides WHERE package_id = (SELECT id FROM package WHERE type='game' AND name='mineclonia')),
  sa AS (SELECT DISTINCT pr.modname FROM provides pr JOIN package s ON s.id = pr.package_id WHERE s.type = 'mod')
SELECT d.modname, count(*) AS mods FROM dep d JOIN package p ON p.id = d.package_id
WHERE p.type = 'mod' AND d.optional = 0 AND d.modname NOT IN g AND d.modname NOT IN sa
GROUP BY d.modname ORDER BY mods DESC LIMIT 15"
```

The API and item counts come from the corpus:

```sh
cd ~/.avanti/corpus/packages
grep -rHoE --include=*.lua '\bdefault\.[A-Za-z_]+' . | awk -F: '{split($1,a,"/"); print a[2]"/"a[3]" "$2}' | sort -u | awk '{print $2}' | sort | uniq -c | sort -rn | head -30
```
