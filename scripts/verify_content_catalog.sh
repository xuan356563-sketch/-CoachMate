#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_dir/.." && pwd)"
python_path="$repository_root/backend/.venv/bin/python"

if [[ ! -x "$python_path" ]]; then
  echo "业务内容资源库校验失败：未找到 backend/.venv/bin/python，请先恢复项目现有后端环境。" >&2
  exit 1
fi

cd "$repository_root"
exec "$python_path" scripts/content_catalog.py --check "$@"
