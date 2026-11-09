#!/usr/bin/env bash
# Android 单命令入口：构建、测试、检查环境或安装到已授权设备。
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_BUILD_DIR="${TMPDIR:-/tmp}/everframe-android-build"
export EVERFRAME_BUILD_DIR="${EVERFRAME_BUILD_DIR:-$DEFAULT_BUILD_DIR}"
if [[ -z "${ANDROID_HOME:-}" ]]; then
  if [[ -n "${ANDROID_SDK_ROOT:-}" ]]; then
    export ANDROID_HOME="$ANDROID_SDK_ROOT"
  elif [[ -d "$HOME/Library/Android/sdk" ]]; then
    export ANDROID_HOME="$HOME/Library/Android/sdk"
  elif [[ -d /tmp/everframe-android-tools/sdk ]]; then
    export ANDROID_HOME=/tmp/everframe-android-tools/sdk
  fi
fi
export ANDROID_SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
ACTION="${1:-build}"
if [[ "$ACTION" == doctor ]]; then
  java -version
  printf 'Android SDK：%s\n构建输出：%s\n' "${ANDROID_HOME:-未配置}" "$EVERFRAME_BUILD_DIR"
  if [[ -x "${ANDROID_HOME:-}/platform-tools/adb" ]]; then "$ANDROID_HOME/platform-tools/adb" devices -l; fi
  exit 0
fi
if [[ ! -f "$ANDROID_SDK_ROOT/platforms/android-36/android.jar" ]]; then
  echo '缺少 Android API 36 SDK。请通过 Android Studio SDK Manager 安装 Android SDK Platform 36、Build-Tools 35.0.0 和 Platform-Tools，设置 ANDROID_HOME。' >&2
  exit 1
fi
cd "$PROJECT_ROOT/android"
GRADLE_CMD=(./gradlew)
if [[ -n "${EVERFRAME_GRADLE_BIN:-}" ]]; then GRADLE_CMD=("$EVERFRAME_GRADLE_BIN"); fi
case "$ACTION" in
  build) TASKS=(assembleDebug) ;;
  test) TASKS=(testDebugUnitTest) ;;
  check) TASKS=(testDebugUnitTest lintDebug assembleDebug assembleRelease) ;;
  release) TASKS=(assembleRelease) ;;
  play) TASKS=(bundleRelease) ;;
  install) TASKS=(assembleDebug) ;;
  *) echo '用法：./scripts/android.sh [doctor|build|test|check|release|play|install]' >&2; exit 2 ;;
esac
"${GRADLE_CMD[@]}" --project-cache-dir "$EVERFRAME_BUILD_DIR/project-cache" --console=plain "${TASKS[@]}"
if [[ "$ACTION" == install ]]; then
  ADB="$ANDROID_SDK_ROOT/platform-tools/adb"
  if [[ -n "${ANDROID_SERIAL:-}" ]]; then DEVICE=(-s "$ANDROID_SERIAL"); else DEVICE=(-d); fi
  "$ADB" "${DEVICE[@]}" get-state
  "$ADB" "${DEVICE[@]}" install -r "$EVERFRAME_BUILD_DIR/app/outputs/apk/debug/app-debug.apk"
  "$ADB" "${DEVICE[@]}" shell am start -n com.bebackpacker.everframe/com.everframe.app.MainActivity
