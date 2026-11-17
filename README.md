# foco-revops-warehouse — traces GA4 sessions to CRM pipeline in BigQuery and verifies that the attributed revenue reconciles

`dbt package · Nov 2026 · Implementation notes, assumptions, and limits · Walkthrough / no client data`

By Christopher Landaverde, FOCO Systems.

`Scope /` reads GA4 daily exports, HubSpot contacts, and Salesforce leads and opportunities. It builds 12 models, with 31 data tests and 1 native unit test. It does not write to GA4, HubSpot, or Salesforce. It does not stitch identities by email, convert currency, or host a dbt Semantic Layer service.

It builds the readable layer described in **FOCO Analytics Engineering Lab: BigQuery Semantic Layer**. Sessions are modeled across daily export tables. Session attribution stays separate from lifetime acquisition. Polymorphic parameters are coerced safely. Immutable conversion tokens link sessions to CRM opportunities.

## The trace

```
□ OBSERVED   GA4 daily exports, HubSpot contacts, Salesforce leads and opportunities
× BROKEN     sessions split at midnight, missing session IDs, parameter type drift,
             conversion tokens shared across users, duplicate CRM paths that
             multiply revenue
+ REPAIRED   one session per composite key; ranked deterministic ID linkage;
             first-observed and linear weights that sum to 1 per opportunity;
             unmatched deals kept as Unattributed
✓ VERIFIED   14 local relational tests pass; dbt parse passes in CI;
             native BigQuery build passes 45 of 45 (12 models, 32 data tests,
             1 unit test) on a synthetic fixture, run 44109338907
```

See the [validation record](VALIDATION.md) for what has run and what has not.

## Quickstart

Requires Python 3.10+, dbt Core 1.10.5–1.10.x, a BigQuery development project, and Application Default Credentials. All source and output datasets must share a BigQuery location.

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp profiles.yml.example profiles.yml
export DBT_BIGQUERY_PROJECT=your-development-project
export DBT_BIGQUERY_DATASET=foco_revops_dev
export DBT_BIGQUERY_LOCATION=US
# Authenticate outside the repository using your approved Google Cloud account.
gcloud auth application-default login
dbt deps
dbt debug --profiles-dir .
dbt parse --profiles-dir .
```

Configure source dataset variables in `dbt_project.yml` or pass them to the command. Source project variables default to the profile project; set `ga4_project`, `hubspot_project`, or `salesforce_project` when necessary. Map your connector to the [source contract](docs/source-contracts.md) before building.

```bash
dbt build --profiles-dir . --vars '{ga4_dataset: analytics_123456789, hubspot_dataset: hubspot_raw, salesforce_dataset: salesforce_raw, ga4_timezone: America/New_York}'
dbt docs generate --profiles-dir .
```

The profile caps each job at 10 GB billed. Adjust deliberately for your data volume. Full table refreshes are intentional in v1: every build recomputes the configured observation window and current CRM snapshot. No incremental merge can leave stale allocations behind.

### Try synthetic data first

Local relational checks need only the Python standard library:

```bash
python3 scripts/test_local.py
```

For the complete BigQuery path, follow [the synthetic walkthrough](docs/synthetic-walkthrough.md). It creates new fixture tables in a development project; it never uses client data.

### Install as a dbt package

Use this checkout as a local package in a consuming dbt project:

```yaml
packages:
  - local: /absolute/path/to/foco-revops-warehouse
```

Run `dbt deps` in the consuming project and configure variables under `foco_revops_warehouse` in that project's `vars`. The package also works as a standalone modeling repository. A Git URL package entry also works once the repository is reachable from your dbt environment.

## Model surfaces

| Model | Grain | Intended use |
|---|---|---|
| `stg_ga4_events` | Export event | Restricted parameter and attribution inspection |
| `stg_hubspot_contacts` | Current contact | Restricted identity evidence |
| `stg_sfdc_leads` | Current lead | Restricted converted IDs |
| `stg_sfdc_opportunities` | Current opportunity | Revenue reconciliation |
| `int_ga4_sessions` | User pseudonym + session ID | Session metrics and provenance |
| `int_session_conversion_tokens` | Session + conversion token | Preserve multiple conversions per session |
| `int_crm_touchpoint_linkage` | Opportunity + session, including unmatched | Auditable linkage evidence |
| `dim_touchpoints` | Session | Restricted session detail |
| `fct_ga4_sessions_daily` | Date + channel/source/medium/campaign | Traffic reporting |
| `fct_revops_pipeline_attribution` | Opportunity + session | Attribution bridge; use allocated measures |
| `fct_pipeline_attribution_daily` | Opportunity creation date + channel/currency/basis | Preferred BI and agent revenue surface |
| `audit_ga4_unkeyed_events` | Export date + event name | Missing-identity coverage |

See [architecture and decisions](docs/architecture.md), [metric definitions](docs/metrics.md), and [operations](docs/operations.md).

## Limits that affect interpretation

The default window covers sessions starting from 90 days ago through yesterday in the property timezone. Raw daily shards include a two-day buffer on each boundary. Old opportunities remain in the pipeline output but become unattributed when their eligible sessions fall outside the observation window. Set a fixed `ga4_start_date` for durable historical reporting. A rolling-window build replaces prior output; it is not an attribution history store.

First touch means the earliest **observed, token-linked** eligible session, not the first anonymous visit in a person's lifetime. The package does not stitch identities by email, infer anonymous journeys, model consent-denied users, perform FX conversion, or implement Google's complete channel-group rules. `fbclid` alone does not prove a paid-social click.

This is a governed SQL modeling layer, not a deployed dbt Semantic Layer/MetricFlow service. Metric definitions and safe query examples are included. Production validation, IAM grants, and scheduling remain deployment tasks.

Field notes on this problem ↗ [focosys.io](https://focosys.io) · Start with the decision you cannot trust: [christopher@focosys.io](mailto:christopher@focosys.io)
