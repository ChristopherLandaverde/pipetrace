"""Execute actual relational SQL on synthetic SQLite fixtures; not a BigQuery emulator."""
from pathlib import Path
import datetime as dt
import re
import sqlite3
import unittest
ROOT = Path(__file__).resolve().parents[1]

MACRO_RE = re.compile(r"\{% macro (\w+)\(([^)]*)\) -%\}(.*?)\{%- endmacro %\}", re.S)
MACROS = {}
for path in (ROOT / 'macros').glob('*.sql'):
    for m in MACRO_RE.finditer(path.read_text()):
        MACROS[m.group(1)] = ([a.split('=')[0].strip() for a in m.group(2).split(',') if a.strip()], m.group(3))
# Only these plain-SQL macros are expanded; anything else must stay out of the
# models rendered here, or render_sql fails loudly.
LOCAL_MACROS = ('pipetrace_channel_grouping', 'pipetrace_hubspot_source_channel')
FLAG_RE = re.compile(r"\{\{ pipetrace_flag\('(\w+)'\) \}\}")
VARS = {'attribution_lookback_days': '90', 'enable_ga_client_id_matching': 'true', 'enable_crm_source_fallback': 'true'}

def expand_macro(match):
    name, raw_args = match.group(1), match.group(2)
    params, body = MACROS[name]
    args = [a.strip().strip("'") for a in raw_args.split("',")]
    for param, arg in zip(params, args):
        body = body.replace('{{ ' + param + ' }}', arg.strip("'"))
    return body.strip()

def render_sql(name, overrides=None):
    sql = next((ROOT / 'models').rglob(name + '.sql')).read_text()
    sql = re.sub(r'\{\{ config\(.*?\) \}\}', '', sql, flags=re.S)
    sql = re.sub(r"\{\{ ref\('([^']+)'\) \}\}", r'\1', sql)
    values = {**VARS, **(overrides or {})}
    sql = re.sub(r"\{\{ var\('(\w+)'\)(?: \| int)? \}\}", lambda m: values[m.group(1)], sql)
    sql = FLAG_RE.sub(lambda m: values[m.group(1)], sql)
    sql = re.sub(r"\{\{ (" + '|'.join(LOCAL_MACROS) + r")\((.*?)\) \}\}", expand_macro, sql)
    sql = re.sub(r'timestamp_sub\((\w+)\.created_at, interval (\d+) day\)', r"datetime(\1.created_at, '-\2 day')", sql)
    sql = sql.replace('timestamp_diff(opp_created_at, session_start_timestamp, day)', 'days_between(opp_created_at, session_start_timestamp)')
    if '{{' in sql or '{%' in sql:
        raise ValueError('Unrendered Jinja: ' + name)
    return sql

