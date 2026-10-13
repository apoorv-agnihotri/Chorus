#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
# A self-contained runner also works on standalone CLT installs missing XCTest
# and the Swift Testing interop dylib. Every failed assertion exits nonzero.
swift run -c release --cache-path .build/cache --disable-sandbox chorus-tests
