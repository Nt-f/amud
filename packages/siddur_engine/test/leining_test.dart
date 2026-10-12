import 'dart:convert';
import 'dart:io';

import 'package:hebcal/hebcal.dart';
import 'package:siddur_engine/siddur_engine.dart';
import 'package:test/test.dart';

class _FileSource implements TextSource {
  @override
  Future<List<int>> readBytes(String file) => File('../../$file').readAsBytes();
}

void main() {
  setUpAll(initHebcal);
  final rules = jsonDecode(File('../../assets/rules/rules.json').readAsStringSync()) as Map<String, dynamic>;
  const books = {
    'Siddur Ashkenaz': 'ashkenaz',
    'Weekday Siddur Chabad': 'chabad',
    'Siddur Sefard': 'sefard',
    'Siddur Edot HaMizrach': 'edot_hamizrach',
    'The Koren Shalem Siddur; Ashkenaz': 'koren',
  };
  // Shabbat Bereshit 5787 (a Shabbat), the Monday and Tuesday after.
  final shabbat = HDate(26, Months.tishrei, 5787).onOrAfter(6);
  final monday = shabbat.addDays(9);
  final tuesday = shabbat.addDays(10);

  for (final MapEntry(key: title, value: slug) in books.entries) {
    test('$slug: the day\'s Torah reading appears where the siddur has one', () async {
      final lib = SiddurLibrary(_FileSource(), gzip.decode);
      final book = (await lib.manifest()).book(title)!;
      final corpus = Corpus.fromJson(
          jsonDecode(utf8.decode(gzip.decode(File('../../assets/corpus/$slug.json.gz').readAsBytesSync()))) as Map<String, Object?>);
      final root = corpus.index!;
      final resolver = SiddurResolver().withOverrides((rules[title] as Map<String, dynamic>?) ?? const {}).withCorpus(corpus);
      final versions = VersionSelection([CorpusTextVersion(corpus, corpus.versionInfo('he')!)], [CorpusTextVersion(corpus, corpus.versionInfo('en')!)]);
      expect(book, isNotNull);
      List<DynamicItem> leining(HDate day) => [
            for (final l in root.leaves)
              for (final i in resolver.resolve(l, versions, (s) => DayContext.forService(day, s, il: false),
                  options: const ResolveOptions(excluded: ExcludedDisplay.hide)))
                if (i is DynamicItem && i.kind == 'leining') i,
          ];
      final onShabbat = leining(shabbat);
      final onTuesday = leining(tuesday);
      print('$slug shabbat=${onShabbat.length} monday=${leining(monday).length} tuesday=${onTuesday.length}');
      expect(onTuesday, isEmpty);
      if (slug == 'ashkenaz') {
        List<DynamicItem> service(String section, HDate day) => [
              for (final i in resolver.resolve(root.find(section)!, versions, (s) => DayContext.forService(day, s, il: false),
                  options: const ResolveOptions(excluded: ExcludedDisplay.hide)))
                if (i is DynamicItem && i.kind == 'leining') i,
            ];
        final onMonday = service('Weekday/Shacharit', monday);
        expect(onMonday, hasLength(1));
        expect(onMonday.single.data['scope'], 'first');
        expect(onMonday.single.data['parsha'], getSedra(5787, false).lookup(shabbat.addDays(14)).parsha);
        expect(service('Weekday/Shacharit', tuesday), isEmpty);
        final onShabbat = service('Shabbat/Shacharit', shabbat);
        expect(onShabbat, hasLength(1));
        expect(onShabbat.single.data['scope'], 'shabbat');
        expect((onShabbat.single.data['ranges'] as List), hasLength(7));
      }
      for (final i in onShabbat) {
        expect(i.data['parsha'], isNotEmpty);
      }
    });
  }
}
