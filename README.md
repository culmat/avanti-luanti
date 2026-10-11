# avanti-luanti

**An agent-based factory for [Luanti](https://www.luanti.org) (formerly Minetest) mods, built in the open to give back to the Luanti community.**

avanti-luanti is developer tooling. It is **not a Luanti mod** and doesn't run inside the game. It runs on your machine and in CI, and helps you (and Claude Code agents) build, test and publish Luanti mods that work across games.

```
 YOUR MACHINE / CI                                         LUANTI ENGINE (headless, native or Docker)
 ┌────────────────────────────────────────────────┐       ┌──────────────────────────────────┐
 │ Claude Code + Claude Code plugin "avanti"       │       │ game: Minetest Game / Mineclonia │
 │   skills · /avanti:* commands · agents · hooks  ├──────▶│       / VoxeLibre / devtest      │
 │ avanti CLI   scaffold · test matrix · serve     │ tests │ + your mod + resolved deps       │
 │ ldg          dependency graph (luanti-depgraph) │       └──────────────────────────────────┘
 │ zg           semantic search over Luanti code   │                 │ publish (human-approved)
 └────────────────────────────────────────────────┘                 ▼
                                                        ContentDB  ·  GitHub culmat/<mod>
```

| Repo | What |
|---|---|
| **culmat/avanti-luanti** (this repo) | `setup.sh`, the `avanti` CLI, the **Claude Code plugin** `avanti` (skills, commands, agents, hooks, MCP config), the mod template, reusable mod CI, docs |
| [culmat/luanti-depgraph](https://github.com/culmat/luanti-depgraph) | `ldg`: dependency graph of all ContentDB content. CLI, MCP server and SQLite/Cypher data. Useful without Claude. |
| `culmat/<modname>` | One repo per mod produced by the factory (ContentDB releases one package per repo) |

## Why

The pain point is that **dependencies between Luanti games and mods are hard to reason about**:

- A dependency names a mod name (an API), not a package. `depends = default` is satisfied by 37 games and by no standalone mod.
- Games bundle and reuse mod names.
- Undeclared dependencies only show up in other games or other load orders.

[docs/luanti-primer.md](docs/luanti-primer.md) explains this in detail. The factory attacks it from three sides:

1. **Know the graph.** `ldg providers / deps / resolve / compat / rdeps` over all ~3,500 ContentDB packages, plus static analysis of the sources.
2. **Lint for undeclared dependencies.** `ldg lint` finds `default.*` calls, `"mcl_core:*"` item strings and `get_modpath` checks that `mod.conf` doesn't declare.
3. **Test in real games.** `avanti test` runs the mod headlessly in Minetest Game, Mineclonia, VoxeLibre and devtest with random mod load order, across engine versions in CI.

## Quick start

```sh
git clone https://github.com/culmat/avanti-luanti && cd avanti-luanti
./setup.sh            # tools, ldg, Luanti, reference games, corpus + search index, Claude Code plugin
avanti doctor
```

**Accounts and tokens:** `./setup.sh --secrets` (or later `avanti secrets setup`) opens the sign-up and token pages of ContentDB, Sketchfab and api.data.gov and stores what you paste in `~/.config/avanti/secrets.env` (mode 600). `avanti secrets push OWNER/REPO` copies them into a repository's Actions secrets; the ContentDB token goes into a `contentdb` environment that asks for your approval before each release.

**macOS:** needs Homebrew; uses the Luanti app for native tests. **Linux:** install `luantiserver`, or use Docker. **Disk:** about 1 GB under `~/.avanti` (games, corpus, index). `./setup.sh --minimal` skips the package corpus and the index.

Then, in Claude Code:

```
/avanti:new-mod glowing_mushrooms Mushrooms that glow and spread in caves
/avanti:test
/avanti:compat
/avanti:release 0.1.0
```

Or without Claude:

```sh
avanti new glowing_mushrooms --description "Mushrooms that glow and spread in caves."
cd glowing_mushrooms && avanti test
ldg compat . && ldg lint .
```

## What's in the Claude Code plugin

| Kind | Name | Purpose |
|---|---|---|
| Skill | `luanti-modding` | Mod anatomy, conventions, API lookup (never guess: grep `lua_api.md`, search the corpus), security, performance |
| Skill | `luanti-dependencies` | The dependency mental model, `ldg` usage, cross-game patterns (optional deps with guards, xcompat, groups, aliases) |
| Skill | `luanti-testing` | `avanti test`, writing mtt tests, luacheck, reading failures |
| Skill | `contentdb-publishing` | Policy checklist, `.cdb.json`, AI disclosure, release methods |
| Command | `/avanti:new-mod` | Name check → scaffold → first green test → optional GitHub repo |
| Command | `/avanti:deps` | Explain a mod's or package's dependencies in plain language |
| Command | `/avanti:compat` | Static and dynamic per-game compatibility, then fixes |
| Command | `/avanti:test` | Run and interpret the test matrix |
| Command | `/avanti:release` | Readiness gate, then tag / push / ContentDB release, each step confirmed |
| Command | `/avanti:give-back` | Turn findings into evidence for upstream reports, written by a human |
| Agent | `mod-builder` | Implements features and keeps `avanti test` green |
| Agent | `mod-reviewer` | Read-only review: correctness, security, dependencies, release readiness |
| Agent | `compat-investigator` | Root-causes a failing game and proposes the smallest fix |
| Hook | PostToolUse | luacheck/stylua after Lua edits, `ldg lint` after `mod.conf` edits (feedback only) |
| Hook | SessionStart | In Luanti projects: what's available and what's missing |
| MCP | `luanti-depgraph` | `ldg mcp`: read-only dependency graph tools and `search_code` (Lua-aware code search) |
| MCP | `zvec-grep` | Local semantic search over `~/.avanti/search`, a text-only mirror of the corpus: engine docs and builtin, games, top packages, modding book |

Install it without `setup.sh`:

```sh
claude plugin marketplace add culmat/avanti-luanti
claude plugin install avanti@avanti-luanti
```

The `avanti` and `ldg` CLIs must also be on your PATH (`setup.sh` does that).

## avanti CLI

```
avanti doctor                      check tools, games, database, index
avanti games sync [ID...]          minetest, mineclonia, mineclone2, devtest
avanti corpus sync [--top N]       engine docs + games + vendored refs + top-N package sources, then index
avanti new NAME [...]              scaffold from plugins/avanti/templates/mod
avanti test [PATH] [...]           lint + headless run per game × engine (native or Docker)
avanti serve [PATH] --game ID      local server for play-testing with the Luanti client
avanti screenshot [PATH]           in-game screenshots and videos from a shot list, one engine start per game (macOS)
avanti screenshot --record --game ID   fly around and save camera positions (/shot) and video keyframes (/key)
avanti index [PATH]                zvec-grep index
avanti cdb status [PATH|A/NAME]    ContentDB state, latest release vs local tag, game support
avanti cdb release REF [PATH]      create a ContentDB release from a pushed tag (CONTENTDB_TOKEN)
```

**Test statuses:**

| Status | Meaning |
|---|---|
| PASS | Clean |
| WARN | Errors that don't mention your mod (usually game load-order bugs) |
| FAIL | Errors naming your mod, crash, timeout, or unresolvable dependencies |
| BROKEN | The game itself can't start on that engine (not counted as a failure) |
| SKIP | Game not synced, or engine below the game's minimum |

Mods made with the template get CI from [.github/workflows/mod-ci.yml](.github/workflows/mod-ci.yml): luacheck + `ldg lint`, then games × engines `5.10.0, 5.17.0` in the official server images.

## Principles

- **Give back.** Everything is MIT and on GitHub. Findings go upstream: see [docs/upstream.md](docs/upstream.md) and `/avanti:give-back`.
- **Be transparent about AI.** Mods declare `ai_disclosure`, and AI-generated media is allowed but listed in `LICENSE`. Agents never publish, post or open upstream PRs on their own, and humans write to humans. See [docs/ai-policy.md](docs/ai-policy.md).
- **Be a good citizen of ContentDB.** Identified, rate-limited, cached; a nightly public snapshot instead of everyone crawling ([docs/contentdb.md](docs/contentdb.md)).
- **Verify; don't guess.** Skills send agents to `lua_api.md` and real code. Tests run in real games.

## Layout

```
setup.sh                         workstation bootstrap
.claude-plugin/marketplace.json  marketplace "avanti-luanti" → plugins/avanti
plugins/avanti/                  the Claude Code plugin (+ the avanti CLI in bin/, its lib/ and the mod template)
.github/workflows/mod-ci.yml     reusable CI for mods; ci.yml tests this repo
docs/                            primer, ContentDB, AI policy, upstream backlog
```

## Roadmap

- **Iteration 1 (now):** tooling, i.e. setup, plugin, CLI, template, CI, and luanti-depgraph with CLI, MCP and the nightly snapshot.
- **Iteration 2 (done):**
  - [dependency explorer](https://culmat.github.io/luanti-depgraph/) on GitHub Pages (sigma.js overview, per-game coloring, Cytoscape dependency trees, SQL in the browser);
  - Lua-aware code search (`ldg code search`, MCP `search_code`);
  - dependency and provides history carried across nightly snapshots;
  - analysis that understands conditionally loaded files;
  - PyPI release workflow;
  - upstream findings with patches (`docs/upstream.md`);
  - the first factory-made mod, [Glowshrooms](https://github.com/culmat/glowshroom).
- **Next:** more mods, upstream PRs filed by the maintainer, per-release history backfill from git.

## License

MIT, see [LICENSE](LICENSE). Developed with AI assistance (Claude) and reviewed by the maintainer.
