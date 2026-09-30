import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Font files the app can import, by extension.
const importableFontExtensions = ['ttf', 'otf', 'ttc', 'otc', 'woff'];

/// The file name without a font extension ("Frank.woff" → "Frank").
String fontNameFromFile(String fileName) =>
    fileName.replaceAll(RegExp(r'\.(ttf|otf|ttc|otc|woff2?)$', caseSensitive: false), '');

/// Returns [bytes] as a font the engine can load: TrueType, OpenType and
/// collections as they are, WOFF unpacked to the TrueType/OpenType font it
/// wraps. Throws a [FormatException] for anything else.
Uint8List toLoadableFont(List<int> bytes) {
  final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  if (data.length < 12) throw const FormatException('Not a font file');
  final sig = String.fromCharCodes(data.sublist(0, 4));
  final trueType = data[0] == 0 && data[1] == 1 && data[2] == 0 && data[3] == 0;
  if (trueType || sig == 'OTTO' || sig == 'true' || sig == 'ttcf') return data;
  if (sig == 'wOFF') return _unwoff(data);
  if (sig == 'wOF2') {
    throw const FormatException("WOFF2 fonts can't be imported yet. Use the font's .ttf or .otf file instead.");
  }
  throw const FormatException('Only TrueType (.ttf), OpenType (.otf), font collections (.ttc) and WOFF (.woff) fonts are supported');
}

/// WOFF 1.0 → sfnt: each table is zlib-compressed (or stored) behind a
/// WOFF header; rebuild the plain table directory around the tables.
Uint8List _unwoff(Uint8List w) {
  final r = ByteData.sublistView(w);
  final flavor = r.getUint32(4);
  final numTables = r.getUint16(12);
  if (44 + numTables * 20 > w.length) throw const FormatException('Damaged WOFF font');

  final tables = <({int tag, int checksum, Uint8List data})>[];
  for (var i = 0; i < numTables; i++) {
    final e = 44 + i * 20;
    final tag = r.getUint32(e);
    final offset = r.getUint32(e + 4);
    final compLength = r.getUint32(e + 8);
    final origLength = r.getUint32(e + 12);
    final checksum = r.getUint32(e + 16);
    if (offset + compLength > w.length) throw const FormatException('Damaged WOFF font');
    final raw = w.sublist(offset, offset + compLength);
    final table = compLength < origLength ? ZLibDecoder().decodeBytes(raw) : raw;
    if (table.length != origLength) throw const FormatException('Damaged WOFF font');
    tables.add((tag: tag, checksum: checksum, data: Uint8List.fromList(table)));
  }
  // Tables in tag order, as the sfnt directory requires.
  tables.sort((a, b) => a.tag.compareTo(b.tag));

  var pow2 = 1, log2 = 0;
  while (pow2 * 2 <= numTables) {
    pow2 *= 2;
    log2++;
  }
  final headerSize = 12 + 16 * numTables;
  final size = headerSize + tables.fold<int>(0, (n, t) => n + ((t.data.length + 3) & ~3));
  final out = Uint8List(size);
  final o = ByteData.sublistView(out);
  o
    ..setUint32(0, flavor)
    ..setUint16(4, numTables)
    ..setUint16(6, pow2 * 16)
    ..setUint16(8, log2)
    ..setUint16(10, numTables * 16 - pow2 * 16);
  var at = headerSize;
  for (final (i, t) in tables.indexed) {
    final rec = 12 + i * 16;
    o
      ..setUint32(rec, t.tag)
      ..setUint32(rec + 4, t.checksum)
      ..setUint32(rec + 8, at)
      ..setUint32(rec + 12, t.data.length);
    out.setRange(at, at + t.data.length, t.data);
    at += (t.data.length + 3) & ~3;
  }
  return out;
}
