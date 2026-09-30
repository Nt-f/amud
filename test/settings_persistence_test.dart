import 'dart:io';

import 'package:amud/core/l10n.dart';
import 'package:amud/core/settings.dart';
import 'package:amud/core/storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a damaged value falls back alone; the other settings survive', () {
    final saved = {
      ...const AppSettings(uiLanguage: UiLanguage.he, setupDone: true, textScale: 1.4, hebrewFont: 'user_123').toJson(),
      'location': {'name': 'Somewhere', 'lat': 'not a number'},
      'hour12': 'yes',
      'hebrewVersions': {'Siddur Ashkenaz': 'not a list'},
      'learningSchedules': ['dafYomi', 7],
      'minhagim': 'bad',
    };
    final s = AppSettings.fromJson(saved);
    expect(s.setupDone, isTrue);
    expect(s.uiLanguage, UiLanguage.he);
    expect(s.textScale, 1.4);
    expect(s.hebrewFont, 'user_123');
    expect(s.location.name, const AppSettings().location.name);
    expect(s.hour12, isNull);
    expect(s.learningSchedules, ['dafYomi']);
  });

  test('settings round-trip through storage', () async {
    final dir = await Directory.systemTemp.createTemp('settings');
    addTearDown(() => dir.delete(recursive: true));
    final storage = await Storage.openAt(dir.path);
    const s = AppSettings(uiLanguage: UiLanguage.yi, setupDone: true, hebrewFont: 'gf_Frank', textScale: 1.2);
    await storage.writeJson('settings', s.toJson());
    final back = storage.readJson('settings', (j) => AppSettings.fromJson((j as Map).cast<String, Object?>()))!;
    expect(back.toJson(), s.toJson());
  });

  test('unreadable data is kept aside rather than lost', () async {
    final dir = await Directory.systemTemp.createTemp('settings');
    addTearDown(() => dir.delete(recursive: true));
    final storage = await Storage.openAt(dir.path);
    await storage.writeJson('thing', {'a': 1});
    expect(storage.readJson('thing', (j) => throw const FormatException()), isNull);
    expect(storage.readJson('thing.unreadable', (j) => j), {'a': 1});
  });
}
