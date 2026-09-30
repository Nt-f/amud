#!/usr/bin/env bash
# Builds the site into web-dist/: the static landing page (landing/) at the
# root and the self-contained, offline-capable PWA under /app/.
#   tool/build_web.sh                      # landing page + app at /app/
#   BASE_HREF=/ tool/build_web.sh          # the app alone, at the root
set -euo pipefail
cd "$(dirname "$0")/.."
BASE_HREF="${BASE_HREF:-/app/}"
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
if [[ "$BASE_HREF" == "/" ]]; then
  cp -r build/web web-dist
else
  mkdir -p "web-dist$BASE_HREF"
  cp -r build/web/. "web-dist$BASE_HREF"
  cp -r landing/. web-dist/
fi
echo "Prebuilt site in web-dist/ ($(du -sh web-dist | cut -f1)), app at $BASE_HREF"
