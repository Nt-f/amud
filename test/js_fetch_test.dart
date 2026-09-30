import 'package:amud/features/js_cards/js_fetch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  var calls = 0;
  JsFetcher fetcher({String body = '{"a":1}', int status = 200}) => JsFetcher(
      client: () => MockClient((req) async {
            calls++;
            return http.Response(body, status, headers: {'content-type': 'application/json'}, request: req);
          }));
  Map<String, Object?> req(String url, {String method = 'GET', Object? id = '1'}) => {'type': 'fetch', 'id': id, 'url': url, 'method': method};

  setUp(() => calls = 0);

  test('returns status, headers and body for the script', () async {
    final r = await fetcher().fetch(req('https://example.com/a'));
    expect(r['id'], '1');
    expect(r['status'], 200);
    expect(r['body'], '{"a":1}');
    expect((r['headers'] as Map)['content-type'], 'application/json');
  });

  test('only https', () async {
    expect((await fetcher().fetch(req('http://example.com')))['error'], contains('https'));
    expect((await fetcher().fetch(req('file:///etc/passwd')))['error'], contains('https'));
  });

  test('at most ${JsFetcher.maxRequests} requests per update', () async {
    final f = fetcher();
    for (var i = 0; i < JsFetcher.maxRequests; i++) {
      expect((await f.fetch(req('https://example.com/n$i')))['error'], isNull);
    }
    expect((await f.fetch(req('https://example.com/more')))['error'], contains('Too many'));
  });

  test('GETs are cached across updates; other methods are not', () async {
    await fetcher().fetch(req('https://example.com/cached'));
    final again = await fetcher().fetch(req('https://example.com/cached', id: '7'));
    expect(calls, 1);
    expect(again['id'], '7');
    await fetcher().fetch(req('https://example.com/cached', method: 'POST'));
    await fetcher().fetch(req('https://example.com/cached', method: 'POST'));
    expect(calls, 3);
  });

  test('refuses huge responses and unknown methods', () async {
    final big = await fetcher(body: 'x' * (JsFetcher.maxBytes + 1)).fetch(req('https://example.com/big'));
    expect(big['error'], contains('too large'));
    expect((await fetcher().fetch(req('https://example.com', method: 'CONNECT')))['error'], contains('Unsupported'));
  });
}
