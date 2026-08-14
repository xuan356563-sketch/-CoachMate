#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
META_ENV="${1:-${DEPLOY_DIR}/.env.deploy}"
COMPOSE_FILE="${DEPLOY_DIR}/compose.production.yml"

fail() {
  printf '部署预检失败：%s\n' "$1" >&2
  exit 1
}

for command_name in docker curl; do
  command -v "${command_name}" >/dev/null 2>&1 \
    || fail "缺少必需命令 ${command_name}"
done

[[ -f "${META_ENV}" ]] || fail "找不到部署元数据文件 ${META_ENV}"

# 部署元数据不包含业务密钥，可作为受控 shell 环境文件加载。
set -a
# shellcheck disable=SC1090
source "${META_ENV}"
set +a

required_meta=(
  TRAINMATE_API_IMAGE
  TRAINMATE_OPS_WEB_IMAGE
  TRAINMATE_ENV_FILE
  API_DOMAIN
  APP_VERSION
  BACKUP_RECEIPT_ID
)
for variable_name in "${required_meta[@]}"; do
  [[ -n "${!variable_name:-}" ]] || fail "未设置 ${variable_name}"
  [[ "${!variable_name}" != *REPLACE_WITH* ]] \
    || fail "${variable_name} 仍是占位值"
done

[[ -f "${TRAINMATE_ENV_FILE}" ]] \
  || fail "找不到生产环境变量文件 ${TRAINMATE_ENV_FILE}"
[[ -s "${DEPLOY_DIR}/certs/fullchain.pem" ]] \
  || fail "缺少 TLS 证书 deploy/certs/fullchain.pem"
[[ -s "${DEPLOY_DIR}/certs/privkey.pem" ]] \
  || fail "缺少 TLS 私钥 deploy/certs/privkey.pem"

if grep -Eq '(^|=)REPLACE_WITH' "${TRAINMATE_ENV_FILE}"; then
  fail "生产环境变量中仍存在 REPLACE_WITH 占位值"
fi

grep -qx 'APP_ENV=production' "${TRAINMATE_ENV_FILE}" \
  || fail "APP_ENV 必须为 production"
grep -qx "APP_VERSION=${APP_VERSION}" "${TRAINMATE_ENV_FILE}" \
  || fail "部署元数据与应用 APP_VERSION 不一致"

if [[ "${ALLOW_RISKY_FLAGS:-false}" != "true" ]]; then
  safe_flags=(
    SYNC_ENABLED
    HEALTH_PROFILE_CLOUD_ENABLED
    PROFILE_PROPOSAL_ENABLED
    TRAINING_STRUCTURE_V1_ENABLED
    PLAN_REVISION_ENABLED
    IOS_SUBSCRIPTION_ENABLED
    PAID_PLAN_GENERATION_GATE_ENABLED
  )
  for flag_name in "${safe_flags[@]}"; do
    grep -qx "${flag_name}=false" "${TRAINMATE_ENV_FILE}" \
      || fail "首批部署要求 ${flag_name}=false；经专项验收后才可设置 ALLOW_RISKY_FLAGS=true"
  done
fi

compose=(
  docker compose
  --project-name trainmate-production
  --env-file "${META_ENV}"
  --file "${COMPOSE_FILE}"
)

"${compose[@]}" config --quiet

# 直接使用候选镜像执行 Pydantic 生产配置校验和 Alembic 单 Head 检查。
"${compose[@]}" run --rm --no-deps api \
  python -c 'from app.core.config import get_settings; get_settings(); print("生产配置校验通过")'
"${compose[@]}" run --rm --no-deps api \
  python -c 'from app.api.health import _expected_migration_head; print(_expected_migration_head())'

printf '部署预检通过：版本 %s，域名 %s\n' "${APP_VERSION}" "${API_DOMAIN}"
