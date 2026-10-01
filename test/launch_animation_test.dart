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

    await run(1300);
    expect(find.text('amud'), findsOneWidget);
    await run(800);
    expect(find.text('amud'), findsNothing);
  });
}
