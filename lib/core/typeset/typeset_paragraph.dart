import 'package:flutter/widgets.dart';

import 'paragraph_fit.dart';
import 'type_scale.dart';

/// A paragraph set by [ParagraphFitter]: justified where that reads well,
/// with its last line kept from ending in a stranded word.
///
/// A drop-in for `Text.rich`: selection, gesture recognizers and inline
/// widgets work as they do there. Only justified or balanced paragraphs
/// are measured; the rest build a plain `Text.rich`.
class TypesetParagraph extends StatelessWidget {
  final InlineSpan text;
  final TextDirection textDirection;
  final ParagraphAlign align;

  /// The paragraph's body size, the unit its spacing is adjusted in.
  final double em;

  /// Pull back (or fill out) a runt last line.
  final bool balance;

  const TypesetParagraph({
    super.key,
    required this.text,
    required this.textDirection,
    required this.em,
    this.align = ParagraphAlign.justify,
    this.balance = true,
  });

  @override
  Widget build(BuildContext context) {
    final justify = align == ParagraphAlign.justify;
    final fixed = switch (align) {
      ParagraphAlign.center => TextAlign.center,
      ParagraphAlign.end => TextAlign.end,
      _ => TextAlign.start,
    };
    // Centered and end-set lines are short by design; nothing to fit.
    if (!justify && (!balance || align != ParagraphAlign.start)) {
      return Text.rich(text, textDirection: textDirection, textAlign: fixed);
    }
    return LayoutBuilder(builder: (context, constraints) {
      final defaults = DefaultTextStyle.of(context);
      final fit = ParagraphFitter.fit(
        text: text,
        width: constraints.maxWidth,
        textDirection: textDirection,
        em: em,
        style: defaults.style,
        textScaler: MediaQuery.textScalerOf(context),
        strutStyle: null,
        textHeightBehavior: defaults.textHeightBehavior ?? DefaultTextHeightBehavior.maybeOf(context),
        locale: Localizations.maybeLocaleOf(context),
        justify: justify,
        balance: balance,
      );
      return Text.rich(
        fit.wordSpacing == 0 ? text : TextSpan(style: TextStyle(wordSpacing: fit.wordSpacing), children: [text]),
        textDirection: textDirection,
        textAlign: fit.align == TextAlign.justify ? TextAlign.justify : fixed,
      );
    });
  }
}

/// Sets a paragraph's opening word large, as printed siddurim do at the
/// start of each prayer.
///
/// The leading bold run (see `normalizeOpeningBold`) is the opening; when
/// there is none, the first word is. Inline widgets before it (a "Today"
/// chip) are passed over. The enlarged word keeps the line's height, so
/// the first line doesn't drop away from the rest: it rises into the
/// space above the paragraph instead.
List<InlineSpan> enlargeOpening(List<InlineSpan> spans, double factor, {required double lineHeight}) {
  if (factor == 1 || spans.isEmpty) return spans;
  TextStyle big(TextStyle? s) {
    final size = s?.fontSize ?? 16;
    return (s ?? const TextStyle()).copyWith(fontSize: size * factor, height: lineHeight / factor, fontWeight: FontWeight.w700);
  }

  final out = <InlineSpan>[];
  var i = 0;
  while (i < spans.length && (spans[i] is! TextSpan || ((spans[i] as TextSpan).text ?? '').trim().isEmpty)) {
    out.add(spans[i]);
    i++;
  }
  if (i == spans.length) return spans;
  final first = spans[i] as TextSpan;
  if (first.style?.fontWeight == FontWeight.w700) {
    // The bold lead-in, however many spans it runs over.
    while (i < spans.length) {
      final s = spans[i];
      if (s is! TextSpan || s.children != null || s.style?.fontWeight != FontWeight.w700) break;
      out.add(TextSpan(text: s.text, style: big(s.style), recognizer: s.recognizer, semanticsLabel: s.semanticsLabel, locale: s.locale));
      i++;
    }
  } else if (first.children == null) {
    final t = first.text!;
    final m = RegExp(r'^(\s*\S+)').firstMatch(t)!;
    out.add(TextSpan(text: m[1], style: big(first.style), recognizer: first.recognizer, locale: first.locale));
    final rest = t.substring(m.end);
    if (rest.isNotEmpty) out.add(TextSpan(text: rest, style: first.style, recognizer: first.recognizer, locale: first.locale));
    i++;
  } else {
    return spans;
  }
  out.addAll(spans.skip(i));
  return out;
}
