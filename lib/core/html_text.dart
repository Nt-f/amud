import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Converts the small HTML subset Sefaria uses (b, i, small, big, br, sup,
/// span, u, footnotes) into [InlineSpan]s. Footnotes (`<sup
/// class="footnote-marker">` + `<i class="footnote">`) become tappable
/// superscript markers that call [onFootnote].
class SefariaHtml {
  final TextStyle base;
  final TextStyle? instructionStyle;
  final void Function(String footnote)? onFootnote;

  SefariaHtml(this.base, {this.instructionStyle, this.onFootnote});

  static final _tag = RegExp(r'<(/?)([a-zA-Z0-9]+)([^>]*)>');
  static final _entity = RegExp(r'&(#\d+|#x[0-9a-fA-F]+|[a-z]+);');

  static String decodeEntities(String s) => s.replaceAllMapped(_entity, (m) {
        final e = m.group(1)!;
        if (e.startsWith('#x')) return String.fromCharCode(int.parse(e.substring(2), radix: 16));
        if (e.startsWith('#')) return String.fromCharCode(int.parse(e.substring(1)));
        return switch (e) {
          'nbsp' => ' ',
          'amp' => '&',
          'lt' => '<',
          'gt' => '>',
          'quot' => '"',
          'thinsp' => ' ',
          _ => '',
        };
      });

  List<InlineSpan> parse(String html, {TextStyle? style}) {
    final spans = <InlineSpan>[];
    // Stack entries: tag name, style to restore, capture mode it opened.
    final stack = <(String, TextStyle, _Capture)>[];
    var current = style ?? base;
    var capture = _Capture.none;
    final buf = StringBuffer();
    var marker = '';
    var i = 0;

    void emitText(String t) {
      if (t.isEmpty) return;
      final text = decodeEntities(t);
      if (capture != _Capture.none) {
        buf.write(text);
      } else {
        spans.add(TextSpan(text: text, style: current));
      }
    }

    for (final m in _tag.allMatches(html)) {
      emitText(html.substring(i, m.start));
      i = m.end;
      final closing = m.group(1) == '/';
      final name = m.group(2)!.toLowerCase();
      final attrs = m.group(3) ?? '';
      if (name == 'br') {
        if (capture == _Capture.none) spans.add(TextSpan(text: '\n', style: current));
        continue;
      }
      if (!closing) {
        if (capture == _Capture.none && name == 'sup' && attrs.contains('footnote-marker')) {
          stack.add((name, current, _Capture.marker));
          capture = _Capture.marker;
          buf.clear();
          continue;
        }
        if (capture == _Capture.none && name == 'i' && attrs.contains('footnote')) {
          stack.add((name, current, _Capture.note));
          capture = _Capture.note;
          buf.clear();
          continue;
        }
        stack.add((name, current, _Capture.none));
        current = _apply(name, attrs, current);
        continue;
      }
      // Closing tag: pop to the matching open tag (tolerates bad nesting).
      final idx = stack.lastIndexWhere((e) => e.$1 == name);
      if (idx < 0) continue;
      final (_, restore, opened) = stack[idx];
      stack.removeRange(idx, stack.length);
      current = restore;
      if (opened == _Capture.marker) {
        marker = buf.toString().trim();
        buf.clear();
        capture = _Capture.none;
      } else if (opened == _Capture.note) {
        final note = buf.toString().trim();
        buf.clear();
        capture = _Capture.none;
        spans.add(_footnoteSpan(marker, note, current));
        marker = '';
      }
    }
    emitText(html.substring(i));
    if (capture == _Capture.note && buf.isNotEmpty) spans.add(_footnoteSpan(marker, buf.toString(), current));
    return spans;
  }

  InlineSpan _footnoteSpan(String marker, String note, TextStyle style) {
    final recognizer = onFootnote == null ? null : (TapGestureRecognizer()..onTap = () => onFootnote!(note));
    return TextSpan(
      text: ' ${marker.isEmpty ? '*' : marker}',
      style: style.copyWith(
        fontSize: (style.fontSize ?? 16) * 0.65,
        fontFeatures: const [FontFeature.superscripts()],
        color: Colors.blueGrey,
        fontWeight: FontWeight.w600,
      ),
      recognizer: recognizer,
    );
  }

  TextStyle _apply(String name, String attrs, TextStyle s) {
    switch (name) {
      case 'b':
      case 'strong':
        return s.copyWith(fontWeight: FontWeight.w700);
      case 'i':
      case 'em':
        if (attrs.contains('instruction') && instructionStyle != null) return s.merge(instructionStyle);
        return s.copyWith(fontStyle: FontStyle.italic);
      case 'small':
        return s.copyWith(fontSize: (s.fontSize ?? 16) * 0.8);
      case 'big':
        return s.copyWith(fontSize: (s.fontSize ?? 16) * 1.25);
      case 'u':
        return s.copyWith(decoration: TextDecoration.underline);
      case 'sup':
        // Verse numbers keep the text's size, so a highlight behind them
        // runs level with the words; a faint color sets them apart.
        if (attrs.contains('verse')) return s.copyWith(color: instructionStyle?.color?.withValues(alpha: 0.7), fontWeight: FontWeight.w400);
        return s.copyWith(fontSize: (s.fontSize ?? 16) * 0.65);
      default:
        return s;
    }
  }
}

enum _Capture { none, marker, note }

final _leadBold = RegExp(r'^(\s*)<(b|strong)>(.*?)</\2>', dotAll: true);
final _leadHebrewWord = RegExp(r'^(\s*)([א-ת][^\s<]*)');

/// Makes the bold opening words of a paragraph consistent. Some versions
/// set the first words of every paragraph in bold, some only some of them,
/// and some none, and the reader mixes versions section by section. So the
/// [opening] line of a prayer starts in bold (added for Hebrew when
/// [addIfMissing]) and other lines lose a short bold lead-in. Lines that are
/// bold throughout (responses such as "Amen, yehei shmei rabba") and
/// longer bold passages are left alone.
String normalizeOpeningBold(String html, {required bool opening, bool addIfMissing = false}) {
  final m = _leadBold.firstMatch(html);
  if (m != null) {
    final rest = html.substring(m.end);
    final restText = rest.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    final words = m[3]!.replaceAll(RegExp(r'<[^>]*>'), '').trim().split(RegExp(r'\s+')).length;
    if (opening || restText.isEmpty || words > 4) return html;
    return '${m[1]}${m[3]}$rest';
  }
  if (!opening || !addIfMissing) return html;
  return html.replaceFirstMapped(_leadHebrewWord, (w) => '${w[1]}<b>${w[2]}</b>');
}
