{{ config(enabled=var('validate_fixture', false)) }}
select 1 as fixture_failure
where (select count(*) from {{ ref('int_ga4_sessions') }}) != 2
  or (select count(*) from {{ ref('stg_sfdc_opportunities') }}) != 2
  or (select count(*) from {{ ref('fct_revops_pipeline_attribution') }}) != 2
  or (select sum(linear_pipeline_value) from {{ ref('fct_revops_pipeline_attribution') }}) is distinct from 1500
  or (select count(*) from {{ ref('fct_revops_pipeline_attribution') }} where channel_grouping = 'Unattributed') != 1
  or (select count(*) from {{ ref('int_ga4_sessions') }}
      where session_key = 'u1-1767311940' and total_events = 2 and session_date = date('2026-01-01')
        and session_source = 'newsletter' and session_medium = 'email' and is_engaged_session) != 1
