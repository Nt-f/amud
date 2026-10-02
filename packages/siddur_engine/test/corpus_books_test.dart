import 'dart:convert';
import 'dart:io';

import 'package:hebcal/hebcal.dart';
import 'package:siddur_engine/siddur_engine.dart';
import 'package:test/test.dart';

class _FileSource implements TextSource {
  @override
  Future<List<int>> readBytes(String file) => File('../../$file').readAsBytes();
}

/// Every tagged siddur (assets/corpus): the corpus covers the book, was
/// tagged on the Hebrew the app shows by default, and resolves a whole
/// year without anything left undetermined.
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
        root = await lib.index(book);
        corpus = Corpus.fromJson(
            jsonDecode(utf8.decode(gzip.decode(File('../../assets/corpus/$slug.json.gz').readAsBytesSync())))
                as Map<String, Object?>);
        final bookRules = (rules[title] as Map<String, dynamic>?) ?? const {};
        resolver = SiddurResolver().withOverrides(bookRules).withCorpus(corpus);
        // The app's default order: rules.json's defaultVersions, then the
        // manifest's (see versionOrderProvider).
        final defaults = ((bookRules['defaultVersions'] as Map?)?.cast<String, List>()) ?? const {};
        Future<List<TextVersion>> load(String lang) {
          final titles = <String>{
            for (final t in defaults[lang] ?? const []) t as String,
            for (final v in book.byLanguage(lang))
              if (lang == 'he' || v.languageTag == null) v.versionTitle,
          };
          return Future.wait([
            for (final t in titles)
              if (book.byLanguage(lang).any((v) => v.versionTitle == t))
                lib.version(book.byLanguage(lang).firstWhere((v) => v.versionTitle == t)),
          ]);
        }

        versions = VersionSelection(await load('he'), await load('en'));
      });

      test('the corpus covers the book, on the default Hebrew', () {
        final missing = <String>[];
        final otherVersion = <String>[];
        for (final l in root.leaves) {
          final (info, _) = versions.pick(versions.hebrew, l.path);
          if (info == null) continue;
          final c = corpus.leaf(l.id);
          if (c == null) {
            missing.add(l.id);
          } else if (c.he != null && c.he!.version.trim() != info.versionTitle.trim()) {
            otherVersion.add('${l.id}: ${c.he!.version} vs ${info.versionTitle}');
          }
        }
        expect(missing, isEmpty, reason: missing.take(10).join('\n'));
        expect(otherVersion, isEmpty, reason: otherVersion.take(10).join('\n'));
      });

      List<SegmentItem> said(String section, HDate day, {Minhagim m = const Minhagim()}) => [
            for (final i in resolver.resolve(root.find(section)!, versions,
                (s) => DayContext.forService(day, s, il: false, minhagim: m),
                options: const ResolveOptions(excluded: ExcludedDisplay.hide)))
              if (i is SegmentItem && !i.excluded) i
          ];
      final plain = HDate(13, Months.cheshvan, 5786); // a Tuesday
      final roshChodesh = HDate(1, Months.kislev, 5786);

      // Leaf conditions found wrong in review (tool/corpus/reconcile.py).
      if (slug == 'edot_hamizrach') {
        test('the weekday Amidah is said on an ordinary day', () {
          expect(said('Weekday Shacharit/Amida', plain).where((i) => i.kind == SegmentKind.prayer), isNotEmpty);
          expect(said('Weekday Shacharit', plain).any((i) => i.node.id == 'Weekday Shacharit/Amida'), isTrue);
        });
      }
      if (slug == 'sefard') {
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

      test('a year resolves with nothing undetermined', () {
        final unknown = <String, int>{};
        var day = HDate(1, Months.tishrei, 5786);
        final end = HDate(1, Months.tishrei, 5787).abs();
        // Every 5th day keeps it quick while still meeting every season.
        while (day.abs() < end) {
          for (final top in root.children) {
            for (final i in resolver.resolve(top, versions, (s) => DayContext.forService(day, s, il: false))) {
              // "If: …" lines are personal circumstances, left to the reader.
          if (i is SegmentItem && i.applicability == Applicability.unknown && !(i.labelEn?.startsWith('If') ?? false)) {
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
