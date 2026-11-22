select o.opportunity_id
from {{ ref('pipetrace_stg_sfdc_opportunities') }} o
left join {{ ref('pipetrace_fct_revops_pipeline_attribution') }} a using (opportunity_id)
where a.opportunity_id is null
