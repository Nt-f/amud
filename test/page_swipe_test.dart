import 'package:amud/core/page_swipe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<List<String>> swipe(WidgetTester tester, Offset from, Offset by, {TextDirection dir = TextDirection.ltr}) async {
    final turned = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: dir,
        child: PageSwipe(
          onNext: () => turned.add('next'),
          onPrevious: () => turned.add('previous'),
          child: const SizedBox.expand(child: ColoredBox(color: Colors.white)),
        ),
      ),
    ));
    await tester.dragFrom(from, by);
    await tester.pumpAndSettle();
    return turned;
  }

  testWidgets('a leftward swipe turns forward, a rightward one back', (tester) async {
    expect(await swipe(tester, const Offset(400, 300), const Offset(-150, 0)), ['next']);
    expect(await swipe(tester, const Offset(300, 300), const Offset(150, 0)), ['previous']);
  });

  testWidgets('swipes from the screen edges are left for the back gesture', (tester) async {
    expect(await swipe(tester, const Offset(10, 300), const Offset(200, 0)), isEmpty);
    expect(await swipe(tester, const Offset(795, 300), const Offset(-200, 0)), isEmpty);
  });

  testWidgets('scrolling and short swipes do nothing', (tester) async {
    expect(await swipe(tester, const Offset(400, 400), const Offset(-60, -200)), isEmpty);
    expect(await swipe(tester, const Offset(400, 300), const Offset(-40, 0)), isEmpty);
  });

  testWidgets('a Hebrew interface turns the other way', (tester) async {
    expect(await swipe(tester, const Offset(300, 300), const Offset(150, 0), dir: TextDirection.rtl), ['next']);
  });

  group('TabSwipe', () {
    Future<List<String>> tabSwipe(WidgetTester tester, Offset from, Offset by, {Widget? child}) async {
      final turned = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TabSwipe(
            onNext: () => turned.add('next'),
            onPrevious: () => turned.add('previous'),
            child: child ?? const SizedBox.expand(child: ColoredBox(color: Colors.white)),
          ),
        ),
      ));
      await tester.dragFrom(from, by);
      await tester.pumpAndSettle();
      return turned;
    }

    testWidgets('swipes move between tabs', (tester) async {
      expect(await tabSwipe(tester, const Offset(400, 300), const Offset(-150, 0)), ['next']);
      expect(await tabSwipe(tester, const Offset(300, 300), const Offset(150, 0)), ['previous']);
    });

    testWidgets('edges and short or vertical drags do nothing', (tester) async {
      expect(await tabSwipe(tester, const Offset(10, 300), const Offset(200, 0)), isEmpty);
      expect(await tabSwipe(tester, const Offset(400, 300), const Offset(-40, 0)), isEmpty);
      expect(await tabSwipe(tester, const Offset(400, 400), const Offset(-30, -200)), isEmpty);
    });

    testWidgets('a slider under the finger keeps the drag', (tester) async {
      var value = 0.5;
      final slider = Center(
        child: SizedBox(
          width: 600,
          child: StatefulBuilder(builder: (context, set) => Slider(value: value, onChanged: (v) => set(() => value = v))),
        ),
      );
      expect(await tabSwipe(tester, const Offset(400, 300), const Offset(-150, 0), child: slider), isEmpty);
      expect(value, lessThan(0.5));
    });
  });
}
