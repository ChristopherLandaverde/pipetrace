-- Fivetran Salesforce OPPORTUNITY table reshaped to the source contract.
{{ config(enabled=(var('pipetrace_connector', 'native') | lower == 'fivetran'), materialized='view', tags=['connector']) }}
with raw as (
  select t.*, to_json_string(t) as row_json
  from {{ source('salesforce', 'opportunities') }} as t
)
select
  cast(id as string) as Id,
  {{ pipetrace_optional_column('account_id') }} as AccountId,
  {{ pipetrace_optional_column('name') }} as Name,
  {{ pipetrace_optional_column('stage_name') }} as StageName,
  safe_cast(json_value(row_json, '$.amount') as numeric) as Amount,
  safe_cast(json_value(row_json, '$.is_won') as bool) as IsWon,
  safe_cast(json_value(row_json, '$.is_closed') as bool) as IsClosed,
  safe_cast(json_value(row_json, '$.created_date') as timestamp) as CreatedDate,
  safe_cast(json_value(row_json, '$.close_date') as date) as CloseDate,
  coalesce(safe_cast(json_value(row_json, '$.is_deleted') as bool), false)
    or coalesce(safe_cast(json_value(row_json, '$._fivetran_deleted') as bool), false) as IsDeleted
  {%- for field in pipetrace_sfdc_custom_fields('opportunity') %},
  {{ pipetrace_optional_column(pipetrace_fivetran_name(field)) }} as {{ field }}
  {%- endfor %}
from raw
