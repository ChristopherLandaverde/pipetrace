{{ config(partition_by={'field': 'opp_created_date', 'data_type': 'date'}, cluster_by=['channel_grouping', 'stage_name']) }}
with ranked as (
  select *,
    row_number() over (partition by opportunity_id order by session_start_timestamp, session_key) as touch_rank,
    count(*) over (partition by opportunity_id) as touch_count
  from {{ ref('pipetrace_int_crm_touchpoint_linkage') }}
), weighted as (
  select opportunity_id, opportunity_name, date(opp_created_at) as opp_created_date,
    close_date, stage_name, is_won, is_closed, currency_code, revenue_basis,
    arr as opp_arr, pipeline_value as opp_pipeline_value,
    session_key, match_method, attribution_level, attribution_basis,
    coalesce(channel_grouping, 'Unattributed') as channel_grouping,
    session_source, session_medium, session_campaign,
    timestamp_diff(opp_created_at, session_start_timestamp, day) as days_to_opportunity_create,
    case when touch_rank = 1 then 1.0 else 0.0 end as first_touch_weight,
    1.0 / touch_count as linear_touch_weight
  from ranked
)
select *,
  opp_pipeline_value * first_touch_weight as first_touch_pipeline_value,
  opp_pipeline_value * linear_touch_weight as linear_pipeline_value,
  case when is_won then opp_pipeline_value * first_touch_weight else 0 end as first_touch_won_value,
  case when is_won then opp_pipeline_value * linear_touch_weight else 0 end as linear_won_value,
  opp_arr * first_touch_weight as first_touch_arr,
  opp_arr * linear_touch_weight as linear_arr
from weighted
