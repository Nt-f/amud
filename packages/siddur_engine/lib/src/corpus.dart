/// The tagged corpus (corpus/SCHEMA.md, built into assets/corpus by
/// tool/corpus/build_assets.py): every segment of a nusach's siddur
/// annotated with its kind, condition, alternatives and how it is read.
/// Where a leaf is in the corpus, the resolver takes its segments from here
/// instead of guessing from formatting.
library;

import 'analyzer.dart';
import 'model.dart';
import 'rubrics.dart';
import 'rules.dart';

/// The title of Amud's own text in a book's version lists, in both
/// languages (it is listed first, before the Sefaria versions).
const corpusVersionTitle = 'Amud';

class CorpusPart {
  final String text;
  final String kind;
  final String? when;
  final String? alt;
  final String? role;
  final String? voice;
  final String? amidah;
  final bool minyan;
  final List<String> gestures;
  final int? repeat;
  final String? en;
  final bool forgot;

  const CorpusPart(this.text, this.kind,
      {this.when,
      this.alt,
      this.role,
      this.voice,
      this.amidah,
      this.minyan = false,
      this.gestures = const [],
      this.repeat,
      this.en,
      this.forgot = false});

  factory CorpusPart.fromJson(Map<String, Object?> j) => CorpusPart(
        j['text'] as String,
        (j['kind'] as String?) ?? 'prayer',
        when: j['when'] as String?,
        alt: j['alt'] as String?,
        role: j['role'] as String?,
        voice: j['voice'] as String?,
        amidah: j['amidah'] as String?,
        minyan: j['minyan'] == true,
        gestures: [for (final g in (j['gestures'] as List? ?? const [])) g as String],
        repeat: (j['repeat'] as num?)?.toInt(),
        en: j['en'] as String?,
        forgot: j['forgot'] == true,
      );

  bool get prayer => kind == 'prayer';
}

class CorpusSegment {
  final String ref;
  final List<CorpusPart> parts;

  /// English only: refs of the Hebrew segments it translates.
  final List<String> he;
  const CorpusSegment(this.ref, this.parts, [this.he = const []]);

  String get html => parts.map((p) => p.text).join();
}

class CorpusText {
  final String version;
  final List<CorpusSegment> segments;
  const CorpusText(this.version, this.segments);
}

class CorpusLeaf {
  final String path;
  final String node;
  final String? when;
  final String? service;
  final CorpusText? he;
  final CorpusText? en;
  const CorpusLeaf(this.path, this.node, this.when, this.service, this.he, this.en);
}

/// A service as the service graph lays it out for one siddur: its own
/// sections in order, and what is inserted among them on the days it is
/// said (corpus/graph.json, built into the asset).
class CorpusService {
  final String en;
  final String he;

  /// The section that is the whole service, to read straight through;
  /// null when the service is a run of sections in a larger one (Koren's
  /// weekday Shacharit in "Weekdays").
  final String? whole;

  /// Paths of the service's sections, in book order.
  final List<String> sections;
  final List<InsertRule> inserts;
  const CorpusService(this.en, this.he, this.whole, this.sections, this.inserts);

  factory CorpusService.fromJson(Map<String, Object?> j) => CorpusService(
        j['en'] as String,
        j['he'] as String,
        j['whole'] as String?,
        [for (final s in j['sections'] as List) s as String],
        [for (final r in j['inserts'] as List) InsertRule.fromJson((r as Map).cast<String, Object?>())],
      );
}

/// A Sefaria version a corpus text began as, credited in the app.
class CorpusSource {
  final String version;
  final String license;
  final String? source;
  const CorpusSource(this.version, this.license, this.source);
}

/// One language of the corpus as a whole: its license (the most restrictive
/// of its sources) and size.
class CorpusEdition {
  final String license;
  final int segments;
  final List<CorpusSource> sources;
  const CorpusEdition(this.license, this.segments, this.sources);

  factory CorpusEdition.fromJson(Map<String, Object?> j) => CorpusEdition(
        j['license'] as String,
        (j['segments'] as num).toInt(),
        [
          for (final s in j['sources'] as List)
            CorpusSource((s as Map)['version'] as String, s['license'] as String, s['source'] as String?),
        ],
      );
}

class Corpus {
  final String book;
  final String heTitle;

  /// The siddur's slug (`ashkenaz`).
  final String nusach;
  final Map<String, CorpusLeaf> leaves;

  /// The table of contents, in Sefaria's schema form; see [index].
  final Map<String, Object?>? _index;

  /// Each language's edition, by `he`/`en`.
  final Map<String, CorpusEdition> editions;

  /// What each personal circumstance (`if_…`) means, for its label: "For a
  /// man", "Three or more ate together". The engine can't know these, so
  /// such lines are shown, marked, for the reader to decide.
  final Map<String, String> labels;

