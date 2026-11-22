# Changelog

## v1.0.0 · 2026-11-22

First public release. Synthetic data only: native BigQuery runs pass on synthetic fixtures; no run on real client data is recorded yet.

- Three attribution levels, strongest wins per opportunity and is labeled on every row: `conversion_token` (2), `ga_client_id` (1), `crm_source` (0). Unmatched deals stay `unattributed`.
- Matching fields are dbt vars. Optional CRM columns read as NULL instead of failing the build.
- `pipetrace_readiness` table and `dbt run-operation pipetrace_doctor`: deals per level, field coverage, and whether CRM tokens and client IDs appear in GA4.
- `pipetrace_connector` var with mapping views for Fivetran and Airbyte.
- Tested on dbt-core 1.12; the package declares `>=1.10.5`. BigQuery only.
- Every model, test and macro is prefixed `pipetrace_` so it cannot clash with models in the project that installs it. dbt_utils accepts any 1.x.
- Setup guide for each level: [docs/setup-guide.md](docs/setup-guide.md).
- BigQuery data agent config and GA4 cross-check scripts.
