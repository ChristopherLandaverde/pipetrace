{{ config(partition_by={'field': 'touchpoint_date', 'data_type': 'date'}, cluster_by=['channel_grouping']) }}
select session_key as touchpoint_id, session_date as touchpoint_date,
  session_start_timestamp as touchpoint_timestamp, user_pseudo_id, user_id,
  session_default_channel_grouping as channel_grouping,
  session_source as source, session_medium as medium, session_campaign as campaign,
  attribution_method, landing_page, gclid, fbclid, original_conversion_id
from {{ ref('pipetrace_int_ga4_sessions') }}
