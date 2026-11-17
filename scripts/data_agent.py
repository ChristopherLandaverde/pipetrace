"""Create or update PipeTrace's BigQuery data agent (Conversational Analytics API).

Reads agents/pipetrace-pipeline-agent.json, points it at one dataset of
PipeTrace marts, and creates the agent or updates it in place. Read-only on
data: the agent only gets table references and instructions.

Usage:
  python scripts/data_agent.py --project P --dataset D [--location global] [--dry-run]

--dry-run prints the request body and makes no network call. Real runs use
Application Default Credentials (the CI service account via Workload Identity
Federation). The project needs billing, the Gemini Data Analytics API, and the
data agent IAM roles listed in docs/agents.md.
"""
import argparse
import json
import re
import sys
from pathlib import Path

API = 'https://geminidataanalytics.googleapis.com/v1beta'
CONFIG = Path(__file__).resolve().parent.parent / 'agents' / 'pipetrace-pipeline-agent.json'
NAME_RE = re.compile(r'[a-z][a-z0-9-]{4,61}[a-z0-9]')
DATASET_RE = re.compile(r'[A-Za-z_][A-Za-z0-9_]{0,1023}')


def build_agent(config, project, dataset):
    """Return the DataAgent resource body for one project and dataset."""
    tables = [{'projectId': project, 'datasetId': dataset, 'tableId': t} for t in config['tables']]
    examples = [
        {'naturalLanguageQuestion': q['naturalLanguageQuestion'],
         'sqlQuery': q['sqlQuery'].format(project=project, dataset=dataset)}
        for q in config['exampleQueries']
    ]
    context = {
        'systemInstruction': config['systemInstruction'],
        'datasourceReferences': {'bq': {'tableReferences': tables}},
        'exampleQueries': examples,
    }
    return {
        'displayName': config['displayName'],
        'description': config['description'],
        'dataAnalyticsAgent': {'stagingContext': context, 'publishedContext': context},
    }


def _session():
    import google.auth
    from google.auth.transport.requests import AuthorizedSession
    creds, _ = google.auth.default(scopes=['https://www.googleapis.com/auth/cloud-platform'])
    return AuthorizedSession(creds)


def upsert(project, location, agent_id, body):
    parent = f'projects/{project}/locations/{location}'
    name = f'{parent}/dataAgents/{agent_id}'
    s = _session()
    got = s.get(f'{API}/{name}')
    if got.status_code == 404:
        r = s.post(f'{API}/{parent}/dataAgents', params={'dataAgentId': agent_id}, json=body)
        action = 'created'
    elif got.ok:
        r = s.patch(f'{API}/{name}', params={'updateMask': 'displayName,description,dataAnalyticsAgent'}, json=body)
        action = 'updated'
    else:
        raise SystemExit(f'× BROKEN  could not read {name}: HTTP {got.status_code} {got.text[:300]}')
    if not r.ok:
        raise SystemExit(f'× BROKEN  {action} failed: HTTP {r.status_code} {r.text[:500]}')
    return action, name


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--project', required=True)
    p.add_argument('--dataset', required=True, help='Dataset holding the PipeTrace marts, e.g. pipetrace_demo_models')
    p.add_argument('--location', default='global')
    p.add_argument('--dry-run', action='store_true')
    a = p.parse_args(argv)
    if not NAME_RE.fullmatch(a.project):
        p.error('Invalid project ID')
    if not DATASET_RE.fullmatch(a.dataset):
        p.error('Invalid dataset ID')
    config = json.loads(CONFIG.read_text())
    body = build_agent(config, a.project, a.dataset)
    if a.dry_run:
        json.dump(body, sys.stdout, indent=2)
        print()
        return 0
    action, name = upsert(a.project, a.location, config['dataAgentId'], body)
    print(f'✓ VERIFIED  data agent {action}: {name} over {a.project}.{a.dataset}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
