"""Emit synthetic BigQuery raw tables. Never executes SQL or connects to a service.

Use a disposable development project. Existing fixture tables are not overwritten.
"""
import argparse
import json
import re
from datetime import date, datetime, timedelta, timezone


def literal(value):
    if value is None: return 'NULL'
    if isinstance(value, bool): return 'TRUE' if value else 'FALSE'
    if isinstance(value, (int,float)): return str(value)
    return "'" + str(value).replace('\\','\\\\').replace("'","\\'") + "'"


def micros(ts):
    return int(datetime.fromisoformat(ts).replace(tzinfo=timezone.utc).timestamp()*1000000)


def event(ts, user, sid, token=None, medium=None, engaged=None):
    params=[('ga_session_id',str(sid)),('page_location','https://example.test/demo')]
    if token: params.append(('original_conversion_id',token))
    if engaged: params.append(('session_engaged',engaged))
    arr=[]
    for key,value in params:
        # Session ID deliberately arrives as STRING, exercising safe coercion.
        arr.append('STRUCT('+literal(key)+' AS key, STRUCT('+literal(value)+' AS string_value, CAST(NULL AS INT64) AS int_value, CAST(NULL AS FLOAT64) AS float_value, CAST(NULL AS FLOAT64) AS double_value) AS value)')
    return 'SELECT '+', '.join([
        literal(ts[:10].replace('-',''))+' AS event_date',str(micros(ts))+' AS event_timestamp',
        literal('generate_lead' if token else 'page_view')+' AS event_name',literal(user)+' AS user_pseudo_id',
        'CAST(NULL AS STRING) AS user_id','['+','.join(arr)+'] AS event_params',
        "STRUCT('lifetime-source' AS source, 'referral' AS medium) AS traffic_source",
        "STRUCT('desktop' AS category) AS device", "STRUCT('Synthetic' AS country) AS geo",
        'STRUCT('+literal('newsletter' if medium=='email' else 'google')+' AS manual_source, '+'CAST('+literal(medium)+' AS STRING) AS manual_medium, '+literal('synthetic')+' AS manual_campaign_name, CAST(NULL AS STRING) AS manual_term, CAST(NULL AS STRING) AS manual_content, CAST(NULL AS STRING) AS gclid) AS collected_traffic_source',
        'STRUCT(STRUCT('+literal('newsletter' if medium=='email' else 'google')+' AS source, '+'CAST('+literal(medium)+' AS STRING) AS medium, '+literal('synthetic')+' AS campaign_name) AS cross_channel_campaign) AS session_traffic_source_last_click'])


