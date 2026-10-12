# {{title}}

{{description}}

## Supported games

Tested headlessly in: {{supported_games}} (see CI). Other games may work if they provide the
dependencies listed in `mod.conf`.

## Dependencies

None yet. See `depends` / `optional_depends` in [mod.conf](mod.conf).

## Installation

Install from [ContentDB](https://content.luanti.org) through the Luanti main menu, or clone
this repository into your `mods/` folder and enable it for your world.

## Development

This mod was created with [avanti-luanti](https://github.com/culmat/avanti-luanti).

```sh
avanti test            # luacheck + ldg lint + headless run in every supported game
avanti play --game minetest   # creative world with this working copy (no hot reload: rerun after edits)
```

## AI disclosure

Developed with AI assistance (ai_disclosure: {{ai_disclosure}} in `.cdb.json`); every change is
reviewed by a human maintainer. AI-generated media, if any, is listed in [LICENSE](LICENSE).

## License

Code: {{license}}. Media: CC-BY-SA-4.0. See [LICENSE](LICENSE).
