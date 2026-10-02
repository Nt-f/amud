import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/analytics.dart';

/// A card placed on the home dashboard.
class CardConfig {
  final String id;
  final String type;

  /// Columns spanned (1 = half width on phones, 2 = full width).
  final int span;
  final Map<String, Object?> settings;
  const CardConfig({required this.id, required this.type, this.span = 1, this.settings = const {}});

  CardConfig copyWith({int? span, Map<String, Object?>? settings}) =>
      CardConfig(id: id, type: type, span: span ?? this.span, settings: settings ?? this.settings);

  T setting<T>(String key, T fallback) {
    final v = settings[key];
    return v is T ? v : fallback;
  }

  Map<String, Object?> toJson() => {'id': id, 'type': type, 'span': span, 'settings': settings};
  factory CardConfig.fromJson(Map<String, Object?> j) => CardConfig(
        id: j['id'] as String,
        type: j['type'] as String,
        span: (j['span'] as num?)?.toInt() ?? 1,
        settings: ((j['settings'] as Map?) ?? const {}).cast<String, Object?>(),
      );
}

typedef CardBuilder = Widget Function(BuildContext context, WidgetRef ref, CardConfig config);
typedef CardEditorBuilder = Widget Function(BuildContext context, WidgetRef ref, CardConfig config, ValueChanged<CardConfig> onChanged);

/// Describes a kind of card. New card kinds register here — the dashboard
/// knows nothing about individual cards.
class CardType {
  final String type;
  final String title;
  final String description;
  final IconData icon;
  final int defaultSpan;
  final Map<String, Object?> defaults;
  final CardBuilder build;
  final CardEditorBuilder? editor;

  /// Whether the card shows right now (e.g. Sefirat HaOmer only during
  /// the Omer); hidden cards take no space on the dashboard.
  final bool Function(WidgetRef ref, CardConfig config)? visible;

  /// When the card is conditional, says when it shows ("Only during the
  /// Omer"), for the add and edit screens; null for a card always shown.
  final String? Function(CardConfig config)? shownWhen;
  const CardType({
    required this.type,
    required this.title,
    required this.description,
    required this.icon,
    required this.build,
    this.defaultSpan = 1,
    this.defaults = const {},
    this.editor,
    this.visible,
    this.shownWhen,
  });
}

class CardRegistry {
  final Map<String, CardType> _types = {};
  void register(CardType t) => _types[t.type] = t;
  CardType? operator [](String type) => _types[type];
  List<CardType> get all => _types.values.toList();
}

final cardRegistryProvider = Provider<CardRegistry>((ref) => throw UnimplementedError('registered in main'));

const defaultDashboard = [
  CardConfig(id: 'd1', type: 'hebrewDate', span: 2),
  CardConfig(id: 'd5', type: 'omer', span: 2),
  CardConfig(id: 'd12', type: 'levanaWindow', span: 2, settings: {'onlyWhenOpen': true}),
  CardConfig(id: 'd4', type: 'todayInSiddur', span: 2),
  CardConfig(id: 'd9', type: 'quickPrayers', span: 2),
  CardConfig(id: 'd6', type: 'learning', span: 1, settings: {'schedules': ['dafYomi', 'mishnaYomi', 'rambam1']}),
  CardConfig(id: 'd10', type: 'minyan', span: 1),
  CardConfig(id: 'd3', type: 'candles', span: 1),
  CardConfig(id: 'd2', type: 'nextZman', span: 1),
  CardConfig(id: 'd11', type: 'calendar', span: 2),
  CardConfig(id: 'd7', type: 'zmanimList', span: 2),
  CardConfig(id: 'd8', type: 'upcoming', span: 2),
];

/// Bumped when saved dashboards should adopt a new arrangement.
const _dashboardVersion = 4;

/// v4: the Kiddush Levana window sits under Sefirat HaOmer, shown only
/// while the window is open.
List<CardConfig> _migrateV4(List<CardConfig> l) {
  final out = [...l];
  final i = out.indexWhere((c) => c.type == 'levanaWindow');
  final levana = i < 0
      ? const CardConfig(id: 'd12', type: 'levanaWindow', span: 2, settings: {'onlyWhenOpen': true})
      : out.removeAt(i);
  final omer = out.indexWhere((c) => c.type == 'omer');
  final date = out.indexWhere((c) => c.type == 'hebrewDate');
  out.insert(omer >= 0 ? omer + 1 : (date >= 0 ? date + 1 : 0), levana);
  return out;
}

