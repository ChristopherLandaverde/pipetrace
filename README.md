<p align="center">
  <img src="docs/images/logo.png" width="96" height="96" alt="PipeTrace logo: three paper session dots on a dark green tile, their lines joining into one pipeline line that ends at a lime total bar">
</p>

<h1 align="center">PipeTrace</h1>

<p align="center">
  <strong>A deal can be credited to three channels and still add up to more than it was worth. Trace every pipeline dollar to the GA4 session behind it, and prove it sums back to the deal.</strong>
</p>

<p align="center">
  14 dbt models on BigQuery · three attribution levels, each labeled · first-observed and linear credit that sums to 1 per opportunity · 54 of 54 dbt nodes pass on BigQuery in CI (14 models, 40 tests), for native, Fivetran and Airbyte tables · read-only on GA4, HubSpot and Salesforce
</p>

<p align="center">
  <a href="https://github.com/ChristopherLandaverde/pipetrace/actions/workflows/ci.yml"><img src="https://github.com/ChristopherLandaverde/pipetrace/actions/workflows/ci.yml/badge.svg?branch=main" alt="Validate package"></a>
  <a href="https://github.com/ChristopherLandaverde/pipetrace/actions/workflows/walkthrough.yml"><img src="https://github.com/ChristopherLandaverde/pipetrace/actions/workflows/walkthrough.yml/badge.svg?branch=main" alt="Native BigQuery walkthrough"></a>
  <a href="requirements.txt"><img src="https://img.shields.io/badge/dbt-1.12-10231F" alt="dbt Core 1.12"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-10231F" alt="License: MIT"></a>
</p>

<p align="center">
  <a href="#start-here">Start here</a> · <a href="docs/setup-guide.md">Setup guide</a> · <a href="#the-trace">The trace</a> · <a href="#model-surfaces">Model surfaces</a> · <a href="#limits-that-affect-interpretation">Known limits</a> · <a href="VALIDATION.md">Validation record</a> · <a href="docs/synthetic-walkthrough.md">Synthetic walkthrough</a> · <a href="CHANGELOG.md">Changelog</a> · <a href="CONTRIBUTING.md">Contributing</a>
</p>

`dbt package · Nov 2026 · Implementation notes, assumptions, and limits · Walkthrough / no client data`

