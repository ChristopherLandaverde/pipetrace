with raw as (
  select t.*, to_json_string(t) as row_json
  from {{ source('salesforce', 'opportunities') }} as t
)
select
  cast(Id as string) as opportunity_id,
  cast(AccountId as string) as account_id,
  nullif(trim(json_value(row_json, '$.ContactId')), '') as primary_contact_id,
  Name as opportunity_name,
  StageName as stage_name,
  safe_cast(Amount as numeric) as amount,
  safe_cast(json_value(row_json, '$.ARR__c') as numeric) as arr,
  coalesce(safe_cast(json_value(row_json, '$.ARR__c') as numeric), safe_cast(Amount as numeric)) as pipeline_value,
  case when safe_cast(json_value(row_json, '$.ARR__c') as numeric) is not null
    then 'ARR' else 'Amount' end as revenue_basis,
  coalesce(json_value(row_json, '$.CurrencyIsoCode'), 'UNSPECIFIED') as currency_code,
  safe_cast(IsWon as bool) as is_won,
  safe_cast(IsClosed as bool) as is_closed,
  safe_cast(CreatedDate as timestamp) as created_at,
  safe_cast(CloseDate as date) as close_date,
  nullif(trim(cast(Original_Conversion_Id__c as string)), '') as original_conversion_id
from raw
where not coalesce(safe_cast(IsDeleted as bool), false)
