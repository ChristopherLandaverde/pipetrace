{{ config(partition_by={'field': 'session_date', 'data_type': 'date'}, cluster_by=['session_key']) }}
with attributed_events as (
  select *,
    case
      when cross_source is not null or cross_medium is not null then
        struct(1 as priority, cross_source as source, cross_medium as medium, cross_campaign as campaign, 'session_cross_channel' as method)
      when google_ads_campaign is not null then
        struct(2, 'google', 'cpc', google_ads_campaign, 'session_google_ads')
      when last_click_source is not null or last_click_medium is not null then
        struct(3, last_click_source, last_click_medium, last_click_campaign, 'session_manual')
      when gclid is not null then struct(4, 'google', 'cpc', utm_campaign, 'gclid_fallback')
      when utm_source is not null or utm_medium is not null then
        struct(5, utm_source, utm_medium, utm_campaign, 'collected_fallback')
      else struct(6, cast(null as string), cast(null as string), cast(null as string), 'direct_fallback')
    end as attribution
  from {{ ref('stg_ga4_events') }}
  where session_key is not null
    -- GA4 IDs are Unix seconds. Bound before timestamp conversion to avoid overflow.
    and ga_session_id between 0 and 253402300799
), aggregated as (
  select session_key, user_pseudo_id, ga_session_id,
    array_agg(user_id ignore nulls order by event_timestamp, event_order_key limit 1)[safe_offset(0)] as user_id,
    timestamp_seconds(ga_session_id) as session_start_timestamp,
    min(event_timestamp) as first_observed_event_timestamp,
    max(event_timestamp) as session_end_timestamp,
    date(timestamp_seconds(ga_session_id), '{{ var("ga4_timezone") }}') as session_date,
    array_agg(page_location ignore nulls order by event_timestamp, event_order_key limit 1)[safe_offset(0)] as landing_page,
    array_agg(attribution order by attribution.priority, event_timestamp, event_order_key limit 1)[offset(0)] as attribution,
    array_agg(gclid ignore nulls order by event_timestamp, event_order_key limit 1)[safe_offset(0)] as gclid,
    array_agg(fbclid ignore nulls order by event_timestamp, event_order_key limit 1)[safe_offset(0)] as fbclid,
    array_agg(original_conversion_id ignore nulls order by event_timestamp, event_order_key limit 1)[safe_offset(0)] as original_conversion_id,
    countif(session_engaged = '1') > 0 as is_engaged_session,
    countif(event_name in ({% for name in var('lead_conversion_events') %}'{{ name }}'{% if not loop.last %}, {% endif %}{% endfor %})) > 0 as has_lead_conversion,
    sum(coalesce(engagement_time_msec, 0)) as engagement_time_msec,
    count(*) as total_events
  from attributed_events
  group by session_key, user_pseudo_id, ga_session_id
), flattened as (
  select * except(attribution),
    attribution.source as session_source,
    attribution.medium as session_medium,
    attribution.campaign as session_campaign,
    attribution.method as attribution_method
  from aggregated
  where session_date between {{ ga4_start_date() }} and {{ ga4_end_date() }}
)
select *,
  {{ pipetrace_channel_grouping('session_source', 'session_medium') }} as session_default_channel_grouping
from flattened
-- Deliberately simplified channel rules; fbclid alone is not evidence of paid traffic.