fi
if [[ "$ACTION" == play ]]; then
  AAB="$EVERFRAME_BUILD_DIR/app/outputs/bundle/release/app-release.aab"
  [[ -s "$AAB" ]] || { echo "未找到 Google Play AAB：$AAB" >&2; exit 1; }
  jarsigner -verify "$AAB" >/dev/null
  VERSION_NAME="$(sed -n 's/^[[:space:]]*versionName = "\([^"]*\)".*/\1/p' "$PROJECT_ROOT/android/app/build.gradle.kts" | head -n 1)"
  VERSION_CODE="$(sed -n 's/^[[:space:]]*versionCode = \([0-9][0-9]*\).*/\1/p' "$PROJECT_ROOT/android/app/build.gradle.kts" | head -n 1)"
  [[ "$VERSION_NAME" =~ ^[A-Za-z0-9._+-]+$ && "$VERSION_CODE" =~ ^[0-9]+$ ]] || {
    echo "无法从 android/app/build.gradle.kts 读取有效版本号。" >&2; exit 1;
  }
  AAB_NAME="everframe-${VERSION_NAME}-release.aab"

  ARTIFACT_PARENT="$PROJECT_ROOT/artifacts/google-play"
  ARTIFACT_DIR="$ARTIFACT_PARENT/release"
  mkdir -p "$ARTIFACT_PARENT"
  [[ ! -L "$ARTIFACT_PARENT" && (! -e "$ARTIFACT_DIR" || ! -L "$ARTIFACT_DIR") ]] || {
    echo "发布产物目录不能是符号链接：$ARTIFACT_DIR" >&2; exit 1;
  }
  STAGE_DIR="$(mktemp -d "$ARTIFACT_PARENT/.release-stage.XXXXXX")"
  trap 'rm -rf -- "$STAGE_DIR"' EXIT
  cp "$AAB" "$STAGE_DIR/$AAB_NAME"
  jarsigner -verify "$STAGE_DIR/$AAB_NAME" >/dev/null
  SYMBOLS="$EVERFRAME_BUILD_DIR/app/outputs/native-debug-symbols/release/native-debug-symbols.zip"
  MAPPING="$EVERFRAME_BUILD_DIR/app/outputs/mapping/release/mapping.txt"
  NATIVE_SYMBOLS_EMBEDDED=false
  NATIVE_SYMBOLS_NOTE="No native libraries in the bundle."
  MAPPING_AVAILABLE=false
  if unzip -Z1 "$AAB" | awk '/^base\/lib\/.*\.so$/ {found=1} END {exit !found}'; then
    NATIVE_SYMBOLS_NOTE="Native libraries are present."
    if [[ -s "$SYMBOLS" ]]; then
      cp "$SYMBOLS" "$STAGE_DIR/native-debug-symbols.zip"
      NATIVE_SYMBOLS_NOTE="Separate native debug symbols archive retained."
    elif unzip -Z1 "$AAB" | awk '/^BUNDLE-METADATA\/com\.android\.tools\.build\.debugsymbols\// {found=1} END {exit !found}'; then
      NATIVE_SYMBOLS_EMBEDDED=true
      NATIVE_SYMBOLS_NOTE="Native debug symbols embedded in the AAB."
    else
      NATIVE_SYMBOLS_NOTE="Packaged third-party native libraries are pre-stripped; no debug symbols were available."
    fi
  fi
  if [[ -s "$MAPPING" ]]; then cp "$MAPPING" "$STAGE_DIR/mapping.txt"; MAPPING_AVAILABLE=true; fi
  if command -v sha256sum >/dev/null 2>&1; then
    HASH="$(sha256sum "$STAGE_DIR/$AAB_NAME" | awk '{print $1}')"
  else
    HASH="$(shasum -a 256 "$STAGE_DIR/$AAB_NAME" | awk '{print $1}')"
  fi
  printf '%s  %s\n' "$HASH" "$AAB_NAME" > "$STAGE_DIR/SHA256SUMS"
  printf '{\n  "applicationId": "com.bebackpacker.everframe",\n  "versionName": "%s",\n  "versionCode": %s,\n  "aabSha256": "%s",\n  "nativeSymbolsEmbedded": %s,\n  "nativeSymbolsNote": "%s",\n  "mappingIncluded": %s\n}\n' \
    "$VERSION_NAME" "$VERSION_CODE" "$HASH" "$NATIVE_SYMBOLS_EMBEDDED" "$NATIVE_SYMBOLS_NOTE" "$MAPPING_AVAILABLE" > "$STAGE_DIR/manifest.json"

  OLD_DIR="$ARTIFACT_PARENT/.release-old.$$.tmp"
  [[ ! -e "$OLD_DIR" && ! -L "$OLD_DIR" ]] || { echo "临时归档目录已存在：$OLD_DIR" >&2; exit 1; }
  if [[ -e "$ARTIFACT_DIR" ]]; then mv "$ARTIFACT_DIR" "$OLD_DIR"; fi
  if ! mv "$STAGE_DIR" "$ARTIFACT_DIR"; then
    [[ ! -e "$OLD_DIR" ]] || mv "$OLD_DIR" "$ARTIFACT_DIR"
    echo "无法安装已验证的发布产物，旧产物已恢复。" >&2
    exit 1
  fi
  trap - EXIT
  [[ ! -e "$OLD_DIR" ]] || rm -rf -- "$OLD_DIR"

  if [[ "$EVERFRAME_BUILD_DIR" == "$DEFAULT_BUILD_DIR" && ! -L "$EVERFRAME_BUILD_DIR" &&
      -d "$EVERFRAME_BUILD_DIR/app" && ! -L "$EVERFRAME_BUILD_DIR/app" ]]; then
    rm -rf -- "$EVERFRAME_BUILD_DIR/app"
    printf '已清理本次成功生成的 Android 中间产物：%s/app\n' "$EVERFRAME_BUILD_DIR"
  else
    printf '构建目录为自定义路径或符号链接，保留中间产物供人工核验：%s/app\n' "$EVERFRAME_BUILD_DIR"
  fi
  printf '签名 AAB 与校验材料：%s\n' "$ARTIFACT_DIR"
fi
if [[ "$ACTION" != "play" ]]; then printf '构建与报告目录：%s/app\n' "$EVERFRAME_BUILD_DIR"; fi
