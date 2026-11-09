import 'dart:io';

import 'package:test/test.dart';

import '../tool/parity_dump.dart';

/// Compares this port against output captured from upstream @hebcal/core
/// 6.x + @hebcal/learning (tool/js_reference.mjs). Line order is ignored
/// because JS objects enumerate integer-like keys ('929') first.
/// The port deliberately leaves out modern Israeli days (see holidays.dart).
final _modern = RegExp(
    r'\| (Sigd|Yom HaAliyah|Yom HaShoah|Yom HaZikaron|Yom HaAtzma|Yom Yerushalayim|Herzl|Jabotinsky|Family Day|Ben-Gurion|Hebrew Language|Yitzhak Rabin)');

/// Days where the port corrects upstream's Hallel (halacha.dart): none on
/// Erev Chanukah or Pesach Sheni, whole on Shmini Atzeret/Simchat Torah.
/// Upstream's line for each, and the port's.
const _hallelFixes = {
  'HD 2021-4-26 14 Iyyar 5781 י״ד אִיָּיר תשפ״א T110 H1': 'HD 2021-4-26 14 Iyyar 5781 י״ד אִיָּיר תשפ״א T110 H0',
  'HD 2021-9-29 23 Tishrei 5782 כ״ג תִּשְׁרֵי תשפ״ב T000 H0': 'HD 2021-9-29 23 Tishrei 5782 כ״ג תִּשְׁרֵי תשפ״ב T000 H2',
  'HD 2024-12-25 24 Kislev 5785 כ״ד כִּסְלֵו תשפ״ה T101 H2': 'HD 2024-12-25 24 Kislev 5785 כ״ד כִּסְלֵו תשפ״ה T101 H0',
};

void main() {
  test('matches upstream JS hebcal output', () {
    final expected = File('test/fixtures/hebcal_js_reference.txt')
        .readAsLinesSync()
        .where((l) => l.isNotEmpty && !_modern.hasMatch(l))
        .map((l) => _hallelFixes[l] ?? l)
        .toList()
      ..sort();
    final actual = parityLines().where((l) => !_modern.hasMatch(l)).toList()..sort();
    final missing = expected.toSet().difference(actual.toSet());
    final extra = actual.toSet().difference(expected.toSet());
    expect(missing.take(20), isEmpty, reason: 'lines missing from Dart port');
    expect(extra.take(20), isEmpty, reason: 'unexpected lines in Dart port');
    expect(actual.length, expected.length);
  });
}
