/// Hallel's "Hodu" and the three verses after it (Psalm 118:1-4) are
/// responsive: the chazzan says the verse and the congregation answers
/// "כי לעולם חסדו". Siddurim print them as one run, so the answers are found
/// by their words and split off, to be set apart like any other response.
library;

import 'rubrics.dart';

/// Where a reading of Hallel is: the answers stop after the third verse
/// ("יאמרו נא יראי ה׳"), so the "הודו" that closes Psalm 118 is said by all.
class HoduState {
  bool done = false;
}

const _marks = r'[֑-ׇ]*';
final RegExp _response = () {
  String word(String w) => [for (final c in w.split('')) '$c$_marks'].join();
  const gap = r'(?:[\s ־]|<[^>]*>)+';
  return RegExp('${word('כי')}$gap${word('לעולם')}$gap${word('חסדו')}(?:[:׃.]|<[^>]*>)*');
}();

final RegExp _tag = RegExp(r'<(/?)([a-zA-Z]+)[^>]*?(/?)>');

String _letters(String html) => stripHtml(html)
    .replaceAll(RegExp(r'[֑-ׇ]'), '')
    .replaceAll('־', ' ')
    .replaceAll(RegExp(r'[^א-ת\s]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// [html] cut into the chazzan's words and the congregation's answers
/// (`true`), or null where it holds no such answers. Tags a cut falls
/// inside are closed and reopened.
List<(String, bool)>? splitHoduResponses(String html, HoduState state) {
  final cuts = <(int, int)>[];
  var from = 0;
  for (final m in _response.allMatches(html)) {
    final before = _letters(html.substring(from, m.start));
    final leader = before.endsWith('כי טוב')
        ? !state.done
        : before.endsWith('ישראל') || before.endsWith('בית אהרן') || RegExp(r'יראי \S{1,5}$').hasMatch(before);
    if (!leader) continue;
    if (before.contains('יראי')) state.done = true;
    cuts.add((m.start, m.end));
    from = m.end;
  }
  if (cuts.isEmpty) return null;

  final raw = <(String, bool)>[];
  var at = 0;
  for (final (start, end) in cuts) {
    if (start > at) raw.add((html.substring(at, start), false));
    raw.add((html.substring(start, end), true));
    at = end;
  }
  if (at < html.length) raw.add((html.substring(at), false));

  final open = <String>[]; // opening tags still unclosed
  final out = <(String, bool)>[];
  for (final (piece, resp) in raw) {
    final reopened = open.join();
    for (final m in _tag.allMatches(piece)) {
      final name = m.group(2)!.toLowerCase();
      if (name == 'br' || m.group(3) == '/') continue;
      if (m.group(1) == '/') {
        final i = open.lastIndexWhere((t) => t.toLowerCase().startsWith('<$name'));
        if (i >= 0) open.removeRange(i, open.length);
      } else {
        open.add(m.group(0)!);
      }
    }
    final closing = [for (final t in open.reversed) '</${RegExp(r'<([a-zA-Z]+)').firstMatch(t)!.group(1)}>'].join();
    out.add(('$reopened$piece$closing', resp));
  }
  return out;
}
