select session_key, count(*) as occurrences
from {{ ref('int_ga4_sessions') }}
group by session_key having count(*) > 1
