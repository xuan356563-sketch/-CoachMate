#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  printf '用法：%s <上一版 API 镜像> <上一版 Ops Web 镜像> [部署元数据文件]\n' "$0" >&2
  exit 2
fi

previous_api_image="$1"
previous_ops_web_image="$2"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
META_ENV="${3:-${DEPLOY_DIR}/.env.deploy}"
COMPOSE_FILE="${DEPLOY_DIR}/compose.production.yml"

[[ "${previous_api_image}" != -* && "${previous_api_image}" != *[[:space:]]* ]] \
  || { printf '回滚失败：API 镜像名称无效\n' >&2; exit 1; }
[[ "${previous_ops_web_image}" != -* && "${previous_ops_web_image}" != *[[:space:]]* ]] \
  || { printf '回滚失败：Ops Web 镜像名称无效\n' >&2; exit 1; }
[[ -f "${META_ENV}" ]] \
  || { printf '回滚失败：找不到部署元数据文件\n' >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "${META_ENV}"
set +a

export TRAINMATE_API_IMAGE="${previous_api_image}"
export TRAINMATE_OPS_WEB_IMAGE="${previous_ops_web_image}"

compose=(
  docker compose
  --project-name trainmate-production
  --env-file "${META_ENV}"
  --file "${COMPOSE_FILE}"
)

printf '仅回滚应用镜像，不执行数据库降级。\n'
"${compose[@]}" pull api ops-api ops-web
"${compose[@]}" up -d --no-deps --wait --wait-timeout 120 api
"${compose[@]}" up -d --no-deps ops-api ops-web nginx

curl --fail --silent --show-error \
  --retry 12 --retry-delay 5 --max-time 10 \
  "https://${API_DOMAIN}/readyz" >/dev/null

printf '应用镜像回滚完成。数据库仍保持当前迁移版本。\n'
