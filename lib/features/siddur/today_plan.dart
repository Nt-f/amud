import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:siddur_engine/siddur_engine.dart';

import '../../core/providers.dart';
import 'prayer_catalog.dart';
import 'siddur_providers.dart';

/// One section of the day's davening, in order.
class PlanEntry {
  final PrayerRef ref;

  /// Why it's there today when it isn't part of the service every day
  /// (Hallel, Musaf, Hoshanot…).
  final String? addedEn;
  final String? addedHe;

  /// Not among the sections of the service as the siddur prints it, so
  /// reading the service straight through doesn't include it (it comes from
  /// elsewhere in the book or from another siddur).
  final bool extra;
  const PlanEntry(this.ref, {this.addedEn, this.addedHe, this.extra = false});

  SchemaNode get node => ref.node;
  String get book => ref.book;
  bool get added => addedEn != null || addedHe != null;
}

/// A service (or a group such as candle lighting and Kabbalat Shabbat) of
/// the day, in order.
class PlanService {
  /// shacharit, musaf, mincha, shabbatEve, maariv or night.
  final String key;
  final String en;
  final String he;

  /// Said the evening after the day (Maariv belongs to the next Hebrew day).
  final bool tonight;
  final List<PlanEntry> entries;

  /// Sections of the service not said today (Tachanun, Avinu Malkeinu…).
  final List<SchemaNode> skipped;

  /// The whole service, to read straight through.
  final PrayerRef? whole;
  const PlanService(this.key, this.en, this.he, this.entries, {this.tonight = false, this.skipped = const [], this.whole});
}

/// A siddur the plan can draw services from.
class PlanBook {
  final String title;
  final SchemaNode root;
  final SiddurResolver resolver;
  const PlanBook(this.title, this.root, this.resolver);
}

class TodayPlan {
  final String book;
  final List<PlanService> services;

  /// Rosh Hashana and Yom Kippur: the bundled siddurim have no machzor.
  final bool needsMachzor;
  const TodayPlan(this.book, this.services, {this.needsMachzor = false});

  List<PlanEntry> get entries => [for (final s in services) ...s.entries];

  /// The service an entry belongs to.
  PlanService? serviceOf(PlanEntry e) {
    for (final s in services) {
      if (s.entries.contains(e)) return s;
    }
    return null;
  }
}

/// Catalog items the plan may add; looked up before building it.
const planItemKeys = [
  'hallel', 'lulav', 'hoshanot', 'hoshanaRaba', 'musafRoshChodesh', 'musafFestival', 'amidahYomTov', 'kabbalatShabbat', //
  'kiddushShabbat', 'kiddushYomTov', 'candles', 'omer', 'kiddushLevana', 'chanukah', 'havdalah', 'bedtime',
];

final _amidah = RegExp(r'amid|shemoneh', caseSensitive: false);
final _hallel = RegExp(r'hallel', caseSensitive: false);
final _musaf = RegExp(r'mus+af', caseSensitive: false);
final _torah = RegExp(r'torah reading|reading of the torah', caseSensitive: false);

/// Sections that follow a service in a book without being part of it.
final _notService = RegExp(
    r'meal|kiddush|zemir|song|eiruv|candle|havdal|shelishit|se.?uda|levana|new moon|omer|sleep|retiring|bedtime|'
    r'additional prayers|additions|readings after|personal supplications|mishna|guide|preface',
    caseSensitive: false);

