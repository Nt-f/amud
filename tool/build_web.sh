#!/usr/bin/env bash
# Builds the site into web-dist/: the static landing page (landing/) at the
# root and the self-contained, offline-capable PWA under /app/.
#   tool/build_web.sh                      # landing page + app at /app/
#   BASE_HREF=/ tool/build_web.sh          # the app alone, at the root
set -euo pipefail
cd "$(dirname "$0")/.."
BASE_HREF="${BASE_HREF:-/app/}"
flutter pub get
# Start clean: flutter build doesn't remove files from earlier builds, and
# a stale .gz copy would end up in the service worker's precache.
rm -rf build/web
# --wasm: also compile to WebAssembly. Browsers that support it (WasmGC,
# Chromium for now) run the Wasm build with the skwasm renderer, which
# starts and scrolls faster; the rest fall back to the JavaScript build.
# --no-web-resources-cdn: serve the renderers ourselves (no Google CDN at
# runtime), which is required for the app to work fully offline.
flutter build web --release \
  --wasm \
  --no-web-resources-cdn \
  --no-source-maps \
  --base-href "$BASE_HREF"
# Debug symbols for the renderers, and wimp, an opt-in skwasm variant the
# app doesn't enable: none of it is ever loaded.
find build/web -name '*.symbols' -delete
rm -f build/web/canvaskit/wimp.*
dart run tool/gen_service_worker.dart build/web
# Precompressed copies of the big compiled files for nginx's gzip_static,
# at the highest level instead of the on-the-fly default.
find build/web -maxdepth 3 \( -name 'main.dart.*' -o -path '*/canvaskit/*' \) \
  \( -name '*.js' -o -name '*.mjs' -o -name '*.wasm' \) -exec gzip -9kf {} +
rm -rf web-dist
if [[ "$BASE_HREF" == "/" ]]; then
  cp -r build/web web-dist
else
  mkdir -p "web-dist$BASE_HREF"
  cp -r build/web/. "web-dist$BASE_HREF"
  cp -r landing/. web-dist/
fi
echo "Prebuilt site in web-dist/ ($(du -sh web-dist | cut -f1)), app at $BASE_HREF"
