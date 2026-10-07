import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/personal_dates/personal_dates.dart';
import '../../features/shiurim/shiurim_settings.dart';
import '../../features/torah/shnayim_mikra.dart';
import '../../features/torah/torah_settings.dart';
import '../../features/zmanim/zman_catalog.dart';
import '../providers.dart';
import '../settings.dart';
import '../storage.dart';
import 'sync_codec.dart';
import 'sync_engine.dart';
import 'sync_registry.dart';
import 'sync_transport.dart';

/// The Worker used unless the user enters their own (Settings → Advanced →
/// Sync between devices). Empty until a hosted one is deployed: sync then
/// needs a Worker URL (see worker/sync/README.md).
const defaultSyncWorker = 'https://worker.amud.page';

const syncConfigKey = 'syncConfig';

class SyncStatus {
  const SyncStatus({this.enabled = false, this.busy = false, this.error, this.lastSynced, this.workerUrl, this.pairingCode});

  final bool enabled;
  final bool busy;

  /// English text of the last failure (shown as is; it carries server detail).
  final String? error;
  final DateTime? lastSynced;
  final String? workerUrl;
  final String? pairingCode;

  SyncStatus copyWith({bool? enabled, bool? busy, Object? error = _keep, DateTime? lastSynced}) => SyncStatus(
        enabled: enabled ?? this.enabled,
        busy: busy ?? this.busy,
        error: identical(error, _keep) ? this.error : error as String?,
        lastSynced: lastSynced ?? this.lastSynced,
        workerUrl: workerUrl,
        pairingCode: pairingCode,
      );
  static const _keep = Object();
}

/// Builds the transport for a Worker and mailbox (overridden in tests).
final syncTransportProvider = Provider<SyncTransport Function(String url, SyncKeys keys)>(
    (ref) => (url, keys) => WorkerTransport(baseUrl: url, mailboxId: keys.mailboxId, token: keys.token));

/// Whether an address is an Amud sync Worker (overridden in tests).
final syncCheckProvider = Provider<Future<bool> Function(String url)>((ref) => WorkerTransport.check);

/// Cross-device sync: opt-in, end-to-end encrypted, through a Worker.
class SyncController extends Notifier<SyncStatus> {
  static const _configKey = syncConfigKey;
  static const _debounce = Duration(seconds: 4);

  Timer? _timer;
  SyncEngine? _engine;
  bool _again = false;
  late final Set<String> _sourceKeys = {for (final s in syncSources) s.key};

  @override
  SyncStatus build() {
    final storage = ref.watch(storageProvider);
    final sub = storage.changes.listen((key) {
      if (!state.enabled || !_sourceKeys.contains(key) || (_engine?.applying ?? false)) return;
      _timer?.cancel();
      _timer = Timer(_debounce, syncNow);
    });
    ref.onDispose(() {
      sub.cancel();
      _timer?.cancel();
    });
    return _fromConfig(storage.readJson(_configKey, (j) => (j as Map).cast<String, Object?>()), storage);
  }

  SyncStatus _fromConfig(Map<String, Object?>? cfg, Storage storage) {
    if (cfg == null || cfg['secret'] is! String) return const SyncStatus();
    final url = cfg['url'] as String?;
    final last = (storage.readJson(syncStateKey, (j) => (j as Map)['last']) as num?)?.toInt();
    return SyncStatus(
      enabled: true,
      workerUrl: url ?? defaultSyncWorker,
      pairingCode: PairingCode(Uint8List.fromList(base64Url.decode(base64Url.normalize(cfg['secret'] as String))), url).toString(),
      lastSynced: last == null ? null : DateTime.fromMillisecondsSinceEpoch(last),
    );
  }

  /// Starts syncing as the first device: makes a pairing code (see
  /// [SyncStatus.pairingCode]) to enter on the others. Throws
  /// [SyncTransportError] if the Worker can't be used.
  Future<void> startNew({String? workerUrl}) => _enable(PairingCode(SyncKeys.newSecret(), workerUrl));

  /// Joins the devices that share [code]; returns false if it isn't a code.
  Future<bool> join(String code) async {
    final p = PairingCode.parse(code);
    if (p == null) return false;
    await _enable(p);
    return true;
  }

