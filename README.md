# foco-revops-warehouse

GA4 sessions and CRM pipeline attribution in BigQuery, with checks that show where the numbers came from.

Developed by Christopher Landaverde at Focosys. Implementation, November 2026 · Synthetic examples only.

This dbt package builds the readable layer described in **FOCO Analytics Engineering Lab: BigQuery Semantic Layer**. It models sessions across daily export tables, separates session attribution from lifetime acquisition, coerces polymorphic parameters safely, and links immutable conversion tokens to CRM opportunities.

## What it verifies

- **OBSERVED** — GA4 daily exports, HubSpot contacts, and Salesforce leads/opportunities.
- **BROKEN** — missing session identifiers, conversion tokens shared across users, duplicate CRM records, and revenue that fails reconciliation.
- **REPAIRED** — one session per composite key; ranked ID linkage; first-observed and linear allocations that sum to one per opportunity.
- **VERIFIED** — local relational acceptance tests plus native dbt unit and data tests. See [validation status](VALIDATION.md) for what has actually run.

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

Run `dbt deps` in the consuming project and configure variables under `foco_revops_warehouse` in that project's `vars`. The package also works as a standalone modeling repository. A remote Git URL can be used after you publish your own repository; no remote repository is created by this build.

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

Field notes on marketing systems that hold up under inspection: [focosys.io](https://focosys.io).
