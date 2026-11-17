-- Keep every token, not just the first conversion in a session.
select e.session_key, e.original_conversion_id, min(e.event_timestamp) as conversion_timestamp
from {{ ref('stg_ga4_events') }} as e
inner join {{ ref('int_ga4_sessions') }} as s on e.session_key = s.session_key
where e.original_conversion_id is not null
group by e.session_key, e.original_conversion_id
