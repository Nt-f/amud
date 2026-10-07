import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:amud/core/settings.dart';
import 'package:amud/core/storage.dart';
import 'package:amud/core/sync/sync_codec.dart';
import 'package:amud/core/sync/sync_doc.dart';
import 'package:amud/core/sync/sync_engine.dart';
import 'package:amud/core/sync/sync_registry.dart';
import 'package:amud/core/sync/sync_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// An in-memory mailbox with the Worker's rules (revisions, If-Match).
class FakeMailbox implements SyncTransport {
  String? blob;
  int rev = 0;
  int pushes = 0;

  /// Runs once before the next push is judged: another device writing first.
  Future<void> Function()? beforePush;

  @override
  Future<RemoteBlob?> pull() async => blob == null ? null : RemoteBlob(rev, blob);

  @override
  Future<PushResult> push(String b, int ifRev) async {
    final hook = beforePush;
    beforePush = null;
    if (hook != null) await hook();
    if (ifRev != rev) return PushResult.conflict(RemoteBlob(rev, blob));
    blob = b;
    rev++;
    pushes++;
    return PushResult.ok(rev);
  }

  @override
  Future<void> deleteAll() async {
    blob = null;
    rev = 0;
  }
}

class Device {
  Device(this.storage, this.mailbox, this.keys, String id, this.clock) : state = SyncState(deviceId: id);

  final Storage storage;
  final FakeMailbox mailbox;
  final SyncKeys keys;
  final SyncState state;
  final int Function() clock;

  SyncEngine get engine => SyncEngine(storage: storage, transport: mailbox, keys: keys, state: state, now: clock);
  Future<SyncOutcome> sync() => engine.sync();

  Map<String, Object?>? get settings => storage.readJson('settings', (j) => (j as Map).cast<String, Object?>());
  void set(Map<String, Object?> fields) {
    final cur = settings ?? const AppSettings().toJson();
    storage.writeJson('settings', {...cur, ...fields});
  }
}

