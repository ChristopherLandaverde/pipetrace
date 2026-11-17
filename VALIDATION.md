# Validation record

Implementation based on Christopher's supplied FOCO Analytics Engineering Lab PDF. Synthetic data only. Status: implementation built; native warehouse validation remains blocked.

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
| dbt dependency installation | Blocked: pypi.org DNS resolution unavailable; no dbt executable installed |
| dbt parse / compile | Not run; requires the blocked dependencies |
| Native BigQuery unit/data tests | Not run; requires dbt and an authenticated development project |
| Production deployment / public repository | Not performed |

## What the local tests prove

The tests execute the current `int_crm_touchpoint_linkage`, `fct_revops_pipeline_attribution`, and `fct_pipeline_attribution_daily` SELECT statements with narrowly scoped substitutions for dbt refs/config and timestamp operations. They cover duplicate evidence paths, multiple tokens within one session, converted-opportunity and HubSpot lead paths, unmatched/null-token deals, pre-creation windows, future conversion timestamps, tied touchpoints, weights, value conservation, unknown ARR, and currency separation. Five singular integrity SELECTs also execute against those built fixtures.

SQLite does not validate BigQuery structs, arrays, SAFE_CAST behavior, wildcard scanning, adapter materializations, or dbt's full parser. The GA4 native unit test and parameter drift singular test are authored for those checks but have not executed. YAML parsing does not prove dbt compilation.

## Review corrections

The independent review found two native-fixture defects: missing expected values in one dbt unit-test row and untyped NULL medium fields inside UNIONed BigQuery STRUCTs. Both are corrected. A follow-up review verified those changes and requested a null-safe synthetic total assertion; that correction is also applied. It also flagged attribution history loss under a rolling session window. README, architecture and operations now explain that policy, partial lookback coverage near the window boundary, and the fixed historical-start alternative.

The floating-point parameter test uses a fractional value to avoid assuming how BigQuery prints integral FLOAT64 values as STRING. The native session test additionally covers all-null attribution and a missing-key event.

## Remaining release gates

Run `dbt deps`, `dbt parse --profiles-dir ci --no-partial-parse`, and the complete `docs/synthetic-walkthrough.md` in a development project. Verify connector contracts, timezone, source completeness, IAM restrictions, and actual bytes scanned. No production-readiness claim is made until native checks pass. External cloud/warehouse jobs were not run; no Gateway or other paid model API was invoked by the implementation.
