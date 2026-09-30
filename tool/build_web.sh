#!/usr/bin/env bash
# Builds the self-contained, offline-capable PWA into web-dist/.
#   tool/build_web.sh            # release build
#   BASE_HREF=/siddur/ tool/build_web.sh   # when served from a sub-path
set -euo pipefail
cd "$(dirname "$0")/.."
BASE_HREF="${BASE_HREF:-/}"
flutter pub get
# --no-web-resources-cdn: serve CanvasKit ourselves (no Google CDN at runtime),
# which is required for the app to work fully offline.
flutter build web --release \
  --no-web-resources-cdn \
  --no-source-maps \
  --no-wasm-dry-run \
  --base-href "$BASE_HREF"
dart run tool/gen_service_worker.dart build/web
rm -rf web-dist
cp -r build/web web-dist
echo "Prebuilt PWA in web-dist/ ($(du -sh web-dist | cut -f1))"
