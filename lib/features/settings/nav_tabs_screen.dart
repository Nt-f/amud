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
  ('settings', Icons.settings_outlined, Icons.settings, CupertinoIcons.settings, 'Settings'),
];

/// A shortcut the bar can show among the tabs: another part of the app,
/// opened the way a link would open it. Its id in [AppSettings.navTabs],
/// icons (Material, Cupertino), label and route.
typedef NavShortcut = (String id, IconData icon, IconData cupertino, String label, String route);

const navShortcuts = <NavShortcut>[
  ('calendar', Icons.calendar_month_outlined, CupertinoIcons.calendar, 'Calendar', '/calendar'),
  ('tehillim', Icons.auto_stories_outlined, CupertinoIcons.book_solid, 'Tehillim', '/torah/tehillim'),
  ('learning', Icons.school_outlined, CupertinoIcons.lightbulb, 'Learning', '/learning'),
  ('alerts', Icons.notifications_active_outlined, CupertinoIcons.bell, 'Alerts', '/alerts'),
  ('personal-dates', Icons.event_repeat, CupertinoIcons.calendar_badge_plus, 'Dates', '/personal-dates'),
];

/// The most items the bar holds, tabs and shortcuts together.
const maxNavItems = 7;

/// An item on the bar: a tab (with its shell [branch]) or a shortcut (with
/// its [route]).
class NavItem {
  final String id;
  final IconData outlined, selected, cupertino;
  final String label;
  final int? branch;
  final String? route;
  const NavItem._(this.id, this.outlined, this.selected, this.cupertino, this.label, {this.branch, this.route});

  /// The item for [id], or null for one this version doesn't know.
  static NavItem? of(String id) {
    final b = navTabs.indexWhere((t) => t.$1 == id);
    if (b >= 0) {
      final (_, o, s, c, l) = navTabs[b];
      return NavItem._(id, o, s, c, l, branch: b);
    }
    for (final (sid, i, c, l, r) in navShortcuts) {
      if (sid == id) return NavItem._(id, i, i, c, l, route: r);
    }
    return null;
  }
}

/// Choose which tabs and shortcuts the navigation bar shows, their order,
/// and whether it shows labels.
class NavTabsScreen extends ConsumerWidget {
  const NavTabsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final shown = [for (final id in s.navTabs) if (NavItem.of(id) != null) id];
    void save(List<String> tabs) => ref.read(settingsProvider.notifier).update((x) => x.copyWith(navTabs: tabs));
    final hiddenTabs = [for (final t in navTabs) if (!shown.contains(t.$1)) t.$1];
    final hiddenShortcuts = [for (final t in navShortcuts) if (!shown.contains(t.$1)) t.$1];
    final theme = Theme.of(context);

    Widget tile(String id, {required bool on, int? index}) {
      final item = NavItem.of(id)!;
      return ListTile(
        key: ValueKey(id),
        leading: Checkbox.adaptive(
          value: on,
          // Settings stays, so this screen can always be reached; the bar
          // needs two items at least, and has room for [maxNavItems].
          onChanged: id == 'settings' || (on && shown.length <= 2) || (!on && shown.length >= maxNavItems)
              ? null
              : (v) => save(v! ? [...shown, id] : [...shown]..remove(id)),
        ),
        title: Row(children: [
          Icon(item.outlined, size: 20),
          const SizedBox(width: 12),
          Flexible(child: Text(context.tr(item.label))),
          if (item.route != null) ...[
            const SizedBox(width: 8),
            Icon(Icons.north_east, size: 14, color: theme.colorScheme.outline),
          ],
        ]),
        trailing: index == null ? null : ReorderableDragStartListener(index: index, child: const Icon(Icons.drag_handle)),
      );
    }

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(text, style: theme.textTheme.titleSmall),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Navigation bar')),
        actions: [
          TextButton(
            onPressed: () => ref.read(settingsProvider.notifier).update((x) => x.copyWith(
                  navTabs: const AppSettings().navTabs,
                  navLabels: const AppSettings().navLabels,
                )),
            child: Text(context.tr('Reset')),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        SwitchListTile.adaptive(
          title: Text(context.tr('Show labels')),
          subtitle: Text(context.tr('Turn off for a bar of icons only')),
          value: s.navLabels,
          onChanged: (v) => ref.read(settingsProvider.notifier).update((x) => x.copyWith(navLabels: v)),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
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
            for (var i = 0; i < shown.length; i++) tile(shown[i], on: true, index: i),
          ],
        ),
        if (hiddenTabs.isNotEmpty) heading(context.tr('Hidden')),
        for (final id in hiddenTabs) tile(id, on: false),
        if (hiddenShortcuts.isNotEmpty) ...[
          heading(context.tr('Shortcuts')),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              context.tr('Add other parts of the app to the bar. Up to {n} items fit.', {'n': maxNavItems}),
              style: theme.textTheme.bodySmall,
            ),
          ),
          for (final id in hiddenShortcuts) tile(id, on: false),
        ],
      ]),
    );
  }
}
