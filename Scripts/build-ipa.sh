#!/bin/bash
# 本地构建未签名 IPA：不需要开发者账号，产物可直接交给 AltStore / Sideloadly 等工具重签安装。
#
# 用法：
#   ./Scripts/build-ipa.sh            # 构建并把 IPA 输出到 dist/
#   ./Scripts/build-ipa.sh --clean    # 先清掉中间产物再构建
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="Radar.xcodeproj"
SCHEME="Radar"
DERIVED=".build-device"
ARCHIVE="$DERIVED/Radar.xcarchive"
APP_NAME="Radar"

if [[ "${1:-}" == "--clean" ]]; then
  rm -rf "$DERIVED" dist/Payload
fi

VERSION=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null \
  | awk '/ MARKETING_VERSION = /{print $3; exit}')
BUILD=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null \
  | awk '/ CURRENT_PROJECT_VERSION = /{print $3; exit}')
VERSION=${VERSION:-1.0.0}
BUILD=${BUILD:-1}

echo "==> 归档 Radar $VERSION ($BUILD) · 未签名"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  -archivePath "$ARCHIVE" \
  archive \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  > /tmp/radar-archive.log 2>&1 || { tail -40 /tmp/radar-archive.log; exit 1; }

APP_PATH="$ARCHIVE/Products/Applications/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "未找到归档产物：$APP_PATH" >&2
  exit 1
fi

echo "==> 打包 Payload"
rm -rf dist/Payload
mkdir -p dist/Payload
ditto --norsrc --noextattr "$APP_PATH" "dist/Payload/$APP_NAME.app"
xattr -cr "dist/Payload/$APP_NAME.app" 2>/dev/null || true

IPA="dist/Radar-ios-$VERSION-unsigned.ipa"
rm -f "$IPA"
(cd dist && zip -qry "$(basename "$IPA")" Payload)
rm -rf dist/Payload

SIZE=$(stat -f%z "$IPA")
echo "==> 完成：$IPA"
echo "    大小：$SIZE 字节（$(du -h "$IPA" | awk '{print $1}')）"
echo "    架构：$(lipo -archs "$APP_PATH/$APP_NAME")"
echo "    最低系统：$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$APP_PATH/Info.plist")"
