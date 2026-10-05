import 'dart:convert';
import 'dart:io';

import 'package:amud/core/providers.dart';
import 'package:amud/core/settings.dart';
import 'package:amud/core/storage.dart';
import 'package:amud/core/theme.dart';
import 'package:amud/features/torah/shnayim_mikra.dart';
import 'package:amud/features/home/card_registry.dart';
import 'package:amud/features/torah/shnayim_mikra_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hebcal/hebcal.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
      name: 'Noach',
      begin: (chapter: 6, verse: 9),
      mikra: body(['אֵלֶּה', 'וַיּוֹלֶד'], en: ['This is the line of Noah.']),
      targum: body(['אִלֵּין']),
    ));
    final s = unpackShnayimMikra(packed);
    expect(s.name, 'Noach');
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

  test('the Chumash downloads once, then every parsha works offline', () async {
    final c = await container();
    final asked = <String>[];
    // Sefaria, in miniature: Bereshit 6–11 with English and Onkelos.
    final sefaria = MockClient((req) async {
      final ref = req.url.pathSegments.last;
      asked.add(ref);
      final chapters = [for (var ch = 1; ch <= 11; ch++) [for (var v = 1; v <= 32; v++) '$ch:$v']];
      return http.Response.bytes(
          ref.startsWith('Onkelos_')
              ? body([for (final ch in chapters) [for (final v in ch) 'ת $v']])
              : body(chapters, en: [for (final ch in chapters) [for (final v in ch) 'en $v']]),
          200);
    });
    final noach = await http.runWithClient(() => c.read(shnayimMikraProvider('Noach').future), () => sefaria);
    // Bereshit came first, so Noach opened; the rest finish behind it.
    expect(asked.take(2), ['Genesis', 'Onkelos_Genesis']);
    await c.read(chumashDownloadProvider.notifier).downloadAll();
    expect(asked, hasLength(10));
    expect(c.read(chumashDownloadProvider).have, {1, 2, 3, 4, 5});
    expect(noach.verses.first.at, (chapter: 6, verse: 9));
    expect(noach.verses.last.at, (chapter: 11, verse: 32));
    expect(noach.verses.first.targum, 'ת 6:9');
    expect(noach.verses.first.en, 'en 6:9');

    // No connection at all: another parsha still opens, from storage.
    final offline = ProviderContainer(overrides: [storageProvider.overrideWithValue(c.read(storageProvider))]);
    addTearDown(offline.dispose);
    final bereshit = await http.runWithClient(
        () => offline.read(shnayimMikraProvider('Bereshit').future), () => MockClient((_) => throw const SocketException('offline')));
    expect(bereshit.verses.first.at, (chapter: 1, verse: 1));
    expect(asked, hasLength(10));
  });

  test("Rashi's comments: the dibbur hamatchil, then the comment", () {
    expect(rashiComment('<b>בראשית ברא.</b> אמר רבי יצחק'), (dh: 'בראשית ברא.', text: 'אמר רבי יצחק'));
    // A dash after it, footnotes and other markup go.
    expect(
        rashiComment('<b>ויאמר</b> - לא <i>היה</i><sup class="footnote-marker">1</sup><i class="footnote">הערה</i> צריך&nbsp;להתחיל'),
        (dh: 'ויאמר', text: 'לא היה צריך להתחיל'));
    // Without a bold opening, it's all comment.
    expect(rashiComment('אמר רבי יצחק'), (dh: '', text: 'אמר רבי יצחק'));
  });

  test('packs Rashi by verse in Hebrew and English, leaving out verses he passes over', () {
    final rashi = unpackRashi(packRashi(body([
      [
        ['<b>בראשית</b> אמר רבי יצחק', '<b>ברא אלהים</b> ולא אמר'],
        <String>[],
        ['<b>תהו ובהו</b> תהו לשון תמה'],
      ],
      [
        '',
        ['<b>ויכלו</b> כלה מלאכתו'],
      ],
    ], en: [
      [
        ['<b>IN THE BEGINNING</b> — Rabbi Isaac said'],
        <String>[],
        <String>[],
        ['<b>UNFORMED AND VOID</b> astonishment'],
      ],
    ])));
    expect(rashi.verses.keys, [(chapter: 1, verse: 1), (chapter: 1, verse: 3), (chapter: 1, verse: 4), (chapter: 2, verse: 2)]);
    expect(rashi.verses[(chapter: 1, verse: 1)]!.he, [(dh: 'בראשית', text: 'אמר רבי יצחק'), (dh: 'ברא אלהים', text: 'ולא אמר')]);
    expect(rashi.verses[(chapter: 1, verse: 1)]!.en, [(dh: 'IN THE BEGINNING', text: 'Rabbi Isaac said')]);
    expect(rashi.verses[(chapter: 1, verse: 3)]!.en, isEmpty);
    // English only where the Hebrew has none here: kept, by its own verse.
    expect(rashi.verses[(chapter: 1, verse: 4)]!.he, isEmpty);
    expect(rashi.verses[(chapter: 2, verse: 2)]!.he.single.dh, 'ויכלו');
    expect(rashi.enCredit, 'The Contemporary Torah (CC-BY-NC)');
    // Without an English version, no credit.
    expect(unpackRashi(packRashi(body([[['<b>א</b> ב']]]))).enCredit, '');
  });

  test('Rashi in Hebrew is taken from a vocalized version where Sefaria has one', () {
    List<int> versions(List<(String, bool, Object)> he) => utf8.encode(jsonEncode({
          'versions': [
            for (final (title, primary, text) in he) {'language': 'he', 'versionTitle': title, 'isPrimary': primary, 'text': text},
          ],
        }));
    final rashi = unpackRashi(packRashi(versions([
      ('Plain', true, [
        [
          ['<b>בראשית</b> אמר רבי יצחק'],
          ['<b>והארץ</b> היתה'],
        ],
      ]),
      ('Vocalized', false, [
        [
          ['<b>בְּרֵאשִׁית</b> אָמַר רַבִּי יִצְחָק'],
        ],
      ]),
    ])));
    expect(rashi.verses[(chapter: 1, verse: 1)]!.he.single, (dh: 'בְּרֵאשִׁית', text: 'אָמַר רַבִּי יִצְחָק'));
    // Where the vocalized version has nothing, the main one.
    expect(rashi.verses[(chapter: 1, verse: 2)]!.he.single, (dh: 'והארץ', text: 'היתה'));
    // With no vocalized version, the main one, though it's listed second.
    final plain = unpackRashi(packRashi(versions([
      ('Other', false, [[['<b>א</b> אחר']]]),
      ('Plain', true, [[['<b>א</b> עיקר']]]),
    ])));
    expect(plain.verses[(chapter: 1, verse: 1)]!.he.single.text, 'עיקר');
  });

  test('Rashi downloads once, with his markup, then works offline', () async {
    final c = await container();
    final asked = <Uri>[];
    final sefaria = MockClient((req) async {
      asked.add(req.url);
      final book = req.url.pathSegments.last.replaceFirst('Rashi_on_', '');
      return http.Response.bytes(
          body([
            [
              ['<b>$book</b> 1:1'],
            ],
          ]),
          200);
    });
    final exodus = await http.runWithClient(() => c.read(rashiBookProvider(2).future), () => sefaria);
    expect(asked.first.pathSegments.last, 'Rashi_on_Exodus');
    // Not text only: the bold sets off the dibbur hamatchil.
    // Every Hebrew version, to find one with nikud.
    expect(asked.first.queryParametersAll['version'], ['hebrew|all', 'english']);
    expect(exodus.verses[(chapter: 1, verse: 1)]!.he, [(dh: 'Exodus', text: '1:1')]);
    await http.runWithClient(() => c.read(rashiDownloadProvider.notifier).downloadAll(), () => sefaria);
    expect(asked, hasLength(5));
    expect(c.read(rashiDownloadProvider).have, {1, 2, 3, 4, 5});

    final offline = ProviderContainer(overrides: [storageProvider.overrideWithValue(c.read(storageProvider))]);
    addTearDown(offline.dispose);
    final numbers = await http.runWithClient(
        () => offline.read(rashiBookProvider(4).future), () => MockClient((_) => throw const SocketException('offline')));
    expect(numbers.verses[(chapter: 1, verse: 1)]!.he.single.dh, 'Numbers');
    expect(asked, hasLength(5));
  });

  test("its own text style starts from the siddur's and leaves it alone", () async {
    final c = await container();
    final siddur = c.read(settingsProvider.notifier);
    final mikra = c.read(shnayimMikraSettingsProvider.notifier);
    siddur.update((x) => x.copyWith(hebrewFont: 'TaameyFrankCLM', layout: TextLayout.hebrewOnly));
    // Following the siddur: its changes show here.
    expect(c.read(mikraStyleProvider).hebrewFont, 'TaameyFrankCLM');
    // Its own style starts as the siddur's...
    mikra.update((x) => x.startOwnStyle(c.read(settingsProvider)));
    expect(c.read(mikraStyleProvider).layout, TextLayout.hebrewOnly);
    // ...and from then on neither changes the other.
    mikra.update((x) => x.copyWith(hebrewFont: 'DavidLibre', layout: TextLayout.sideBySide));
    siddur.update((x) => x.copyWith(textScale: 1.4));
    expect(c.read(mikraStyleProvider).hebrewFont, 'DavidLibre');
    expect(c.read(mikraStyleProvider).textScale, isNot(1.4));
    expect(c.read(settingsProvider).hebrewFont, 'TaameyFrankCLM');
    expect(c.read(settingsProvider).layout, TextLayout.hebrewOnly);
    // Back to the siddur's, keeping the own style for next time.
    mikra.update((x) => x.copyWith(ownStyle: false));
    expect(c.read(mikraStyleProvider).hebrewFont, 'TaameyFrankCLM');
    expect(c.read(shnayimMikraSettingsProvider).hebrewFont, 'DavidLibre');
  });

  testWidgets('the reader follows the siddur layout and its own options', (tester) async {
    late ProviderContainer c;
    await tester.runAsync(() async {
      c = await container();
      // Bereshit as downloaded, here only from Noach's first verse.
      await c.read(storageProvider).writeBlob('shnayim-mikra:1', packShnayimMikra((
        name: 'Genesis',
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

    // Rashi, once he's downloaded: in Rashi script, or in the Hebrew font.
    await tester.runAsync(() async {
      await c.read(storageProvider).writeBlob('shnayim-mikra-rashi:1', packRashi(body([
        for (var ch = 1; ch < 6; ch++) <List<String>>[],
        [
          for (var v = 1; v < 9; v++) <String>[],
          ['<b>אֵלֶּה תּוֹלְדוֹת נֹחַ</b> הוֹאִיל וְהִזְכִּירוֹ סִפֵּר בְּשִׁבְחוֹ'],
        ],
      ], en: [
        for (var ch = 1; ch < 6; ch++) <List<String>>[],
        [
          for (var v = 1; v < 9; v++) <String>[],
          ['<b>THESE ARE THE GENERATIONS OF NOAH</b> since Scripture mentions him, it tells his praise'],
        ],
      ])));
    });
    c.read(shnayimMikraSettingsProvider.notifier).update((x) => x.copyWith(showRashi: true));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    final rashi = find.textContaining('הוֹאִיל וְהִזְכִּירוֹ סִפֵּר בְּשִׁבְחוֹ', findRichText: true);
    expect(rashi, findsOneWidget);
    expect(tester.widget<RichText>(rashi).text.style?.fontFamily, 'NotoRashiHebrew');
    // His nikud, on its own switch.
    c.read(shnayimMikraSettingsProvider.notifier).update((x) => x.copyWith(rashiNikud: false));
    await tester.pump();
    expect(rashi, findsNothing);
    expect(find.textContaining('הואיל והזכירו ספר בשבחו', findRichText: true), findsOneWidget);
    c.read(shnayimMikraSettingsProvider.notifier).update((x) => x.copyWith(rashiNikud: true));
    await tester.pump();
    c.read(shnayimMikraSettingsProvider.notifier).update((x) => x.copyWith(rashiScript: false));
    await tester.pump();
    expect(tester.widget<RichText>(rashi).text.style?.fontFamily, isNot('NotoRashiHebrew'));
    c.read(shnayimMikraSettingsProvider.notifier).update((x) => x.copyWith(rashiScript: true));
    await tester.pump();
    // His English, when it's turned on and the layout shows English.
    final rashiEn = find.textContaining('it tells his praise', findRichText: true);
    c.read(settingsProvider.notifier).update((x) => x.copyWith(layout: TextLayout.interleaved));
    await tester.pump();
    expect(rashiEn, findsNothing);
    c.read(shnayimMikraSettingsProvider.notifier).update((x) => x.copyWith(rashiEnglish: true));
    await tester.pump();
    expect(rashiEn, findsOneWidget);
    c.read(settingsProvider.notifier).update((x) => x.copyWith(layout: TextLayout.hebrewOnly));
    await tester.pump();
    expect(rashiEn, findsNothing);
    c.read(settingsProvider.notifier).update((x) => x.copyWith(layout: TextLayout.interleaved));
    await tester.pump();

    // In the order chosen: here the English first, then the verse and Rashi.
    final pasuk = find.textContaining('אלה תולדת נח', findRichText: true);
    final english = find.textContaining('This is the line of Noah.', findRichText: true);
    double y(Finder f) => tester.getTopLeft(f).dy;
    expect(y(pasuk), lessThan(y(rashi)));
    expect(y(rashi), lessThan(y(english)));
    expect(y(english), lessThan(y(rashiEn)));
    c.read(shnayimMikraSettingsProvider.notifier).update((x) => x.copyWith(order: [
          MikraPart.english,
          MikraPart.rashiEnglish,
          MikraPart.verse,
          MikraPart.rashi,
          MikraPart.verseAgain,
          MikraPart.targum,
        ]));
    await tester.pump();
    expect(y(english), lessThan(y(rashiEn)));
    expect(y(rashiEn), lessThan(y(pasuk)));
    expect(y(pasuk), lessThan(y(rashi)));
    // Side by side, each language keeps that order in its own column.
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    c.read(settingsProvider.notifier).update((x) => x.copyWith(layout: TextLayout.sideBySide));
    await tester.pump();
    expect(tester.getTopLeft(english).dx, lessThan(tester.getTopLeft(pasuk).dx));
    expect(y(english), lessThan(y(rashiEn)));
    expect(y(pasuk), lessThan(y(rashi)));
    await tester.binding.setSurfaceSize(null);
    c.read(settingsProvider.notifier).update((x) => x.copyWith(layout: TextLayout.interleaved));
    c.read(shnayimMikraSettingsProvider.notifier).update((x) => x.copyWith(order: MikraPart.values));
    await tester.pump();
    expect(find.textContaining('English: The Contemporary Torah (CC-BY-NC).', findRichText: true), findsNWidgets(2));
    c.read(shnayimMikraSettingsProvider.notifier).update((x) => x.copyWith(rashiEnglish: false));
    await tester.pump();
    expect(rashiEn, findsNothing);
    c.read(shnayimMikraSettingsProvider.notifier).update((x) => x.copyWith(showRashi: false));
    await tester.pump();
    expect(rashi, findsNothing);
    c.read(settingsProvider.notifier).update((x) => x.copyWith(layout: TextLayout.hebrewOnly));
    await tester.pump();

    // Checking off the aliyah saves it and moves on to the next.
    await tester.tap(find.textContaining('Mark aliyah 1 done'));
    await tester.pump();
    expect(c.read(shnayimMikraProgressProvider.notifier).done(5790, 'Noach', 1), isTrue);
    // Stop the app clock's timer before the test ends.
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  test('a saved order keeps the parts it knows, and adds new ones', () {
    ShnayimMikraSettings read(Object? order) => ShnayimMikraSettings.fromJson({'order': order});
    expect(read(null).order, MikraPart.values);
    // Unknown and repeated names go; missing ones come back after the part
    // they follow by default.
    expect(read(['english', 'verse', 'english', 'shmoo', 'rashi']).order,
        [MikraPart.english, MikraPart.rashiEnglish, MikraPart.verse, MikraPart.verseAgain, MikraPart.targum, MikraPart.rashi]);
    const custom = ShnayimMikraSettings(order: [
      MikraPart.rashi,
      MikraPart.verse,
      MikraPart.english,
      MikraPart.verseAgain,
      MikraPart.rashiEnglish,
      MikraPart.targum,
    ]);
    expect(ShnayimMikraSettings.fromJson(custom.toJson()).order, custom.order);
  });

  testWidgets('the settings sheet turns parts on and off, and drags them into order', (tester) async {
    late ProviderContainer c;
    await tester.runAsync(() async {
      c = await container();
      await c.read(storageProvider).writeBlob('shnayim-mikra:1', packShnayimMikra((
        name: 'Genesis',
        begin: (chapter: 6, verse: 9),
        mikra: body(['אלה תולדת נח'], en: ['This is the line of Noah.']),
        targum: body(['אלין תולדת נח']),
      )));
    });
    // From the defaults, whatever earlier tests left behind.
    c.read(shnayimMikraSettingsProvider.notifier).update((_) => const ShnayimMikraSettings());
    await tester.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: buildTheme(c.read(settingsProvider), Brightness.light),
        home: const ShnayimMikraScreen(parsha: 'Noach', year: 5790),
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.text_fields));
    await tester.pumpAndSettle();

    // Checking off the Targum hides it.
    final targum = find.ancestor(of: find.text('Targum Onkelos'), matching: find.byType(ListTile));
    await tester.tap(find.descendant(of: targum, matching: find.byType(Checkbox)));
    await tester.pump();
    expect(c.read(shnayimMikraSettingsProvider).showTargum, isFalse);

    // Dragging the verse below "Verse again" and the Targum.
    final handle = find.descendant(
        of: find.ancestor(of: find.text('Verse'), matching: find.byType(ListTile)), matching: find.byIcon(Icons.drag_handle));
    final rowHeight = tester.getSize(targum).height;
    final drag = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 20));
    for (var i = 0; i < 10; i++) {
      await drag.moveBy(Offset(0, rowHeight * 2.2 / 10));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await drag.up();
    await tester.pumpAndSettle();
    expect(c.read(shnayimMikraSettingsProvider).order.take(3), [MikraPart.verseAgain, MikraPart.targum, MikraPart.verse]);

    // Reset puts it back.
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(c.read(shnayimMikraSettingsProvider).order, MikraPart.values);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets("the Home card checks off today's aliyah", (tester) async {
    late ProviderContainer c;
    await tester.runAsync(() async => c = await container());
    final registry = CardRegistry();
    registerShnayimMikraCard(registry);
    final type = registry['shnayimMikra']!;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: buildTheme(c.read(settingsProvider), Brightness.light),
        home: Scaffold(body: Consumer(builder: (context, ref, _) => type.build(context, ref, const CardConfig(id: 'x', type: 'shnayimMikra')))),
      ),
    ));
    expect(find.text('Shnayim Mikra'), findsOneWidget);
    expect(find.textContaining('0 of 7 this week'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.check_circle_outline));
    await tester.pump();
    expect(find.textContaining('1 of 7 this week'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
