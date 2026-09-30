import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/format.dart';
import 'core/l10n.dart';
import 'core/providers.dart';
import 'core/settings.dart';
import 'core/theme.dart';
import 'features/alerts/alerts_screen.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/home/home_screen.dart';
import 'features/learning/learning_screen.dart';
import 'features/settings/font_gallery_screen.dart';
import 'features/settings/location_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/setup/setup_screen.dart';
import 'features/update/update_screen.dart';
import 'features/siddur/library_screen.dart';
import 'features/siddur/meein_shalosh_screen.dart';
import 'features/siddur/reader_screen.dart';
import 'features/siddur/versions_screen.dart';
import 'features/tehillim/tehillim_data.dart';
import 'features/tehillim/tehillim_reader.dart';
import 'features/tehillim/tehillim_screen.dart';
import 'features/zmanim/zmanim_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) => GoRouter(
      navigatorKey: _rootKey,
      initialLocation: '/',
      // First run: walk through the main options before anything else.
      redirect: (context, state) {
        final done = ref.read(settingsProvider).setupDone;
        final inSetup = state.matchedLocation == '/setup' || state.matchedLocation.startsWith('/settings/');
        return !done && !inSetup ? '/setup' : null;
      },
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => AdaptiveShell(shell: shell),
          branches: [
            StatefulShellBranch(routes: [GoRoute(path: '/', builder: (c, s) => const HomeScreen())]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/siddur',
                builder: (c, s) => LibraryScreen(section: s.uri.queryParameters['section']),
                routes: [
                  GoRoute(
                    path: 'tehillim',
                    builder: (c, s) => const TehillimScreen(),
                    routes: [
                      GoRoute(
                        path: 'read',
                        builder: (c, s) {
                          final q = s.uri.queryParameters;
                          return TehillimReaderScreen(
                            key: ValueKey(s.uri.toString()),
                            portion: Portion(q['en'] ?? 'Tehillim', q['he'] ?? 'תהלים', Portion.decode(q['p'] ?? '1')),
                          );
                        },
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'book/:book',
                    builder: (c, s) => BookScreen(book: s.pathParameters['book']!),
                    routes: [
                      GoRoute(
                        path: 'read',
                        builder: (c, s) => ReaderScreen(book: s.pathParameters['book']!, nodeId: s.uri.queryParameters['node'] ?? ''),
                      ),
                      GoRoute(path: 'versions', builder: (c, s) => VersionsScreen(book: s.pathParameters['book']!)),
                    ],
                  ),
                ],
              ),
            ]),
            StatefulShellBranch(routes: [GoRoute(path: '/zmanim', builder: (c, s) => const ZmanimScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/calendar', builder: (c, s) => const CalendarScreen())]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/settings',
                builder: (c, s) => const SettingsScreen(),
                routes: [
                  GoRoute(path: 'location', parentNavigatorKey: _rootKey, builder: (c, s) => const LocationScreen()),
                  GoRoute(path: 'fonts', parentNavigatorKey: _rootKey, builder: (c, s) => const FontGalleryScreen()),
                  GoRoute(path: 'rules', parentNavigatorKey: _rootKey, builder: (c, s) => const CustomRulesScreen()),
                ],
              ),
            ]),
          ],
        ),
        // Home shortcuts open prayers above the tabs, so back returns Home.
        GoRoute(path: '/pray/:section', parentNavigatorKey: _rootKey, builder: (c, s) => SectionReaderScreen(section: s.pathParameters['section']!)),
        GoRoute(
          path: '/read/:book',
          parentNavigatorKey: _rootKey,
          builder: (c, s) => ReaderScreen(book: s.pathParameters['book']!, nodeId: s.uri.queryParameters['node'] ?? '', standalone: true),
        ),
        GoRoute(path: '/update', parentNavigatorKey: _rootKey, builder: (c, s) => const UpdateScreen()),
        GoRoute(path: '/setup', parentNavigatorKey: _rootKey, builder: (c, s) => const SetupScreen()),
        GoRoute(path: '/alerts', parentNavigatorKey: _rootKey, builder: (c, s) => const AlertsScreen()),
        GoRoute(path: '/learning', parentNavigatorKey: _rootKey, builder: (c, s) => const LearningScreen()),
        GoRoute(path: '/meein-shalosh', parentNavigatorKey: _rootKey, builder: (c, s) => const MeeinShaloshScreen()),
      ],
    ));

class SiddurApp extends ConsumerWidget {
  const SiddurApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    shabbatName = s.ashkenaziSpelling ? 'Shabbos' : 'Shabbat';
    return MaterialApp.router(
      title: 'Siddur',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(s, Brightness.light),
      darkTheme: buildTheme(s, Brightness.dark),
      themeMode: s.flutterThemeMode,
      routerConfig: ref.watch(routerProvider),
      locale: s.uiLanguage.locale,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: [for (final l in UiLanguage.values) l.locale],
      builder: (context, child) => AppText(lang: s.uiLanguage, ashkenazi: s.ashkenaziSpelling, child: child!),
    );
  }
}

const _destinations = [
  (Icons.dashboard_outlined, Icons.dashboard, CupertinoIcons.square_grid_2x2, 'Home'),
  (Icons.menu_book_outlined, Icons.menu_book, CupertinoIcons.book, 'Siddur'),
  (Icons.wb_twilight_outlined, Icons.wb_twilight, CupertinoIcons.sunrise, 'Zmanim'),
  (Icons.calendar_month_outlined, Icons.calendar_month, CupertinoIcons.calendar, 'Calendar'),
  (Icons.settings_outlined, Icons.settings, CupertinoIcons.settings, 'Settings'),
];

/// Native navigation chrome: Cupertino tab bar on iOS/macOS, Material 3
/// navigation bar on phones, navigation rail on wide screens (tablet/web).
class AdaptiveShell extends ConsumerWidget {
  final StatefulNavigationShell shell;
  const AdaptiveShell({super.key, required this.shell});

  void _go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    // Reader focus mode slides the navigation out of view.
    final focus = ref.watch(focusModeProvider);
    Widget away(Widget bar, {required bool vertical}) => ClipRect(
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubic,
            alignment: vertical ? Alignment.topCenter : AlignmentDirectional.centerEnd,
            heightFactor: vertical && focus ? 0 : 1,
            widthFactor: !vertical && focus ? 0 : 1,
            child: bar,
          ),
        );
    if (wide) {
      return Scaffold(
        body: Row(children: [
          away(
            vertical: false,
            Row(children: [
              NavigationRail(
                selectedIndex: shell.currentIndex,
                onDestinationSelected: _go,
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final (o, s, _, l) in _destinations) NavigationRailDestination(icon: Icon(o), selectedIcon: Icon(s), label: Text(context.tr(l))),
                ],
              ),
              const VerticalDivider(width: 1),
            ]),
          ),
          Expanded(child: shell),
        ]),
      );
    }
    if (isCupertinoPlatform) {
      return Scaffold(
        body: shell,
        bottomNavigationBar: away(vertical: true, CupertinoTabBar(
          currentIndex: shell.currentIndex,
          onTap: _go,
          activeColor: Theme.of(context).colorScheme.primary,
          items: [for (final (_, _, c, l) in _destinations) BottomNavigationBarItem(icon: Icon(c), label: context.tr(l))],
        )),
      );
    }
    return Scaffold(
      body: shell,
      bottomNavigationBar: away(
        vertical: true,
        NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: _go,
          destinations: [for (final (o, s, _, l) in _destinations) NavigationDestination(icon: Icon(o), selectedIcon: Icon(s), label: context.tr(l))],
        ),
      ),
    );
  }
}
