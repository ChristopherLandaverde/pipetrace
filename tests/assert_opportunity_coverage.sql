select o.opportunity_id
from {{ ref('stg_sfdc_opportunities') }} o
left join {{ ref('fct_revops_pipeline_attribution') }} a using (opportunity_id)
where a.opportunity_id is null
