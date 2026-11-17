select
  cast(Id as string) as sfdc_lead_id,
  nullif(trim(cast(ConvertedContactId as string)), '') as converted_contact_id,
  nullif(trim(cast(ConvertedOpportunityId as string)), '') as converted_opportunity_id,
  safe_cast(IsConverted as bool) as is_converted,
  lower(nullif(trim(Email), '')) as email,
  safe_cast(CreatedDate as timestamp) as created_at,
  First_Touch_Source__c as ft_source,
  First_Touch_Medium__c as ft_medium,
  First_Touch_Campaign__c as ft_campaign,
  nullif(trim(cast(Original_Conversion_Id__c as string)), '') as original_conversion_id,
  Status as lead_status
from {{ source('salesforce', 'leads') }}
where not coalesce(safe_cast(IsDeleted as bool), false)
