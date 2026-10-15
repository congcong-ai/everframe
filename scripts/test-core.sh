#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
work_dir=$(mktemp -d /tmp/everframe-core.XXXXXX)
trap 'rm -rf "$work_dir"' EXIT
swiftc -D DEBUG -parse-as-library \
  EverFrame/App/Product.swift EverFrame/Core/AppLogger.swift \
  EverFrame/Core/Recording/RecordingContinuation.swift EverFrame/Core/Recording/DualCameraCompositor.swift \
  EverFrame/Models/*.swift EverFrame/Core/Storage/*.swift \
  EverFrame/Core/Security/PairingStore.swift EverFrame/Core/WebServer/HTTPParser.swift \
  EverFrame/Core/AI/AIJSON.swift Tests/CoreTests.swift \
  -o "$work_dir/core-tests"
"$work_dir/core-tests"
