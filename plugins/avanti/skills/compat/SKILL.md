---
name: compat
description: Check and improve cross-game compatibility of a Luanti mod - static analysis (ldg compat/lint) plus headless runs in each game, then concrete code changes to make failing games work.
argument-hint: [path] [games, e.g. minetest,mineclonia,mineclone2]
---

# /avanti:compat

Arguments: `$ARGUMENTS`. The path defaults to the current directory; games default to `supported_games`, else minetest, mineclonia and mineclone2.

1. **Static check:** run `ldg compat <path> --games <games>` and `ldg lint <path>`.
2. **Dynamic check:** run `avanti test <path> --game <g>` for each game (add `--keep` when something fails).
3. **Diagnose each failing or risky game.** Combine the resolution ("missing X"), the lint findings, and the errors in `debug.txt`. For anything non-obvious, delegate to the `compat-investigator` agent with the log path.
4. **Propose fixes** following `avanti:luanti-dependencies`: optional dependencies with guards, xcompat, groups in recipes, aliases. Show the code changes and apply them once the user agrees.
5. **Re-run** `avanti test` until every target game passes, or until a game is clearly out of reach. In that case, propose adding it to `unsupported_games` and explain why.
6. **Report** a before/after matrix.
