import 'package:amud/core/adaptive.dart';
import 'package:amud/core/settings.dart';
import 'package:amud/features/settings/nav_tabs_screen.dart';
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
    // Settings is added back; an id from a newer version is kept for it.
    expect(s.navTabs, ['calendar', 'home', 'someday-feature', 'settings']);
    expect(s.navLabels, isFalse);
    expect(s.expandedSettings, ['zmanim']);
  });

  test('bar items are tabs with a branch or shortcuts with a route', () {
    expect(NavItem.of('torah')?.branch, 3);
    expect(NavItem.of('tehillim')?.route, '/siddur/tehillim');
    expect(NavItem.of('someday-feature'), isNull);
  });

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
