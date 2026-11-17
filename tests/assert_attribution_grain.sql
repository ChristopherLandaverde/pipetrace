select opportunity_id, session_key, count(*) as occurrences
from {{ ref('fct_revops_pipeline_attribution') }}
group by 1, 2 having count(*) > 1
