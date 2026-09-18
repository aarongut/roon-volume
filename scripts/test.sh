#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift format lint --strict --recursive Sources Tests Package.swift
# Standalone Command Line Tools need explicit framework and macro search paths.
developer="$(xcode-select -p)"
if [[ -d "$developer/Library/Developer/Frameworks/Testing.framework" ]]; then
  swift test --build-system native --disable-xctest \
    -Xswiftc "-F$developer/Library/Developer/Frameworks" \
    -Xswiftc -plugin-path -Xswiftc "$developer/usr/lib/swift/host/plugins/testing" \
    -Xlinker -rpath -Xlinker "$developer/Library/Developer/Frameworks"
else
  swift test --disable-xctest
fi
(cd helper && npm test)
