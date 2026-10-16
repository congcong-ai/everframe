#!/usr/bin/env bash
# 生成便于查找的本地 IPA 和 APK；安装包不进入 Git。
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/everframe-package.XXXXXX")"
trap 'rm -rf "$PACKAGE_WORK_DIR"' EXIT
IOS_BUILD_DIR="${TMPDIR:-/tmp}/everframe-package-ios"
OUTPUT_DIR="$PROJECT_ROOT/artifacts"
mkdir -p "$OUTPUT_DIR/ios" "$OUTPUT_DIR/android" "$PACKAGE_WORK_DIR/Payload"
cd "$PROJECT_ROOT"
# 使用缓存的 Personal Team 签名，不启用自动 provisioning 或上传。
xcodebuild -project EverFrame.xcodeproj -target EverFrame -configuration Debug \
  -sdk iphoneos -arch arm64 SYMROOT="$IOS_BUILD_DIR" build
IOS_APP="$IOS_BUILD_DIR/Debug-iphoneos/EverFrame.app"
codesign --verify --deep --strict "$IOS_APP"
test -f "$IOS_APP/embedded.mobileprovision"
IOS_VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$IOS_APP/Info.plist")
IOS_BUILD=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$IOS_APP/Info.plist")
IOS_NAME="EverFrame-v${IOS_VERSION}-build${IOS_BUILD}-development.ipa"
ditto "$IOS_APP" "$PACKAGE_WORK_DIR/Payload/EverFrame.app"
ditto -c -k --keepParent "$PACKAGE_WORK_DIR/Payload" "$PACKAGE_WORK_DIR/$IOS_NAME"
unzip -tq "$PACKAGE_WORK_DIR/$IOS_NAME"
./scripts/android.sh build
ANDROID_OUTPUT_DIR="${EVERFRAME_BUILD_DIR:-${TMPDIR:-/tmp}/everframe-android-build}/app/outputs/apk/debug"
ANDROID_VERSION=$(python3 - "$ANDROID_OUTPUT_DIR/output-metadata.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    print(json.load(f)['elements'][0]['versionName'])
PY
)
ANDROID_NAME="everframe-android-v${ANDROID_VERSION}-debug.apk"
cp "$ANDROID_OUTPUT_DIR/app-debug.apk" "$PACKAGE_WORK_DIR/$ANDROID_NAME"
unzip -tq "$PACKAGE_WORK_DIR/$ANDROID_NAME"
# 两端均成功后才替换交付文件，失败时保留上一份有效包。
mv -f "$PACKAGE_WORK_DIR/$IOS_NAME" "$OUTPUT_DIR/ios/$IOS_NAME"
mv -f "$PACKAGE_WORK_DIR/$ANDROID_NAME" "$OUTPUT_DIR/android/$ANDROID_NAME"
cd "$OUTPUT_DIR"
shasum -a 256 "ios/$IOS_NAME" "android/$ANDROID_NAME" > SHA256SUMS
shasum -a 256 -c SHA256SUMS
printf '\n安装包：\n%s\n%s\n' "$OUTPUT_DIR/ios/$IOS_NAME" "$OUTPUT_DIR/android/$ANDROID_NAME"
