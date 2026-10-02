#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
runtime="${ROON_NODE_PATH:-$(command -v node)}"
runtime="$("$runtime" -p 'process.execPath')"
if [[ "$("$runtime" --version)" != "v24.21.0" ]]; then
  echo "Expected Node v24.21.0. Set ROON_NODE_PATH to that runtime." >&2
  exit 1
fi
if [[ ! -d helper/node_modules ]]; then
  (cd helper && npm ci --ignore-scripts)
fi
swift build --build-system native -c release --arch arm64
app="dist/Roon Volume.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/helper"
cp .build/arm64-apple-macosx/release/RoonVolume "$app/Contents/MacOS/RoonVolume"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp "$runtime" "$app/Contents/Resources/node"
cp helper/index.cjs helper/controller.cjs helper/tide16.cjs helper/package.json helper/package-lock.json "$app/Contents/Resources/helper/"
cp Resources/Node-LICENSE "$app/Contents/Resources/Node-LICENSE"
ditto helper/node_modules "$app/Contents/Resources/helper/node_modules"
identity="${ROON_SIGNING_IDENTITY:--}"
codesign --force --sign "$identity" "$app/Contents/Resources/node"
codesign --force --sign "$identity" "$app"
codesign --verify --deep --strict "$app"
echo "Built $app"
if [[ "$identity" == "-" ]]; then
  echo "Locally signed build: after updates, macOS may require toggling Accessibility access off and on."
fi
