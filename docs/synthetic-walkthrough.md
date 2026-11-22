# Synthetic walkthrough / no client data

This creates two daily GA4 tables, two HubSpot contacts, three converted Salesforce leads, and five opportunities in a disposable development project. One session crosses midnight. There is one opportunity per attribution level: `o1` by conversion token, `o3` by GA4 client ID across two sessions, `o4` from Salesforce first-touch fields and `o5` from HubSpot's original source. `o2` remains Unattributed. Linear pipeline value totals 2,800 (`o1` uses its ARR).

The SQL generator prints create-only statements; it does not execute them. It does not overwrite existing fixture tables. Do not point it at production datasets.

```bash
python3 scripts/generate_fixture.py --project "$DBT_BIGQUERY_PROJECT" > /tmp/foco-fixture.sql
bq query --project_id="$DBT_BIGQUERY_PROJECT" --location="${DBT_BIGQUERY_LOCATION:-US}" --use_legacy_sql=false < /tmp/foco-fixture.sql

dbt deps
dbt build --profiles-dir . --vars '{ga4_dataset: foco_fixture_ga4, hubspot_dataset: foco_fixture_hubspot, salesforce_dataset: foco_fixture_salesforce, ga4_start_date: "2026-01-01", ga4_end_date: "2026-01-02", ga4_timezone: UTC, validate_fixture: true}'
```

For a non-US location, pass `--location` to the generator as well as bq/profile configuration. Use a new `--prefix` for repeat runs and set all three dbt dataset variables to that prefix. Clean up fixtures with your normal development-project process when finished.

Expected evidence:

- Two modeled sessions, not three daily event groups.
- `u1-1767311940` starts on January 1, has two events, source newsletter, medium email, and engaged-session true.
- Session attribution does not become the synthetic lifetime referral source.
- Two opportunities remain visible: linked value 1000 using explicit ARR and unmatched value 500 using Amount.
- Every opportunity's first-observed and linear weights sum to one; allocated pipeline totals 1500, separated by revenue basis.

`assert_synthetic_fixture` enforces these expectations only when `validate_fixture: true`. Never enable that fixture-only assertion against real source data. Unit tests exercise session aggregation independently of this fixture; singular tests exercise the built lineage.
