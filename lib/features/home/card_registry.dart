import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

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
  const CardType({
    required this.type,
    required this.title,
    required this.description,
    required this.icon,
    required this.build,
    this.defaultSpan = 1,
    this.defaults = const {},
    this.editor,
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
  CardConfig(id: 'd2', type: 'nextZman', span: 1),
  CardConfig(id: 'd3', type: 'candles', span: 1),
  CardConfig(id: 'd4', type: 'todayInSiddur', span: 2),
  CardConfig(id: 'd5', type: 'omer', span: 1),
  CardConfig(id: 'd6', type: 'learning', span: 1, settings: {'schedules': ['dafYomi', 'mishnaYomi', 'rambam1']}),
  CardConfig(id: 'd7', type: 'zmanimList', span: 2),
  CardConfig(id: 'd8', type: 'upcoming', span: 2),
  CardConfig(id: 'd9', type: 'quickPrayers', span: 2),
  CardConfig(id: 'd10', type: 'minyan', span: 2),
];

class DashboardNotifier extends Notifier<List<CardConfig>> {
  @override
  List<CardConfig> build() =>
      ref.watch(storageProvider).readJson(
          'dashboard', (j) => [for (final e in (j as List).cast<Map>()) CardConfig.fromJson(e.cast<String, Object?>())]) ??
      defaultDashboard;

  void _save(List<CardConfig> l) {
    state = l;
    ref.read(storageProvider).writeJson('dashboard', [for (final c in l) c.toJson()]);
  }

  void add(CardConfig c) => _save([...state, c]);
  void remove(String id) => _save(state.where((c) => c.id != id).toList());
  void replace(CardConfig c) => _save([for (final e in state) e.id == c.id ? c : e]);
  void reorder(int oldIndex, int newIndex) {
    final l = [...state];
    if (newIndex > oldIndex) newIndex--;
    l.insert(newIndex, l.removeAt(oldIndex));
    _save(l);
  }

  void reset() => _save(defaultDashboard);
}

final dashboardProvider = NotifierProvider<DashboardNotifier, List<CardConfig>>(DashboardNotifier.new);
