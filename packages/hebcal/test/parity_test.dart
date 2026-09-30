import 'dart:io';

import 'package:test/test.dart';

import '../tool/parity_dump.dart';

/// Compares this port against output captured from upstream @hebcal/core
/// 6.x + @hebcal/learning (tool/js_reference.mjs). Line order is ignored
/// because JS objects enumerate integer-like keys ('929') first.
void main() {
  test('matches upstream JS hebcal output', () {
    final expected = File('test/fixtures/hebcal_js_reference.txt')
        .readAsLinesSync()
        .where((l) => l.isNotEmpty)
        .toList()
      ..sort();
    final actual = parityLines()..sort();
    final missing = expected.toSet().difference(actual.toSet());
    final extra = actual.toSet().difference(expected.toSet());
    expect(missing.take(20), isEmpty, reason: 'lines missing from Dart port');
    expect(extra.take(20), isEmpty, reason: 'unexpected lines in Dart port');
    expect(actual.length, expected.length);
  });
}
