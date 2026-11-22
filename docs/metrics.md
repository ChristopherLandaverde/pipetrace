# Governed metric definitions

| Measure | Definition | Aggregation rule |
|---|---|---|
| total_sessions | One valid composite session ID, assigned to its start date | Sum daily session counts |
| engaged_sessions | Sessions with at least one exported session_engaged = 1 | Sum within the same window |
| lead_conversion_sessions | Sessions with at least one configured lead event | Sum; this counts sessions, not submissions |
| unique_visitors | Distinct pseudonyms per daily campaign group | Never sum across dates/campaigns; query session detail for period distincts |
| first_touch_opportunities | Sum of first-observed weights | Sum across channel rows |
| linear_opportunities | Sum of fractional linear weights | Sum across channel rows |
| first_touch_pipeline_value | Pipeline value allocated to the earliest eligible linked session | Sum within currency and revenue_basis |
| linear_pipeline_value | Pipeline value divided equally over eligible linked sessions | Sum within currency and revenue_basis |
| first_touch_won_value / linear_won_value | Allocated pipeline value where current is_won is true | Opportunity creation cohort; not close-date bookings |
| first_touch_arr / linear_arr | Allocated explicit ARR__c | Excludes null ARR; never substitute Amount |

`opp_pipeline_value` and `opp_arr` repeat on every touchpoint row. They are reconciliation context, not additive measures. Prefer `fct_pipeline_attribution_daily` for conversational agents and Looker Studio. Retain `currency_code` and `revenue_basis` in every monetary grouping.

Unknown amounts stay null in the detail bridge. SUM ignores nulls, so an all-unknown group returns null and a mixed group represents only known value. Check opportunity completeness against staging before making financial decisions.

First-observed attribution does not claim a complete acquisition journey. Missing identity, consent limits, the raw observation window, and CRM sync quality limit linkage coverage. Unattributed means no eligible deterministic web match and no CRM-recorded source; it does not mean Direct traffic. `crm_source` rows (level 0) carry the CRM's own channel claim with no session, so split every revenue answer by `attribution_basis`. `Unassigned` is a channel the rules could not map; `Unattributed` is a deal with no evidence.

The channel grouping is intentionally a small transparent rule set. Exported source/medium are retained so consumers can implement an organization-specific taxonomy without rewriting session identity.

Example safe agent instruction: "Query fct_pipeline_attribution_daily, filter opportunity creation dates, retain currency_code and revenue_basis, and sum linear_pipeline_value. State the observation window and Unattributed share. Do not query raw GA4 or sum opp_pipeline_value from the bridge."
