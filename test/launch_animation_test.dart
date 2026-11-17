import 'package:amud/features/setup/launch_animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The system's "remove animations" setting, as Android reports it: it
  // also makes AnimationController run 20 times faster unless told not to.
  testWidgets('with reduced motion the still logo stays up, then goes', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(MaterialApp(builder: (context, child) => LaunchAnimation(child: child!), home: const Text('app')));
    // Frame by frame, as on a device.
    Future<void> run(int ms) async {
      for (var t = 0; t < ms; t += 50) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await run(250);
    expect(find.text('amud'), findsOneWidget);
    await run(400);
    expect(find.text('amud'), findsNothing);
  });

  testWidgets('a tap skips the animation', (tester) async {
    LaunchAnimation.resetForTest();
    await tester.pumpWidget(MaterialApp(builder: (context, child) => LaunchAnimation(child: child!), home: const Text('app')));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('amud'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    // Just the fade, not the rest of the animation.
    for (var t = 0; t < 300; t += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('amud'), findsNothing);
  });

  testWidgets('the whole animation is over in well under a second', (tester) async {
    LaunchAnimation.resetForTest();
    await tester.pumpWidget(MaterialApp(builder: (context, child) => LaunchAnimation(child: child!), home: const Text('app')));
    for (var t = 0; t < 900; t += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('amud'), findsNothing);
  });

  testWidgets('on a flip phone\'s 240 by 180 screen the whole logo shows', (tester) async {
    LaunchAnimation.resetForTest();
    tester.view.physicalSize = const Size(240, 180);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(builder: (context, child) => LaunchAnimation(child: child!), home: const Text('app')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    final screen = Offset.zero & const Size(240, 180);
    for (final f in [find.byType(CustomPaint).last, find.text('amud')]) {
      final r = tester.getRect(f);
      expect(screen.intersect(r), r, reason: '$f is on the screen');
    }
  });

  testWidgets('a phone too slow to animate it still shows the finished logo for a moment', (tester) async {
    LaunchAnimation.resetForTest();
    await tester.pumpWidget(MaterialApp(builder: (context, child) => LaunchAnimation(child: child!), home: const Text('app')));
    // Frames a third of a second apart: the half-second animation is over
    // in two of them.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 330));
    }
    final word = tester.widget<Opacity>(find.ancestor(of: find.text('amud'), matching: find.byType(Opacity)).first);
    expect(word.opacity, 1);
    await tester.pump(const Duration(milliseconds: 330));
    expect(find.text('amud'), findsOneWidget, reason: 'held, not faded yet');
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 330));
    }
    expect(find.text('amud'), findsNothing);
  });
}
