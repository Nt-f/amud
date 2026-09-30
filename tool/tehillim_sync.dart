// Downloads Sefer Tehillim from Sefaria for offline bundling.
//
//   dart run tool/tehillim_sync.dart
//
// Output: assets/tehillim/tehillim.json.gz with the Hebrew (Miqra according
// to the Masorah: nikud, te'amim, ketiv/qere; CC-BY-SA) and English (JPS
// 1917; public domain) texts, each as 150 chapters of verse HTML, plus
// their titles, licenses and sources for attribution.
import 'dart:convert';
import 'dart:io';

const _versions = {
  'he': 'Miqra according to the Masorah',
  'en': 'The Holy Scriptures: A New Translation (JPS 1917)',
};

Future<void> main() async {
  final client = HttpClient()..userAgent = 'flutter_siddur-sync/1.0';
  final out = <String, Object?>{};
  for (final MapEntry(key: lang, value: title) in _versions.entries) {
    final lang3 = lang == 'he' ? 'hebrew' : 'english';
    final uri = Uri.parse('https://www.sefaria.org/api/v3/texts/Psalms?version=${Uri.encodeQueryComponent('$lang3|$title')}');
    final req = await client.getUrl(uri);
    final res = await req.close();
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}', uri: uri);
    final j = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
    final v = (j['versions'] as List).cast<Map<String, dynamic>>().single;
    final chapters = (v['text'] as List).map((c) => (c as List).cast<String>()).toList();
    if (chapters.length != 150) throw StateError('$title: expected 150 chapters, got ${chapters.length}');
    out[lang] = chapters;
    out['${lang}Version'] = {'title': v['versionTitle'], 'license': v['license'], 'source': v['versionSource']};
    stdout.writeln('$lang: ${v['versionTitle']} (${v['license']}), ${chapters.fold<int>(0, (n, c) => n + c.length)} verses');
  }
  client.close();
  final file = File('assets/tehillim/tehillim.json.gz')..parent.createSync(recursive: true);
  file.writeAsBytesSync(gzip.encode(utf8.encode(jsonEncode(out))));
  stdout.writeln('Wrote ${file.path} (${file.lengthSync() ~/ 1024} KB)');
}
