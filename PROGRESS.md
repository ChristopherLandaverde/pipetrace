# Current state

Implementation authored from the supplied PDF. The 12-model dbt repository, native tests, synthetic fixture generator, local relational tests, CI configuration and documentation are complete. All 14 local acceptance tests pass; source references and YAML parse checks pass. Independent review completed and identified fixture corrections are applied.

2026-11-17: `dbt deps` and `dbt parse` pass in GitHub Actions and locally (12 models, 31 data tests, 1 unit test, 4 sources). BigQuery execution remains blocked: this workspace cannot reach googleapis.com, and no development project or credentials have been selected. See VALIDATION.md and docs/synthetic-walkthrough.md. No production deployment, public visibility change, real client data, or client-stack writes occurred.

Source is on GitHub at ChristopherLandaverde/pipetrace (public since 2026-11-22; renamed from foco-revops-warehouse on 2026-11-17, and the old URL redirects). PR #1 (brand README, native CI walkthrough, validation record) merged to `main` as 8592524 on 2026-11-17.

## 2026-11-17: native walkthrough passes

GitHub Actions job `Native BigQuery walkthrough` signs in to project `foco-revops-ci` through Workload Identity Federation (no key file) and runs `scripts/run_walkthrough.sh`. Run 44109338907 passed 45 of 45. It runs on every PR that touches models, macros, tests or the fixture, and on manual dispatch.

## 2026-11-17: PipeTrace

Renamed to PipeTrace: GitHub repo `pipetrace`, dbt package `pipetrace`, and a logo in the Focosys family shared with OSRA and Rabbit. The CI sign-in condition and service account grant follow the new repo name.

## 2026-11-22: v1.0.0, open-source release

- PR #5 GA4 data agents merged.
- PR #6 three attribution levels (conversion token, GA4 client ID, CRM source), labeled on every row; match fields are vars; missing columns read as NULL.
- PR #7 readiness check: `pipetrace_readiness` table and `dbt run-operation pipetrace_doctor`.
- PR #8 Fivetran and Airbyte connector mappings; walkthrough matrix over three loader shapes.
- PR #9 tested toolchain on dbt 1.12.
- PR #10 setup guide, contributor files, fork-PR CI skip.
- PR #11 release docs; tag v1.0.0.
