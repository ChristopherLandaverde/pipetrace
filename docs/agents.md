# Using PipeTrace with a data agent

`Agent guide · Nov 2026 · Instructions for BigQuery conversational agents · Read-only`

PipeTrace is the governed layer an agent should query instead of raw GA4 exports. This page gives the tables to expose, the rules to paste into the agent, and the checks to run before trusting an answer. It applies to BigQuery's conversational analytics agents and to any agent that queries BigQuery through MCP or SQL.

## The trace

```
□ OBSERVED   Agent asks a revenue or traffic question
↓ TRACED     It queries only the two marts below, with the rules in this page
+ REPAIRED   Answers keep currency and revenue basis apart, name the model
             and window, and report the Unattributed share
✓ VERIFIED   Totals reconcile to the CRM (assert_pipeline_reconciles) and the
             numbers carry a citation to the table and filter used
```

## Tables to expose

Give the agent read access to these two tables only:

| Table | Grain | Use for |
|---|---|---|
| `fct_pipeline_attribution_daily` | Opportunity creation date × channel × attribution basis × currency × revenue basis | Pipeline and won value by channel |
| `fct_ga4_sessions_daily` | Session date × channel × source × medium × campaign | Traffic, engagement and lead-conversion sessions |

Leave out the raw `events_*` tables, the staging views and `fct_revops_pipeline_attribution`. The bridge table repeats `opp_pipeline_value` and `opp_arr` on every touchpoint row, so an agent that sums them multiplies revenue.

Grant the agent's identity `roles/bigquery.dataViewer` on the output dataset and `roles/bigquery.jobUser` on the project. Set a `maximum_bytes_billed` cap on its connection.

## Instructions to paste into the agent

```
You answer marketing pipeline and traffic questions from two BigQuery tables:
fct_pipeline_attribution_daily and fct_ga4_sessions_daily. Query nothing else.

Revenue
- Group every monetary sum by currency_code and revenue_basis. Never add
  different currencies or ARR and Amount together.
- Use linear_pipeline_value by default. Use first_touch_pipeline_value only when
  asked for first touch.
- Name the model in every answer: "linear attribution" or "first-observed
  attribution". State the date range, which is the opportunity creation date.
- Report the Unattributed share next to channel totals. Unattributed means no
  deterministic web match was found; it does not mean Direct.
- attribution_basis says how each deal was credited: conversion_token or
  ga_client_id (traced to GA4 sessions) or crm_source (the CRM's own recorded
  source, no session). Report the crm_source share separately when it is not 0.
- won_value columns are filtered on the opportunity's current won status, by
  creation cohort. They are not bookings by close date.
- ARR columns exclude deals with no ARR. Never substitute Amount for ARR.

Traffic
- total_sessions, engaged_sessions and lead_conversion_sessions can be summed.
- unique_visitors cannot be summed across rows or dates. Say so if asked.

Language
- Describe attribution as association under a named model and window, never as
  causation.
- If a question needs a table you don't have, say so instead of guessing.
```

## Checks before trusting an answer

1. The latest `dbt build` passed, including `assert_pipeline_reconciles` and `assert_opportunity_coverage`.
2. The question's dates fall inside the observation window. The default is the last 90 days (`ga4_lookback_days`). Deals whose sessions fall outside it show as Unattributed.
3. `ga4_timezone` matches the GA4 property's timezone. A mismatch moves sessions across midnight.

## The live demo agent

`agents/pipetrace-pipeline-agent.json` defines the agent as code: the two tables, the instructions above, and three example queries. `scripts/data_agent.py` creates it or updates it in place through Google's Conversational Analytics API.

The **Data agent and GA4 cross-check** workflow (Actions tab, run manually) does this in project `foco-revops-ci`:

1. `demo` rebuilds the stable synthetic dataset `pipetrace_demo_models` and runs every example query through BigQuery's dry run, so broken SQL fails CI.
2. `demo-and-agent` also creates or updates the data agent `pipetrace-pipeline`.

The agent step needs one-time setup:
- billing linked to the project, which data agents require;
- the Gemini Data Analytics API and the Gemini for Google Cloud API enabled;
- these roles on the CI service account, as the console names them: Gemini Data Analytics Data Agent Creator, Gemini Data Analytics Stateless Chat User, and Dataplex Catalog Viewer. They were granted in `foco-revops-ci` on 2026-11-17.

## Cross-checking GA4's own numbers

`scripts/ga4_crosscheck.py` compares GA4's Data API session counts per day with `fct_ga4_sessions_daily`. The two never match exactly, because of thresholding and session counting differences, so it flags days that drift beyond a tolerance (5% by default). It skips days where both sides have under 20 sessions. It prints percentages only, not traffic counts, because CI logs on a public repository are public. Pass `--show-counts` locally to see the counts. GA4 reports dates in the property's timezone, so set `ga4_timezone` to match.

The `crosscheck` step of the workflow runs it. It needs:
- a GA4 property with BigQuery export linked, plus PipeTrace's marts built from that export;
- the CI service account added as Viewer on the GA4 property;
- the Google Analytics Data API enabled on `foco-revops-ci`.

Field notes on this problem ↗ [focosys.io](https://focosys.io)
