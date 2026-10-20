import 'dart:io';

import 'package:amud/core/adaptive.dart';
import 'package:amud/core/format.dart';
import 'package:amud/core/l10n.dart';
import 'package:amud/core/providers.dart';
import 'package:amud/core/settings.dart';
import 'package:amud/core/storage.dart';
import 'package:amud/core/theme.dart';
import 'package:amud/features/gemara/daf_video.dart';
import 'package:amud/features/gemara/gemara_home_screen.dart';
import 'package:amud/features/gemara/gemara_reader_screen.dart';
import 'package:amud/features/gemara/gemara_user.dart';
import 'package:amud/features/gemara/study_book.dart';
import 'package:amud/features/home/card_registry.dart';
import 'package:amud/features/home/cards/builtin_cards.dart';
import 'package:amud/features/integrations/seasonal_windows.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hebcal/hebcal.dart';
import 'package:timezone/timezone.dart' as tz;

/// The reader's app bar on a phone [width] wide at text size [scale]: four
/// tools, the link going into the menu first, then Why today?, then the date.
Future<void> _bar(WidgetTester t, double width, double scale) async {
  t.view.physicalSize = Size(width, 800);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(
          leading: const BackButton(),
          title: const Text('Shacharis'),
          actions: fitBarActions(context, 'Shacharis', spare: const [1, 0, 2], [
            for (final i in [Icons.help_outline, Icons.link, Icons.event, Icons.text_fields])
              BarTool(tooltip: '${i.codePoint}', icon: Icon(i), onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('tapped ${i.codePoint}')))),
          ]),
        ),
      ),
    ),
  ));
}

final _menu = find.byType(PopupMenuButton<VoidCallback>);

/// [child] on a phone [width] wide at text size [scale], at [now] in New
/// York, with its own storage.
Future<ProviderContainer> _phone(WidgetTester t, double width, double scale, DateTime now, Widget child) async {
  t.view.physicalSize = Size(width, 900);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  late Storage storage;
  await t.runAsync(() async {
    final dir = await Directory.systemTemp.createTemp('narrow');
    addTearDown(() => dir.delete(recursive: true));
    storage = await Storage.openAt(dir.path, name: 'narrow');
  });
  final c = ProviderContainer(overrides: [storageProvider.overrideWithValue(storage), nowProvider.overrideWith((ref) => Stream.value(now))]);
  addTearDown(c.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: buildTheme(const AppSettings(), Brightness.light),
      builder: (context, w) => AppText(lang: UiLanguage.en, ashkenazi: true, child: w!),
      home: child,
    ),
  ));
  await t.pump();
  return c;
}

/// A dashboard card of [type], [span] columns of a two-column phone.
Widget _card(String type, {int span = 2, Map<String, Object?> settings = const {}}) {
  final r = CardRegistry();
  registerBuiltInCards(r);
  registerSeasonalCards(r);
  return Scaffold(
    body: LayoutBuilder(builder: (context, c) {
      final w = span == 2 ? c.maxWidth - 24 : (c.maxWidth - 36) / 2;
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: w,
            child: Consumer(builder: (context, ref, _) {
              final t = r[type]!;
              return t.build(context, ref, CardConfig(id: 'x', type: type, span: span, settings: {...t.defaults, ...settings}));
            }),
          ),
        ),
      );
    }),
  );
}

/// Whether [text] is set whole: no line cut short with an ellipsis.
bool _whole(WidgetTester t, String text) => !t.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines;

/// Whether no word of [text] breaks mid-word: it's set at least as wide as
/// its longest word.
bool _unbroken(WidgetTester t, String text) {
  final p = t.renderObject<RenderParagraph>(find.text(text));
  return p.size.width >= p.getMinIntrinsicWidth(double.infinity);
}

DateTime _ny(int y, int m, int d, int h) => tz.TZDateTime(tz.getLocation('America/New_York'), y, m, d, h);

