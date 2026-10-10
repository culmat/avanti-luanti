---
name: luanti-modding
description: How to write correct, idiomatic Luanti (formerly Minetest) mods in Lua - mod layout, mod.conf, the core.* API, namespacing, translations, storage, security, performance and common mistakes - and how to look up the real API instead of guessing. Use whenever writing, changing or reviewing Luanti/Minetest mod, modpack or game code.
when_to_use: Any task touching init.lua, mod.conf, game.conf, modpack.conf, registrations (nodes, items, crafts, entities, ABMs), formspecs, HUDs, or questions like "how do I ... in Luanti/Minetest".
---

# Writing Luanti mods

## Look things up; don't guess

The Luanti API is large and has changed over the years (`minetest.*` became `core.*` and functions were added in 5.x). Before using an API function, setting or callback you aren't certain of, verify it. Prefer these sources, in this order:

1. **The engine's own reference**, for the engine version avanti tests against:
   - `$AVANTI_HOME/corpus/engine/doc/lua_api.md` (`AVANTI_HOME` defaults to `~/.avanti`). Grep for the exact name, e.g. `grep -n "get_mod_data_path" ~/.avanti/corpus/engine/doc/lua_api.md`.
   - Settings are in `.../engine/builtin/settingtypes.txt`.
2. **Real usage in the ecosystem:** the `zvec_grep_search` MCP tool with `root` = the absolute path of `~/.avanti/search` (a text-only mirror of `~/.avanti/corpus`; the same relative paths exist in both). It covers the engine docs and builtin, Minetest Game, Mineclonia, VoxeLibre, the top ContentDB packages, the modding book and mtt. Ask in natural language ("how do mods register a stair node in mineclonia"), then read the hits.
3. **Lua-aware code search:** the `search_code` MCP tool (luanti-depgraph), or `ldg code search "…" [--kind register|function|table] [--game mineclonia]`. Results come back as whole functions, `register_*` calls and API tables from the top ContentDB packages and games, with package, file and lines. It's the fastest way to see how working mods do something, and `--game` limits results to mods that work in that game.
4. **The Luanti Modding Book:** `~/.avanti/corpus/vendor/modding_book/_en/` for idioms and explanations.
5. **LuaLS annotations:** `~/.avanti/corpus/vendor/luanti-ide-helper` for signatures and types.

If a function isn't in `lua_api.md`, it doesn't exist in the engine. It may come from a mod; check which with `ldg` (see the luanti-dependencies skill).

## Anatomy of a mod

```
mymod/
├── mod.conf        name, title, description, depends, optional_depends, supported_games, min_minetest_version
├── init.lua        entry point; load other files with dofile(core.get_modpath(modname) .. "/x.lua")
├── locale/         template.txt (# textdomain: mymod) and mymod.<lang>.tr / .po
├── textures/       mymod_*.png (16x16 for nodes; prefix every file with the mod name)
├── sounds/ models/ schematics/
├── test/mtt.lua    integration tests (see luanti-testing)
├── LICENSE  README.md  .cdb.json  .luacheckrc
```

- **Names:** the mod name is `[a-z0-9_]+`. `mod.conf` `name` overrides the folder name.
- **ContentDB-only fields:** `supported_games`, `unsupported_games`, `min_minetest_version` and `max_minetest_version` are read only by ContentDB; the engine ignores them.

## Conventions the community expects

- **Use `core.*`, not `minetest.*`.** `minetest` remains an alias; `core` has existed since 0.4.10.
- **Exactly one global:** a table named after the mod (`mymod = {}`). Everything else is `local`. luacheck enforces this.
- **Registration names are `modname:thing`.** `":othermod:thing"` (leading colon) overrides another mod's item; only do that deliberately. Rename with `core.register_alias("old:name", "mymod:new")`.
- **Registration happens at load time only.** Don't call `register_*` or `get_mod_storage()` from callbacks.
- **Groups beat names.** Use `group:wood`, `group:stone` and similar in recipes, and give your nodes the standard groups (`cracky`, `choppy`, `snappy`, `crumbly`, `oddly_breakable_by_hand`). That way they work across games.

## Translations

```lua
local S = core.get_translator(core.get_current_modname())
description = S("Steel Chest")
```

- List every string in `locale/template.txt` under `# textdomain: mymod`.
- Never log or compare translated strings. They contain escape sequences.

## Storage

| What | API |
|---|---|
| Per node | `core.get_meta(pos)`. Call `meta:mark_as_private(key)` for data clients must not see. |
| Per item stack | `stack:get_meta()` |
| Per player | `player:get_meta()` |
| Per mod, per world | `core.get_mod_storage()`, obtained at load time |
| Files independent of worlds | `core.get_mod_data_path()`. Since 5.16 mods may not write into their own mod directory. |

## Security

**Never trust client input.** Formspec `fields` can be forged:
- Re-check privileges (`core.check_player_privs(name, {priv = true})`) when the fields arrive, not only when you show the form.
- Check that the player is near the node, and validate every value.

**Unsafe APIs need explicit permission from the server owner:**
- `core.request_insecure_environment()` requires `secure.trusted_mods`.
- `core.request_http_api()` requires `secure.http_mods`.
- Call either only at load time, and keep the result in a local.
- Never ask users to disable mod security (ContentDB rejects such mods).

## Performance

- Prefer node timers (`core.get_node_timer(pos)`) over ABMs for per-node behaviour.
- Keep ABMs (active block modifiers) cheap, with a sensible `interval` and `chance`.
- Use VoxelManip for bulk map changes. Avoid `core.get_node` and `core.set_node` in large loops.
- Keep `register_globalstep` callbacks light. Accumulate `dtime` and work every N seconds.

## Common mistakes

- **Holding on to ObjectRefs** across callbacks or `core.after`. Store the player name and look the player up again with `core.get_player_by_name`.
- **Changing an ItemStack copy without writing it back** (`inv:set_stack(list, i, stack)`, or return it from `on_use`).
- **Calling another mod's API without declaring the mod** in `depends` or `optional_depends`. This works by luck, then breaks in other games or load orders. See the luanti-dependencies skill.
- **Assuming Minetest Game.** `default:*` items and `default.*` functions don't exist in Mineclonia, VoxeLibre, NodeCore and many others.
- **Using features newer than `min_minetest_version`.** Check `core.features` or `lua_api.md`.

## Done means

- `luacheck .` is clean.
- `ldg lint .` has no errors.
- `avanti test` passes in every game listed in `supported_games`.
- Player-facing strings are translatable.
- `LICENSE` covers every media file. AI-generated assets are listed there, and `ai_disclosure` in `.cdb.json` is accurate.
