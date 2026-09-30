import 'dart:io';

import 'package:amud/core/font_formats.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tag → table bytes, from an sfnt (TrueType/OpenType) file.
Map<String, List<int>> tables(Uint8List f) {
  final r = ByteData.sublistView(f);
  return {
    for (var i = 0; i < r.getUint16(4); i++)
      String.fromCharCodes(f.sublist(12 + i * 16, 16 + i * 16)):
          f.sublist(r.getUint32(12 + i * 16 + 8), r.getUint32(12 + i * 16 + 8) + r.getUint32(12 + i * 16 + 12)),
  };
}

void main() {
  final ttf = File('assets/fonts/Fraunces-Amud.ttf').readAsBytesSync();

  test('TrueType and OpenType load as they are', () {
    expect(toLoadableFont(ttf), same(ttf));
  });

  test('WOFF unpacks to the same tables as the TrueType font', () {
    final out = toLoadableFont(File('test/fixtures/fraunces_amud.woff').readAsBytesSync());
    expect(out.sublist(0, 4), ttf.sublist(0, 4));
    // Every table matches, except what the WOFF encoder restamped in head:
    // the whole-font checksum (bytes 8–11) and the modified date (28–35).
    Map<String, List<int>> comparable(Uint8List f) => tables(f)
        .map((tag, t) => MapEntry(tag, tag == 'head' ? [...t.sublist(0, 8), ...t.sublist(12, 28), ...t.sublist(36)] : t));
    expect(comparable(out), comparable(ttf));
  });

  testWidgets('an unpacked WOFF registers with the engine', (t) async {
    final font = toLoadableFont(File('test/fixtures/fraunces_amud.woff').readAsBytesSync());
    await t.runAsync(() => (FontLoader('woff_test')..addFont(Future.value(ByteData.sublistView(font)))).load());
  });

  test('WOFF2 and other files are refused with a reason', () {
    expect(() => toLoadableFont(File('test/fixtures/fraunces_amud.woff2').readAsBytesSync()),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('WOFF2'))));
    expect(() => toLoadableFont('not a font at all'.codeUnits), throwsFormatException);
  });

  test('font names drop the extension', () {
    expect(fontNameFromFile('Frank Ruhl.WOFF'), 'Frank Ruhl');
    expect(fontNameFromFile('David.ttc'), 'David');
  });
}
