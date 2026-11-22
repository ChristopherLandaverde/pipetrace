-- Custom fields (conversion token, GA client ID, first-touch UTMs) are read
-- through JSON so a missing field becomes NULL instead of failing the build.
with raw as (
  select t.*, to_json_string(t) as row_json
  from {{ pipetrace_crm_relation('salesforce', 'leads') }} as t
)
select
  cast(Id as string) as sfdc_lead_id,
  nullif(trim(cast(ConvertedContactId as string)), '') as converted_contact_id,
  nullif(trim(cast(ConvertedOpportunityId as string)), '') as converted_opportunity_id,
  safe_cast(IsConverted as bool) as is_converted,
  lower(nullif(trim(Email), '')) as email,
  safe_cast(CreatedDate as timestamp) as created_at,
  {{ pipetrace_optional_column(var('sfdc_lead_first_touch_source_field')) }} as ft_source,
  {{ pipetrace_optional_column(var('sfdc_lead_first_touch_medium_field')) }} as ft_medium,
  {{ pipetrace_optional_column(var('sfdc_lead_first_touch_campaign_field')) }} as ft_campaign,
  {{ pipetrace_optional_column(var('sfdc_lead_conversion_token_field')) }} as original_conversion_id,
  {{ pipetrace_normalize_ga_client_id(pipetrace_optional_column(var('sfdc_lead_ga_client_id_field'))) }} as ga_client_id,
  Status as lead_status
from raw
where not coalesce(safe_cast(IsDeleted as bool), false)
