---
name: test
description: Run the avanti test pipeline for a Luanti mod (luacheck, ldg lint, headless server runs per game and engine) and interpret the results, fixing what is clearly the mod's fault.
argument-hint: [path] [--game id]... [--engine version]... [--runner native|docker]
---

# /avanti:test

1. Run `avanti test $ARGUMENTS`. With no arguments it tests the current directory in its `supported_games`.
2. **Summarize the matrix:** PASS, WARN, FAIL or SKIP per game × engine.
3. **For each FAIL, find the cause:**
   - Lint errors are explained in the output.
   - "Dependencies can't be met" → check `ldg resolve`.
   - Errors naming the mod → read the cited file:line.
   - Timeouts → rerun with `--timeout 400 --keep` and read the log.
   Use the `avanti:luanti-testing` skill's failure table.
4. **Fix** what is clearly the mod's fault. Don't change tests just to make them pass. Re-run until green.
5. **WARN** means errors came from the game or other mods. Report them to the user without "fixing" them in the mod, and mention `/avanti:give-back` if one looks like an upstream bug.
6. **SKIP** means the game isn't synced: offer `avanti games sync <id>`.
