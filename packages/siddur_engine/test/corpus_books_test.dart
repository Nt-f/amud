import 'dart:convert';
import 'dart:io';

import 'package:hebcal/hebcal.dart';
import 'package:siddur_engine/siddur_engine.dart';
import 'package:test/test.dart';

class _FileSource implements TextSource {
  @override
  Future<List<int>> readBytes(String file) => File('../../$file').readAsBytes();
}

/// Every one of Amud's own siddurim (assets/corpus): its table of contents
/// and text are the corpus's, and it resolves a whole year without anything
/// left undetermined.
const books = {
  'Siddur Ashkenaz': 'ashkenaz',
  'Weekday Siddur Chabad': 'chabad',
  'Siddur Sefard': 'sefard',
  'Siddur Edot HaMizrach': 'edot_hamizrach',
  'The Koren Shalem Siddur; Ashkenaz': 'koren',
};

void main() {
  setUpAll(initHebcal);
  final rules = jsonDecode(File('../../assets/rules/rules.json').readAsStringSync()) as Map<String, dynamic>;

  for (final MapEntry(key: title, value: slug) in books.entries) {
    group(slug, () {
      late SchemaNode root;
      late VersionSelection versions;
      late Corpus corpus;
      late SiddurResolver resolver;

      setUpAll(() async {
        final lib = SiddurLibrary(_FileSource(), gzip.decode);
        final book = (await lib.manifest()).book(title)!;
        corpus = Corpus.fromJson(
            jsonDecode(utf8.decode(gzip.decode(File('../../assets/corpus/$slug.json.gz').readAsBytesSync())))
                as Map<String, Object?>);
        root = corpus.index!;
        final bookRules = (rules[title] as Map<String, dynamic>?) ?? const {};
        resolver = SiddurResolver().withOverrides(bookRules).withCorpus(corpus);
        // The app's default order: Amud's text, rules.json's
        // defaultVersions, then the manifest's (see versionOrderProvider).
        final defaults = ((bookRules['defaultVersions'] as Map?)?.cast<String, List>()) ?? const {};
        Future<List<TextVersion>> load(String lang) async {
          final titles = <String>{
            for (final t in defaults[lang] ?? const []) t as String,
            for (final v in book.byLanguage(lang))
              if (lang == 'he' || v.languageTag == null) v.versionTitle,
          };
          return [
            CorpusTextVersion(corpus, corpus.versionInfo(lang)!),
            ...await Future.wait([
              for (final t in titles)
                if (book.byLanguage(lang).any((v) => v.versionTitle == t))
                  lib.version(book.byLanguage(lang).firstWhere((v) => v.versionTitle == t)),
            ]),
          ];
        }

        versions = VersionSelection(await load('he'), await load('en'));
      });

      test("every section is the corpus's, in Amud's text", () {
        final missing = <String>[];
        final otherVersion = <String>[];
        for (final l in root.leaves) {
          final c = corpus.leaf(l.id);
          if (c == null) {
            missing.add(l.id);
            continue;
          }
          final (info, _) = versions.pick(versions.hebrew, l.path);
          if (c.he != null && !(info?.isCorpus ?? false)) otherVersion.add('${l.id}: ${info?.versionTitle}');
        }
        expect(missing, isEmpty, reason: missing.take(10).join('\n'));
        expect(otherVersion, isEmpty, reason: otherVersion.take(10).join('\n'));
        expect(root.leaves.length, corpus.leaves.length);
      });

      List<SegmentItem> said(String section, HDate day, {Minhagim m = const Minhagim()}) => [
            for (final i in resolver.resolve(root.find(section)!, versions,
                (s) => DayContext.forService(day, s, il: false, minhagim: m),
                options: const ResolveOptions(excluded: ExcludedDisplay.hide)))
              if (i is SegmentItem && !i.excluded) i
          ];
      final plain = HDate(13, Months.cheshvan, 5786); // a Tuesday
      final roshChodesh = HDate(1, Months.kislev, 5786);

      // Leaf conditions found wrong in review (their comments in corpus/siddur).
      if (slug == 'edot_hamizrach') {
        test('the weekday Amidah is said on an ordinary day', () {
          expect(said('Weekday Shacharit/Amida', plain).where((i) => i.kind == SegmentKind.prayer), isNotEmpty);
          expect(said('Weekday Shacharit', plain).any((i) => i.node.id == 'Weekday Shacharit/Amida'), isTrue);
        });
      }
      if (slug == 'sefard') {
        test('Maariv Amidah: each blessing\'s closing is said once, the Ten Days\' in its place', () {
          String said_(HDate d) => [
                for (final i in said('Weekday Maariv/Amidah', d))
                  if (i.kind == SegmentKind.prayer) ...[for (final r in i.he?.runs ?? const <ResolvedRun>[]) if (!r.marker) r.html],
              ].join(' ').replaceAll(RegExp(r'[^א-ת ]'), '');
          int count(String text, String word) => word.allMatches(text).length;
          final plainDay = said_(plain);
          final tenDays = said_(HDate(5, Months.tishrei, 5786));
          expect(count(plainDay, 'האל הקדוש'), 1);
          expect(count(plainDay, 'המלך הקדוש'), 0);
          expect(count(plainDay, 'בספר חיים'), 0);
          expect(count(tenDays, 'האל הקדוש'), 0);
          expect(count(tenDays, 'המלך הקדוש'), 1);
          expect(count(tenDays, 'בספר חיים'), 1);
        });
        test('the prayer for a sick person is offered, not said every day', () {
          final sick = said('Weekday Shacharit/Amidah', plain).where((i) =>
              i.he != null && i.he!.runs.any((r) => r.html.replaceAll(RegExp(r'[^א-ת ]'), '').contains('שתשלח מהרה רפואה')));
          expect(sick, isNotEmpty);
          expect(sick.every((i) => i.applicability != Applicability.always && i.labelEn != null), isTrue);
        });
        test('Tachanun on a Tachanun day, not on Rosh Chodesh', () {
          bool tachanun(HDate d) => said('Weekday Shacharit', d).any((i) => i.node.id == 'Weekday Shacharit/Tachanun');
          expect(tachanun(plain), isTrue);
          expect(tachanun(roshChodesh), isFalse);
        });
      }
      if (slug == 'koren') {
        test('the Shema is said without a minyan', () {
          final alone = said('Weekdays', plain, m: const Minhagim(withMinyan: false));
          expect(alone.any((i) => i.node.id == 'Weekdays/Blessings of the Shema'), isTrue);
        });
      }

      /// The sections inserted into [section] on [day], in order, as
      /// (anchor-relative) indexes of the first item from each path.
      int firstAt(List<RenderItem> items, String path) => items.indexWhere((i) =>
          (i is SegmentItem && (i.node.id == path || i.node.id.startsWith('$path/'))) ||
          (i is InsertedSectionItem && i.node.id == path));
      List<RenderItem> service(String section, HDate day) => resolver.resolve(
          root.find(section)!, versions, (s) => DayContext.forService(day, s, il: false),
          options: const ResolveOptions(excluded: ExcludedDisplay.hide));
      final cholHamoedSukkot = HDate(18, Months.tishrei, 5786);
      final fast = HDate(10, Months.tevet, 5786);

      if (slug == 'sefard') {
        test('BaHaB: each day inserts its own Selichot (first Monday, Thursday, second Monday)', () {
          List<String> selichot(HDate d) => [
                for (final i in service('Weekday Shacharit', d))
                  if (i is InsertedSectionItem && i.node.id.startsWith('Fast Days/Selichot for ')) i.node.id.split('for ').last,
              ];
          expect(selichot(HDate(8, Months.cheshvan, 5787)), ['BaHaB', 'First Monday']);
          expect(selichot(HDate(11, Months.cheshvan, 5787)), ['BaHaB', 'Thursday']);
          expect(selichot(HDate(15, Months.cheshvan, 5787)), ['BaHaB', 'Concluding Monday']);
          expect(selichot(HDate(19, Months.tevet, 5787)), isEmpty);
        });
        test('Rosh Chodesh: the end of Shacharit after Musaf is said once', () {
          final aleinu = service('Weekday Shacharit', HDate(1, Months.cheshvan, 5787))
              .where((i) => i is SegmentItem && i.node.id != '' && (i.he?.segment.html.replaceAll(RegExp(r'[^א-ת]'), '').startsWith('עלינולשבח') ?? false));
          expect(aleinu, hasLength(1));
        });
      }
      if (slug == 'ashkenaz') {
        test('Vidui: in Israel every Tachanun day, elsewhere Monday and Thursday; God of Israel only Monday and Thursday', () {
          Set<String> leaves(HDate d, {bool il = false}) => {
                for (final i in resolver.resolve(root.find('Weekday/Shacharit/Post Amidah')!, versions,
                    (s) => DayContext.forService(d, s, il: il),
                    options: const ResolveOptions(excluded: ExcludedDisplay.hide)))
                  if (i is SegmentItem) i.node.id.split('/').last,
              };
          final tuesday = HDate(19, Months.tevet, 5787), monday = HDate(18, Months.tevet, 5787);
          expect(leaves(tuesday), isNot(contains('Vidui and 13 Middot')));
          expect(leaves(tuesday), isNot(contains('God of Israel')));
          expect(leaves(tuesday), contains('Shomer Yisrael'));
          expect(leaves(monday), containsAll(['Vidui and 13 Middot', 'God of Israel']));
          expect(leaves(tuesday, il: true), contains('Vidui and 13 Middot'));
          expect(leaves(tuesday, il: true), isNot(contains('God of Israel')));
          expect(leaves(roshChodesh), isNot(contains('Nefilat Apayim')));
        });
        test('touching the tefillin is marked at the words: the shel yad at "al yadecha", the shel rosh at "bein einecha"', () {
          final runs = [
            for (final i in said('Weekday/Shacharit/Preparatory Prayers/Tefillin', HDate(19, Months.tevet, 5787)))
              if (i.he != null) ...i.he!.runs,
          ];
          String bare(ResolvedRun r) => r.html.replaceAll(RegExp(r'[^א-ת ]'), '').trim();
          final yad = runs.where((r) => r.gestures.contains('touch_tefillin_yad')).map(bare).toList();
          final rosh = runs.where((r) => r.gestures.contains('touch_tefillin_rosh')).map(bare).toList();
          expect(yad, hasLength(2));
          expect(yad.every((w) => w.startsWith('על')), isTrue, reason: '$yad');
          expect(rosh, ['בין עיניך', 'בין עיניך']);
        });
        test('Hosha\'anot: the Ashkenaz order for every weekday Sukkot can start on (MB 663:6)', () {
          const open = {
            'lemaan': 'למעןאמתך', 'even': 'אבןשתיה', 'eerach': 'אערךשועי', 'om': 'אםאניחומה',
            'el': 'אללמושעות', 'adon': 'אדוןהמושיע', 'netzura': 'אםנצורה',
          };
          // Days 1–6 of Sukkot, by the weekday of 15 Tishrei (Levushei Serad's table).
          const table = {
            1: ['lemaan', 'even', 'eerach', 'om', 'el', 'netzura'],
            2: ['lemaan', 'even', 'eerach', 'el', 'netzura', 'adon'],
            4: ['lemaan', 'even', 'netzura', 'eerach', 'el', 'adon'],
            6: ['netzura', 'lemaan', 'eerach', 'even', 'el', 'adon'],
          };
          final seen = <int>{};
          for (var year = 5780; seen.length < 4 && year < 5800; year++) {
            final first = HDate(15, Months.tishrei, year);
            final dow = first.getDay();
            if (!table.containsKey(dow) || !seen.add(dow)) continue;
            for (var day = 0; day < 6; day++) {
              final d = first.addDays(day);
              final said = [
                for (final i in resolver.resolve(root.find("Festivals/Sukkot/Hosha'anot")!, versions,
                    (s) => DayContext.forService(d, s, il: false),
                    options: const ResolveOptions(excluded: ExcludedDisplay.hide)))
                  if (i is SegmentItem && i.kind == SegmentKind.prayer && i.he != null)
                    [for (final r in i.he!.runs) if (!r.marker) r.html].join().replaceAll(RegExp(r'[^א-ת]'), ''),
              ].join('|');
              final want = table[dow]![day];
              for (final MapEntry(key: k, value: text) in open.entries) {
                expect(said.contains('|$text') || said.startsWith(text), k == want,
                    reason: '$year, 15 Tishrei on day $dow, day ${day + 1}: $k');
              }
            }
          }
          expect(seen, {1, 2, 4, 6});
        });
        test('leaving the sukkah: Shemini Atzeret abroad, Hoshana Rabbah in Israel (Rema 667:1)', () {
          bool leaving(HDate d, bool il) => resolver
              .resolve(root.find('Festivals/Sukkot/Prayers in the Sukkah')!, versions, (s) => DayContext.forService(d, s, il: il),
                  options: const ResolveOptions(excluded: ExcludedDisplay.hide))
              .any((i) => i is SegmentItem && i.node.id.endsWith('Leaving the Sukkah'));
          expect(leaving(HDate(22, Months.tishrei, 5788), false), isTrue);
          expect(leaving(HDate(21, Months.tishrei, 5788), false), isFalse);
          expect(leaving(HDate(21, Months.tishrei, 5788), true), isTrue);
          expect(leaving(HDate(22, Months.tishrei, 5788), true), isFalse);
        });
        test('bentching: Migdol on Shabbat, Yom Tov, Rosh Chodesh and Chol HaMoed; Magdil otherwise (MB 189:5)', () {
          String bentch(HDate d) => [
                for (final i in said('Berachot/Birkat HaMazon', d))
                  if (i.he != null) for (final r in i.he!.runs) if (!r.marker) r.html,
              ].join(' ').replaceAll(RegExp(r'[^א-ת ]'), '');
          for (final (d, migdol) in [
            (HDate(19, Months.tevet, 5787), false),
            (HDate(1, Months.cheshvan, 5787), true),
            (HDate(18, Months.tishrei, 5788), true),
            (HDate(26, Months.kislev, 5787), false),
          ]) {
            expect(bentch(d).contains('מגדול ישועות'), migdol, reason: '$d');
            expect(bentch(d).contains('מגדיל ישועות'), !migdol, reason: '$d');
          }
        });
        test('Morid HaTal in Israel is highlighted for 30 days after Pesach, not all summer', () {
          Applicability moridHatal(HDate d) => [
                for (final i in resolver.resolve(root.find('Weekday/Shacharit/Amidah/Divine Might')!, versions,
                    (s) => DayContext.forService(d, s, il: true)))
                  if (i is SegmentItem && i.kind == SegmentKind.prayer && i.he!.segment.html.replaceAll(RegExp(r'[^א-ת]'), '') == 'מורידהטל')
                    i.applicability,
              ].single;
          expect(moridHatal(HDate(20, Months.nisan, 5787)), Applicability.today);
          expect(moridHatal(HDate(8, Months.tamuz, 5787)), Applicability.always);
        });
        test('Kaddish: "Oseh shalom" all year, "Oseh hashalom" in the Ten Days, never without "Oseh"', () {
          String said_(HDate d) => [
                for (final i in said('Weekday/Shacharit/Concluding Prayers/Kaddish Shalem', d))
                  if (i.he != null) for (final r in i.he!.runs) if (!r.marker) r.html,
              ].join(' ').replaceAll(RegExp(r'[^א-ת]'), '');
          expect(said_(HDate(19, Months.tevet, 5787)), contains('עושהשלוםבמרומיו'));
          expect(said_(HDate(4, Months.tishrei, 5788)), contains('עושההשלוםבמרומיו'));
        });
        test('the Ten Days\' wording is highlighted as today\'s, and the everyday wording is not said', () {
          final tenDays = HDate(4, Months.tishrei, 5788);
          for (final svc in ['Shacharit/Amidah', 'Minchah/Amida', 'Maariv/Amidah']) {
            final runs = [
              for (final i in said('Weekday/$svc/Holiness of God', tenDays))
                if (i.kind == SegmentKind.prayer) ...i.he!.runs.where((r) => !r.marker),
            ];
            String bare(ResolvedRun r) => r.html.replaceAll(RegExp(r'[^א-ת]'), '');
            final king = runs.where((r) => bare(r).contains('המלךהקדוש'));
            expect(king, isNotEmpty, reason: svc);
            expect(king.every((r) => r.applicability == Applicability.today), isTrue, reason: svc);
          }
        });
        test('a blessing\'s closing line is not set apart from its body', () {
          String bare(SegmentItem i) => [for (final r in i.he!.runs) if (!r.marker) r.html].join().replaceAll(RegExp(r'[^א-ת]'), '');
          final tenDays = HDate(5, Months.tishrei, 5786);
          for (final (section, closing) in [
            ('Justice', 'ברוךאתהיהוהמלךאהבצדקהומשפט'),
            ('Holiness of God', 'ברוךאתהיהוההאלהקדוש'),
            ('Rebuilding Jerusalem', 'ברוךאתהיהוהבונהירושלים'),
            ('Peace', 'ברוךאתהיהוההמברךאתעמוישראלבשלום'),
          ]) {
            final items = said('Weekday/Minchah/Amida/$section', plain).where((i) => i.kind == SegmentKind.prayer).toList();
            expect(items, hasLength(1), reason: section);
            expect(bare(items.single), endsWith(closing), reason: section);
            expect(items.single.tr?.runs.map((r) => r.html).join(), contains('Blessed are You'), reason: section);
          }
          final justice = said('Weekday/Minchah/Amida/Justice', tenDays).where((i) => i.kind == SegmentKind.prayer).toList();
          expect(justice, hasLength(1));
          expect(bare(justice.single), endsWith('ברוךאתהיהוההמלךהמשפט'));
        });
        test('Mashiv HaRuach and the seasonal Ve\'ten are highlighted for 30 days after they begin, not after', () {
          String bare(SegmentItem i) => (i.he?.segment.html ?? '').replaceAll(RegExp(r'[^א-ת]'), '');
          bool highlighted(HDate day, String section, String word) =>
              said(section, day).any((i) => i.applicability == Applicability.today && bare(i) == word);
          bool shown(HDate day, String section, String word) => said(section, day).any((i) => bare(i) == word);
          const mashiv = 'משיבהרוחומורידהגשם'; // "Mashiv haruach umorid hagashem"
          const divine = 'Weekday/Minchah/Amida/Divine Might';
          final shevat = HDate(10, Months.shvat, 5786);
          // 13 Cheshvan is 21 days after Shmini Atzeret; 10 Shevat is long after.
          expect(shown(plain, divine, mashiv), isTrue);
          expect(highlighted(plain, divine, mashiv), isTrue);
          expect(shown(shevat, divine, mashiv), isTrue);
          expect(highlighted(shevat, divine, mashiv), isFalse);
          // "Ve'ten bracha" is highlighted for 30 days after Pesach.
          const prosperity = 'Weekday/Minchah/Amida/Prosperity';
          expect(highlighted(HDate(5, Months.iyyar, 5786), prosperity, 'ברכה'), isTrue);
          expect(shown(HDate(5, Months.sivan, 5786), prosperity, 'ברכה'), isTrue);
          expect(highlighted(HDate(5, Months.sivan, 5786), prosperity, 'ברכה'), isFalse);
        });
      }
      if (slug == 'ashkenaz') {
        test('service graph: Rosh Chodesh Shacharit in order', () {
          final items = service('Weekday/Shacharit', roshChodesh);
          final amidah = firstAt(items, 'Weekday/Shacharit/Amidah');
          final hallel = firstAt(items, 'Festivals/Rosh Chodesh/Hallel');
          final uva = firstAt(items, 'Weekday/Shacharit/Concluding Prayers/Uva Letzion');
          final musaf = firstAt(items, 'Festivals/Rosh Chodesh/Musaf Amidah for Rosh Chodesh');
          final alenu = firstAt(items, 'Weekday/Shacharit/Concluding Prayers/Alenu');
          expect([amidah, hallel, uva, musaf, alenu].every((i) => i >= 0), isTrue);
          expect(amidah < hallel && hallel < uva && uva < musaf && musaf < alenu, isTrue);
        });
        test('service graph: Hoshanot after Musaf on Chol HaMoed Sukkot', () {
          final items = service('Weekday/Shacharit', cholHamoedSukkot);
          final musaf = firstAt(items, 'Festivals/Shalosh Regalim/Mussaf');
          final hoshanot = firstAt(items, "Festivals/Sukkot/Hosha'anot");
          expect(musaf >= 0 && hoshanot > musaf, isTrue);
          expect(firstAt(items, 'Festivals/Rosh Chodesh/Musaf Amidah for Rosh Chodesh'), -1);
        });
        test('service graph: Selichot after the Amidah on a fast day', () {
          final items = service('Weekday/Shacharit', fast);
          final selichot = firstAt(items, 'Festivals/Selichot/Ten of Tevet');
          expect(selichot, greaterThan(firstAt(items, 'Weekday/Shacharit/Amidah')));
          expect(selichot, lessThan(firstAt(items, 'Weekday/Shacharit/Post Amidah')));
        });
      }
      if (slug == 'sefard') {
        test('service graph: Hoshanot after Hallel on Chol HaMoed Sukkot', () {
          final items = service('Weekday Shacharit', cholHamoedSukkot);
          final hallel = firstAt(items, 'Rosh Chodesh/Hallel');
          final hoshanot = firstAt(items, 'Sukkot');
          final torah = firstAt(items, 'Weekday Shacharit/Torah Reading');
          expect(hallel >= 0 && hoshanot > hallel && hoshanot < torah, isTrue);
        });
      }

      test('a section opened on a day none of it is said is not blank', () {
        for (final top in root.children) {
          final items = resolver.resolve(top, versions, (s) => DayContext.forService(plain, s, il: false),
              options: const ResolveOptions(excluded: ExcludedDisplay.hide));
          expect(items.any((i) => i is! HeadingItem), isTrue, reason: top.id);
        }
      });

      test('the Daily Psalm is never marked as today\'s (corpus `plain`)', () {
        const psalm = {
          'ashkenaz': 'Weekday/Shacharit/Concluding Prayers/Song of the Day',
          'chabad': 'Shacharit/Song of the Day',
          'edot_hamizrach': 'Weekday Shacharit/Song of the Day',
          'koren': 'Weekdays/The Daily Psalm',
          'sefard': 'Weekday Shacharit/Song of the Day',
        };
        // Sunday 11 Cheshvan 5786 through Friday.
        for (var d = 11; d <= 16; d++) {
          final items = said(psalm[slug]!, HDate(d, Months.cheshvan, 5786));
          expect(items.where((i) => i.kind == SegmentKind.prayer), isNotEmpty, reason: '$d Cheshvan');
          expect(items.where((i) => i.applicability == Applicability.today), isEmpty, reason: '$d Cheshvan');
        }
      });

      test('a year resolves with nothing undetermined', () {
        final unknown = <String, int>{};
        var day = HDate(1, Months.tishrei, 5786);
        final end = HDate(1, Months.tishrei, 5787).abs();
        // Every 5th day keeps it quick while still meeting every season.
        while (day.abs() < end) {
          for (final top in root.children) {
            for (final i in resolver.resolve(top, versions, (s) => DayContext.forService(day, s, il: false))) {
              // "If: …" lines are personal circumstances, left to the reader,
              // as is the service in a section printed for several (`any`).
          if (i is SegmentItem &&
              i.applicability == Applicability.unknown &&
              !(i.labelEn?.startsWith('If') ?? false) &&
              corpus.leaf(i.node.id)?.service != 'any') {
                final k = '${i.node.id} [${i.labelEn}]';
                unknown[k] = (unknown[k] ?? 0) + 1;
              }
            }
          }
          day = HDate.fromAbs(day.abs() + 5);
        }
        expect(unknown.keys, isEmpty, reason: unknown.keys.take(25).join('\n'));
      });
    });
  }
}
