# Handoff — foco-revops-warehouse

`Handoff note · 2026-11-16 · State, blockers, and the next three steps`

Read this first tomorrow. It records where the build stopped and how to resume.

## Where things stand

```
□ OBSERVED   Repo: github.com/ChristopherLandaverde/foco-revops-warehouse (private)
             main = f222123, the initial import; draft PR #1 = build/brand-and-parse
✓ VERIFIED   test_local.py 14/14 · check_repository.py PASS · dbt parse in CI
             Native BigQuery build 45/45 in GitHub Actions (run 44109338907)
× OPEN       Not yet run against real source data. PR #1 not merged.
```

## How the native test runs now

No Terminal steps. The `Native BigQuery walkthrough` workflow runs on PRs that touch models, macros, tests or the fixture, and can be started by hand from the Actions tab.

- GCP project `foco-revops-ci`: no billing, so BigQuery runs in the free sandbox.
- Service account `foco-ci-walkthrough`: BigQuery Job User and Data Editor on that project only.
- Workload Identity Federation pool `github`, provider `foco-revops-warehouse`: accepts only this repository. No key file.
- Logs are kept as the `walkthrough-logs` artifact for 7 days.

## Cost guards

- Every query is capped at 1 GB billed, about $0.006. The fixture is a few KB, so a run costs well under a cent.
- Every table the run creates expires after 7 days.
- Datasets are named `foco_fixture_<timestamp>_{ga4,hubspot,salesforce,models}`. Existing tables are never touched.

## Why Claude could not run it

- The Claude workspace and the Mac VM both block `*.googleapis.com` (HTTP 403 from the proxy).
- Computer control cannot type into Terminal.
- Cloud Shell in Chrome froze while the repo was being pasted in, and its sign-in needs a verification code only you can enter.
- Permanent fix, if you administer the Claude org: allow `*.googleapis.com` and `accounts.google.com` under Admin settings → Capabilities → network access.

## Known issue: the local checkout's history is diverged

`~/projects/foco-revops-warehouse` has two older local commits (`b60b5d7`, `6acfc96`) that are not on GitHub. GitHub `main` is a fresh root commit with identical file contents, so `git pull` refuses to merge. To realign while keeping the old commits on a backup branch:

```bash
cd ~/projects/foco-revops-warehouse
git branch backup/pre-github-import
git fetch origin
git checkout -B main origin/main
git checkout build/brand-and-parse   # to work on PR #1
```

## Decisions still open

| Decision | Default |
|---|---|
| Merge PR #1 to main | After the BigQuery walkthrough passes |
| Make the repo public | Stay private until native tests pass. Publishing also opens a new loop while AdLinter → focosys.io is still open (Meadows rule) |
| Upgrade dbt from 1.10.x (dbt flags it deprecated) | Separate PR, with its own parse and native run |
| Run the walkthrough in CI | Later, via Workload Identity Federation. It needs a service account, which requires approval |

## Links

- PR #1: https://github.com/ChristopherLandaverde/foco-revops-warehouse/pull/1
- Validation record: `VALIDATION.md`
- Walkthrough detail: `docs/synthetic-walkthrough.md`
