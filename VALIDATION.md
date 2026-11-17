# Validation record

Implementation based on Christopher's supplied FOCO Analytics Engineering Lab PDF. Synthetic data only. Status: native BigQuery build passes on synthetic data (45 of 45, 2026-11-17). Not yet run against real source data.

| Check | Observed result |
|---|---|
| Actual CRM/attribution SQL against SQLite synthetic fixtures | 14 tests passed |
| Opportunity/session duplication and revenue conservation | Passed local relational tests |
| First-observed/linear allocation, ties, unmatched rows, future touches | Passed local relational tests |
| Currency separation and explicit ARR null semantics | Passed local relational tests |
| Model references and dependency graph | 12 models resolve; graph acyclic |
| YAML parsing | All project, source, schema, native test, CI and example profile YAML parsed with Ruby Psych |
| Python syntax / fixture generation | Parsed; synthetic BigQuery SQL generation succeeded |
| Private-key/local-profile scan | No embedded private keys or local runtime profile found by the repository checker; not a comprehensive security scan |
| Independent code review | Completed; fixture typing and incomplete native expected rows corrected |
| dbt dependency installation | Passed in GitHub Actions (`dbt deps`, run 44009430700, 2026-11-17). Locally: dbt-core 1.10.23 / dbt-bigquery 1.10.3 installed; dbt Hub blocked by egress policy, so dbt_utils 1.3.0 was vendored from its GitHub tag for the parse check |
| dbt parse | Passed, exit 0: GitHub Actions on `main` (f222123) and locally with `--profiles-dir ci --no-partial-parse`. Resolved 12 models, 31 data tests, 1 unit test, 4 sources |
| dbt compile | Covered by the native `dbt build` above |
| Native BigQuery unit/data tests | Passed 45 of 45 in GitHub Actions run 44109338907 (2026-11-17): 12 models, 32 data tests, 1 unit test, against a synthetic fixture in project `foco-revops-ci` (BigQuery sandbox, no billing). Every model built 2 rows; `assert_synthetic_fixture` confirms 2 sessions, 2 opportunities, 1 Unattributed, linear pipeline total 1500 |
| Native run fixes | Run 1: unit-test expected rows listed columns in different orders (UNION ALL type error). Run 2: two tests used SELECT … WHERE without FROM; sandbox 60-day partition expiry emptied tables built from the fixed 2026-01-01 fixture. Fixture dates are now relative (`--base-date`, 12 days back in CI) |
| Production deployment / public repository | Not performed |

## What the local tests prove

The tests execute the current `int_crm_touchpoint_linkage`, `fct_revops_pipeline_attribution`, and `fct_pipeline_attribution_daily` SELECT statements with narrowly scoped substitutions for dbt refs/config and timestamp operations. They cover duplicate evidence paths, multiple tokens within one session, converted-opportunity and HubSpot lead paths, unmatched/null-token deals, pre-creation windows, future conversion timestamps, tied touchpoints, weights, value conservation, unknown ARR, and currency separation. Five singular integrity SELECTs also execute against those built fixtures.

SQLite does not validate BigQuery structs, arrays, SAFE_CAST behavior, wildcard scanning, adapter materializations, or dbt's full parser. The GA4 native unit test and parameter drift singular test are authored for those checks but have not executed. YAML parsing does not prove dbt compilation.

## Review corrections

The independent review found two native-fixture defects: missing expected values in one dbt unit-test row and untyped NULL medium fields inside UNIONed BigQuery STRUCTs. Both are corrected. A follow-up review verified those changes and requested a null-safe synthetic total assertion; that correction is also applied. It also flagged attribution history loss under a rolling session window. README, architecture and operations now explain that policy, partial lookback coverage near the window boundary, and the fixed historical-start alternative.

The floating-point parameter test uses a fractional value to avoid assuming how BigQuery prints integral FLOAT64 values as STRING. The native session test additionally covers all-null attribution and a missing-key event.

## Remaining release gates

The native synthetic build passes. Before production use, verify connector contracts, timezone, source completeness, IAM restrictions, and actual bytes scanned. No production-readiness claim is made until the package runs against real connector data.
