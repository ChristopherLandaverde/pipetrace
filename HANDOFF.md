# Handoff — PipeTrace

`Handoff note · 2026-11-22 · State, blockers, and the next steps`

Read this first. It records where the build stopped and how to resume.

## Where things stand

```
□ OBSERVED   Repo: github.com/ChristopherLandaverde/pipetrace (public since 2026-11-22)
             main carries PRs #1-#11; release v1.0.0
✓ VERIFIED   test_local.py 27/27 · check_repository.py PASS · dbt parse per connector
             Native BigQuery build in GitHub Actions on dbt 1.12.7 (run 45029750908):
             native 54/54, Fivetran-shaped 57/57, Airbyte-shaped 55/55
× OPEN       Not yet run against real source data or a live Fivetran/Airbyte connection.
             GTM snippets in docs/setup-guide.md not yet run on a live site.
```

## How the native test runs now

No Terminal steps. The `Native BigQuery walkthrough` workflow runs on PRs that touch models, macros, tests or the fixture, and can be started by hand from the Actions tab.

- GCP project `foco-revops-ci`: no billing, so BigQuery runs in the free sandbox.
- Service account `foco-ci-walkthrough`: BigQuery Job User and Data Editor on that project only.
- Workload Identity Federation pool `github`, provider `foco-revops-warehouse`: accepts only this repository. No key file. The provider and GCP project keep their original IDs, because Google does not allow renaming them.
- It runs as a matrix over `native`, `fivetran` and `airbyte` fixtures. Logs are kept as `walkthrough-logs-<connector>` artifacts for 7 days. Pull requests from forks skip it (no OIDC token).

## Cost guards

- Every query is capped at 1 GB billed, about $0.006. The fixture is a few KB, so a run costs well under a cent.
- Every table and view the run creates expires after 7 days. The expiry is set on each dataset when it is created, so it holds even if a run stops early.
- Datasets are named `foco_fixture_<timestamp>_{ga4,hubspot,salesforce,models}`. Existing tables are never touched.

## Why the test runs in GitHub Actions

The Claude workspace and the Mac VM both block `*.googleapis.com`, so Claude cannot reach BigQuery directly. GitHub's runners can. Claude starts runs and reads their logs through the GitHub API, so no Terminal step is needed. To run locally instead, install the Google Cloud SDK and run `bash scripts/run_walkthrough.sh <dev-project-id>`.

## Local checkout

`~/projects/foco-revops-warehouse` tracks `origin/main` (realigned 2026-11-17). The two pre-import commits are kept on `backup/pre-github-import`.

## Decisions still open

| Decision | Default |
|---|---|
| Submit to dbt Hub (PR to dbt-labs/hubcap adding `ChristopherLandaverde: [pipetrace]` to hub.json) | Prepared, not sent: it is a public post in dbt Labs' repo and needs Christopher's yes |
| Live data agent | Needs billing on `foco-revops-ci` (Christopher) |
| GA4 cross-check | Needs a GA4 property with BigQuery export (focosys.io's own) |
| First real-data run | Christopher's own stack or a client engagement; then update README, VALIDATION and release notes |

## Links

- PR #1 (merged): https://github.com/ChristopherLandaverde/pipetrace/pull/1
- Validation record: `VALIDATION.md`
- Walkthrough detail: `docs/synthetic-walkthrough.md`
