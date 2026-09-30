import 'rubrics.dart';

enum SegmentKind {
  /// Liturgical text that is said.
  prayer,

  /// A short rubric/instruction ("On Rosh Chodesh say:", "Bow here").
  instruction,

  /// A long halachic note or commentary paragraph.
  note,

  /// A role label such as "Chazzan:" / "קהל:".
  speaker,
}

enum RunKind { text, marker }

/// A contiguous piece of a segment. Marker runs are rubric text like
/// `בעשי"ת:`; text runs may carry the condition set by the preceding marker.
class TextRun {
  final String html;
  final RunKind kind;
  final RubricMatch? rubric;
  const TextRun(this.html, this.kind, [this.rubric]);

  bool get conditional => rubric != null;
}

class Segment {
  final String ref;
  final String html;
  final bool hebrew;
  final SegmentKind kind;
  final List<TextRun> runs;

  /// Condition that applies to the whole segment (from a preceding
  /// standalone rubric, a per-segment override, or an omer day line).
  RubricMatch? rubric;

  /// For instruction segments: the rubric this instruction sets for the
  /// following prayer segment(s).
  final RubricMatch? setsRubric;

  /// If set, [setsRubric] only applies when the next prayer segment's
  /// opening words appear in this (normalized) instruction text, e.g.
  /// "בחנוכה ופורים אומרים על הנסים." → next segment "על הנסים…".
  final String? requiresNamedNext;

  /// For "if you forgot…" notes: bound to the previous conditional segment.
  bool followsPrevious;

  /// If this is a day of the Omer count line, its day number.
  int? omerDay;

  Segment({
    required this.ref,
    required this.html,
    required this.hebrew,
    required this.kind,
    required this.runs,
    this.rubric,
    this.setsRubric,
    this.requiresNamedNext,
    this.followsPrevious = false,
    this.omerDay,
  });

  String get plain => stripHtml(html);
  bool get hasInlineConditions => runs.any((r) => r.conditional);

  @override
  String toString() => 'Segment($ref, $kind, ${rubric?.expression}, ${plain.length > 40 ? plain.substring(0, 40) : plain})';
}

final _errorNote = RegExp(
    r'^(?:\*?\s*)?(?:אם שכח|שכח|טעה|הטועה|אם לא אמר|אם טעה|if you (?:forgot|forget|neglected|omitted|did not)|if (?:forgotten|omitted)|\* ?if)',
    caseSensitive: false);
final _saysNext = RegExp(
    r'(?:אומרים|אומר|מוסיפים|מוסיף|יאמר|יאמרו|מתחילין|מתחילים|ממשיך|מסיים|יסיים|חותם)|:\s*\)?\s*$|\b(?:say|says|said|add|adds|added|recite|recited|insert|inserted|continue|following)\b',
    caseSensitive: false);
final _omerLineHe = RegExp(r'(?:ב|ל)(?:עומר|עמר)');
final _omerLineEn = RegExp(r'today is .* (?:of|to) the omer', caseSensitive: false);

/// Analyzes the segments of one leaf node in one language.
class SegmentAnalyzer {
  /// Maximum number of prayer segments a standalone rubric governs.
  final int maxRubricSpan;
  const SegmentAnalyzer({this.maxRubricSpan = 1});

  List<Segment> analyze(List<(String, String)> raw, {required bool hebrew, bool omerSection = false}) {
    // Unvocalized versions can't use niqqud to tell prayers from rubrics.
    final vocalized = !hebrew ||
        raw.where((r) => nikkudRatio(r.$2) > 0.2).length >= raw.length * 0.3;
    final out = <Segment>[];
    for (final (ref, html) in raw) {
      out.add(_classify(ref, html, hebrew, vocalized));
    }
    _propagate(out);
    if (omerSection) _markOmer(out, hebrew);
    return out;
  }

