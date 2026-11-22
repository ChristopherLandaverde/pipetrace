{{ config(enabled=var('validate_fixture', false)) }}
-- Expected readiness on the synthetic fixture: one deal per level.
select check_name, numerator, denominator, status
from {{ ref('pipetrace_readiness') }}
where concat(check_name, '=', cast(numerator as string), '/', coalesce(cast(denominator as string), '-'), ':', status) not in (
  'level_2_conversion_token=1/5:ok',
  'level_1_ga_client_id=1/5:ok',
  'level_0_crm_source=2/5:ok',
  'unattributed=1/5:review',
  'ga4_sessions_in_window=4/-:ok',
  'ga4_sessions_with_token=2/4:ok',
  'hubspot_contacts_with_token=1/2:ok',
  'hubspot_contacts_with_ga_client_id=0/2:missing',
  'hubspot_contacts_with_original_source=2/2:ok',
  'hubspot_contacts_linked_to_salesforce=2/2:ok',
  'sfdc_leads_with_token=1/3:low',
  'sfdc_leads_with_ga_client_id=1/3:low',
  'sfdc_leads_with_first_touch=2/3:ok',
  'sfdc_opportunities_with_token=1/5:low',
  'crm_tokens_found_in_ga4=1/1:ok',
  'crm_client_ids_found_in_ga4=1/1:ok'
)
union all
select 'row_count', count(*), 16, 'expected 16' from {{ ref('pipetrace_readiness') }} having count(*) != 16
