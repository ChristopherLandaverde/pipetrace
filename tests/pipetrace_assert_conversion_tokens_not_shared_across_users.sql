select t.original_conversion_id
from {{ ref('pipetrace_int_session_conversion_tokens') }} t
join {{ ref('pipetrace_int_ga4_sessions') }} s using (session_key)
group by 1 having count(distinct s.user_pseudo_id) > 1
