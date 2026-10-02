import 'package:amud/core/typeset/typeset.dart';
import 'package:amud/features/siddur/reader_typography.dart';
import 'package:amud/features/siddur/reading_marks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:siddur_engine/siddur_engine.dart';

// Tests use the FlutterTest font: every glyph, the space included, is one
// em wide, so line widths can be worked out by hand.
const _style = TextStyle(fontFamily: 'FlutterTest', fontSize: 10, height: 1);

ParagraphFit _fit(InlineSpan text, double width, {bool justify = true, bool balance = true}) =>
    ParagraphFitter.fit(text: text, width: width, textDirection: TextDirection.ltr, em: 10, style: _style, justify: justify, balance: balance);

SegmentItem _line(String html, {SegmentKind kind = SegmentKind.prayer, String? role, String? voice, bool chazarah = false}) {
  final seg = Segment(ref: 'r', html: html, hebrew: true, kind: kind, runs: [TextRun(html, RunKind.text)]);
  return SegmentItem('k', SchemaNode.parse({'enTitle': 'Test'}), ResolvedSegment(seg, const []), null, kind, Applicability.always, null, null, false,
      role: role, voice: voice, chazarah: chazarah);
}

void main() {
  setUp(ParagraphFitter.clearCache);

  group('ParagraphFitter', () {
    test('a one-line paragraph is left alone', () {
      final f = _fit(const TextSpan(text: 'aa aa'), 200);
      expect(f.lines, 1);
      expect(f.wordSpacing, 0);
    });

    test('a runt last line is pulled back by tightening the word space', () {
      // Three words (80) fit in 108 and a fourth (110) doesn't, leaving
      // "aa" alone on a line; 0.08em less per space gets it in (107.6).
      final f = _fit(const TextSpan(text: 'aa aa aa aa'), 108);
      expect(f.lines, 1);
      expect(f.wordSpacing, lessThan(0));
      expect(f.wordSpacing, greaterThanOrEqualTo(-1.2));
    });

    test('without balancing or justifying nothing is measured', () {
      final f = _fit(const TextSpan(text: 'aa aa aa aa'), 108, justify: false, balance: false);
      expect(f.align, TextAlign.start);
      expect(f.wordSpacing, 0);
    });

    test('a line that would gape is set ragged', () {
      // "aaaa b" (60) then a long word that can't join it: justifying the
      // first line would put 4em in its one space.
      final f = _fit(const TextSpan(text: 'aaaa b cccccccc'), 100);
      expect(f.lines, 2);
      expect(f.looseness, greaterThan(ParagraphFitter.tolerableGap));
      expect(f.align, TextAlign.start);
    });

    test('evenly filled lines justify', () {
      // Two lines of "aaa aaa aaa" (110) in 112: 1px over two spaces.
      final f = _fit(const TextSpan(text: 'aaa aaa aaa aaa aaa aaa'), 112);
      expect(f.lines, 2);
      expect(f.align, TextAlign.justify);
      expect(f.looseness, lessThan(ParagraphFitter.maxGap));
    });

    test('inline widgets are estimated, not measured, and leave the last line be', () {
      // Ragged, so only balancing could change it, and it doesn't trust
      // the estimate.
      final f = _fit(
          const TextSpan(children: [WidgetSpan(child: SizedBox(width: 20, height: 10)), TextSpan(text: ' aa aa aa aa aa aa')]), 108,
          justify: false);
      expect(f.lines, greaterThan(1));
      expect(f.wordSpacing, 0);
    });

    test('results are cached across fresh but equal spans', () {
      final a = _fit(const TextSpan(text: 'aa aa aa aa'), 108);
      final b = _fit(TextSpan(text: 'aa aa aa ${'aa'}'), 108);
      expect(identical(a, b), isTrue);
    });
  });

  group('enlargeOpening', () {
    const base = TextStyle(fontSize: 20);
    const bold = TextStyle(fontSize: 20, fontWeight: FontWeight.w700);

    test('scales the bold lead-in, keeping the line height', () {
      final out = enlargeOpening(const [TextSpan(text: 'בָּרוּךְ', style: bold), TextSpan(text: ' אַתָּה', style: base)], 1.5, lineHeight: 1.65);
      final first = out.first as TextSpan;
      expect(first.style!.fontSize, 30);
      expect(first.style!.fontSize! * first.style!.height!, closeTo(20 * 1.65, 1e-9));
      expect((out[1] as TextSpan).style, base);
    });

    test('without a bold lead-in, takes the first word', () {
      final out = enlargeOpening(const [TextSpan(text: 'מוֹדֶה אֲנִי', style: base)], 1.5, lineHeight: 1.65);
      expect(out.map((s) => (s as TextSpan).text), ['מוֹדֶה', ' אֲנִי']);
      expect((out.first as TextSpan).style!.fontSize, 30);
    });

    test('passes over a leading chip', () {
      final out = enlargeOpening(const [WidgetSpan(child: SizedBox()), TextSpan(text: 'יַעֲלֶה וְיָבֹא', style: base)], 1.4, lineHeight: 1.65);
      expect(out.first, isA<WidgetSpan>());
      expect((out[1] as TextSpan).text, 'יַעֲלֶה');
    });
  });

  group('TypeScale', () {
    test('sizes follow intent at the default contrast', () {
      const ts = TypeScale(hebrewSize: 22, latinSize: 16);
      double he(ParagraphRole r) => ts.size(r, hebrew: true);
      expect(he(ParagraphRole.proclamation), greaterThan(he(ParagraphRole.keystone)));
      expect(he(ParagraphRole.keystone), greaterThan(he(ParagraphRole.opening)));
      expect(he(ParagraphRole.opening), greaterThan(he(ParagraphRole.body)));
      expect(he(ParagraphRole.body), greaterThan(he(ParagraphRole.undertone)));
      expect(he(ParagraphRole.instruction), closeTo(22 * 0.7, 1e-9));
      // Slight: nothing but the Shema strays more than an eighth from the
      // body.
      expect(he(ParagraphRole.proclamation) / 22, closeTo(1.25, 1e-9));
      for (final r in ParagraphRole.values.where((r) => r.said && r != ParagraphRole.proclamation)) {
        expect((he(r) / 22 - 1).abs(), lessThan(0.125), reason: '$r');
      }
    });

    test('no contrast sets every said line at the body size', () {
      const ts = TypeScale(hebrewSize: 22, latinSize: 16, contrast: 0);
      for (final r in ParagraphRole.values.where((r) => r.said)) {
        expect(ts.size(r, hebrew: true), 22);
      }
    });

    test('plain setting keeps the old spacing and ragged lines', () {
      const ts = TypeScale(hebrewSize: 22, latinSize: 16, print: false, justify: false, contrast: 0);
      expect(ts.space(ParagraphRole.keystone), const EdgeInsets.symmetric(vertical: 5));
      expect(ts.align(ParagraphRole.body), ParagraphAlign.start);
      expect(ts.leading(ParagraphRole.body, hebrew: true), 1.65);
      expect(ts.openingWord, 1);
    });

    test("te'amim get more leading", () {
      const ts = TypeScale(hebrewSize: 22, latinSize: 16);
      expect(ts.leading(ParagraphRole.body, hebrew: true, marks: true), greaterThan(ts.leading(ParagraphRole.body, hebrew: true)));
    });
  });

  group('paragraphRole', () {
    test("the Shema's first verse is the proclamation, with or without te'amim", () {
      expect(paragraphRole(_line('<b>שְׁמַע</b> יִשְׂרָאֵל יְהֹוָה אֱלֹהֵינוּ יְהֹוָה אֶחָד׃'), opening: true), ParagraphRole.proclamation);
      expect(paragraphRole(_line('שְׁמַ֖ע יִשְׂרָאֵ֑ל יְהֹוָ֥ה אֱלֹהֵ֖ינוּ יְהֹוָ֥ה ׀ אֶחָֽד׃'), opening: true), ParagraphRole.proclamation);
    });

    test('Barchu and Kedushah are keystones', () {
      expect(paragraphRole(_line("בָּרְכוּ אֶת ה' הַמְבֹרָךְ:"), opening: false), ParagraphRole.keystone);
      expect(paragraphRole(_line('בָּרוּךְ יְיָ הַמְּבֹרָךְ לְעוֹלָם וָעֶד:'), opening: false), ParagraphRole.keystone);
      expect(paragraphRole(_line('קָדוֹשׁ קָדוֹשׁ קָדוֹשׁ יְהֹוָה צְבָאוֹת מְלֹא כָל הָאָרֶץ כְּבוֹדוֹ:'), opening: false), ParagraphRole.keystone);
    });

    test('a long paragraph that starts like one is not', () {
      final long = 'שְׁמַע יִשְׂרָאֵל ${List.filled(20, 'מִלָּה').join(' ')}';
      expect(paragraphRole(_line(long), opening: false), ParagraphRole.body);
    });

    test('voice, chazarah and responses', () {
      expect(paragraphRole(_line('בָּרוּךְ שֵׁם כְּבוֹד מַלְכוּתוֹ לְעוֹלָם וָעֶד׃'), opening: false), ParagraphRole.undertone);
      expect(paragraphRole(_line('אֱלֹהֵינוּ', voice: 'undertone'), opening: false), ParagraphRole.undertone);
      expect(paragraphRole(_line('יְבָרֶכְךָ', chazarah: true), opening: false), ParagraphRole.chazarah);
      expect(paragraphRole(_line('אָמֵן. יְהֵא שְׁמֵהּ רַבָּא מְבָרַךְ'), opening: false), ParagraphRole.response);
      expect(paragraphRole(_line('אָמֵן', role: 'congregation'), opening: false), ParagraphRole.response);
    });

    test('openings, blessings, and words about the prayer', () {
      expect(paragraphRole(_line('אַשְׁרֵי יוֹשְׁבֵי בֵיתֶךָ'), opening: true), ParagraphRole.opening);
      expect(paragraphRole(_line('בָּרוּךְ אַתָּה יְהֹוָה מָגֵן אַבְרָהָם׃'), opening: false), ParagraphRole.blessing);
      expect(paragraphRole(_line('בראש חודש אומרים:', kind: SegmentKind.instruction), opening: true), ParagraphRole.instruction);
      expect(paragraphRole(_line('ש״ץ:', kind: SegmentKind.speaker), opening: false), ParagraphRole.speaker);
    });

    test("the Shema's paragraphs and the places the congregation waits open large", () {
      for (final line in ['וְאָהַבְתָּ אֵת יְהֹוָה אֱלֹהֶיךָ בְּכָל לְבָבְךָ', 'וְהָיָה אִם שָׁמֹעַ תִּשְׁמְעוּ', 'עֶזְרַת אֲבוֹתֵינוּ אַתָּה הוּא', 'צוּר יִשְׂרָאֵל קוּמָה בְּעֶזְרַת יִשְׂרָאֵל']) {
        expect(paragraphRole(_line(line), opening: false), ParagraphRole.opening, reason: line);
      }
    });

    test("the Amidah's opening verse leaves the large word to the blessing", () {
      expect(isPreamble(_line('אֲדֹנָי שְׂפָתַי תִּפְתָּח וּפִי יַגִּיד תְּהִלָּתֶךָ:')), isTrue);
      expect(isPreamble(_line('בָּרוּךְ אַתָּה יְהֹוָה אֱלֹהֵינוּ')), isFalse);
    });

    test('Baruch shem is said quietly, tagged or not', () {
      expect(isUndertone(_line('בָּרוּךְ שֵׁם כְּבוֹד מַלְכוּתוֹ לְעוֹלָם וָעֶד:')), isTrue);
      expect(const TypeScale(hebrewSize: 22, latinSize: 16).align(ParagraphRole.undertone), ParagraphAlign.center);
    });

    test('the divine name reads the same however it is spelled', () {
      for (final name in ['יְהֹוָה', 'ה\'', 'יְיָ', 'ד\'']) {
        expect(normalizeHebrewWords('בָּרוּךְ $name הַמְבֹרָךְ'), 'ברוך ה המברך');
      }
    });
  });

  testWidgets('TypesetParagraph justifies a long paragraph and tightens a runt', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: _style,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 108,
            child: TypesetParagraph(text: TextSpan(text: 'aa aa aa aa'), textDirection: TextDirection.ltr, em: 10),
          ),
        ),
      ),
    ));
    final rich = tester.widget<RichText>(find.byType(RichText));
    expect(rich.textAlign, TextAlign.justify);
    // Pulled onto one line.
    expect(tester.getSize(find.byType(RichText)).height, 10);
  });

  group('splitParagraphs', () {
    // As the Daat siddur prints it: the whole psalm one line, verse 12's
    // number run into its first word.
    const psalm116 = 'א אָהַבְתִּי כִּי יִשְׁמַע יְהוָה אֶת קוֹלִי תַּחֲנוּנָי. '
        'יא אֲנִי אָמַרְתִּי בְחָפְזִי כָּל הָאָדָם כֹּזֵב. יבמָה אָשִׁיב לַיהוָה כָּל תַּגְמוּלוֹהִי עָלָי. '
        'יג כּוֹס יְשׁוּעוֹת אֶשָּׂא וּבְשֵׁם יְהוָה אֶקְרָא.';

    test("Hallel's מה אשיב starts its own paragraph, its verse number with it", () {
      final pieces = splitParagraphs(verseNumbers(psalm116));
      expect(pieces, hasLength(2));
      expect(pieces.first, startsWith('<sup class="verse">א</sup> אָהַבְתִּי'));
      final (number, words) = splitLeadingVerse(pieces.last);
      expect(number, '<sup class="verse">יב</sup> ');
      expect(words, startsWith('מָה אָשִׁיב'));
    });

    test('a line that starts a paragraph is not split at its start', () {
      expect(splitParagraphs(verseNumbers('א לֹא לָנוּ יְהוָה לֹא לָנוּ כִּי לְשִׁמְךָ תֵּן כָּבוֹד.')), hasLength(1));
    });

    test('mid-sentence words are not paragraph starts', () {
      expect(splitParagraphs('וְאָמַר מָה אָשִׁיב לוֹ'), hasLength(1));
    });

    test('the divine name matches in any spelling', () {
      expect(splitParagraphs("שָׁלוֹם. אָנָּא ה' הוֹשִׁיעָה נָּא"), hasLength(2));
      expect(splitParagraphs('שָׁלוֹם: אָנָּא יְהֹוָה הוֹשִׁיעָה נָּא'), hasLength(2));
    });
  });
}
