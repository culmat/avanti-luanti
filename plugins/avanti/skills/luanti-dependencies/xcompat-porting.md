# Porting a mod from `default` to xcompat

[xcompat](https://content.luanti.org/packages/mt-mods/xcompat/) (mt-mods) is a game-agnostic library. A mod that uses xcompat instead of `default` can be installed in every game xcompat knows, not only in the 37 games that bundle `default`. All names below were checked against `~/.avanti/corpus/packages/mt-mods/xcompat/src` (commit 758684d, 2026-09-06). Check them again there if your copy is newer.

## Never do this

- **Don't create a mod named `default`** (a "shim").
  - Many mods detect the game with `get_modpath("default")`, xcompat included: `src/gameid.lua` sets `gameid = "minetest"` whenever `default` exists.
  - Inside Mineclonia, a shim would switch all of them onto their Minetest Game code path.
  - The background is in `docs/default-dependency.md` in the avanti-luanti repo.
- **Don't make xcompat a hard dependency in an update of a published mod.**
  - Existing worlds don't have xcompat enabled, so they would stop loading.
  - Add it to `optional_depends`, use it when present, and keep the old code as the fallback. Example: [cultom/hammermod](https://github.com/cultom/hammermod) (commits 4c118c9, 5fa0944).
  - A *new* mod can use `depends = xcompat`.
- **Don't branch on `get_modpath("default")` to detect the game.** Use `xcompat.gameid`, which is for example `"minetest"` or `"mineclonia"` (VoxeLibre and MineClone2 map to `"mineclonia"`). Better still, use the xcompat call and don't branch at all.

## Sounds: `xcompat.sounds`

These are drop-in replacements for the `default.node_sound_*` functions.

| `default.` | `xcompat.sounds.` |
|---|---|
| `node_sound_defaults` | `node_sound_default` (no **s**) |
| `node_sound_stone_defaults` | `node_sound_stone_defaults` |
| `node_sound_dirt_defaults`, `…_sand_…`, `…_gravel_…`, `…_wood_…`, `…_leaves_…`, `…_glass_…`, `…_ice_…`, `…_metal_…`, `…_water_…`, `…_snow_…` | same name |
| (not in MTG's `default`) | xcompat adds `node_sound_grass_defaults`, `…_lava_…`, `…_wool_…` |

There are two ways to use them:
- Call them directly: `sounds = xcompat.sounds.node_sound_wood_defaults()`.
- Or declare `_sound_def = {key = "node_sound_wood_defaults"}` in the node definition. xcompat then fills in `sounds` for you.

## Items: `xcompat.materials`

Replace `"default:…"` strings with `xcompat.materials.<key>`. Here is what each key gives in Mineclonia (`src/materials/mineclonia.lua`):

| `default:` item | key | Mineclonia / VoxeLibre |
|---|---|---|
| `steel_ingot`, `steelblock` | `steel_ingot`, `steel_block` | iron ingot, iron block |
| `gold_ingot`, `goldblock`, `copper_ingot`, `copperblock` | `gold_ingot`, `gold_block`, `copper_ingot`, `copper_block` | the same metals |
| `tin_ingot`, `tinblock` | `tin_ingot`, `tin_block` | **iron** (or moreores tin if installed) |
| `mese`, `mese_crystal` | `mese`, `mese_crystal` | **redstone block, redstone** |
| `mese_crystal_fragment` | `mese_crystal_fragment` | **iron ingot** |
| `stick`, `paper`, `book`, `coal_lump`, `clay_lump`, `diamond`, `flint`, `torch` | same keys | equivalents |
| `stone`, `cobble`, `desert_stone`, `sand`, `desert_sand`, `sandstone`, `gravel`, `dirt`, `dirt_with_grass`, `obsidian`, `brick`, `glass` | same keys | equivalents |
| `obsidian_glass` | `obsidian_glass` | **`""` (none)**: check for an empty string before using it |
| `tree`, `wood`, `leaves` | `apple_log`, `apple_planks`, `apple_leaves` | oak |
| `aspen_tree`, `aspen_wood`, `aspen_leaves` | `birch_log`, `birch_planks`, `birch_leaves` | birch |
| `jungleleaves` | `jungle_leaves` | jungle leaves |
| `chest` | `chest` | `mcl_chests:chest` |
| `water_source`, `water_flowing` | same keys | equivalents |

For tool, dye, wool and the remaining keys, see the full key list in `src/materials/minetest.lua`.

The **bold** rows are approximations. If balance matters, decide whether such a recipe should exist in that game at all.

**Check every key before using it.**
- Each game's table is different. Development Test has no `steel_block`, and Mineclonia's `obsidian_glass` is `""`.
- A `nil` in a recipe makes `core.register_craft` raise "Invalid crafting recipe", and the mod fails to load.
- Use xcompat only when all the keys you need are non-empty; otherwise fall back or skip the recipe:
  ```lua
  local m = core.get_modpath("xcompat") and xcompat.materials or {}
  local function known(item) return item ~= nil and item ~= "" end
  if known(m.stick) and known(m.steel_ingot) then
      core.register_craft({output = "mymod:thing", recipe = {{m.steel_ingot}, {m.stick}}})
  end
  ```

- **Prefer groups** (`group:wood`, `group:stone`, `group:sand`, `group:stick`) where both games define them. Then you need no lookup at all.
- **Items xcompat doesn't map:**
  - keep a per-game table behind `optional_depends` plus `core.get_modpath` guards;
  - or drop the recipe in games where the item doesn't exist.

## Other APIs

| `default.` | Replacement |
|---|---|
| `gui_bg`, `gui_bg_img`, `gui_slots` | Delete them: they're `""` in MTG (`mods/default/legacy.lua`). |
| `get_hotbar_bg`, `gui_survival_form` and other formspec helpers | MTG-only. Guard them with `get_modpath("default")` or drop them. |
| `can_interact_with_node` | `xcompat.functions.can_interact_with_node(player, pos)` |
| `sapling_on_place` | `xcompat.functions.sapling_on_place(…)` (same arguments) |
| `player_attached`, `player_set_model`, `player_set_animation`, `player_set_textures` (player_api) | `xcompat.player.player_attached`, `.set_model`, `.set_animation`, `.set_textures`, `.register_model`, `.get_animation`, `.get_textures` |
| `stairs.register_stair_and_slab` (stairs mod) | `xcompat.stairs.register("mymod:name", def)`. In MTG it calls `stairs`. Elsewhere, including Mineclonia, xcompat registers its own nodebox stairs and slabs. |
| `register_leafdecay`, `register_fence`, `register_fence_rail`, `register_mesepost`, `grow_tree`, `can_grow`, `LIGHT_MAX`, … | No xcompat equivalent. Use `optional_depends = default` plus guards, with a Mineclonia branch if needed (`mcl_fences`, …), or write it yourself. |

## Checklist

1. `ldg lint PATH` lists every `default.*` and `default:*` use (LDG001 and LDG003). `ldg compat PATH` shows the games that are blocked today.
2. Replace the uses with the tables above, and guard what's left.
3. Update `mod.conf`:
   - new mod: `depends = xcompat`;
   - update of a published mod: `optional_depends = …, xcompat` plus the old code as fallback;
   - either way, remove `default` from `depends`.
4. Add `xcompat` to `read_globals` in `.luacheckrc`.
5. Test with xcompat present and with it absent:
   - run `avanti test PATH --game minetest_game --game mineclonia --game mineclone2`;
   - `avanti test` installs hard dependencies only, so to test the xcompat path of an optional dependency, run a scratch copy with `depends = xcompat`.
   - Add `--game devtest`: its sparse xcompat table catches unchecked keys.
6. `ldg compat PATH` afterwards shows the newly reachable games.
