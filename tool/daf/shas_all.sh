#!/bin/sh
# All of Shas again, a tractate at a time (kraken's lines, then the render),
# into OUT (default build/daf/v3) and its own log, so build/daf/place (what
# was published) stays as it is until the new set is compared and chosen.
# A tractate whose render finished is skipped when the script runs again.
#
#     setsid nohup tool/daf/shas_all.sh [OUT] > /dev/null 2>&1 &
#     tail -f build/daf/v3/run.log
cd "$(dirname "$0")/../.." || exit 1
. build/daf/env.sh
export OCR_LANG=heb_vilna
out=${1:-build/daf/v3}
mkdir -p "$out/done"
log="$out/run.log"
# The worst tractates of the 2026-11-08 run first, then the rest in order.
first='Keritot|Tamid|Temurah|Menachot|Bekhorot|Nedarim|Horayot|Arakhin'
rest=$(python3 -c "
import sys; sys.path.insert(0, 'tool/daf')
import shas
print('|'.join(b for b, _, _ in shas.tractates()))")
echo "$first|$rest" | tr '|' '\n' | awk '!seen[$0]++' | while read -r book; do
  [ -e "$out/done/$book" ] && continue
  echo "== $book kraken $(date +%T)" >> "$log"
  python3 tool/daf/shas.py kraken -j 8 "$book" >> "$log" 2>&1
  echo "== $book render $(date +%T)" >> "$log"
  python3 tool/daf/shas.py render -j 12 --out "$out" "$book" >> "$log" 2>&1 && touch "$out/done/$book"
done
echo "== all done $(date +%T)" >> "$log"