/// Builds the order of the day's davening from the sections of the first
/// of [books] (the default siddur; a service it lacks, such as Shabbat in
/// a weekday siddur, comes from the next that has it), their insert rules
/// and the app's own additions (Lulav, Hoshanot…). [contexts] describes
/// the civil day (Maariv is the evening after it); [lookup] finds
/// catalogued prayers, possibly in other books.
TodayPlan buildTodayPlan({
  required List<PlanBook> books,
  required DayContext Function(Service) contexts,
  required PrayerRef? Function(String key) lookup,
}) {
  final book = books.first.title;
  final day = contexts(Service.shacharit);
  final night = contexts(Service.maariv);
  final shabbatOrYt = day['shabbat'] || day['yomTov'];
  final services = <PlanService>[];

  final resolver = books.first.resolver;

  bool otherService(SchemaNode n, Service svc) {
    final s = SiddurResolver.serviceFor(n, Service.other);
    return s != Service.other && s != svc;
  }

  // The sections of a service: its parts, or, where the book prints a
  // service as a run of top-level sections (Koren's Shabbat), the leaf and
  // the sections after it up to the next service.
  List<SchemaNode> sectionsOf(SchemaNode node, Service svc) {
    final out = <SchemaNode>[];
    if (!node.isLeaf) {
      for (final c in node.children) {
        if (otherService(c, svc)) break;
        out.add(c);
      }
    } else {
      out.add(node);
    }
    final siblings = node.parent?.children ?? const <SchemaNode>[];
    for (var i = siblings.indexOf(node) + 1; i < siblings.length && i > 0; i++) {
      final sib = siblings[i];
      final torah = _torah.hasMatch(sib.en);
      if (!node.isLeaf && !torah) break;
      if (otherService(sib, svc) || (!torah && _notService.hasMatch(sib.en))) break;
      out.add(sib);
    }
    return out;
  }

  PlanService? service(String key, String en, String he, Service svc, {bool tonight = false}) {
    PlanBook? from;
    SchemaNode? node;
    for (final b in books) {
      final id = findSectionOn(b.root, key, contexts);
      node = id == null ? null : b.root.find(id);
      if (node != null) {
        from = b;
        break;
      }
    }
    if (from == null || node == null) return null;
    final (book, root, resolver) = (from.title, from.root, from.resolver);
    bool said(SchemaNode n, Service svc) => sectionStatus(resolver, n, contexts, svc).ap != Applicability.notToday;
    final entries = <PlanEntry>[];
    final skipped = <SchemaNode>[];
    void inserts(SchemaNode section, bool before) {
      for (final r in resolver.insertRules) {
        if (r.before != before || !(r.anchor == section.id || r.anchor.startsWith('${section.id}/'))) continue;
        final target = root.find(r.insert);
        final anchor = root.find(r.anchor) ?? section;
        if (target == null || !r.condition.eval(contexts(SiddurResolver.serviceFor(anchor, svc)).env)) continue;
        entries.add(PlanEntry(PrayerRef(book, target), addedEn: r.labelEn, addedHe: r.labelHe));
      }
    }

    final amidahYomTov = contexts(svc)['yomTov'] ? lookup('amidahYomTov') : null;
    for (final section in sectionsOf(node, svc)) {
      inserts(section, true);
      if (!said(section, svc)) {
        skipped.add(section);
      } else if (amidahYomTov != null && _amidah.hasMatch(section.en)) {
        // The festival Amidah in place of the Shabbat one.
        entries.add(PlanEntry(amidahYomTov, addedEn: 'Yom Tov', addedHe: 'יום טוב', extra: true));
      } else {
        entries.add(PlanEntry(PrayerRef(book, section)));
      }
      inserts(section, false);
    }
    return PlanService(key, en, he, entries, tonight: tonight, skipped: skipped, whole: PrayerRef(book, node));
  }

  /// A weekday service as the service graph lays it out for the default
  /// siddur (corpus/graph.json): its own sections in order, with what the
  /// day adds placed among them (Hallel after the Amidah, Musaf after Uva
  /// LeTziyon…). A section holding such a placement is opened into its
  /// parts, so the plan lists them in the order they're said. Null when the
  /// siddur has no corpus for it.
  PlanService? graphService(String name, String key, String en, String he, Service svc, {bool tonight = false}) {
    final from = books.first;
    final gs = from.resolver.corpus?.services[name];
    if (gs == null || gs.sections.isEmpty) return null;
    final (book, root, resolver) = (from.title, from.root, from.resolver);
    final env = contexts(svc).env;
    final applying = [for (final r in gs.inserts) if (r.condition.eval(env)) r];
    bool said(SchemaNode n) => sectionStatus(resolver, n, contexts, svc).ap != Applicability.notToday;
    // Of a section with a part for each day (the Hoshanot), today's part:
    // only when every other part is for another day.
    SchemaNode todays(SchemaNode n) {
      final status = {for (final c in n.children) c: sectionStatus(resolver, c, contexts, svc).ap};
      final today = [for (final e in status.entries) if (e.value == Applicability.today) e.key];
      final others = status.values.where((a) => a != Applicability.today);
      return today.length == 1 && others.every((a) => a == Applicability.notToday) ? today.single : n;
    }

    final entries = <PlanEntry>[];
    final skipped = <SchemaNode>[];
    void place(SchemaNode n, bool before) {
      for (final r in applying) {
        if (r.before != before || r.anchor != n.id) continue;
        final target = root.find(r.insert);
        if (target != null) entries.add(PlanEntry(PrayerRef(book, todays(target)), addedEn: r.labelEn, addedHe: r.labelHe));
      }
    }

    void visit(SchemaNode n) {
      place(n, true);
      if (!said(n)) {
        skipped.add(n);
      } else if (!n.isLeaf && applying.any((r) => r.anchor.startsWith('${n.id}/'))) {
        n.children.forEach(visit);
      } else {
        entries.add(PlanEntry(PrayerRef(book, n)));
      }
      place(n, false);
    }

    final nodes = [for (final p in gs.sections) ?root.find(p)];
    nodes.forEach(visit);
    final whole = gs.whole == null ? null : root.find(gs.whole!);
    return PlanService(key, en, he, entries,
        tonight: tonight, skipped: skipped, whole: whole == null ? null : PrayerRef(book, whole));
  }

  bool has(PlanService s, bool Function(PlanEntry e) test) => s.entries.any(test);
  // Already there: the same section, one containing it, or a part of it
  // (today's Hoshana of the Hoshanot).
  bool contains(PlanService s, PrayerRef r) => s.entries.any((e) =>
      e.book == r.book && (e.node == r.node || r.id.startsWith('${e.node.id}/') || e.node.id.startsWith('${r.id}/')));

  // The service's own copy of a catalogued prayer (Shabbat Maariv's
  // Sefirat HaOmer, not the weekday one the catalog found).
  bool hasItem(PlanService s, String key) {
    final patterns = [for (final p in catalogItem(key)?.patterns ?? const <String>[]) RegExp(p, caseSensitive: false)];
    return s.entries.any((e) => patterns.any((p) => p.hasMatch(e.node.id)));
  }
  int lastIndex(PlanService s, bool Function(PlanEntry e) test) => s.entries.lastIndexWhere(test);

  /// Adds catalog item [key] after the last entry matching [after] (or at
  /// the end), unless the service already has it.
  PrayerRef? add(PlanService? s, String key, String en, String he, {bool Function(PlanEntry e)? after, bool before = false}) {
    if (s == null) return null;
    final r = lookup(key);
    if (r == null || contains(s, r) || hasItem(s, key)) return null;
    final at = after == null ? -1 : (before ? s.entries.indexWhere(after) : lastIndex(s, after));
    final e = PlanEntry(r, addedEn: en, addedHe: he, extra: true);
    if (at < 0) {
      s.entries.add(e);
    } else {
      s.entries.insert(before ? at : at + 1, e);
    }
    return r;
  }

  final ashkenaz = nusachOf(book) == Nusach.ashkenaz;

  // Weekday services come from the service graph where the siddur has a
  // corpus; Shabbat, Yom Tov and other siddurim from their sections below.
  final weekdayDay = !day['shabbat'] && !day['yomTov'];
  final weekdayNight = !night['shabbat'] && !night['yomTov'];

  // Morning.
  final shacharit = (weekdayDay ? graphService('shacharit.weekday', 'shacharit', 'Shacharit', 'שחרית', Service.shacharit) : null) ??
      service('shacharit', 'Shacharit', 'שחרית', Service.shacharit);
  if (shacharit != null) {
    services.add(shacharit);
    if (day['hallel']) add(shacharit, 'hallel', 'Hallel', 'הלל', after: (e) => _amidah.hasMatch(e.node.en));
    bool isHallel(PlanEntry e) => _hallel.hasMatch(e.node.en);
    if (day['sukkot'] && !day['shabbat']) {
      add(shacharit, 'lulav', 'Lulav', 'לולב', after: has(shacharit, isHallel) ? isHallel : (e) => _amidah.hasMatch(e.node.en), before: has(shacharit, isHallel));
    }
    if (!shabbatOrYt && (day['roshChodesh'] || day['cholHamoed']) && !has(shacharit, (e) => _musaf.hasMatch(e.node.en))) {
      final key = day['cholHamoed'] ? 'musafFestival' : 'musafRoshChodesh';
      add(shacharit, key, 'Musaf', 'מוסף', after: (e) => _torah.hasMatch(e.node.en) || isHallel(e));
    }
  }

  // Musaf of Shabbat and Yom Tov.
  PlanService? musaf;
  if (shabbatOrYt) {
    final festival = day['yomTov'] || day['cholHamoed'] ? lookup('musafFestival') : null;
    musaf = festival != null
        ? PlanService('musaf', 'Musaf', 'מוסף', [PlanEntry(festival, extra: festival.book != book)], whole: festival)
        : service('musaf', 'Musaf', 'מוסף', Service.musaf);
    if (musaf != null) services.add(musaf);
  }

  // Hoshanot: after Musaf in Nusach Ashkenaz, after Hallel otherwise.
  if (day['sukkot']) {
    var h = lookup('hoshanot');
    final hr = day['hoshanaRaba'] ? lookup('hoshanaRaba') : null;
    if (h != null && hr != null && !(hr.book == h.book && (hr.node == h.node || hr.id.startsWith('${h.id}/')))) h = hr;
    if (h != null) {
      // Open today's Hoshana directly when the day's is one part of it.
      final today = [for (final c in h.node.children) if (sectionStatus(resolver, c, contexts).ap == Applicability.today) c];
      final target = today.length == 1 ? PrayerRef(h.book, today.single) : h;
      final into = ashkenaz ? (musaf ?? shacharit) : shacharit;
      if (into != null && !contains(into, target)) {
        final e = PlanEntry(target, addedEn: 'Hoshanot', addedHe: 'הושענות', extra: true);
        final at = ashkenaz && musaf == null
            ? lastIndex(into, (e) => _musaf.hasMatch(e.node.en))
            : (ashkenaz ? into.entries.length - 1 : lastIndex(into, (e) => _hallel.hasMatch(e.node.en)));
        into.entries.insert(at < 0 ? into.entries.length : at + 1, e);
      }
    }
  }

  // Afternoon.
  final mincha = (weekdayDay ? graphService('mincha.weekday', 'mincha', 'Mincha', 'מנחה', Service.mincha) : null) ??
      service('mincha', 'Mincha', 'מנחה', Service.mincha);
  if (mincha != null) services.add(mincha);

  // Shabbat and Yom Tov evening: candles, Kabbalat Shabbat.
  final shabbatEve = night['shabbat'] && !day['shabbat'];
  if (shabbatEve || night['yomTov']) {
    final eve = PlanService('shabbatEve', shabbatEve ? 'Shabbat evening' : 'Yom Tov evening', shabbatEve ? 'ערב שבת' : 'ערב יום טוב', []);
    add(eve, 'candles', 'Candle lighting', 'הדלקת נרות');
    if (shabbatEve) add(eve, 'kabbalatShabbat', 'Kabbalat Shabbat', 'קבלת שבת');
    if (eve.entries.isNotEmpty) services.add(eve);
  }

  // Evening.
  final maariv =
      (weekdayNight ? graphService('maariv.weekday', 'maariv', 'Maariv', 'ערבית', Service.maariv, tonight: true) : null) ??
          service('maariv', 'Maariv', 'ערבית', Service.maariv, tonight: true);
  if (maariv != null) {
    services.add(maariv);
    if (night['chanukah']) add(maariv, 'chanukah', 'Chanukah', 'חנוכה', after: (e) => _amidah.hasMatch(e.node.en));
    if (night['omer']) add(maariv, 'omer', 'Sefirat HaOmer', 'ספירת העומר');
    if (night['kiddushLevana']) add(maariv, 'kiddushLevana', 'Kiddush Levana', 'קידוש לבנה');
    if (night['motzaeiShabbat'] || night['motzaeiYomTov']) add(maariv, 'havdalah', 'Havdalah', 'הבדלה');
    if (night['shabbat'] && !day['shabbat']) {
      add(maariv, 'kiddushShabbat', 'Kiddush', 'קידוש');
    } else if (night['yomTov']) {
      add(maariv, 'kiddushYomTov', 'Kiddush', 'קידוש');
    }
    final bedtime = lookup('bedtime');
    if (bedtime != null && !contains(maariv, bedtime) && !hasItem(maariv, 'bedtime')) {
      services.add(PlanService('night', 'Before sleep', 'לפני השינה', [PlanEntry(bedtime, extra: true)], tonight: true, whole: bedtime));
    }
  }

  return TodayPlan(book, services, needsMachzor: day['roshHashana'] || day['yomKippur']);
}

