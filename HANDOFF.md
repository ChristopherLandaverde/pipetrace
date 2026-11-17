# Handoff — foco-revops-warehouse

`Handoff note · 2026-11-16 · State, blockers, and the next three steps`

Read this first tomorrow. It records where the build stopped and how to resume.

## Where things stand

```
□ OBSERVED   Repo: github.com/ChristopherLandaverde/foco-revops-warehouse (private)
             main = f222123, the initial import from the zip
             build/brand-and-parse = draft PR #1, not merged
✓ VERIFIED   test_local.py 14/14 · check_repository.py PASS
             dbt deps + dbt parse pass in GitHub Actions on main and on PR #1
             parse resolves 12 models, 31 data tests, 1 unit test, 4 sources
× OPEN       Native BigQuery walkthrough has never run
             dbt compile has never run (needs Google credentials)
```

What PR #1 contains:

- README rewritten to the foco-brand trace format: a scope line, the □ × + ✓ block, counts as evidence, and the christopher@focosys.io CTA.
- VALIDATION, PROGRESS, PLAN and DECISIONS updated to match what actually ran.
- `scripts/run_walkthrough.sh`: a one-command BigQuery test on synthetic data, with cost guards.
- This file.

## Resume: the next three steps

1. **Install the Google Cloud SDK on the Mac.** The last run stopped here.
   ```bash
   brew install --cask google-cloud-sdk
   ```
2. **Choose a dev or sandbox GCP project** under christopher@focosys.io. Never a client project.
3. **Run the walkthrough:**
   ```bash
   cd ~/projects/foco-revops-warehouse && bash scripts/run_walkthrough.sh <dev-project-id>
   ```
   On first run it opens a Google sign-in in the browser; approve it once. The log is written to `logs/walkthrough-<prefix>.log`. Then ask Claude to read the log and fix any failures on PR #1.

Expected result: `✓ VERIFIED  dbt build passed against synthetic fixture`. Expect one or two fix rounds first. The SQL has never run on BigQuery, and the likely trouble spots are STRUCT typing, SAFE_CAST behavior and the `events_*` wildcard scan.

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