class AttributionAcceptance(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(':memory:')
        self.db.row_factory = sqlite3.Row
        self.db.create_function('days_between', 2, lambda end, start: None if start is None else int((dt.datetime.fromisoformat(end)-dt.datetime.fromisoformat(start)).total_seconds()/86400))
        self.db.executescript('''
        create table stg_sfdc_leads (sfdc_lead_id text, converted_contact_id text, converted_opportunity_id text, original_conversion_id text, ga_client_id text, ft_source text, ft_medium text, ft_campaign text, created_at text);
        create table stg_hubspot_contacts (hubspot_contact_id text, sfdc_lead_id text, sfdc_contact_id text, original_conversion_id text, ga_client_id text, original_source text, created_at text);
        create table stg_sfdc_opportunities (opportunity_id text, opportunity_name text, stage_name text, arr real, amount real, pipeline_value real, revenue_basis text, currency_code text, is_won bool, is_closed bool, created_at text, close_date text, original_conversion_id text, primary_contact_id text, ga_client_id text);
        create table int_ga4_sessions (session_key text, user_pseudo_id text, session_start_timestamp text, session_source text, session_medium text, session_campaign text, session_default_channel_grouping text);
        create table int_session_conversion_tokens (session_key text, original_conversion_id text, conversion_timestamp text);
        ''')

    def tearDown(self):
        self.db.close()

    def opportunity(self, oid='o1', token='token1', contact='c1', value=1200, arr=1000):
        self.db.execute('insert into stg_sfdc_opportunities values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)', (oid,'Synthetic deal','Closed Won',arr,value,value,'ARR' if arr is not None else 'Amount','USD',1,1,'2026-01-10 12:00:00','2026-02-01',token,contact,None))

    def session(self, key='s1', token='token1', at='2026-01-01 12:00:00', conversion_at=None, user='u1'):
        self.db.execute('insert into int_ga4_sessions values (?,?,?,?,?,?,?)',(key,user,at,'google','cpc','synthetic','Paid Search'))
        if token is not None:
            self.db.execute('insert into int_session_conversion_tokens values (?,?,?)',(key,token,conversion_at or at))

    def lead(self, lid='l1', contact=None, opp='o1', token=None, client=None, source=None, medium=None, campaign=None, created='2026-01-05 12:00:00'):
        self.db.execute('insert into stg_sfdc_leads values (?,?,?,?,?,?,?,?,?)',(lid,contact,opp,token,client,source,medium,campaign,created))

    def contact(self, hid='h1', lead=None, sfdc_contact=None, token=None, client=None, source=None, created='2026-01-05 12:00:00'):
        self.db.execute('insert into stg_hubspot_contacts values (?,?,?,?,?,?,?)',(hid,lead,sfdc_contact,token,client,source,created))

    def build(self, **overrides):
        for name in ('int_opportunity_identity_paths','int_crm_touchpoint_linkage','fct_revops_pipeline_attribution','fct_pipeline_attribution_daily'):
            self.db.execute('create table '+name+' as '+render_sql(name, overrides))
        return [dict(r) for r in self.db.execute('select * from fct_revops_pipeline_attribution order by opportunity_id, session_key')]

    def test_duplicate_crm_paths_do_not_multiply_revenue(self):
        self.opportunity(); self.session()
        self.lead(contact='c1',token='token1')
        self.contact('h1','l1','c1','token1'); self.contact('h2','l1','c1','token1')
        rows=self.build()
        self.assertEqual(len(rows),1)
        self.assertEqual(rows[0]['match_method'],'opportunity_record')
        self.assertEqual(rows[0]['linear_pipeline_value'],1200)

    def test_two_sessions_allocate_once(self):
        self.opportunity(); self.session(); self.session('s2',at='2026-01-02 12:00:00')
        rows=self.build()
        self.assertEqual([r['first_touch_weight'] for r in rows],[1,0])
        self.assertEqual([r['linear_touch_weight'] for r in rows],[.5,.5])
        for key,expected in [('first_touch_pipeline_value',1200),('linear_pipeline_value',1200),('linear_arr',1000)]:
            self.assertEqual(sum(r[key] for r in rows),expected)

    def test_unmatched_null_tokens_remain_visible(self):
        self.opportunity(token=None,contact=None); self.session(token='other')
        row=self.build()[0]
        self.assertIsNone(row['session_key'])
        self.assertEqual(row['channel_grouping'],'Unattributed')
        self.assertEqual(row['linear_touch_weight'],1)
        self.assertEqual(row['linear_won_value'],1200)

    def test_future_session_excluded(self):
        self.opportunity(); self.session(at='2026-01-11 12:00:00')
        self.assertIsNone(self.build()[0]['session_key'])

    def test_future_conversion_excluded(self):
        self.opportunity(); self.session(conversion_at='2026-01-11 12:00:00')
        self.assertIsNone(self.build()[0]['session_key'])

    def test_outside_lookback_excluded(self):
        self.opportunity(); self.session(at='2025-01-01 12:00:00')
        self.assertIsNone(self.build()[0]['session_key'])

    def test_converted_opportunity_without_primary_contact(self):
        self.opportunity(token=None,contact=None); self.session()
        self.lead(token='token1')
        row=self.build()[0]
        self.assertEqual(row['session_key'],'s1')
        self.assertEqual(row['match_method'],'converted_opportunity')

    def test_hubspot_lead_id_without_email(self):
        self.opportunity(token=None,contact=None); self.session()
        self.lead(); self.contact(lead='l1',token='token1')
        self.assertEqual(self.build()[0]['match_method'],'hubspot_lead')

    def test_multiple_tokens_one_session_deduplicated(self):
        self.opportunity(); self.session()
        self.db.execute("insert into int_session_conversion_tokens values ('s1','token2','2026-01-01 13:00:00')")
        self.lead(contact='c1',token='token2')
        self.assertEqual(len(self.build()),1)

    def test_tied_sessions_one_first_touch(self):
        self.opportunity(); self.session('b'); self.session('a')
        self.assertEqual([r['first_touch_weight'] for r in self.build()],[1,0])

    def test_missing_arr_not_fabricated(self):
        self.opportunity(arr=None); self.session()
        row=self.build()[0]
        self.assertIsNone(row['opp_arr']); self.assertIsNone(row['linear_arr'])
        self.assertEqual(row['revenue_basis'],'Amount')
        self.assertEqual(row['linear_pipeline_value'],1200)

    def test_unknown_value_stays_null(self):
        self.opportunity(value=None,arr=None)
        self.assertIsNone(self.build()[0]['linear_pipeline_value'])

    def test_daily_currency_separation(self):
        self.opportunity(); self.opportunity('o2'); self.session()
        self.db.execute("update stg_sfdc_opportunities set currency_code='EUR' where opportunity_id='o2'")
        self.build()
        rows=self.db.execute('select currency_code,linear_pipeline_value from fct_pipeline_attribution_daily order by currency_code').fetchall()
        self.assertEqual([tuple(r) for r in rows],[('EUR',1200),('USD',1200)])

    def test_relational_integrity_tests_execute(self):
        self.opportunity(); self.session(); self.opportunity('o2',token=None)
        self.build()
        for name in ['assert_attribution_weights','assert_opportunity_coverage','assert_attribution_grain','assert_pipeline_reconciles','assert_no_future_touchpoints']:
            sql=(ROOT/'tests'/f'{name}.sql').read_text()
            sql=re.sub(r"\{\{ ref\('([^']+)'\) \}\}",r'\1',sql)
            with self.subTest(name=name):
                self.assertEqual(self.db.execute(sql).fetchall(),[])

    # Attribution levels: 2 conversion token, 1 GA4 client ID, 0 CRM source.
    def test_ga_client_id_level_credits_every_eligible_session(self):
        self.opportunity(token=None,contact=None)
        self.lead(client='u9')
        self.session('s1',token=None,user='u9'); self.session('s2',token=None,user='u9',at='2026-01-03 12:00:00')
        self.session('s3',token=None,user='u9',at='2026-01-11 12:00:00')  # after creation
        self.session('s4',token=None,user='other')
        rows=self.build()
        self.assertEqual([r['session_key'] for r in rows],['s1','s2'])
        self.assertEqual({r['attribution_basis'] for r in rows},{'ga_client_id'})
        self.assertEqual({r['attribution_level'] for r in rows},{1})
        self.assertEqual(sum(r['linear_pipeline_value'] for r in rows),1200)
        self.assertEqual(sum(r['first_touch_weight'] for r in rows),1)

    def test_token_level_wins_over_client_id(self):
        self.opportunity(contact=None); self.session('s1')
        self.lead(client='u9'); self.session('s2',token=None,user='u9')
        rows=self.build()
        self.assertEqual([(r['session_key'],r['attribution_basis']) for r in rows],[('s1','conversion_token')])

    def test_client_id_outside_lookback_falls_through(self):
        self.opportunity(token=None,contact=None)
        self.lead(client='u9',medium='organic',source='google')
        self.session('s1',token=None,user='u9',at='2025-01-01 12:00:00')
        row=self.build()[0]
        self.assertEqual(row['attribution_basis'],'crm_source')

    def test_crm_source_level_from_salesforce_first_touch(self):
        self.opportunity(token=None,contact=None)
        self.lead(source='google',medium='organic',campaign='brand')
        rows=self.build()
        self.assertEqual(len(rows),1)
        row=rows[0]
        self.assertIsNone(row['session_key'])
        self.assertEqual((row['attribution_level'],row['attribution_basis'],row['match_method']),(0,'crm_source','salesforce_lead_source'))
        self.assertEqual(row['channel_grouping'],'Organic Search')
        self.assertEqual((row['session_source'],row['session_medium'],row['session_campaign']),('google','organic','brand'))
        self.assertEqual((row['first_touch_weight'],row['linear_pipeline_value']),(1,1200))

    def test_crm_source_level_from_hubspot_original_source(self):
        self.opportunity(token=None,contact='c5')
        self.contact('h5',sfdc_contact='c5',source='PAID_SOCIAL')
        row=self.build()[0]
        self.assertEqual((row['attribution_basis'],row['match_method'],row['channel_grouping']),('crm_source','hubspot_source','Paid Social'))

    def test_salesforce_first_touch_ranks_above_hubspot(self):
        self.opportunity(token=None,contact='c5')
        self.lead(medium='email',source='newsletter')
        self.contact('h5',sfdc_contact='c5',source='PAID_SOCIAL')
        rows=self.build()
        self.assertEqual([(r['match_method'],r['channel_grouping']) for r in rows],[('salesforce_lead_source','Email')])

    def test_session_level_suppresses_crm_source(self):
        self.opportunity(contact=None); self.session()
        self.lead(medium='organic',source='google')
        rows=self.build()
        self.assertEqual([r['attribution_basis'] for r in rows],['conversion_token'])
        self.assertEqual(rows[0]['channel_grouping'],'Paid Search')

    def test_crm_source_after_opportunity_creation_ignored(self):
        self.opportunity(token=None,contact=None)
        self.lead(medium='organic',source='google',created='2026-01-11 12:00:00')
        self.assertEqual(self.build()[0]['attribution_basis'],'unattributed')

    def test_crm_source_ties_break_by_record(self):
        self.opportunity(token=None,contact='c5')
        self.contact('h9',sfdc_contact='c5',source='PAID_SOCIAL',created='2026-01-02 12:00:00')
        self.contact('h8',sfdc_contact='c5',source='ORGANIC_SEARCH',created='2026-01-02 12:00:00')
        self.assertEqual(self.build()[0]['channel_grouping'],'Organic Search')

    def test_levels_can_be_switched_off(self):
        self.opportunity(token=None,contact=None)
        self.lead(client='u9',medium='organic',source='google'); self.session('s1',token=None,user='u9')
        self.assertEqual(self.build(enable_ga_client_id_matching='false')[0]['attribution_basis'],'crm_source')

    def test_crm_fallback_can_be_switched_off(self):
        self.opportunity(token=None,contact=None)
        self.lead(medium='organic',source='google')
        row=self.build(enable_crm_source_fallback='false')[0]
        self.assertEqual((row['attribution_basis'],row['channel_grouping']),('unattributed','Unattributed'))
        self.assertIsNone(row['attribution_level'])

    def test_daily_keeps_attribution_basis_separate(self):
        self.opportunity(); self.session()
        self.opportunity('o2',token=None,contact=None)
        self.lead('l2',opp='o2',medium='cpc',source='google')
        self.build()
        rows=self.db.execute('select channel_grouping,attribution_basis,linear_pipeline_value from fct_pipeline_attribution_daily order by attribution_basis').fetchall()
        self.assertEqual([tuple(r) for r in rows],[('Paid Search','conversion_token',1200),('Paid Search','crm_source',1200)])

    def test_relational_integrity_tests_execute_across_levels(self):
        self.opportunity(); self.session()
        self.opportunity('o2',token=None,contact=None); self.lead('l2',opp='o2',client='u9')
        self.session('s9',token=None,user='u9'); self.session('s10',token=None,user='u9',at='2026-01-05 12:00:00')
        self.opportunity('o3',token=None,contact=None); self.lead('l3',opp='o3',medium='organic',source='google')
        self.opportunity('o4',token=None,contact=None)
        rows=self.build()
        self.assertEqual(sorted({(r['opportunity_id'],r['attribution_basis']) for r in rows}),
            [('o1','conversion_token'),('o2','ga_client_id'),('o3','crm_source'),('o4','unattributed')])
        for name in ['assert_attribution_weights','assert_opportunity_coverage','assert_attribution_grain','assert_pipeline_reconciles','assert_no_future_touchpoints']:
            sql=(ROOT/'tests'/f'{name}.sql').read_text()
            sql=re.sub(r"\{\{ ref\('([^']+)'\) \}\}",r'\1',sql)
            with self.subTest(name=name):
                self.assertEqual(self.db.execute(sql).fetchall(),[])

if __name__=='__main__':
    unittest.main(verbosity=2)