def emit_connector_tables(connector, datasets, create):
    """Copy the contract tables into the shape a loader writes, plus one deleted
    or archived HubSpot row that the connector mapping must drop."""
    hs, sf = datasets['hubspot'], datasets['salesforce']
    if connector == 'fivetran':
        print(f'''{create} `{hs}.contact` AS
SELECT *, FALSE AS _fivetran_deleted FROM `{hs}.contacts`
UNION ALL
SELECT * REPLACE ('h9' AS id), TRUE FROM `{hs}.contacts` WHERE id = 'h1';''')
        print(f'''{create} `{sf}.lead` AS
SELECT Id AS id, ConvertedContactId AS converted_contact_id, ConvertedOpportunityId AS converted_opportunity_id,
IsConverted AS is_converted, Email AS email, CreatedDate AS created_date,
First_Touch_Source__c AS first_touch_source_c, First_Touch_Medium__c AS first_touch_medium_c,
First_Touch_Campaign__c AS first_touch_campaign_c, Original_Conversion_Id__c AS original_conversion_id_c,
Status AS status, IsDeleted AS is_deleted, GA_Client_ID__c AS ga_client_id_c, FALSE AS _fivetran_deleted
FROM `{sf}.Lead`;''')
        print(f'''{create} `{sf}.opportunity` AS
SELECT Id AS id, AccountId AS account_id, ContactId AS contact_id, Name AS name, StageName AS stage_name,
Amount AS amount, ARR__c AS arr_c, CurrencyIsoCode AS currency_iso_code, IsWon AS is_won, IsClosed AS is_closed,
CreatedDate AS created_date, CloseDate AS close_date, Original_Conversion_Id__c AS original_conversion_id_c,
IsDeleted AS is_deleted, FALSE AS _fivetran_deleted
FROM `{sf}.Opportunity`;''')
    elif connector == 'airbyte':
        props = ('TO_JSON(STRUCT(property_email AS email, property_createdate AS createdate, '
                 'property_hs_analytics_source AS hs_analytics_source, '
                 'property_hs_analytics_source_data_1 AS hs_analytics_source_data_1, '
                 'property_original_conversion_id AS original_conversion_id, property_hs_lead_status AS hs_lead_status, '
                 'property_salesforceleadid AS salesforceleadid, property_salesforcecontactid AS salesforcecontactid, '
                 'property_ga_client_id AS ga_client_id))')
        print(f'''{create} `{hs}.contacts` AS
SELECT id, TIMESTAMP(property_createdate) AS createdAt, {props} AS properties, FALSE AS archived FROM `{hs}.contacts_contract`
UNION ALL
SELECT 'h9', TIMESTAMP(property_createdate), {props}, TRUE FROM `{hs}.contacts_contract` WHERE id = 'h1';''')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project',required=True)
    parser.add_argument('--prefix',default='foco_fixture')
    parser.add_argument('--location',default='US')
    parser.add_argument('--expiration-days',type=int,default=0,help='Set default_table_expiration_days on the fixture datasets (0 = none).')
    parser.add_argument('--replace',action='store_true',help='Use CREATE OR REPLACE TABLE, for a stable demo dataset rebuilt in place.')
    parser.add_argument('--connector',choices=['native','fivetran','airbyte'],default='native',help='Shape the HubSpot and Salesforce tables as this loader writes them.')
    parser.add_argument('--base-date',default='2026-01-01',help='Session day 0 (YYYY-MM-DD). Use a recent date in BigQuery sandbox projects, which drop partitions older than 60 days.')
    args=parser.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9-]{4,61}[a-z0-9]',args.project): parser.error('Invalid project ID')
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,60}',args.prefix): parser.error('Invalid dataset prefix')
    if not re.fullmatch(r'[A-Za-z0-9-]+',args.location): parser.error('Invalid location')
    try: b=date.fromisoformat(args.base_date)
    except ValueError: parser.error('Invalid --base-date; use YYYY-MM-DD')
    if args.expiration_days<0: parser.error('--expiration-days must be >= 0')
    d=lambda n: (b+timedelta(days=n)).isoformat()
    ts=lambda n,hms: d(n)+'T'+hms
    sid=lambda n,hms: int(datetime.fromisoformat(ts(n,hms)).replace(tzinfo=timezone.utc).timestamp())
    create='CREATE OR REPLACE TABLE' if args.replace else 'CREATE TABLE'
    datasets={k:f'{args.project}.{args.prefix}_{k}' for k in ['ga4','hubspot','salesforce']}
    print('-- SYNTHETIC DATA ONLY. '+('Replace mode: rebuilds tables in place; older events_ tables outside the date window are left and ignored.' if args.replace else 'Create-only fixture; reruns fail instead of overwriting tables.'))
    for ds in datasets.values(): print(f'CREATE SCHEMA IF NOT EXISTS `{ds}` OPTIONS(location={literal(args.location)}'+(f', default_table_expiration_days={args.expiration_days}' if args.expiration_days else '')+');')
    bydate={
      d(0).replace('-',''):[event(ts(0,'23:59:00'),'u1',sid(0,'23:59:00'),'conversion-1','email')],
      d(1).replace('-',''):[event(ts(1,'00:01:00'),'u1',sid(0,'23:59:00'),engaged='1'),event(ts(1,'12:00:00'),'u2',sid(1,'12:00:00'),'conversion-2','cpc')],
    }
    # Level 1: user u3 never submits a token; their GA4 client ID is on lead l3.
    bydate[d(0).replace('-','')].append(event(ts(0,'10:00:00'),'u3',sid(0,'10:00:00'),medium='cpc'))
    bydate[d(1).replace('-','')].append(event(ts(1,'15:00:00'),'u3',sid(1,'15:00:00'),medium='email'))
    for day,events in bydate.items():
        print(f'{create} `{datasets["ga4"]}.events_{day}` AS '+ '\nUNION ALL\n'.join(events)+';')
    hubspot_table='contacts_contract' if args.connector=='airbyte' else 'contacts'
    print(f'''{create} `{datasets['hubspot']}.{hubspot_table}` AS
SELECT 'h1' AS id, 'synthetic@example.test' AS property_email, '{ts(0,'23:59:00')}Z' AS property_createdate,
'EMAIL_MARKETING' AS property_hs_analytics_source, 'synthetic' AS property_hs_analytics_source_data_1,
'conversion-1' AS property_original_conversion_id, 'QUALIFIED' AS property_hs_lead_status,
'l1' AS property_salesforceleadid, 'c1' AS property_salesforcecontactid,
CAST(NULL AS STRING) AS property_ga_client_id
UNION ALL
-- Level 0: HubSpot's own original source, linked through Opportunity.ContactId.
SELECT 'h5', 'synthetic5@example.test', '{ts(0,'09:00:00')}Z', 'PAID_SOCIAL', 'synthetic',
CAST(NULL AS STRING), 'QUALIFIED', CAST(NULL AS STRING), 'c5', CAST(NULL AS STRING);''')
    print(f'''{create} `{datasets['salesforce']}.Lead` AS
SELECT 'l1' AS Id, 'c1' AS ConvertedContactId, 'o1' AS ConvertedOpportunityId, TRUE AS IsConverted,
'synthetic@example.test' AS Email, TIMESTAMP('{ts(0,'23:59:00')}Z') AS CreatedDate,
'newsletter' AS First_Touch_Source__c, 'email' AS First_Touch_Medium__c, 'synthetic' AS First_Touch_Campaign__c,
'conversion-1' AS Original_Conversion_Id__c, 'Converted' AS Status, FALSE AS IsDeleted,
CAST(NULL AS STRING) AS GA_Client_ID__c
UNION ALL
-- Level 1: GA4 client ID captured from the _ga cookie, no conversion token.
SELECT 'l3', 'c3', 'o3', TRUE, 'synthetic3@example.test', TIMESTAMP('{ts(1,'15:05:00')}Z'),
CAST(NULL AS STRING), CAST(NULL AS STRING), CAST(NULL AS STRING), CAST(NULL AS STRING), 'Converted', FALSE, 'GA1.1.u3'
UNION ALL
-- Level 0: only the first-touch fields Salesforce recorded.
SELECT 'l4', 'c4', 'o4', TRUE, 'synthetic4@example.test', TIMESTAMP('{ts(1,'09:00:00')}Z'),
'google', 'organic', 'brand', CAST(NULL AS STRING), 'Converted', FALSE, CAST(NULL AS STRING);''')
    print(f'''{create} `{datasets['salesforce']}.Opportunity` AS
SELECT 'o1' AS Id, 'a1' AS AccountId, 'c1' AS ContactId, 'Synthetic linked opportunity' AS Name,
'Closed Won' AS StageName, 1200 AS Amount, 1000 AS ARR__c, 'USD' AS CurrencyIsoCode,
TRUE AS IsWon, TRUE AS IsClosed, TIMESTAMP('{ts(9,'12:00:00')}Z') AS CreatedDate,
DATE('{d(31)}') AS CloseDate, 'conversion-1' AS Original_Conversion_Id__c, FALSE AS IsDeleted
UNION ALL
SELECT 'o2','a2',NULL,'Synthetic unmatched opportunity','Prospecting',500,NULL,'USD',FALSE,FALSE,
TIMESTAMP('{ts(9,'12:00:00')}Z'), DATE('{d(59)}'),NULL,FALSE
UNION ALL
SELECT 'o3','a3',NULL,'Synthetic client-ID opportunity','Qualification',800,NULL,'USD',FALSE,FALSE,
TIMESTAMP('{ts(9,'12:00:00')}Z'), DATE('{d(59)}'),NULL,FALSE
UNION ALL
SELECT 'o4','a4',NULL,'Synthetic CRM-source opportunity','Qualification',300,NULL,'USD',FALSE,FALSE,
TIMESTAMP('{ts(9,'12:00:00')}Z'), DATE('{d(59)}'),NULL,FALSE
UNION ALL
SELECT 'o5','a5','c5','Synthetic HubSpot-source opportunity','Qualification',200,NULL,'USD',FALSE,FALSE,
TIMESTAMP('{ts(9,'12:00:00')}Z'), DATE('{d(59)}'),NULL,FALSE;''')
    emit_connector_tables(args.connector,datasets,create)
    variables={f'{k}_dataset':f'{args.prefix}_{k}' for k in datasets}
    variables['pipetrace_connector']=args.connector
    variables.update(ga4_start_date=d(0),ga4_end_date=d(1),ga4_timezone='UTC',fixture_base_date=d(0))
    print('-- dbt build --vars '+json.dumps(variables))

if __name__=='__main__': main()