PipeTrace is a dbt package for marketing ops and RevOps analysts who have to say which channels sourced pipeline, and defend the number. By Christopher Landaverde, FOCO Systems. Sibling of [Open Source Revenue Attribution](https://github.com/ChristopherLandaverde/open-source-revenue-attribution), which does the same job as a self-hosted app.

<p align="center">
  <img src="docs/images/pipeline.svg" width="880" alt="PipeTrace pipeline. Sources: GA4 daily export, HubSpot contacts with conversion tokens, Salesforce leads and opportunities. int_ga4_sessions builds one row per user and session ID. int_session_conversion_tokens keeps every token per session. int_crm_touchpoint_linkage joins tokens to opportunities by ranked deterministic ID paths, keeping unmatched deals. fct_revops_pipeline_attribution weights sessions first-observed and linear, each summing to 1, and fct_pipeline_attribution_daily is the BI surface. Checks: midnight sessions count once, no token shared across users, every opportunity present, weights sum to 1, pipeline reconciles to source value.">
  <br><sub>Model names and checks as built. The counts come from the CI run on synthetic data.</sub>
</p>

`Scope /` reads GA4 daily exports, HubSpot contacts, and Salesforce leads and opportunities. It builds 14 models, with 37 data tests, 1 native unit test, and 2 fixture-only checks, plus mapping views for Fivetran or Airbyte tables that runs only on synthetic data. It does not write to GA4, HubSpot, or Salesforce. It does not stitch identities by email, convert currency, or host a dbt Semantic Layer service.

It builds the readable layer described in **FOCO Analytics Engineering Lab: BigQuery Semantic Layer**. Sessions are modeled across daily export tables. Session attribution stays separate from lifetime acquisition. Polymorphic parameters are coerced safely. Immutable conversion tokens link sessions to CRM opportunities.

## The trace

```
□ OBSERVED   GA4 daily exports, HubSpot contacts, Salesforce leads and opportunities
× BROKEN     sessions split at midnight, missing session IDs, parameter type drift,
             conversion tokens shared across users, duplicate CRM paths that
             multiply revenue
+ REPAIRED   one session per composite key; ranked deterministic ID linkage;
             first-observed and linear weights that sum to 1 per opportunity;
             three attribution levels, strongest wins per deal and is labeled;
             unmatched deals kept as Unattributed
✓ VERIFIED   14 local relational tests pass; dbt parse passes in CI;
             native BigQuery build passes 54 of 54 (14 models, 37 data tests
             + 2 fixture checks, 1 unit test) on synthetic data, and 57/57
             and 55/55 with Fivetran and Airbyte tables, run 45029750908
```

See the [validation record](VALIDATION.md) for what has run and what has not.

## Start here

1. Install the package (below) and point it at your GA4, HubSpot and Salesforce datasets. Set `pipetrace_connector` to `native`, `fivetran` or `airbyte`.
2. `dbt build`, then `dbt run-operation pipetrace_doctor`. The first build already credits deals by the source your CRM recorded (level 0).
3. Follow the [setup guide](docs/setup-guide.md) for the field the doctor says is missing: a GA4 client ID on the form (level 1), then a conversion token (level 2).

### Install as a dbt package

In your dbt project's `packages.yml`:

```yaml
packages:
  - git: "https://github.com/ChristopherLandaverde/pipetrace.git"
    revision: v1.0.0
```

Then set the variables under `pipetrace` in your `dbt_project.yml` and run `dbt deps`:

```yaml
vars:
  pipetrace:
    ga4_dataset: analytics_123456789
    hubspot_dataset: hubspot
    salesforce_dataset: salesforce
    ga4_timezone: America/New_York
    pipetrace_connector: fivetran
```

## Quickstart (standalone repository)

Requires Python 3.10+, dbt Core 1.12 (tested; the package declares >=1.10.5), a BigQuery development project, and Application Default Credentials. All source and output datasets must share a BigQuery location.

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp profiles.yml.example profiles.yml
export DBT_BIGQUERY_PROJECT=your-development-project
export DBT_BIGQUERY_DATASET=pipetrace_dev
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
dbt run-operation pipetrace_doctor --profiles-dir .
dbt docs generate --profiles-dir .
```

`pipetrace_doctor` prints the readiness check: how many deals reached each attribution level, how complete each matching field is, and whether CRM tokens and client IDs actually appear in GA4. The same rows are in the `pipetrace_readiness` table.

The profile caps each job at 10 GB billed. Adjust deliberately for your data volume. Full table refreshes are intentional in v1: every build recomputes the configured observation window and current CRM snapshot. No incremental merge can leave stale allocations behind.

### Try synthetic data first

Local relational checks need only the Python standard library:

```bash
python3 scripts/test_local.py
```

For the complete BigQuery path, follow [the synthetic walkthrough](docs/synthetic-walkthrough.md). It creates new fixture tables in a development project; it never uses client data.

## Attribution levels

Each opportunity is credited at the strongest level its data supports. Every row carries `attribution_level` and `attribution_basis`.

| Level | `attribution_basis` | Evidence | Needs |
|---|---|---|---|
| 2 | `conversion_token` | GA4 sessions holding the token copied to the CRM | Token in GA4, HubSpot and Salesforce |
| 1 | `ga_client_id` | Every eligible GA4 session of the client ID stored on a CRM record | One hidden form field with the GA4 client ID |
| 0 | `crm_source` | The source HubSpot or Salesforce recorded. No session | Nothing new |
| — | `unattributed` | None | — |

Levels 1 and 2 are traced to sessions. Level 0 is the CRM's own claim, so report it separately: the daily mart keeps `attribution_basis` as a dimension. Match fields are dbt vars in `dbt_project.yml`. They are case-sensitive, and a missing column reads as NULL rather than failing the build, so that level is simply not reached. Turn levels off with `enable_ga_client_id_matching` and `enable_crm_source_fallback`.

## Model surfaces

| Model | Grain | Intended use |
|---|---|---|
| `stg_ga4_events` | Export event | Restricted parameter and attribution inspection |
| `stg_hubspot_contacts` | Current contact | Restricted identity evidence |
| `stg_sfdc_leads` | Current lead | Restricted converted IDs |
| `stg_sfdc_opportunities` | Current opportunity | Revenue reconciliation |
| `int_ga4_sessions` | User pseudonym + session ID | Session metrics and provenance |
| `int_session_conversion_tokens` | Session + conversion token | Preserve multiple conversions per session |
| `int_opportunity_identity_paths` | Opportunity + CRM record path | Restricted token, client ID and CRM-source evidence |
| `int_crm_touchpoint_linkage` | Opportunity + session, including unmatched | Auditable linkage evidence |
| `dim_touchpoints` | Session | Restricted session detail |
| `fct_ga4_sessions_daily` | Date + channel/source/medium/campaign | Traffic reporting |
| `fct_revops_pipeline_attribution` | Opportunity + session | Attribution bridge; use allocated measures |
| `fct_pipeline_attribution_daily` | Opportunity creation date + channel/currency/basis | Preferred BI and agent revenue surface |
| `audit_ga4_unkeyed_events` | Export date + event name | Missing-identity coverage |

See [architecture and decisions](docs/architecture.md), [metric definitions](docs/metrics.md), [operations](docs/operations.md), and [using PipeTrace with a data agent](docs/agents.md).

## Limits that affect interpretation

The default window covers sessions starting from 90 days ago through yesterday in the property timezone. Raw daily shards include a two-day buffer on each boundary. Old opportunities remain in the pipeline output but become unattributed when their eligible sessions fall outside the observation window. Set a fixed `ga4_start_date` for durable historical reporting. A rolling-window build replaces prior output; it is not an attribution history store.

First touch means the earliest **observed, linked** eligible session (level 1 or 2), not the first anonymous visit in a person's lifetime. The package does not stitch identities by email, infer anonymous journeys, model consent-denied users, perform FX conversion, or implement Google's complete channel-group rules. `fbclid` alone does not prove a paid-social click.

This is a governed SQL modeling layer, not a deployed dbt Semantic Layer/MetricFlow service. Metric definitions and safe query examples are included. Production validation, IAM grants, and scheduling remain deployment tasks.

Field notes on this problem ↗ [focosys.io](https://focosys.io) · Start with the decision you cannot trust: [christopher@focosys.io](mailto:christopher@focosys.io)
