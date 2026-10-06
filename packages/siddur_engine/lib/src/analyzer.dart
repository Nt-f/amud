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
  TextRun(this.html, this.kind, [this.rubric]);

  bool get conditional => rubric != null;

  /// Part of a run of alternatives within the line (see [Segment.option]).
  bool option = false;

  /// Who says this run, when it differs within the line (corpus `role`,
  /// e.g. the congregation's "Amen" inside the chazzan's Kaddish).
  String? role;
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

  /// An instruction whose only job is to introduce the conditional line
  /// after it ("On Rosh Chodesh say:"); [rubric] is that line's condition.
  bool announces = false;

  /// One of a set of alternative lines ("לר"ח: …", "לפסח: …", "לסכות: …")
  /// inside a longer prayer; the reader keeps the unsaid ones, crossed out,
  /// beside the one that is said.
  bool option = false;

  /// If this is a day of the Omer count line, its day number.
  int? omerDay;

  /// Part of a passage said only in the chazzan's repetition, printed
  /// inside the Amidah (Birkas Kohanim; see [SegmentAnalyzer]).
  bool chazarah = false;

  /// How it is read, from the corpus (null for heuristic analysis): who
  /// says it (`chazzan`, `congregation_then_chazzan`, …), how loud
  /// (`silent`, `undertone`, `aloud`), what one does, how many times.
  String? role;
  String? voice;

  /// How the line is set, from the corpus: `start`, `center`, `end` or
  /// `justify`; null leaves it to the reader's own typesetting.
  String? align;

  /// A title, from the corpus, shared by a run of lines the reader folds
  /// into one row (the zimun, Al Naharot); [foldHe] is its Hebrew.
  String? fold;
  String? foldHe;

  /// Id of a choice the reader makes here (see the app's choices); the
  /// selector is drawn above this line.
  String? select;

  /// The graph node key the corpus gives this line (`kaddish.half`), when it
  /// differs from its section's.
  String? graphNode;
  List<String> gestures = const [];
  int? repeat;

  /// Said only with a minyan.
  bool minyan = false;

  /// English rendering of a Hebrew instruction or note.
  String? en;

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
/// "If you forgot / made a mistake" anywhere in a note, not just at its start
/// ("בכל השנה … ובעשי"ת אם טעה …").
final _mentionsError = RegExp(r'(?:אם|ואם) (?:שכח|טעה|לא אמר)|הטועה|if you (?:forgot|forget|mistakenly|omitted|neglected)',
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
    _markOptions(out);
    _markBirkatKohanim(out, hebrew);
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
          ? nikkudRatio(_dropBold(html)) < 0.12
          : plain.length < 90 && plain.endsWith(':') && matchRubric(plain) != null;
    } else {
      instruction = _allItalic(html);
    }
    if (instruction) {
      final norm = normalizeRubric(plain);
      final errorNote = _errorNote.hasMatch(norm) || (_mentionsError.hasMatch(norm) && !norm.endsWith(':'));
      RubricMatch? governing;
      var strict = false;
      if (!errorNote) {
        // Notes often mix an instruction with halachic commentary; use the
        // last sentence that tells us to say/add something.
        final sentences = norm.split(RegExp(r'(?<=[.!?])\s+(?=\S)'));
        for (final sentence in sentences.reversed) {
          if (_errorNote.hasMatch(sentence)) continue;
          final r = matchRubric(sentence);
          // "Chazzan:"/"In the repetition, Kedushah here:" are roles, not
          // conditions on the next line.
          if (r != null && r.expression != 'minyan' && (_saysNext.hasMatch(sentence) || norm.endsWith(':'))) {
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
    return Segment(ref: ref, html: html, hebrew: hebrew, kind: SegmentKind.prayer, runs: runs, rubric: _wholeLine(runs));
  }

  /// Bold opening words are vocalized even in instructions ("…אומרים
  /// <b>וִיהִי נֹעַם</b>"), so they don't count when telling them apart.
  static String _dropBold(String html) {
    final rest = html.replaceAll(RegExp(r'<b>.*?</b>', dotAll: true), '');
    return RegExp('[א-ת]').allMatches(stripHtml(rest)).length >= 12 ? rest : html;
  }

  /// When every word of a line sits under one inline rubric ("בעשי"ת:
  /// זָכְרֵנוּ…"), the whole line is conditional, not just a phrase in it.
  static RubricMatch? _wholeLine(List<TextRun> runs) {
    RubricMatch? only;
    for (final r in runs) {
      if (r.kind == RunKind.marker) continue;
      if (stripHtml(r.html).replaceAll(RegExp(r'[\s()\[\].,;:׃־—–-]+'), '').isEmpty) continue;
      if (r.rubric == null) return null;
      if (only != null && only.expression != r.rubric!.expression) return null;
      only = r.rubric;
    }
    return only;
  }

  /// Birkas Kohanim printed inside the Amidah, from its instruction or
  /// "ברכנו בברכה המשלשת" up to Sim Shalom / Shalom Rav: the chazzan's
  /// (and the kohanim's) passage, several lines long. A standalone rubric
  /// governs only one line, so a condition on its opening ("בתענית ציבור
  /// אומר כאן הש"ץ ברכת כהנים:") is carried through the rest of it here.
  /// Without an end within a few dozen lines it's left alone: a separate
  /// Birkas Kohanim section is recognized by its title instead.
  static void _markBirkatKohanim(List<Segment> segs, bool hebrew) {
    final start = segs.indexWhere((s) => hebrew ? _bkStartHe(s) : _bkStartEn(s));
    if (start < 0) return;
    var end = -1;
    for (var k = start + 1; k < segs.length && k <= start + 40; k++) {
      if (hebrew ? _bkEndHe(segs[k]) : _bkEndEn(segs[k])) {
        end = k;
        break;
      }
    }
    if (end < 0) return;
    final passage = segs.sublist(start, end);
    // The condition the passage opens with, if any (Mincha: fast days).
    final opening = passage.take(3).map((s) => s.rubric).whereType<RubricMatch>().firstOrNull;
    for (final s in passage) {
      s.chazarah = true;
      if (opening != null && s.rubric == null && s.kind != SegmentKind.note && !s.hasInlineConditions) s.rubric = opening;
    }
  }

  static String _bkText(Segment s) => normalizeRubric(s.html).replaceAll(RegExp(r'[^\u05d0-\u05ea ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool _bkStartHe(Segment s) {
    final t = _bkText(s);
    if (t.contains('בברכה המשלשת')) return true;
    if (!t.contains('ברכת כהנים')) return false;
    return s.kind != SegmentKind.prayer || t.startsWith('ברכת כהנים');
  }

  static bool _bkEndHe(Segment s) {
    final t = _bkText(s);
    if (s.kind == SegmentKind.speaker) return t == 'שלום';
    return s.kind == SegmentKind.prayer && (t.startsWith('שים שלום') || t.startsWith('שלום רב'));
  }

  static final _bkNameEn = RegExp(r'\b(?:birkas|birkat|birchas|birchat|birkath) (?:ha)?[kc]oh?anim(?![a-z])|priestly blessing', caseSensitive: false);
  static final _bkEndPrayerEn = RegExp(
      r'^\W*(?:grant (?:abundant )?peace|sim shalom|shalom rav|abundant peace|establish (?:abundant )?peace|bestow peace|place peace|set peace|put peace)',
      caseSensitive: false);

  static bool _bkStartEn(Segment s) {
    final t = s.plain.trim();
    if (RegExp(r'threefold blessing', caseSensitive: false).hasMatch(t)) return true;
    if (!_bkNameEn.hasMatch(t)) return false;
    // An instruction, a bracketed one printed as text, or a heading line.
    return s.kind != SegmentKind.prayer || t.startsWith('[') || t.startsWith('(') || _bkNameEn.matchAsPrefix(t) != null;
  }

  static bool _bkEndEn(Segment s) {
    final t = s.plain.trim();
    if (s.kind == SegmentKind.speaker) return RegExp(r'peace|shalom', caseSensitive: false).hasMatch(t);
    return s.kind == SegmentKind.prayer && _bkEndPrayerEn.hasMatch(t);
  }

  void _propagate(List<Segment> segs) {
    RubricMatch? pending;
    String? named;
    var remaining = 0;
    RubricMatch? lastApplied;
    var since = 0;
    Segment? setter;
    for (final s in segs) {
      if (s.setsRubric != null) {
        setter = s;
        pending = s.setsRubric;
        named = s.requiresNamedNext;
        remaining = named != null ? 1 : maxRubricSpan;
        continue;
      }
      if (s.kind == SegmentKind.prayer) {
        if (pending != null && named != null && !_namesSegment(named, s)) {
          pending = null;
        }
        // A line may carry its own inline options (Ya'aleh VeYavo's "Rosh
        // Chodesh / Pesach / Sukkos") and still be said only on some days.
        if (pending != null && remaining > 0 && s.rubric == null) {
          s.rubric = pending.resolveSeason(s.html);
          lastApplied = s.rubric;
          since = 0;
          remaining--;
          // The instruction goes (or stays) with the line it introduces.
          if (setter != null && setter.rubric == null) {
            setter
              ..rubric = s.rubric
              ..announces = true;
          }
          setter = null;
          continue;
        }
        if (pending != null && s.rubric != null && setter != null && setter.rubric == null) {
          // "בחורף:" before a line whose own inline marker says the same.
          setter
            ..rubric = s.rubric
            ..announces = true;
        }
        pending = null;
        setter = null;
        // "If you forgot…" notes often come after the rest of the blessing;
        // they still refer to the conditional line a little before.
        if (s.rubric != null) {
          lastApplied = s.rubric;
          since = 0;
        } else if (++since > 2) {
          lastApplied = null;
        }
      } else if (s.followsPrevious && lastApplied != null) {
        s.rubric = lastApplied;
        pending = null;
      } else if (s.kind == SegmentKind.note || s.kind == SegmentKind.instruction) {
        pending = null;
      }
    }
    // A one-sentence instruction about one occasion that doesn't introduce
    // a line of its own ("(On a public fast the chazzan says Aneinu here)")
    // is itself only relevant then.
    for (final s in segs) {
      if (s.kind != SegmentKind.instruction || s.rubric != null || s.followsPrevious || s.setsRubric != null) continue;
      final t = normalizeRubric(s.html);
      if (RegExp(r'[.!?]\s+\S').hasMatch(t.replaceAll(RegExp(r'[.!?)\s]+$'), ''))) continue;
      s.rubric = matchRubric(t);
    }
  }

  /// Alternatives: two or more adjacent conditional runs in a line, or two or
  /// more adjacent lines that are each one conditional phrase. A prayer
  /// split around its options (Ya'aleh VeYavo in some versions) keeps its
  /// condition in the part after them.
  void _markOptions(List<Segment> segs) {
    for (final s in segs) {
      var run = <TextRun>[];
      void close() {
        if (run.where((r) => r.kind == RunKind.text).length >= 2) {
          for (final r in run) {
            r.option = true;
          }
        }
        run = [];
      }

      for (final r in s.runs) {
        final blank = stripHtml(r.html).replaceAll(RegExp(r'[\s:׃,./]+'), '').isEmpty;
        if (r.conditional || (blank && run.isNotEmpty)) {
          run.add(r);
        } else if (!blank) {
          close();
        }
      }
      close();
    }
    for (var i = 0; i < segs.length; i++) {
      bool optionLine(Segment s) =>
          s.kind == SegmentKind.prayer && s.rubric != null && s.runs.any((r) => r.kind == RunKind.marker);
      var j = i;
      while (j < segs.length && optionLine(segs[j])) {
        j++;
      }
      if (j - i < 2) continue;
      for (var k = i; k < j; k++) {
        segs[k].option = true;
      }
      final before = i > 0 ? segs[i - 1] : null;
      final after = j < segs.length ? segs[j] : null;
      if (before?.rubric != null && !before!.option && after != null && after.kind == SegmentKind.prayer && after.rubric == null) {
        after.rubric = before.rubric;
      }
      i = j - 1;
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
        // "בקיץ: מוֹרִיד הַטָּל. בחורף: מַשִּׁיב הָרוּחַ" — more options follow.
        final more = _inlineMarker.allMatches(rest).any((x) => matchRubric(x.group(1) ?? x.group(2)!) != null);
        if (rubric != null && nikkudRatio(rest) > 0.15 && !more) {
          if (m.group(1)!.isNotEmpty) runs.add(TextRun(m.group(1)!, RunKind.text));
          final resolved = rubric.resolveSeason(rest);
          runs.add(TextRun('${m.group(2)}:', RunKind.marker, resolved));
          runs.add(TextRun(' $rest', RunKind.text, resolved));
          continue;
        }
      }
      for (final piece in _hebrewInline(line)) {
        runs.addAll(piece.kind == RunKind.text && piece.rubric == null ? _hebrewParens(piece.html) : [piece]);
      }
    }
    return _merge(runs);
  }

  /// `<small>לפסח:</small>`, or an unvocalized "בחורף:" starting a line or
  /// sentence.
  static final _inlineMarker =
      RegExp(r'<small>([^<]{2,30}?):\s*</small>\s*|(?:^|(?<=[.:׃,]\s))(?:<[^>]+>)*([^\u0591-\u05C7<>:.,()]{2,24}):(?:\s*</[^>]+>)?\s*');

  /// Options marked mid-line, as in Ya'aleh VeYavo:
  /// `בְּיוֹם <small>לר"ח:</small> רֹאשׁ הַחֹדֶשׁ הַזֶּה: <small>לפסח:</small> …`.
  /// Each option runs to the next marker or its closing colon.
  List<TextRun> _hebrewInline(String line) {
    final runs = <TextRun>[];
    var last = 0;
    final markers = _inlineMarker.allMatches(line).toList();
    for (var k = 0; k < markers.length; k++) {
      final m = markers[k];
      if (m.start < last) continue;
      final label = m.group(1) ?? m.group(2)!;
      if (m.group(2) != null && RegExp(r'[\u0591-\u05C7]').hasMatch(label)) continue;
      final rubric = isSpeakerLabel(label) ? null : matchRubric(label);
      if (rubric == null) continue;
      final limit = k + 1 < markers.length ? markers[k + 1].start : line.length;
      var end = limit;
      final colon = RegExp(r'[:׃]').firstMatch(line.substring(m.end, limit));
      if (colon != null) end = m.end + colon.end;
      final body = line.substring(m.end, end);
      if (nikkudRatio(body) < 0.15) continue;
      if (m.start > last) runs.add(TextRun(line.substring(last, m.start), RunKind.text));
      final resolved = rubric.resolveSeason(body);
      runs.add(TextRun(line.substring(m.start, m.end), RunKind.marker, resolved));
      runs.add(TextRun(body, RunKind.text, resolved));
      last = end;
    }
    if (last < line.length) runs.add(TextRun(line.substring(last), RunKind.text));
    return runs;
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
    final options = _englishOptions(html);
    if (options != null) return options;
    final parens = _englishParens(html);
    if (parens != null) return parens;
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

  static final _slashList = RegExp(r'<i>([^<]{3,120}/[^<]{3,120})</i>');

  /// "on this day of the: <i>Rosh Chodesh/Festival of Matzos/Festival of
  /// Sukkos</i>" — one run per occasion, the slash kept with the option
  /// after it.
  List<TextRun>? _englishOptions(String html) {
    final m = _slashList.firstMatch(html);
    if (m == null) return null;
    final parts = m.group(1)!.split('/');
    // "Festival of Matzos" names Pesach, not any festival.
    final rubrics = [for (final p in parts) matchRubric(p.replaceAll(RegExp(r'festival of', caseSensitive: false), ''))];
    if (rubrics.any((r) => r == null)) return null;
    return [
      if (m.start > 0) TextRun(html.substring(0, m.start), RunKind.text),
      for (var i = 0; i < parts.length; i++) TextRun('${i == 0 ? '' : '/'}<i>${parts[i]}</i>', RunKind.text, rubrics[i]),
      if (m.end < html.length) ..._englishRuns(html.substring(m.end)),
    ];
  }

  static final _enParen = RegExp(r'\(([^():]{3,60}):\s*([^()]{1,120})\)');

  /// "above (Ten Days of Penitence: far above) all the blessings".
  List<TextRun>? _englishParens(String html) {
    final runs = <TextRun>[];
    var last = 0;
    for (final m in _enParen.allMatches(html)) {
      final rubric = matchRubric('${m.group(1)}:');
      if (rubric == null || isSpeakerLabel(m.group(1)!)) continue;
      if (m.start > last) runs.add(TextRun(html.substring(last, m.start), RunKind.text));
      runs.add(TextRun('(${m.group(1)}: ', RunKind.marker, rubric));
      runs.add(TextRun('${m.group(2)})', RunKind.text, rubric));
      last = m.end;
    }
    if (runs.isEmpty) return null;
    if (last < html.length) runs.add(TextRun(html.substring(last), RunKind.text));
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
