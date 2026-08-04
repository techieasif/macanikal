#!/bin/bash
# Builds and launches Macanikal. No Apple Developer account needed —
# the app is signed ad-hoc for local use. (If you iterate on the code,
# prefer Xcode with your own team: ad-hoc rebuilds get a fresh identity,
# so macOS re-asks for the Input Monitoring permission each time.)
set -euo pipefail
cd "$(dirname "$0")"

xcodebuild -project macanikal.xcodeproj -scheme macanikal -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
  build | grep -E "error|warning: [^M]|BUILD" || true

APP="build/Build/Products/Release/Macanikal.app"
if [ -d "$APP" ]; then
  echo "✅ Built $APP — launching."
  open "$APP"
else
  echo "❌ Build failed." >&2
  exit 1
fi
