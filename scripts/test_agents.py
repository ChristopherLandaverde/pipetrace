"""Offline tests for scripts/data_agent.py and scripts/ga4_crosscheck.py. Standard library only."""
import io
import json
import sys
import unittest
from contextlib import redirect_stdout
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import data_agent  # noqa: E402
import ga4_crosscheck  # noqa: E402


class DataAgentConfig(unittest.TestCase):
    def setUp(self):
        self.config = json.loads(data_agent.CONFIG.read_text())
        self.body = data_agent.build_agent(self.config, 'demo-proj', 'pipetrace_demo_models')

    def test_only_governed_marts(self):
        refs = self.body['dataAnalyticsAgent']['publishedContext']['datasourceReferences']['bq']['tableReferences']
        self.assertEqual({r['tableId'] for r in refs}, {'pipetrace_fct_pipeline_attribution_daily', 'pipetrace_fct_ga4_sessions_daily'})
        self.assertTrue(all(r['projectId'] == 'demo-proj' and r['datasetId'] == 'pipetrace_demo_models' for r in refs))

    def test_staging_and_published_match(self):
        a = self.body['dataAnalyticsAgent']
        self.assertEqual(a['stagingContext'], a['publishedContext'])

    def test_instructions_carry_the_guardrails(self):
        text = self.config['systemInstruction']
        for rule in ('currency_code and revenue_basis', 'Unattributed', 'never as\n  causation', 'unique_visitors cannot be summed'):
            self.assertIn(rule, text)

    def test_example_sql_is_bound_and_safe(self):
        for q in self.body['dataAnalyticsAgent']['publishedContext']['exampleQueries']:
            sql = q['sqlQuery']
            self.assertIn('`demo-proj.pipetrace_demo_models.', sql)
            self.assertNotIn('{', sql)
            self.assertNotIn('opp_pipeline_value', sql)
            self.assertTrue(sql.lstrip().upper().startswith('SELECT'))
            if 'pipeline_value' in sql:
                self.assertIn('currency_code', sql)
                self.assertIn('revenue_basis', sql)

    def test_agent_id_is_valid(self):
        import re
        self.assertRegex(self.config['dataAgentId'], re.compile(r'^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$'))

    def test_dry_run_prints_body_without_network(self):
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = data_agent.main(['--project', 'demo-proj', '--dataset', 'pipetrace_demo_models', '--dry-run'])
        self.assertEqual(rc, 0)
        self.assertEqual(json.loads(buf.getvalue())['displayName'], 'PipeTrace pipeline agent')

    def test_rejects_bad_ids(self):
        with self.assertRaises(SystemExit):
            data_agent.main(['--project', 'Bad Project', '--dataset', 'x', '--dry-run'])


class CrossCheck(unittest.TestCase):
    D1, D2, D3 = date(2026, 11, 1), date(2026, 11, 2), date(2026, 11, 3)

    def test_within_tolerance_passes(self):
        r = ga4_crosscheck.compare({self.D1: 100}, {self.D1: 104}, 0.05)
        self.assertEqual(r[0]['status'], 'pass')
        self.assertAlmostEqual(r[0]['drift'], 0.04)

    def test_beyond_tolerance_fails(self):
        self.assertEqual(ga4_crosscheck.compare({self.D1: 100}, {self.D1: 120}, 0.05)[0]['status'], 'fail')

    def test_missing_day_fails(self):
        r = ga4_crosscheck.compare({self.D1: 100, self.D2: 90}, {self.D1: 100}, 0.05)
        self.assertEqual([x['status'] for x in r], ['pass', 'fail'])
        self.assertIn('warehouse', r[1]['reason'])

    def test_quiet_day_missing_from_ga4_is_not_a_failure(self):
        r = ga4_crosscheck.compare({}, {self.D1: 2}, 0.05, 20)
        self.assertEqual(r[0]['status'], 'skipped')

    def test_rejects_unsafe_dataset_name(self):
        with self.assertRaises(SystemExit):
            ga4_crosscheck.main(['--property', '123456', '--project', 'demo-proj', '--dataset', 'x`; DROP',
                                 '--start', '2026-11-01', '--end', '2026-11-02'])

    def test_rejects_reversed_dates(self):
        with self.assertRaises(SystemExit):
            ga4_crosscheck.main(['--property', '123456', '--project', 'demo-proj', '--dataset', 'ok_ds',
                                 '--start', '2026-11-05', '--end', '2026-11-02'])

    def test_small_days_are_skipped(self):
        self.assertEqual(ga4_crosscheck.compare({self.D3: 3}, {self.D3: 9}, 0.05, 20)[0]['status'], 'skipped')

    def test_counts_hidden_by_default(self):
        self.assertNotIn('show_counts', ga4_crosscheck.main.__defaults__ or ())
        src = Path(ga4_crosscheck.__file__).read_text()
        self.assertIn("'--show-counts', action='store_true'", src)


if __name__ == '__main__':
    unittest.main(verbosity=1)
