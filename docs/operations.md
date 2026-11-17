# Operations

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| ga4_project / hubspot_project / salesforce_project | target project | Source projects |
| ga4_dataset | analytics_demo | GA4 dataset |
| hubspot_dataset | hubspot_demo | Contact dataset |
| salesforce_dataset | salesforce_demo | Lead/opportunity dataset |
| ga4_timezone | UTC | Property timezone used for session dates |
| ga4_lookback_days | 90 | Rolling session-start observation window |
| ga4_start_date | null | Inclusive fixed YYYY-MM-DD override |
| ga4_end_date | null | Inclusive override; otherwise yesterday |
| ga4_boundary_buffer_days | 2 | Raw shard padding before and after the window |
| attribution_lookback_days | 90 | Maximum pre-opportunity session age |
| lead_conversion_events | generate_lead, form_submit, demo_request | Session lead flags |

The global observation window also truncates the eligible lookback for opportunities near its start. For stable historical reporting, set `ga4_start_date` to your retained history start and schedule a daily rebuild. Bound `ga4_end_date` for reproducible backfills. Increasing the boundary buffer supports unusually long cross-day sessions but increases scanned bytes. An arbitrary-length session cannot be guaranteed complete with a finite buffer. GA4 UI totals may differ due to consent modeling, reporting identity, retention, and data freshness.

## Deployment gate

1. Map sources and run their uniqueness/null tests in a development dataset.
2. Run the synthetic walkthrough and `dbt build`, including native unit tests and all singular reconciliation tests.
3. Compare daily counts, session attribution provenance, unknown-identity counts, and unmatched pipeline against source evidence.
4. Inspect BigQuery dry-run bytes and jobs; tune the billing cap and schedule to the actual volume.
5. Use isolated versioned output datasets and grant BI access only after all checks pass. A dbt build can leave newly created tables behind even when a later test fails.

Authenticate with ADC for development or your organization's workload identity in CI. Do not commit a service-account key or profiles.yml. Grant read access to source datasets, Job User in the execution project, and write access only to the output dataset. The package does not apply IAM grants or row policies.

The package's `restricted` tag is documentation, not access enforcement. Stage/contact email, user identifiers, URLs, and click IDs require restricted datasets or authorized views. Daily aggregates also need a real access policy. Do not grant agents unrestricted access to the detail dimension simply because it is in marts.

## Failed checks

Duplicate CRM IDs indicate unresolved connector snapshots. Resolve them upstream. Shared conversion tokens across users indicate token reuse or tracking errors. Weight or pipeline reconciliation failures block promotion. Null identifiers are retained in the audit surface because consent-denied events should not be assigned invented sessions.

Review GA4 export completeness and connector sync freshness with your ingestion system. Native GA4 wildcard sources do not expose a uniform connector loaded-at column, so no fabricated source freshness SLA is declared here. Failures outside the observation window require widening the window and rebuilding.
