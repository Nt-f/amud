// Runs the sync engine against a real Worker. Skipped unless a Worker is up:
//   (cd worker/sync && npx wrangler dev --port 8787) &
//   AMUD_SYNC_WORKER=http://localhost:8787 flutter test test/sync_worker_e2e_test.dart
import 'dart:io';

import 'package:amud/core/settings.dart';
import 'package:amud/core/storage.dart';
import 'package:amud/core/sync/sync_codec.dart';
import 'package:amud/core/sync/sync_engine.dart';
import 'package:amud/core/sync/sync_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final url = Platform.environment['AMUD_SYNC_WORKER'];

  test('two devices sync through the real Worker', () async {
    final tmp = await Directory.systemTemp.createTemp('sync_e2e');
    addTearDown(() => tmp.delete(recursive: true));
    expect(await WorkerTransport.check(url!), isTrue);
    final keys = await SyncKeys.derive(SyncKeys.newSecret());
    WorkerTransport transport() => WorkerTransport(baseUrl: url, mailboxId: keys.mailboxId, token: keys.token);
    addTearDown(() => transport().deleteAll());

    Future<(Storage, SyncEngine)> device(String id, String name) async {
      final s = await Storage.openAt(tmp.path, name: name);
      return (s, SyncEngine(storage: s, transport: transport(), keys: keys, state: SyncState(deviceId: id)));
    }

    final (sa, ea) = await device('a', 'a');
    final (sb, eb) = await device('b', 'b');
    sa.writeJson('settings', {...const AppSettings().toJson(), 'themeMode': 'dark', 'textScale': 1.3});
    expect((await ea.sync()).pushed, isTrue);
    expect((await eb.sync()).appliedKeys, {'settings'});
    final got = sb.readJson('settings', (j) => (j as Map).cast<String, Object?>())!;
    expect(got['themeMode'], 'dark');
    expect(got['textScale'], 1.3);

    // Someone with the wrong key is refused, not merged.
    final other = await SyncKeys.derive(SyncKeys.newSecret());
    final stranger = WorkerTransport(baseUrl: url, mailboxId: keys.mailboxId, token: other.token);
    await expectLater(stranger.pull(), throwsA(isA<SyncTransportError>()));
    // The Worker holds ciphertext only.
    final raw = await transport().pull();
    expect(raw!.blob, isNot(contains('themeMode')));
  }, skip: url == null ? 'set AMUD_SYNC_WORKER to a running Worker' : false);
}
