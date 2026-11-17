-- BI / agent example. This is opportunity-creation cohort value, not bookings by close date.
select channel_grouping, currency_code, revenue_basis,
  sum(linear_pipeline_value) as pipeline_value,
  sum(linear_won_value) as won_value
from {{ ref('fct_pipeline_attribution_daily') }}
where opp_created_date >= date_sub(current_date(), interval 30 day)
group by 1, 2, 3
