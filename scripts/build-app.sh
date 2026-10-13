#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build -c release --cache-path .build/cache --disable-sandbox --product Chorus
BIN_DIR="$(swift build -c release --show-bin-path --cache-path .build/cache --disable-sandbox)"
APP="$(pwd)/dist/Chorus.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# SwiftPM resource files can arrive read-only; keep repeated builds replaceable.
chmod -R u+w "$APP/Contents"
cp "$BIN_DIR/Chorus" "$APP/Contents/MacOS/Chorus"
cp packaging/Info.plist "$APP/Contents/Info.plist"
python3 scripts/prepare-metal-runtime.py "$APP/Contents/Resources/mlx.metallib"
cp Sources/ChorusPocket/LICENSE-UPSTREAM "$APP/Contents/Resources/POCKET_RUNTIME_LICENSE"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
for resource in "$BIN_DIR"/*.bundle; do
    if [ -d "$resource" ]; then
        cp -R "$resource" "$APP/Contents/Resources/"
    fi
done
swift scripts/make-icon.swift dist/Chorus.iconset
iconutil -c icns dist/Chorus.iconset -o "$APP/Contents/Resources/Chorus.icns"
python3 scripts/collect-licenses.py "$APP/Contents/Resources/ThirdPartyLicenses"
python3 scripts/package-swift-runtime.py "$APP"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"
