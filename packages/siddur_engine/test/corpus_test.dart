import 'dart:convert';
import 'dart:io';

import 'package:hebcal/hebcal.dart';
import 'package:siddur_engine/siddur_engine.dart';
import 'package:test/test.dart';

class _FileSource implements TextSource {
  @override
  Future<List<int>> readBytes(String file) => File('../../$file').readAsBytes();
}

List<int> _gunzip(List<int> b) => gzip.decode(b);

/// Plain Hebrew letters and spaces, for finding passages.
String _letters(String html) =>
    stripHtml(html).replaceAll(RegExp('[^א-ת ]'), '').replaceAll(RegExp(r'\s+'), ' ');

void main() {
  late SiddurResolver resolver;
  late SchemaNode root;
  late VersionSelection versions;
  late Corpus corpus;

  setUpAll(() async {
    initHebcal();
    final lib = SiddurLibrary(_FileSource(), _gunzip);
    final book = (await lib.manifest()).book('Siddur Ashkenaz')!;
    final rules = jsonDecode(File('../../assets/rules/rules.json').readAsStringSync()) as Map<String, dynamic>;
    final bookRules = rules['Siddur Ashkenaz'] as Map<String, dynamic>;
    corpus = Corpus.fromJson(
        jsonDecode(utf8.decode(gzip.decode(File('../../assets/corpus/ashkenaz.json.gz').readAsBytesSync())))
            as Map<String, Object?>);
    root = corpus.index!;
    resolver = SiddurResolver().withOverrides(bookRules).withCorpus(corpus);
    final defaults = (bookRules['defaultVersions'] as Map).cast<String, List>();
    // Amud's text first, as in the app, then the default Sefaria versions.
    Future<List<TextVersion>> load(String lang) async => [
          CorpusTextVersion(corpus, corpus.versionInfo(lang)!),
          ...await Future.wait([
            for (final t in defaults[lang]!)
              if (book.byLanguage(lang).any((v) => v.versionTitle == t))
                lib.version(book.byLanguage(lang).firstWhere((v) => v.versionTitle == t)),
          ]),
        ];
    versions = VersionSelection(await load('he'), await load('en'));
  });

  List<RenderItem> resolve(String section, HDate day, {bool il = false, Minhagim m = const Minhagim()}) =>
      resolver.resolve(root.find(section)!, versions, (s) => DayContext.forService(day, s, il: il, minhagim: m),
          options: const ResolveOptions(excluded: ExcludedDisplay.hide));

  /// The Hebrew said (in hide mode), as plain letters.
  String said(List<RenderItem> items) => [
        for (final i in items)
          if (i is SegmentItem && i.he != null && i.kind == SegmentKind.prayer && !i.excluded)
            for (final r in i.he!.runs)
              if (!r.marker && r.applicability != Applicability.notToday) _letters(r.html),
      ].join(' ');

  test('every Ashkenaz leaf is in the corpus', () {
    final missing = [
      for (final l in root.leaves)
        if (versions.pick(versions.hebrew, l.path).$1 != null && corpus.leaf(l.id) == null) l.id
    ];
    expect(missing, isEmpty);
  });

  test("Ya'aleh VeYavo only on Rosh Chodesh", () {
    final plain = said(resolve('Weekday/Shacharit/Amidah', HDate(3, Months.cheshvan, 5786)));
    final rc = said(resolve('Weekday/Shacharit/Amidah', HDate(1, Months.cheshvan, 5786)));
    expect(plain, isNot(contains('יעלה ויבא')));
    expect(rc, contains('יעלה ויבא'));
  });

  test('Mashiv HaRuach in winter, Morid HaTal not said by Ashkenaz in summer', () {
    final winter = said(resolve('Weekday/Shacharit/Amidah/Divine Might', HDate(3, Months.cheshvan, 5786)));
    final summer = said(resolve('Weekday/Shacharit/Amidah/Divine Might', HDate(3, Months.tamuz, 5786)));
    expect(winter, contains('משיב הרוח'));
    expect(summer, isNot(contains('משיב הרוח')));
    expect(summer, isNot(contains('מוריד הטל')));
    final israel = said(resolve('Weekday/Shacharit/Amidah/Divine Might', HDate(3, Months.tamuz, 5786), il: true));
    expect(israel, contains('מוריד הטל'));
  });

  test('Kaddish marks who says what', () {
    final items = resolve('Kaddish/Kaddish Shalem', HDate(3, Months.cheshvan, 5786)).whereType<SegmentItem>();
    final roles = {
      for (final i in items) ...[i.role, for (final r in i.he?.runs ?? const <ResolvedRun>[]) r.role]
    }.whereType<String>();
    expect(roles, containsAll(['chazzan', 'congregation']));
  });

  test('Kaddish: Le\'eila u\'le\'eila only in the Ten Days', () {
    final ten = said(resolve('Kaddish/Kaddish Shalem', HDate(5, Months.tishrei, 5786)));
    final plain = said(resolve('Kaddish/Kaddish Shalem', HDate(3, Months.cheshvan, 5786)));
    expect(ten, contains('לעילא ולעילא'));
    expect(plain, isNot(contains('לעילא ולעילא')));
  });

  test('a whole year of weekday and Shabbat services resolves with nothing undetermined', () {
    const sections = [
      'Weekday/Shacharit',
      'Weekday/Minchah',
      'Weekday/Maariv',
      'Shabbat/Shacharit',
      'Shabbat/Musaf LeShabbat',
      'Shabbat/Minchah',
    ];
    final unknown = <String, int>{};
    var day = HDate(1, Months.tishrei, 5786);
    final end = HDate(1, Months.tishrei, 5787).abs();
    while (day.abs() < end) {
      for (final s in sections) {
        if (s.startsWith('Shabbat') != (day.getDay() == 6)) continue;
        for (final i in resolver.resolve(root.find(s)!, versions, (svc) => DayContext.forService(day, svc, il: false))) {
          // "If: …" lines are personal circumstances, left to the reader.
          if (i is SegmentItem && i.applicability == Applicability.unknown && !(i.labelEn?.startsWith('If') ?? false)) {
            final k = '${i.node.id} ${i.labelEn}';
            unknown[k] = (unknown[k] ?? 0) + 1;
          }
        }
      }
      day = day.next();
    }
    expect(unknown, isEmpty, reason: unknown.keys.take(20).join('\n'));
  });

  test('the plain day used for "ordinary" conditions has no occasion', () {
    final c = DayContext(HDate(13, Months.cheshvan, 5786), il: false);
    expect(c.number('dow'), 2);
    expect(c.labels, isEmpty);
  });

  test('Tefillin hidden on Chol HaMoed unless that is the custom', () {
    final cholHamoed = HDate(18, Months.tishrei, 5787);
    bool tefillin(List<RenderItem> items) =>
        items.whereType<SegmentItem>().any((i) => i.node.id.endsWith('Preparatory Prayers/Tefillin'));
    expect(tefillin(resolve('Weekday/Shacharit', cholHamoed)), isFalse);
    expect(tefillin(resolve('Weekday/Shacharit', cholHamoed, m: const Minhagim(tefillinCholHamoed: true))), isTrue);
    final weekday = resolve('Weekday/Shacharit', HDate(13, Months.cheshvan, 5786));
    expect(tefillin(weekday), isTrue);
    // An ordinary day: no "Not on Tisha B'Av / Chol HaMoed" label.
    expect(weekday.whereType<HeadingItem>().where((h) => h.node.id.endsWith('/Tefillin')).single.applicability,
        Applicability.always);
  });

  test('labels say "not on" through negated groups', () {
    expect(labelsForCondition('!tishaBav && !(cholHamoed && noTefillinCholHamoed)')!.labelEn,
        "Not on Tisha B'Av / Not on Chol HaMoed");
  });

  test("Mourner's Kaddish is the mourner's", () {
    final node = root.leaves.firstWhere((l) => corpus.leaf(l.id)?.node == 'kaddish.mourners');
    final roles = {
      for (final i in resolve(node.id, HDate(13, Months.cheshvan, 5786)).whereType<SegmentItem>()) i.role
    }.whereType<String>();
    expect(roles, contains('mourner'));
    expect(roles, isNot(contains('chazzan')));
  });

  test('personal circumstances are shown, marked "If: …"', () {
    final items = resolve('Berachot/Birkat HaMazon', HDate(13, Months.cheshvan, 5786)).whereType<SegmentItem>();
    final ifs = {
      for (final i in items) ...[
        if (i.applicability == Applicability.unknown) i.labelEn,
        for (final r in i.he?.runs ?? const <ResolvedRun>[])
          if (r.applicability == Applicability.unknown) r.labelEn,
      ]
    };
    expect(ifs, contains('If: Ten or more ate together'));
    expect(ifs, contains('If not: At a festive meal (wedding, bris, pidyon haben)'));
  });

  test('Uva LeTziyon is said at Shabbat Mincha', () {
    final mincha = said(resolve('Shabbat/Minchah', HDate(16, Months.cheshvan, 5786)));
    expect(mincha, contains('ובא לציון'));
  });
}
