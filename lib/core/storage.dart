import 'dart:convert';

import 'package:hive_ce_flutter/hive_ce_flutter.dart';

/// Thin persistence layer over Hive (IndexedDB on web, files elsewhere).
///
/// Everything is stored as JSON strings in a single key/value box so the
/// schema can evolve without Hive type adapters; binary blobs (user
/// fonts) live in their own box.
class Storage {
  Storage._(this._kv, this._blobs);
  final Box<String> _kv;
  final Box<List<int>> _blobs;

  static Future<Storage> open() async {
    // The folder keeps the app's original name so saved data survives the
    // rename to Amud.
    await Hive.initFlutter('flutter_siddur');
    final kv = await Hive.openBox<String>('kv');
    final blobs = await Hive.openBox<List<int>>('blobs');
    return Storage._(kv, blobs);
  }

  /// Opens the boxes in [dir] (tests, where there's no app directory).
  static Future<Storage> openAt(String dir) async {
    Hive.init(dir);
    return Storage._(await Hive.openBox<String>('kv'), await Hive.openBox<List<int>>('blobs'));
  }

  T? readJson<T>(String key, T Function(Object? json) decode) {
    final raw = _kv.get(key);
    if (raw == null) return null;
    try {
      return decode(jsonDecode(raw));
    } catch (_) {
      // Callers fall back to defaults and may save over this key; keep a
      // copy of what couldn't be read so it isn't lost for good.
      if (_kv.get('$key.unreadable') != raw) _kv.put('$key.unreadable', raw);
      return null;
    }
  }

  Future<void> writeJson(String key, Object? value) => _kv.put(key, jsonEncode(value));

  List<int>? readBlob(String key) => _blobs.get(key);
  Future<void> writeBlob(String key, List<int> bytes) => _blobs.put(key, bytes);
  Future<void> deleteBlob(String key) => _blobs.delete(key);
}
