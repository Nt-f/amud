#!/usr/bin/env bash
# Publishes a daf's video shiur, or a Kitzur Yomi day's, to R2 for the app's
# player (lib/features/gemara/daf_video.dart): uploads
# <hls_root>/<tractate>/<daf>/ to amud-video/daf/<tractate>/<daf>/ with the
# content types and cache times HLS needs, checks every file is served at
# video.amud.page, then adds it to daf/index.json, the list the app lights up.
#   tool/publish_daf_video.sh ~/yomis/bechoros30/hls Bekhorot 30
# A Kitzur Yomi day goes by where its portion starts, <siman>-<se'if>, so
# siman 2 from se'if 4 is in <hls_root>/kitzur-shulchan-arukh/2-4/:
#   tool/publish_daf_video.sh ~/yomis/kitzur2-4/hls "Kitzur Shulchan Arukh" 2-4
# <hls_root> is what learn-video-kit's hls.sh writes. Files already on the
# bucket at the same size are skipped, so a re-run resumes an upload.
set -euo pipefail
BUCKET="${BUCKET:-amud-video}"
PUBLIC="${PUBLIC:-https://video.amud.page}"
ROOT=$(realpath "$1"); TRACTATE=$(echo "$2" | tr 'A-Z ' 'a-z-'); DAF=$3
[[ $DAF =~ ^[0-9]+(-[0-9]+)?$ ]] || { echo "not a daf or <siman>-<se'if>: $DAF" >&2; exit 1; }
DIR="$ROOT/$TRACTATE/$DAF"
for f in avc/index.m3u8 hevc/index.m3u8; do [ -f "$DIR/$f" ] || { echo "missing $DIR/$f" >&2; exit 1; }; done

# Size of an object as served, or 0. The query string skips any edge cache.
served() { curl -s -o /dev/null -I -w '%{http_code} %header{content-length}' "$PUBLIC/daf/$1?v=$RANDOM" | awk '$1 == 200 { print $2; exit } { print 0 }'; }
upload() {   # <path under daf/> <file>
  local type cache
  case "$1" in
    *.m3u8) type=application/vnd.apple.mpegurl cache="public, max-age=300" ;;
    *.m4s) type=video/iso.segment cache="public, max-age=86400" ;;
    *.mp4) type=video/mp4 cache="public, max-age=86400" ;;
    *.json) type=application/json cache="public, max-age=300" ;;
    *) echo "unknown type: $1" >&2; return 1 ;;
  esac
  npx -y wrangler@4 r2 object put "$BUCKET/daf/$1" --file "$2" --content-type "$type" --cache-control "$cache" --remote >/dev/null
  echo "  put $1"
}
export -f served upload; export BUCKET PUBLIC

# Segments first and playlists last, so a playlist never lists a file that isn't up.
cd "$DIR"
upload_new() {   # <find tests>
  find . -type f "$@" | sed 's|^\./||' | sort |
    xargs -P 6 -I{} bash -c 'f={}; k='"$TRACTATE/$DAF"'/$f; [ "$(served "$k")" = "$(stat -c %s "$f")" ] || upload "$k" "$f"'
}
upload_new \( -name init.mp4 -o -name '*.m4s' \)
upload_new -name '*.m3u8'

missing=0
while read -r f; do
  [ "$(served "$TRACTATE/$DAF/$f")" = "$(stat -c %s "$f")" ] || { echo "not served: $f" >&2; missing=1; }
done < <(find . -type f | sed 's|^\./||')
[ $missing = 0 ] || { echo "not adding $TRACTATE $DAF to index.json" >&2; exit 1; }
echo "all $(find . -type f | wc -l) files served"

# Add it to index.json ({"bekhorot": [30], "kitzur-shulchan-arukh": ["2-4"], …}).
# Only a real 404 starts a new list; any other failure stops, so a bad read
# can't wipe the list.
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
code=$(curl -s -o "$tmp" -w '%{http_code}' "$PUBLIC/daf/index.json?v=$RANDOM")
case "$code" in 200) ;; 404) echo '{}' > "$tmp" ;; *) echo "index.json: HTTP $code" >&2; exit 1 ;; esac
python3 - "$tmp" "$TRACTATE" "$DAF" <<'EOF'
import json, sys
path, tractate, unit = sys.argv[1], sys.argv[2], sys.argv[3]
# A daf is a number; a Kitzur Yomi day stays "siman-se'if".
unit = int(unit) if unit.isdigit() else unit
index = json.load(open(path))
order = lambda u: [int(n) for n in str(u).split('-')]
index[tractate] = sorted(set(index.get(tractate, [])) | {unit}, key=order)
json.dump(dict(sorted(index.items())), open(path, 'w'), separators=(',', ':'))
EOF
upload index.json "$tmp"
echo "index.json: $(cat "$tmp")"
