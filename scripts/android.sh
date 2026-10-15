#!/usr/bin/env bash
# Android 单命令入口：构建、测试、检查环境或安装到已授权设备。
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export EVERFRAME_BUILD_DIR="${EVERFRAME_BUILD_DIR:-${TMPDIR:-/tmp}/everframe-android-build}"
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
  install) TASKS=(assembleDebug) ;;
  *) echo '用法：./scripts/android.sh [doctor|build|test|check|release|install]' >&2; exit 2 ;;
esac
"${GRADLE_CMD[@]}" --project-cache-dir "$EVERFRAME_BUILD_DIR/project-cache" --console=plain "${TASKS[@]}"
if [[ "$ACTION" == install ]]; then
  ADB="$ANDROID_SDK_ROOT/platform-tools/adb"
  if [[ -n "${ANDROID_SERIAL:-}" ]]; then DEVICE=(-s "$ANDROID_SERIAL"); else DEVICE=(-d); fi
  "$ADB" "${DEVICE[@]}" get-state
  "$ADB" "${DEVICE[@]}" install -r "$EVERFRAME_BUILD_DIR/app/outputs/apk/debug/app-debug.apk"
  "$ADB" "${DEVICE[@]}" shell am start -n com.everframe.app/.MainActivity
fi
printf '构建与报告目录：%s/app\n' "$EVERFRAME_BUILD_DIR"
