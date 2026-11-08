#!/bin/sh
# Re-render the check pages' core SVGs (build/daf/svg: the 42 checked
# pages; build/daf/sample: 20 random ones) with their side-by-side and
# overlay images, eight at a time.
#
#     tool/daf/rerender.sh [svg|sample ...]
cd "$(dirname "$0")/../.." || exit 1
. build/daf/env.sh
export OCR_LANG=heb_vilna
for dir in ${*:-svg sample}; do
  ls build/daf/$dir/*.core.svg | sed 's#.*/##; s#\.core\.svg##' |
    xargs -P 8 -I{} sh -c '
      n={}; book=$(echo ${n%_*} | tr _ " "); amud=${n##*_}
      python3 tool/daf/svg.py "$book" $amud --core --place --cache build/daf/cache --out build/daf/'$dir' >/dev/null &&
      python3 tool/daf/side.py build/daf/'$dir'/$n.core.svg >/dev/null 2>&1;
      python3 tool/daf/overlay.py build/daf/'$dir'/$n.core.svg >/dev/null' 
done
