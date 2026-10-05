import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'shiurim_data.dart';

/// Whose shiurim are shown first, and the defaults for the time shiurim
/// and coins. Every opinion is always listed; these only choose which one
/// leads.
class ShiurimSettings {
  /// The posek followed: one of [followable].
  final String follow;

  /// The time to walk a mil, and to eat a pras: opinion ids.
  final String mil;
  final String pras;

  /// The weight of a perutah: an opinion id.
  final String coins;

  /// The price of a gram of silver, to show coins in money; null when not
  /// entered (the app doesn't look it up, so it works offline).
  final double? silverPerGram;
  final String currency;

  const ShiurimSettings({
    this.follow = 'naeh',
    this.mil = '18',
    this.pras = '4',
    this.coins = 'shulchanAruch',
    this.silverPerGram,
    this.currency = r'$',
  });

  ShiurimSettings copyWith({String? follow, String? mil, String? pras, String? coins, double? Function()? silverPerGram, String? currency}) =>
      ShiurimSettings(
        follow: follow ?? this.follow,
        mil: mil ?? this.mil,
        pras: pras ?? this.pras,
        coins: coins ?? this.coins,
        silverPerGram: silverPerGram != null ? silverPerGram() : this.silverPerGram,
        currency: currency ?? this.currency,
      );

  /// The opinion [m] is shown by: the posek followed where he has one,
  /// else the usual default.
  Opinion? opinionFor(Measure m) {
    final list = m.opinions;
    if (list == null) return null;
    final id = m.id == 'coins' ? coins : follow;
    return list.where((o) => o.id == id).firstOrNull ?? list.where((o) => o.id == usualDefaults[m.id]).firstOrNull ?? list.first;
  }

  /// The opinion chosen for a unit with its own opinions (mil, pras).
  String unitOpinion(String unitId) => switch (unitId) { 'mil' => mil, 'pras' => pras, _ => '' };

  /// The ruling of [s] that leads: the default's for the time shiurim, the
  /// posek followed's for the others (his first, not an alternative).
  Ruling leading(CommonShiur s) {
    final id = switch (s.id) { 'mil' => mil, 'pras' => pras, _ => follow };
    return s.rulings.where((r) => r.opinionId == id && !r.alternative).firstOrNull ?? s.rulings.first;
  }

  Map<String, Object?> toJson() =>
      {'follow': follow, 'mil': mil, 'pras': pras, 'coins': coins, 'silverPerGram': silverPerGram, 'currency': currency};

  factory ShiurimSettings.fromJson(Map<String, Object?> j) {
    const d = ShiurimSettings();
    String pick(String key, String fallback, Iterable<String> allowed) =>
        j[key] is String && allowed.contains(j[key]) ? j[key] as String : fallback;
    return ShiurimSettings(
      follow: pick('follow', d.follow, followable),
      mil: pick('mil', d.mil, [for (final o in hiluchMil) o.id]),
      pras: pick('pras', d.pras, [for (final o in achilasPras) o.id]),
      coins: pick('coins', d.coins, [for (final o in measures.firstWhere((m) => m.id == 'coins').opinions!) o.id]),
      silverPerGram: j['silverPerGram'] is num && (j['silverPerGram'] as num) > 0 ? (j['silverPerGram'] as num).toDouble() : null,
      currency: j['currency'] is String && (j['currency'] as String).isNotEmpty ? j['currency'] as String : d.currency,
    );
  }
}

class ShiurimSettingsNotifier extends Notifier<ShiurimSettings> {
  static const _key = 'shiurimSettings';

  @override
  ShiurimSettings build() =>
      ref.watch(storageProvider).readJson(_key, (j) => ShiurimSettings.fromJson((j as Map).cast<String, Object?>())) ??
      const ShiurimSettings();

  void update(ShiurimSettings Function(ShiurimSettings) f) {
    state = f(state);
    ref.read(storageProvider).writeJson(_key, state.toJson());
  }
}

final shiurimSettingsProvider = NotifierProvider<ShiurimSettingsNotifier, ShiurimSettings>(ShiurimSettingsNotifier.new);
