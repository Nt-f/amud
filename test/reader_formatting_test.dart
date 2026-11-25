import 'dart:io';

import 'package:amud/core/l10n.dart';
import 'package:amud/core/providers.dart';
import 'package:amud/core/settings.dart';
import 'package:amud/core/storage.dart';
import 'package:amud/core/theme.dart';
import 'package:amud/core/typeset/typeset.dart';
import 'package:amud/features/siddur/reader_screen.dart';
import 'package:amud/features/siddur/reader_typography.dart';
import 'package:amud/features/siddur/siddur_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hebcal/hebcal.dart';

// An ordinary Tuesday, and Rosh Chodesh Kislev.
final _tuesday = HDate(16, Months.cheshvan, 5787);
final _roshChodesh = HDate(30, Months.cheshvan, 5787);

/// Opens [node] of [book] for [date] on a phone [width] wide with text at
/// [scale], tall enough to build the whole section.
Future<void> _read(WidgetTester t, String book, String node, HDate date, {double width = 400, double scale = 1}) async {
  t.view.physicalSize = Size(width, 4000);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  late Storage storage;
  await t.runAsync(() async {
    final dir = await Directory.systemTemp.createTemp('formatting');
    addTearDown(() => dir.delete(recursive: true));
    storage = await Storage.openAt(dir.path, name: 'formatting');
  });
  final c = ProviderContainer(overrides: [storageProvider.overrideWithValue(storage)]);
  addTearDown(c.dispose);
  c.read(settingsProvider.notifier).update((s) => s.copyWith(readerCompass: false));
  c.read(readerDateProvider.notifier).state = date;
  await t.runAsync(() async {
    await c.read(bookIndexProvider(book).future);
    await c.read(versionSelectionProvider(book).future);
    await c.read(resolverProvider(book).future);
  });
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: buildTheme(const AppSettings(), Brightness.light),
      builder: (context, w) => AppText(lang: UiLanguage.en, ashkenazi: false, child: w!),
      home: ReaderScreen(book: book, nodeId: node),
    ),
  ));
  for (var i = 0; i < 20 && find.byType(TypesetParagraph).evaluate().isEmpty; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
  }
  expect(find.byType(TypesetParagraph), findsWidgets);
}

/// The paragraph whose words (as [normalizeHebrewWords] gives them) start
/// with [words].
Finder _paragraph(String words) => find.byWidgetPredicate(
    (w) => w is TypesetParagraph && normalizeHebrewWords(w.text.toPlainText()).startsWith(words), description: 'paragraph "$words"');

TypesetParagraph _widget(WidgetTester t, String words) {
  expect(_paragraph(words), findsOneWidget);
  return t.widget<TypesetParagraph>(_paragraph(words));
}

/// The text's own spans, in order.
List<TextSpan> _spans(InlineSpan text) {
  final out = <TextSpan>[];
  text.visitChildren((s) {
    if (s is TextSpan && (s.text ?? '').trim().isNotEmpty) out.add(s);
    return true;
  });
  return out;
}

void main() {
  for (final (book, node) in [
    ('Siddur Ashkenaz', 'Weekday/Minchah/Amida/Concluding Passage'),
    ('Siddur Sefard', 'Weekday Mincha/Amidah/Concluding Passage'),
  ]) {
    testWidgets('$book: "יהיו לרצון" on its own line is plain and centered, and אלהי נצור opens', (t) async {
      await _read(t, book, node, _tuesday);
      // Before אלהי נצור, and in Sefard after it too.
      final verses = t.widgetList<TypesetParagraph>(_paragraph('יהיו לרצון')).toList();
      expect(verses, isNotEmpty);
      final size = _spans(verses.first.text).first.style?.fontSize;
      for (final verse in verses) {
        expect(verse.align, ParagraphAlign.center);
        for (final s in _spans(verse.text)) {
          expect(s.style?.fontWeight, isNot(FontWeight.bold), reason: s.text);
          expect(s.style?.fontSize, size, reason: s.text);
        }
      }
      // The large first word is אלהי's.
      final elokai = _spans(_widget(t, 'אלהי נצור').text);
      expect(elokai.first.style!.fontSize!, greaterThan(size!));
    });
  }

  testWidgets("Modim DeRabbanan is set as a paragraph, not faded with the reader's repetition", (t) async {
    await _read(t, 'Siddur Ashkenaz', 'Weekday/Minchah/Amida/Thanksgiving', _tuesday);
    final header = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_ChazarahHeader');
    if (_paragraph('מודים אנחנו לך שאתה הוא ה אלהינו ואלהי אבותינו אלהי כל בשר').evaluate().isEmpty) {
      await t.tap(header.first);
      await t.pump();
    }
    final modim = _paragraph('מודים אנחנו לך שאתה הוא ה אלהינו ואלהי אבותינו אלהי כל בשר');
    expect(t.widget<TypesetParagraph>(modim).align, isNot(ParagraphAlign.end));
    expect(find.ancestor(of: modim, matching: find.byWidgetPredicate((w) => w is Opacity && w.opacity < 1)), findsNothing);
  });

  for (final (width, scale) in [(400.0, 1.0), (360.0, 1.3), (320.0, 1.3)]) {
    testWidgets('on Rosh Chodesh, "לר"ח:" is highlighted one line tall with its words (${width.toInt()} wide, text ×$scale)', (t) async {
      await _read(t, 'Siddur Ashkenaz', 'Weekday/Minchah/Amida/Temple Service', _roshChodesh, width: width, scale: scale);
      final label = find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().trim() == 'לר"ח:');
      expect(label, findsOneWidget);
      final box = find.ancestor(of: label, matching: find.byWidgetPredicate((w) => w is Container && w.color != null)).first;
      // Its words: highlighted, in the same paragraph.
      final paragraph = t.widget<TypesetParagraph>(find.ancestor(of: box, matching: find.byType(TypesetParagraph)));
      final words = _spans(paragraph.text).firstWhere((s) => s.style?.backgroundColor != null && s.text!.contains('רֹאשׁ'));
      expect(t.widget<Container>(box).color, words.style!.backgroundColor);
      final line = words.style!.fontSize! * words.style!.height! * scale;
      expect(t.getRect(box).height, moreOrLessEquals(line, epsilon: 1.5));
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('on an ordinary day there is no box', (t) async {
    await _read(t, 'Siddur Ashkenaz', 'Weekday/Minchah/Amida/Temple Service', _tuesday);
    expect(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('לר"ח')), findsNothing);
  });
}
