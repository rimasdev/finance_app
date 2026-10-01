#!/usr/bin/env bash
# Push Takings API → Alphabet VPS and restart PM2.
# Usage: bash scripts/push.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VPS_HOST="${VPS_HOST:-alphabet-vps}"
APP_DIR="${APP_DIR:-/var/www/takings}"

echo "━━━ Push takings-api → ${VPS_HOST}:${APP_DIR} ━━━"
ssh "${VPS_HOST}" "mkdir -p '${APP_DIR}'"

rsync -az --delete \
  --exclude .venv \
  --exclude __pycache__ \
  --exclude .pytest_cache \
  --exclude .env \
  --exclude data \
  --exclude '.git' \
  "${ROOT}/api/" "${VPS_HOST}:${APP_DIR}/"

ssh "${VPS_HOST}" bash -s <<EOF
set -euo pipefail
cd ${APP_DIR}
if [[ ! -f .env ]]; then
  echo "Missing ${APP_DIR}/.env — copy from .env.example and fill secrets first."
  exit 1
fi
python3 -m venv .venv
.venv/bin/pip install -q -r requirements.txt
set -a
source .env
set +a
pm2 delete takings-api 2>/dev/null || true
pm2 start .venv/bin/uvicorn --name takings-api --cwd ${APP_DIR} --interpreter none -- app.main:app --host 127.0.0.1 --port "\${PORT:-3120}"
pm2 save
pm2 show takings-api | head -20
curl -sS "http://127.0.0.1:\${PORT:-3120}/health" || true
echo
EOF

echo "Done. Point Caddy at :3120 (see docs/DEPLOY.md)"
