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
import 'package:amud/features/home/home_screen.dart';
import 'package:amud/features/integrations/seasonal_windows.dart';
import 'package:amud/features/siddur/meein_shalosh_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hebcal/hebcal.dart';
import 'package:timezone/timezone.dart' as tz;

/// The reader's app bar on a phone [width] wide at text size [scale]: four
/// tools, the link going into the menu first, then Why today?, then the date.
/// With the [compass] first, text settings can go too.
Future<void> _bar(WidgetTester t, double width, double scale, {bool compass = false}) async {
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
          actions: fitBarActions(context, 'Shacharis', spare: compass ? const [2, 1, 3, 4] : const [1, 0, 2], [
            if (compass) const BarTool.custom(SizedBox(key: Key('compass'), width: 48, height: 48)),
            for (final i in [Icons.help_outline, Icons.link, Icons.event, Icons.text_fields])
              BarTool(tooltip: '${i.codePoint}', icon: Icon(i), onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('tapped ${i.codePoint}')))),
          ]),
        ),
      ),
    ),
  ));
}

final _menu = find.byType(PopupMenuButton<VoidCallback>);

/// [child] on a phone [width] wide (and [height] tall) at text size
/// [scale], at [now] in New York, with its own storage.
Future<ProviderContainer> _phone(WidgetTester t, double width, double scale, DateTime now, Widget child, {double height = 900}) async {
  t.view.physicalSize = Size(width, height);
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

/// Me'ein Shalosh's text: how much it's scaled down, where it's shown, the
/// card it's in, and the page's scroll position.
({double scale, Rect text, Rect card, ScrollPosition scroll}) _bracha(WidgetTester t) {
  final card = find.byType(Card);
  final text = find.descendant(of: card, matching: find.byType(Directionality)).first;
  final rect = t.getRect(text);
  return (scale: rect.width / t.renderObject<RenderBox>(text).size.width, text: rect, card: t.getRect(card), scroll: Scrollable.of(t.element(text)).position);
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

  testWidgets('the compass toward Jerusalem takes no room from the title; at 320dp text settings goes in the menu', (t) async {
    double title() => t.getSize(find.text('Shacharis')).width;
    for (final (width, scale) in [(360.0, 1.0), (320.0, 1.3)]) {
      await _bar(t, width, scale);
      final without = title();
      await _bar(t, width, scale, compass: true);
      expect(find.byKey(const Key('compass')), findsOneWidget);
      expect(title(), without);
    }
    expect(find.byIcon(Icons.text_fields), findsNothing);
    await _bar(t, 360, 1, compass: true);
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
    testWidgets('the card’s name is whole, with no status badge beside it', (t) async {
      // Thursday before Tammuz 5787's window, which opens Motzei Shabbos.
      // (The test font's letters are about twice as wide as Roboto's, so
      // 360dp here is tighter than 320dp with 1.3× text on a phone.)
      await _phone(t, 360, 1, _ny(2027, 7, 8, 12), _card('levanaWindow'));
      // The color and "Opens …" say it's not open yet.
      expect(find.text('Not open yet'), findsNothing);
      expect(_whole(t, 'Kiddush Levanah window'), isTrue);
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

  for (final (width, scale) in [(360.0, 1.3), (320.0, 1.3), (412.0, 1.0)]) {
    testWidgets('editing the dashboard at ${width}dp, $scale× text: each card with its controls, its settings with a preview', (t) async {
      t.view.physicalSize = Size(width, 900);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(t.view.reset);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      late Storage storage;
      await t.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('narrow');
        addTearDown(() => dir.delete(recursive: true));
        // Its own box: Hive keeps one per name open between tests.
        storage = await Storage.openAt(dir.path, name: 'dashboard${width.toInt()}');
        await storage.writeJson('dashboardVersion', 4);
        await storage.writeJson('dashboard', [
          const CardConfig(id: 'a', type: 'levanaWindow', span: 2, settings: {'onlyWhenOpen': true}).toJson(),
          const CardConfig(id: 'b', type: 'hachamaWindow').toJson(),
          const CardConfig(id: 'c', type: 'nextZman').toJson(),
        ]);
      });
      final r = CardRegistry();
      registerBuiltInCards(r);
      registerSeasonalCards(r);
      final c = ProviderContainer(overrides: [
        storageProvider.overrideWithValue(storage),
        cardRegistryProvider.overrideWithValue(r),
        nowProvider.overrideWith((ref) => Stream.value(_ny(2027, 7, 1, 12))),
      ]);
      addTearDown(c.dispose);
      await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: buildTheme(const AppSettings(), Brightness.light),
          builder: (context, w) => AppText(lang: UiLanguage.en, ashkenazi: true, child: w!),
          home: const HomeScreen(),
        ),
      ));
      await t.pump();
      // Kiddush Levana is closed, so hidden until editing.
      expect(find.text('Kiddush Levanah window'), findsNothing);
      await t.tap(find.text('Edit dashboard'));
      await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
      expect(find.text('Kiddush Levanah window'), findsOneWidget);
      expect(find.byTooltip('Remove'), findsNWidgets(3));
      expect(t.takeException(), isNull);
      // Moving the second card first.
      await t.ensureVisible(find.byTooltip('Move earlier').at(1));
      await t.pump();
      await t.tap(find.byTooltip('Move earlier').at(1));
      await t.pump();
      expect([for (final x in c.read(dashboardProvider)) x.id], ['b', 'a', 'c']);
      // Its settings, with the card above them, follow the size chosen.
      // (The card itself takes no taps while editing: they open its settings.)
      await t.ensureVisible(find.text('Kiddush Levanah window'));
      await t.pump();
      await t.tap(find.text('Kiddush Levanah window'), warnIfMissed: false);
      await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
      expect(find.text('Kiddush Levanah window'), findsNWidgets(2));
      final preview = find.ancestor(of: find.text('Kiddush Levanah window').last, matching: find.byType(Card));
      final wide = t.getSize(preview).width;
      await t.tap(find.text('Compact'));
      await t.pump();
      expect(t.takeException(), isNull);
      // One column at 1.3× text, where compact cards are full width too.
      expect(t.getSize(preview).width, scale > 1 ? wide : lessThan(wide));
      expect(t.getRect(find.text('Save')).bottom, lessThan(900));
      await t.tap(find.text('Save'));
      await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
      expect(c.read(dashboardProvider).firstWhere((x) => x.id == 'a').span, 1);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 20));
    });
  }

  group("Me'ein Shalosh", () {
    testWidgets('on an ordinary phone the bracha still fits without scrolling', (t) async {
      await _phone(t, 360, 1.0, _ny(2026, 11, 3, 12), const MeeinShaloshScreen(), height: 780);
      await t.pumpAndSettle();
      expect(_bracha(t).scroll.maxScrollExtent, 0);
      await t.tap(find.text('Al HaMichya'));
      await t.pumpAndSettle();
      expect(_bracha(t).scroll.maxScrollExtent, 0);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 20));
    });

    for (final (w, h) in [(240.0, 320.0), (320.0, 240.0)]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('on a ${w.toInt()}×${h.toInt()} flip phone, $scale× text, it scrolls rather than shrink past reading or cut off the end', (t) async {
          await _phone(t, w, scale, _ny(2026, 11, 3, 12), const MeeinShaloshScreen(), height: h);
          await t.pumpAndSettle();
          for (final pick in [null, 'Al HaMichya']) {
            if (pick != null) {
              await t.tap(find.text(pick));
              await t.pumpAndSettle();
            }
            var b = _bracha(t);
            expect(b.scale, greaterThanOrEqualTo(0.449), reason: 'text scaled to ${b.scale}');
            expect(b.scroll.maxScrollExtent, greaterThan(0));
            b.scroll.jumpTo(b.scroll.maxScrollExtent);
            await t.pump();
            b = _bracha(t);
            // The whole bracha is inside its card, and the card's end is on screen.
            expect(b.text.bottom, lessThanOrEqualTo(b.card.bottom));
            expect(b.card.bottom, lessThanOrEqualTo(h));
            b.scroll.jumpTo(0);
            await t.pump();
          }
          await t.pumpWidget(const SizedBox());
          await t.pump(const Duration(seconds: 20));
        });
      }
    }

    testWidgets("a flip phone's keypad scrolls it down and back up", (t) async {
      await _phone(t, 240, 1.0, _ny(2026, 11, 3, 12), const MeeinShaloshScreen(), height: 320);
      await t.pumpAndSettle();
      final scroll = _bracha(t).scroll;
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      final down = scroll.pixels;
      expect(down, greaterThan(0));
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      expect(scroll.pixels, greaterThan(down));
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pumpAndSettle();
      expect(scroll.pixels, 0);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 20));
    });
  });
}
