# Contributing to PipeTrace

`Contributor guide · Nov 2026 · How changes are checked before they merge`

PipeTrace is a governed modeling layer: a change is ready when it keeps every opportunity's credit summing to 1 and reconciling to deal value. Bug reports with a failing case are the most useful contribution.

## Before you open a pull request

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
python3 scripts/test_local.py          # relational acceptance tests, SQLite, no network
python3 scripts/test_agents.py         # data agent config tests
python3 scripts/check_repository.py    # run from a clean checkout
dbt deps && dbt parse --profiles-dir ci --no-partial-parse
dbt parse --profiles-dir ci --no-partial-parse --vars '{pipetrace_connector: fivetran}'
dbt parse --profiles-dir ci --no-partial-parse --vars '{pipetrace_connector: airbyte}'
```

To run the full build against BigQuery, use your own development project: `bash scripts/run_walkthrough.sh <dev-project-id>`. It creates expiring synthetic datasets and never touches existing tables.

## What CI runs

| Check | On | Needs |
|---|---|---|
| `validate` | Every push and pull request | Nothing |
| `walkthrough (native, fivetran, airbyte)` | Pull requests from branches of this repository, and manual runs | The maintainer's BigQuery sandbox |

GitHub does not give pull requests from forks the identity token the BigQuery sign-in needs, so the walkthrough is skipped on them (shown as skipped, not failed). A maintainer runs it before merging.

## Rules for changes

- Synthetic data only. Never commit client data, real CRM exports or credentials.
- Joins use record IDs and conversion tokens, never email.
- A new attribution path needs a test in `scripts/test_local.py` and, if it changes fixture output, an updated `tests/assert_synthetic_fixture.sql`.
- Do not change a test or a CI check just to make a failure go away.
- Record a design decision in `DECISIONS.md` with its reason.

## Reporting a bug

Use the bug report template. Include the dbt version, `pipetrace_connector`, the failing test or model, and the `pipetrace_doctor` output. Remove any client data first.

By contributing you agree that your contribution is licensed under the MIT License and that you follow the [code of conduct](CODE_OF_CONDUCT.md).
