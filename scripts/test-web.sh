#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
work_dir=$(mktemp -d /tmp/everframe-web.XXXXXX)
trap 'rm -rf "$work_dir"' EXIT
port_pids=$(lsof -tiTCP:18080 -sTCP:LISTEN || true)
if [[ -n "$port_pids" ]]; then kill ${(f)port_pids}; fi
swiftc -parse-as-library EverFrame/App/Product.swift EverFrame/Core/AppLogger.swift \
  EverFrame/Models/Clip.swift EverFrame/Core/Storage/ClipRepository.swift \
  EverFrame/Core/Security/PairingStore.swift EverFrame/Core/WebServer/HTTPParser.swift \
  EverFrame/Core/WebServer/LocalWebServer.swift Tests/WebTransportTests.swift \
  -o "$work_dir/web-tests"
"$work_dir/web-tests"
