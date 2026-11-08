#!/bin/sh
# check.py on the pages segment.py was tuned on (`tuned`), on twelve it
# wasn't at first (`holdout`, the default; looked at since 2026-10-25), or
# on twelve never looked at (`fresh`), or on six chapter openings
# (`openings`); more arguments go to check.py
# (LINEMAP_SEGMENT=0 for the line map without segment.py).
#
#     tool/daf/checkpages.sh holdout -v
cd "$(dirname "$0")/../.." || exit 1
. build/daf/env.sh
export OCR_LANG=heb_vilna
set="${1:-holdout}"
[ $# -gt 0 ] && shift
if [ "$set" = tuned ]; then
  pages='Berakhot 5a|Shabbat 41a|Chullin 16a|Ketubot 10b|Gittin 12a|Sanhedrin 15b|Pesachim 20a|Yoma 14b|Bava Metzia 18a|Eruvin 13a|Menachot 21b|Taanit 11a'
elif [ "$set" = fresh ]; then
  pages='Bava Kamma 30a|Bava Batra 40b|Avodah Zarah 25a|Makkot 8b|Horayot 6a|Keritot 10a|Meilah 12b|Temurah 14a|Nedarim 30b|Nazir 25a|Rosh Hashanah 20b|Moed Katan 15b'
elif [ "$set" = openings ]; then
  pages='Berakhot 26a|Shabbat 36b|Pesachim 42a|Megillah 21a|Sukkah 29b|Bava Kamma 27a'
else
  pages='Bekhorot 20b|Beitzah 12a|Kiddushin 14b|Shevuot 19a|Sotah 13a|Sukkah 18b|Yevamot 17a|Zevachim 22a|Arakhin 13b|Megillah 15a|Sanhedrin 20a|Eruvin 19b'
fi
echo "$pages" | tr '|' '\n' | while read -r p; do
  book=${p% *}; amud=${p##* }
  printf '%s ' "$book"; python3 tool/daf/check.py "$book" "$amud" "$@" | grep -v '^total'
done
