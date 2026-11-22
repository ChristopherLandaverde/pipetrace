-- Airbyte HubSpot contacts stream: properties arrive as one JSON column.
-- Unpacked to the source contract's property_* columns. Drops archived rows.
-- Airbyte's Salesforce streams already use API names and need no mapping.
{{ config(enabled=(var('pipetrace_connector', 'native') | lower == 'airbyte'), materialized='view', tags=['connector']) }}
with raw as (
  select t.*, to_json_string(t) as row_json
  from {{ source('hubspot', 'contacts') }} as t
), unpacked as (
  -- properties is JSON in Airbyte's BigQuery destination v2. If an older
  -- destination stored it as a STRING, parse it so lookups still resolve.
  select *, coalesce(json_query(row_json, '$.properties'), '{}') as properties_text
  from raw
), props as (
  select *, if(starts_with(properties_text, '"'),
      safe.parse_json(json_value(row_json, '$.properties')),
      safe.parse_json(properties_text)) as props_json
  from unpacked
)
select
  json_value(row_json, '$.id') as id,
  coalesce(json_value(props_json, '$.createdate'), json_value(row_json, '$.createdAt')) as property_createdate
  {%- for column in pipetrace_hubspot_contact_columns() | unique %},
  nullif(json_value(props_json, '$.{{ pipetrace_hubspot_property_name(column) }}'), '') as {{ column }}
  {%- endfor %}
from props
where not coalesce(safe_cast(json_value(row_json, '$.archived') as bool), false)
