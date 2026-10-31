import 'dart:io';

import 'package:amud/core/l10n.dart';
import 'package:amud/core/providers.dart';
import 'package:amud/core/settings.dart';
import 'package:amud/core/storage.dart';
import 'package:amud/core/theme.dart';
import 'package:amud/features/siddur/reader_jump.dart';
import 'package:amud/features/siddur/reader_screen.dart';
import 'package:amud/features/siddur/siddur_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hebcal/hebcal.dart';

/// The jump bar's points, reading [node] of the Ashkenaz siddur on a
/// Tuesday with [settings]; "| " marks one set off as a new part.
Future<List<String>> _chips(WidgetTester t, AppSettings settings, {String node = 'Weekday/Shacharit'}) async {
  t.view.physicalSize = const Size(360, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  late Storage storage;
  await t.runAsync(() async {
    final dir = await Directory.systemTemp.createTemp('jump');
    addTearDown(() => dir.delete(recursive: true));
    storage = await Storage.openAt(dir.path, name: 'jump');
  });
  final c = ProviderContainer(overrides: [storageProvider.overrideWithValue(storage)]);
  addTearDown(c.dispose);
  c.read(settingsProvider.notifier).update((_) => settings.copyWith(readerCompass: false));
  // An ordinary Tuesday: 16 Cheshvan 5787, 27 October 2026.
  final tuesday = HDate(16, Months.cheshvan, 5787);
  expect(tuesday.getDay(), 2);
  c.read(readerDateProvider.notifier).state = tuesday;
  await t.runAsync(() async {
    await c.read(bookIndexProvider('Siddur Ashkenaz').future);
    await c.read(versionSelectionProvider('Siddur Ashkenaz').future);
    await c.read(resolverProvider('Siddur Ashkenaz').future);
  });
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: buildTheme(const AppSettings(), Brightness.light),
      builder: (context, w) => AppText(lang: UiLanguage.en, ashkenazi: settings.ashkenaziSpelling, child: w!),
      home: ReaderScreen(book: 'Siddur Ashkenaz', nodeId: node),
    ),
  ));
  for (var i = 0; i < 20 && find.byType(ReaderJumpBar).evaluate().isEmpty; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
  }
  final bar = find.byType(ReaderJumpBar);
  expect(bar, findsOneWidget);
  final points = t.widget<ReaderJumpBar>(bar).points;
  final chips = t.widgetList<ChoiceChip>(find.descendant(of: bar, matching: find.byType(ChoiceChip))).toList();
  expect(chips, hasLength(points.length));
  return [
    for (final (i, p) in points.indexed) '${p.part ? '| ' : ''}${(chips[i].label as Text).data}',
  ];
}

void main() {
  test('Shomer Yisrael is not Sefirat HaOmer', () {
    expect(keyPointFor('Shomer Yisrael'), isNull);
    expect(keyPointFor('Sefirat HaOmer')?.$1, 'Sefirat HaOmer');
    expect(keyPointFor('Counting of the Omer')?.$1, 'Sefirat HaOmer');
    expect(keyPointFor('Weekday Maariv/Sefirat HaOmer')?.$1, 'Sefirat HaOmer');
  });

  testWidgets('the jump bar offers the key points', (t) async {
    final key = await _chips(t, const AppSettings(titleLanguage: TitleLanguage.english, ashkenaziSpelling: false));
    expect(key, containsAllInOrder(['Pesukei DeZimra', 'Shema', 'Shemoneh Esrei', 'Aleinu']));
    expect(key, isNot(contains('Tefillin')));
  });

  testWidgets('or every section of the service', (t) async {
    final every = await _chips(t, const AppSettings(titleLanguage: TitleLanguage.english, ashkenaziSpelling: false, jumpDetail: JumpDetail.sections));
    expect(every, containsAllInOrder(['Preparatory Prayers', 'Modeh Ani', 'Tallit', 'Tefillin', '| Pesukei Dezimra', "Barukh She'amar",
        'Psalm 146', 'Yishtabach', '| Blessings of the Shema', 'Shema', '| Amidah', 'Patriarchs', 'Kedushah', 'Healing', 'Modim DeRabbanan',
        'Birkat Kohanim', 'Peace', '| Post Amidah', 'Tachanun', '| Concluding Prayers', 'Alenu', 'Song of the Day']));
    expect(every.where((p) => p.startsWith('| ')), hasLength(5));
    // Not said on an ordinary Tuesday: hidden, so not in the bar either.
    expect(every, isNot(contains('Avinu Malkenu')));
    expect(every, isNot(contains('Barchi Nafshi')));
    expect(every, isNot(contains('Birkat Hagomel')));
    expect(every.length, greaterThan(40));
  });

  testWidgets('every psalm of Pesukei DeZimra, opened by itself, without dividers', (t) async {
    final psalms = await _chips(t, const AppSettings(ashkenaziSpelling: false, jumpDetail: JumpDetail.sections),
        node: 'Weekday/Shacharit/Pesukei Dezimra');
    expect(psalms, containsAllInOrder(["Barukh She'amar", 'Hodu', 'Ashrei', 'Psalm 150', 'Az Yashir', 'Yishtabach']));
    expect(psalms.where((p) => p.startsWith('| ')), isEmpty);
  });

  testWidgets('every section, in the Ashkenazi spelling', (t) async {
    final ashkenazi = await _chips(t, const AppSettings(titleLanguage: TitleLanguage.english, jumpDetail: JumpDetail.sections, ashkenaziSpelling: true));
    expect(ashkenazi, containsAllInOrder(['Netilas Yadayim', 'Tzitzis', 'Tallis', 'Tefillin', 'Birchas Kohanim']));
  });
}
