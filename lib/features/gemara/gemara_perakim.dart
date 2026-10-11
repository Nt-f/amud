import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/providers.dart';
import 'gemara_data.dart';

/// A perek (chapter) of a tractate: its name and where it starts and ends,
/// down to the segment.
class Perek {
  final int number;
  final String en;
  final String he;
  final String startAmud;
  final int startSegment;
  final String endAmud;
  final int endSegment;
  const Perek(this.number, this.en, this.he, this.startAmud, this.startSegment, this.endAmud, this.endSegment);

  int get startNumber => amudNumber(startAmud)!;
  int get endNumber => amudNumber(endAmud)!;

  /// Whether the perek has text on this amud.
  bool covers(String amud) {
    final n = amudNumber(amud);
    return n != null && n >= startNumber && n <= endNumber;
  }

  Map<String, Object?> toJson() =>
      {'n': number, 'en': en, 'he': he, 'sa': startAmud, 'ss': startSegment, 'ea': endAmud, 'es': endSegment};

  static Perek? fromJson(Object? o) {
    if (o is! Map) return null;
    try {
      return Perek(o['n'] as int, '${o['en']}', '${o['he']}', '${o['sa']}', o['ss'] as int, '${o['ea']}', o['es'] as int);
    } catch (_) {
      return null;
    }
  }
}

/// "Berakhot 2a:1-13a:15", "Tamid 33a:8-14", "Tamid 33b:1-12" → range.
/// Segments are 1-based in the ref and 0-based here.
({String startAmud, int startSegment, String endAmud, int endSegment})? parseWholeRef(String ref) {
  final m = RegExp(r'(\d+[ab])(?::(\d+))?-(?:(\d+[ab])(?::(\d+))?|(\d+))$').firstMatch(ref.trim());
  if (m == null) {
    final one = RegExp(r'(\d+[ab])(?::(\d+))?$').firstMatch(ref.trim());
    if (one == null) return null;
    return (startAmud: one.group(1)!, startSegment: int.parse(one.group(2) ?? '1') - 1, endAmud: one.group(1)!, endSegment: 9999);
  }
  final startAmud = m.group(1)!;
  final startSegment = int.parse(m.group(2) ?? '1') - 1;
  if (m.group(5) != null) {
    return (startAmud: startAmud, startSegment: startSegment, endAmud: startAmud, endSegment: int.parse(m.group(5)!) - 1);
  }
  return (startAmud: startAmud, startSegment: startSegment, endAmud: m.group(3)!, endSegment: int.parse(m.group(4) ?? '9999') - 1);
}

/// Perakim from Sefaria's index of a tractate (its "Chapters" structure).
List<Perek> parsePerakim(String indexJson) {
  final j = jsonDecode(indexJson) as Map<String, Object?>;
  final nodes = (((j['alt_structs'] as Map?)?['Chapters'] as Map?)?['nodes'] as List?) ?? const [];
  final out = <Perek>[];
  for (final n in nodes.cast<Map<String, Object?>>()) {
    final r = parseWholeRef('${n['wholeRef'] ?? ''}');
    if (r == null) continue;
    final titles = (n['titles'] as List? ?? const []).cast<Map<String, Object?>>();
    String title(String lang) =>
        '${titles.where((t) => t['lang'] == lang && t['primary'] == true).firstOrNull?['text'] ?? titles.where((t) => t['lang'] == lang).firstOrNull?['text'] ?? ''}';
    // "Chapter 1; MeEimatai" → "MeEimatai".
    final en = title('en').replaceFirst(RegExp(r'^Chapter \d+;\s*'), '');
    out.add(Perek(out.length + 1, en, title('he'), r.startAmud, r.startSegment, r.endAmud, r.endSegment));
  }
  return out;
}

/// A tractate's perakim: kept on the device after the first fetch. Empty
/// when they can't be had (offline on first use); callers then show the
/// tractate without them.
final perakimProvider = FutureProvider.family<List<Perek>, String>((ref, tractate) async {
  final storage = ref.read(storageProvider);
  final key = 'gemaraPerakim:$tractate';
  final saved = storage.readJson(key, (j) => [for (final p in (j as List)) ?Perek.fromJson(p)]);
  if (saved != null && saved.isNotEmpty) return saved;
  try {
    final res = await http
        .get(Uri.parse('https://www.sefaria.org/api/v2/raw/index/${Uri.encodeComponent(tractate.replaceAll(' ', '_'))}'))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return const [];
    final perakim = parsePerakim(utf8.decode(res.bodyBytes));
    if (perakim.isNotEmpty) await storage.writeJson(key, [for (final p in perakim) p.toJson()]);
    return perakim;
  } catch (_) {
    return const [];
  }
});

/// The perek that ends on this amud, if one does.
Perek? perekEndingOn(List<Perek> perakim, String amud) => perakim.where((p) => p.endAmud == amud).firstOrNull;

/// The perek a segment of an amud is in.
Perek? perekAt(List<Perek> perakim, String amud, int segment) {
  final n = amudNumber(amud);
  if (n == null) return null;
  for (final p in perakim) {
    final afterStart = n > p.startNumber || (n == p.startNumber && segment >= p.startSegment);
    final beforeEnd = n < p.endNumber || (n == p.endNumber && segment <= p.endSegment);
    if (afterStart && beforeEnd) return p;
  }
  return null;
}
