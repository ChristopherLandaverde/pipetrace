# Implementation contract

Authority: Christopher's supplied 12-page FOCO Analytics Engineering Lab PDF and explicit request to build it. This file records that scope; it does not request another approval for the same work.

Problem: GA4 raw exports expose session identity, attribution-scope, parameter-type, and CRM-join failure modes. BI users and analytical agents need governed BigQuery models whose traffic and allocated pipeline values can be reconciled to source records.

Scope: standalone and reusable dbt package, the specified macros and staging/intermediate/mart files, explicit sources, documentation, deterministic CRM linkage, synthetic fixtures, integrity tests, and CI parsing. Corrections to demonstrably unsafe sample SQL are recorded in DECISIONS.md and docs/architecture.md.

Out of scope: client-system writes, live client data, public repository creation, production deployment, account-wide identity stitching, ingestion connectors, FX conversion, MetricFlow hosting, and a web application.

Acceptance:

- `python3 scripts/test_local.py` executes the actual relational SQL against synthetic opportunity/session cases without revenue multiplication.
- `python3 scripts/check_repository.py` verifies repository references, dependency graphs, required surfaces, and basic SQL-template structure.
- `dbt deps` and `dbt parse --profiles-dir ci --no-partial-parse` resolve and parse the package.
- The documented BigQuery synthetic walkthrough passes native unit and data tests, including midnight grouping, parameter drift, opportunity coverage, and allocation reconciliation.
- No secrets or client data are introduced. README describes all unresolved verification limits.

Assumptions: current CRM snapshots expose the documented connector field contract (verify source uniqueness and source mapping); GA4 uses a single property's daily export schema (verify native fixture and development compile); ga4_timezone matches that property (verify its admin configuration); tokens are immutable and opaque (verify shared-token test and capture implementation).

History checks: this target directory did not exist before the build; no repository history, removed implementation, or target-specific revisit gate exists here. This is a user-directed analytics modeling repository, explicitly authorized by the supplied PDF. No existing application loop is modified.
