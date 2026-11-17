select 1 as failure
from unnest([1])
where (select count(*) from {{ ref('int_ga4_sessions') }}) !=
  (select coalesce(sum(total_sessions), 0) from {{ ref('fct_ga4_sessions_daily') }})
