with raw as (
  select t.*, to_json_string(t) as row_json
  from {{ source('ga4', 'events') }} as t
  where _table_suffix between
    format_date('%Y%m%d', date_sub({{ pipetrace_ga4_start_date() }}, interval {{ var('ga4_boundary_buffer_days') | int }} day))
    and format_date('%Y%m%d', date_add({{ pipetrace_ga4_end_date() }}, interval {{ var('ga4_boundary_buffer_days') | int }} day))
), extracted as (
  select
    safe.parse_date('%Y%m%d', event_date) as event_date,
    timestamp_micros(event_timestamp) as event_timestamp,
    event_name, user_pseudo_id, user_id,
    {{ pipetrace_extract_event_param('ga_session_id', 'int') }} as ga_session_id,
    {{ pipetrace_extract_event_param('ga_session_number', 'int') }} as ga_session_number,
    {{ pipetrace_extract_event_param('page_location') }} as page_location,
    {{ pipetrace_extract_event_param('page_referrer') }} as page_referrer,
    coalesce(json_value(row_json, '$.collected_traffic_source.gclid'),
             {{ pipetrace_extract_event_param('gclid') }}) as gclid,
    {{ pipetrace_extract_event_param('fbclid') }} as fbclid,
    nullif(trim({{ pipetrace_extract_event_param(var('ga4_conversion_token_param')) }}), '') as original_conversion_id,
    {{ pipetrace_extract_event_param('engagement_time_msec', 'int') }} as engagement_time_msec,
    {{ pipetrace_extract_event_param('session_engaged') }} as session_engaged,
    json_value(row_json, '$.session_traffic_source_last_click.cross_channel_campaign.source') as cross_source,
    json_value(row_json, '$.session_traffic_source_last_click.cross_channel_campaign.medium') as cross_medium,
    json_value(row_json, '$.session_traffic_source_last_click.cross_channel_campaign.campaign_name') as cross_campaign,
    json_value(row_json, '$.session_traffic_source_last_click.manual_campaign.source') as last_click_source,
    json_value(row_json, '$.session_traffic_source_last_click.manual_campaign.medium') as last_click_medium,
    json_value(row_json, '$.session_traffic_source_last_click.manual_campaign.campaign_name') as last_click_campaign,
    json_value(row_json, '$.session_traffic_source_last_click.google_ads_campaign.campaign_name') as google_ads_campaign,
    coalesce(json_value(row_json, '$.collected_traffic_source.manual_source'), {{ pipetrace_extract_event_param('source') }}) as utm_source,
    coalesce(json_value(row_json, '$.collected_traffic_source.manual_medium'), {{ pipetrace_extract_event_param('medium') }}) as utm_medium,
    coalesce(json_value(row_json, '$.collected_traffic_source.manual_campaign_name'), {{ pipetrace_extract_event_param('campaign') }}) as utm_campaign,
    json_value(row_json, '$.collected_traffic_source.manual_term') as utm_term,
    json_value(row_json, '$.collected_traffic_source.manual_content') as utm_content,
    json_value(row_json, '$.traffic_source.source') as lifetime_user_source,
    json_value(row_json, '$.traffic_source.medium') as lifetime_user_medium,
    json_value(row_json, '$.device.category') as device_category,
    json_value(row_json, '$.geo.country') as geo_country,
    -- Used only as a deterministic tie breaker. This is not an event deduplication key.
    to_hex(sha256(row_json)) as event_order_key
  from raw
)
select *, {{ pipetrace_generate_session_key('user_pseudo_id', 'ga_session_id') }} as session_key
from extracted
