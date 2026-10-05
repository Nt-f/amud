import 'dart:convert';

import 'package:amud/features/torah/shnayim_mikra.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hebcal/hebcal.dart';

void main() {
  setUpAll(initHebcal);

  test("the week's parsha, an aliyah a day from Sunday to Shabbat", () {
    // Monday after Bereshit: Noach, the second aliyah.
    final mon = shnayimMikraWeek(HDate(1, Months.cheshvan, 5787), false)!;
    expect(mon.reading.parsha, ['Noach']);
    expect(mon.aliyah, 2);
    // Shabbat Noach itself: the seventh; the next day starts Lech-Lecha.
    final shabbat = shnayimMikraWeek(HDate(6, Months.cheshvan, 5787), false)!;
    expect(shabbat.reading.parsha, ['Noach']);
    expect(shabbat.aliyah, 7);
    final sun = shnayimMikraWeek(HDate(7, Months.cheshvan, 5787), false)!;
    expect(sun.reading.parsha, ['Lech-Lecha']);
    expect(sun.aliyah, 1);
    // Chol HaMoed Sukkot, before a holiday Shabbat: on to Bereshit.
    final sukkot = shnayimMikraWeek(HDate(19, Months.tishrei, 5787), false)!;
    expect(sukkot.reading.parsha, ['Bereshit']);
    expect(sukkot.shabbat.plainDate().toString(), '2026-10-10');
    expect(sukkot.aliyah, 4);
  });

  test('Sefaria refs for the parsha and its Onkelos', () {
    final r = ParshaReading.of(['Noach'])!;
    expect(sefariaRange(r), 'Genesis.6.9-11.32');
    expect(sefariaRange(r, onkelos: true), 'Onkelos_Genesis.6.9-11.32');
  });

  List<int> body(Object text) => utf8.encode(jsonEncode({
        'versions': [
          {'language': 'he', 'text': text},
        ],
      }));

  test('reads verses within one chapter and across chapters', () {
    expect(sefariaVerses(body(['א', 'ב']), (chapter: 6, verse: 9)), [
      ((chapter: 6, verse: 9), 'א'),
      ((chapter: 6, verse: 10), 'ב'),
    ]);
    expect(sefariaVerses(body([['א', 'ב {פ}'], ['ג']]), (chapter: 6, verse: 21)), [
      ((chapter: 6, verse: 21), 'א'),
      ((chapter: 6, verse: 22), 'ב'),
      ((chapter: 7, verse: 1), 'ג'),
    ]);
  });

  test('packs verses with their Targum', () {
    final packed = packShnayimMikra((
      parsha: 'Noach',
      begin: (chapter: 6, verse: 9),
      mikra: body(['אֵלֶּה', 'וַיּוֹלֶד']),
      targum: body(['אִלֵּין']),
    ));
    final s = unpackShnayimMikra(packed);
    expect(s.parsha, 'Noach');
    expect(s.verses, hasLength(2));
    expect(s.verses[0].at, (chapter: 6, verse: 9));
    expect(s.verses[0].he, 'אֵלֶּה');
    expect(s.verses[0].targum, 'אִלֵּין');
    expect(s.verses[1].targum, '');
  });
}
