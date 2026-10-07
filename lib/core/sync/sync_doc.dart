import 'dart:convert';

/// One synced value with the time and device that last changed it.
class SyncEntry {
  const SyncEntry(this.t, this.d, this.v);

  /// Hybrid logical clock, in ms: never behind a time this device has seen.
  final int t;

  /// Id of the device that wrote it; breaks ties between equal times.
  final String d;

  /// Null means "unset" (the key was deleted or the field is empty).
  final Object? v;

  /// Whether this entry beats [o]: later time wins, then the larger device id.
  bool beats(SyncEntry o) => t != o.t ? t > o.t : d.compareTo(o.d) > 0;

  Map<String, Object?> toJson() => {'t': t, 'd': d, 'v': v};

  static SyncEntry? fromJson(Object? j) {
    if (j is! Map || j['t'] is! int || j['d'] is! String) return null;
    return SyncEntry(j['t'] as int, j['d'] as String, j['v']);
  }
}

/// The whole synced state: entry name → latest entry. Merging two documents
/// is per entry (last writer wins), so it is commutative, associative and
/// idempotent: devices converge in any order without a coordinator.
class SyncDoc {
  SyncDoc([Map<String, SyncEntry>? entries]) : entries = entries ?? {};

  final Map<String, SyncEntry> entries;

  static const format = 'amud-sync';
  static const version = 1;

  SyncDoc copy() => SyncDoc({...entries});

  /// Folds [other] in; returns the names whose entry changed.
  Set<String> mergeIn(SyncDoc other) {
    final changed = <String>{};
    for (final e in other.entries.entries) {
      final mine = entries[e.key];
      if (mine == null || e.value.beats(mine)) {
        entries[e.key] = e.value;
        changed.add(e.key);
      }
    }
    return changed;
  }

  /// Whether both documents hold the same entries.
  bool sameAs(SyncDoc o) {
    if (entries.length != o.entries.length) return false;
    for (final e in entries.entries) {
      final x = o.entries[e.key];
      if (x == null || x.t != e.value.t || x.d != e.value.d || canon(x.v) != canon(e.value.v)) return false;
    }
    return true;
  }

  int get maxTime => entries.values.fold(0, (m, e) => e.t > m ? e.t : m);

  Map<String, Object?> toJson() =>
      {'a': format, 's': version, 'e': {for (final e in entries.entries) e.key: e.value.toJson()}};

  List<int> encode() => utf8.encode(jsonEncode(toJson()));

  /// Reads a document; unknown entries and a newer format are tolerated
  /// (entries that can't be read are skipped, never fatal).
  static SyncDoc decode(List<int> bytes) {
    final j = jsonDecode(utf8.decode(bytes));
    if (j is! Map || j['a'] != format) throw const FormatException('not an Amud sync document');
    final out = <String, SyncEntry>{};
    final e = j['e'];
    if (e is Map) {
      for (final x in e.entries) {
        final entry = SyncEntry.fromJson(x.value);
        if (x.key is String && entry != null) out[x.key as String] = entry;
      }
    }
    return SyncDoc(out);
  }
}

/// JSON with sorted keys, so equal values compare equal however their maps
/// were built.
String canon(Object? v) => jsonEncode(_sorted(v));

Object? _sorted(Object? v) {
  if (v is Map) return {for (final k in (v.keys.toList()..sort())) '$k': _sorted(v[k])};
  if (v is List) return [for (final x in v) _sorted(x)];
  return v;
}
