"""Execute actual relational SQL on synthetic SQLite fixtures; not a BigQuery emulator."""
from pathlib import Path
import datetime as dt
import re
import sqlite3
import unittest
ROOT = Path(__file__).resolve().parents[1]

def render_sql(name):
    sql = next((ROOT / 'models').rglob(name + '.sql')).read_text()
    sql = re.sub(r'\{\{ config\(.*?\) \}\}', '', sql, flags=re.S)
    sql = re.sub(r"\{\{ ref\('([^']+)'\) \}\}", r'\1', sql)
    sql = re.sub(r"\{\{ var\('attribution_lookback_days'\) \| int \}\}", '90', sql)
    sql = sql.replace('timestamp_sub(o.created_at, interval 90 day)', "datetime(o.created_at, '-90 day')")
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
        create table stg_sfdc_leads (sfdc_lead_id text, converted_contact_id text, converted_opportunity_id text, original_conversion_id text);
        create table stg_hubspot_contacts (hubspot_contact_id text, sfdc_lead_id text, sfdc_contact_id text, original_conversion_id text);
        create table stg_sfdc_opportunities (opportunity_id text, opportunity_name text, stage_name text, arr real, amount real, pipeline_value real, revenue_basis text, currency_code text, is_won bool, is_closed bool, created_at text, close_date text, original_conversion_id text, primary_contact_id text);
        create table int_ga4_sessions (session_key text, session_start_timestamp text, session_source text, session_medium text, session_campaign text, session_default_channel_grouping text);
        create table int_session_conversion_tokens (session_key text, original_conversion_id text, conversion_timestamp text);
        ''')

    def tearDown(self):
        self.db.close()

    def opportunity(self, oid='o1', token='token1', contact='c1', value=1200, arr=1000):
        self.db.execute('insert into stg_sfdc_opportunities values (?,?,?,?,?,?,?,?,?,?,?,?,?,?)', (oid,'Synthetic deal','Closed Won',arr,value,value,'ARR' if arr is not None else 'Amount','USD',1,1,'2026-01-10 12:00:00','2026-02-01',token,contact))

    def session(self, key='s1', token='token1', at='2026-01-01 12:00:00', conversion_at=None):
        self.db.execute('insert into int_ga4_sessions values (?,?,?,?,?,?)',(key,at,'google','cpc','synthetic','Paid Search'))
        self.db.execute('insert into int_session_conversion_tokens values (?,?,?)',(key,token,conversion_at or at))

    def build(self):
        for name in ('int_crm_touchpoint_linkage','fct_revops_pipeline_attribution','fct_pipeline_attribution_daily'):
            self.db.execute('create table '+name+' as '+render_sql(name))
        return [dict(r) for r in self.db.execute('select * from fct_revops_pipeline_attribution order by opportunity_id, session_key')]

    def test_duplicate_crm_paths_do_not_multiply_revenue(self):
        self.opportunity(); self.session()
        self.db.execute("insert into stg_sfdc_leads values ('l1','c1','o1','token1')")
        self.db.executemany('insert into stg_hubspot_contacts values (?,?,?,?)',[('h1','l1','c1','token1'),('h2','l1','c1','token1')])
        rows=self.build()
        self.assertEqual(len(rows),1)
        self.assertEqual(rows[0]['match_method'],'opportunity_token')
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
        self.db.execute("insert into stg_sfdc_leads values ('l1',null,'o1','token1')")
        row=self.build()[0]
        self.assertEqual(row['session_key'],'s1')
        self.assertEqual(row['match_method'],'converted_opportunity')

    def test_hubspot_lead_id_without_email(self):
        self.opportunity(token=None,contact=None); self.session()
        self.db.execute("insert into stg_sfdc_leads values ('l1',null,'o1',null)")
        self.db.execute("insert into stg_hubspot_contacts values ('h1','l1',null,'token1')")
        self.assertEqual(self.build()[0]['match_method'],'hubspot_lead')

    def test_multiple_tokens_one_session_deduplicated(self):
        self.opportunity(); self.session()
        self.db.execute("insert into int_session_conversion_tokens values ('s1','token2','2026-01-01 13:00:00')")
        self.db.execute("insert into stg_sfdc_leads values ('l1','c1','o1','token2')")
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

if __name__=='__main__':
    unittest.main(verbosity=2)
