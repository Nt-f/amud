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
  for (final MapEntry(key: title, value: slug) in books.entries) {
    test('probe $slug', () async {
      final lib = SiddurLibrary(_FileSource(), gzip.decode);
      final book = (await lib.manifest()).book(title)!;
      final corpus = Corpus.fromJson(jsonDecode(utf8.decode(gzip.decode(File('../../assets/corpus/$slug.json.gz').readAsBytesSync()))) as Map<String, Object?>);
      final root = corpus.index!;
      final bookRules = (rules[title] as Map<String, dynamic>?) ?? const {};
      final resolver = SiddurResolver().withOverrides(bookRules).withCorpus(corpus);
      final versions = VersionSelection([CorpusTextVersion(corpus, corpus.versionInfo('he')!)], [CorpusTextVersion(corpus, corpus.versionInfo('en')!)]);
      final days = {
        'plain': HDate(13, Months.cheshvan, 5786),
        'tenDays': HDate(5, Months.tishrei, 5786),
        'roshChodesh': HDate(1, Months.kislev, 5786),
        'chanukah': HDate(27, Months.kislev, 5786),
        'purim': HDate.fromDate(DateTime(2026, 3, 3)),
        'summer': HDate(5, Months.sivan, 5786),
        'shabbatShuva': HDate(7, Months.tishrei, 5786),
      };
      final bad = <String>{};
      final re = RegExp(r"ten days|rosh chodesh|new moon|chanuk|hanuk|purim|tisha|fast day|public fast|yom tov|festival|chol hamoed|holiday|shabbat|sabbath|summer|winter|rainy|motzaei|saturday night|sunday|monday|thursday|if one|if you|forgot|erred|mistake", caseSensitive: false);
      for (final leaf in root.leaves) {
        final items = resolver.resolve(leaf, versions, (s) => DayContext.forService(days['plain']!, s, il: false),
            options: const ResolveOptions(excluded: ExcludedDisplay.hide));
        for (final i in items) {
          if (i is! SegmentItem || i.excluded || i.he == null) continue;
          if (i.kind != SegmentKind.instruction) continue;
          if (i.applicability != Applicability.always) continue;
          final t = i.he!.runs.map((r) => r.html).join().replaceAll(RegExp(r'<[^>]*>'), '');
          bad.add('${leaf.id}|${i.key.split(':')[2]}|${t.length > 70 ? t.substring(0, 70) : t}');
        }
      }
      File('/tmp/claude-1000/-home-n-Downloads-flutter-siddur/14780671-0546-4814-91cb-3e67757a87c6/scratchpad/instr_$slug.txt').writeAsStringSync(bad.join('\n'));
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}
