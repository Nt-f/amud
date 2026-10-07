import 'dart:io';

import 'package:archive/archive.dart';
import 'package:amud/core/settings.dart';
import 'package:amud/features/siddur/book_kind.dart';
import 'package:amud/features/siddur/linear_reader.dart';
import 'package:amud/features/siddur/prayer_catalog.dart';
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

  test('books are told apart: nusach, Shabbat siddur, commentary', () {
    expect(bookKind('Siddur Ashkenaz'), BookKind.nusach);
    expect(bookKind('Weekday Siddur Chabad'), BookKind.nusach);
    expect(bookKind('Shabbat Siddur Sefard Linear'), BookKind.shabbat);
    expect(bookKind('Rabbi Sacks on Siddur'), BookKind.commentary);
  });

  test('commentary reads in English whatever the layout; siddurim keep the reader\'s', () {
    const s = AppSettings(layout: TextLayout.sideBySide, linearStyle: LinearStyle.facing);
    expect(readerSettings(s, 'Rabbi Sacks on Siddur').layout, TextLayout.translationOnly);
    expect(readerSettings(s, 'Rabbi Sacks on Siddur').showHebrewText, isFalse);
    expect(readerSettings(s, 'Siddur Ashkenaz').layout, TextLayout.sideBySide);
    expect(linearPageStyle(readerSettings(s, 'Rabbi Sacks on Siddur'), wide: true), LinearStyle.off);
  });

  test('prayers are looked up in Shabbat siddurim last, and never in commentary', () async {
    final m = await lib.manifest();
    final order = bookSearchOrder(m, 'Siddur Sefard');
    expect(order, isNot(contains('Rabbi Sacks on Siddur')));
    expect(order.first, 'Siddur Sefard');
    final shabbat = order.indexOf('Shabbat Siddur Sefard Linear');
    for (final b in order) {
      if (bookKind(b) == BookKind.nusach && nusachOf(b) == Nusach.sefard) expect(order.indexOf(b), lessThan(shabbat), reason: b);
    }
    // Last among the books of its own nusach, and before another nusach's Shabbat siddur.
    expect(order.last == 'Shabbat Siddur Sefard Linear' || nusachOf(order.last) != Nusach.sefard, isTrue);
  });

  test('linear style needs bilingual text; the columns give way on a narrow page', () {
    expect(linearPageStyle(const AppSettings(layout: TextLayout.hebrewOnly, linearStyle: LinearStyle.below), wide: true), LinearStyle.off);
    expect(linearPageStyle(const AppSettings(layout: TextLayout.interleaved, linearStyle: LinearStyle.facing), wide: true), LinearStyle.facing);
    expect(linearPageStyle(const AppSettings(layout: TextLayout.interleaved, linearStyle: LinearStyle.facing), wide: false), LinearStyle.below);
    expect(linearPageStyle(const AppSettings(layout: TextLayout.sideBySide), wide: true), LinearStyle.off);
    expect(AppSettings.fromJson(const AppSettings(linearStyle: LinearStyle.below).toJson()).linearStyle, LinearStyle.below);
  });

  test('the linear page groups lines of a section into blocks of a few lines', () async {
    final book = (await lib.manifest()).book('Siddur Ashkenaz')!;
    final root = await lib.index(book);
    final he = await lib.version(book.byLanguage('he').firstWhere((v) => v.versionTitle == 'The Metsudah siddur, 1981'));
    final en = await lib.version(book.byLanguage('en').firstWhere((v) => v.versionTitle == 'Sefaria Community Translation'));
    final node = root.descendants.firstWhere((n) => RegExp(r'Amidah$').hasMatch(n.id) && n.id.startsWith('Weekday/Shacharit'));
    final items = SiddurResolver().resolve(node, VersionSelection([he], [en]), (svc) => DayContext.forService(HDate(19, Months.tishrei, 5787), svc, il: false));

    var i = 0, blocks = 0, lines = 0;
    while (i < items.length) {
      final run = linearRun(items, i);
      if (run.isEmpty) {
        i++;
        continue;
      }
      expect(run.length, lessThanOrEqualTo(5));
      expect(run.every((x) => x.node == run.first.node && linearLine(x)), isTrue);
      expect([for (var k = 0; k < run.length; k++) items[i + k]], run);
      blocks++;
      lines += run.length;
      i += run.length;
    }
    expect(blocks, greaterThan(0));
    expect(lines, greaterThanOrEqualTo(blocks));

    final line = items.whereType<SegmentItem>().firstWhere(linearLine);
    expect(line.onlyHebrew().tr, isNull);
    expect(line.onlyHebrew().he, isNotNull);
    expect(line.onlyTranslation().he, isNull);
    expect(line.onlyTranslation().tr, isNotNull);
    expect(line.onlyHebrew().key, line.key);
  });
}