void main() {
  setUpAll(initHebcal);

  testWidgets('every tool on the bar where the title has room', (t) async {
    await _bar(t, 412, 1);
    expect(_menu, findsNothing);
    for (final i in [Icons.help_outline, Icons.link, Icons.event, Icons.text_fields]) {
      expect(find.byIcon(i), findsOneWidget);
    }
  });

  testWidgets('on a 360dp Samsung the link and Why today? go in a menu', (t) async {
    await _bar(t, 360, 1);
    expect(_menu, findsOneWidget);
    expect(find.byIcon(Icons.link), findsNothing);
    expect(find.byIcon(Icons.help_outline), findsNothing);
    expect(find.byIcon(Icons.event), findsOneWidget);
    expect(find.byIcon(Icons.text_fields), findsOneWidget);

    // Still there, and still work, from the menu.
    await t.tap(_menu);
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.link), findsOneWidget);
    await t.tap(find.byIcon(Icons.link));
    await t.pumpAndSettle();
    expect(find.text('tapped ${Icons.link.codePoint}'), findsOneWidget);
  });

  testWidgets('narrower still, with large text, only text settings stay', (t) async {
    await _bar(t, 320, 1.3);
    expect(_menu, findsOneWidget);
    expect(find.byIcon(Icons.event), findsNothing);
    expect(find.byIcon(Icons.text_fields), findsOneWidget);
  });

  test('a time never leaves AM or PM on a line of its own', () {
    final loc = SavedLocation.newYork.toLocation();
    expect(formatTime(tz.TZDateTime(loc.tzLocation, 2026, 10, 19, 15, 22), loc, hour12: true), '3:22 PM');
  });

  testWidgets('in a Hebrew interface a time reads "3:22 PM", not "PM 3:22"', (t) async {
    final loc = SavedLocation.newYork.toLocation();
    dateLocale = 'he';
    addTearDown(() => dateLocale = 'en');
    final text = 'היום: ${formatTime(tz.TZDateTime(loc.tzLocation, 2026, 10, 19, 15, 22), loc, hour12: true)}';
    final p = TextPainter(text: TextSpan(text: text), textDirection: TextDirection.rtl)..layout();
    addTearDown(p.dispose);
    double left(String s) {
      final i = text.indexOf(s);
      return p.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1)).first.left;
    }

    expect(left('3'), lessThan(left('P')));
    // And the Hebrew still comes first, on the right.
    expect(left('3'), lessThan(left('ה')));
  });

  test('a Hebrew date wraps whole', () {
    expect(keepTogether('ח׳ חשון תשפ״ז'), 'ח׳ חשון תשפ״ז');
  });

  group('Kiddush Levana, Daf Yomi video', () {
    testWidgets('“Not open yet” goes under the card’s name rather than cutting it', (t) async {
      // Thursday before Tammuz 5787's window, which opens Motzei Shabbos.
      // (The test font's letters are about twice as wide as Roboto's, so
      // 360dp here is tighter than 320dp with 1.3× text on a phone.)
      await _phone(t, 360, 1, _ny(2027, 7, 8, 12), _card('levanaWindow'));
      expect(find.text('Not open yet'), findsOneWidget);
      expect(_whole(t, 'Kiddush Levanah window'), isTrue);
      expect(t.getTopLeft(find.text('Not open yet')).dy, greaterThanOrEqualTo(t.getTopLeft(find.text('Kiddush Levanah window')).dy));
      await _phone(t, 412, 1, _ny(2027, 7, 8, 12), _card('levanaWindow'));
      expect(_whole(t, 'Kiddush Levanah window'), isTrue);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 20));
    });

    testWidgets("the Gemara's Continue and Daf Yomi stack where they don't fit side by side", (t) async {
      dafVideoIndex.value = {'bekhorot': {'31'}};
      addTearDown(() => dafVideoIndex.value = const {});
      Future<double> rise(double width, double scale) async {
        final c = await _phone(t, width, scale, _ny(2026, 10, 19, 12), const StudyHomeScreen(kind: StudyKind.bavli));
        c.read(gemaraMarksProvider.notifier).visit(const DafPlace('Bekhorot', '30b'));
        await t.pump();
        expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
        return t.getTopLeft(find.text('Daf Yomi')).dy - t.getTopLeft(find.text('Continue')).dy;
      }

      expect(await rise(320, 1.3), greaterThan(20));
      expect(await rise(900, 1), 0);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 20));
    });

    testWidgets("the reader's bar keeps the daf's name, the rest in a menu", (t) async {
      dafVideoIndex.value = {'bekhorot': {'31'}};
      addTearDown(() => dafVideoIndex.value = const {});
      await _phone(t, 320, 1.3, _ny(2026, 10, 19, 12), const GemaraReaderScreen(tractate: 'Bekhorot', amud: '31a'));
      expect(_menu, findsOneWidget);
      expect(find.byIcon(Icons.link), findsNothing);
      // A wide window has room for everything, the video among them.
      await _phone(t, 1200, 1, _ny(2026, 10, 19, 12), const GemaraReaderScreen(tractate: 'Bekhorot', amud: '31a'));
      expect(_menu, findsNothing);
      expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
      expect(find.byIcon(Icons.link), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 20));
    });

    testWidgets('on a compact learning card the video goes under Daf Yomi', (t) async {
      dafVideoIndex.value = {'bekhorot': {'31'}};
      addTearDown(() => dafVideoIndex.value = const {});
      await _phone(t, 320, 1.3, _ny(2026, 10, 19, 12), _card('learning', span: 1, settings: const {'schedules': ['dafYomi']}));
      expect(t.getTopLeft(find.byIcon(Icons.movie_outlined)).dy, greaterThan(t.getTopLeft(find.text('Daf Yomi (Bavli)')).dy + 10));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 20));
    });
  });

  testWidgets('a compact minyan card shrinks GoDaven rather than breaking it, the link beside it', (t) async {
    await _phone(t, 320, 1.3, _ny(2026, 10, 19, 12), _card('minyan', span: 1));
    expect(_unbroken(t, 'GoDaven'), isTrue);
    expect(_unbroken(t, 'Minyanim near New York'), isTrue);
    // Not on a line of its own under the card's name.
    final name = t.getRect(find.text('GoDaven'));
    expect(t.getCenter(find.byIcon(Icons.open_in_new)).dy, inInclusiveRange(name.top, name.bottom));

    // Where there's room, the link stays beside the card's name and GoDaven
    // keeps its size.
    await _phone(t, 412, 1, _ny(2026, 10, 19, 12), _card('minyan'));
    final heading = t.getRect(find.text('Find a minyan'));
    expect(t.getCenter(find.byIcon(Icons.open_in_new)).dy, inInclusiveRange(heading.top, heading.bottom));
    expect(t.getRect(find.text('GoDaven')).width, closeTo(t.getSize(find.text('GoDaven')).width, 0.01));
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 20));
  });
}
