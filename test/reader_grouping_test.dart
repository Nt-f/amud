import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:amud/core/settings.dart';
import 'package:amud/features/alerts/alerts.dart';
import 'package:amud/features/siddur/reader_grouping.dart';
import 'package:amud/features/zmanim/zman_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hebcal/hebcal.dart';
import 'package:siddur_engine/siddur_engine.dart';

class _FileSource implements TextSource {
  @override
  Future<List<int>> readBytes(String file) => File(file).readAsBytes();
}

void main() {
  late SiddurLibrary lib;
  setUpAll(() {
    initHebcal();
    lib = SiddurLibrary(_FileSource(), (b) => const GZipDecoder().decodeBytes(b));
  });

  Future<(SchemaNode, VersionSelection, SiddurResolver)> load(String title, List<String> he) async {
    final book = (await lib.manifest()).book(title)!;
    final root = await lib.index(book);
    final versions = [for (final t in he) await lib.version(book.byLanguage('he').firstWhere((v) => v.versionTitle == t))];
    final rules = jsonDecode(File('assets/rules/rules.json').readAsStringSync()) as Map<String, dynamic>;
    final resolver = SiddurResolver().withOverrides((rules[title] as Map<String, dynamic>?) ?? const {});
    return (root, VersionSelection(versions, const []), resolver);
  }

  test('chazaras hashatz: Kedushah, Birkas Kohanim and Modim DeRabbanan', () async {
    final (root, versions, resolver) = await load('Siddur Ashkenaz', ['The Metsudah siddur, 1981']);
    final amidah = root.find('Weekday/Shacharit/Amidah')!;
    expect(isChazarahNode(amidah.find('Weekday/Shacharit/Amidah/Kedushah')!), isTrue);
    expect(isChazarahNode(amidah.find('Weekday/Shacharit/Amidah/Birkat Kohanim')!), isTrue);
    expect(isChazarahNode(amidah.find('Weekday/Shacharit/Amidah/Holiness of God')!), isFalse);
    expect(isChazarahNode(amidah.find('Weekday/Shacharit/Amidah/Thanksgiving')!), isFalse);

    final items = resolver.resolve(amidah.find('Weekday/Shacharit/Amidah/Thanksgiving')!, versions,
        (svc) => DayContext.forService(HDate(19, Months.tishrei, 5787), svc, il: false));
    final modim = items.whereType<SegmentItem>().where(isChazarahSegment).toList();
    expect(modim, hasLength(1));
  });

  test('a season rubric line is dropped when the next line carries its label', () async {
    final (root, versions, resolver) = await load('Siddur Ashkenaz', ['The Metsudah siddur, 1981']);
    // Summer (Nisan): "בקיץ:" labels מוריד הטל.
    final items = resolver
        .resolve(root.find('Weekday/Shacharit/Amidah/Divine Might')!, versions,
            (svc) => DayContext.forService(HDate(20, Months.iyyar, 5787), svc, il: false),
            options: const ResolveOptions(excluded: ExcludedDisplay.dim))
        .whereType<SegmentItem>()
        .toList();
    final i = items.indexWhere((s) => stripHtml(s.he!.segment.html).trim() == 'בקיץ:');
    expect(i, isNonNegative);
    expect(isRedundantRubric(items[i], items[i + 1], const AppSettings()), isTrue);
  });

  test('Kadesh and Kiddush are single units', () async {
    final (root, _, _) = await load('Siddur Sefard', ['The Metsudah siddur, 1981']);
    expect(isUnitNode(root.find('Pesach Haggadah/Kadesh')!), isTrue);
    expect(isUnitNode(root.find('Holidays/Yom Tov Eve Kiddush')!), isTrue);
    expect(isUnitNode(root.find('Kiddush Levanah')!), isFalse);
    expect(kaddishUnit('kaddish.half')?.$1, 'Half Kaddish');
    expect(kaddishUnit('kaddish.unknown')?.$1, 'Kaddish');
    expect(kaddishUnit('mincha.ashrei'), isNull);
    expect(kaddishUnit(null), isNull);
  });

  test('notification ids are stable per alert and day', () {
    final loc = Location(40.71427, -74.00597, false, 'America/New_York', cityName: 'NY', countryCode: 'US');
    List<PlannedNotification> plan(DateTime now) => planNotifications(
          alerts: const [
            ZmanAlert(id: 'a', title: 'Shkiah', zmanKey: 'sunset', offsetMinutes: -15),
            ZmanAlert(id: 'b', title: 'Shkiah', zmanKey: 'sunset', offsetMinutes: -15),
          ],
          location: loc,
          zmanim: ZmanResolver(const []),
          settings: const AppSettings(),
          now: now,
          days: 3,
        );
    final first = plan(DateTime.utc(2026, 9, 29, 12));
    // Identical alerts collapse into one notification per day.
    expect(first, hasLength(3));
    // Re-planning later keeps the same id for the same notification.
    final later = plan(DateTime.utc(2026, 9, 29, 13));
    expect(later.map((p) => p.id), first.map((p) => p.id));
    expect(first.map((p) => p.id).toSet(), hasLength(3));
  });

  test('settings saved before v2 adopt the new defaults', () {
    final s = AppSettings.fromJson({'ashkenaziSpelling': false, 'hebrewFont': 'FrankRuhlLibre', 'showNotes': false, 'themeMode': 'sepia'});
    expect(s.ashkenaziSpelling, isTrue);
    expect(s.hebrewFont, 'TaameyFrankCLM');
    expect(s.showNotes, isTrue);
    expect(s.themeMode, AppThemeMode.light);
    expect(s.warmth, greaterThan(0));
    // Choices made since are kept.
    final v2 = AppSettings.fromJson({...const AppSettings(ashkenaziSpelling: false).toJson()});
    expect(v2.ashkenaziSpelling, isFalse);
  });
}
