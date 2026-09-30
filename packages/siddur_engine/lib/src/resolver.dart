import 'dart:convert';

import 'package:hebcal/hebcal.dart';

import 'analyzer.dart';
import 'condition.dart';
import 'day_context.dart';
import 'model.dart';
import 'rubrics.dart';
import 'rules.dart';

/// Reads bundled files (gzip-compressed JSON etc.). The Flutter app
/// implements this with `rootBundle`; tests use `dart:io`.
abstract class TextSource {
  Future<List<int>> readBytes(String file);
}

/// Decodes gzip bytes. Injected so the engine stays free of dart:io.
typedef Gunzip = List<int> Function(List<int> bytes);

/// Loads books, versions and per-book rule overrides, with caching.
class SiddurLibrary {
  final TextSource source;
  final Gunzip gunzip;
  final String baseDir;
  Manifest? _manifest;
  final _indexes = <String, SchemaNode>{};
  final _texts = <String, Future<TextVersion>>{};

  SiddurLibrary(this.source, this.gunzip, {this.baseDir = 'assets/sefaria'});

  Future<Manifest> manifest() async =>
      _manifest ??= Manifest.fromJson(jsonDecode(utf8.decode(await source.readBytes('$baseDir/manifest.json')))
          as Map<String, dynamic>);

  Future<SchemaNode> index(BookInfo book) async {
    final cached = _indexes[book.slug];
    if (cached != null) return cached;
    final j = jsonDecode(utf8.decode(gunzip(await source.readBytes('$baseDir/${book.indexFile}'))))
        as Map<String, dynamic>;
    return _indexes[book.slug] = SchemaNode.parse(j['schema'] as Map<String, dynamic>);
  }

  Future<TextVersion> version(VersionInfo v) => _texts.putIfAbsent(v.file, () async {
        final j = jsonDecode(utf8.decode(gunzip(await source.readBytes('$baseDir/${v.file}'))))
            as Map<String, dynamic>;
        final text = j['text'];
        _patch(v.versionTitle.trim(), text);
        return TextVersion(v, text);
      });

  /// Fills known gaps in Sefaria versions: the cantillated Shema leaves
  /// its first two lines empty, which would otherwise drop "Shema Yisrael"
  /// whenever that version is preferred.
  static const _patches = {
    'Shema with Cantillation': {
      'Weekday/Shacharit/Blessings of the Shema/Shema': {
        // Deuteronomy 6:4, Miqra according to the Masorah (CC-BY-SA).
        0: '<b>שְׁמַ֖<big>ע</big> יִשְׂרָאֵ֑ל יְהֹוָ֥ה אֱלֹהֵ֖ינוּ יְהֹוָ֥ה&thinsp;<small>׀</small>&thinsp;אֶחָֽ<big>ד</big>׃</b>',
        1: '<small>בָּרוּךְ שֵׁם כְּבוֹד מַלְכוּתוֹ לְעוֹלָם וָעֶד׃</small>',
      },
    },
  };

  static void _patch(String title, Object? text) {
    final byPath = _patches[title];
    if (byPath == null) return;
    for (final e in byPath.entries) {
      Object? node = text;
      for (final p in e.key.split('/')) {
        node = node is Map ? node[p] : null;
      }
      if (node is! List) continue;
      for (final s in e.value.entries) {
        if (s.key < node.length && node[s.key] is String && (node[s.key] as String).trim().isEmpty) node[s.key] = s.value;
      }
    }
  }

  /// Registers an additional (e.g. user-downloaded) version.
  void putVersion(TextVersion v) => _texts[v.info.file] = Future.value(v);
}

/// Ordered version preference per language; the first version that has
/// text for a node is used (Sefaria-style merging).
class VersionSelection {
  final List<TextVersion> hebrew;
  final List<TextVersion> translation;
  const VersionSelection(this.hebrew, this.translation);

  (VersionInfo?, List<(String, String)>?) pick(List<TextVersion> list, List<String> path) {
    for (final v in list) {
      final s = v.segmentsAt(path);
      if (s != null) return (v.info, s);
    }
    return (null, null);
  }
}

