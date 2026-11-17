"""Emit synthetic BigQuery raw tables. Never executes SQL or connects to a service.

Use a disposable development project. Existing fixture tables are not overwritten.
"""
import argparse
import json
import re
from datetime import datetime, timezone


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


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project',required=True)
    parser.add_argument('--prefix',default='foco_fixture')
    parser.add_argument('--location',default='US')
    args=parser.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9-]{4,61}[a-z0-9]',args.project): parser.error('Invalid project ID')
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,60}',args.prefix): parser.error('Invalid dataset prefix')
    if not re.fullmatch(r'[A-Za-z0-9-]+',args.location): parser.error('Invalid location')
    datasets={k:f'{args.project}.{args.prefix}_{k}' for k in ['ga4','hubspot','salesforce']}
    print('-- SYNTHETIC DATA ONLY. Create-only fixture; reruns fail instead of overwriting tables.')
    for ds in datasets.values(): print(f'CREATE SCHEMA IF NOT EXISTS `{ds}` OPTIONS(location={literal(args.location)});')
    bydate={
      '20260101':[event('2026-01-01T23:59:00','u1',1767311940,'conversion-1','email')],
      '20260102':[event('2026-01-02T00:01:00','u1',1767311940,engaged='1'),event('2026-01-02T12:00:00','u2',1767355200,'conversion-2','cpc')],
    }
    for day,events in bydate.items():
        print(f'CREATE TABLE `{datasets["ga4"]}.events_{day}` AS '+ '\nUNION ALL\n'.join(events)+';')
    print(f'''CREATE TABLE `{datasets['hubspot']}.contacts` AS
SELECT 'h1' AS id, 'synthetic@example.test' AS property_email, '2026-01-01T23:59:00Z' AS property_createdate,
'EMAIL_MARKETING' AS property_hs_analytics_source, 'synthetic' AS property_hs_analytics_source_data_1,
'conversion-1' AS property_original_conversion_id, 'QUALIFIED' AS property_hs_lead_status,
'l1' AS property_salesforceleadid, 'c1' AS property_salesforcecontactid;''')
    print(f'''CREATE TABLE `{datasets['salesforce']}.Lead` AS
SELECT 'l1' AS Id, 'c1' AS ConvertedContactId, 'o1' AS ConvertedOpportunityId, TRUE AS IsConverted,
'synthetic@example.test' AS Email, TIMESTAMP('2026-01-01T23:59:00Z') AS CreatedDate,
'newsletter' AS First_Touch_Source__c, 'email' AS First_Touch_Medium__c, 'synthetic' AS First_Touch_Campaign__c,
'conversion-1' AS Original_Conversion_Id__c, 'Converted' AS Status, FALSE AS IsDeleted;''')
    print(f'''CREATE TABLE `{datasets['salesforce']}.Opportunity` AS
SELECT 'o1' AS Id, 'a1' AS AccountId, 'c1' AS ContactId, 'Synthetic linked opportunity' AS Name,
'Closed Won' AS StageName, 1200 AS Amount, 1000 AS ARR__c, 'USD' AS CurrencyIsoCode,
TRUE AS IsWon, TRUE AS IsClosed, TIMESTAMP('2026-01-10T12:00:00Z') AS CreatedDate,
DATE('2026-02-01') AS CloseDate, 'conversion-1' AS Original_Conversion_Id__c, FALSE AS IsDeleted
UNION ALL
SELECT 'o2','a2',NULL,'Synthetic unmatched opportunity','Prospecting',500,NULL,'USD',FALSE,FALSE,
TIMESTAMP('2026-01-10T12:00:00Z'), DATE('2026-03-01'),NULL,FALSE;''')
    variables={f'{k}_dataset':f'{args.prefix}_{k}' for k in datasets}
    variables.update(ga4_start_date='2026-01-01',ga4_end_date='2026-01-02',ga4_timezone='UTC')
    print('-- dbt build --vars '+json.dumps(variables))

if __name__=='__main__': main()
