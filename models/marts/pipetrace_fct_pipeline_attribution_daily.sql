{{ config(partition_by={'field': 'opp_created_date', 'data_type': 'date'}, cluster_by=['channel_grouping', 'currency_code']) }}
select opp_created_date, channel_grouping, attribution_basis, currency_code, revenue_basis,
  sum(first_touch_weight) as first_touch_opportunities,
  sum(linear_touch_weight) as linear_opportunities,
  sum(first_touch_pipeline_value) as first_touch_pipeline_value,
  sum(linear_pipeline_value) as linear_pipeline_value,
  sum(first_touch_won_value) as first_touch_won_value,
  sum(linear_won_value) as linear_won_value,
  sum(first_touch_arr) as first_touch_arr,
  sum(linear_arr) as linear_arr
from {{ ref('pipetrace_fct_revops_pipeline_attribution') }}
group by 1, 2, 3, 4, 5
