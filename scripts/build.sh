#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
runtime="${ROON_NODE_PATH:-$(command -v node)}"
runtime="$("$runtime" -p 'process.execPath')"
if [[ ! -d helper/node_modules ]]; then
  (cd helper && npm ci --ignore-scripts)
fi
if [[ "${ROON_SKIP_SWIFT_BUILD:-0}" != "1" ]]; then
  swift build --build-system native -c release --arch arm64
elif [[ ! -x .build/arm64-apple-macosx/release/RoonVolume ]]; then
  echo "ROON_SKIP_SWIFT_BUILD requires an existing release binary." >&2
  exit 1
fi
app="dist/Roon Volume.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/helper"
cp .build/arm64-apple-macosx/release/RoonVolume "$app/Contents/MacOS/RoonVolume"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp "$runtime" "$app/Contents/Resources/node"

# Homebrew's Node 26 executable is a small launcher linked to libnode and other
# Homebrew libraries. Bundle and relink non-system dylibs so the helper does not
# depend on the build machine's Homebrew installation. Official Node binaries
# are normally self-contained, so this is a no-op for them.
declare -a pending=("$runtime")
declare -a sources=("$runtime")
declare -a bundled=("$app/Contents/Resources/node")
declare -A seen=()
seen["$runtime"]=1
while ((${#pending[@]})); do
  source_file="${pending[0]}"
  pending=("${pending[@]:1}")
  while IFS= read -r dependency; do
    [[ "$dependency" == /usr/lib/* || "$dependency" == /System/* ]] && continue
    if [[ "$dependency" == @rpath/* || "$dependency" == @loader_path/* ]]; then
      name="${dependency##*/}"
      if [[ -f "$(dirname "$source_file")/$name" ]]; then
        dependency="$(dirname "$source_file")/$name"
      elif [[ -f "$(dirname "$source_file")/../lib/$name" ]]; then
        dependency="$(cd "$(dirname "$source_file")/../lib" && pwd)/$name"
      else
        echo "Cannot resolve $dependency required by $source_file" >&2
        exit 1
      fi
    fi
    dependency="$(realpath "$dependency")"
    [[ -n "${seen[$dependency]:-}" ]] && continue
    seen["$dependency"]=1
    destination="$app/Contents/Resources/$(basename "$dependency")"
    cp -L "$dependency" "$destination"
    pending+=("$dependency")
    sources+=("$dependency")
    bundled+=("$destination")
  done < <(otool -L "$source_file" | tail -n +2 | sed -E 's/^[[:space:]]*([^[:space:]]+).*/\1/')
done

for index in "${!sources[@]}"; do
  source_file="${sources[$index]}"
  bundled_file="${bundled[$index]}"
  while IFS= read -r dependency; do
    [[ "$dependency" == /usr/lib/* || "$dependency" == /System/* ]] && continue
    resolved="$dependency"
    if [[ "$resolved" == @rpath/* || "$resolved" == @loader_path/* ]]; then
      name="${resolved##*/}"
      if [[ -f "$(dirname "$source_file")/$name" ]]; then
        resolved="$(dirname "$source_file")/$name"
      else
        resolved="$(dirname "$source_file")/../lib/$name"
      fi
    fi
    resolved="$(realpath "$resolved")"
    install_name_tool -change "$dependency" "@loader_path/$(basename "$resolved")" "$bundled_file"
  done < <(otool -L "$source_file" | tail -n +2 | sed -E 's/^[[:space:]]*([^[:space:]]+).*/\1/')
  if [[ "$bundled_file" == *.dylib ]]; then
    install_name_tool -id "@loader_path/$(basename "$bundled_file")" "$bundled_file"
  fi
done
cp helper/index.cjs helper/controller.cjs helper/package.json helper/package-lock.json "$app/Contents/Resources/helper/"
cp Resources/Node-LICENSE "$app/Contents/Resources/Node-LICENSE"
ditto helper/node_modules "$app/Contents/Resources/helper/node_modules"
identity="${ROON_SIGNING_IDENTITY:--}"
for bundled_file in "${bundled[@]:1}"; do
  codesign --force --sign "$identity" "$bundled_file"
done
codesign --force --sign "$identity" "$app/Contents/Resources/node"
codesign --force --sign "$identity" "$app"
codesign --verify --deep --strict "$app"
echo "Built $app"
if [[ "$identity" == "-" ]]; then
  echo "Locally signed build: after updates, macOS may require toggling Accessibility access off and on."
fi
