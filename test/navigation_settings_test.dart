import 'dart:io';

import 'package:amud/core/adaptive.dart';
import 'package:amud/core/settings.dart';
import 'package:amud/features/settings/nav_tabs_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the bar keeps shortcuts and its label choice', () {
    final s = AppSettings.fromJson({
      ...const AppSettings().toJson(),
      'navTabs': ['calendar', 'home', 'someday-feature', 'calendar'],
      'navLabels': false,
      'expandedSettings': ['zmanim', 3],
    });
    // Settings is added back; an id this version doesn't know is dropped.
    expect(s.navTabs, ['calendar', 'home', 'settings']);
    expect(s.navLabels, isFalse);
    expect(s.expandedSettings, ['zmanim']);
  });

  test('bar items are tabs with a branch or shortcuts with a route', () {
    expect(NavItem.of('torah')?.branch, 3);
    expect(NavItem.of('tehillim')?.route, '/torah/tehillim');
    expect(NavItem.of('someday-feature'), isNull);
    // Settings keeps the ids it knows; they're the bar's shortcuts.
    expect({for (final t in navShortcuts) t.$1}, navShortcutIds);
  });

  test('a bar with more than fit keeps Settings and the open tab', () {
    final items = [for (final id in ['home', 'siddur', 'calendar', 'torah', 'settings', 'zmanim']) NavItem.of(id)!];
    expect([for (final t in fitNavItems(items, 4, branch: 2)) t.id], ['home', 'siddur', 'settings', 'zmanim']);
    expect(fitNavItems(items, 9), items);
  });

  // The test font draws every letter a square; widths need a real one.
  setUpAll(() async {
    final font = File('assets/fonts/FrankRuhlLibre.ttf').readAsBytesSync();
    await (FontLoader('BarTest')..addFont(Future.value(ByteData.sublistView(font)))).load();
  });

  // The default bar, then with the longest labels.
  const usual = ['home', 'siddur', 'zmanim', 'torah', 'settings'];
  const long = ['tehillim', 'calendar', 'learning', 'settings'];
  for (final (width, scale, labels, ids, want) in [
    (360.0, 1.0, true, usual, 5),
    (360.0, 1.3, true, usual, 5),
    (320.0, 1.3, true, usual, 4),
    (320.0, 1.3, true, long, 4),
    (320.0, 1.3, false, usual, 5),
    (412.0, 1.0, false, usual, 6),
  ]) {
    testWidgets('$want bar items fit at ${width}dp, text ×$scale, labels $labels, $ids', (tester) async {
      tester.view.physicalSize = Size(width, 780);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      late int fit;
      await tester.pumpWidget(MaterialApp(theme: ThemeData(fontFamily: 'BarTest'), home: Builder(builder: (context) {
        fit = maxNavItems(context, labels: labels, ids: ids);
        return const SizedBox();
      })));
      expect(fit, want);
    });
  }

  testWidgets('a folded section shows only its header, and opens on a tap', (tester) async {
    var expanded = false;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: AdaptiveSection(
            header: 'Zmanim',
            icon: Icons.wb_twilight_outlined,
            expanded: expanded,
            onExpandedChanged: (v) => setState(() => expanded = v),
            children: const [ListTile(title: Text('Candle lighting'))],
          ),
        ),
      ),
    ));
    expect(find.text('Candle lighting'), findsNothing);
    await tester.tap(find.text('Zmanim'));
    await tester.pumpAndSettle();
    expect(expanded, isTrue);
    expect(find.text('Candle lighting'), findsOneWidget);
  });
}
