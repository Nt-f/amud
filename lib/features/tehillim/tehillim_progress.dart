import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'tehillim_data.dart';

/// Reading progress through Sefer Tehillim, plus the user's own lists and
/// Tehillim display preferences.
class TehillimState {
  /// Chapters read in the current cycle through the whole sefer.
  final Set<int> read;

  /// Times the whole sefer has been completed.
  final int completions;

  /// Last chapter opened, to continue from.
  final int? lastChapter;

  /// User-defined selections, e.g. for a particular person or need.
  final List<Portion> lists;

  /// Show the ketiv (written form) beside the qere.
  final bool ketiv;
  final bool verseNumbers;

  /// One verse per line (otherwise verses flow as a paragraph).
  final bool versePerLine;

  const TehillimState({
    this.read = const {},
    this.completions = 0,
    this.lastChapter,
    this.lists = const [],
    this.ketiv = false,
    this.verseNumbers = true,
    this.versePerLine = true,
  });

  TehillimState copyWith({
    Set<int>? read,
    int? completions,
    int? Function()? lastChapter,
    List<Portion>? lists,
    bool? ketiv,
    bool? verseNumbers,
    bool? versePerLine,
  }) =>
      TehillimState(
        read: read ?? this.read,
        completions: completions ?? this.completions,
        lastChapter: lastChapter != null ? lastChapter() : this.lastChapter,
        lists: lists ?? this.lists,
        ketiv: ketiv ?? this.ketiv,
        verseNumbers: verseNumbers ?? this.verseNumbers,
        versePerLine: versePerLine ?? this.versePerLine,
      );

  Map<String, Object?> toJson() => {
        'read': (read.toList()..sort()),
        'completions': completions,
        'lastChapter': lastChapter,
        'lists': [for (final l in lists) {'en': l.titleEn, 'he': l.titleHe, 'p': l.encoded}],
        'ketiv': ketiv,
        'verseNumbers': verseNumbers,
        'versePerLine': versePerLine,
      };

  factory TehillimState.fromJson(Map<String, Object?> j) => TehillimState(
        read: {...((j['read'] as List?) ?? const []).cast<int>()},
        completions: (j['completions'] as num?)?.toInt() ?? 0,
        lastChapter: (j['lastChapter'] as num?)?.toInt(),
        lists: [
          for (final l in ((j['lists'] as List?) ?? const []).cast<Map>())
            Portion(l['en'] as String, l['he'] as String, Portion.decode(l['p'] as String)),
        ],
        ketiv: j['ketiv'] == true,
        verseNumbers: j['verseNumbers'] != false,
        versePerLine: j['versePerLine'] != false,
      );
}

class TehillimProgress extends Notifier<TehillimState> {
  static const _key = 'tehillim';

  @override
  TehillimState build() =>
      ref.watch(storageProvider).readJson(_key, (j) => TehillimState.fromJson((j as Map).cast())) ?? const TehillimState();

  void _save(TehillimState s) {
    state = s;
    ref.read(storageProvider).writeJson(_key, s.toJson());
  }

  void update(TehillimState Function(TehillimState s) f) => _save(f(state));

  void opened(int chapter) {
    if (state.lastChapter != chapter) _save(state.copyWith(lastChapter: () => chapter));
  }

  /// Marks chapters read; finishing all 150 counts a completion and starts
  /// a new cycle. Returns true when this completed the sefer.
  bool markRead(Iterable<int> chapters) {
    final read = {...state.read, ...chapters};
    if (read.length >= 150) {
      _save(state.copyWith(read: {}, completions: state.completions + 1));
      return true;
    }
    _save(state.copyWith(read: read));
    return false;
  }

  void unmark(int chapter) => _save(state.copyWith(read: {...state.read}..remove(chapter)));

  void resetCycle() => _save(state.copyWith(read: {}));

  void saveList(Portion p, {Portion? replacing}) => _save(state.copyWith(lists: [
        for (final l in state.lists)
          if (!identical(l, replacing)) l,
        p,
      ]));

  void deleteList(Portion p) => _save(state.copyWith(lists: [for (final l in state.lists) if (!identical(l, p)) l]));
}

final tehillimProgressProvider = NotifierProvider<TehillimProgress, TehillimState>(TehillimProgress.new);
