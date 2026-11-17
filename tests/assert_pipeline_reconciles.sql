with allocated as (
  select opportunity_id,
    sum(first_touch_pipeline_value) as first_value,
    sum(linear_pipeline_value) as linear_value
  from {{ ref('fct_revops_pipeline_attribution') }} group by 1
)
select o.opportunity_id
from {{ ref('stg_sfdc_opportunities') }} o
left join allocated a using (opportunity_id)
where (o.pipeline_value is not null and
  (a.first_value is null or a.linear_value is null
   or abs(o.pipeline_value - a.first_value) > 0.01
   or abs(o.pipeline_value - a.linear_value) > 0.01))
  or (o.pipeline_value is null and (a.first_value is not null or a.linear_value is not null))
