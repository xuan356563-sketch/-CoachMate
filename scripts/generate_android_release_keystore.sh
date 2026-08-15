#!/usr/bin/env bash
#
# 生成 Android 正式签名 keystore 并写入 android/key.properties
#
# 用法：
#   1. 在有 JDK 17 的机器上运行（本机需安装 Android Studio 或 openjdk）
#   2. ./scripts/generate_android_release_keystore.sh
#   3. 脚本会生成 android/app/upload-keystore.jks 与 android/key.properties
#   4. 之后 flutter build apk --release / flutter build appbundle --release 使用正式签名
#
# 安全提醒：
#   - upload-keystore.jks 与 key.properties 已被 .gitignore 排除，绝不提交到仓库
#   - keystore 一旦丢失或密码遗忘，无法找回，也无法更新商店已发布应用
#   - 请将 keystore 文件备份到多个安全位置（离线磁盘/密码管理器）
#
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd -P)"
keystore_dir="$project_dir/android/app"
keystore_file="$keystore_dir/upload-keystore.jks"
props_file="$project_dir/android/key.properties"

if ! command -v keytool >/dev/null 2>&1; then
  echo "错误：未找到 keytool。请先安装 JDK 17（Android Studio 自带 JBR，或用 brew install openjdk@17）。" >&2
  exit 1
fi

if [ -f "$keystore_file" ]; then
  echo "已存在 $keystore_file，为避免覆盖现网密钥，脚本退出。"
  echo "如需重新生成，请先手动删除该文件与 android/key.properties。"
  exit 1
fi

echo "===== 生成 Android 正式签名 keystore ====="
echo "输出位置：$keystore_file"
echo ""

# 生成随机强密码（32 字节 base64）
STORE_PASS="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"
KEY_PASS="$STORE_PASS"

# 证书信息（按需修改，但 CN/OU/O/L/ST/C 需合法）
CN="${1:-CoachMate}"
OU="TrainMate"
O="${2:-CoachMate Studio}"
L="Beijing"
ST="Beijing"
C="CN"
VALIDITY=10000  # 天，约 27 年

keytool -genkeypair -v \
  -keystore "$keystore_file" \
  -alias trainmate \
  -keyalg RSA \
  -keysize 4096 \
  -validity "$VALIDITY" \
  -storepass "$STORE_PASS" \
  -keypass "$KEY_PASS" \
  -dname "CN=$CN, OU=$OU, O=$O, L=$L, ST=$ST, C=$C" \
  >/dev/null 2>&1

# 写入 key.properties（相对路径基于 android/ 目录）
cat > "$props_file" <<EOF
storePassword=$STORE_PASS
keyPassword=$KEY_PASS
keyAlias=trainmate
storeFile=app/upload-keystore.jks
EOF

chmod 600 "$keystore_file" "$props_file"

echo "✅ 已生成："
echo "  keystore : $keystore_file"
echo "  props    : $props_file"
echo ""
echo "⚠️  请立即将以下密码保存到密码管理器（本输出后不再显示明文）："
echo "  storePassword / keyPassword : $STORE_PASS"
echo "  keyAlias                    : trainmate"
echo ""
echo "⚠️  请将 $keystore_file 备份到离线磁盘/密码管理器；丢失无法找回。"
echo ""
echo "构建命令："
echo "  cd $project_dir && flutter build appbundle --release"