  /// Where sections from elsewhere in the book are said on the days they
  /// apply (Hallel after the Amidah, Musaf after Uva LeTziyon…), derived
  /// from the service graph (corpus/graph.json) at build time.
  final List<InsertRule> inserts;

  /// The services the graph lays out for this siddur, by graph name
  /// (`shacharit.weekday`, `mincha.weekday`, `maariv.weekday`).
  final Map<String, CorpusService> services;
  const Corpus(this.book, this.leaves,
      [this.labels = const {},
      this.inserts = const [],
      this.services = const {},
      this.heTitle = '',
      this.nusach = '',
      this._index,
      this.editions = const {}]);

  /// The book's table of contents, built from the corpus (null for a
  /// corpus without one, which then uses Sefaria's).
  SchemaNode? get index => _index == null ? null : SchemaNode.parse(_index.cast<String, dynamic>());

  /// The corpus as a version in a book's list, for [language] `he` or `en`.
  VersionInfo? versionInfo(String language) {
    final e = editions[language];
    if (e == null) return null;
    return VersionInfo(
      language: language,
      actualLanguage: language,
      versionTitle: corpusVersionTitle,
      versionTitleInHebrew: 'עמוד',
      license: e.license,
      isPrimary: true,
      direction: language == 'he' ? 'rtl' : 'ltr',
      segments: e.segments,
      file: 'corpus:$nusach:$language',
    );
  }

  factory Corpus.fromJson(Map<String, Object?> j) {
    List<CorpusPart> parts(Object? l) =>
        [for (final p in l as List) CorpusPart.fromJson((p as Map).cast<String, Object?>())];
    CorpusText? text(Object? t, bool english) {
      if (t is! Map) return null;
      return CorpusText(t['version'] as String, [
        for (final s in t['segs'] as List)
          english
              ? CorpusSegment(s[0] as String, parts(s[2]), [for (final h in s[1] as List) h as String])
              : CorpusSegment(s[0] as String, parts(s[1])),
      ]);
    }

    final leaves = <String, CorpusLeaf>{};
    for (final e in (j['leaves'] as Map).entries) {
      final l = (e.value as Map).cast<String, Object?>();
      final when = l['when'] as String?;
      leaves[e.key as String] = CorpusLeaf(e.key as String, l['node'] as String, when == 'true' ? null : when,
          l['service'] as String?, text(l['he'], false), text(l['en'], true));
    }
    return Corpus(
      j['book'] as String,
      leaves,
      ((j['labels'] as Map?) ?? const {}).cast<String, String>(),
      [
        for (final r in (j['inserts'] as List? ?? const [])) InsertRule.fromJson((r as Map).cast<String, Object?>()),
      ],
      {
        for (final e in ((j['services'] as Map?) ?? const {}).entries)
          e.key as String: CorpusService.fromJson((e.value as Map).cast<String, Object?>()),
      },
      (j['heTitle'] as String?) ?? j['book'] as String,
      (j['nusach'] as String?) ?? '',
      (j['index'] as Map?)?.cast<String, Object?>(),
      {
        for (final e in ((j['editions'] as Map?) ?? const {}).entries)
          e.key as String: CorpusEdition.fromJson((e.value as Map).cast<String, Object?>()),
      },
    );
  }

  CorpusLeaf? leaf(String path) => leaves[path];
}

/// The corpus in one language as a [TextVersion], so it can be listed and
/// picked like any version: a leaf's segments are the corpus's.
class CorpusTextVersion extends TextVersion {
  final Corpus corpus;
  final bool hebrew;
  CorpusTextVersion(this.corpus, VersionInfo info)
      : hebrew = info.language == 'he',
        super(info, null);

  @override
  List<(String, String)>? segmentsAt(List<String> path) {
    final leaf = corpus.leaf(path.join('/'));
    final t = hebrew ? leaf?.he : leaf?.en;
    if (t == null || t.segments.isEmpty) return null;
    return [for (final s in t.segments) (s.ref, s.html)];
  }
}

const _kinds = {
  'prayer': SegmentKind.prayer,
  'instruction': SegmentKind.instruction,
  'note': SegmentKind.note,
  'commentary': SegmentKind.note,
  'speaker': SegmentKind.speaker,
  'heading': SegmentKind.speaker,
};

