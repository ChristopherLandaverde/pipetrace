"""Dependency-free repository checks. Does not claim to compile dbt or BigQuery SQL."""
from pathlib import Path
import ast
import re
import sys

ROOT=Path(__file__).resolve().parents[1]

def main():
    errors=[]
    models={p.stem:p for p in (ROOT/'models').rglob('*.sql')}
    sources={('ga4','events'),('hubspot','contacts'),('salesforce','leads'),('salesforce','opportunities')}
    graph={name:set() for name in models}
    for p in list(ROOT.rglob('*.sql')):
        sql=p.read_text()
        if sql.count('{{') != sql.count('}}') or sql.count('{%') != sql.count('%}'):
            errors.append(f'Unbalanced Jinja delimiters: {p.relative_to(ROOT)}')
        for ref in re.findall(r"ref\('([^']+)'\)",sql):
            if ref not in models: errors.append(f'Unknown model {ref} in {p.name}')
            if p.stem in graph: graph[p.stem].add(ref)
        for source in re.findall(r"source\('([^']+)', '([^']+)'\)",sql):
            if source not in sources: errors.append(f'Unknown source {source}')
    def visit(node, ancestors):
        if node in ancestors: raise ValueError('Model dependency cycle: '+' -> '.join(ancestors+[node]))
        for child in graph[node]: visit(child,ancestors+[node])
    for node in graph:
        try: visit(node,[])
        except ValueError as exc: errors.append(str(exc))
    for p in (ROOT/'scripts').glob('*.py'):
        try: ast.parse(p.read_text(), filename=p.name)
        except SyntaxError as exc: errors.append(str(exc))
    for name in ['stg_ga4_events','stg_hubspot_contacts','stg_sfdc_leads','stg_sfdc_opportunities','int_ga4_sessions','int_crm_touchpoint_linkage','fct_ga4_sessions_daily','dim_touchpoints','fct_revops_pipeline_attribution']:
        if name not in models: errors.append('Missing PDF model '+name)
    for name in ['extract_event_param','generate_session_key']:
        if not (ROOT/'macros'/f'{name}.sql').exists(): errors.append('Missing PDF macro '+name)
    for p in ROOT.rglob('*'):
        if not p.is_file() or '.git' in p.parts or '__pycache__' in p.parts: continue
        if p.name in ['profiles.yml'] and p.parent != ROOT/'ci': errors.append('Untracked local profile in delivery: '+str(p))
        if p.suffix in ['.pem','.key']: errors.append('Potential key file: '+str(p))
        if p.suffix in ['.md','.sql','.py','.yml','.txt']:
            text=p.read_text()
            if re.search(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',text): errors.append('Private key content: '+str(p))
    if errors:
        print('\n'.join(errors)); return 1
    print(f'PASS: {len(models)} models; SQL references resolve; graph is acyclic; Python parses; no private keys/local profiles found.')
    print('Not a dbt compiler, SQL validator, or comprehensive security scanner.')
    return 0

if __name__=='__main__': sys.exit(main())
