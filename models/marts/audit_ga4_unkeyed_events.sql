select event_date, event_name, count(*) as excluded_events
from {{ ref('stg_ga4_events') }}
where session_key is null or ga_session_id not between 0 and 253402300799
group by 1, 2
