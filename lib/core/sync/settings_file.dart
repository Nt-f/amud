import 'dart:convert';

import '../storage.dart';
import 'sync_registry.dart';

/// A settings backup as a file: the same values that sync between devices
/// (see [syncSources]), so device-only settings (location, reminders) and
/// fonts that only exist on one device are left out. Progress goes in for
/// the groups ([syncGroups]) the reader includes.
const settingsFileFormat = 'amud-settings';

/// The file's bytes, from what [storage] holds now.
List<int> exportSettings(Storage storage, {Set<String>? groups}) {
  final data = <String, Object?>{};
  for (final s in syncSources) {
    if (!includesSource(s, groups ?? {...syncGroups})) continue;
    final stored = storage.readJson<Object?>(s.key, (j) => j);
    if (s.isParts) {
      if (stored != null) data[s.key] = s.join!(s.split!(stored));
      continue;
    }
    if (!s.perField) {
      if (stored != null) data[s.key] = stored;
      continue;
    }
    final m = stored is Map ? stored.cast<String, Object?>() : const <String, Object?>{};
    final defaults = s.defaults?.call() ?? const <String, Object?>{};
    final out = <String, Object?>{};
    for (final f in s.fields ?? {...defaults.keys, ...m.keys}) {
      final v = m.containsKey(f) ? m[f] : defaults[f];
      if (syncableValue(f, v)) out[f] = v;
    }
    data[s.key] = out;
  }
  return utf8.encode(const JsonEncoder.withIndent('  ').convert({'a': settingsFileFormat, 's': 1, 'data': data}));
}

/// Applies a file made by [exportSettings]; returns the storage keys written.
/// Progress in the file is added to what this device has. Throws
/// [FormatException] when it isn't one.
Future<Set<String>> importSettings(Storage storage, List<int> bytes, {Set<String>? groups}) async {
  final Object? j;
  try {
    j = jsonDecode(utf8.decode(bytes));
  } catch (_) {
    throw const FormatException('not an Amud settings file');
  }
  if (j is! Map || j['a'] != settingsFileFormat || j['data'] is! Map) throw const FormatException('not an Amud settings file');
  final data = (j['data'] as Map).cast<String, Object?>();
  final written = <String>{};
  for (final s in syncSources) {
    final v = data[s.key];
    if (v == null || !includesSource(s, groups ?? {...syncGroups})) continue;
    if (s.isParts) {
      await storage.writeJson(s.key, s.join!({...s.split!(storage.readJson<Object?>(s.key, (j) => j)), ...s.split!(v)}));
    } else if (!s.perField) {
      await storage.writeJson(s.key, v);
    } else {
      if (v is! Map) continue;
      final m = {
        ...?s.defaults?.call(),
        ...?storage.readJson<Map<String, Object?>>(s.key, (x) => (x as Map).cast<String, Object?>()),
      };
      for (final e in v.cast<String, Object?>().entries) {
        if (s.fields != null && !s.fields!.contains(e.key)) continue;
        if (!syncableValue(e.key, e.value)) continue;
        m[e.key] = e.value;
      }
      await storage.writeJson(s.key, m);
    }
    written.add(s.key);
  }
  return written;
}
