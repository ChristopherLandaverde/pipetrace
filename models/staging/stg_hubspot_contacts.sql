-- Optional properties are read through JSON so a missing column becomes NULL
-- instead of failing the build. Property names are set in dbt_project.yml vars.
with raw as (
  select t.*, to_json_string(t) as row_json
  from {{ source('hubspot', 'contacts') }} as t
)
select
  cast(id as string) as hubspot_contact_id,
  lower({{ pipetrace_optional_column('property_email') }}) as email,
  safe_cast(property_createdate as timestamp) as created_at,
  {{ pipetrace_optional_column('property_hs_analytics_source') }} as original_source,
  {{ pipetrace_optional_column('property_hs_analytics_source_data_1') }} as original_source_data_1,
  {{ pipetrace_optional_column(var('hubspot_conversion_token_property')) }} as original_conversion_id,
  {{ pipetrace_normalize_ga_client_id(pipetrace_optional_column(var('hubspot_ga_client_id_property'))) }} as ga_client_id,
  {{ pipetrace_optional_column('property_hs_lead_status') }} as lead_status,
  {{ pipetrace_optional_column('property_salesforceleadid') }} as sfdc_lead_id,
  {{ pipetrace_optional_column('property_salesforcecontactid') }} as sfdc_contact_id
from raw
