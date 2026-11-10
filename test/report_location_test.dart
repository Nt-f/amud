import 'dart:convert';
import 'dart:io';

import 'package:amud/core/l10n.dart';
import 'package:amud/core/providers.dart';
import 'package:amud/core/settings.dart';
import 'package:amud/core/storage.dart';
import 'package:amud/core/text_report.dart';
import 'package:amud/core/theme.dart';
import 'package:amud/features/siddur/reader_jump.dart';
import 'package:amud/features/siddur/reader_screen.dart';
import 'package:amud/features/siddur/reader_typography.dart' show normalizeHebrewWords;
import 'package:amud/features/siddur/report_location.dart';
import 'package:amud/features/siddur/siddur_providers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hebcal/hebcal.dart';
import 'package:siddur_engine/siddur_engine.dart';

const _book = 'Siddur Ashkenaz';
const _musaf = 'Festivals/Rosh Chodesh/Musaf Amidah for Rosh Chodesh';
const _day = '$_musaf/Sanctity of the Day';

void main() {
  setUpAll(initHebcal);

  // Rosh Chodesh Kislev, 10 November 2026: Weekday Shacharit holds Hallel
  // and Musaf for Rosh Chodesh.
  final roshChodesh = HDate(30, Months.cheshvan, 5787);
  late List<SegmentItem> page;

  setUpAll(() {
    final corpus = Corpus.fromJson(
        jsonDecode(utf8.decode(gzip.decode(File(corpusFiles[_book]!).readAsBytesSync()))) as Map<String, Object?>);
    final rules = jsonDecode(File('assets/rules/rules.json').readAsStringSync()) as Map<String, dynamic>;
    final resolver = SiddurResolver().withOverrides(rules[_book] as Map<String, dynamic>).withCorpus(corpus);
    final versions = VersionSelection([CorpusTextVersion(corpus, corpus.versionInfo('he')!)],
        [CorpusTextVersion(corpus, corpus.versionInfo('en')!)]);
    page = segmentsIn(resolver.resolve(corpus.index!.find('Weekday/Shacharit')!, versions,
        (s) => DayContext.forService(roshChodesh, s, il: false),
        options: const ResolveOptions(excluded: ExcludedDisplay.hide)));
  });

  List<SegmentItem> leaf(String id) => [for (final s in page) if (s.node.id == id) s];
  List<String> heRefs(SelectionSpot s) => [for (final x in s.he) x.he!.segment.ref];

  group('the reports from Rosh Chodesh Kislev 5787', () {
    // As the reader's rows would offer them: the section the selection is
    // in, with the sections either side (a row can hold several).
    List<SegmentItem> rows() => [...leaf('$_musaf/Kedushah/Kedushat HaShem'), ...leaf(_day), ...leaf('$_musaf/Avodah')];

    test('#3: one word that the Amidah says often', () {
      final spot = locateSelection(leaf(_day), 'אֱלהֵינוּ')!;
      expect(spot.exact, isTrue);
      expect(heRefs(spot), ['5']);
      expect(spot.leaves.map((n) => n.id), [_day]);
      // Across the whole page it can't be told apart.
      expect(locateSelection(page, 'אֱלהֵינוּ', exactOnly: true)!.ambiguous, isTrue);
    });

    test('#4: the opening of the verse', () {
      final spot = locateSelection(rows(), 'וּבְרָאשֵׁי')!;
      expect(heRefs(spot), ['3']);
      expect(spot.leaves.map((n) => n.id), [_day]);
    });

    test('#5: from the end of one line into the next', () {
      final spot = locateSelection(rows(), 'תִּזְכּור: וַהֲבִיאֵנוּ')!;
      expect(spot.exact, isTrue);
      expect(heRefs(spot), ['1', '2']);
      // The page has only one place with these words.
      final sure = locateSelection(page, 'תִּזְכּור: וַהֲבִיאֵנוּ', exactOnly: true)!;
      expect(sure.ambiguous, isFalse);
      expect(heRefs(sure), ['1', '2']);
      expect(
          reportLocation(
              book: _book, page: 'Weekday/Shacharit', spot: spot, date: roshChodesh, dayLabels: ['Rosh Chodesh Kislev']),
          '$_book › $_day he 1–2 · page Weekday/Shacharit · 30 Cheshvan 5787 (2026-11-10): Rosh Chodesh Kislev');
    });
  });

  test('a word in several lines of one row: where the selection starts decides', () {
    final lines = leaf(_day);
    // רָאשֵׁי (and ובראשי, וראשי) is in lines 1, 3, 5 and 6.
    final unsure = locateSelection(lines, 'רָאשֵׁי')!;
    expect(unsure.ambiguous, isTrue);
    expect(heRefs(unsure), ['1', '3', '5', '6']);
    // The row's text starts with line 1's Hebrew; an offset past lines 1–4
    // is in line 5.
    final into5 = [for (final l in lines.take(4)) stripHtml(l.he!.segment.html).length].reduce((a, b) => a + b) + 10;
    expect(lineAt(lines, into5), 4);
    final sure = locateSelection(lines, 'רָאשֵׁי', near: lineAt(lines, into5))!;
    expect(sure.ambiguous, isFalse);
    expect(heRefs(sure), ['5']);
    expect(heRefs(locateSelection(lines, 'רָאשֵׁי', near: 0)!), ['1']);
  });

  test('a selection that starts mid-word, and the English beside the Hebrew', () {
    final lines = leaf(_day);
    final he = stripHtml(lines[2].he!.segment.html);
    final en = stripHtml(lines[2].tr!.segment.html);
    // Mid-word, in the Hebrew, then the English line under it.
    final selected = '${he.substring(3, 30)}\n${en.substring(0, 25)}';
    final spot = locateSelection(lines, selected)!;
    expect(heRefs(spot), ['3']);
    expect([for (final x in spot.en) x.tr!.segment.ref], [lines[2].tr!.segment.ref]);
    expect(reportLocation(book: _book, page: 'Weekday/Shacharit', spot: spot, date: roshChodesh, dayLabels: const []),
        contains('$_day he 3 en ${lines[2].tr!.segment.ref} · '));
  });

  test('words not found as shown still name the section, marked "near"', () {
    final spot = locateSelection(leaf(_day), 'Words the reader added')!;
    expect(spot.exact, isFalse);
    expect(spot.leaves.map((n) => n.id), [_day]);
    expect(reportLocation(book: _book, page: 'Weekday/Shacharit', spot: spot, date: roshChodesh, dayLabels: const []),
        startsWith('$_book › $_day near he 1–6 · '));
    expect(locateSelection(leaf(_day), 'Words the reader added', exactOnly: true), isNull);
    expect(locateSelection(const [], 'anything'), isNull);
  });

  test('nothing to go on: the page, said plainly', () {
    expect(
        reportLocation(
            book: _book, page: 'Weekday/Shacharit', spot: null, date: roshChodesh, dayLabels: ['Rosh Chodesh Kislev'],
            chosenDate: true),
        '$_book › page Weekday/Shacharit (section not found) · chosen date 30 Cheshvan 5787 (2026-11-10): Rosh Chodesh Kislev');
  });

  test("Maariv: the Hebrew day it's said on, with the evening's civil date", () {
    // Maariv read on the evening of 9 November belongs to 30 Cheshvan.
    expect(
        reportLocation(
            book: _book,
            page: 'Weekday/Maariv',
            spot: null,
            date: roshChodesh,
            civil: DateTime(2026, 11, 9),
            dayLabels: ['Rosh Chodesh Kislev']),
        endsWith(' · 30 Cheshvan 5787 (2026-11-09): Rosh Chodesh Kislev'));
  });

  test('a long selection keeps the first section and the day within 300 characters', () {
    final musaf = [for (final s in page) if (s.node.id.startsWith(_musaf)) s];
    final spot = locateSelection(musaf, 'nothing here matches')!;
    expect(spot.leaves.length, greaterThan(5));
    final at = reportLocation(
        book: _book, page: 'Weekday/Shacharit', spot: spot, date: roshChodesh, dayLabels: ['Rosh Chodesh Kislev']);
    expect(at.length, lessThanOrEqualTo(300));
    expect(at, startsWith('$_book › $_musaf/Avot near he 1–6'));
    expect(at, matches(RegExp(r'; \+\d+ more · page Weekday/Shacharit · 30 Cheshvan 5787 \(2026-11-10\): Rosh Chodesh Kislev$')));
  });

  /// Opens Weekday Shacharit on Rosh Chodesh at Musaf's Sanctity of the Day,
  /// on a screen tall enough to show it all. [linear]: the printed linear
  /// page, which sets several lines in one row.
  Future<({int heading, Future<TextReportDialog?> Function(Future<void> Function()) report})> openSanctity(
      WidgetTester t, {bool linear = false}) async {
    t.view.physicalSize = const Size(600, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    late Storage storage;
    await t.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('report');
      addTearDown(() => dir.delete(recursive: true));
      storage = await Storage.openAt(dir.path, name: 'report');
    });
    final c = ProviderContainer(overrides: [storageProvider.overrideWithValue(storage)]);
    addTearDown(c.dispose);
    c.read(settingsProvider.notifier).update((s) => s.copyWith(
        readerCompass: false,
        titleLanguage: TitleLanguage.english,
        ashkenaziSpelling: false,
        jumpDetail: JumpDetail.sections,
        layout: TextLayout.interleaved,
        linearStyle: linear ? LinearStyle.below : LinearStyle.off));
    c.read(readerDateProvider.notifier).state = roshChodesh;
    await t.runAsync(() async {
      await c.read(bookIndexProvider(_book).future);
      await c.read(versionSelectionProvider(_book).future);
      await c.read(resolverProvider(_book).future);
    });
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: buildTheme(const AppSettings(), Brightness.light),
        builder: (context, w) => AppText(lang: UiLanguage.en, ashkenazi: false, child: w!),
        home: const ReaderScreen(book: _book, nodeId: 'Weekday/Shacharit'),
      ),
    ));
    for (var i = 0; i < 20 && find.byType(ReaderJumpBar).evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump();
    }
    final heading = t.widget<ReaderJumpBar>(find.byType(ReaderJumpBar)).points.firstWhere((p) => p.en == 'Sanctity of the Day');
    final chip = find.widgetWithText(ChoiceChip, 'Sanctity of the Day');
    await t.ensureVisible(chip);
    await t.pump();
    await t.tap(chip);
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }

    /// Opens Report on the selection made by [select], reads the form and
    /// closes it; null if nothing was selected (a press between lines).
    Future<TextReportDialog?> report(Future<void> Function() select) async {
      await select();
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final bar = find.byType(AdaptiveTextSelectionToolbar);
      if (bar.evaluate().isEmpty || find.descendant(of: bar, matching: find.text('Copy')).evaluate().isEmpty) return null;
      // On a phone, Report can be in the toolbar's overflow menu. It isn't
      // offered for a selection that's only white space.
      final more = find.descendant(of: bar, matching: find.byTooltip('More'));
      if (find.text('Report').evaluate().isEmpty && more.evaluate().isNotEmpty) {
        await t.tap(more);
        await t.pump(const Duration(milliseconds: 300));
      }
      if (find.text('Report').evaluate().isEmpty) return null;
      await t.tap(find.text('Report'));
      await t.pump(const Duration(milliseconds: 300));
      final dialog = t.widget<TextReportDialog>(find.byType(TextReportDialog));
      await t.tap(find.text('Cancel'));
      await t.pump(const Duration(milliseconds: 300));
      return dialog;
    }

    return (heading: heading.row!, report: report);
  }

  Rect rowRect(WidgetTester t, int index) =>
      t.getRect(find.byWidgetPredicate((w) => w is RowSelectionProbe && w.index == index));
  const shown = ' · page Weekday/Shacharit · chosen date 30 Cheshvan 5787 (2026-11-10): Rosh Chodesh Kislev';

  testWidgets('the reader reports the section a word is in, not just the page', (t) async {
    final r = await openSanctity(t);
    final title = rowRect(t, r.heading);
    final box = rowRect(t, r.heading + 1);
    // The first word of its first line (on the right): רָאשֵׁי, which is in
    // four of the section's lines.
    final first = (await r.report(() => t.longPressAt(Offset(box.right - 40, box.top + 30))))!;
    expect(first.label, 'Musaf Amidah for Rosh Chodesh › Sanctity of the Day');
    expect(first.text.replaceAll(RegExp('[^א-ת]'), ''), 'ראשי');
    expect(first.location, '$_book › $_day he 1$shown');

    // The section's title alone.
    final heading = (await r.report(() => t.longPressAt(rowRect(t, r.heading).center)))!;
    expect(heading.location, '$_book › $_day title$shown');

    // A mouse drag from the title into the first line, then a right click.
    final drag = (await r.report(() async {
      final g = await t.startGesture(title.center, kind: PointerDeviceKind.mouse);
      await t.pump();
      await g.moveTo(Offset(box.right - 80, box.top + 30));
      await t.pump();
      await g.up();
      await t.pump();
      // Inside the selection (the title's second half), or it collapses.
      await t.tapAt(title.center + const Offset(20, 0), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    }))!;
    // Across two rows: the end of the title and the start of the first line.
    expect(drag.text, contains('the Day'));
    expect(drag.text, contains('רָ'));
    expect(drag.location, '$_book › $_day he 1$shown');
  });

  testWidgets('on the linear page, a row of several lines: each word in its own line', (t) async {
    final r = await openSanctity(t, linear: true);
    final letters = {for (final l in leaf(_day)) l.he!.segment.ref: normalizeHebrewWords(stripHtml(l.he!.segment.html))};
    // The lines reported from each row.
    final byRow = <int, Set<String>>{};
    // Down the whole section, at the start (right) of each line of text.
    for (var y = rowRect(t, r.heading + 1).top + 20; y < 2400; y += 45) {
      final at = Offset(rowRect(t, r.heading).right - 60, y);
      final row = [
        for (final e in find.byType(RowSelectionProbe).evaluate())
          if (t.getRect(find.byWidget(e.widget)).contains(at)) (e.widget as RowSelectionProbe).index,
      ].firstOrNull;
      final got = await r.report(() => t.longPressAt(at));
      if (got == null || row == null) continue;
      final word = normalizeHebrewWords(got.text);
      if (word.isEmpty) continue; // English
      if (!got.location.startsWith('$_book › $_day ')) break; // past the section
      expect(got.location, isNot(contains('near')));
      final refs = RegExp(r' he ([\d, –]+) · ').firstMatch(got.location)?.group(1);
      expect(refs, isNotNull, reason: got.location);
      expect(refs, isNot(contains(',')), reason: '$word: ${got.location}');
      expect(letters[refs]!.split(' '), anyElement(contains(word)), reason: '$word in line $refs');
      (byRow[row] ??= {}).add(refs!);
    }
    // Some row sets more than one line, and words in each were placed.
    expect(byRow.values.any((lines) => lines.length > 1), isTrue, reason: '$byRow');
  });

  testWidgets('each row knows when it holds the selection', (t) async {
    final rows = SelectedRows();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SelectionArea(
          child: ListView(children: [
            for (var i = 0; i < 4; i++)
              RowSelectionProbe(
                  index: i, rows: rows, child: Padding(padding: const EdgeInsets.all(8), child: Text('Row number $i'))),
          ]),
        ),
      ),
    ));
    expect(rows.indexes, isEmpty);
    // Drag with a mouse from inside row 1 to inside row 2.
    final gesture = await t.startGesture(t.getTopLeft(find.text('Row number 1')) + const Offset(2, 4),
        kind: PointerDeviceKind.mouse);
    await t.pump();
    await gesture.moveTo(t.getCenter(find.text('Row number 2')));
    await t.pump();
    await gesture.up();
    await t.pumpAndSettle();
    expect(rows.indexes, [1, 2]);
    // A click elsewhere clears it.
    await t.tapAt(t.getCenter(find.text('Row number 3')), kind: PointerDeviceKind.mouse);
    await t.pumpAndSettle();
    expect(rows.indexes, isEmpty);
  });
}
