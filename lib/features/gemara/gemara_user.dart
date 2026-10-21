import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// A place in the Gemara: an amud and, optionally, a segment on it.
class DafPlace {
  final String tractate;
  final String amud;
  final int segment;
  const DafPlace(this.tractate, this.amud, [this.segment = 0]);

  String get key => '$tractate:$amud:$segment';

  Map<String, Object?> toJson() => {'tractate': tractate, 'amud': amud, 'segment': segment};
  static DafPlace? fromJson(Object? o) {
    if (o is! Map || o['tractate'] is! String || o['amud'] is! String) return null;
    return DafPlace(o['tractate'] as String, o['amud'] as String, o['segment'] is int ? o['segment'] as int : 0);
  }

  @override
  bool operator ==(Object other) => other is DafPlace && other.key == key;
  @override
  int get hashCode => key.hashCode;
}

/// The reader's own marks on the text, kept on the device (and carried by
/// sync and settings files when learning progress is included).
class GemaraMarks {
  final List<DafPlace> bookmarks;

  /// Segment key → note text.
  final Map<String, String> notes;

  /// Segment key → highlight color index (into [highlightColors]).
  final Map<String, int> highlights;

  /// Most recent first; the first entry is where to resume.
  final List<DafPlace> history;

  /// Amudim the reader marked complete ("Berakhot:2a"), only ever with the
  /// button at the end of the amud; opening or reading one doesn't count.
  final Set<String> completed;

  const GemaraMarks({
    this.bookmarks = const [],
    this.notes = const {},
    this.highlights = const {},
    this.history = const [],
    this.completed = const {},
  });

  bool isComplete(String tractate, String amud) => completed.contains('$tractate:$amud');

  /// Dafim of a tractate whose every amud there is complete.
  int completedDafim(String tractate, Iterable<String> amudim) {
    final byDaf = <String, bool>{};
    for (final a in amudim) {
      final daf = a.substring(0, a.length - 1);
      byDaf[daf] = (byDaf[daf] ?? true) && isComplete(tractate, a);
    }
    return byDaf.values.where((v) => v).length;
  }

  GemaraMarks copyWith({
    List<DafPlace>? bookmarks,
    Map<String, String>? notes,
    Map<String, int>? highlights,
    List<DafPlace>? history,
    Set<String>? completed,
  }) =>
      GemaraMarks(
        bookmarks: bookmarks ?? this.bookmarks,
        notes: notes ?? this.notes,
        highlights: highlights ?? this.highlights,
        history: history ?? this.history,
        completed: completed ?? this.completed,
      );

  DafPlace? get resume => history.firstOrNull;

  bool isBookmarked(DafPlace p) => bookmarks.any((b) => b.tractate == p.tractate && b.amud == p.amud);

  Map<String, Object?> toJson() => {
        'bookmarks': [for (final b in bookmarks) b.toJson()],
        'notes': notes,
        'highlights': highlights,
        'history': [for (final h in history) h.toJson()],
        'completed': completed.toList(),
      };

  factory GemaraMarks.fromJson(Map<String, Object?> j) => GemaraMarks(
        bookmarks: [for (final b in (j['bookmarks'] as List? ?? const [])) ?DafPlace.fromJson(b)],
        notes: {for (final e in ((j['notes'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
        highlights: {
          for (final e in ((j['highlights'] as Map?) ?? const {}).entries)
            if (e.value is int) '${e.key}': e.value as int,
        },
        history: [for (final h in (j['history'] as List? ?? const [])) ?DafPlace.fromJson(h)],
        completed: {for (final c in (j['completed'] as List? ?? const [])) '$c'},
      );
}

/// Highlight colors, light enough to read through in both themes.
const highlightColors = [Color(0x66FFD54F), Color(0x6681C784), Color(0x6664B5F6), Color(0x66F06292)];

class GemaraMarksNotifier extends Notifier<GemaraMarks> {
  static const _key = 'gemaraMarks';
  static const _historyLength = 30;

  @override
  GemaraMarks build() =>
      ref.watch(storageProvider).readJson(_key, (j) => GemaraMarks.fromJson((j as Map).cast<String, Object?>())) ?? const GemaraMarks();

  void _save(GemaraMarks m) {
    state = m;
    ref.read(storageProvider).writeJson(_key, m.toJson());
  }

  void toggleBookmark(DafPlace p) {
    final has = state.isBookmarked(p);
    _save(state.copyWith(
      bookmarks: has ? [for (final b in state.bookmarks) if (b.tractate != p.tractate || b.amud != p.amud) b] : [p, ...state.bookmarks],
    ));
  }

  void setNote(DafPlace p, String text) {
    final notes = {...state.notes};
    if (text.trim().isEmpty) {
      notes.remove(p.key);
    } else {
      notes[p.key] = text.trim();
    }
    _save(state.copyWith(notes: notes));
  }

  void setHighlight(DafPlace p, int? color) {
    final h = {...state.highlights};
    if (color == null) {
      h.remove(p.key);
    } else {
      h[p.key] = color;
    }
    _save(state.copyWith(highlights: h));
  }

  /// Records that [p] was read; the newest place per amud wins.
  void visit(DafPlace p) {
    if (state.history.firstOrNull == p) return;
    final rest = [for (final h in state.history) if (h.tractate != p.tractate || h.amud != p.amud) h];
    _save(state.copyWith(history: [p, ...rest].take(_historyLength).toList()));
  }

  /// Marks an amud complete (or not). Returns whether it is complete now.
  bool setComplete(String tractate, String amud, bool done) {
    final key = '$tractate:$amud';
    _save(state.copyWith(completed: done ? {...state.completed, key} : ({...state.completed}..remove(key))));
    return done;
  }
}

final gemaraMarksProvider = NotifierProvider<GemaraMarksNotifier, GemaraMarks>(GemaraMarksNotifier.new);
