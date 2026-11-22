-- One row per readiness check: how many deals reach each attribution level,
-- and how complete each matching field is. Print it with
--   dbt run-operation pipetrace_doctor
{{ config(materialized='table', tags=['readiness']) }}
{% set guide = 'docs/setup-guide.md' %}
with opps as (
  select attribution_basis, count(distinct opportunity_id) as opportunities
  from {{ ref('pipetrace_fct_revops_pipeline_attribution') }}
  group by 1
), opp_total as (
  select count(*) as n from {{ ref('pipetrace_stg_sfdc_opportunities') }}
), crm_tokens as (
  select original_conversion_id as token from {{ ref('pipetrace_stg_hubspot_contacts') }} where original_conversion_id is not null
  union distinct
  select original_conversion_id from {{ ref('pipetrace_stg_sfdc_leads') }} where original_conversion_id is not null
  union distinct
  select original_conversion_id from {{ ref('pipetrace_stg_sfdc_opportunities') }} where original_conversion_id is not null
), crm_client_ids as (
  select ga_client_id as client_id from {{ ref('pipetrace_stg_hubspot_contacts') }} where ga_client_id is not null
  union distinct
  select ga_client_id from {{ ref('pipetrace_stg_sfdc_leads') }} where ga_client_id is not null
  union distinct
  select ga_client_id from {{ ref('pipetrace_stg_sfdc_opportunities') }} where ga_client_id is not null
), checks as (
  -- Attribution levels reached
  select 1 as check_order, 'level' as area, 'level_2_conversion_token' as check_name,
    'Deals credited by conversion token' as description,
    (select coalesce(sum(opportunities), 0) from opps where attribution_basis = 'conversion_token') as numerator,
    (select n from opp_total) as denominator,
    '{{ guide }}#level-2-conversion-token' as guide_section
  union all
  select 2, 'level', 'level_1_ga_client_id', 'Deals credited by GA4 client ID',
    (select coalesce(sum(opportunities), 0) from opps where attribution_basis = 'ga_client_id'),
    (select n from opp_total), '{{ guide }}#level-1-ga4-client-id'
  union all
  select 3, 'level', 'level_0_crm_source', 'Deals credited by CRM-recorded source (no session)',
    (select coalesce(sum(opportunities), 0) from opps where attribution_basis = 'crm_source'),
    (select n from opp_total), '{{ guide }}#level-0-crm-source'
  union all
  select 4, 'level', 'unattributed', 'Deals with no evidence at any level',
    (select coalesce(sum(opportunities), 0) from opps where attribution_basis = 'unattributed'),
    (select n from opp_total), '{{ guide }}#reading-the-readiness-check'
  -- GA4
  union all
  select 10, 'ga4', 'ga4_sessions_in_window', 'GA4 sessions found in the observation window',
    (select count(*) from {{ ref('pipetrace_int_ga4_sessions') }}), cast(null as int64), '{{ guide }}#before-you-start'
  union all
  select 11, 'ga4', 'ga4_sessions_with_token', 'GA4 sessions carrying a conversion token',
    (select count(distinct session_key) from {{ ref('pipetrace_int_session_conversion_tokens') }}),
    (select count(*) from {{ ref('pipetrace_int_ga4_sessions') }}), '{{ guide }}#level-2-conversion-token'
  -- HubSpot
  union all
  select 20, 'hubspot', 'hubspot_contacts_with_token', 'HubSpot contacts with a conversion token ({{ var("hubspot_conversion_token_property") }})',
    (select countif(original_conversion_id is not null) from {{ ref('pipetrace_stg_hubspot_contacts') }}),
    (select count(*) from {{ ref('pipetrace_stg_hubspot_contacts') }}), '{{ guide }}#level-2-conversion-token'
  union all
  select 21, 'hubspot', 'hubspot_contacts_with_ga_client_id', 'HubSpot contacts with a GA4 client ID ({{ var("hubspot_ga_client_id_property") }})',
    (select countif(ga_client_id is not null) from {{ ref('pipetrace_stg_hubspot_contacts') }}),
    (select count(*) from {{ ref('pipetrace_stg_hubspot_contacts') }}), '{{ guide }}#level-1-ga4-client-id'
  union all
  select 22, 'hubspot', 'hubspot_contacts_with_original_source', 'HubSpot contacts with an original source',
    (select countif(original_source is not null) from {{ ref('pipetrace_stg_hubspot_contacts') }}),
    (select count(*) from {{ ref('pipetrace_stg_hubspot_contacts') }}), '{{ guide }}#level-0-crm-source'
  union all
  select 23, 'hubspot', 'hubspot_contacts_linked_to_salesforce', 'HubSpot contacts with a Salesforce lead or contact ID',
    (select countif(sfdc_lead_id is not null or sfdc_contact_id is not null) from {{ ref('pipetrace_stg_hubspot_contacts') }}),
    (select count(*) from {{ ref('pipetrace_stg_hubspot_contacts') }}), '{{ guide }}#before-you-start'
  -- Salesforce
  union all
  select 30, 'salesforce', 'sfdc_leads_with_token', 'Salesforce leads with a conversion token ({{ var("sfdc_lead_conversion_token_field") }})',
    (select countif(original_conversion_id is not null) from {{ ref('pipetrace_stg_sfdc_leads') }}),
    (select count(*) from {{ ref('pipetrace_stg_sfdc_leads') }}), '{{ guide }}#level-2-conversion-token'
  union all
  select 31, 'salesforce', 'sfdc_leads_with_ga_client_id', 'Salesforce leads with a GA4 client ID ({{ var("sfdc_lead_ga_client_id_field") }})',
    (select countif(ga_client_id is not null) from {{ ref('pipetrace_stg_sfdc_leads') }}),
    (select count(*) from {{ ref('pipetrace_stg_sfdc_leads') }}), '{{ guide }}#level-1-ga4-client-id'
  union all
  select 32, 'salesforce', 'sfdc_leads_with_first_touch', 'Salesforce leads with first-touch source or medium',
    (select countif(ft_source is not null or ft_medium is not null) from {{ ref('pipetrace_stg_sfdc_leads') }}),
    (select count(*) from {{ ref('pipetrace_stg_sfdc_leads') }}), '{{ guide }}#level-0-crm-source'
  union all
  select 33, 'salesforce', 'sfdc_opportunities_with_token', 'Opportunities with a conversion token ({{ var("sfdc_opportunity_conversion_token_field") }})',
    (select countif(original_conversion_id is not null) from {{ ref('pipetrace_stg_sfdc_opportunities') }}),
    (select n from opp_total), '{{ guide }}#level-2-conversion-token'
  -- Do CRM values actually match GA4? Catches format mismatches.
  union all
  select 40, 'match', 'crm_tokens_found_in_ga4', 'CRM conversion tokens that appear in GA4',
    (select count(*) from crm_tokens c where exists (
      select 1 from {{ ref('pipetrace_int_session_conversion_tokens') }} t where t.original_conversion_id = c.token)),
    (select count(*) from crm_tokens), '{{ guide }}#level-2-conversion-token'
  union all
  select 41, 'match', 'crm_client_ids_found_in_ga4', 'CRM GA4 client IDs that appear in GA4 as user_pseudo_id',
    (select count(*) from crm_client_ids c where exists (
      select 1 from {{ ref('pipetrace_int_ga4_sessions') }} s where s.user_pseudo_id = c.client_id)),
    (select count(*) from crm_client_ids), '{{ guide }}#level-1-ga4-client-id'
)
select check_order, area, check_name, description, numerator, denominator,
  safe_divide(numerator, denominator) as share,
  case
    when check_name = 'ga4_sessions_in_window' then if(numerator > 0, 'ok', 'missing')
    when check_name = 'level_1_ga_client_id' and not {{ pipetrace_flag('enable_ga_client_id_matching') }} then 'off'
    when check_name = 'level_0_crm_source' and not {{ pipetrace_flag('enable_crm_source_fallback') }} then 'off'
    when denominator is null or denominator = 0 then 'no_rows'
    when check_name = 'unattributed' then if(numerator = 0, 'ok', 'review')
    when numerator = 0 then 'missing'
    when area = 'level' then 'ok'
    when safe_divide(numerator, denominator) < 0.5 then 'low'
    else 'ok'
  end as status,
  guide_section
from checks