  Segment _classify(String ref, String html, bool hebrew, bool vocalized) {
    final plain = stripHtml(html).trim();
    final boldOnly = plain.length < 40 &&
        stripHtml(html.replaceAll(RegExp(r'<b>.*?</b>', dotAll: true), '')).trim().isEmpty;
    if (isSpeakerLabel(plain) || boldOnly) {
      return Segment(ref: ref, html: html, hebrew: hebrew, kind: SegmentKind.speaker, runs: [TextRun(html, RunKind.text)]);
    }
    final bool instruction;
    if (_errorNote.hasMatch(normalizeRubric(plain)) && plain.length > 25) {
      instruction = true;
    } else if (hebrew) {
      instruction = vocalized
          ? nikkudRatio(html) < 0.12
          : plain.length < 90 && plain.endsWith(':') && matchRubric(plain) != null;
    } else {
      instruction = _allItalic(html);
    }
    if (instruction) {
      final norm = normalizeRubric(plain);
      final errorNote = _errorNote.hasMatch(norm);
      RubricMatch? governing;
      var strict = false;
      if (!errorNote) {
        // Notes often mix an instruction with halachic commentary; use the
        // last sentence that tells us to say/add something.
        final sentences = norm.split(RegExp(r'(?<=[.!?])\s+(?=\S)'));
        for (final sentence in sentences.reversed) {
          if (_errorNote.hasMatch(sentence)) continue;
          final r = matchRubric(sentence);
          if (r != null && (_saysNext.hasMatch(sentence) || norm.endsWith(':'))) {
            governing = r;
            strict = RegExp(r':\s*\)?\s*$|\bfollowing\b').hasMatch(sentence);
            break;
          }
        }
      }
      final kind = plain.length > 160 ? SegmentKind.note : SegmentKind.instruction;
      return Segment(
        ref: ref,
        html: html,
        hebrew: hebrew,
        kind: kind,
        runs: [TextRun(html, RunKind.text)],
        setsRubric: governing,
        requiresNamedNext: governing != null && !strict ? norm : null,
        followsPrevious: errorNote,
      );
    }
    final runs = hebrew ? _hebrewRuns(html) : _englishRuns(html);
    return Segment(ref: ref, html: html, hebrew: hebrew, kind: SegmentKind.prayer, runs: runs);
  }

  void _propagate(List<Segment> segs) {
    RubricMatch? pending;
    String? named;
    var remaining = 0;
    RubricMatch? lastApplied;
    for (final s in segs) {
      if (s.setsRubric != null) {
        pending = s.setsRubric;
        named = s.requiresNamedNext;
        remaining = named != null ? 1 : maxRubricSpan;
        continue;
      }
      if (s.kind == SegmentKind.prayer) {
        if (pending != null && named != null && !_namesSegment(named, s)) {
          pending = null;
        }
        if (pending != null && remaining > 0 && !s.hasInlineConditions) {
          s.rubric = pending.resolveSeason(s.html);
          lastApplied = s.rubric;
          remaining--;
          continue;
        }
        pending = null;
        lastApplied = null;
      } else if (s.followsPrevious && lastApplied != null) {
        s.rubric = lastApplied;
        pending = null;
      } else if (s.kind == SegmentKind.note || s.kind == SegmentKind.instruction) {
        pending = null;
      }
    }
  }

