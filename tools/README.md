# tools/

Standalone programs that sit beside the harness without being part of it.
Nothing here is a pnpm workspace package, and nothing here is compiled or
linted by the TypeScript build.

| Path | What it is | License |
|---|---|---|
| `heretic/` | [Heretic](https://github.com/p-e-w/heretic), git subtree at upstream commit `a2e626f` | AGPL-3.0 (see `heretic/LICENSE`) |
| `skills/heretic/` | dsh skill that drives Heretic from an agent session | MIT, like the rest of the repository |

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
