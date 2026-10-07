import 'dart:io';

import 'package:amud/core/providers.dart';
import 'package:amud/core/settings.dart';
import 'package:amud/core/storage.dart';
import 'package:amud/core/sync/sync_codec.dart';
import 'package:amud/core/sync/sync_service.dart';
import 'package:amud/core/sync/sync_transport.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_test.dart' show FakeMailbox;

/// A mailbox per Worker URL + id, shared by every "device" in a test.
class FakeWorker {
  final boxes = <String, FakeMailbox>{};
  SyncTransport call(String url, SyncKeys k) => _Routed(boxes.putIfAbsent('$url/${k.mailboxId}', FakeMailbox.new));
}

class _Routed implements SyncTransport {
  _Routed(this.box);
  final FakeMailbox box;
  @override
  Future<RemoteBlob?> pull() => box.pull();
  @override
  Future<PushResult> push(String b, int r) => box.push(b, r);
  @override
  Future<void> deleteAll() => box.deleteAll();
}

void main() {
  late Directory tmp;
  var n = 0;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('sync_ctl'));
  tearDown(() => tmp.delete(recursive: true));

  Future<ProviderContainer> app(FakeWorker w, {bool reachable = true}) async {
    final c = ProviderContainer(overrides: [
      storageProvider.overrideWithValue(await Storage.openAt(tmp.path, name: '${n++}')),
      syncTransportProvider.overrideWithValue(w.call),
      syncCheckProvider.overrideWithValue((_) async => reachable),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('pairing a second app: settings flow both ways and the app state reloads', () async {
    final w = FakeWorker();
    final a = await app(w), b = await app(w);
    a.read(settingsProvider.notifier).update((s) => s.copyWith(textScale: 1.4));
    await a.read(syncProvider.notifier).startNew(workerUrl: 'https://sync.example.com');
    final code = a.read(syncProvider).pairingCode!;
    expect(code, startsWith('amud1:'));
    expect(code, endsWith('@https://sync.example.com'));
    expect(a.read(syncProvider).lastSynced, isNotNull);

    expect(b.read(settingsProvider).textScale, isNot(1.4));
    expect(await b.read(syncProvider.notifier).join(code), isTrue);
    expect(b.read(settingsProvider).textScale, 1.4, reason: 'the provider reloaded from storage');
    expect(b.read(syncProvider).workerUrl, 'https://sync.example.com');

    b.read(settingsProvider.notifier).update((s) => s.copyWith(warmth: 0.6));
    await b.read(syncProvider.notifier).syncNow();
    await a.read(syncProvider.notifier).syncNow();
    expect(a.read(settingsProvider).warmth, 0.6);
  });

  test('a bad code or an unreachable server pairs nothing', () async {
    final w = FakeWorker();
    final a = await app(w, reachable: false);
    expect(await a.read(syncProvider.notifier).join('nonsense'), isFalse);
    await expectLater(a.read(syncProvider.notifier).startNew(workerUrl: 'https://nope.example.com'), throwsA(isA<SyncTransportError>()));
    expect(a.read(syncProvider).enabled, isFalse);
    await expectLater(a.read(syncProvider.notifier).startNew(), throwsA(isA<SyncTransportError>()), reason: 'no default server yet');
  });

  test('leaving keeps settings; leaving with delete empties the mailbox; a restart remembers', () async {
    final w = FakeWorker();
    final a = await app(w);
    a.read(settingsProvider.notifier).update((s) => s.copyWith(textScale: 1.3));
    await a.read(syncProvider.notifier).startNew(workerUrl: 'https://sync.example.com');
    final box = w.boxes.values.single;
    expect(box.blob, isNotNull);

    final again = ProviderContainer(overrides: [
      storageProvider.overrideWithValue(a.read(storageProvider)),
      syncTransportProvider.overrideWithValue(w.call),
    ]);
    addTearDown(again.dispose);
    expect(again.read(syncProvider).enabled, isTrue, reason: 'config persisted');
    expect(again.read(syncProvider).pairingCode, a.read(syncProvider).pairingCode);

    await a.read(syncProvider.notifier).leave(deleteRemote: true);
    expect(box.blob, isNull);
    expect(a.read(syncProvider).enabled, isFalse);
    expect(a.read(settingsProvider).textScale, 1.3);
  });

  test('a local change is pushed after the debounce', () async {
    final w = FakeWorker();
    final a = await app(w);
    await a.read(syncProvider.notifier).startNew(workerUrl: 'https://sync.example.com');
    final box = w.boxes.values.single;
    final before = box.rev;
    a.read(settingsProvider.notifier).update((s) => s.copyWith(warmth: 0.9));
    await Future<void>.delayed(const Duration(seconds: 5));
    expect(box.rev, before + 1);
  });
}
