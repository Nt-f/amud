import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import 'prayer_links.dart';

class ShortcutPreferences extends Notifier<List<String>> {
  @override
  List<String> build() =>
      ref
          .watch(storageProvider)
          .readJson(
            'iconShortcuts',
            (j) => (j as List)
                .whereType<String>()
                .where(prayerShortcuts.containsKey)
                .take(4)
                .toList(),
          ) ??
      const ['shacharit', 'mincha', 'maariv', 'birkat'];
  void set(List<String> keys) {
    state = keys.where(prayerShortcuts.containsKey).toSet().take(4).toList();
    ref.read(storageProvider).writeJson('iconShortcuts', state);
  }
}

final shortcutPreferencesProvider =
    NotifierProvider<ShortcutPreferences, List<String>>(
      ShortcutPreferences.new,
    );