/// How excluded (not-said-today) content is presented. [hide] removes it
/// entirely: whole sections, single lines and inline phrases, along with
/// headings left empty.
enum ExcludedDisplay { hide, collapse, dim }

class ResolveOptions {
  final ExcludedDisplay excluded;
  final bool showNotes;
  final bool showInstructions;
  final bool showTranslation;

  /// Hebrew text of the prayers themselves.
  final bool showHebrew;

  /// Languages for instructions, notes and speaker labels, independent of
  /// the prayer text languages.
  final bool notesHebrew;
  final bool notesTranslation;

  /// Node ids the user explicitly expanded despite being excluded.
  final Set<String> forceExpanded;
  const ResolveOptions({
    this.excluded = ExcludedDisplay.collapse,
    this.showNotes = false,
    this.showInstructions = true,
    this.showTranslation = true,
    this.showHebrew = true,
    this.notesHebrew = true,
    this.notesTranslation = true,
    this.forceExpanded = const {},
  });
}

/// Whether an item is governed by a condition, and its outcome today.
enum Applicability {
  /// Not conditional — always said.
  always,

  /// Conditional and applies today (highlight it).
  today,

  /// Conditional and does not apply today.
  notToday,

  /// Conditional, but depends on something we can't determine.
  unknown,
}

sealed class RenderItem {
  final String key;
  const RenderItem(this.key);
}

class HeadingItem extends RenderItem {
  final SchemaNode node;
  final int level;
  final Applicability applicability;
  final String? labelEn;
  final String? labelHe;
  const HeadingItem(super.key, this.node, this.level, this.applicability, this.labelEn, this.labelHe);
}

/// Marks the start of a section spliced in by an [InsertRule].
class InsertedSectionItem extends RenderItem {
  final SchemaNode node;
  final String labelEn;
  final String labelHe;
  const InsertedSectionItem(super.key, this.node, this.labelEn, this.labelHe);
}

/// A section that isn't said today, shown as a single collapsed row.
class CollapsedSectionItem extends RenderItem {
  final SchemaNode node;
  final String labelEn;
  final String labelHe;
  const CollapsedSectionItem(super.key, this.node, this.labelEn, this.labelHe);
}

/// A run of text inside a segment with its own applicability.
class ResolvedRun {
  final String html;
  final bool marker;
  final Applicability applicability;
  final String? labelEn;
  final String? labelHe;
  const ResolvedRun(this.html, this.marker, this.applicability, this.labelEn, this.labelHe);
}

class ResolvedSegment {
  final Segment segment;
  final List<ResolvedRun> runs;
  const ResolvedSegment(this.segment, this.runs);
}

/// One row: Hebrew with (optionally) aligned translation.
class SegmentItem extends RenderItem {
  final SchemaNode node;
  final ResolvedSegment? he;
  final ResolvedSegment? tr;
  final SegmentKind kind;
  final Applicability applicability;
  final String? labelEn;
  final String? labelHe;

  /// Rendered dimmed/collapsed because it's not said today.
  final bool excluded;
  const SegmentItem(super.key, this.node, this.he, this.tr, this.kind, this.applicability, this.labelEn,
      this.labelHe, this.excluded);
}

/// Consecutive segments that aren't said today, folded into one row.
class ExcludedGroupItem extends RenderItem {
  final List<SegmentItem> items;
  const ExcludedGroupItem(super.key, this.items);

  /// Distinct labels of the grouped conditions.
  List<String> get labelsEn => {for (final i in items) if (i.labelEn != null) i.labelEn!}.toList();
  List<String> get labelsHe => {for (final i in items) if (i.labelHe != null) i.labelHe!}.toList();
}

/// Generated content (e.g. today's Omer count) inserted by the engine.
class DynamicItem extends RenderItem {
  final String kind;
  final Map<String, Object?> data;
  const DynamicItem(super.key, this.kind, this.data);
}

/// Provides a [DayContext] for a service; the app decides the date,
/// location (Israel/diaspora) and customs.
typedef ContextProvider = DayContext Function(Service service);

/// Produces the render list for a section of a book.
class SiddurResolver {
  final List<SectionRule> sectionRules;
  final List<SegmentRule> segmentRules;
  final List<InsertRule> insertRules;
  final List<CalloutRule> callouts;
  final SegmentAnalyzer analyzer;

