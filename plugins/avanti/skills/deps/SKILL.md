---
name: deps
description: Explain the dependency situation of a Luanti mod, modpack or ContentDB package in plain language - what each dependency stands for, who provides it, which games satisfy it, and what to change.
argument-hint: <path | author/name> [--game <game>]
---

# /avanti:deps

Target: `$ARGUMENTS` (default: the current directory).

1. **Gather facts:** run `ldg deps <target> --json --tree`, `ldg compat <target> --json` and, for a local path, `ldg lint <target> --json`. Add `ldg resolve <target> --game <game> --json` if a game was given.
2. **Explain each hard and optional dependency** in a short table: what API it is (e.g. "`default`: Minetest Game's core items and sounds"), how many standalone mods and games provide it, and what that implies ("only games bundle it, so this mod can't run in Mineclonia").
3. **Show which games work** (`ok` / `risky` / `unsatisfiable`). Point out where ContentDB's own claim differs, if `contentdb_says` is present.
4. **List undeclared references** (LDG001–LDG003) with file:line and the concrete fix.
5. **Recommend the smallest changes** that widen compatibility. Typical moves: hard → optional with a guard, `default` sounds → `xcompat.sounds`, adding `optional_depends` for load order. Follow the `avanti:luanti-dependencies` skill.

Keep it factual. If `ldg info` says the database is older than a week, mention it and suggest `ldg update`.
