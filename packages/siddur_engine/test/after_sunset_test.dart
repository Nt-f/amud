import 'dart:convert';
import 'dart:io';

import 'package:hebcal/hebcal.dart';
import 'package:siddur_engine/siddur_engine.dart';
import 'package:test/test.dart';

/// Birkat HaMazon read after sunset (ResolveOptions.night): the night's
/// additions, and the ended day's folded for a meal eaten before sunset.
void main() {
  setUpAll(initHebcal);
  late SchemaNode root;
  late VersionSelection versions;
  late SiddurResolver resolver;

  setUpAll(() async {
    final corpus = Corpus.fromJson(
        jsonDecode(utf8.decode(gzip.decode(File('../../assets/corpus/ashkenaz.json.gz').readAsBytesSync()))) as Map<String, Object?>);
    root = corpus.index!;
    resolver = SiddurResolver().withCorpus(corpus);
    versions = VersionSelection([CorpusTextVersion(corpus, corpus.versionInfo('he')!)], [CorpusTextVersion(corpus, corpus.versionInfo('en')!)]);
  });

  List<RenderItem> bentch(HDate day, {required bool night, ExcludedDisplay excluded = ExcludedDisplay.hide}) => resolver.resolve(
        root.find('Berachot/Birkat HaMazon')!,
        versions,
        (svc) => DayContext.forService(day, svc, il: false),
        options: ResolveOptions(
            excluded: excluded, night: night ? (svc) => DayContext.forService(day.next(), svc, il: false) : null),
      );

  String text(SegmentItem s) => stripHtml(s.he!.segment.html).replaceAll(RegExp('[\u0591-\u05C7]'), '');
  Iterable<SegmentItem> said(List<RenderItem> items) => items.whereType<SegmentItem>().where((s) => !s.excluded);

  test("Rosh Chodesh's Ya'aleh VeYavo after sunset is folded, for a meal eaten before it", () {
    final rc = HDate(1, Months.kislev, 5787);
    expect(said(bentch(rc, night: false)).any((s) => text(s).contains('יעלה ויבא')), isTrue);
    for (final mode in ExcludedDisplay.values) {
      final items = bentch(rc, night: true, excluded: mode);
      expect(said(items).any((s) => text(s).contains('יעלה ויבא')), isFalse, reason: '$mode');
      final folded = items.whereType<ExcludedGroupItem>().where((g) => g.beforeSunset).toList();
      expect(folded.any((g) => g.items.any((s) => text(s).contains('יעלה ויבא'))), isTrue, reason: '$mode');
    }
  });

  test('Friday night: Retzei, as on Shabbat', () {
    final friday = HDate(5, Months.cheshvan, 5787);
    expect(friday.getDay(), 5);
    bool retzei(Iterable<SegmentItem> l) => l.any((s) => text(s).contains('רצה והחליצנו'));
    expect(retzei(said(bentch(friday, night: false))), isFalse);
    expect(retzei(said(bentch(friday, night: true))), isTrue);
  });

  test('an ordinary evening is unchanged', () {
    final tuesday = HDate(9, Months.cheshvan, 5787);
    expect(bentch(tuesday, night: true).whereType<ExcludedGroupItem>().where((g) => g.beforeSunset), isEmpty);
  });
}