  SiddurResolver({
    List<SectionRule>? sectionRules,
    this.segmentRules = const [],
    this.insertRules = const [],
    List<CalloutRule>? callouts,
    this.analyzer = const SegmentAnalyzer(),
  })  : sectionRules = sectionRules ?? defaultSectionRules,
        callouts = callouts ?? defaultCallouts;

  final _analysisCache = <String, List<Segment>>{};

  /// Parses a per-book rules JSON (`{"sections": [...], "segments": [...]}`)
  /// and returns a resolver with those rules taking precedence.
  SiddurResolver withOverrides(Map<String, Object?> json) => SiddurResolver(
        sectionRules: [
          for (final r in (json['sections'] as List? ?? const [])) SectionRule.fromJson(r as Map<String, Object?>),
          ...sectionRules,
        ],
        segmentRules: [
          for (final r in (json['segments'] as List? ?? const [])) SegmentRule.fromJson(r as Map<String, Object?>),
          ...segmentRules,
        ],
        insertRules: [
          for (final r in (json['inserts'] as List? ?? const [])) InsertRule.fromJson(r as Map<String, Object?>),
          ...insertRules,
        ],
        callouts: callouts,
        analyzer: analyzer,
      );

  static Service serviceFor(SchemaNode node, [Service fallback = Service.other]) {
    var s = fallback;
    for (final n in [...node.ancestors, node]) {
      for (final r in serviceRules) {
        if (r.title.hasMatch(n.en)) {
          s = r.service!;
          break;
        }
      }
    }
    return s;
  }

  SectionRule? sectionRuleFor(SchemaNode node) {
    final anc = node.ancestors.map((a) => a.en).toList();
    for (final r in sectionRules) {
      if (r.matches(node.en, anc)) return r;
    }
    return null;
  }

  Applicability _eval(Condition c, DayContext ctx) {
    final unknown = <String>{};
    final v = c.eval(ctx.env, unknown);
    if (unknown.isNotEmpty) return Applicability.unknown;
    return v ? Applicability.today : Applicability.notToday;
  }

  List<Segment> analyzed(VersionInfo v, SchemaNode leaf, List<(String, String)> raw) {
    final key = '${v.file}|${leaf.id}';
    return _analysisCache.putIfAbsent(key, () {
      final omer = RegExp(r'omer', caseSensitive: false).hasMatch(leaf.id);
      final segs = analyzer.analyze(raw, hebrew: v.language == 'he', omerSection: omer);
      for (final r in segmentRules) {
        if (r.path == leaf.id && r.index >= 0 && r.index < segs.length) {
          segs[r.index].rubric = RubricMatch(r.when, [r.labelEn], [r.labelHe]);
        }
      }
      return segs;
    });
  }

  /// Resolves [node] (a section or a leaf) into render items.
  List<RenderItem> resolve(SchemaNode node, VersionSelection versions, ContextProvider contexts,
      {ResolveOptions options = const ResolveOptions()}) {
    final out = <RenderItem>[];
    final baseLevel = node.path.length;
    final baseService = serviceFor(node, Service.shacharit);
    // Ancestor section rules apply to everything below.
    Applicability inherited = Applicability.always;
    for (final a in node.ancestors) {
      final r = sectionRuleFor(a);
      if (r != null) {
        final ap = _eval(r.condition, contexts(serviceFor(a, baseService)));
        if (ap == Applicability.notToday) inherited = ap;
      }
    }
    _resolveNode(node, versions, contexts, options, out, baseLevel, baseService, inherited, true);
    return switch (options.excluded) {
      ExcludedDisplay.collapse => _group(out),
      ExcludedDisplay.hide => _pruneEmptyHeadings(out),
      ExcludedDisplay.dim => out,
    };
  }