/// v3: the Calendar tab became a card, placed under Shabbat & Yom Tov and
/// the next zman (above the zmanim list).
///
/// v2: the Omer card is a full-width strip under the date; after "Today
/// in the siddur" come quick prayers, then daily learning beside the
/// minyan card, then Shabbat & Yom Tov beside the next zman.
List<CardConfig> _migrate(List<CardConfig> l, int from) {
  l = _migrateBefore4(l, from);
  if (from < 4) l = _migrateV4(l);
  return l;
}

List<CardConfig> _migrateBefore4(List<CardConfig> l, int from) {
  if (from < 2) l = _migrateV2(l);
  if (from < 3 && !l.any((c) => c.type == 'calendar')) {
    final out = [...l];
    final after = [for (final (i, c) in out.indexed) if (c.type == 'candles' || c.type == 'nextZman') i];
    final zmanim = out.indexWhere((c) => c.type == 'zmanimList');
    final at = after.isNotEmpty ? after.last + 1 : (zmanim >= 0 ? zmanim : out.length);
    final ids = {for (final c in out) c.id};
    var n = out.length + 1;
    while (ids.contains('c$n')) {
      n++;
    }
    out.insert(at, CardConfig(id: 'c$n', type: 'calendar', span: 2));
    l = out;
  }
  return l;
}

List<CardConfig> _migrateV2(List<CardConfig> l) {
  final out = [...l];
  CardConfig? take(String type) {
    final i = out.indexWhere((c) => c.type == type);
    return i < 0 ? null : out.removeAt(i);
  }

  void insertAfter(String type, List<CardConfig> cards) {
    final i = out.indexWhere((c) => c.type == type);
    out.insertAll(i < 0 ? out.length : i + 1, cards);
  }

  final omer = take('omer');
  final quick = take('quickPrayers');
  final learning = take('learning');
  final minyan = take('minyan');
  final candles = take('candles');
  final next = take('nextZman');
  if (omer != null) insertAfter('hebrewDate', [omer.copyWith(span: 2)]);
  insertAfter('todayInSiddur', [
    ?quick?.copyWith(span: 2),
    ?learning?.copyWith(span: 1),
    ?minyan?.copyWith(span: 1),
    ?candles?.copyWith(span: 1),
    ?next?.copyWith(span: 1),
  ]);
  return out;
}

class DashboardNotifier extends Notifier<List<CardConfig>> {
  @override
  List<CardConfig> build() {
    final storage = ref.watch(storageProvider);
    final saved = storage.readJson(
        'dashboard', (j) => [for (final e in (j as List).cast<Map>()) CardConfig.fromJson(e.cast<String, Object?>())]);
    if (saved == null) return defaultDashboard;
    final version = storage.readJson('dashboardVersion', (j) => (j as num).toInt()) ?? 1;
    if (version >= _dashboardVersion) return saved;
    final migrated = _migrate(saved, version);
    storage.writeJson('dashboard', [for (final c in migrated) c.toJson()]);
    storage.writeJson('dashboardVersion', _dashboardVersion);
    return migrated;
  }

  void _save(List<CardConfig> l) {
    state = l;
    ref.read(storageProvider).writeJson('dashboard', [for (final c in l) c.toJson()]);
    ref.read(storageProvider).writeJson('dashboardVersion', _dashboardVersion);
  }

  void add(CardConfig c) {
    analytics.event('card_add', {'type': c.type});
    _save([...state, c]);
  }

  void remove(String id) {
    analytics.event('card_remove', {'type': state.where((c) => c.id == id).firstOrNull?.type});
    _save(state.where((c) => c.id != id).toList());
  }
  void replace(CardConfig c) => _save([for (final e in state) e.id == c.id ? c : e]);
  void reorder(int oldIndex, int newIndex) {
    final l = [...state];
    if (newIndex > oldIndex) newIndex--;
    l.insert(newIndex, l.removeAt(oldIndex));
    _save(l);
  }

  void reset() {
    analytics.event('cards_reset');
    _save(defaultDashboard);
  }
}

final dashboardProvider = NotifierProvider<DashboardNotifier, List<CardConfig>>(DashboardNotifier.new);
