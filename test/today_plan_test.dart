import 'dart:convert';
import 'dart:io';

import 'package:amud/core/providers.dart' show corpusFiles;
import 'package:amud/features/siddur/prayer_catalog.dart';
import 'package:amud/features/siddur/today_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hebcal/hebcal.dart';
import 'package:siddur_engine/siddur_engine.dart';

class _FileSource implements TextSource {
  @override
  Future<List<int>> readBytes(String file) => File(file).readAsBytes();
}

void main() {
  setUpAll(initHebcal);

  late SiddurLibrary lib;
  late Manifest manifest;
  late Map<String, dynamic> rules;
  final roots = <String, SchemaNode>{};
  final selections = <String, VersionSelection>{};
  final resolvers = <String, SiddurResolver>{};

  setUpAll(() async {
    lib = SiddurLibrary(_FileSource(), gzip.decode);
    manifest = await lib.manifest();
    rules = jsonDecode(File('assets/rules/rules.json').readAsStringSync()) as Map<String, dynamic>;
    for (final b in manifest.books) {
      roots[b.title] = await lib.index(b);
      // The app's default versions (rules.json), else every Hebrew version.
      final defaults = ((rules[b.title] as Map?)?['defaultVersions'] as Map?)?['he'] as List?;
      final he = [for (final v in b.byLanguage('he')) if (defaults == null || defaults.contains(v.versionTitle)) v];
      selections[b.title] = VersionSelection([for (final v in he) await lib.version(v)], const []);
      // As the app does: the tagged corpus, where the siddur has one.
      final f = corpusFiles[b.title];
      final corpus = f == null
          ? null
          : Corpus.fromJson(jsonDecode(utf8.decode(gzip.decode(File(f).readAsBytesSync()))) as Map<String, Object?>);
      resolvers[b.title] =
          SiddurResolver().withOverrides((rules[b.title] as Map<String, dynamic>?) ?? const {}).withCorpus(corpus);
    }
  });

  TodayPlan plan(HDate day, {String book = 'Siddur Ashkenaz'}) {
    PrayerRef? lookup(String key) {
      final item = catalogItem(key)!;
      for (final b in bookSearchOrder(manifest, book)) {
        final n = findByPatterns(roots[b]!, item.patterns);
        if (n != null && hasText(selections[b]!, n)) return PrayerRef(b, n);
      }
      return null;
    }

    return buildTodayPlan(
      books: [
        for (final b in bookSearchOrder(manifest, book))
          PlanBook(b, roots[b]!, resolvers[b]!),
      ],
      contexts: (svc) => DayContext.forService(day, svc, il: false),
      lookup: lookup,
    );
  }

  List<String> titles(PlanService s) => [for (final e in s.entries) e.node.en];
  PlanService svc(TodayPlan p, String key) => p.services.firstWhere((s) => s.key == key);

  test('Chol HaMoed Sukkot: Lulav and Hallel, then Musaf after Uva LeTziyon and the day\'s Hoshana', () {
    // 19 Tishrei 5787: Wednesday, the fifth day of Sukkot.
    final p = plan(HDate(19, Months.tishrei, 5787));
    // The bedtime Shema printed inside Ashkenaz Maariv is its own service.
    expect(p.services.map((s) => s.key), ['shacharit', 'mincha', 'maariv', 'night']);
    final s = svc(p, 'shacharit');
    expect(titles(s), [
      'Preparatory Prayers',
      'Pesukei Dezimra',
      'Blessings of the Shema',
      'Amidah',
      'Blessing on Lulav',
      'Hallel',
      'Torah Reading',
      // Concluding Prayers, opened: Musaf and Hoshanot come after Uva
      // LeTziyon (the service graph).
      'Ashrei',
      'Uva Letzion',
      'Mussaf',
      'Fifth Day of Sukkot',
      'Kaddish Shalem',
      'Alenu',
      "Mourner's Kaddish",
      'Song of the Day',
      'LeDavid',
    ]);
    expect(s.skipped.map((n) => n.en), containsAll(['Post Amidah', "Lamenatze'ach", 'Post Service']),
        reason: 'no Tachanun or Lamenatzeach on Chol HaMoed');
    final hoshana = s.entries.firstWhere((e) => e.node.en == 'Fifth Day of Sukkot');
    expect(hoshana.added && !hoshana.extra, isTrue, reason: 'inserted by the service graph, read with the service');
    expect(svc(p, 'maariv').tonight, isTrue);
  });

  test('an ordinary Wednesday has no Torah reading and says Tachanun', () {
    final s = svc(plan(HDate(3, Months.cheshvan, 5787)), 'shacharit');
    expect(s.skipped.map((n) => n.en), contains('Torah Reading'));
    expect(titles(s), contains('Post Amidah'));
    expect(s.entries.where((e) => e.added), isEmpty);
  });

  test('Friday: candles and Kabbalat Shabbat, then Shabbat Maariv and Kiddush', () {
    // 5 Cheshvan 5787 is a Friday.
    final d = HDate(5, Months.cheshvan, 5787);
    expect(d.getDay(), 5);
    final p = plan(d);
    expect(p.services.map((s) => s.key), ['shacharit', 'mincha', 'shabbatEve', 'maariv', 'night']);
    expect(titles(svc(p, 'shabbatEve')), contains('Kabbalat Shabbat'));
    final maariv = svc(p, 'maariv');
    expect(maariv.whole!.id, 'Shabbat/Maariv');
    expect(titles(maariv).last, 'Kiddush');
  });

  test('Shabbat: Shabbat services, Musaf, and weekday Maariv with Havdalah', () {
    final d = HDate(6, Months.cheshvan, 5787);
    expect(d.getDay(), 6);
    final p = plan(d);
    expect(svc(p, 'shacharit').whole!.id, 'Shabbat/Shacharit');
    expect(svc(p, 'musaf').whole!.id, 'Shabbat/Musaf LeShabbat');
    final maariv = svc(p, 'maariv');
    expect(maariv.whole!.id, 'Weekday/Maariv');
    expect(titles(maariv), contains("Additions for Motza'ei Shabbat"));
    expect(titles(maariv), contains('Havdalah'));
  });

  test('Hoshana Raba opens its own Hoshanot', () {
    final s = svc(plan(HDate(21, Months.tishrei, 5787)), 'shacharit');
    expect(titles(s), contains("Hosha'ana Rabba"));
    final koren = svc(plan(HDate(21, Months.tishrei, 5787), book: 'The Koren Shalem Siddur; Ashkenaz'), 'shacharit');
    expect(titles(koren), contains('Hoshanot for Hoshana Raba'));
  });

  test('Rosh Chodesh in every siddur: Hallel and Musaf', () {
    for (final b in ['Siddur Ashkenaz', 'Siddur Sefard', 'Siddur Edot HaMizrach', 'Weekday Siddur Chabad', 'The Koren Shalem Siddur; Ashkenaz']) {
      // 1 Cheshvan 5787 is a Monday.
      final s = svc(plan(HDate(1, Months.cheshvan, 5787), book: b), 'shacharit');
      expect(titles(s).where((t) => RegExp('hallel', caseSensitive: false).hasMatch(t)), isNotEmpty, reason: b);
      expect(s.entries.where((e) => RegExp(r'mus+af|rosh c?hodesh', caseSensitive: false).hasMatch(e.node.id)), isNotEmpty, reason: b);
    }
  });

  test('a fast day: Selichot after the Amidah; Torah reading at Mincha where the siddur has it', () {
    final d = HDate(10, Months.tevet, 5786);
    final s = svc(plan(d), 'shacharit');
    final t = titles(s);
    expect(t.indexOf('Ten of Tevet'), greaterThan(t.indexOf('Amidah')));
    expect(t.indexOf('Ten of Tevet'), lessThan(t.indexOf('Post Amidah')));
    final edot = svc(plan(d, book: 'Siddur Edot HaMizrach'), 'mincha');
    expect(titles(edot), ['Offerings', 'Torah Reading for Fast Days', 'Amida', 'Vidui', 'Alenu']);
  });

  test('Motzaei Shabbat: weekday Maariv, then Kiddush Levana and Havdalah', () {
    // 9 Kislev 5786 is a Shabbat in the Kiddush Levana window.
    final d = HDate(9, Months.kislev, 5786);
    expect(d.getDay(), 6);
    final edot = svc(plan(d, book: 'Siddur Edot HaMizrach'), 'maariv');
    expect(edot.whole!.id, 'Weekday Arvit');
    final t = titles(edot);
    expect(t.indexOf('Blessing of the Moon'), lessThan(t.indexOf('Havdala')));
  });

  test('Chanukah: the candles once, after the Maariv Amidah', () {
    final m = svc(plan(HDate(27, Months.kislev, 5786)), 'maariv');
    final candles = [for (final e in m.entries) if (RegExp('chanukah', caseSensitive: false).hasMatch(e.node.id)) e];
    expect(candles, hasLength(1));
    expect(titles(m).indexOf(candles.single.node.en), titles(m).indexOf('Amidah') + 1);
  });

  test('Koren: weekday Shacharit ends at the Daily Psalm; Hoshana Raba has its own Hoshanot', () {
    final s = svc(plan(HDate(13, Months.cheshvan, 5786), book: 'The Koren Shalem Siddur; Ashkenaz'), 'shacharit');
    expect(titles(s).last, 'The Daily Psalm');
    final hr = svc(plan(HDate(21, Months.tishrei, 5787), book: 'The Koren Shalem Siddur; Ashkenaz'), 'shacharit');
    expect(titles(hr), isNot(contains('Hoshanot')));
  });
}
