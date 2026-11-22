-- Fivetran Salesforce LEAD table (snake_case columns, custom fields as *_c)
-- reshaped to the source contract's API names.
{{ config(enabled=(var('pipetrace_connector', 'native') | lower == 'fivetran'), materialized='view', tags=['connector']) }}
with raw as (
  select t.*, to_json_string(t) as row_json
  from {{ source('salesforce', 'leads') }} as t
)
select
  cast(id as string) as Id,
  {{ pipetrace_optional_column('converted_contact_id') }} as ConvertedContactId,
  {{ pipetrace_optional_column('converted_opportunity_id') }} as ConvertedOpportunityId,
  safe_cast(json_value(row_json, '$.is_converted') as bool) as IsConverted,
  {{ pipetrace_optional_column('email') }} as Email,
  safe_cast(json_value(row_json, '$.created_date') as timestamp) as CreatedDate,
  {{ pipetrace_optional_column('status') }} as Status,
  coalesce(safe_cast(json_value(row_json, '$.is_deleted') as bool), false)
    or coalesce(safe_cast(json_value(row_json, '$._fivetran_deleted') as bool), false) as IsDeleted
  {%- for field in pipetrace_sfdc_custom_fields('lead') %},
  {{ pipetrace_optional_column(pipetrace_fivetran_name(field)) }} as {{ field }}
  {%- endfor %}
from raw
