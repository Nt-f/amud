import 'package:amud/features/torah/verse_snap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Ten 300px verses in an 800px view; a settled verse sits 8px down.
  Future<ScrollController> reader(WidgetTester tester, {bool enabled = true}) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = ScrollController();
    final keys = List.generate(10, (_) => GlobalKey());
    await tester.pumpWidget(MaterialApp(
      home: VerseSnap(
        verses: keys,
        enabled: enabled,
        child: ListView(controller: controller, children: [for (final k in keys) SizedBox(key: k, height: 300)]),
      ),
    ));
    return controller;
  }

  testWidgets('near the end of a verse, the next one moves to the top', (tester) async {
    final c = await reader(tester);
    c.jumpTo(230);
    await tester.pumpAndSettle();
    expect(c.offset, 292);
  });

  testWidgets('mid-verse, it stays put', (tester) async {
    final c = await reader(tester);
    c.jumpTo(120);
    await tester.pumpAndSettle();
    expect(c.offset, 120);
  });

  testWidgets('just past its start, the verse comes back into view', (tester) async {
    final c = await reader(tester);
    c.jumpTo(350);
    await tester.pumpAndSettle();
    expect(c.offset, 292);
  });

  testWidgets('off, it never moves', (tester) async {
    final c = await reader(tester, enabled: false);
    c.jumpTo(230);
    await tester.pumpAndSettle();
    expect(c.offset, 230);
  });
}
