# Source contracts

Read-only source access is sufficient. This package never writes HubSpot, Salesforce, or GA4. Source tables must expose these names and current snapshots.

## Loaders

Set `pipetrace_connector` to match how HubSpot and Salesforce reach BigQuery. PipeTrace then reads mapping views that reshape the loader's tables into the contract below.

| `pipetrace_connector` | HubSpot table | Salesforce tables | Mapping |
|---|---|---|---|
| `native` (default) | `contacts` | `Lead`, `Opportunity` | None: tables already follow this contract |
| `fivetran` | `contact` | `lead`, `opportunity` | Drops `_fivetran_deleted` rows; renames Salesforce snake_case columns (`Foo__c` → `foo_c`) back to API names |
| `airbyte` | `contacts` | `Lead`, `Opportunity` | Unpacks the HubSpot `properties` JSON (or JSON string); drops `archived` rows. Salesforce streams already use API names |

Override table names with `hubspot_contacts_table`, `sfdc_lead_table` and `sfdc_opportunity_table` (BigQuery table names are case-sensitive; some Airbyte destinations write `lead` and `opportunity`). History-mode or append-only tables (Fivetran `_fivetran_active`, Airbyte append streams) need a current-snapshot view first. Mappings are verified on synthetic tables in each loader's documented shape, not on a live connection.

## GA4

Daily `events_YYYYMMDD` tables with native GA4 `event_date`, `event_timestamp`, `event_name`, `user_pseudo_id`, `user_id`, and `event_params` are required. `event_params` must be an array of key/value structs containing string/int/float/double slots. Session identity requires a valid Unix-second `ga_session_id` and nonblank pseudonym. A single GA4 property is modeled per package instance; do not union properties under the same pseudonym/session namespace.

Traffic records, device, and geography are optional and accessed as JSON. Event dates use export dates; session dates use `ga4_timezone`. Keep it equal to your property's timezone. Intraday exports are excluded so daily and intraday copies cannot both count. Wildcard tables still require compatible shared column types. Table-level schema drift must be normalized upstream if BigQuery rejects the wildcard scan.

`original_conversion_id` is an immutable, opaque, non-PII token captured on the conversion and copied unchanged to CRM. Never use an email address as this token. Blank tokens become null. Multiple events may repeat a token for the same user. A shared token across users is an integrity failure. A missing token produces no inferred identity match.

No blanket event deduplication occurs. GA4 has no universal guaranteed event UUID. Removing rows solely because timestamps and names match can delete legitimate events. Upstream event replay handling needs an explicit contract.

## HubSpot contacts

| Required column | Expected type/meaning |
|---|---|
| `id` | Unique current contact ID |
| `property_email` | Nullable string; restricted, not used for joining |
| `property_createdate` | Timestamp or timestamp string |
| `property_hs_analytics_source` | Nullable string |
| `property_hs_analytics_source_data_1` | Nullable string |
| `property_original_conversion_id` | Nullable opaque token |
| `property_hs_lead_status` | Nullable string |
| `property_salesforceleadid` | Nullable Salesforce lead ID |
| `property_salesforcecontactid` | Nullable Salesforce contact ID |

## Salesforce Lead

`Id`, `ConvertedContactId`, `ConvertedOpportunityId`, `IsConverted`, `Email`, `CreatedDate`, `First_Touch_Source__c`, `First_Touch_Medium__c`, `First_Touch_Campaign__c`, `Original_Conversion_Id__c`, `Status`, `IsDeleted`. One row per Id. Deleted rows are excluded. Remove connector history and soft-delete artifacts in an upstream view.

## Salesforce Opportunity

Required: `Id`, `AccountId`, `Name`, `StageName`, `Amount`, `IsWon`, `IsClosed`, `CreatedDate`, `CloseDate`, `Original_Conversion_Id__c`, `IsDeleted`.

Optional JSON-accessed columns: `ContactId`, `ARR__c`, `CurrencyIsoCode`. `ContactId` is not assumed to exist on every Salesforce Opportunity export. Converted lead IDs and opportunity tokens remain usable without it. To use OpportunityContactRole, expose an explicit primary-contact mapping upstream; do not join every contact role without revisiting the attribution grain.

Amount/ARR must already represent the intended currency and business definition. Missing CurrencyIsoCode produces `UNSPECIFIED`, not an assumed USD value. Numeric parse failures remain null. An unknown revenue amount is not a zero-dollar deal.
