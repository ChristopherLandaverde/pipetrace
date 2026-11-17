# Handoff — PipeTrace

`Handoff note · 2026-11-16 · State, blockers, and the next three steps`

Read this first tomorrow. It records where the build stopped and how to resume.

## Where things stand

```
□ OBSERVED   Repo: github.com/ChristopherLandaverde/pipetrace (private; renamed from foco-revops-warehouse 2026-11-17)
             main = 8592524: PR #1 merged 2026-11-17
✓ VERIFIED   test_local.py 14/14 · check_repository.py PASS · dbt parse in CI
             Native BigQuery build 45/45 in GitHub Actions (run 44109338907)
× OPEN       Not yet run against real source data (client engagement scope).
```

## How the native test runs now

No Terminal steps. The `Native BigQuery walkthrough` workflow runs on PRs that touch models, macros, tests or the fixture, and can be started by hand from the Actions tab.

- GCP project `foco-revops-ci`: no billing, so BigQuery runs in the free sandbox.
- Service account `foco-ci-walkthrough`: BigQuery Job User and Data Editor on that project only.
- Workload Identity Federation pool `github`, provider `foco-revops-warehouse`: accepts only this repository. No key file. The provider and GCP project keep their original IDs, because Google does not allow renaming them.
- Logs are kept as the `walkthrough-logs` artifact for 7 days.

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
| Make the repo public | Stay private until native tests pass. Publishing also opens a new loop while AdLinter → focosys.io is still open (Meadows rule) |
| Upgrade dbt from 1.10.x (dbt flags it deprecated) | Separate PR, with its own parse and native run |
| Run the walkthrough in CI | Later, via Workload Identity Federation. It needs a service account, which requires approval |

## Links

- PR #1 (merged): https://github.com/ChristopherLandaverde/pipetrace/pull/1
- Validation record: `VALIDATION.md`
- Walkthrough detail: `docs/synthetic-walkthrough.md`
