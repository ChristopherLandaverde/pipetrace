{{ config(enabled=var('validate_fixture', false)) }}
{% set base = var('fixture_base_date', '2026-01-01') %}
select 1 as fixture_failure
from unnest([1])
where (select count(*) from {{ ref('int_ga4_sessions') }}) != 4
  or (select count(*) from {{ ref('stg_sfdc_opportunities') }}) != 5
  or (select count(*) from {{ ref('fct_revops_pipeline_attribution') }}) != 6
  or (select sum(linear_pipeline_value) from {{ ref('fct_revops_pipeline_attribution') }}) is distinct from 2800
  or (select count(*) from {{ ref('fct_revops_pipeline_attribution') }} where channel_grouping = 'Unattributed') != 1
  -- One opportunity per level: o1 token, o3 client ID (two sessions), o4 and o5 CRM source, o2 none.
  or (select string_agg(concat(opportunity_id, ':', attribution_basis, ':', channel_grouping, ':', format('%.2f', linear_touch_weight)), ',' order by opportunity_id, session_key)
      from {{ ref('fct_revops_pipeline_attribution') }})
     != 'o1:conversion_token:Email:1.00,o2:unattributed:Unattributed:1.00,o3:ga_client_id:Paid Search:0.50,o3:ga_client_id:Email:0.50,o4:crm_source:Organic Search:1.00,o5:crm_source:Paid Social:1.00'
  or (select count(*) from {{ ref('int_ga4_sessions') }}
      where session_key = concat('u1-', cast(unix_seconds(timestamp(datetime(date('{{ base }}'), time(23, 59, 0)))) as string))
        and total_events = 2 and session_date = date('{{ base }}')
        and session_source = 'newsletter' and session_medium = 'email' and is_engaged_session) != 1
