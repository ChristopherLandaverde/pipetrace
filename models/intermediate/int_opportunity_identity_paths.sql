-- One row per opportunity and deterministic CRM record path. Each row carries
-- the evidence that record holds: a conversion token, a GA4 client ID, and the
-- source the CRM itself recorded. Paths are ranked; lower priority wins.
-- Joins use record IDs only, never email.
with leads as (
  select * from {{ ref('stg_sfdc_leads') }}
), contacts as (
  select * from {{ ref('stg_hubspot_contacts') }}
), opportunities as (
  select * from {{ ref('stg_sfdc_opportunities') }}
), paths as (
  select o.opportunity_id, 'opportunity_record' as match_method, 1 as match_priority,
    o.original_conversion_id as conversion_token, o.ga_client_id,
    cast(null as string) as crm_source_system, cast(null as string) as crm_source,
    cast(null as string) as crm_medium, cast(null as string) as crm_campaign,
    cast(null as string) as crm_channel_grouping
  from opportunities o
  union all
  select o.opportunity_id, 'converted_opportunity', 2,
    l.original_conversion_id, l.ga_client_id,
    'salesforce_lead', l.ft_source, l.ft_medium, l.ft_campaign,
    case when l.ft_source is not null or l.ft_medium is not null
      then {{ pipetrace_channel_grouping('l.ft_source', 'l.ft_medium') }} end
  from opportunities o join leads l on o.opportunity_id = l.converted_opportunity_id
  union all
  select o.opportunity_id, 'converted_contact', 3,
    l.original_conversion_id, l.ga_client_id,
    'salesforce_lead', l.ft_source, l.ft_medium, l.ft_campaign,
    case when l.ft_source is not null or l.ft_medium is not null
      then {{ pipetrace_channel_grouping('l.ft_source', 'l.ft_medium') }} end
  from opportunities o join leads l on o.primary_contact_id = l.converted_contact_id
  union all
  select o.opportunity_id, 'hubspot_contact', 4,
    h.original_conversion_id, h.ga_client_id,
    'hubspot', h.original_source, cast(null as string), cast(null as string),
    case when h.original_source is not null
      then {{ pipetrace_hubspot_source_channel('h.original_source') }} end
  from opportunities o join contacts h on o.primary_contact_id = h.sfdc_contact_id
  union all
  select o.opportunity_id, 'hubspot_lead', 5,
    h.original_conversion_id, h.ga_client_id,
    'hubspot', h.original_source, cast(null as string), cast(null as string),
    case when h.original_source is not null
      then {{ pipetrace_hubspot_source_channel('h.original_source') }} end
  from opportunities o join leads l on o.opportunity_id = l.converted_opportunity_id
  join contacts h on l.sfdc_lead_id = h.sfdc_lead_id
)
select * from paths
where conversion_token is not null or ga_client_id is not null or crm_channel_grouping is not null
