# Contributing

Thanks for helping! avanti-luanti is meant to be useful to the whole Luanti community, whether or not you use Claude Code.

- **Bugs and ideas:** open an issue. For dependency-graph or lint problems (wrong providers, false LDG findings), please open them on [luanti-depgraph](https://github.com/culmat/luanti-depgraph/issues).
- **Pull requests:** keep them focused.
  - `shellcheck` must pass, and the scripts must work with macOS's bash 3.2.
  - `claude plugin validate . --strict` must pass.
  - CI runs both, plus a self-test that scaffolds and tests a mod in Docker.
- **Skills and docs:** state facts that can be checked, with links to the source (`lua_api.md`, ContentDB help pages, engine code).
- **AI assistance** is welcome if disclosed in the PR and you understand the change. See [docs/ai-policy.md](docs/ai-policy.md). Upstream Luanti projects have their own, stricter rules; respect them.
- **Reference games:** add one by appending a line to `plugins/avanti/lib/games.tsv` (game ID, folder, git URL). Its game ID must exist on ContentDB for dependency resolution.

By contributing you agree that your contributions are licensed under the MIT license.