/// Turns corpus segments into the resolver's [Segment]s.
List<Segment> corpusSegments(List<CorpusSegment> segs,
    {required bool hebrew, Map<String, String> labels = const {}}) {
  final out = <Segment>[];
  // The label for a condition: the instruction that announced it ("On Rosh
  // Chodesh:"), else the rubric table's name for it.
  final announced = <String, (String, String)>{};
  RubricMatch rubric(String when) {
    final ifs = {
      for (final m in RegExp(r'(!?)\s*\b(if_\w+)').allMatches(when))
        if (labels[m.group(2)] != null) '${m.group(1)!.isEmpty ? 'If' : 'If not'}: ${labels[m.group(2)]}'
    };
    if (ifs.isNotEmpty) {
      final l = [ifs.join(' / ')];
      return RubricMatch(when, l, l);
    }
    final a = announced[when];
    if (a != null) return RubricMatch(when, [a.$1], [a.$2]);
    return labelsForCondition(when) ?? RubricMatch(when, const [], const []);
  }

  void announce(CorpusPart p) {
    if (p.when == null || p.prayer) return;
    final en = (p.en ?? (hebrew ? null : stripHtml(p.text))) ?? '';
    final he = hebrew ? stripHtml(p.text) : '';
    String tidy(String s) => s.trim().replaceAll(RegExp(r'[:：\s]+$'), '').replaceAll(RegExp(r'^[(\s]+|[)\s]+$'), '');
    announced[p.when!] = (tidy(en), tidy(he));
  }

  for (final s in segs) {
    for (final p in s.parts) {
      announce(p);
    }
    final prayers = s.parts.where((p) => p.prayer).toList();
    final first = prayers.firstOrNull ?? s.parts.first;
    final kind = prayers.isNotEmpty ? SegmentKind.prayer : (_kinds[first.kind] ?? SegmentKind.instruction);
    // One condition for the whole line, when every part shares it.
    final whens = {for (final p in s.parts) p.when};
    final whole = whens.length == 1 ? whens.single : null;
    final runs = <TextRun>[];
    for (final p in s.parts) {
      final r = TextRun(p.text, p.prayer || s.parts.length == 1 ? RunKind.text : RunKind.marker,
          whole == null && p.when != null ? rubric(p.when!) : null)
        ..option = whole == null && p.alt != null
        ..role = p.role != first.role ? p.role : null;
      runs.add(r);
    }
    final seg = Segment(
      ref: s.ref,
      html: s.html,
      hebrew: hebrew,
      kind: kind,
      runs: runs,
      rubric: whole == null ? null : rubric(whole),
      followsPrevious: s.parts.every((p) => p.forgot || p.prayer) && s.parts.any((p) => p.forgot),
    )
      ..option = whole != null && s.parts.any((p) => p.alt != null)
      ..chazarah = s.parts.any((p) => p.amidah == 'repetition')
      ..role = first.role
      ..voice = first.voice
      ..gestures = [for (final p in s.parts) ...p.gestures]
      ..repeat = first.repeat
      ..minyan = s.parts.every((p) => p.minyan || !p.prayer) && prayers.isNotEmpty && prayers.every((p) => p.minyan)
      ..en = kind == SegmentKind.prayer ? null : s.parts.map((p) => p.en).whereType<String>().join(' ');
    if (seg.en?.isEmpty ?? false) seg.en = null;
    out.add(seg);
  }
  // An instruction line that only introduces the next line's condition.
  for (var i = 0; i + 1 < out.length; i++) {
    final a = out[i], b = out[i + 1];
    if (a.kind == SegmentKind.instruction && a.rubric != null && b.rubric?.expression == a.rubric!.expression) {
      a.announces = true;
    }
  }
  return out;
}

/// Pairs each Hebrew segment with the English segments that translate it
/// (by the corpus alignment); English with no counterpart goes with the
/// line before it.
List<Segment?> alignedTranslation(CorpusText he, CorpusText en, List<Segment> enSegs) {
  final index = {for (var i = 0; i < he.segments.length; i++) he.segments[i].ref: i};
  final groups = List<List<Segment>>.generate(he.segments.length, (_) => []);
  var last = 0;
  for (var i = 0; i < en.segments.length; i++) {
    final at = en.segments[i].he.map((r) => index[r]).whereType<int>().firstOrNull ?? last;
    if (groups.isEmpty) break;
    groups[at].add(enSegs[i]);
    last = at;
  }
  return [
    for (final g in groups)
      if (g.isEmpty)
        null
      else if (g.length == 1)
        g.single
      else
        _join(g),
  ];
}

Segment _join(List<Segment> g) {
  final first = g.first;
  return Segment(
    ref: first.ref,
    html: g.map((s) => s.html).join('<br>'),
    hebrew: false,
    kind: g.any((s) => s.kind == SegmentKind.prayer) ? SegmentKind.prayer : first.kind,
    runs: [
      for (final (i, s) in g.indexed) ...[
        if (i > 0) TextRun('<br>', RunKind.text),
        // A whole-line condition of one of the joined lines stays with it.
        for (final r in s.runs)
          TextRun(r.html, r.kind, r.rubric ?? (g.length > 1 ? s.rubric : null))
            ..option = r.option
            ..role = r.role,
      ],
    ],
  );
}
