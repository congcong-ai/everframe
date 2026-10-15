#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
configuration=${1:-Debug}
if [[ "$configuration" != Debug && "$configuration" != Release ]]; then
  print -u2 '用法：./scripts/build.sh [Debug|Release]'
  exit 2
fi
# 不启用自动 provisioning；此脚本只编译未签名 arm64 App，真机安装由 Xcode 完成。
xcodebuild -project EverFrame.xcodeproj -target EverFrame \
  -configuration "$configuration" -sdk iphoneos -arch arm64 \
  CODE_SIGNING_ALLOWED=NO SYMROOT="/tmp/everframe-build-$configuration" build
