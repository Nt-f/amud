#!/bin/sh
# kraken_compare.py over the fresh set, for kraken's lines in DIR
# (default build/daf/kraken), summed:
#
#     tool/daf/kraken_eval.sh build/daf/kraken/stock
cd "$(dirname "$0")/../.." || exit 1
. build/daf/env.sh
export OCR_LANG=heb_vilna
dir="${1:-build/daf/kraken}"
for p in 'Bava Kamma 30a' 'Bava Batra 40b' 'Avodah Zarah 25a' 'Makkot 8b' 'Horayot 6a' 'Keritot 10a' 'Meilah 12b' 'Temurah 14a' 'Nedarim 30b' 'Nazir 25a' 'Rosh Hashanah 20b' 'Moed Katan 15b'; do
  python3 tool/daf/kraken_compare.py "${p% *}" "${p##* }" --dir "$dir" | grep -v '^total'
done | python3 -c '
import re, sys
from collections import Counter
c = Counter()
for line in sys.stdin:
    print(line, end="")
    m = re.search(r"(\d+) map lines: (\{.*\}); kraken lines in the body on no map line: (\d+)", line)
    if m:
        c["map"] += int(m.group(1))
        c.update(eval(m.group(2)))
        c["kraken only"] += int(m.group(3))
print("total", dict(c))'
