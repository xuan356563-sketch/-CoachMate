#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
project_dir="$(cd "$script_dir/.." && pwd -P)"
temp_root="$(mktemp -d '/private/tmp/trainmate-flutter-analyze.XXXXXX')"

cleanup_temp() {
  case "$temp_root" in
    /private/tmp/trainmate-flutter-analyze.*|/tmp/trainmate-flutter-analyze.*)
      rm -rf -- "$temp_root"
      ;;
    *)
      printf '拒绝清理非预期临时目录：%s\n' "$temp_root" >&2
      ;;
  esac
}
trap cleanup_temp EXIT

printf '正在创建临时干净副本：%s\n' "$temp_root"
COPYFILE_DISABLE=1 rsync -a \
  --exclude='.git' \
  --exclude='.dart_tool' \
  --exclude='build' \
  --exclude='._*' \
  --exclude='**/._*' \
  --exclude='backend/.venv' \
  --exclude='ops-web/node_modules' \
  --exclude='ops-web/dist' \
  --exclude='ios/Pods' \
  --exclude='outputs' \
  "$project_dir/" "$temp_root/"

cd "$temp_root"
flutter pub get --offline
flutter analyze --no-pub
