#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
META_ENV="${1:-${DEPLOY_DIR}/.env.deploy}"
COMPOSE_FILE="${DEPLOY_DIR}/compose.production.yml"

"${SCRIPT_DIR}/preflight.sh" "${META_ENV}"

set -a
# shellcheck disable=SC1090
source "${META_ENV}"
set +a

compose=(
  docker compose
  --project-name trainmate-production
  --env-file "${META_ENV}"
  --file "${COMPOSE_FILE}"
)

printf '开始拉取不可变镜像：%s\n' "${APP_VERSION}"
"${compose[@]}" pull api ops-api ops-web nginx

printf '开始执行单实例数据库迁移。生产环境不会自动降级。\n'
"${compose[@]}" run --rm migration

printf '开始更新业务 API 并等待就绪。\n'
"${compose[@]}" up -d --no-deps --wait --wait-timeout 120 api

printf '开始更新 HTTPS 入口和私网运营台。\n'
"${compose[@]}" up -d nginx ops-api ops-web

curl --fail --silent --show-error \
  --retry 12 --retry-delay 5 --max-time 10 \
  "https://${API_DOMAIN}/readyz" >/dev/null

state_dir="${DEPLOY_STATE_DIR:-/opt/trainmate/state}"
install -d -m 700 "${state_dir}"
receipt_file="${state_dir}/deployment-${APP_VERSION}.receipt"
umask 077
{
  printf 'APP_VERSION=%s\n' "${APP_VERSION}"
  printf 'TRAINMATE_API_IMAGE=%s\n' "${TRAINMATE_API_IMAGE}"
  printf 'TRAINMATE_OPS_WEB_IMAGE=%s\n' "${TRAINMATE_OPS_WEB_IMAGE}"
  printf 'BACKUP_RECEIPT_ID=%s\n' "${BACKUP_RECEIPT_ID}"
  printf 'DEPLOYED_AT_UTC=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
} >"${receipt_file}"

printf '部署完成：%s；回执：%s\n' "${APP_VERSION}" "${receipt_file}"
