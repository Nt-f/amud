import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/content.dart';
import 'gemara_settings.dart';

/// The word-by-word layer of one amud, from the interlinear server
/// (the content site's interlinear bundles, schema 1; see fetchInterlinearWork).
///
/// Each segment has the source words, an English gloss per word, and for
/// each word the index of the literal phrase (a `lit` run) it belongs to.
/// The runs themselves are the segment's English split into literal
/// translation, filler and explanation, the same split the app makes from
/// the Davidson English.
class InterlinearUnit {
  final String unit;
  final List<InterlinearSegment> segments;
  final String? model;
  const InterlinearUnit(this.unit, this.segments, {this.model});

  InterlinearSegment? at(int i) => i < segments.length ? segments[i] : null;

  factory InterlinearUnit.fromJson(Map<String, Object?> j) {
    // A stored envelope (what the precompute CLI writes) wraps the body.
    final body = j['parsed'] is Map ? (j['parsed'] as Map).cast<String, Object?>() : j;
    final meta = body['meta'] is Map ? (body['meta'] as Map).cast<String, Object?>() : const <String, Object?>{};
    return InterlinearUnit(
      '${body['unit'] ?? ''}',
      [for (final s in (body['segments'] as List? ?? const [])) InterlinearSegment.fromJson((s as Map).cast<String, Object?>())],
      model: (meta['model'] ?? j['model'])?.toString(),
    );
  }

  Map<String, Object?> toJson() => {
        'unit': unit,
        'segments': [for (final s in segments) s.toJson()],
        if (model != null) 'meta': {'model': model},
      };
}

class InterlinearSegment {
  final List<String> tokens;
  final List<String> glosses;
  final List<int> links;
  final List<(String, String)> runs;
  final bool ok;
  const InterlinearSegment({required this.tokens, required this.glosses, required this.links, required this.runs, required this.ok});

  bool get hasWords => ok && glosses.length == tokens.length && tokens.isNotEmpty;

  String? glossAt(int i) => hasWords && i < glosses.length ? glosses[i] : null;
  int linkAt(int i) => i < links.length ? links[i] : -1;

  factory InterlinearSegment.fromJson(Map<String, Object?> j) => InterlinearSegment(
        tokens: [for (final t in (j['tokens'] as List? ?? const [])) '$t'],
        glosses: [for (final g in (j['glosses'] as List? ?? const [])) '$g'],
        links: [for (final l in (j['links'] as List? ?? const [])) l is int ? l : -1],
        runs: [
          for (final r in (j['runs'] as List? ?? const []))
            if (r is Map) ('${r['t']}', '${r['text']}'),
        ],
        ok: j['status'] == 'ok',
      );

  Map<String, Object?> toJson() => {
        'tokens': tokens,
        'glosses': glosses,
        'links': links,
        'runs': [for (final (t, text) in runs) {'t': t, 'text': text}],
        'status': ok ? 'ok' : 'failed',
      };
}

/// A whole work's word-by-word layer (a tractate, a masechta of Mishnah),
/// with the hash of the bundle it came from; null when the server has none.
/// The server is the content site (text.amud.page): its index names each
/// work's bundle.
Future<({List<InterlinearUnit> units, String sha})?> fetchInterlinearWork(http.Client client, String server, String spine, String book) async {
  if (server.trim().isEmpty) return null;
  final index = await fetchInterlinearIndex(client, server);
  final entry = index?['$spine/$book'];
  if (entry == null) return null;
  final base = server.trim().replaceAll(RegExp(r'/+$'), '');
  final res = await client.get(Uri.parse('$base/interlinear/v1/${entry['path']}')).timeout(const Duration(minutes: 2));
  if (res.statusCode != 200) return null;
  final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, Object?>;
  return (
    units: [for (final u in (j['units'] as List? ?? const [])) InterlinearUnit.fromJson((u as Map).cast<String, Object?>())],
    sha: '${entry['sha256']}',
  );
}

final interlinearServerProvider = Provider<String>((ref) => ref.watch(gemaraSettingsProvider.select((s) => s.interlinearServer)));
