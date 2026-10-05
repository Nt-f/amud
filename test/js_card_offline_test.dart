import 'dart:io';

import 'package:amud/core/providers.dart';
import 'package:amud/core/settings.dart';
import 'package:amud/core/storage.dart';
import 'package:amud/core/theme.dart';
import 'package:amud/features/home/card_registry.dart';
import 'package:amud/features/js_cards/js_card.dart';
import 'package:amud/features/js_cards/js_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hebcal/hebcal.dart';

/// A card runtime that answers with [result].
class _Runtime implements JsCardRuntime {
  final JsCardResult result;
  const _Runtime(this.result);
  @override
  Future<JsCardResult> render(String script, String contextJson, {Duration timeout = jsCardTimeout}) async => result;
}

void main() {
  setUpAll(initHebcal);

  Future<Storage> storage() async {
    final dir = await Directory.systemTemp.createTemp('card');
    return Storage.openAt(dir.path);
  }

  testWidgets('offline, a card shows what it last had, and when', (tester) async {
    late Storage s;
    await tester.runAsync(() async => s = await storage());
    const cfg = CardConfig(id: 'weather', type: 'js', settings: {'script': 'function render(){}', 'title': 'Weather'});
    const runtime = _Runtime(
      JsCardResult({
        'title': 'Weather',
        'children': [
          {'type': 'text', 'text': 'Sunny, 21°'},
        ],
      }),
    );
    final apps = <ProviderContainer>[];
    ProviderContainer app(JsCardRuntime runtime) {
      final c = ProviderContainer(overrides: [storageProvider.overrideWithValue(s), jsRuntimeProvider.overrideWithValue(runtime)]);
      apps.add(c);
      return c;
    }

    Future<void> show(ProviderContainer c) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: buildTheme(c.read(settingsProvider), Brightness.light),
            home: const Scaffold(body: JsCard(cfg)),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }

    // Online: the card as it is, saved.
    await show(app(runtime));
    expect(find.text('Sunny, 21°'), findsOneWidget);
    expect(find.textContaining('Not updated since'), findsNothing);
    // Let the save, started while building, finish.
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(readSavedCard(s, 'weather', 'function render(){}'), isNotNull);

    // Offline, after a restart: the script fails to fetch and throws.
    await tester.pumpWidget(const SizedBox());
    await show(app(_Runtime(const JsCardResult(null, 'TypeError: cannot read data', true))));
    expect(find.text('Sunny, 21°'), findsOneWidget);
    expect(find.textContaining('Not updated since'), findsOneWidget);
    // Stop the app clock's timers before the test ends.
    await tester.pumpWidget(const SizedBox());
    for (final c in apps) {
      c.dispose();
    }
  });
}
