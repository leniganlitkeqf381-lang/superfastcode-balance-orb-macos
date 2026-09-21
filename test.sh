#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
xcrun swiftc Sources/Quota.swift Tests/QuotaTests.swift -o build/QuotaTests
build/QuotaTests
