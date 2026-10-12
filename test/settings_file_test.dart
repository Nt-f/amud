import 'dart:convert';
import 'dart:io';

import 'package:amud/core/storage.dart';
import 'package:amud/core/sync/settings_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('amud_sf'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('settings round-trip through a file; device-only fields stay put', () async {
    final a = await Storage.openAt('${dir.path}/a', name: 'a');
    await a.writeJson('settings', {'textScale': 1.4, 'location': 'here'});
    await a.writeJson('personalDates', [{'n': 1}]);
    final bytes = exportSettings(a);
    expect(utf8.decode(bytes), isNot(contains('"location"')));

    final b = await Storage.openAt('${dir.path}/b', name: 'b');
    await b.writeJson('settings', {'location': 'there'});
    final keys = await importSettings(b, bytes);
    expect(keys, containsAll(['settings', 'personalDates']));
    final s = b.readJson<Map>('settings', (j) => j as Map)!;
    expect(s['textScale'], 1.4);
    expect(s['location'], 'there');
    expect(b.readJson<Object?>('personalDates', (j) => j), [{'n': 1}]);
  });

  test('a file that is not settings is refused', () async {
    final a = await Storage.openAt('${dir.path}/c', name: 'c');
    expect(() => importSettings(a, utf8.encode('{"x":1}')), throwsFormatException);
    expect(() => importSettings(a, [0xff, 0xfe]), throwsFormatException);
  });
}
