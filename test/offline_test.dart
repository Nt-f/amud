import 'dart:io';

import 'package:amud/core/providers.dart';
import 'package:amud/core/settings.dart';
import 'package:amud/core/storage.dart';
import 'package:amud/core/theme.dart';
import 'package:amud/features/js_cards/js_card.dart';
import 'package:amud/features/js_cards/js_fetch.dart';
import 'package:amud/features/settings/offline_screen.dart';
import 'package:amud/features/torah/torah_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hebcal/hebcal.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  // One store for the file (Hive keeps its boxes open between tests),
  // emptied before each test.
  late Storage shared;
  setUpAll(() async {
    initHebcal();
    final dir = await Directory.systemTemp.createTemp('offline');
    shared = await Storage.openAt(dir.path);
  });

  Future<Storage> storage() async {
    for (final k in [...shared.jsonKeys]) {
      await shared.deleteJson(k);
    }
    for (final k in [...shared.blobKeys]) {
      await shared.deleteBlob(k);
    }
    return shared;
  }

  test("a fetch that can't reach the network marks the card's result", () async {
    final offline = JsFetcher(client: () => MockClient((_) => throw const SocketException('offline')));
    final r = await offline.fetch({'type': 'fetch', 'id': 1, 'url': 'https://example.com'});
    expect(r['error'], isNotNull);
    expect(offline.failed, isTrue);
    // The script's own mistakes aren't the network's.
    final refused = JsFetcher(client: () => MockClient((_) async => http.Response('', 200)));
    await refused.fetch({'type': 'fetch', 'id': 1, 'url': 'http://example.com'});
    expect(refused.failed, isFalse);
  });

  test("a card's last result is saved for its script, and not rewritten every minute", () async {
    final s = await storage();
    final at = DateTime(2026, 10, 5, 14, 0);
    await saveCard(s, 'c1', 'script A', {'title': 'One'}, now: at);
    expect(readSavedCard(s, 'c1', 'script A')?.value, {'title': 'One'});
    expect(readSavedCard(s, 'c1', 'script A')?.at, at);
    // Another script for the card: what was saved doesn't fit it.
    expect(readSavedCard(s, 'c1', 'script B'), isNull);
    // The same result a minute later isn't written again...
    await saveCard(s, 'c1', 'script A', {'title': 'One'}, now: at.add(const Duration(minutes: 1)));
    expect(readSavedCard(s, 'c1', 'script A')?.at, at);
    // ...but a new one is, and an old one is refreshed.
    await saveCard(s, 'c1', 'script A', {'title': 'Two'}, now: at.add(const Duration(minutes: 2)));
    expect(readSavedCard(s, 'c1', 'script A')?.value, {'title': 'Two'});
    await saveCard(s, 'c1', 'script A', {'title': 'Two'}, now: at.add(const Duration(minutes: 20)));
    expect(readSavedCard(s, 'c1', 'script A')?.at, at.add(const Duration(minutes: 20)));
  });

  testWidgets('the offline screen lists downloads with their size, and removes them', (tester) async {
    late Storage s;
    await tester.runAsync(() async {
      s = await storage();
      await s.writeBlob('torah:kitzur', List.filled(2 * 1024 * 1024, 1));
      await s.writeBlob('font:gf_Rubik', List.filled(300 * 1024, 1));
      await s.writeBlob('font:gf_Heebo', List.filled(100 * 1024, 1));
      await saveCard(s, 'c1', 'script', {'title': 'One'});
    });
    final c = ProviderContainer(overrides: [storageProvider.overrideWithValue(s)]);
    addTearDown(c.dispose);
    c.read(settingsProvider.notifier).update((x) => x.copyWith(hebrewFont: 'gf_Heebo'));
    await tester.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: buildTheme(c.read(settingsProvider), Brightness.light), home: const OfflineScreen()),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    expect(find.textContaining('Downloaded on this device: 2.4 MB'), findsOneWidget);
    expect(find.text('Kitzur Shulchan Aruch'), findsOneWidget);
    expect(find.text('Downloaded · 2.0 MB'), findsOneWidget);
    // The font in use can't be removed; the other can.
    final heebo = find.ancestor(of: find.textContaining('In use'), matching: find.byType(ListTile));
    expect(find.descendant(of: heebo, matching: find.byIcon(Icons.delete_outline)), findsNothing);
    final rubik = find.ancestor(of: find.text('300 KB'), matching: find.byType(ListTile));
    await tester.tap(find.descendant(of: rubik, matching: find.byIcon(Icons.delete_outline)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(s.readBlob('font:gf_Rubik'), isNull);
    expect(s.readBlob('font:gf_Heebo'), isNotNull);

    // Custom cards' saved results clear.
    expect(find.text('Last results of 1 cards'), findsOneWidget);
    await tester.tap(find.text('Clear'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(s.jsonKeys.where((k) => k.startsWith(savedCardPrefix)), isEmpty);

    // A text is removed after asking.
    final kitzur = find.ancestor(of: find.text('Kitzur Shulchan Aruch'), matching: find.byType(ListTile));
    await tester.tap(find.descendant(of: kitzur, matching: find.byIcon(Icons.delete_outline)));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(s.readBlob('torah:kitzur'), isNull);
    expect(c.read(torahLibraryProvider)['kitzur'], isA<NotDownloaded>());
    expect(find.textContaining('Download all texts'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
