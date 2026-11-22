-- Session-level credit (levels 1 and 2) always names a session; CRM-source
-- credit (level 0) and Unattributed rows never do. One level per opportunity.
select opportunity_id
from {{ ref('pipetrace_fct_revops_pipeline_attribution') }}
group by opportunity_id
having count(distinct coalesce(attribution_basis, '')) != 1
    or countif(attribution_level in (1, 2) and session_key is null) > 0
    or countif((attribution_level = 0 or attribution_level is null) and session_key is not null) > 0
    or countif(attribution_level is null and channel_grouping != 'Unattributed') > 0
    or countif(attribution_level = 0) > 1
