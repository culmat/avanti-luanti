---
name: new-mod
description: Create a new Luanti mod with the avanti template - checks the name on ContentDB, scaffolds mod.conf/init.lua/tests/CI/LICENSE/.cdb.json, and optionally creates its GitHub repo.
argument-hint: <modname> [what the mod should do]
disable-model-invocation: true
---

# /avanti:new-mod

Arguments: `$ARGUMENTS`. The first word is the technical mod name; the rest describes the mod.

1. **Understand the idea.** If there's no description, ask one short question about what the mod should do and for whom. Load the `avanti:luanti-modding` and `avanti:luanti-dependencies` skills.
2. **Check the name.** Run `ldg name-check <name>` (or the `name_check` MCP tool).
   - Names are `[a-z0-9_]+`. ContentDB's "right to a name" rule (policy 3.1) means a taken name needs another choice, unless this really is a fork or drop-in replacement.
   - If it's taken, propose 2–3 free alternatives and ask.
3. **Pick target games.** Default: `minetest,mineclonia,mineclone2`.
   - If the idea is inherently game-specific (e.g. extends `mcl_*` features), say so and narrow the list.
   - Check any dependencies you plan to use with `ldg providers <name>`, and prefer game-agnostic ones (e.g. `xcompat`).
4. **Scaffold** in the current directory (unless the user names another one):
   ```sh
   avanti new <name> --description "<one sentence>" --games <g1,g2,...> [--license MIT|LGPL-2.1-or-later] [--ai ASSISTED|GENERATED]
   ```
   The defaults are MIT for code, CC-BY-SA-4.0 for media, and `ai_disclosure: ASSISTED`. Use `GENERATED` if AI will produce textures or sounds (allowed, but they must be listed in `LICENSE`).
5. **Verify** with `avanti test <name>`. It should PASS in every target game before any feature work.
6. **Offer, don't do:** "Create the GitHub repo `<owner>/<name>` and push the initial commit?" Only on an explicit yes:
   ```sh
   cd <name> && git add -A && git commit -m "Initial scaffold" && gh repo create <owner>/<name> --public --source . --push
   ```
7. **Summarize.** List the files created and the next step: implement features (the `mod-builder` agent fits well), then run `/avanti:test`.
