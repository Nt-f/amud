import 'package:amud/core/reader_mode.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<List<String>> run(WidgetTester tester, Future<void> Function() gesture, {bool active = true}) async {
    final log = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: ReaderModeLayer(
        active: active,
        onNext: () => log.add('next'),
        onBackTwo: () => log.add('back2'),
        onExit: () => log.add('exit'),
        child: GestureDetector(onTap: () => log.add('page'), child: const ColoredBox(color: Colors.white, child: SizedBox.expand())),
      ),
    ));
    await gesture();
    await tester.pump(const Duration(seconds: 1));
    return log;
  }

  testWidgets('a tap goes forward at once, and the page underneath gets nothing', (tester) async {
    expect(await run(tester, () => tester.tapAt(const Offset(200, 300))), ['next']);
  });

  testWidgets('a quick second tap goes back two (net one back)', (tester) async {
    final log = await run(tester, () async {
      await tester.tapAt(const Offset(200, 300));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(const Offset(200, 300));
    });
    expect(log, ['next', 'back2']);
  });

  testWidgets('press and hold stops it', (tester) async {
    final log = await run(tester, () async {
      final g = await tester.startGesture(const Offset(200, 300));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await g.up();
    });
    expect(log, ['exit']);
  });

  testWidgets('off, taps reach the page', (tester) async {
    expect(await run(tester, () => tester.tapAt(const Offset(200, 300)), active: false), ['page']);
  });
}
