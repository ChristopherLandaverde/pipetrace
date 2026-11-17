#!/usr/bin/env bash
# Synthetic walkthrough / no client data.
# Creates new fixture datasets in a development BigQuery project, then runs
# dbt build (models + unit + data tests) against them.
# Usage: bash scripts/run_walkthrough.sh <dev-project-id> [location]
set -euo pipefail

PROJECT="${1:?usage: bash scripts/run_walkthrough.sh <dev-project-id> [location]}"
LOCATION="${2:-US}"
PREFIX="foco_fixture_$(date -u +%Y%m%d%H%M%S)"
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
grep -q "maximum_bytes_billed: ${MAX_BYTES}" logs/profiles.yml || { echo "× BROKEN  cost cap not applied to logs/profiles.yml"; exit 1; }

export DBT_BIGQUERY_PROJECT="$PROJECT"
export DBT_BIGQUERY_DATASET="${PREFIX}_models"
export DBT_BIGQUERY_LOCATION="$LOCATION"

# BigQuery sandbox projects drop partitions older than 60 days, so the fixture
# starts 12 days ago: sessions on day 0-1, opportunities created on day 9.
BASE_DATE="$(python3 -c 'import datetime as d; print(d.datetime.now(d.timezone.utc).date()-d.timedelta(days=12))')"
END_DATE="$(python3 -c "import datetime as d; print(d.date.fromisoformat('$BASE_DATE')+d.timedelta(days=1))")"
echo "↓ TRACED  fixture base date $BASE_DATE"
echo "↓ TRACED  creating synthetic fixture datasets ${PREFIX}_{ga4,hubspot,salesforce}"
python3 scripts/generate_fixture.py --project "$PROJECT" --prefix "$PREFIX" --location "$LOCATION" --base-date "$BASE_DATE" --expiration-days 7 > "logs/${PREFIX}.sql"
bq query --project_id="$PROJECT" --location="$LOCATION" --use_legacy_sql=false --maximum_bytes_billed="$MAX_BYTES" < "logs/${PREFIX}.sql" >/dev/null

# Cleanup guard: every table and view in these datasets expires after 7 days,
# set at dataset creation so it holds even if the run stops early.
bq mk --project_id="$PROJECT" --location="$LOCATION" --dataset --default_table_expiration 604800 "${PROJECT}:${PREFIX}_models" >/dev/null

.venv/bin/dbt deps
.venv/bin/dbt debug --profiles-dir logs
set +e
.venv/bin/dbt build --profiles-dir logs --vars "{ga4_dataset: ${PREFIX}_ga4, hubspot_dataset: ${PREFIX}_hubspot, salesforce_dataset: ${PREFIX}_salesforce, ga4_start_date: '${BASE_DATE}', ga4_end_date: '${END_DATE}', ga4_timezone: UTC, fixture_base_date: '${BASE_DATE}', validate_fixture: true}"
STATUS=$?
set -e

if [ "$STATUS" -eq 0 ]; then
  echo "✓ VERIFIED  dbt build passed against synthetic fixture $PREFIX"
else
  echo "× BROKEN  dbt build exited $STATUS; see $LOG"
fi
echo "Datasets created in $PROJECT: ${PREFIX}_ga4 ${PREFIX}_hubspot ${PREFIX}_salesforce ${PREFIX}_models (tables expire in 7 days)"
exit "$STATUS"
