import 'dart:io';
import 'dart:convert';
import 'package:amud/core/settings.dart';
import 'package:amud/features/siddur/prayer_catalog.dart';
import 'package:amud/features/siddur/today_plan.dart';
import 'package:amud/features/siddur/day_explanations.dart';
import 'package:amud/features/siddur/prayer_insights.dart';
import 'package:amud/features/siddur/siddur_print.dart';
import 'package:amud/features/siddur/today_summary.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hebcal/hebcal.dart';
import 'package:siddur_engine/siddur_engine.dart';

class _Files implements TextSource {
  @override
  Future<List<int>> readBytes(String file) => File(file).readAsBytes();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initHebcal);

  test('tomorrow evening observes the following Hebrew date', () {
    final date = HDate(24, Months.kislev, 5786);
    final day = DayContext.forService(date, Service.shacharit, il: false);
    final night = DayContext.forService(date, Service.maariv, il: false);
    expect(day['chanukah'], isFalse);
    expect(night['chanukah'], isTrue);
    expect(night.hdate.abs(), date.abs() + 1);
    final omerDate = HDate(15, Months.nisan, 5786);
    final omerDay = DayContext.forService(
      omerDate,
      Service.shacharit,
      il: false,
    );
    final omerMincha = DayContext.forService(
      omerDate,
      Service.mincha,
      il: false,
    );
    final omerNight = DayContext.forService(
      omerDate,
      Service.maariv,
      il: false,
    );
    final change = summarizeDay(
      omerDay,
      omerMincha,
      omerNight,
    ).firstWhere((c) => c.en.contains('Omer'));
    expect(
      explainDayChange(change, omerDay, omerMincha, omerNight),
      contains('day 1'),
    );
  });

  test('custom omissions and unknown rules have truthful explanations', () {
    final day = DayContext(
      HDate(5, Months.cheshvan, 5786),
      il: false,
      minhagim: const Minhagim(bris: true),
    );
    final changes = summarizeDay(day, day, day);
    final omit = changes.firstWhere((c) => c.en.contains('Tachanun'));
    expect(explainDayChange(omit, day, day, day), contains('bris'));
    expect(
      conditionFacts('roshChodesh || myCustomFlag', day),
      contains('myCustomFlag: Unknown'),
    );
  });

  test(
    'PDF filters date-dependent text, embeds fonts and preserves sources',
    () async {
      final library = SiddurLibrary(_Files(), gzip.decode);
      final manifest = await library.manifest();
      final book = manifest.book('Siddur Ashkenaz')!;
      final root = await library.index(book);
      final version = book.versions.firstWhere(
        (v) => v.versionTitle == 'The Metsudah siddur, 1981',
      );
      final versions = VersionSelection([await library.version(version)], []);
      final node = root.find('Weekday/Shacharit/Amidah/Temple Service')!;
      List<RenderItem> render(HDate date) => SiddurResolver().resolve(
        node,
        versions,
        (service) => DayContext.forService(date, service, il: false),
        options: const ResolveOptions(
          excluded: ExcludedDisplay.hide,
          showTranslation: false,
        ),
      );
      final date = HDate(1, Months.cheshvan, 5786);
      final festival = render(date);
      final ordinary = render(HDate(5, Months.cheshvan, 5786));
      expect(
        festival
            .whereType<SegmentItem>()
            .map((i) => normalizeRubric(resolvedText(i.he)))
            .join(' '),
        contains('יעלה'),
      );
      expect(
        ordinary
            .whereType<SegmentItem>()
            .map((i) => normalizeRubric(resolvedText(i.he)))
            .join(' '),
        isNot(contains('יעלה')),
      );
      final he = await rootBundle.load('assets/fonts/NotoSerifHebrew.ttf');
      final en = await rootBundle.load('assets/fonts/FrankRuhlLibre.ttf');
      final bytes = await createSiddurPdf(
        date: date,
        book: book.title,
        sections: [PrintSection('Shacharit', festival)],
        sources: [version],
        hebrewFont: he,
        latinFont: en,
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(10000));
      await File('/tmp/amud-siddur-preview.pdf').writeAsBytes(bytes);
    },
  );

  test(
    'complete selected services produce a multi-page PDF without duplicate insertions',
    () async {
      final library = SiddurLibrary(_Files(), gzip.decode);
      final manifest = await library.manifest();
      final rules =
          jsonDecode(await File('assets/rules/rules.json').readAsString())
              as Map<String, dynamic>;
      final books = <PlanBook>[];
      final versions = <String, VersionSelection>{};
      for (final title in bookSearchOrder(manifest, 'Siddur Ashkenaz')) {
        final book = manifest.book(title)!;
        books.add(
          PlanBook(
            title,
            await library.index(book),
            SiddurResolver().withOverrides(
              (rules[title] as Map<String, dynamic>?) ?? {},
            ),
          ),
        );
        final defaults =
            ((rules[title] as Map?)?['defaultVersions'] as Map?)?['he']
                as List?;
        versions[title] = VersionSelection([
          for (final v in book.byLanguage('he'))
            if (defaults == null || defaults.contains(v.versionTitle))
              await library.version(v),
        ], []);
      }
      final date = HDate(1, Months.cheshvan, 5786);
      final plan = buildTodayPlan(
        books: books,
        contexts: (service) => DayContext.forService(date, service, il: false),
        lookup: (key) {
          for (final book in books) {
            final node = findByPatterns(book.root, catalogItem(key)!.patterns);
            if (node != null && hasText(versions[book.title]!, node)) {
              return PrayerRef(book.title, node);
            }
          }
          return null;
        },
      );
      final prepared = await preparePrintSections(
        plan: plan,
        date: date,
        settings: const AppSettings(),
        selected: {'shacharit'},
        hebrew: true,
        translation: false,
        resolverFor: (title) async =>
            books.firstWhere((b) => b.title == title).resolver,
        versionsFor: (title) async => versions[title]!,
      );
      expect(prepared.sections.length, 1);
      final items = prepared.sections.single.items;
      expect(items.map((i) => i.key).toSet().length, items.length);
      expect(items.whereType<SegmentItem>().where((i) => i.excluded), isEmpty);
      expect(prepared.sources, isNotEmpty);
      final bytes = await createSiddurPdf(
        date: date,
        book: plan.book,
        sections: prepared.sections,
        sources: prepared.sources,
        hebrewFont: await rootBundle.load('assets/fonts/NotoSerifHebrew.ttf'),
        latinFont: await rootBundle.load('assets/fonts/FrankRuhlLibre.ttf'),
      );
      await File('/tmp/amud-full-siddur.pdf').writeAsBytes(bytes);
      expect(bytes.length, greaterThan(50000));
    },
  );

  test('curated Shema source matches the selected line', () {
    final root = SchemaNode.parse({
      'title': 'Test',
      'nodes': [
        {'title': 'Shema'},
      ],
    });
    final segment = Segment(
      ref: '1',
      html: 'שְׁמַע יִשְׂרָאֵל',
      hebrew: true,
      kind: SegmentKind.prayer,
      runs: [TextRun('שְׁמַע יִשְׂרָאֵל', RunKind.text)],
    );
    final item = SegmentItem(
      's',
      root.children.first,
      ResolvedSegment(segment, [
        ResolvedRun(segment.html, false, Applicability.always, null, null),
      ]),
      null,
      SegmentKind.prayer,
      Applicability.always,
      null,
      null,
      false,
    );
    expect(insightFor(item)?.source, 'Deuteronomy 6:4');
    expect(vocabularyFor(segment.html), containsPair('שמע', 'Hear; listen'));
    expect(vocabularyFor(segment.html).containsKey('נסים'), isFalse);
  });
}
