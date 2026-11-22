select opportunity_id
from {{ ref('pipetrace_fct_revops_pipeline_attribution') }}
group by opportunity_id
having abs(sum(first_touch_weight) - 1) > 0.000000001
    or abs(sum(linear_touch_weight) - 1) > 0.000000001
    or min(first_touch_weight) < 0 or min(linear_touch_weight) <= 0
