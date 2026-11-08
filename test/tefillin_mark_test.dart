import 'package:amud/features/siddur/tefillin_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The mark for touching the tefillin sits in the line just before its
/// words, captioned יד or ראש, and never ends up at the end of a line with
/// its word on the next.
void main() {
  test('the first word is split off with its tags; the rest keeps its leading space', () {
    expect(splitFirstWord(' עַל־יָדְךָ'), (' ', 'עַל־יָדְךָ', ''));
    expect(splitFirstWord(' בֵּין עֵינֶיךָ'), (' ', 'בֵּין', ' עֵינֶיךָ'));
    expect(splitFirstWord('<b>בֵּין</b> עֵינֶיךָ'), ('', '<b>בֵּין</b>', ' עֵינֶיךָ'));
  });

  for (final (width, scale) in const [(360.0, 1.3), (320.0, 1.3), (360.0, 1.0)]) {
    testWidgets('at ${width}dp, $scale× text, each mark holds its word and keeps the line its height', (t) async {
      t.view.physicalSize = Size(width, 2400);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(t.view.reset);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      const style = TextStyle(fontSize: 23, height: 2);
      // Enough text that the marks land at many points in the line.
      final spans = <InlineSpan>[
        for (var i = 0; i < 12; i++) ...[
          TextSpan(text: '${'וּקְשַׁרְתָּם לְאוֹת ' * (i % 4 + 1)} ', style: style),
          tefillinMarkSpan(i.isEven ? 'touch_tefillin_yad' : 'touch_tefillin_rosh',
              fontSize: 23, color: Colors.blue, word: const [TextSpan(text: 'עַל־יָדֶךָ', style: style)]),
          const TextSpan(text: ' וְהָיוּ לְטֹטָפֹת ', style: style),
        ],
      ];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text.rich(TextSpan(children: spans), textDirection: TextDirection.rtl, textAlign: TextAlign.justify),
            ),
          ),
        ),
      ));
      expect(t.takeException(), isNull);
      expect(find.text('יד'), findsNWidgets(6));
      expect(find.text('ראש'), findsNWidgets(6));
      // Each mark carries its word, so no line can separate them.
      expect(find.descendant(of: find.byType(Row), matching: find.textContaining('יָדֶךָ', findRichText: true)), findsNWidgets(12));

      final para = t.renderObject<RenderParagraph>(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('לְאוֹת')).first);
      final plain = para.text.toPlainText();
      final at = [for (var i = plain.indexOf('￼'); i >= 0; i = plain.indexOf('￼', i + 1)) i];
      expect(at, hasLength(12));
      final line = style.fontSize! * style.height! * scale;
      for (final i in at) {
        final box = para.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1)).first.toRect();
        // The mark with its caption is no taller than a line, so it doesn't
        // push the lines apart.
        expect(box.height, lessThanOrEqualTo(line + 0.5), reason: 'mark at $i');
      }
    });
  }
}
