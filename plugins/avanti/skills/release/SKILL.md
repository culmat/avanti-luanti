---
name: release
description: Release a Luanti mod - runs the ContentDB readiness checklist (license, AI disclosure, metadata, lint, tests in every supported game), then tags, pushes and creates the ContentDB release, asking for confirmation before every external step.
argument-hint: [version, e.g. 1.0.0]
disable-model-invocation: true
---

# /avanti:release

Version: `$ARGUMENTS`. If it's missing, propose one: the last tag plus a semver bump, or `0.1.0` for a first release. Load the `avanti:contentdb-publishing` skill.

## 1. Readiness gate (local, no side effects)

Check each item and show a ✅/❌ table. Stop on any ❌ and offer fixes.

- `LICENSE` has a code license, a media license, attribution for every file in `textures/`, `sounds/` and `models/`, and the AI-assets section filled in (or "(none)").
- `.cdb.json` is valid. `ai_disclosure` honestly reflects how code and media were made: ask the user to confirm it. `license` and `media_license` match `LICENSE`.
- `mod.conf`: `description` is present and `supported_games` lists exactly the games that pass. `min_minetest_version` is set.
- README says what the mod does, its dependencies, supported games and the AI disclosure.
- `ldg name-check <name> --author <contentdb user>` passes (first release only).
- `avanti test` passes in every supported game. For the engine matrix, add `--runner docker --engine <min> --engine 5.17.0` if Docker is available.
- `git status` is clean. Draft release notes from `git log <last-tag>..HEAD`, written for players and server owners. The user edits or approves them.

## 2. External steps (ask before each one, one at a time)

1. `git tag -a v<version> -m "<version>"`, then `git push origin main --tags`.
2. **First release?** Hand over the website steps from the contentdb-publishing skill: create the package, add screenshots, submit for approval, set up the webhook. Don't automate them.
3. **Later releases:** if the webhook is set up, the tag is enough. Otherwise, with `CONTENTDB_TOKEN` set by the user, run `avanti cdb release v<version> --notes-file <approved notes>`. It waits for ContentDB's import and prints the reason if it fails. Never print or store the token.
4. **Confirm:** `avanti cdb status` until the latest release matches the tag (give a webhook import a minute or two). Report the package state, the game support ContentDB computed, and any failure, which usually means a game-support conflict between `supported_games` and the dependencies.
5. Optional: a forum post. Give the user the facts (title format `[Mod] Title [modname]`, links, supported games, license); they write the post themselves.

Finish by reporting the release URL, or what's left for the user to do.
