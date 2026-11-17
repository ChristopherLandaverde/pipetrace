with leads as (
  select * from {{ ref('stg_sfdc_leads') }}
), contacts as (
  select * from {{ ref('stg_hubspot_contacts') }}
), opportunities as (
  select * from {{ ref('stg_sfdc_opportunities') }}
), token_paths as (
  select opportunity_id, original_conversion_id as conversion_token, 'opportunity_token' as match_method, 1 as match_priority
  from opportunities where original_conversion_id is not null
  union all
  select o.opportunity_id, l.original_conversion_id, 'converted_opportunity', 2
  from opportunities o join leads l on o.opportunity_id = l.converted_opportunity_id
  where l.original_conversion_id is not null
  union all
  select o.opportunity_id, l.original_conversion_id, 'converted_contact', 3
  from opportunities o join leads l on o.primary_contact_id = l.converted_contact_id
  where l.original_conversion_id is not null
  union all
  select o.opportunity_id, h.original_conversion_id, 'hubspot_contact', 4
  from opportunities o join contacts h on o.primary_contact_id = h.sfdc_contact_id
  where h.original_conversion_id is not null
  union all
  select o.opportunity_id, h.original_conversion_id, 'hubspot_lead', 5
  from opportunities o join leads l on o.opportunity_id = l.converted_opportunity_id
  join contacts h on l.sfdc_lead_id = h.sfdc_lead_id
  where h.original_conversion_id is not null
), candidates as (
  select p.opportunity_id, t.session_key, p.match_method,
    row_number() over (partition by p.opportunity_id, t.session_key
      order by p.match_priority, p.conversion_token) as match_rank
  from token_paths p
  join {{ ref('int_session_conversion_tokens') }} t on p.conversion_token = t.original_conversion_id
  join {{ ref('int_ga4_sessions') }} s on t.session_key = s.session_key
  join opportunities o on p.opportunity_id = o.opportunity_id
  where s.session_start_timestamp <= o.created_at
    and t.conversion_timestamp <= o.created_at
    and s.session_start_timestamp >= timestamp_sub(o.created_at, interval {{ var('attribution_lookback_days') | int }} day)
)
select o.opportunity_id, o.opportunity_name, o.stage_name,
  o.arr, o.amount, o.pipeline_value, o.revenue_basis, o.currency_code, o.is_won, o.is_closed,
  o.created_at as opp_created_at, o.close_date,
  c.session_key, coalesce(c.match_method, 'unmatched') as match_method,
  s.session_start_timestamp, s.session_source, s.session_medium, s.session_campaign,
  s.session_default_channel_grouping
from opportunities o
left join candidates c on o.opportunity_id = c.opportunity_id and c.match_rank = 1
left join {{ ref('int_ga4_sessions') }} s on c.session_key = s.session_key