void main() {
  late Directory tmp;
  var n = 0;
  var time = 1000;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sync');
    time = 1000;
  });
  tearDown(() => tmp.delete(recursive: true));

  Future<Storage> open() async => Storage.openAt(tmp.path, name: '${n++}');
  Future<Device> device(String id, FakeMailbox m, SyncKeys k) async => Device(await open(), m, k, id, () => time += 10);

  test('every AppSettings field is either synced or kept on the device', () {
    final all = const AppSettings().toJson().keys.toSet();
    expect(syncedSettingsFields.intersection(localSettingsFields), isEmpty);
    expect({...syncedSettingsFields, ...localSettingsFields}, all,
        reason: 'a new setting must be added to syncedSettingsFields or localSettingsFields in sync_registry.dart');
  });

  group('codec', () {
    test('seal and open round-trip; a wrong key or a tampered blob is refused', () async {
      final a = await SyncKeys.derive(SyncKeys.newSecret());
      final b = await SyncKeys.derive(SyncKeys.newSecret());
      final blob = await a.seal(utf8.encode('{"x":1}'));
      expect(utf8.decode(await a.open(blob)), '{"x":1}');
      expect(a.mailboxId, hasLength(32));
      expect(a.mailboxId, isNot(b.mailboxId));
      await expectLater(b.open(blob), throwsA(isA<SyncKeyError>()));
      final bytes = base64.decode(blob)..[20] ^= 1;
      await expectLater(a.open(base64.encode(bytes)), throwsA(isA<SyncKeyError>()));
      await expectLater(a.open('not base64!'), throwsA(isA<SyncKeyError>()));
    });

    test('the same secret derives the same ids; the ciphertext never repeats', () async {
      final s = SyncKeys.newSecret();
      final a = await SyncKeys.derive(s), b = await SyncKeys.derive(Uint8List.fromList(s));
      expect(a.mailboxId, b.mailboxId);
      expect(a.token, b.token);
      expect(await a.seal([1, 2, 3]), isNot(await a.seal([1, 2, 3])));
      expect(utf8.decode(utf8.encode(a.token)), isNot(contains(a.mailboxId)));
    });

    test('pairing codes round-trip, with and without a custom Worker', () {
      final s = SyncKeys.newSecret();
      final plain = PairingCode.parse(PairingCode(s).toString())!;
      expect(plain.secret, s);
      expect(plain.workerUrl, isNull);
      final custom = PairingCode.parse(PairingCode(s, 'https://sync.example.com').toString())!;
      expect(custom.workerUrl, 'https://sync.example.com');
      expect(PairingCode.parse('  ${PairingCode(s)}\n')!.secret, s);
      expect(PairingCode.parse('hello'), isNull);
      expect(PairingCode.parse('amud1:short'), isNull);
      expect(PairingCode.parse('${PairingCode(s)}@http://evil.example'), isNull);
    });

    test('Worker URLs are normalised; plain http only for localhost', () {
      expect(normalizeWorkerUrl('sync.example.com/'), 'https://sync.example.com');
      expect(normalizeWorkerUrl(' https://a.b.workers.dev// '), 'https://a.b.workers.dev');
      expect(normalizeWorkerUrl('http://localhost:8787'), 'http://localhost:8787');
      expect(normalizeWorkerUrl('http://example.com'), isNull);
      expect(normalizeWorkerUrl(''), isNull);
      expect(normalizeWorkerUrl('https://a.com?x=1'), isNull);
    });
  });

  group('document', () {
    SyncDoc doc(Map<String, (int, String, Object?)> m) => SyncDoc({for (final e in m.entries) e.key: SyncEntry(e.value.$1, e.value.$2, e.value.$3)});

    test('merge is commutative, associative and idempotent', () {
      final a = doc({'x': (5, 'a', 1), 'y': (1, 'a', 'old')});
      final b = doc({'x': (6, 'b', 2), 'z': (3, 'b', 3)});
      final c = doc({'y': (9, 'c', 'new'), 'x': (6, 'c', 4)});
      SyncDoc merged(List<SyncDoc> ds) => ds.fold(SyncDoc(), (acc, d) => acc..mergeIn(d));
      final ab = merged([a, b, c]);
      expect(merged([c, b, a]).sameAs(ab), isTrue);
      expect(merged([b, c, a]).sameAs(ab), isTrue);
      expect(merged([a, a, b, b, c]).sameAs(ab), isTrue);
      expect(ab.entries['x']!.v, 4, reason: 'equal times: the larger device id wins');
      expect(ab.entries['y']!.v, 'new');
    });

    test('decoding skips entries it cannot read and rejects foreign documents', () {
      final d = SyncDoc.decode(utf8.encode(jsonEncode({
        'a': 'amud-sync',
        's': 99,
        'e': {'ok': {'t': 1, 'd': 'a', 'v': 1}, 'bad': {'t': 'x'}, 'worse': 5}
      })));
      expect(d.entries.keys, ['ok']);
      expect(() => SyncDoc.decode(utf8.encode('{"a":"other"}')), throwsFormatException);
    });

    test('equal values compare equal however the maps were built', () {
      expect(canon({'a': 1, 'b': {'x': 1, 'y': 2}}), canon({'b': {'y': 2, 'x': 1}, 'a': 1}));
    });
  });

  group('two devices', () {
    test('a change on one reaches the other, field by field', () async {
      final keys = await SyncKeys.derive(SyncKeys.newSecret());
      final m = FakeMailbox();
      final a = await device('a', m, keys), b = await device('b', m, keys);
      a.set({'themeMode': 'dark', 'showNikud': false});
      await a.sync();
      await b.sync();
      expect(b.settings!['themeMode'], 'dark');
      expect(b.settings!['showNikud'], false);

      // Different fields changed on each device at once: both survive.
      a.set({'textScale': 1.5});
      b.set({'warmth': 0.7});
      await a.sync();
      await b.sync();
      await a.sync();
      for (final d in [a, b]) {
        expect(d.settings!['textScale'], 1.5);
        expect(d.settings!['warmth'], 0.7);
        expect(d.settings!['themeMode'], 'dark');
      }
    });

    test('the later change wins when both change one field', () async {
      final keys = await SyncKeys.derive(SyncKeys.newSecret());
      final m = FakeMailbox();
      final a = await device('a', m, keys), b = await device('b', m, keys);
      a.set({'layout': 'columns'});
      await a.sync();
      await b.sync();
      a.set({'textScale': 1.2});
      await a.sync();
      b.set({'textScale': 1.8}); // later in time
      await b.sync();
      await a.sync();
      expect(a.settings!['textScale'], 1.8);
      expect(b.settings!['textScale'], 1.8);
    });

    test('a device that never changed a value does not undo another\'s choice', () async {
      final keys = await SyncKeys.derive(SyncKeys.newSecret());
      final m = FakeMailbox();
      final a = await device('a', m, keys);
      a.set({'themeMode': 'dark'});
      await a.sync();
      final fresh = await device('z', m, keys); // untouched install joins later
      await fresh.sync();
      await a.sync();
      expect(fresh.settings!['themeMode'], 'dark');
      expect(a.settings!['themeMode'], 'dark');
    });

    test('device-local settings and device-only fonts stay put', () async {
      final keys = await SyncKeys.derive(SyncKeys.newSecret());
      final m = FakeMailbox();
      final a = await device('a', m, keys), b = await device('b', m, keys);
      a.set({'exactAlarms': true, 'shareUsage': true, 'setupDone': true, 'hebrewFont': 'user_123', 'latinFont': 'gf_Lora', 'location': {'name': 'Elsewhere'}, 'themeMode': 'light'});
      await a.sync();
      await b.sync();
      final s = b.settings ?? const AppSettings().toJson();
      final d = const AppSettings().toJson();
      for (final k in ['exactAlarms', 'shareUsage', 'setupDone', 'hebrewFont', 'latinFont', 'location']) {
        expect(canon(s[k]), canon(d[k]), reason: k);
      }
      expect(s['themeMode'], 'light');
      final remote = SyncDoc.decode(await keys.open(m.blob!));
      expect(remote.entries.keys.where((k) => k.contains('exactAlarms') || k.contains('location') || k.contains('Font')), isEmpty);
    });

    test('an incoming font this device does not have is ignored', () async {
      final keys = await SyncKeys.derive(SyncKeys.newSecret());
      final m = FakeMailbox();
      final b = await device('b', m, keys);
      m.blob = await keys.seal(SyncDoc({'settings/hebrewFont': const SyncEntry(5000, 'a', 'user_9'), 'settings/warmth': const SyncEntry(5000, 'a', 0.9)}).encode());
      m.rev = 1;
      await b.sync();
      expect(b.settings!['warmth'], 0.9);
      expect(b.settings!['hebrewFont'], const AppSettings().toJson()['hebrewFont']);
    });

    test('lists sync whole, including deleting them', () async {
      final keys = await SyncKeys.derive(SyncKeys.newSecret());
      final m = FakeMailbox();
      final a = await device('a', m, keys), b = await device('b', m, keys);
      a.storage.writeJson('personalDates', [{'id': '1', 'name': 'Yahrzeit'}]);
      await a.sync();
      await b.sync();
      expect(b.storage.readJson('personalDates', (j) => j), [{'id': '1', 'name': 'Yahrzeit'}]);
      b.storage.deleteJson('personalDates');
      await b.sync();
      await a.sync();
      expect(a.storage.readJson('personalDates', (j) => j), isNull);
    });

    test('the engine\'s own writes are flagged so they are not re-uploaded as the user\'s', () async {
      final keys = await SyncKeys.derive(SyncKeys.newSecret());
      final m = FakeMailbox();
      final a = await device('a', m, keys), b = await device('b', m, keys);
      a.set({'themeMode': 'dark'});
      await a.sync();
      final seen = <(String, bool)>[];
      final e = b.engine;
      final sub = b.storage.changes.listen((k) => seen.add((k, e.applying)));
      // Replace b's engine state via a manual run on the same engine instance.
      final remote = SyncDoc.decode(await keys.open(m.blob!));
      e.state.doc.mergeIn(remote);
      e.applyToStorage();
      await sub.cancel();
      expect(seen, [('settings', true)]);
    });

    test('syncing again with nothing new neither writes nor pushes', () async {
      final keys = await SyncKeys.derive(SyncKeys.newSecret());
      final m = FakeMailbox();
      final a = await device('a', m, keys);
      a.set({'themeMode': 'dark'});
      await a.sync();
      final before = m.pushes;
      final out = await a.sync();
      expect(out.pushed, isFalse);
      expect(out.appliedKeys, isEmpty);
      expect(m.pushes, before);
    });

    test('a conflicting write in between is merged, not lost', () async {
      final keys = await SyncKeys.derive(SyncKeys.newSecret());
      final m = FakeMailbox();
      final a = await device('a', m, keys), b = await device('b', m, keys);
      a.set({'themeMode': 'dark'});
      await a.sync();
      await b.sync();
      a.set({'warmth': 0.4});
      b.set({'textScale': 1.6});
      m.beforePush = () => b.sync(); // b gets in while a is pushing
      await a.sync();
      await b.sync();
      for (final d in [a, b]) {
        expect(d.settings!['warmth'], 0.4);
        expect(d.settings!['textScale'], 1.6);
      }
    });

    test('a wrong pairing code is reported, and nothing is overwritten', () async {
      final m = FakeMailbox();
      final a = await device('a', m, await SyncKeys.derive(SyncKeys.newSecret()));
      a.set({'themeMode': 'dark'});
      await a.sync();
      final intruder = await device('x', m, await SyncKeys.derive(SyncKeys.newSecret()));
      await expectLater(intruder.sync(), throwsA(isA<SyncKeyError>()));
      expect(m.rev, 1);
    });

    test('state survives a restart', () async {
      final keys = await SyncKeys.derive(SyncKeys.newSecret());
      final m = FakeMailbox();
      final a = await device('a', m, keys);
      a.set({'themeMode': 'dark'});
      await a.sync();
      final back = syncStateFromJson((jsonDecode(jsonEncode(syncStateToJson(a.state))) as Map).cast<String, Object?>());
      expect(back.deviceId, 'a');
      expect(back.doc.sameAs(a.state.doc), isTrue);
      expect(back.rev, a.state.rev);
    });
  });

  group('worker transport', () {
    late HttpServer server;
    late String url;
    String? blob;
    int rev = 0;
    setUp(() async {
      blob = null;
      rev = 0;
      server = await HttpServer.bind('127.0.0.1', 0);
      url = 'http://127.0.0.1:${server.port}';
      server.listen((req) async {
        final res = req.response..headers.contentType = ContentType.json;
        void send(int code, Object body) => res..statusCode = code..write(jsonEncode(body));
        if (req.uri.path == '/v1/health') {
          send(200, {'ok': true, 'app': 'amud-sync', 'v': 1});
        } else if (req.headers.value('authorization') != 'Bearer tokentokentokentoken') {
          send(403, {'error': 'wrong token'});
        } else if (req.method == 'GET') {
          blob == null ? send(404, {'error': 'empty'}) : send(200, {'rev': rev, 'blob': blob});
        } else if (req.method == 'PUT') {
          final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
          if (int.parse(req.headers.value('if-match')!) != rev) {
            send(409, {'error': 'conflict', 'rev': rev, 'blob': blob});
          } else {
            blob = body['blob'] as String;
            send(200, {'rev': ++rev});
          }
        } else if (req.method == 'DELETE') {
          blob = null;
          rev = 0;
          send(200, {'ok': true});
        }
        await res.close();
      });
    });
    tearDown(() => server.close(force: true));

    test('pull, push, conflict, delete and the health check', () async {
      final t = WorkerTransport(baseUrl: url, mailboxId: 'a' * 32, token: 'tokentokentokentoken');
      expect(await WorkerTransport.check(url), isTrue);
      expect(await WorkerTransport.check('http://127.0.0.1:1'), isFalse);
      expect(await t.pull(), isNull);
      expect((await t.push('Zm9v', 0)).rev, 1);
      final r = await t.pull();
      expect((r!.rev, r.blob), (1, 'Zm9v'));
      final stale = await t.push('YmFy', 0);
      expect(stale.conflict!.rev, 1);
      expect(stale.conflict!.blob, 'Zm9v');
      await t.deleteAll();
      expect(await t.pull(), isNull);
      final bad = WorkerTransport(baseUrl: url, mailboxId: 'a' * 32, token: 'someone-else-someone');
      await expectLater(bad.pull(), throwsA(isA<SyncTransportError>()));
      final down = WorkerTransport(baseUrl: 'http://127.0.0.1:1', mailboxId: 'a' * 32, token: 'tokentokentokentoken');
      await expectLater(down.pull(), throwsA(isA<SyncTransportError>()));
    });
  });
}
