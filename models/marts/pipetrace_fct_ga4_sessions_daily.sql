{{ config(partition_by={'field': 'session_date', 'data_type': 'date'}, cluster_by=['session_default_channel_grouping', 'session_source']) }}
select session_date, session_default_channel_grouping,
  coalesce(session_source, '(direct)') as session_source,
  coalesce(session_medium, '(none)') as session_medium,
  coalesce(session_campaign, '(not set)') as session_campaign,
  count(*) as total_sessions,
  countif(is_engaged_session) as engaged_sessions,
  countif(has_lead_conversion) as lead_conversion_sessions,
  count(distinct user_pseudo_id) as unique_visitors,
  sum(total_events) as total_events
from {{ ref('pipetrace_int_ga4_sessions') }}
group by 1, 2, 3, 4, 5