  /// Drops headings with nothing under them (their content was all hidden),
  /// keeping the top heading so the page is never blank.
  static List<RenderItem> _pruneEmptyHeadings(List<RenderItem> items) {
    final keep = List.filled(items.length, true);
    for (var i = 0; i < items.length; i++) {
      final h = items[i];
      if (h is! HeadingItem || h.level == 0) continue;
      var empty = true;
      for (var j = i + 1; j < items.length; j++) {
        final n = items[j];
        if (n is HeadingItem) {
          if (n.level <= h.level) break;
          continue;
        }
        empty = false;
        break;
      }
      keep[i] = !empty;
    }
    return [for (var i = 0; i < items.length; i++) if (keep[i]) items[i]];
  }

  /// Folds runs of 2+ excluded segments into [ExcludedGroupItem]s.
  static List<RenderItem> _group(List<RenderItem> items) {
    final out = <RenderItem>[];
    final buf = <SegmentItem>[];
    void flush() {
      if (buf.length >= 2) {
        out.add(ExcludedGroupItem('g:${buf.first.key}', List.of(buf)));
      } else {
        out.addAll(buf);
      }
      buf.clear();
    }

    for (final it in items) {
      if (it is SegmentItem && it.excluded) {
        buf.add(it);
      } else {
        flush();
        out.add(it);
      }
    }
    flush();
    return out;
  }

  void _resolveNode(SchemaNode node, VersionSelection versions, ContextProvider contexts, ResolveOptions options,
      List<RenderItem> out, int baseLevel, Service service, Applicability inherited, bool isTop) {
    final svc = serviceFor(node, service);
    final ctx = contexts(svc);
    final rule = sectionRuleFor(node);
    var ap = Applicability.always;
    if (rule != null && rule.when != 'true') {
      ap = _eval(rule.condition, ctx);
    }
    final excluded = inherited == Applicability.notToday || ap == Applicability.notToday;
    final forced = options.forceExpanded.contains(node.id);
    if (excluded && !forced && !isTop) {
      if (options.excluded != ExcludedDisplay.hide) {
        out.add(CollapsedSectionItem('c:${node.id}', node, rule?.labelEn ?? node.en, rule?.labelHe ?? node.he));
      }
      return;
    }
    out.add(HeadingItem('h:${node.id}', node, node.path.length - baseLevel, ap, rule?.labelEn, rule?.labelHe));

    if (ap == Applicability.today && rule != null && RegExp('omer', caseSensitive: false).hasMatch(rule.when)) {
      final day = ctx.number('omerDay').toInt();
      if (day > 0) {
        final ev = OmerEvent(ctx.hdate, day);
        out.add(DynamicItem('omer:${node.id}', 'omer', {
          'day': day,
          'he': ev.getTodayIs('he'),
          'en': ev.getTodayIs('en'),
          'sefiraHe': ev.sefira(OmerLang.he),
          'sefiraEn': ev.sefira(OmerLang.en),
          'sefiraTranslit': ev.sefira(OmerLang.translit),
        }));
      }
    }

    if (!excluded) {
      final anc = node.ancestors.map((a) => a.en).toList();
      for (final c in callouts) {
        if (c.matches(node.en, anc) && _eval(Condition.parse(c.when), ctx) == Applicability.today) {
          out.add(DynamicItem('n:${node.id}:${c.en.hashCode}', 'note', {'en': c.en, 'he': c.he}));
        }
      }
    }

    if (node.isLeaf) {
      _resolveLeaf(node, versions, ctx, options, out, excluded && !forced);
      return;
    }
    final childInherited = excluded && !forced ? Applicability.notToday : Applicability.always;
    for (final c in node.children) {
      if (!excluded) _inserts(c, true, versions, contexts, options, out, baseLevel, svc);
      _resolveNode(c, versions, contexts, options, out, baseLevel, svc, childInherited, false);
      if (!excluded) _inserts(c, false, versions, contexts, options, out, baseLevel, svc);
    }
  }

