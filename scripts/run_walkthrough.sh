#!/usr/bin/env bash
# Synthetic walkthrough / no client data.
# Creates new fixture datasets in a development BigQuery project, then runs
# dbt build (models + unit + data tests) against them.
# Usage: bash scripts/run_walkthrough.sh <dev-project-id> [location]
set -euo pipefail

PROJECT="${1:?usage: bash scripts/run_walkthrough.sh <dev-project-id> [location]}"
LOCATION="${2:-US}"
PREFIX="foco_fixture_$(date +%Y%m%d%H%M%S)"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p logs
LOG="logs/walkthrough-${PREFIX}.log"
exec > >(tee "$LOG") 2>&1

echo "□ OBSERVED  project=$PROJECT location=$LOCATION prefix=$PREFIX"

for cmd in python3 gcloud bq; do
  command -v "$cmd" >/dev/null || { echo "× BROKEN  missing $cmd (install Google Cloud SDK: brew install --cask google-cloud-sdk)"; exit 1; }
done

if [ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]; then
  echo "↓ TRACED  using credentials from GOOGLE_APPLICATION_CREDENTIALS (CI)"
elif ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
  echo "↓ TRACED  no Application Default Credentials; opening browser sign-in"
  gcloud auth application-default login
fi

if [ ! -x .venv/bin/dbt ]; then
  python3 -m venv .venv
  .venv/bin/pip install -q --upgrade pip
  .venv/bin/pip install -q -r requirements.txt
fi
# Cost guard: a run-only profile caps every dbt query at 1 GB billed
# (about $0.006 at on-demand pricing). The fixture is a few KB.
MAX_BYTES=1000000000
sed "s/maximum_bytes_billed: .*/maximum_bytes_billed: ${MAX_BYTES}/" profiles.yml.example > logs/profiles.yml

export DBT_BIGQUERY_PROJECT="$PROJECT"
export DBT_BIGQUERY_DATASET="${PREFIX}_models"
export DBT_BIGQUERY_LOCATION="$LOCATION"

echo "↓ TRACED  creating synthetic fixture datasets ${PREFIX}_{ga4,hubspot,salesforce}"
python3 scripts/generate_fixture.py --project "$PROJECT" --prefix "$PREFIX" --location "$LOCATION" > "logs/${PREFIX}.sql"
bq query --project_id="$PROJECT" --location="$LOCATION" --use_legacy_sql=false --maximum_bytes_billed="$MAX_BYTES" < "logs/${PREFIX}.sql" >/dev/null

.venv/bin/dbt deps
.venv/bin/dbt debug --profiles-dir logs
set +e
.venv/bin/dbt build --profiles-dir logs --vars "{ga4_dataset: ${PREFIX}_ga4, hubspot_dataset: ${PREFIX}_hubspot, salesforce_dataset: ${PREFIX}_salesforce, ga4_start_date: '2026-01-01', ga4_end_date: '2026-01-02', ga4_timezone: UTC, validate_fixture: true}"
STATUS=$?
set -e

if [ "$STATUS" -eq 0 ]; then
  echo "✓ VERIFIED  dbt build passed against synthetic fixture $PREFIX"
else
  echo "× BROKEN  dbt build exited $STATUS; see $LOG"
fi
# Cleanup guard: every table this run created expires in 7 days.
for ds in ga4 hubspot salesforce models; do
  for t in $(bq ls --project_id="$PROJECT" --max_results=1000 --format=json "${PROJECT}:${PREFIX}_${ds}" 2>/dev/null | python3 -c 'import json,sys; [print(x["tableReference"]["tableId"]) for x in json.load(sys.stdin) if x.get("type")=="TABLE"]'); do
    bq update --expiration 604800 "${PROJECT}:${PREFIX}_${ds}.${t}" >/dev/null
  done
done
echo "Datasets created in $PROJECT: ${PREFIX}_ga4 ${PREFIX}_hubspot ${PREFIX}_salesforce ${PREFIX}_models (tables expire in 7 days)"
exit "$STATUS"
