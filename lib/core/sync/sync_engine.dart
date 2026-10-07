import 'dart:convert';

import '../storage.dart';
import 'sync_codec.dart';
import 'sync_doc.dart';
import 'sync_registry.dart';
import 'sync_transport.dart';

/// What a device remembers about syncing (device-local; never synced).
class SyncState {
  SyncState({required this.deviceId, SyncDoc? doc, this.clock = 0, this.rev = 0, this.lastSynced}) : doc = doc ?? SyncDoc();

  final String deviceId;
  final SyncDoc doc;
  int clock;

  /// The mailbox revision this doc was last in step with.
  int rev;
  int? lastSynced;
}

class SyncOutcome {
  const SyncOutcome(this.pulled, this.pushed, this.appliedKeys);

  /// Entries taken from other devices.
  final int pulled;
  final bool pushed;

  /// Storage keys rewritten, so the app can reload what it holds in memory.
  final Set<String> appliedKeys;
}

/// Reads the synced values out of storage, merges them with the mailbox, and
/// writes what other devices changed back. Pure logic over [Storage] and a
/// [SyncTransport], so it is tested without a network.
class SyncEngine {
  SyncEngine({required this.storage, required this.transport, required this.keys, required this.state, int Function()? now})
      : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Storage storage;
  final SyncTransport transport;
  final SyncKeys keys;
  final SyncState state;
  final int Function() _now;

  int _tick() {
    state.clock = _now() > state.clock ? _now() : state.clock + 1;
    return state.clock;
  }

  /// The current value of every synced entry on this device.
  Map<String, Object?> snapshot() {
    final out = <String, Object?>{};
    for (final s in syncSources) {
      if (!s.perField) {
        final v = storage.readJson<Object?>(s.key, (j) => j);
        if (v != null) out[s.key] = v;
        continue;
      }
      final stored = storage.readJson<Map<String, Object?>>(s.key, (j) => (j as Map).cast<String, Object?>());
      final defaults = s.defaults?.call() ?? const {};
      final fields = s.fields ?? {...defaults.keys, ...?stored?.keys};
      for (final f in fields) {
        final v = stored != null && stored.containsKey(f) ? stored[f] : defaults[f];
        if (syncableValue(f, v)) out[s.entryName(f)] = v;
      }
    }
    return out;
  }

  Map<String, Object?> _defaultsByEntry() => {
        for (final s in syncSources)
          if (s.perField)
            for (final e in (s.defaults?.call() ?? const <String, Object?>{}).entries) s.entryName(e.key): e.value,
      };

  /// Stamps entries changed on this device since the last sync. A value an
  /// untouched install holds by default is not stamped, so a new device
  /// doesn't overwrite another device's choices.
  void refreshLocal() {
    final defaults = _defaultsByEntry();
    final snap = snapshot();
    for (final e in snap.entries) {
      final prior = state.doc.entries[e.key];
      if (prior == null) {
        if (defaults.containsKey(e.key) && canon(defaults[e.key]) == canon(e.value)) continue;
        if (!defaults.containsKey(e.key) && e.value == null) continue;
      } else if (canon(prior.v) == canon(e.value)) {
        continue;
      }
      state.doc.entries[e.key] = SyncEntry(_tick(), state.deviceId, e.value);
    }
    // A whole-key value that was deleted here.
    for (final s in syncSources.where((s) => !s.perField)) {
      final prior = state.doc.entries[s.key];
      if (prior != null && prior.v != null && !snap.containsKey(s.key)) state.doc.entries[s.key] = SyncEntry(_tick(), state.deviceId, null);
    }
  }


  SyncSource? _source(String name) {
    for (final s in syncSources) {
      if (s.perField ? name.startsWith('${s.key}/') : name == s.key) return s;
    }
    return null; // an entry from a newer app version: kept in the doc, not applied
  }

  /// Writes to storage whatever the merged doc says differently from this
  /// device; returns the storage keys it rewrote.
  Set<String> applyToStorage() {
    applying = true;
    try {
      return _applyToStorage();
    } finally {
      applying = false;
    }
  }

  /// True while [applyToStorage] writes, so change listeners can tell the
  /// engine's own writes from the user's.
  bool applying = false;

  Set<String> _applyToStorage() {
    final snap = snapshot();
    final maps = <String, Map<String, Object?>>{};
    final out = <String>{};
    for (final e in state.doc.entries.entries) {
      final src = _source(e.key);
      if (src == null) continue;
      final field = src.perField ? e.key.substring(src.key.length + 1) : null;
      if (field != null) {
        if (src.fields != null && !src.fields!.contains(field)) continue;
        if (!syncableValue(field, e.value.v)) continue;
      }
      if (canon(snap[e.key]) == canon(e.value.v)) continue;
      if (field == null) {
        if (e.value.v == null) {
          storage.deleteJson(src.key);
        } else {
          storage.writeJson(src.key, e.value.v);
        }
        out.add(src.key);
      } else {
        final m = maps.putIfAbsent(
            src.key,
            () => {
                  ...?src.defaults?.call(),
                  ...?storage.readJson<Map<String, Object?>>(src.key, (j) => (j as Map).cast<String, Object?>()),
                });
        m[field] = e.value.v;
      }
    }
    for (final m in maps.entries) {
      storage.writeJson(m.key, m.value);
      out.add(m.key);
    }
    return out;
  }

  /// One round: pull, merge, apply, push. Retries when another device wrote
  /// in between (the server answers 409 with its copy, which is merged next).
  Future<SyncOutcome> sync() async {
    var pulled = 0;
    var pushed = false;
    final applied = <String>{};
    var remote = await transport.pull();
    for (var attempt = 0; attempt < 5; attempt++) {
      final blob = remote?.blob;
      final remoteDoc = blob == null ? SyncDoc() : SyncDoc.decode(await keys.open(blob));
      if (remoteDoc.maxTime > state.clock) state.clock = remoteDoc.maxTime;
      refreshLocal();
      pulled += state.doc.mergeIn(remoteDoc).length;
      applied.addAll(applyToStorage());
      final rev = remote?.rev ?? 0;
      if (blob != null && state.doc.sameAs(remoteDoc)) {
        state.rev = rev;
        state.lastSynced = _now();
        return SyncOutcome(pulled, pushed, applied);
      }
      final res = await transport.push(await keys.seal(state.doc.encode()), rev);
      if (res.rev != null) {
        state.rev = res.rev!;
        state.lastSynced = _now();
        return SyncOutcome(pulled, true, applied);
      }
      remote = res.conflict;
      pushed = false;
    }
    throw SyncTransportError('Other devices kept changing the data; try again.');
  }
}

/// State persistence: kept under its own key, never synced.
const syncStateKey = 'sync';

Map<String, Object?> syncStateToJson(SyncState s) =>
    {'device': s.deviceId, 'clock': s.clock, 'rev': s.rev, 'last': s.lastSynced, 'doc': s.doc.toJson()};

SyncState syncStateFromJson(Map<String, Object?> j) => SyncState(
      deviceId: j['device'] as String,
      clock: (j['clock'] as num?)?.toInt() ?? 0,
      rev: (j['rev'] as num?)?.toInt() ?? 0,
      lastSynced: (j['last'] as num?)?.toInt(),
      doc: SyncDoc.decode(utf8.encode(jsonEncode(j['doc']))),
    );
