select
  cast(id as string) as hubspot_contact_id,
  lower(nullif(trim(property_email), '')) as email,
  safe_cast(property_createdate as timestamp) as created_at,
  property_hs_analytics_source as original_source,
  property_hs_analytics_source_data_1 as original_source_data_1,
  nullif(trim(cast(property_original_conversion_id as string)), '') as original_conversion_id,
  property_hs_lead_status as lead_status,
  nullif(trim(cast(property_salesforceleadid as string)), '') as sfdc_lead_id,
  nullif(trim(cast(property_salesforcecontactid as string)), '') as sfdc_contact_id
from {{ source('hubspot', 'contacts') }}
