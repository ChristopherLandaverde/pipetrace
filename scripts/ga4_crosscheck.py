"""Cross-check GA4's own session counts against PipeTrace's fct_ga4_sessions_daily.

GA4's Data API and the BigQuery export never match exactly: the API applies
thresholding and counts sessions differently. This flags drift beyond a
tolerance, per day. By default it prints only percentage differences, never
traffic counts, because CI logs on a public repository are public.

Usage:
  python scripts/ga4_crosscheck.py --property 123456789 --project P --dataset D \
      --start 2026-11-01 --end 2026-11-14 [--tolerance 0.05] [--min-sessions 20] [--show-counts]

Uses Application Default Credentials with analytics.readonly and BigQuery read
access. Read-only on both sides. GA4 reports dates in the property's timezone;
set PipeTrace's ga4_timezone to match, or day boundaries will drift.
"""
import argparse
import re
import sys
from datetime import date

DATA_API = 'https://analyticsdata.googleapis.com/v1beta'


def compare(ga4, warehouse, tolerance=0.05, min_sessions=20):
    """Compare per-day session counts. Returns a list of dicts, one per day.

    A day is 'skipped' when both sides are under min_sessions, since small
    counts make percentages meaningless. Otherwise drift is |wh - ga4| / ga4,
    and a day fails when it exceeds the tolerance or one side is missing.
    """
    out = []
    for d in sorted(set(ga4) | set(warehouse)):
        g, w = ga4.get(d), warehouse.get(d)
        # GA4's API omits zero-session days; treat a missing quiet day as 0.
        if g is None and (w or 0) < min_sessions:
            g = 0
        if w is None and (g or 0) < min_sessions:
            w = 0
        if g is None or w is None:
            out.append({'date': d, 'status': 'fail', 'drift': None, 'ga4': g, 'warehouse': w,
                        'reason': 'missing in ' + ('GA4' if g is None else 'warehouse')})
            continue
        if g < min_sessions and w < min_sessions:
            out.append({'date': d, 'status': 'skipped', 'drift': None, 'ga4': g, 'warehouse': w,
                        'reason': f'under {min_sessions} sessions'})
            continue
        drift = abs(w - g) / g if g else 1.0
        out.append({'date': d, 'status': 'pass' if drift <= tolerance else 'fail', 'drift': drift,
                    'ga4': g, 'warehouse': w, 'reason': ''})
    return out


def ga4_sessions(property_id, start, end):
    import google.auth
    from google.auth.transport.requests import AuthorizedSession
    creds, _ = google.auth.default(scopes=['https://www.googleapis.com/auth/analytics.readonly'])
    body = {'dateRanges': [{'startDate': start, 'endDate': end}],
            'dimensions': [{'name': 'date'}], 'metrics': [{'name': 'sessions'}], 'limit': 1000}
    r = AuthorizedSession(creds).post(f'{DATA_API}/properties/{property_id}:runReport', json=body, timeout=60)
    if not r.ok:
        raise SystemExit(f'× BROKEN  GA4 Data API HTTP {r.status_code}: {r.text[:300]}')
    rows = r.json().get('rows', [])
    return {date(int(v[:4]), int(v[4:6]), int(v[6:])): int(row['metricValues'][0]['value'])
            for row in rows for v in [row['dimensionValues'][0]['value']]}


def warehouse_sessions(project, dataset, start, end):
    from google.cloud import bigquery
    sql = (f'SELECT session_date, SUM(total_sessions) AS sessions '
           f'FROM `{project}.{dataset}.fct_ga4_sessions_daily` '
           f'WHERE session_date BETWEEN @start AND @end GROUP BY 1')
    cfg = bigquery.QueryJobConfig(
        query_parameters=[bigquery.ScalarQueryParameter('start', 'DATE', start),
                          bigquery.ScalarQueryParameter('end', 'DATE', end)],
        maximum_bytes_billed=1_000_000_000)
    rows = bigquery.Client(project=project).query(sql, job_config=cfg).result()
    return {r['session_date']: int(r['sessions']) for r in rows}


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--property', required=True)
    p.add_argument('--project', required=True)
    p.add_argument('--dataset', required=True)
    p.add_argument('--start', required=True)
    p.add_argument('--end', required=True)
    p.add_argument('--tolerance', type=float, default=0.05)
    p.add_argument('--min-sessions', type=int, default=20)
    p.add_argument('--show-counts', action='store_true', help='Also print raw counts (keep off in public CI)')
    a = p.parse_args(argv)
    if not re.fullmatch(r'\d{6,12}', a.property):
        p.error('Invalid GA4 property ID')
    if not re.fullmatch(r'[a-z][a-z0-9-]{4,61}[a-z0-9]', a.project):
        p.error('Invalid project ID')
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]{0,1023}', a.dataset):
        p.error('Invalid dataset ID')
    try:
        start, end = date.fromisoformat(a.start), date.fromisoformat(a.end)
    except ValueError:
        p.error('Dates must be YYYY-MM-DD')
    if start > end:
        p.error('--start must be on or before --end')
    results = compare(ga4_sessions(a.property, a.start, a.end),
                      warehouse_sessions(a.project, a.dataset, a.start, a.end),
                      a.tolerance, a.min_sessions)
    failed = [r for r in results if r['status'] == 'fail']
    for r in results:
        drift = '' if r['drift'] is None else f'{r["drift"]:.1%}'
        counts = f'  ga4={r["ga4"]} warehouse={r["warehouse"]}' if a.show_counts else ''
        glyph = {'pass': '✓', 'fail': '×', 'skipped': '·'}[r['status']]
        print(f'{glyph} {r["date"]}  {r["status"]:7} {drift:>6} {r["reason"]}{counts}')
    checked = sum(r['status'] != 'skipped' for r in results)
    if failed:
        print(f'× BROKEN  {len(failed)} of {checked} days drift beyond {a.tolerance:.0%}')
        return 1
    print(f'✓ VERIFIED  {checked} days within {a.tolerance:.0%} of GA4')
    return 0


if __name__ == '__main__':
    sys.exit(main())
