---
name: give-back
description: Turn findings (undeclared dependencies in other mods, game load-order bugs, ContentDB data issues, missing xcompat coverage, tooling gaps) into well-evidenced upstream reports - collected locally for a human to file in their own words. Never posts anything.
argument-hint: [finding or package, e.g. "WARN errors from mineclonia" or mt-mods/xcompat]
disable-model-invocation: true
---

# /avanti:give-back

Topic: `$ARGUMENTS`. If it's empty, look at recent `avanti test` WARNs, `ldg lint` findings on other packages, and `ldg` results from this conversation.

avanti-luanti exists to give back to the Luanti community. Help with the *evidence*, and leave the *voice* to the human.

1. **Identify the upstream:**
   - the package repo (`ldg sql "select repo from package where author||'/'||name = '<a/n>'"`),
   - the game repo,
   - ContentDB (https://github.com/luanti-org/contentdb),
   - xcompat, luacheck, flint or luma.
   Check its contributing and AI policy first. **The Luanti engine's policy (`~/.avanti/corpus/engine/doc/developing/ai_policy.md`) forbids AI-written issue or PR text and autonomous AI contributions in luanti-org repos.** Treat other repos the same way unless their policy says otherwise.
2. **Collect verifiable evidence:**
   - minimal reproduction steps (an `avanti test` command, game, engine version),
   - exact log lines,
   - `ldg lint` findings with file:line at a specific commit,
   - the suggested fix as a code diff.
3. **Check it's not already known:** `gh issue list -R <owner/repo> --search "<keywords>" --state all`.
4. **Write a notes file** to `drafts/<repo>-<slug>.md` in the current project (create `drafts/` and gitignore it). It holds facts, evidence and the suggested fix as bullet points, *not* finished prose. Add a header noting that the user should write the final issue or PR text in their own words, and disclose AI assistance where the project expects it.
5. **For code fixes in third-party mods,** you may prepare a branch in a local clone. Pushing, forking and opening PRs happen only when the user explicitly does it, or explicitly asks you to for a repo whose policy allows AI-assisted contributions.
6. Record the finding in `docs/upstream.md` of avanti-luanti if it's a tooling or data issue worth tracking.