  Future<void> _enable(PairingCode p) async {
    final url = p.workerUrl ?? defaultSyncWorker;
    if (url.isEmpty) throw SyncTransportError('Enter a Worker URL first.');
    if (!await ref.read(syncCheckProvider)(url)) throw SyncTransportError('That address is not an Amud sync server.');
    final storage = ref.read(storageProvider);
    await storage.writeJson(_configKey, {'secret': base64Url.encode(p.secret).replaceAll('=', ''), 'url': p.workerUrl});
    await storage.deleteJson(syncStateKey);
    state = _fromConfig(storage.readJson(_configKey, (j) => (j as Map).cast<String, Object?>()), storage);
    await syncNow();
    // A first sync that failed leaves nothing half-paired.
    if (state.error != null && state.lastSynced == null) {
      final e = state.error!;
      await _forget();
      throw SyncTransportError(e);
    }
  }

  /// Syncs now; safe to call often (runs one at a time).
  Future<void> syncNow() async {
    if (!state.enabled) return;
    if (state.busy) {
      _again = true;
      return;
    }
    state = state.copyWith(busy: true, error: null);
    try {
      do {
        _again = false;
        await _run();
      } while (_again);
      state = state.copyWith(busy: false);
    } catch (e) {
      state = state.copyWith(busy: false, error: e is SyncKeyError || e is SyncTransportError ? e.toString() : 'Sync failed ($e).');
    }
  }

  Future<void> _run() async {
    final storage = ref.read(storageProvider);
    final cfg = storage.readJson(_configKey, (j) => (j as Map).cast<String, Object?>())!;
    final keys = await SyncKeys.derive(Uint8List.fromList(base64Url.decode(base64Url.normalize(cfg['secret'] as String))));
    final saved = storage.readJson(syncStateKey, (j) => syncStateFromJson((j as Map).cast<String, Object?>()));
    final st = saved ?? SyncState(deviceId: _newDeviceId());
    final engine = _engine = SyncEngine(storage: storage, transport: ref.read(syncTransportProvider)(state.workerUrl!, keys), keys: keys, state: st);
    try {
      final out = await engine.sync();
      await storage.writeJson(syncStateKey, syncStateToJson(st));
      state = state.copyWith(lastSynced: DateTime.fromMillisecondsSinceEpoch(st.lastSynced!));
      _reload(out.appliedKeys);
    } finally {
      _engine = null;
    }
  }

  /// Providers that read these keys once; make them read again. (Alerts
  /// re-plan themselves when the providers they watch change.)
  void _reload(Set<String> keys) {
    for (final k in keys) {
      switch (k) {
        case 'settings':
          ref.invalidate(settingsProvider);
        case 'torahSettings':
          ref.invalidate(torahSettingsProvider);
        case 'shiurimSettings':
          ref.invalidate(shiurimSettingsProvider);
        case 'shnayimMikraSettings':
          ref.invalidate(shnayimMikraSettingsProvider);
        case 'personalDates':
          ref.invalidate(personalDatesProvider);
        case 'customRules':
          ref.invalidate(customRulesProvider);
        case 'customZmanim':
          ref.invalidate(customZmanimProvider);
      }
    }
  }

  /// Stops syncing on this device; with [deleteRemote] also wipes the
  /// mailbox, which ends sync for every paired device.
  Future<void> leave({bool deleteRemote = false}) async {
    if (deleteRemote && state.enabled) {
      final storage = ref.read(storageProvider);
      final cfg = storage.readJson(_configKey, (j) => (j as Map).cast<String, Object?>());
      if (cfg != null) {
        final keys = await SyncKeys.derive(Uint8List.fromList(base64Url.decode(base64Url.normalize(cfg['secret'] as String))));
        await ref.read(syncTransportProvider)(state.workerUrl!, keys).deleteAll();
      }
    }
    await _forget();
  }

  Future<void> _forget() async {
    _timer?.cancel();
    final storage = ref.read(storageProvider);
    await storage.deleteJson(_configKey);
    await storage.deleteJson(syncStateKey);
    state = const SyncStatus();
  }

  static String _newDeviceId() {
    final r = Random.secure();
    return [for (var i = 0; i < 8; i++) r.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
  }
}

final syncProvider = NotifierProvider<SyncController, SyncStatus>(SyncController.new);
