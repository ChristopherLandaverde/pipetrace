-- Airbyte HubSpot contacts stream: properties arrive as one JSON column.
-- Unpacked to the source contract's property_* columns. Drops archived rows.
-- Airbyte's Salesforce streams already use API names and need no mapping.
{{ config(enabled=(var('pipetrace_connector', 'native') | lower == 'airbyte'), materialized='view', tags=['connector']) }}
with raw as (
  select t.*, to_json_string(t) as row_json
  from {{ source('hubspot', 'contacts') }} as t
)
select
  json_value(row_json, '$.id') as id,
  coalesce(json_value(row_json, '$.properties.createdate'), json_value(row_json, '$.createdAt')) as property_createdate
  {%- for column in pipetrace_hubspot_contact_columns() | unique %},
  nullif(json_value(row_json, '$.properties.{{ pipetrace_hubspot_property_name(column) }}'), '') as {{ column }}
  {%- endfor %}
from raw
where not coalesce(safe_cast(json_value(row_json, '$.archived') as bool), false)
