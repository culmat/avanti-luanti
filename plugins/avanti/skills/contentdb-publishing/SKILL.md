---
name: contentdb-publishing
description: Prepare and publish Luanti (Minetest) packages on ContentDB (content.luanti.org) - policy checklist (licenses, right to a name, game prefixes, screenshots, AI disclosure), .cdb.json fields, release methods (webhooks, API, polling), and community etiquette. Use before any release or when preparing a mod for the community.
when_to_use: Releasing a mod, filling .cdb.json or LICENSE, choosing a mod name, asked about ContentDB rules, or before running /avanti:release.
---

# Publishing on ContentDB

**Nothing gets published without the user's explicit go-ahead in this conversation.** That covers creating a package, a release, a forum post, or an upstream issue. Prepare everything, show it, and ask.

## Policy checklist

Source: https://content.luanti.org/policy_and_guidance/

| Area | Rule |
|---|---|
| Name | The technical name must be free (policy 3.1, "right to a name"). Check with `ldg name-check NAME`. Forks or drop-in replacements may reuse a name only if they really are replacements (3.2). New mods introduced by a game need the game's prefix (3.3). |
| License | A `LICENSE` file with an FSF/OSI-approved code license (MIT, LGPL-2.1-or-later, …) and a free media license (CC-BY-SA-4.0, CC0, …). No CC "NC" or "ND" licenses, and "public domain" alone isn't valid. The template's `LICENSE` has code, media and AI-assets sections; keep the attributions complete. |
| Quality | Useful content, English title and short description, at least one *non-misleading* screenshot (`avanti screenshot` renders real in-game ones, see below) (uploaded on ContentDB; 3:2 at 300×200 minimum). WIP must be labelled (`dev_state`). |
| Security | No obfuscated code, no ads, no asking users to disable mod security. Insecure or HTTP APIs need a clear reason. |
| AI disclosure | `.cdb.json` `ai_disclosure` is mandatory and must be true, and significant AI-generated assets must be credited in `LICENSE`. Low-effort "slop" may be rejected. |

`ai_disclosure` values:

| Value | When |
|---|---|
| `NONE` | No generative AI was used |
| `ASSISTED` | AI helped. A human wrote or reviewed and understands the code, and the media is human-made. This is the avanti default. |
| `GENERATED` | Substantial code or media was produced by AI, e.g. AI textures or sounds |

## .cdb.json (package metadata kept in the repo)

The schema is at `https://content.luanti.org/api/cdb_schema/`. Fields avanti uses:

```json
{
  "type": "MOD", "title": "…", "short_description": "…",
  "license": "MIT", "media_license": "CC-BY-SA-4.0",
  "ai_disclosure": "ASSISTED", "dev_state": "WIP",
  "repo": "https://github.com/OWNER/NAME", "issue_tracker": "https://github.com/OWNER/NAME/issues",
  "tags": ["…"]
}
```

`tags` must come from ContentDB's list (see the schema). Engine compatibility comes from `min_minetest_version` and `max_minetest_version` in `mod.conf`.

## First publication (done by the human on the website)