  static bool _namesSegment(String instruction, Segment s) {
    final words = normalizeRubric(s.html)
        .replaceAll(RegExp(r'[^\u05d0-\u05eaa-z0-9 ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1)
        .take(2)
        .join(' ');
    if (words.isEmpty) return false;
    final inst = instruction.replaceAll(RegExp(r'[^\u05d0-\u05eaa-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ');
    return inst.contains(words);
  }

  void _markOmer(List<Segment> segs, bool hebrew) {
    var counter = 0;
    for (final s in segs) {
      if (s.kind != SegmentKind.prayer) continue;
      final t = normalizeRubric(s.html);
      final isLine = hebrew ? (t.contains('היום') && _omerLineHe.hasMatch(t)) : _omerLineEn.hasMatch(t);
      if (!isLine) continue;
      counter++;
      final m = RegExp(r'(\d{1,2})\s*\.').firstMatch(t);
      final n = m != null ? int.parse(m.group(1)!) : counter;
      if (n < 1 || n > 49) continue;
      s.omerDay = n;
      s.rubric ??= RubricMatch('omerDay == $n', ['Omer day $n'], ['יום $n לעומר']);
    }
  }

  static bool _allItalic(String html) {
    var h = html
        .replaceAll(RegExp(r'<sup[^>]*>.*?</sup>', dotAll: true), '')
        .replaceAll(RegExp(r'<i class="footnote">.*?</i>', dotAll: true), '');
    // Remove italic spans and see if meaningful text remains.
    final withoutItalics = _removeItalic(h);
    final rest = stripHtml(withoutItalics).replaceAll(RegExp(r'[\s()\[\].,;:*]+'), '');
    return rest.isEmpty && stripHtml(h).trim().isNotEmpty;
  }

  static String _removeItalic(String h) {
    final b = StringBuffer();
    var depth = 0;
    var i = 0;
    while (i < h.length) {
      if (h.startsWith('<i', i) && (h.length > i + 2 && (h[i + 2] == '>' || h[i + 2] == ' '))) {
        depth++;
        i = h.indexOf('>', i) + 1;
        continue;
      }
      if (h.startsWith('</i>', i)) {
        depth = depth > 0 ? depth - 1 : 0;
        i += 4;
        continue;
      }
      if (depth == 0) b.write(h[i]);
      i++;
    }
    return b.toString();
  }

  // --------------------------------------------------------- inline runs

  static final _hebPrefix = RegExp(r'^((?:<[^>]+>\s*)*)([^֑-ׇ:<>()]{2,60}?):\s*');
  static final _paren = RegExp(r'\(([^()]{2,400})\)');

  List<TextRun> _hebrewRuns(String html) {
    final runs = <TextRun>[];
    // Split into lines on <br> so each line can carry its own prefix rubric.
    final lines = html.split(RegExp(r'(?=<br\s*/?>)'));
    for (final line in lines) {
      final m = _hebPrefix.firstMatch(line);
      if (m != null) {
        final rubric = matchRubric(m.group(2)!);
        final rest = line.substring(m.end);
        if (rubric != null && nikkudRatio(rest) > 0.15) {
          if (m.group(1)!.isNotEmpty) runs.add(TextRun(m.group(1)!, RunKind.text));
          final resolved = rubric.resolveSeason(rest);
          runs.add(TextRun('${m.group(2)}:', RunKind.marker, resolved));
          runs.add(TextRun(' $rest', RunKind.text, resolved));
          continue;
        }
      }
      runs.addAll(_hebrewParens(line));
    }
    return _merge(runs);
  }

  List<TextRun> _hebrewParens(String line) {
    final runs = <TextRun>[];
    var last = 0;
    for (final m in _paren.allMatches(line)) {
      final inner = m.group(1)!;
      final words = inner.split(RegExp(r'\s+'));
      var k = 0;
      while (k < words.length && nikkudRatio(words[k]) < 0.1) {
        k++;
      }
      if (k == 0 || k == words.length) continue;
      final rubricText = words.take(k).join(' ');
      final rubric = matchRubric(rubricText.replaceAll(':', ''));
      if (rubric == null) continue;
      final body = words.skip(k).join(' ');
      if (m.start > last) runs.add(TextRun(line.substring(last, m.start), RunKind.text));
      final resolved = rubric.resolveSeason(body);
      runs.add(TextRun('($rubricText ', RunKind.marker, resolved));
      runs.add(TextRun('$body)', RunKind.text, resolved));
      last = m.end;
    }
    if (last < line.length) runs.add(TextRun(line.substring(last), RunKind.text));
    return runs;
  }

  List<TextRun> _englishRuns(String html) {
    // Find top-level <i ...>…</i> spans that end with ':' and are rubrics.
    final markers = <(int, int, RubricMatch)>[];
    var i = 0;
    while (i < html.length) {
      final open = html.indexOf(RegExp(r'<i[\s>]'), i);
      if (open < 0) break;
      final tagEnd = html.indexOf('>', open);
      final tag = html.substring(open, tagEnd + 1);
      var depth = 1;
      var j = tagEnd + 1;
      while (j < html.length && depth > 0) {
        if (html.startsWith('</i>', j)) {
          depth--;
          j += 4;
          continue;
        }
        if (RegExp(r'<i[\s>]').matchAsPrefix(html, j) != null) depth++;
        j++;
      }
      if (!tag.contains('footnote')) {
        final inner = stripHtml(html.substring(open, j)).trim();
        final core = inner.replaceAll(RegExp(r'[\s)]+$'), '');
        if (core.endsWith(':') && core.length < 220) {
          final rubric = matchRubric(core);
          if (rubric != null) markers.add((open, j, rubric));
        }
      }
      i = j;
    }
    if (markers.isEmpty) return [TextRun(html, RunKind.text)];
    final runs = <TextRun>[];
    if (markers.first.$1 > 0) runs.add(TextRun(html.substring(0, markers.first.$1), RunKind.text));
    for (var k = 0; k < markers.length; k++) {
      final (s, e, rubric) = markers[k];
      final markerIndex = runs.length;
      runs.add(TextRun(html.substring(s, e), RunKind.marker, rubric));
      final nextStart = k + 1 < markers.length ? markers[k + 1].$1 : html.length;
      var body = html.substring(e, nextStart);
      // Inline marker ("<i>In winter:</i> text<br>more") governs only its
      // own line; a marker on its own line governs the rest.
      String tail = '';
      final ownLine = RegExp(r'^\s*<br\s*/?>').hasMatch(body);
      if (!ownLine) {
        final br = RegExp(r'<br\s*/?>').firstMatch(body);
        if (br != null && k + 1 == markers.length) {
          tail = body.substring(br.start);
          body = body.substring(0, br.start);
        }
      }
      final resolved = rubric.resolveSeason(body);
      runs[markerIndex] = TextRun(html.substring(s, e), RunKind.marker, resolved);
      runs.add(TextRun(body, RunKind.text, resolved));
      if (tail.isNotEmpty) runs.add(TextRun(tail, RunKind.text));
    }
    return _merge(runs);
  }

  static List<TextRun> _merge(List<TextRun> runs) {
    final out = <TextRun>[];
    for (final r in runs) {
      if (r.html.isEmpty) continue;
      if (out.isNotEmpty && out.last.kind == RunKind.text && r.kind == RunKind.text &&
          out.last.rubric == null && r.rubric == null) {
        out[out.length - 1] = TextRun(out.last.html + r.html, RunKind.text);
      } else {
        out.add(r);
      }
    }
    return out;
  }
}
