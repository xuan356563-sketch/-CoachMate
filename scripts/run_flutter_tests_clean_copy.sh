#!/usr/bin/env bash

set -euo pipefail

show_help() {
  printf '%s\n' \
    '用法：scripts/run_flutter_tests_clean_copy.sh [flutter test 参数]' \
    '在临时干净副本中运行 Flutter 测试，避开外置卷 AppleDouble 文件。' \
    '原工作区不会被清理或修改。'
}

if [[ "${1:-}" == '--help' || "${1:-}" == '-h' ]]; then
  show_help
  exit 0
fi

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
project_dir="$(cd "$script_dir/.." && pwd -P)"
temp_root="$(mktemp -d '/private/tmp/trainmate-flutter-test.XXXXXX')"

cleanup_temp() {
  case "$temp_root" in
    /private/tmp/trainmate-flutter-test.*|/tmp/trainmate-flutter-test.*)
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
  --exclude='ios/Pods' \
  --exclude='outputs' \
  "$project_dir/" "$temp_root/"

cd "$temp_root"
flutter pub get --offline
flutter test --no-pub "$@"
