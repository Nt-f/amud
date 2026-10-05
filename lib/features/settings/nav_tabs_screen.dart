import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../core/settings.dart';

/// A tab the navigation bar can show: its id in [AppSettings.navTabs], its
/// icons (Material outlined and selected, Cupertino) and label.
typedef NavTab = (String id, IconData outlined, IconData selected, IconData cupertino, String label);

/// Every tab, in the order of the app's shell branches.
const navTabs = <NavTab>[
  ('home', Icons.dashboard_outlined, Icons.dashboard, CupertinoIcons.square_grid_2x2, 'Home'),
  ('siddur', Icons.menu_book_outlined, Icons.menu_book, CupertinoIcons.book, 'Siddur'),
  ('zmanim', Icons.wb_twilight_outlined, Icons.wb_twilight, CupertinoIcons.sunrise, 'Zmanim'),
  ('torah', Icons.local_library_outlined, Icons.local_library, CupertinoIcons.book_circle, 'Torah'),
  ('shiurim', Icons.straighten_outlined, Icons.straighten, CupertinoIcons.resize, 'Shiurim'),
  ('settings', Icons.settings_outlined, Icons.settings, CupertinoIcons.settings, 'Settings'),
];

/// Choose which tabs the navigation bar shows, and their order.
class NavTabsScreen extends ConsumerWidget {
  const NavTabsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = ref.watch(settingsProvider.select((s) => s.navTabs));
    void save(List<String> tabs) => ref.read(settingsProvider.notifier).update((x) => x.copyWith(navTabs: tabs));
    final byId = {for (final t in navTabs) t.$1: t};
    final hidden = [for (final t in navTabs) if (!shown.contains(t.$1)) t];
    final theme = Theme.of(context);

    Widget tile(NavTab t, {required bool on, int? index}) => ListTile(
          key: ValueKey(t.$1),
          leading: Checkbox.adaptive(
            value: on,
            // Settings stays, so this screen can always be reached, and the
            // bar needs two tabs at least.
            onChanged: t.$1 == 'settings' || (on && shown.length <= 2) ? null : (v) => save(v! ? [...shown, t.$1] : [...shown]..remove(t.$1)),
          ),
          title: Row(children: [Icon(t.$2, size: 20), const SizedBox(width: 12), Text(context.tr(t.$5))]),
          trailing: index == null
              ? null
              : ReorderableDragStartListener(index: index, child: const Icon(Icons.drag_handle)),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Navigation bar')),
        actions: [
          TextButton(onPressed: () => save(const AppSettings().navTabs), child: Text(context.tr('Reset'))),
        ],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(context.tr('Choose the tabs to show. Drag to reorder.'), style: theme.textTheme.bodySmall),
        ),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorder: (a, b) {
            final l = [...shown];
            if (b > a) b--;
            l.insert(b, l.removeAt(a));
            save(l);
          },
          children: [
            for (var i = 0; i < shown.length; i++) tile(byId[shown[i]]!, on: true, index: i),
          ],
        ),
        if (hidden.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(context.tr('Hidden'), style: theme.textTheme.titleSmall),
          ),
        for (final t in hidden) tile(t, on: false),
      ]),
    );
  }
}
