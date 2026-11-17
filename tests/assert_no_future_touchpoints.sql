select opportunity_id, session_key
from {{ ref('int_crm_touchpoint_linkage') }}
where session_start_timestamp > opp_created_at
