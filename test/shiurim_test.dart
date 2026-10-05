import 'dart:io';

import 'package:amud/core/providers.dart';
import 'package:amud/core/settings.dart';
import 'package:amud/core/storage.dart';
import 'package:amud/core/theme.dart';
import 'package:amud/features/settings/nav_tabs_screen.dart';
import 'package:amud/features/shiurim/shiurim_data.dart';
import 'package:amud/features/shiurim/shiurim_screen.dart';
import 'package:amud/features/shiurim/shiurim_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  double c(Measure m, num amount, String from, String to, {String? by, Map<String, String> unitOpinions = const {}}) =>
      convert(m, amount.toDouble(), m.unit(from), m.unit(to), opinion: by == null ? null : m.opinion(by), unitOpinions: unitOpinions);

  test("each posek's amah and its parts", () {
    expect(c(length, 1, 'amah', 'cm', by: 'naeh'), closeTo(48, 1e-9));
    expect(c(length, 1, 'tefach', 'cm', by: 'naeh'), closeTo(8, 1e-9));
    expect(c(length, 1, 'etzba', 'cm', by: 'naeh'), closeTo(2, 1e-9));
    expect(c(length, 1, 'amah', 'in', by: 'feinstein'), closeTo(21.25, 1e-9));
    expect(c(length, 1, 'tefach', 'cm', by: 'chazonIsh'), closeTo(9.62, 1e-9));
    expect(c(length, 1, 'amah', 'in', by: 'aruchHashulchan'), closeTo(21, 1e-9));
    // Units between themselves are the same by every opinion.
    for (final o in length.opinions!) {
      expect(c(length, 1, 'mil', 'amah', by: o.id), closeTo(2000, 1e-6));
      expect(c(length, 1, 'parsah', 'mil', by: o.id), closeTo(4, 1e-9));
      expect(c(length, 1, 'mil', 'ris', by: o.id), closeTo(7.5, 1e-9));
    }
    // A techum: 2000 amos.
    expect(c(length, 2000, 'amah', 'm', by: 'naeh'), closeTo(960, 1e-6));
    expect(c(length, 2000, 'amah', 'm', by: 'feinstein'), closeTo(1079.5, 1e-6));
  });

  test('areas are the amah squared', () {
    expect(c(area, 1, 'amahSq', 'm2', by: 'naeh'), closeTo(0.2304, 1e-9));
    expect(c(area, 1, 'beisSeah', 'amahSq', by: 'naeh'), closeTo(2500, 1e-6));
    expect(c(area, 1, 'beisSeah', 'm2', by: 'naeh'), closeTo(576, 1e-6));
    expect(c(area, 1, 'beisKor', 'beisSeah', by: 'naeh'), closeTo(30, 1e-9));
  });

  test("volumes from each posek's beitzah, in the Gemara's ratios", () {
    expect(c(volume, 1, 'reviis', 'ml', by: 'naeh'), closeTo(86.4, 1e-9));
    expect(c(volume, 1, 'reviis', 'ml', by: 'chazonIsh'), closeTo(150, 1e-9));
    expect(c(volume, 1, 'reviis', 'flOz', by: 'feinstein'), closeTo(3.3, 1e-9));
    expect(c(volume, 1, 'kezayis', 'ml', by: 'naeh'), closeTo(28.8, 1e-9));
    expect(c(volume, 1, 'log', 'reviis', by: 'naeh'), closeTo(4, 1e-9));
    expect(c(volume, 1, 'kav', 'log', by: 'naeh'), closeTo(4, 1e-9));
    expect(c(volume, 1, 'seah', 'kav', by: 'naeh'), closeTo(6, 1e-9));
    expect(c(volume, 1, 'ephah', 'seah', by: 'naeh'), closeTo(3, 1e-9));
    expect(c(volume, 1, 'kor', 'seah', by: 'naeh'), closeTo(30, 1e-9));
    expect(c(volume, 1, 'ephah', 'omer', by: 'naeh'), closeTo(10, 1e-9));
    expect(c(volume, 1, 'omer', 'beitzah', by: 'naeh'), closeTo(43.2, 1e-9));
  });

  test('coins in silver, and time', () {
    expect(c(coins, 1, 'perutah', 'g', by: 'shulchanAruch'), closeTo(0.024, 1e-12));
    expect(c(coins, 1, 'sela', 'g', by: 'shulchanAruch'), closeTo(18.432, 1e-9));
    expect(c(coins, 1, 'dinar', 'maah', by: 'rashi'), closeTo(6, 1e-9));
    expect(c(time, 1, 'mil', 'min'), 18);
    expect(c(time, 1, 'mil', 'min', unitOpinions: {'mil': '22.5'}), 22.5);
    expect(c(time, 1, 'pras', 'min', unitOpinions: {'pras': '9'}), 9);
    expect(c(time, 1, 'shaah', 'chelek'), closeTo(1080, 1e-9));
    expect(c(time, 1, 'chelek', 'rega'), closeTo(76, 1e-9));
  });

  test('every figure has a source, and every unit a unique id', () {
    for (final m in measures) {
      expect(m.basis, isNotEmpty);
      expect({for (final u in m.units) u.id}, hasLength(m.units.length), reason: m.id);
      for (final o in [...?m.opinions, for (final u in m.units) ...?u.opinions]) {
        expect(o.source, isNotEmpty, reason: '${m.id} ${o.id}');
        expect(o.value, greaterThan(0));
      }
    }
    for (final s in commonShiurim) {
      expect(s.rulings, isNotEmpty);
      for (final r in s.rulings) {
        expect(r.source, isNotEmpty, reason: '${s.id} ${r.en}');
      }
    }
  });

  test("the common shiurim as each posek ruled, not as the ratios give", () {
    final kezayis = commonShiurim.firstWhere((s) => s.id == 'kezayis');
    const naeh = ShiurimSettings();
    expect(naeh.leading(kezayis).value, 27);
    expect(naeh.copyWith(follow: 'feinstein').leading(kezayis).value, 31.2);
    expect(naeh.copyWith(follow: 'chazonIsh').leading(kezayis).value, 33.3);
    final reviis = commonShiurim.firstWhere((s) => s.id == 'reviis');
    expect(naeh.leading(reviis).value, 86);
    expect(naeh.copyWith(follow: 'chazonIsh').leading(reviis).value, 150);
    // His Friday-night figure is an alternative, not his main one.
    expect(naeh.copyWith(follow: 'feinstein').leading(reviis).value, closeTo(97.6, 0.01));
    final techum = commonShiurim.firstWhere((s) => s.id == 'techum');
    expect(naeh.leading(techum).value, closeTo(960, 1e-6));
    final mil = commonShiurim.firstWhere((s) => s.id == 'mil');
    expect(naeh.leading(mil).value, 18);
    expect(naeh.copyWith(mil: '24').leading(mil).value, 24);
  });

  test('settings choose defaults, and ignore what they don\'t know', () {
    const s = ShiurimSettings();
    expect(s.opinionFor(length)?.id, 'naeh');
    expect(s.copyWith(follow: 'chazonIsh').opinionFor(volume)?.id, 'chazonIsh');
    // Coins have no posek of these; their own default.
    expect(s.opinionFor(coins)?.id, 'shulchanAruch');
    expect(s.opinionFor(time), isNull);
    final read = ShiurimSettings.fromJson({'follow': 'someone', 'mil': '22.5', 'silverPerGram': 1.05, 'currency': '₪'});
    expect(read.follow, 'naeh');
    expect(read.mil, '22.5');
    expect(read.silverPerGram, 1.05);
    expect(ShiurimSettings.fromJson(read.toJson()).currency, '₪');
  });

  test('amounts are shown with useful digits', () {
    expect(formatAmount(86.4), '86.4');
    expect(formatAmount(150), '150');
    expect(formatAmount(28.8), '28.8');
    expect(formatAmount(2.92), '2.92');
    expect(formatAmount(0.024), '0.024');
    expect(formatAmount(1154.4), '1,154');
    expect(formatAmount(48), '48');
  });

  test('the Shiurim tab can be put on the bar, and is saved', () {
    expect({for (final t in navTabs) t.$1}, allNavTabIds);
    final s = AppSettings.fromJson({'navTabs': ['home', 'shiurim', 'settings']});
    expect(s.navTabs, ['home', 'shiurim', 'settings']);
    // Not on the bar unless chosen.
    expect(const AppSettings().navTabs, isNot(contains('shiurim')));
  });

  testWidgets('the screen leads with the posek followed, and converts', (tester) async {
    late ProviderContainer c;
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('shiurim');
      c = ProviderContainer(overrides: [storageProvider.overrideWithValue(await Storage.openAt(dir.path))]);
    });
    addTearDown(c.dispose);
    await tester.binding.setSurfaceSize(const Size(500, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: buildTheme(c.read(settingsProvider), Brightness.light), home: const ShiurimScreen()),
    ));
    expect(find.text("Following Rav Chaim Na'eh"), findsOneWidget);
    expect(find.text('27 ml · 0.913 fl oz'), findsOneWidget);
    expect(find.text('86 ml · 2.91 fl oz'), findsOneWidget);

    // Following the Chazon Ish instead.
    c.read(shiurimSettingsProvider.notifier).update((x) => x.copyWith(follow: 'chazonIsh'));
    await tester.pump();
    expect(find.text('33.3 ml · 1.13 fl oz'), findsOneWidget);
    expect(find.text('150 ml · 5.07 fl oz'), findsOneWidget);

    // Every opinion, with its source.
    await tester.tap(find.text('Kezayis'));
    await tester.pumpAndSettle();
    expect(find.text('Rav Mordechai Willig'), findsOneWidget);
    await tester.tap(find.text('Rav Mordechai Willig'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pesach To-Go'), findsOneWidget);
    Navigator.of(tester.element(find.textContaining('Pesach To-Go'))).pop();
    await tester.pumpAndSettle();

    // The converter: 2 amos, by the Chazon Ish, and by every other opinion.
    await tester.tap(find.text('Converter'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '2');
    await tester.pump();
    expect(find.text('115 centimetres'), findsWidgets);
    // Rav Chaim Na'eh's row, with his stringent figure.
    expect(find.text('96 centimetres · stringently 98'), findsOneWidget);
    expect(find.textContaining('According to Chazon Ish'), findsOneWidget);
    await tester.tap(find.text("Rav Chaim Na'eh"));
    await tester.pump();
    expect(find.text('96 centimetres'), findsOneWidget);
    expect(find.textContaining("According to Rav Chaim Na'eh"), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
