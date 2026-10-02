import 'dart:io';

import 'package:hebcal/hebcal.dart';
import 'package:siddur_engine/siddur_engine.dart';
import 'package:test/test.dart';

class _FileSource implements TextSource {
  @override
  Future<List<int>> readBytes(String file) => File('../../$file').readAsBytes();
}

HDate _greg(int y, int m, int d) => HDate.fromDate(DateTime(y, m, d));

void main() {
  setUpAll(initHebcal);

  group('Condition', () {
    test('parses and evaluates', () {
      final env = <String, Object>{'a': true, 'b': false, 'n': 3};
      expect(Condition.parse('a && !b').eval(env), isTrue);
      expect(Condition.parse('a && (b || n >= 3)').eval(env), isTrue);
      expect(Condition.parse('n in [1, 2]').eval(env), isFalse);
      expect(Condition.parse('n in [3]').eval(env), isTrue);
      final unknown = <String>{};
      Condition.parse('zzz || b').eval(env, unknown);
      expect(unknown, {'zzz'});
      expect(() => Condition.parse('a &&'), throwsA(isA<ConditionParseException>()));
    });
  });

  group('rubrics', () {
    test('Hebrew', () {
      expect(matchRubric('בראש חדש ובחול המועד אומרים זה:')!.expression, '(roshChodesh || cholHamoed)');
      expect(matchRubric('בעשי"ת:')!.expression, 'aseretYemeiTeshuva');
      expect(matchRubric('בחנוכה:')!.expression, 'chanukah');
      expect(matchRubric('קהל וחזן:'), isNull);
      expect(matchRubric('בקיץ:')!.resolveSeason('מוֹרִיד הַטָּל').expression, 'moridHatal');
      expect(matchRubric('בימות הגשמים:')!.resolveSeason('טַל וּמָטָר לִבְרָכָה').expression, 'talUmatar');
    });
    test('English', () {
      expect(matchRubric('On Rosh Ḥodesh and Ḥol HaMo’ed, say:')!.expression, '(roshChodesh || cholHamoed)');
      expect(matchRubric('From the Musaf of Shemini Atzeres until the Musaf of the first day of Pesach you should say:')!
          .expression, 'mashivHaruach');
      expect(matchRubric('In Israel, in spring and summer:')!.resolveSeason('He causes the dew to fall').expression,
          'il && moridHatal');
    });
  });

  group('DayContext', () {
    test('Rosh Chodesh / seasons', () {
      final c = DayContext(HDate(30, Months.tishrei, 5786), il: false);
      expect(c['roshChodesh'], isTrue);
      expect(c['mashivHaruach'], isTrue);
      expect(c['talUmatar'], isFalse);
      expect(c['tachanunShacharit'], isFalse);
      expect(c['hallel'], isTrue);
      expect(c['halfHallel'], isTrue);
    });
    test('Mashiv HaRuach starts at Musaf of Shmini Atzeret', () {
      final sa = HDate(22, Months.tishrei, 5786);
      expect(DayContext(sa, il: false, service: Service.shacharit)['mashivHaruach'], isFalse);
      expect(DayContext(sa, il: false, service: Service.musaf)['mashivHaruach'], isTrue);
    });
    test("Tal u'matar: diaspora from the evening of Dec 4 (5 before leap year)", () {
      // 2025: begins Maariv Dec 4, so daytime Dec 5 is the first full day.
      expect(DayContext.forService(_greg(2025, 12, 4), Service.maariv, il: false)['talUmatar'], isTrue);
      expect(DayContext(_greg(2025, 12, 4), il: false, service: Service.mincha)['talUmatar'], isFalse);
      // 2027 precedes leap year 2028: begins Dec 5 evening.
      expect(DayContext(_greg(2027, 12, 5), il: false, service: Service.mincha)['talUmatar'], isFalse);
      expect(DayContext.forService(_greg(2027, 12, 5), Service.maariv, il: false)['talUmatar'], isTrue);
      // Israel: 7 Cheshvan.
      expect(DayContext(HDate(7, Months.cheshvan, 5786), il: true)['talUmatar'], isTrue);
      expect(DayContext(HDate(6, Months.cheshvan, 5786), il: true)['talUmatar'], isFalse);
    });
    test('Omer at Maariv counts the coming day', () {
      final c = DayContext.forService(HDate(15, Months.nisan, 5786), Service.maariv, il: false);
      expect(c.number('omerDay'), 1);
    });
    test('Chanukah and Purim', () {
      expect(DayContext(HDate(25, Months.kislev, 5786), il: false).number('chanukahDay'), 1);
      expect(DayContext(HDate(24, Months.kislev, 5786), il: false)['chanukah'], isFalse);
      final adar = isLeapYear(5786) ? Months.adarII : Months.adarI;
      expect(DayContext(HDate(14, adar, 5786), il: false)['purim'], isTrue);
      expect(DayContext(HDate(14, adar, 5786), il: false, minhagim: const Minhagim(walledCity: true))['purim'],
          isFalse);
    });
  });

  group('resolver (bundled Sefaria assets)', () {
    late SiddurLibrary lib;
    late BookInfo book;
    late SchemaNode root;
    late VersionSelection sel;
    setUpAll(() async {
      lib = SiddurLibrary(_FileSource(), gzip.decode);
      final m = await lib.manifest();
      book = m.book('Siddur Ashkenaz')!;
      root = await lib.index(book);
      final he = book.versions.firstWhere((v) => v.versionTitle == 'The Metsudah siddur, 1981');
      sel = VersionSelection([await lib.version(he)], const []);
    });

    List<SegmentItem> segs(HDate hd) {
      final node = root.find('Weekday/Shacharit/Amidah/Temple Service')!;
      return SiddurResolver()
          .resolve(node, sel, (s) => DayContext(hd, il: false, service: s),
              options: const ResolveOptions(excluded: ExcludedDisplay.dim))
          .whereType<SegmentItem>()
          .toList();
    }

    test("Ya'aleh VeYavo highlighted on Rosh Chodesh, excluded otherwise", () {
      bool yaaleh(SegmentItem s) => stripHtml(s.he!.segment.html).contains('יַעֲלֶה');
      expect(segs(HDate(1, Months.cheshvan, 5786)).firstWhere(yaaleh).applicability, Applicability.today);
      expect(segs(HDate(5, Months.cheshvan, 5786)).firstWhere(yaaleh).applicability, Applicability.notToday);
    });

    test('hide removes everything not said today', () {
      final node = root.find('Weekday/Shacharit/Amidah')!;
      final items = SiddurResolver().resolve(node, sel, (s) => DayContext(HDate(5, Months.cheshvan, 5786), il: false, service: s),
          options: const ResolveOptions(excluded: ExcludedDisplay.hide));
      final segs = items.whereType<SegmentItem>().toList();
      expect(segs, isNotEmpty);
      expect(segs.where((s) => s.excluded), isEmpty);
      expect(segs.expand((s) => s.he!.runs).where((r) => r.applicability == Applicability.notToday), isEmpty);
      // Chol HaMoed Sukkot: Ya'aleh VeYavo is said with the Sukkot option;
      // Rosh Chodesh and Pesach are hidden like anything else not said.
      final sukkot = SiddurResolver()
          .resolve(node, sel, (s) => DayContext(HDate(18, Months.tishrei, 5787), il: false, service: s),
              options: const ResolveOptions(excluded: ExcludedDisplay.hide))
          .whereType<SegmentItem>()
          .firstWhere((s) => stripHtml(s.he!.segment.html).contains('יַעֲלֶה'));
      expect(sukkot.applicability, Applicability.today);
      final options = sukkot.he!.runs.where((r) => r.applicability != Applicability.always && !r.marker).toList();
      expect(options.map((r) => r.applicability), [Applicability.today]);
      expect(segs.where((s) => stripHtml(s.he!.segment.html).contains('יַעֲלֶה')), isEmpty);
      expect(items.whereType<CollapsedSectionItem>(), isEmpty);
      expect(items.whereType<ExcludedGroupItem>(), isEmpty);
    });

    List<RenderItem> maariv(HDate hd, {bool concise = false}) => SiddurResolver().resolve(
        root.find('Weekday/Maariv/Amidah')!, sel, (s) => DayContext(hd, il: false, service: s),
        options: ResolveOptions(excluded: ExcludedDisplay.hide, showNotes: true, conciseNotes: concise));
    String plain(SegmentItem s) => stripHtml(s.he!.segment.html);

    test('notes and instructions go with the lines they are about', () {
      final weekday = maariv(HDate(5, Months.cheshvan, 5787)).whereType<SegmentItem>().map(plain).join('\n');
      expect(weekday, isNot(contains('בראש חדש ובחול המועד אומרים')));
      expect(weekday, isNot(contains('אם לא אמר זכרנו')));
      expect(weekday, isNot(contains('בקיץ:')), reason: 'winter: no Morid HaTal');
      expect(weekday, isNot(contains('אַתָּה חוֹנַנְתָּנוּ')), reason: 'Atah Chonantanu is for Motzaei Shabbat');
      final rc = maariv(HDate(30, Months.cheshvan, 5787)).whereType<SegmentItem>().toList();
      final announce = rc.firstWhere((s) => plain(s).contains('בראש חדש ובחול המועד אומרים'));
      expect(announce.announces, isTrue);
      expect(announce.applicability, Applicability.today);
    });

    test('concise notes: short, and only when relevant', () {
      List<String> notes(HDate hd) =>
          [for (final d in maariv(hd, concise: true).whereType<DynamicItem>()) if (d.kind == 'note') '${d.data['en']}'];
      expect(notes(HDate(15, Months.kislev, 5787)), isEmpty);
      expect(notes(HDate(5, Months.cheshvan, 5787)).single, contains('Mashiv HaRuach'), reason: 'first 30 days');
      expect(notes(HDate(30, Months.cheshvan, 5787)), [contains('Forgot it at Maariv of Rosh Chodesh')]);
      expect(notes(HDate(18, Months.tishrei, 5787)).single, contains('go back to Retzei'));
      expect(notes(HDate(5, Months.tishrei, 5787)), hasLength(3), reason: 'Zochreinu, HaMelech HaKadosh, HaMelech HaMishpat');
      final items = maariv(HDate(18, Months.tishrei, 5787), concise: true).whereType<SegmentItem>();
      expect(items.where((s) => s.kind == SegmentKind.note), isEmpty);
    });

    test("each day's Hoshanos apply on that day only", () async {
      final resolver = SiddurResolver();
      List<String> today(SchemaNode parent, HDate hd) => [
            for (final n in parent.children)
              if (Condition.parse(resolver.sectionRuleFor(n)?.when ?? 'false').eval(DayContext(hd, il: false).env)) n.en,
          ];
      final hoshanot = root.find("Festivals/Sukkot/Hosha'anot")!;
      // 5787: the first day of Sukkot is Shabbat.
      expect(today(hoshanot, HDate(15, Months.tishrei, 5787)), ['For Shabbat Chol Hamoed']);
      expect(today(hoshanot, HDate(19, Months.tishrei, 5787)), ['Fifth Day of Sukkot']);
      expect(today(hoshanot, HDate(21, Months.tishrei, 5787)), ["Hosha'ana Rabba"]);
      expect(today(hoshanot, HDate(23, Months.tishrei, 5787)), isEmpty);
      final koren = await lib.index((await lib.manifest()).book('The Koren Shalem Siddur; Ashkenaz')!);
      final festivals = koren.find('Festivals')!;
      List<String> korenToday(HDate hd) => today(festivals, hd).where((t) => t.startsWith('Hoshanot')).toList();
      expect(korenToday(HDate(21, Months.tishrei, 5787)), ['Hoshanot', 'Hoshanot for Hoshana Raba']);
      expect(korenToday(HDate(15, Months.tishrei, 5787)), ['Hoshanot', "Hoshanot for Shabbat Hol HaMo'ed"]);
      expect(korenToday(HDate(18, Months.tishrei, 5787)), ['Hoshanot']);
    });

    test('prayer text and notes languages are independent', () async {
      final en = book.versions.firstWhere((v) => v.language == 'en' && v.versionTitle.contains('Metsudah'));
      final both = VersionSelection(sel.hebrew, [await lib.version(en)]);
      List<SegmentItem> run(ResolveOptions o) => SiddurResolver()
          .resolve(root.find('Weekday/Shacharit/Amidah')!, both, (s) => DayContext(HDate(5, Months.cheshvan, 5786), il: false, service: s),
              options: o)
          .whereType<SegmentItem>()
          .toList();
      final heOnly = run(const ResolveOptions(showTranslation: false));
      expect(heOnly.where((s) => s.kind == SegmentKind.prayer && s.tr != null), isEmpty);
      expect(heOnly.where((s) => s.kind != SegmentKind.prayer && s.tr != null), isNotEmpty);
      final enNotes = run(const ResolveOptions(showTranslation: false, notesHebrew: false));
      expect(enNotes.where((s) => s.kind != SegmentKind.prayer && s.he != null), isEmpty);
      expect(enNotes.where((s) => s.kind == SegmentKind.prayer && s.he == null), isEmpty);
    });

    test("English rubrics that can't sit beside the Hebrew aren't left pointing at nothing", () async {
      // The Shema with te'amim (5 lines) and the Metsudah English (12)
      // split it differently, so the English can't be lined up with it.
      final he = book.versions.firstWhere((v) => v.language == 'he' && v.versionTitle.toLowerCase().contains('cantillation'));
      final en = book.versions.firstWhere((v) => v.language == 'en' && v.versionTitle.contains('Metsudah'));
      final sel = VersionSelection([await lib.version(he)], [await lib.version(en)]);
      List<SegmentItem> run(ResolveOptions o) => SiddurResolver()
          .resolve(root.find('Weekday/Shacharit/Blessings of the Shema/Shema')!, sel,
              (s) => DayContext(HDate(5, Months.cheshvan, 5786), il: false, service: s),
              options: o)
          .whereType<SegmentItem>()
          .toList();
      String text(SegmentItem s) => stripHtml(s.tr?.segment.html ?? '');
      final notes = run(const ResolveOptions(showTranslation: false, notesHebrew: false));
      expect(notes.where((s) => s.he != null), isNotEmpty);
      expect(notes.where((s) => s.he == null && s.kind != SegmentKind.note), isEmpty);
      // With the English shown, they stay with the lines they introduce.
      final both = run(const ResolveOptions());
      expect(both.where((s) => s.he == null && text(s).startsWith('The following')), isNotEmpty);
    });
  });

  group('Birkas Kohanim inside the Amidah', () {
    late SiddurLibrary lib;
    setUpAll(() => lib = SiddurLibrary(_FileSource(), gzip.decode));

    Future<List<SegmentItem>> amidah(String title, String path, HDate hd) async {
      final book = (await lib.manifest()).book(title)!;
      final root = await lib.index(book);
      final sel = VersionSelection([for (final v in book.byLanguage('he')) await lib.version(v)], const []);
      return SiddurResolver()
          .resolve(root.find(path)!, sel, (s) => DayContext(hd, il: false, service: s),
              options: const ResolveOptions(excluded: ExcludedDisplay.dim))
          .whereType<SegmentItem>()
          .toList();
    }

    String plain(SegmentItem s) => normalizeRubric(s.he!.segment.html);
    final weekday = HDate(3, Months.cheshvan, 5787);
    final fast = HDate(3, Months.tishrei, 5787); // Tzom Gedaliah

    test("is the chazzan's, through Adir BaMarom and not Sim Shalom", () async {
      final segs = await amidah('Siddur Sefard', 'Weekday Shacharit/Amidah', weekday);
      final verse = segs.firstWhere((s) => plain(s).startsWith('יברכך'));
      expect(verse.chazarah, isTrue);
      expect(verse.applicability, Applicability.always);
      expect(segs.firstWhere((s) => plain(s).startsWith('אדיר במרום')).chazarah, isTrue);
      expect(segs.firstWhere((s) => plain(s).startsWith('שים שלום')).chazarah, isFalse);
      expect(segs.firstWhere((s) => plain(s).startsWith('מודים')).chazarah, isFalse);
    });

    test('at Mincha, all of it follows its fast-day instruction', () async {
      for (final (hd, ap) in [(weekday, Applicability.notToday), (fast, Applicability.today)]) {
        final passage = (await amidah('Siddur Sefard', 'Weekday Mincha/Amidah', hd)).where((s) => s.chazarah).toList();
        expect(passage.where((s) => s.kind == SegmentKind.prayer), hasLength(5));
        expect(passage.map((s) => s.applicability).toSet(), {ap}, reason: '$hd');
      }
    });

    test('at Mincha without an instruction, only on a fast day', () async {
      for (final (hd, ap) in [(weekday, Applicability.notToday), (fast, Applicability.today)]) {
        final passage =
            (await amidah('Weekday Siddur Sefard Linear', 'Mincha/Shemoneh Esrei', hd)).where((s) => s.chazarah && s.kind == SegmentKind.prayer);
        expect(passage, isNotEmpty);
        expect(passage.map((s) => s.applicability).toSet(), {ap}, reason: '$hd');
      }
    });
  });
}
