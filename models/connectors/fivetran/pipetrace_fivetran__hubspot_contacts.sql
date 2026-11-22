-- Fivetran HubSpot CONTACT table: already property_* columns. Drops deleted rows.
{{ config(enabled=(var('pipetrace_connector', 'native') | lower == 'fivetran'), materialized='view', tags=['connector']) }}
with raw as (
  select t.*, to_json_string(t) as row_json
  from {{ source('hubspot', 'contacts') }} as t
)
select * except(row_json)
from raw
where not coalesce(safe_cast(json_value(row_json, '$._fivetran_deleted') as bool), false)