/// The day's davening in the default siddur, for the reader's civil date.
final todayPlanProvider = FutureProvider.family<TodayPlan?, int>((ref, dateAbs) async {
  final m = await ref.watch(manifestProvider.future);
  final first = await ref.watch(defaultBookProvider.future);
  final books = [
    for (final b in bookSearchOrder(m, first))
      PlanBook(b, await ref.watch(bookIndexProvider(b).future), await ref.watch(resolverProvider(b).future)),
  ];
  final refs = <String, PrayerRef?>{
    for (final k in planItemKeys) k: await ref.watch(prayerRefProvider(k).future),
  };
  return buildTodayPlan(
    books: books,
    contexts: (svc) => ref.watch(dayContextProvider((dateAbs, svc))),
    lookup: (k) => refs[k],
  );
});

/// Where [node] of [book] falls in [plan]: the entries it covers (the
/// node itself, or the sections inside it), or the entry it's part of.
({List<PlanEntry> covered, PlanEntry? within}) locateInPlan(TodayPlan plan, String book, SchemaNode node) {
  final covered = [
    for (final e in plan.entries)
      if (e.book == book && (e.node == node || e.node.id.startsWith('${node.id}/'))) e,
  ];
  PlanEntry? within;
  if (covered.isEmpty) {
    for (final e in plan.entries) {
      if (e.book == book && node.id.startsWith('${e.node.id}/')) within = e;
    }
  }
  return (covered: covered, within: within);
}
