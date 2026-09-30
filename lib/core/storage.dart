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
    await Hive.initFlutter('flutter_siddur');
    final kv = await Hive.openBox<String>('kv');
    final blobs = await Hive.openBox<List<int>>('blobs');
    return Storage._(kv, blobs);
  }

  T? readJson<T>(String key, T Function(Object? json) decode) {
    final raw = _kv.get(key);
    if (raw == null) return null;
    try {
      return decode(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> writeJson(String key, Object? value) => _kv.put(key, jsonEncode(value));

  List<int>? readBlob(String key) => _blobs.get(key);
  Future<void> writeBlob(String key, List<int> bytes) => _blobs.put(key, bytes);
  Future<void> deleteBlob(String key) => _blobs.delete(key);
}