1. Create the package at https://content.luanti.org/packages/new/ with the repo URL. ContentDB imports metadata from `mod.conf` and `.cdb.json`.
2. Upload screenshots and submit for approval. An approver reviews it; reply to their comments.
3. Set up automatic releases: either a GitHub webhook (https://content.luanti.org/help/release_webhooks/) or *Update settings* (polls daily for new tags).

## Releases

- Prefer **git tags plus a webhook**. Every pushed tag becomes a release, which keeps ContentDB and git in sync.
- To use the API instead, the user creates a token at `/user/tokens/` scoped to the one package and keeps it in the `CONTENTDB_TOKEN` environment variable (never in the repo). Then:
  ```sh
  avanti cdb release v1.2.0 --notes-file NOTES.md   # creates the release from the pushed tag, waits for the import
  ```
  It exits 0 once ContentDB has imported the release, 1 if the import failed (the reason is printed, e.g. a game-support conflict), and 2 if it's still running after `--timeout`. Without avanti, the call is `POST /api/packages/<author>/<name>/releases/new/` with `{"method": "git", "ref": "v1.2.0", "title": "1.2.0"}`.
- **Packages inside a monorepo** (a mod in a subfolder) can't use git releases or webhooks: ContentDB only imports a repository root (or a root holding exactly one folder). Upload a zip instead, with the package in one top-level folder and dev files left out:
  ```sh
  avanti cdb release 1.2.0 mods/my_pack --zip dist/my_pack-1.2.0.zip --notes-file NOTES.md
  ```
  This sends `title`, `file` and `release_notes` as a multipart form to the same endpoint and waits for the import like a git release.
- `avanti cdb status [PATH|AUTHOR/NAME]` is the read-only check, with no token needed: package state (`WIP`, `READY_FOR_REVIEW`, `APPROVED`, ...), latest release and whether it matches a local tag, game support and maintainers (`--json` for the raw data). Run it before a release, and after one to confirm it went through (webhook imports are asynchronous too). The author comes from `AVANTI_CONTENTDB_USER`.
- Release notes should be human-checked and short: what changed for players and server owners.
- `.gitattributes` `export-ignore` keeps `.github/`, `.luacheckrc` and similar out of the release zip.

## Community

- The forum topic goes in "WIP Mods", later "Mod Releases", titled `[Mod] Title [modname]`. The human posts it in their own words.
- Respond to issues. Upstream fixes beat forks; ContentDB policy asks you to try contributing before forking.
- Generative-AI attitudes in the community range from accepting to hostile. Be transparent, keep quality high, and never present AI output as human-written.

## Screenshots

`avanti screenshot [PATH] [--game ID]...` (macOS, the Luanti app) renders the mod in the real client and
captures only the Luanti window: 1500x1000 (3:2) images for ContentDB, plus `screenshot.png` (600x400,
the in-game content manager) if the mod has none.

- **Scene:** the mod's own `tools/showcase` mod builds it on join and calls `avanti_camera.scene_ready()`
  when done (see culmat/glowshroom). Without one, a generic showcase lines up the mod's nodes on a daylit
  platform; tool-only mods are shown in hand.
- **Shot list:** `screenshots/shots.json` holds camera positions (eye position, `yaw`/`pitch` in degrees
  or a `look_at` point), `time` of day (0–1), `fov` and `settle` seconds. All shots are taken in one engine
  start per game: `screenshots/<game>-<name>.png`. Without a list there is one shot with the scene's own
  camera (`screenshots/<game>.png`). The world seed is fixed (`--seed`, default `avanti`), so positions
  stay valid across runs.
- **Videos:** a shot with `keys` (keyframes `{t, pos, yaw/pitch or look_at, time, fov}`, smooth spline,
  `ease` `inout` or `linear`) or `orbit` (`center`, `radius`, `height`, `turns`, `start`; whole turns loop
  seamlessly) plus `duration` and `fps` (default 30) is rendered frame by frame to
  `screenshots/<game>-<name>.mp4` (H.264); `--gif` adds a 600 px GIF for READMEs. Rendering is lockstep,
  about 7 frames per second of wall time, so every frame is exact. Times above 1 wrap, so `time` 0.8 → 1.2
  runs through midnight. ContentDB has no video upload: `.cdb.json` `video_url` links a hosted video (schema checked 2026-10-11).
- **Positioning the camera:** `avanti screenshot --record --game ID` opens the game in the same world.
  The user flies to a spot (K), sets the time (`/time`) and types `/shot <name>` for a still, or
  `/key <video> [seconds]` at each keyframe of a video (`/preview <video>` plays the path, `/unkey <video>`
  drops the last key). Quitting merges the shots into the list. You can also write `look_at` shots by hand
  from the scene's coordinates.
- The client needs a real desktop session. An agent's sandboxed shell can't open windows, so the command
  must run unsandboxed or in the user's terminal.
- Keep `screenshots/` and `tools/` out of releases with `.gitattributes` `export-ignore`, and always look
  at the images before uploading them.
