<p align="center">
  <img src="docs/images/logo.png" width="96" height="96" alt="PipeTrace logo: three paper session dots on a dark green tile, their lines joining into one pipeline line that ends at a lime total bar">
</p>

<h1 align="center">PipeTrace</h1>

<p align="center">
  <strong>A deal can be credited to three channels and still add up to more than it was worth. Trace every pipeline dollar to the GA4 session behind it, and prove it sums back to the deal.</strong>
</p>

<p align="center">
  12 dbt models on BigQuery · first-observed and linear credit that sums to 1 per opportunity · 45 of 45 dbt nodes pass on BigQuery in CI (12 models, 33 tests) · read-only on GA4, HubSpot and Salesforce
</p>

<p align="center">
  <a href="https://github.com/ChristopherLandaverde/pipetrace/actions/workflows/ci.yml"><img src="https://github.com/ChristopherLandaverde/pipetrace/actions/workflows/ci.yml/badge.svg?branch=main" alt="Validate package"></a>
  <a href="https://github.com/ChristopherLandaverde/pipetrace/actions/workflows/walkthrough.yml"><img src="https://github.com/ChristopherLandaverde/pipetrace/actions/workflows/walkthrough.yml/badge.svg?branch=main" alt="Native BigQuery walkthrough"></a>
  <a href="requirements.txt"><img src="https://img.shields.io/badge/dbt-1.10-10231F" alt="dbt Core 1.10"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-10231F" alt="License: MIT"></a>
</p>

<p align="center">
  <a href="#quickstart">Quickstart</a> · <a href="#the-trace">The trace</a> · <a href="#model-surfaces">Model surfaces</a> · <a href="#limits-that-affect-interpretation">Known limits</a> · <a href="VALIDATION.md">Validation record</a> · <a href="docs/synthetic-walkthrough.md">Synthetic walkthrough</a>
</p>

`dbt package · Nov 2026 · Implementation notes, assumptions, and limits · Walkthrough / no client data`

PipeTrace is a dbt package for marketing ops and RevOps analysts who have to say which channels sourced pipeline, and defend the number. By Christopher Landaverde, FOCO Systems. Sibling of [Open Source Revenue Attribution](https://github.com/ChristopherLandaverde/open-source-revenue-attribution), which does the same job as a self-hosted app.

<p align="center">
  <img src="docs/images/pipeline.svg" width="880" alt="PipeTrace pipeline. Sources: GA4 daily export, HubSpot contacts with conversion tokens, Salesforce leads and opportunities. int_ga4_sessions builds one row per user and session ID. int_session_conversion_tokens keeps every token per session. int_crm_touchpoint_linkage joins tokens to opportunities by ranked deterministic ID paths, keeping unmatched deals. fct_revops_pipeline_attribution weights sessions first-observed and linear, each summing to 1, and fct_pipeline_attribution_daily is the BI surface. Checks: midnight sessions count once, no token shared across users, every opportunity present, weights sum to 1, pipeline reconciles to source value.">
  <br><sub>Model names and checks as built. The counts come from the CI run on synthetic data.</sub>
</p>

`Scope /` reads GA4 daily exports, HubSpot contacts, and Salesforce leads and opportunities. It builds 12 models, with 31 data tests, 1 native unit test, and 1 fixture-only check that runs only on synthetic data. It does not write to GA4, HubSpot, or Salesforce. It does not stitch identities by email, convert currency, or host a dbt Semantic Layer service.

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
             native BigQuery build passes 45 of 45 (12 models, 31 data tests
             + 1 fixture check, 1 unit test) on synthetic data, run 44109338907
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
  - local: /absolute/path/to/pipetrace
```

Run `dbt deps` in the consuming project and configure variables under `pipetrace` in that project's `vars`. The package also works as a standalone modeling repository. A Git URL package entry also works once the repository is reachable from your dbt environment.

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

See [architecture and decisions](docs/architecture.md), [metric definitions](docs/metrics.md), [operations](docs/operations.md), and [using PipeTrace with a data agent](docs/agents.md).

## Limits that affect interpretation

The default window covers sessions starting from 90 days ago through yesterday in the property timezone. Raw daily shards include a two-day buffer on each boundary. Old opportunities remain in the pipeline output but become unattributed when their eligible sessions fall outside the observation window. Set a fixed `ga4_start_date` for durable historical reporting. A rolling-window build replaces prior output; it is not an attribution history store.

First touch means the earliest **observed, token-linked** eligible session, not the first anonymous visit in a person's lifetime. The package does not stitch identities by email, infer anonymous journeys, model consent-denied users, perform FX conversion, or implement Google's complete channel-group rules. `fbclid` alone does not prove a paid-social click.

This is a governed SQL modeling layer, not a deployed dbt Semantic Layer/MetricFlow service. Metric definitions and safe query examples are included. Production validation, IAM grants, and scheduling remain deployment tasks.

Field notes on this problem ↗ [focosys.io](https://focosys.io) · Start with the decision you cannot trust: [christopher@focosys.io](mailto:christopher@focosys.io)
