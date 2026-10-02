import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amud/core/providers.dart';
import 'package:amud/core/storage.dart';
import 'package:amud/features/home/card_registry.dart';
import 'package:amud/features/torah/torah_library.dart';
import 'package:amud/features/torah/torah_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hebcal/hebcal.dart';

void main() {
  test('packs Sefaria text with chapter titles', () {
    final body = utf8.encode(jsonEncode({
      'versions': [
        {'language': 'he', 'text': [['א', 'ב'], ['ג']]},
        {'language': 'en', 'text': [['a', 'b'], []]},
      ],
      'alts': [
        [{'en': ['Chapter 1 Laws Upon Awakening\n'], 'he': ['[סימן א] דיני השכמת הבקר\n']}],
        [{'en': ['Chapter 2 Washing\n'], 'he': ['[סימן ב] נטילת ידים\n']}],
      ],
    }));
    expect(chaptersMissingEnglish(body), [1]);
    final book = unpackTorahBook(packSefariaText((body: body, fills: {1: (text: ['c'], credit: 'Other translation')})));
    expect(book.length, 2);
    expect(book.titlesEn, ['Laws Upon Awakening', 'Washing']);
    expect(book.titlesHe, ['דיני השכמת הבקר', 'נטילת ידים']);
    expect(book.he[0], ['א', 'ב']);
    expect(book.en[1], ['c']);
    expect(book.enCredits, {1: 'Other translation'});
  });

  test('Kitzur Yomi range within one siman, across simanim, and unparseable', () {
    KitzurShulchanAruchEvent ev(String b, String? e) =>
        KitzurShulchanAruchEvent(HDate(1, Months.tishrei, 5787), KitzurShulchanAruchReading(b, e));
    expect(kitzurTarget(ev('133:17', '133:21')), (siman: 133, from: 17, to: 21));
    expect(kitzurTarget(ev('133:27', '134:1')), (siman: 133, from: 27, to: null));
    expect(kitzurTarget(ev('3:2', '3:E')), (siman: 3, from: 2, to: null));
    expect(kitzurTarget(ev('Klalim', null)), isNull);
  });

  test('saved dashboards get the calendar card under Shabbat & next zman', () async {
    final dir = await Directory.systemTemp.createTemp('dash');
    addTearDown(() => dir.delete(recursive: true));
    final storage = await Storage.openAt(dir.path);
    await storage.writeJson('dashboardVersion', 2);
    await storage.writeJson('dashboard', [
      for (final t in ['hebrewDate', 'learning', 'minyan', 'candles', 'nextZman', 'zmanimList', 'upcoming'])
        CardConfig(id: t, type: t).toJson(),
    ]);
    final c = ProviderContainer(overrides: [storageProvider.overrideWithValue(storage)]);
    addTearDown(c.dispose);
    final types = [for (final x in c.read(dashboardProvider)) x.type];
    expect(types,
        ['hebrewDate', 'levanaWindow', 'learning', 'minyan', 'candles', 'nextZman', 'calendar', 'zmanimList', 'upcoming']);
    expect(c.read(dashboardProvider).firstWhere((x) => x.type == 'calendar').span, 2);
  });

  test('saved dashboards get Kiddush Levana under the Omer, shown only while open', () async {
    final dir = await Directory.systemTemp.createTemp('dash');
    addTearDown(() => dir.delete(recursive: true));
    final storage = await Storage.openAt(dir.path);
    await storage.writeJson('dashboardVersion', 3);
    await storage.writeJson('dashboard', [
      for (final t in ['hebrewDate', 'omer', 'todayInSiddur', 'upcoming', 'levanaWindow'])
        CardConfig(id: t, type: t, settings: t == 'levanaWindow' ? const {'onlyWhenOpen': false} : const {}).toJson(),
    ]);
    final c = ProviderContainer(overrides: [storageProvider.overrideWithValue(storage)]);
    addTearDown(c.dispose);
    final cards = c.read(dashboardProvider);
    expect([for (final x in cards) x.type], ['hebrewDate', 'omer', 'levanaWindow', 'todayInSiddur', 'upcoming']);
    // A card the user already had keeps its own setting.
    expect(cards.firstWhere((x) => x.type == 'levanaWindow').setting<bool>('onlyWhenOpen', true), isFalse);
  });
}
