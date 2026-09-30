import 'dart:convert';
import 'dart:io';

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
          PlanBook(b, roots[b]!, SiddurResolver().withOverrides((rules[b] as Map<String, dynamic>?) ?? const {})),
      ],
      contexts: (svc) => DayContext.forService(day, svc, il: false),
      lookup: lookup,
    );
  }

  List<String> titles(PlanService s) => [for (final e in s.entries) e.node.en];
  PlanService svc(TodayPlan p, String key) => p.services.firstWhere((s) => s.key == key);

  test('Chol HaMoed Sukkot: Hallel, Lulav, Musaf and the day\'s Hoshana', () {
    // 19 Tishrei 5787: Wednesday, the fifth day of Sukkot.
    final p = plan(HDate(19, Months.tishrei, 5787));
    expect(p.services.map((s) => s.key), ['shacharit', 'mincha', 'maariv']);
    final s = svc(p, 'shacharit');
    expect(titles(s), [
      'Preparatory Prayers',
      'Pesukei Dezimra',
      'Blessings of the Shema',
      'Amidah',
      'Blessing on Lulav',
      'Hallel',
      'Torah Reading',
      'Mussaf',
      'Fifth Day of Sukkot',
      'Concluding Prayers',
      'Post Service',
    ]);
    expect(s.skipped.map((n) => n.en), contains('Post Amidah'), reason: 'no Tachanun on Chol HaMoed');
    expect(s.entries.firstWhere((e) => e.node.en == 'Fifth Day of Sukkot').extra, isTrue);
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
}
