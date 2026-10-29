# tools/

Standalone programs that sit beside the harness without being part of it.
Nothing here is a pnpm workspace package, and nothing here is compiled or
linted by the TypeScript build: `.oxlintrc.json`, `.jscpd.json` and the
repository-wide `scripts/verify-*` gates skip `tools/` as they skip `vendor/`.

| Path | What it is | License |
|---|---|---|
| `freellmapi/` | [FreeLLMAPI](https://github.com/tashfeenahmed/freellmapi), git subtree at `v0.16.12` (upstream commit `36826e7`) | MIT (see `freellmapi/LICENSE`) |
| `heretic/` | [Heretic](https://github.com/p-e-w/heretic), git subtree at upstream commit `a2e626f` | AGPL-3.0 (see `heretic/LICENSE`) |
| `skills/heretic/` | dsh skill that drives Heretic from an agent session | MIT, like the rest of the repository |

## FreeLLMAPI

The harness reaches FreeLLMAPI over its OpenAI-compatible `/v1` API (the
`freellmapi` route of `llm-pi-ai`), never by importing its code. The
`Deploy image` workflow builds `ghcr.io/<owner>/deepseek-harness-freellmapi` for amd64 and
arm64 from this subtree with its own `Dockerfile`, and
`deploy/oracle/compose.yml` runs that image beside the harness.

Update it to a newer release:

```sh
git subtree pull --prefix=tools/freellmapi https://github.com/tashfeenahmed/freellmapi.git <tag> --squash
```

Then write the release's upstream commit into `tools/freellmapi.upstream-commit`
(the image passes it as `FREELLMAPI_COMMIT_SHA`, which FreeLLMAPI's update
checker compares against) and update the version in this file. FreeLLMAPI keeps its own
tests: `cd tools/freellmapi && npm ci && npm test`.

## License boundary

The harness is MIT. Heretic is AGPL-3.0 and is only ever run as a separate
program through its command line, so the two are an aggregate, not a combined
work. Keep it that way: do not import Heretic code from `packages/` or
`apps/`, and do not copy its files elsewhere in the repository. Models that
Heretic produces carry the license of their base model, not the AGPL.

## Update Heretic

```sh
git subtree pull --prefix=tools/heretic https://github.com/p-e-w/heretic.git <commit> --squash
```

Then update the commit in this file and in the skill, and let the
`Heretic` workflow run its checks.

## Run Heretic's own checks

```sh
cd tools/heretic
uv sync --all-extras --dev
uv run ruff format --check .
uv run ruff check --extend-select I .
uv run ty check --error-on-warning .
uv run python -m unittest discover -s tests -p 'test_*.py'
uv run tests/run_tests.py
```

`tests/run_tests.py` runs Heretic on tiny random models and compares every
output file with the SHA256 sums in `tests/*/SHA256SUMS.*`. It needs no GPU,
but it downloads PyTorch and the test models (a few GB).

## Make the skill available to dsh

Add the skill directory to the profile's `skill-filesystem` entry, for
example in `~/.dsh/profiles/web/cordis.patch.yml`:

```yaml
- id: skill-filesystem
  config:
    customSkillDirs:
      - <absolute path to this repository>/tools/skills
```
