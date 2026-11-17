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

if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
  echo "↓ TRACED  no Application Default Credentials; opening browser sign-in"
  gcloud auth application-default login
fi

if [ ! -x .venv/bin/dbt ]; then
  python3 -m venv .venv
  .venv/bin/pip install -q --upgrade pip
  .venv/bin/pip install -q -r requirements.txt
fi
[ -f profiles.yml ] || cp profiles.yml.example profiles.yml

export DBT_BIGQUERY_PROJECT="$PROJECT"
export DBT_BIGQUERY_DATASET="${PREFIX}_models"
export DBT_BIGQUERY_LOCATION="$LOCATION"

echo "↓ TRACED  creating synthetic fixture datasets ${PREFIX}_{ga4,hubspot,salesforce}"
python3 scripts/generate_fixture.py --project "$PROJECT" --prefix "$PREFIX" --location "$LOCATION" > "logs/${PREFIX}.sql"
bq query --project_id="$PROJECT" --location="$LOCATION" --use_legacy_sql=false < "logs/${PREFIX}.sql" >/dev/null

.venv/bin/dbt deps
.venv/bin/dbt debug --profiles-dir .
set +e
.venv/bin/dbt build --profiles-dir . --vars "{ga4_dataset: ${PREFIX}_ga4, hubspot_dataset: ${PREFIX}_hubspot, salesforce_dataset: ${PREFIX}_salesforce, ga4_start_date: '2026-01-01', ga4_end_date: '2026-01-02', ga4_timezone: UTC, validate_fixture: true}"
STATUS=$?
set -e

if [ "$STATUS" -eq 0 ]; then
  echo "✓ VERIFIED  dbt build passed against synthetic fixture $PREFIX"
else
  echo "× BROKEN  dbt build exited $STATUS; see $LOG"
fi
echo "Datasets created in $PROJECT: ${PREFIX}_ga4 ${PREFIX}_hubspot ${PREFIX}_salesforce ${PREFIX}_models"
exit "$STATUS"
