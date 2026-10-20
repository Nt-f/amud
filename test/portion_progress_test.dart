import 'package:amud/core/portion_progress.dart';
import 'package:amud/core/settings.dart';
import 'package:amud/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

void main() {
  group("progress through a day's portion", () {
    test('empty with its start at the top, full with its end at the bottom', () {
      // Three views long, opened at its start.
      expect(portionProgress(0, 3), 0);
      expect(portionProgress(-1, 2), 0.5);
      expect(portionProgress(-2, 1), 1);
      // Scrolled past it, or not reached yet.
      expect(portionProgress(-5, -2), 1);
      expect(portionProgress(1.5, 4.5), 0);
    });

    test('a reader that opens the portion lower down starts from there', () {
      expect(portionProgress(0.1, 3.1, line: 0.1), 0);
      expect(portionProgress(-1.9, 1.0, line: 0.1), 1);
    });

    test('a portion shorter than the view counts how much of it is in view', () {
      expect(portionProgress(0, 0.6), 1);
      expect(portionProgress(0.7, 1.3), closeTo(0.5, 1e-9));
      expect(portionProgress(1.2, 1.8), 0);
    });

    test('follows a list from the items on screen, placing the rest by their heights', () {
      final tracker = PortionTracker();
      ItemPosition at(int i, double from, double to) => ItemPosition(index: i, itemLeadingEdge: from, itemTrailingEdge: to);
      // Items 2–5 are the portion, half a view each; 2 and 3 are on screen.
      expect(tracker.progress([at(2, 0, 0.5), at(3, 0.5, 1.0)], 2, 5), 0);
      // Scrolled by half a view: 2 is gone, 4 has come in; 5, unseen, is
      // taken to be as tall as the others.
      expect(tracker.progress([at(3, 0, 0.5), at(4, 0.5, 1.0)], 2, 5), closeTo(0.5, 1e-9));
      // At the end: 2 and 3 are off screen above, at the heights they had.
      expect(tracker.progress([at(4, 0, 0.5), at(5, 0.5, 1.0)], 2, 5), 1);
      expect(tracker.progress(const [], 2, 5), isNull);
    });
  });

  Widget themed(Widget child) => MaterialApp(theme: buildTheme(AppSettings(), Brightness.light), home: Scaffold(body: child));

  testWidgets("the bar along the top fills as it's read, and is hidden when there's no portion", (tester) async {
    final progress = ValueNotifier<double?>(null);
    await tester.pumpWidget(themed(Align(alignment: Alignment.topCenter, child: PortionProgressBar(progress: progress))));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    progress.value = 0.4;
    await tester.pumpAndSettle();
    final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, closeTo(0.4, 1e-9));
    expect(tester.getSize(find.byType(LinearProgressIndicator)).height, PortionProgressBar.height);
  });

  testWidgets("the portion's passages are marked by one bar beside them, not a fill", (tester) async {
    Widget passage(String text, {required bool first, required bool last}) => PortionMark(
          first: first,
          last: last,
          gap: 10,
          child: Container(margin: const EdgeInsets.only(bottom: 10), height: 40, child: Text(text)),
        );
    await tester.pumpWidget(themed(Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        passage('one', first: true, last: false),
        passage('two', first: false, last: true),
      ]),
    )));
    final bars = find.descendant(of: find.byType(PortionMark), matching: find.byType(DecoratedBox));
    expect(bars, findsNWidgets(2));
    final first = tester.getRect(bars.at(0)), last = tester.getRect(bars.at(1));
    // In the margin, at the start edge.
    expect(first.left, 6);
    expect(first.width, 3);
    // The first crosses the gap to the next; the last stops at its passage.
    expect(first.bottom, last.top);
    expect(last.height, 40);
  });
}
