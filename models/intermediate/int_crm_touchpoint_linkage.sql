-- Each opportunity is credited at the strongest level its evidence supports:
--   2 conversion_token  sessions holding the token copied to the CRM
--   1 ga_client_id      sessions of the GA4 client ID stored on a CRM record
--   0 crm_source        the source the CRM itself recorded; no session
-- Opportunities with none of these stay Unattributed (level null).
with opportunities as (
  select * from {{ ref('stg_sfdc_opportunities') }}
), paths as (
  select * from {{ ref('int_opportunity_identity_paths') }}
), token_candidates as (
  select p.opportunity_id, t.session_key, p.match_method, p.match_priority
  from paths p
  join {{ ref('int_session_conversion_tokens') }} t on p.conversion_token = t.original_conversion_id
  join {{ ref('int_ga4_sessions') }} s on t.session_key = s.session_key
  join opportunities o on p.opportunity_id = o.opportunity_id
  where p.conversion_token is not null
    and s.session_start_timestamp <= o.created_at
    and t.conversion_timestamp <= o.created_at
    and s.session_start_timestamp >= timestamp_sub(o.created_at, interval {{ var('attribution_lookback_days') | int }} day)
), client_candidates as (
  select p.opportunity_id, s.session_key, p.match_method, p.match_priority
  from paths p
  join {{ ref('int_ga4_sessions') }} s on p.ga_client_id = s.user_pseudo_id
  join opportunities o on p.opportunity_id = o.opportunity_id
  where {{ var('enable_ga_client_id_matching') }}
    and p.ga_client_id is not null
    and s.session_start_timestamp <= o.created_at
    and s.session_start_timestamp >= timestamp_sub(o.created_at, interval {{ var('attribution_lookback_days') | int }} day)
), session_candidates as (
  select opportunity_id, session_key, match_method, match_priority, 2 as attribution_level from token_candidates
  union all
  select opportunity_id, session_key, match_method, match_priority, 1 from client_candidates
), best_session_level as (
  select opportunity_id, max(attribution_level) as attribution_level
  from session_candidates group by opportunity_id
), sessions_ranked as (
  select c.*,
    row_number() over (partition by c.opportunity_id, c.session_key
      order by c.match_priority, c.match_method) as match_rank
  from session_candidates c
  join best_session_level b
    on c.opportunity_id = b.opportunity_id and c.attribution_level = b.attribution_level
), crm_ranked as (
  select p.*,
    row_number() over (partition by p.opportunity_id order by p.match_priority, p.match_method) as crm_rank
  from paths p
  left join best_session_level b on p.opportunity_id = b.opportunity_id
  where {{ var('enable_crm_source_fallback') }}
    and p.crm_channel_grouping is not null
    and b.opportunity_id is null
), evidence as (
  select opportunity_id, session_key, match_method, attribution_level,
    cast(null as string) as crm_source, cast(null as string) as crm_medium,
    cast(null as string) as crm_campaign, cast(null as string) as crm_channel_grouping
  from sessions_ranked where match_rank = 1
  union all
  select opportunity_id, cast(null as string), concat(crm_source_system, '_source'), 0,
    crm_source, crm_medium, crm_campaign, crm_channel_grouping
  from crm_ranked where crm_rank = 1
)
select o.opportunity_id, o.opportunity_name, o.stage_name,
  o.arr, o.amount, o.pipeline_value, o.revenue_basis, o.currency_code, o.is_won, o.is_closed,
  o.created_at as opp_created_at, o.close_date,
  e.session_key, coalesce(e.match_method, 'unmatched') as match_method,
  e.attribution_level,
  case e.attribution_level
    when 2 then 'conversion_token' when 1 then 'ga_client_id' when 0 then 'crm_source'
    else 'unattributed' end as attribution_basis,
  s.session_start_timestamp,
  coalesce(s.session_source, e.crm_source) as session_source,
  coalesce(s.session_medium, e.crm_medium) as session_medium,
  coalesce(s.session_campaign, e.crm_campaign) as session_campaign,
  s.session_default_channel_grouping,
  coalesce(s.session_default_channel_grouping, e.crm_channel_grouping) as channel_grouping
from opportunities o
left join evidence e on o.opportunity_id = e.opportunity_id
left join {{ ref('int_ga4_sessions') }} s on e.session_key = s.session_key
