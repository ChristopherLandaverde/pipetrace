{{ config(enabled=var('validate_fixture', false)) }}
{% set base = var('fixture_base_date', '2026-01-01') %}
select 1 as fixture_failure
from unnest([1])
where (select count(*) from {{ ref('int_ga4_sessions') }}) != 2
  or (select count(*) from {{ ref('stg_sfdc_opportunities') }}) != 2
  or (select count(*) from {{ ref('fct_revops_pipeline_attribution') }}) != 2
  or (select sum(linear_pipeline_value) from {{ ref('fct_revops_pipeline_attribution') }}) is distinct from 1500
  or (select count(*) from {{ ref('fct_revops_pipeline_attribution') }} where channel_grouping = 'Unattributed') != 1
  or (select count(*) from {{ ref('int_ga4_sessions') }}
      where session_key = concat('u1-', cast(unix_seconds(timestamp(datetime(date('{{ base }}'), time(23, 59, 0)))) as string))
        and total_events = 2 and session_date = date('{{ base }}')
        and session_source = 'newsletter' and session_medium = 'email' and is_engaged_session) != 1
