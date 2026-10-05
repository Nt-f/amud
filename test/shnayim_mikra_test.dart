import 'dart:convert';
import 'dart:io';

import 'package:amud/core/providers.dart';
import 'package:amud/core/settings.dart';
import 'package:amud/core/storage.dart';
import 'package:amud/core/theme.dart';
import 'package:amud/features/torah/shnayim_mikra.dart';
import 'package:amud/features/torah/shnayim_mikra_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  List<int> body(Object text, {Object? en}) => utf8.encode(jsonEncode({
        'versions': [
          {'language': 'he', 'text': text},
          if (en != null) {'language': 'en', 'text': en, 'versionTitle': 'The Contemporary Torah', 'license': 'CC-BY-NC'},
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
      mikra: body(['אֵלֶּה', 'וַיּוֹלֶד'], en: ['This is the line of Noah.']),
      targum: body(['אִלֵּין']),
    ));
    final s = unpackShnayimMikra(packed);
    expect(s.parsha, 'Noach');
    expect(s.verses, hasLength(2));
    expect(s.verses[0].at, (chapter: 6, verse: 9));
    expect(s.verses[0].he, 'אֵלֶּה');
    expect(s.verses[0].targum, 'אִלֵּין');
    expect(s.verses[1].targum, '');
    expect(s.verses[0].en, 'This is the line of Noah.');
    expect(s.verses[1].en, '');
    expect(s.enCredit, 'The Contemporary Torah (CC-BY-NC)');
  });

  test("a year's parshiyot, doubled ones once, holiday Shabbatot skipped", () {
    final year = parshiyotOfYear(5787, false);
    final names = [for (final (r, _) in year) r.parsha.join('-')];
    // The year opens on Shabbat Shuva, mid-Devarim.
    expect(names.first, "Ha'azinu");
    expect(names[1], 'Bereshit');
    expect(year[1].$2.plainDate().toString(), '2026-10-10');
    expect(names, contains('Matot-Masei'));
    expect(names.toSet(), hasLength(names.length));
  });

  Future<ProviderContainer> container() async {
    final dir = await Directory.systemTemp.createTemp('shnayim');
    addTearDown(() => dir.delete(recursive: true));
    final storage = await Storage.openAt(dir.path);
    final c = ProviderContainer(overrides: [storageProvider.overrideWithValue(storage)]);
    addTearDown(c.dispose);
    return c;
  }

  test('progress is kept by year and survives a restart', () async {
    final c = await container();
    final p = c.read(shnayimMikraProgressProvider.notifier);
    p.toggle(5787, 'Noach', 1);
    p.toggle(5787, 'Matot-Masei', 7);
    p.toggle(5787, 'Noach', 2);
    p.toggle(5787, 'Noach', 2);
    expect(c.read(shnayimMikraProgressProvider), {5787: {'Noach:1', 'Matot-Masei:7'}});
    final again = ProviderContainer(overrides: [storageProvider.overrideWithValue(c.read(storageProvider))]);
    addTearDown(again.dispose);
    expect(again.read(shnayimMikraProgressProvider.notifier).done(5787, 'Noach', 1), isTrue);
    expect(again.read(shnayimMikraProgressProvider.notifier).done(5788, 'Noach', 1), isFalse);
  });

  testWidgets('the reader follows the siddur layout and its own options', (tester) async {
    late ProviderContainer c;
    await tester.runAsync(() async {
      c = await container();
      await c.read(storageProvider).writeBlob('shnayim-mikra', packShnayimMikra((
        parsha: 'Noach',
        begin: (chapter: 6, verse: 9),
        mikra: body(['אלה תולדת נח'], en: ['This is the line of Noah.']),
        targum: body(['אלין תולדת נח']),
      )));
    });
    Future<void> show() async {
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: buildTheme(c.read(settingsProvider), Brightness.light),
          home: const ShnayimMikraScreen(parsha: 'Noach', year: 5790),
        ),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }

    c.read(settingsProvider.notifier).update((x) => x.copyWith(layout: TextLayout.interleaved));
    await show();
    expect(find.textContaining('אלה תולדת נח', findRichText: true), findsNWidgets(2));
    expect(find.textContaining('אלין תולדת נח', findRichText: true), findsOneWidget);
    expect(find.textContaining('This is the line of Noah.', findRichText: true), findsOneWidget);

    c.read(settingsProvider.notifier).update((x) => x.copyWith(layout: TextLayout.hebrewOnly));
    c.read(shnayimMikraSettingsProvider.notifier).update((x) => x.copyWith(repeatVerse: false, showTargum: false));
    await tester.pump();
    expect(find.textContaining('אלה תולדת נח', findRichText: true), findsOneWidget);
    expect(find.textContaining('אלין תולדת נח', findRichText: true), findsNothing);
    expect(find.textContaining('This is the line of Noah.', findRichText: true), findsNothing);

    // Checking off the aliyah saves it and moves on to the next.
    await tester.tap(find.textContaining('Mark aliyah 1 done'));
    await tester.pump();
    expect(c.read(shnayimMikraProgressProvider.notifier).done(5790, 'Noach', 1), isTrue);
    // Stop the app clock's timer before the test ends.
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