  void _inserts(SchemaNode anchor, bool before, VersionSelection versions, ContextProvider contexts,
      ResolveOptions options, List<RenderItem> out, int baseLevel, Service svc) {
    for (final r in insertRules) {
      if (r.anchor != anchor.id || r.before != before) continue;
      var root = anchor;
      while (root.parent != null) {
        root = root.parent!;
      }
      final target = root.find(r.insert);
      if (target == null) continue;
      final ctx = contexts(serviceFor(anchor, svc));
      if (_eval(r.condition, ctx) != Applicability.today) continue;
      out.add(InsertedSectionItem('i:${r.anchor}>${r.insert}', target, r.labelEn, r.labelHe));
      _resolveNode(target, versions, contexts, options, out, baseLevel - 1 + (anchor.path.length - target.path.length),
          serviceFor(anchor, svc), Applicability.always, true);
    }
  }

  void _resolveLeaf(SchemaNode leaf, VersionSelection versions, DayContext ctx, ResolveOptions options,
      List<RenderItem> out, bool sectionExcluded) {
    final (heInfo, heRaw) = versions.pick(versions.hebrew, leaf.path);
    final (trInfo, trRaw) = options.showTranslation || options.notesTranslation
        ? versions.pick(versions.translation, leaf.path)
        : (null, null);
    final he = heInfo == null ? const <Segment>[] : analyzed(heInfo, leaf, heRaw!);
    final tr = trInfo == null ? const <Segment>[] : analyzed(trInfo, leaf, trRaw!);
    final aligned = he.isNotEmpty && tr.isNotEmpty && he.length == tr.length;

    void emit(int i, Segment? h, Segment? t) {
      final primary = h ?? t!;
      if (primary.kind == SegmentKind.note && !options.showNotes) return;
      if ((primary.kind == SegmentKind.instruction || primary.kind == SegmentKind.speaker) &&
          !options.showInstructions) {
        return;
      }
      final key = 's:${leaf.id}:${primary.ref}:${h == null ? 't' : (t == null ? 'h' : 'b')}';
      // Segment-level condition: prefer Hebrew analysis, fall back to the
      // translation's own rubric when unaligned or Hebrew has none.
      final rubric = h?.rubric ?? (aligned || h == null ? t?.rubric : null);
      // Prayer text and notes each have their own language choice.
      final prayer = primary.kind == SegmentKind.prayer;
      if (!(prayer ? options.showHebrew : options.notesHebrew)) h = null;
      if (!(prayer ? options.showTranslation : options.notesTranslation)) t = null;
      if (h == null && t == null) return;
      var ap = rubric == null ? Applicability.always : _eval(rubric.condition, ctx);
      if (sectionExcluded) ap = Applicability.notToday;
      final isExcluded = ap == Applicability.notToday;
      if (isExcluded && options.excluded == ExcludedDisplay.hide) return;
      final hide = options.excluded == ExcludedDisplay.hide;
      final heRuns = h == null ? null : _runs(h, ctx, hide);
      final trRuns = t == null ? null : _runs(t, ctx, hide);
      if (heRuns == null && trRuns == null) return;
      out.add(SegmentItem(
        key,
        leaf,
        heRuns,
        trRuns,
        primary.kind,
        ap,
        rubric?.labelEn,
        rubric?.labelHe,
        isExcluded,
      ));
    }

    if (aligned) {
      for (var i = 0; i < he.length; i++) {
        emit(i, he[i], tr[i]);
      }
    } else {
      for (var i = 0; i < he.length; i++) {
        emit(i, he[i], null);
      }
      for (var i = 0; i < tr.length; i++) {
        emit(i, null, tr[i]);
      }
    }
  }

  /// Resolves inline runs; with [hide], phrases not said today are dropped
  /// and a segment left with no text returns null.
  ResolvedSegment? _runs(Segment s, DayContext ctx, [bool hide = false]) {
    final runs = <ResolvedRun>[
      for (final r in s.runs)
        ResolvedRun(
          r.html,
          r.kind == RunKind.marker,
          r.rubric == null ? Applicability.always : _eval(r.rubric!.condition, ctx),
          r.rubric?.labelEn,
          r.rubric?.labelHe,
        ),
    ];
    if (!hide) return ResolvedSegment(s, runs);
    final kept = [for (final r in runs) if (r.applicability != Applicability.notToday) r];
    final hasText = kept.any((r) => !r.marker && r.html.replaceAll(RegExp(r'<[^>]*>'), '').trim().isNotEmpty);
    return hasText ? ResolvedSegment(s, kept) : null;
  }
}
