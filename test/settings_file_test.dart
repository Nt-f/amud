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

  test('progress goes in a file only when included, and importing adds it to what is there', () async {
    final a = await Storage.openAt('${dir.path}/d', name: 'd');
    await a.writeJson('gemaraMarks', {'completed': ['Berakhot:2a'], 'bookmarks': []});
    await a.writeJson('tehillim', {'read': [1]});
    expect(utf8.decode(exportSettings(a, groups: {'tehillim'})), isNot(contains('gemaraMarks')));
    final bytes = exportSettings(a);

    final b = await Storage.openAt('${dir.path}/e', name: 'e');
    await b.writeJson('gemaraMarks', {'completed': ['Shabbat:2a']});
    await b.writeJson('tehillim', {'read': [9]});
    final keys = await importSettings(b, bytes, groups: {'learning'});
    expect(keys, contains('gemaraMarks'));
    expect(keys, isNot(contains('tehillim')));
    expect(b.readJson('gemaraMarks', (j) => (j as Map)['completed']), ['Berakhot:2a', 'Shabbat:2a']);
    expect(b.readJson('tehillim', (j) => (j as Map)['read']), [9]);
  });

  test('a file that is not settings is refused', () async {
    final a = await Storage.openAt('${dir.path}/c', name: 'c');
    expect(() => importSettings(a, utf8.encode('{"x":1}')), throwsFormatException);
    expect(() => importSettings(a, [0xff, 0xfe]), throwsFormatException);
  });
}
