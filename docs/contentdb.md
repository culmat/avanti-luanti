# ContentDB: data model, API, game support and publishing

[ContentDB](https://content.luanti.org) is Luanti's package registry: about 3,500 approved packages, of which 3,184 are mods, 181 games and 132 texture packs (October 2026).

- **Stack:** Python/Flask, Postgres, Redis and Celery; AGPL-3.0.
- **Maintainer:** rubenwardy.
- **Source:** [luanti-org/contentdb](https://github.com/luanti-org/contentdb). It accepts outside contributions; ZenonSeth had several PRs merged in Sept–Oct 2026.

## Data model, as it relates to dependencies

| Concept | Meaning |
|---|---|
| Package | `author/name`, type `mod`, `game` or `txp`, a state (only `APPROVED` counts), aliases for renamed packages |
| MetaPackage | A technical mod name (`[a-z0-9_]+`) |
| `provides` | Every mod name inside a package's latest release: the mod itself, every mod of a modpack, every mod of a game |
| Dependency | Package → mod name, hard or optional |
| PackageGameSupport | Package → game, `supports`, `confidence` (1 detected, 10 from `.conf`, 11 set on the website) |

**Limitations to know:**
- Provides and dependencies are stored **per package, not per release**. They're overwritten on every release, so there's no history.
- A modpack counts as **one unit**, so its dependencies are the union of all its mods' dependencies (issue #560).
- Self-provided names are dropped.

## The API

Reference: https://content.luanti.org/help/api/. These are the endpoints luanti-depgraph uses:

| Endpoint | Use |
|---|---|
| `GET /api/packages/?fmt=vcs` | All packages with repo URLs, in one unpaginated call |
| `GET /api/dependencies/?n=300&page=k` | provides / depends / optional_depends for every package (~12 pages) |
| `GET /api/scores/` | Downloads and scores |
| `GET /api/updates/` | `author/name` (aliases included) → latest release ID; good for change detection |
| `GET /api/packages/<a>/<n>/` | Full package incl. `license`, `game_support`, `supports_all_games`, `maintainers` |
| `GET /api/packages/<a>/<n>/releases/` | Releases with `min_minetest_version` / `max_minetest_version` and `commit` |
| `GET /api/packages/<a>/<n>/dependencies/` | Each dependency with all candidate packages |
| `GET /api/cdb_schema/` | JSON Schema of `.cdb.json` |
| `POST /api/packages/<a>/<n>/releases/new/` | Create a release (token; `{"method":"git","ref":…}`). Returns `{"task": "/tasks/<id>/", "release": {…}}` |
| `GET /tasks/<id>/` | Import task status (`PENDING`/`STARTED`/`SUCCESS`/`FAILURE` plus `error`). JSON only with `Accept: application/json` and no `text/html`, otherwise HTML |
| `GET /api/whoami/` | `{is_authenticated, username}` for the token |

### Clients

Checked 2026-10-11: there's **no official CLI, client library, MCP server or GitHub Action** for ContentDB.
- [luctl](https://pkg.go.dev/github.com/brylie/luctl) (Go, MIT) wraps the API for server owners. It searches and installs packages but can't publish.
- Read access for avanti comes from luanti-depgraph (snapshot + MCP tools).
- `avanti cdb` covers the rest, using curl:
  - `status`: package state, latest release vs local tag, game support;
  - `release`: create a git release and poll its task;
  - `whoami`.
- Screenshots, metadata `PUT` and zip releases aren't wrapped; the website or webhook covers them.

Etiquette:
- Rate limits aren't documented, and ContentDB was DDoSed in April 2026, after which unidentified crawlers were blocked. **Always send a descriptive User-Agent, stay slow, cache, and prefer bulk endpoints.**
- luanti-depgraph runs at ≤2 req/s, caches details by release ID, and publishes a nightly snapshot so individual users never need to crawl.
- **Daily dump:** `/uploads/backup-YYYY-MM-DD.zip` contains `provides` and `game_support` but **no dependency lists**. It has been broken since 2026-10-02 ([#694](https://github.com/luanti-org/contentdb/issues/694)).

## How ContentDB computes game support

Source: `app/domain/game_support.py`.

1. Build a graph of approved mods and games: each package's `provides` and its **hard** dependencies.
2. A game supports itself.
3. For each hard dependency of a mod, look at every package that provides it:
   - If any provider is game-independent, the dependency is fine everywhere.
   - Otherwise take the union of the providers' supported games.
4. Intersect those sets across all hard dependencies.
   - An empty union means "Unable to fulfill dependency X".
   - An empty intersection means "Game support conflict".
5. Subtract `unsupported_games`. Check the `supported_games` claims against the result: claiming an impossible game is an error.
6. Updates are incremental. Errors are posted to the package thread and fail the release.

Known gaps:
- **Names only:** a same-name mod in another game counts even if its API differs ([luanti#12034](https://github.com/luanti-org/luanti/issues/12034)).
- **Optional dependencies are ignored,** so mods that support games only via optional deps need manual `supported_games`.
- **Modpacks** produce false cycles (#560). There are concurrency bugs (#573).
- **The `game=` filter** is experimental and doesn't follow aliases.

luanti-depgraph's `resolve` and `compat` mirror these rules per game. They add static analysis of the source and split modpacks into individual mods.

## Publishing

### Policy summary

Source: https://content.luanti.org/policy_and_guidance/.

- **Licenses:** a `LICENSE` file is mandatory, with an FSF/OSI-approved license for code and a free license for media. No NC/ND licenses; "public domain" alone isn't valid.
- **Names:** the first package to use a technical name owns it (3.1). Forks and drop-in replacements are the exception (3.2). Game-introduced mods need a game prefix (3.3).
- **Content:** useful; WIP labelled; English title and description; at least one non-misleading screenshot.
- **Forbidden:** obfuscation, ads, asking users to disable mod security.
- **AI:** AI-generated content must be disclosed (`ai_disclosure`), and significant AI assets credited in `LICENSE`. "Slop" may be rejected.

### Workflow

1. **First submission:** create the package on the website from the repo URL, add screenshots, and submit. An approver reviews it; states go `WIP` → `READY_FOR_REVIEW` → `APPROVED`, or `CHANGES_NEEDED`.
2. **Later releases:**
   - **Webhook** ([help](https://content.luanti.org/help/release_webhooks/)): GitHub `/github/webhook/` or GitLab `/gitlab/webhook/`. The API token is the webhook secret. A tag push creates a release.
   - **Polling** ([help](https://content.luanti.org/help/update_config/)): checks daily for a new tag or commit.
   - **API:** `POST …/releases/new/` with a package-scoped token. Tokens only work for the package author; co-maintainers can't use them yet (#612).
3. Keep development files out of release zips with `.gitattributes` `export-ignore`.

There's no official GitHub Action for ContentDB releases. The webhook plus tags is the simplest setup.
