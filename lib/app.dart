import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/analytics.dart';
import 'features/integrations/reader_device.dart';
import 'features/personal_dates/personal_dates_screen.dart';
import 'features/js_cards/card_gallery_screen.dart';
import 'features/integrations/integrations_screen.dart';
import 'features/integrations/shared_note_screen.dart';
import 'core/format.dart';
import 'core/l10n.dart';
import 'core/page_swipe.dart';
import 'core/providers.dart';
import 'core/settings.dart';
import 'core/theme.dart';
import 'features/alerts/alerts_screen.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/home/home_screen.dart';
import 'features/learning/learning_screen.dart';
import 'features/settings/font_gallery_screen.dart';
import 'features/settings/offline_screen.dart';
import 'features/settings/location_screen.dart';
import 'features/settings/nav_tabs_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shiurim/shiurim_screen.dart';
import 'features/setup/launch_animation.dart';
import 'features/setup/setup_screen.dart';
import 'features/update/update_screen.dart';
import 'features/siddur/library_screen.dart';
import 'features/siddur/meein_shalosh_screen.dart';
import 'features/siddur/reader_screen.dart';
import 'features/siddur/seasons_screen.dart';
import 'features/siddur/versions_screen.dart';
import 'features/tehillim/tehillim_data.dart';
import 'features/tehillim/tehillim_reader.dart';
import 'features/tehillim/tehillim_screen.dart';
import 'features/torah/shnayim_mikra_screen.dart';
import 'features/torah/torah_screen.dart';
import 'features/zmanim/zmanim_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();

/// Opens [route] from outside the app: a link, a launcher shortcut, the
/// tray, a launch argument. A page above the tabs (a prayer opened on its
/// own) is pushed over whatever is open, Home on a cold start, so back and
/// the tab bar lead home; a page inside a tab is gone to.
void openFromOutside(GoRouter router, String route) {
  final first = Uri.parse(route).pathSegments.firstOrNull;
  final aboveTabs = first != null &&
      router.configuration.routes.any((r) => r is GoRoute && Uri.parse(r.path).pathSegments.firstOrNull == first);
  aboveTabs ? router.push(route) : router.go(route);
}

final routerProvider = Provider<GoRouter>((ref) => GoRouter(
      navigatorKey: _rootKey,
      // The app opens on the first tab of the bar. A launch link opens over
      // it after the first frame (see openFromOutside), so back and the tab
      // bar lead somewhere.
      initialLocation: _tabRoots.elementAt(navTabs.indexWhere((t) => t.$1 == ref.read(settingsProvider).navTabs.first)),
      // First run: walk through the main options before anything else.
      redirect: (context, state) {
        final done = ref.read(settingsProvider).setupDone;
        final inSetup = state.matchedLocation == '/setup' || state.matchedLocation.startsWith('/settings/');
        return !done && !inSetup ? Uri(path: '/setup', queryParameters: {'returnTo': state.uri.toString()}).toString() : null;
      },
      routes: [
        StatefulShellRoute.indexedStack(
          // Tabs swipe only on their own first screen: deeper pages (the
          // readers) have swipes of their own.
          builder: (context, state, shell) => AdaptiveShell(shell: shell, atTabRoot: _tabRoots.contains(state.fullPath)),
          branches: [
            StatefulShellBranch(routes: [GoRoute(path: '/', builder: (c, s) => const HomeScreen())]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/siddur',
                builder: (c, s) => LibraryScreen(section: s.uri.queryParameters['section']),
                routes: [
                  GoRoute(path: 'seasons', builder: (c, s) => const SeasonsScreen()),
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
                  GoRoute(path: ':nusach/:prayer', builder: (c, s) => SectionReaderScreen(
                    section: s.pathParameters['prayer']!, nusach: s.pathParameters['nusach']!)),
                ],
              ),
            ]),
            StatefulShellBranch(routes: [GoRoute(path: '/zmanim', builder: (c, s) => const ZmanimScreen())]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/torah',
                builder: (c, s) => const TorahScreen(),
                routes: [
                  GoRoute(
                    path: 'shnayim-mikra',
                    builder: (c, s) => ShnayimMikraScreen(
                      key: ValueKey(s.uri.toString()),
                      parsha: s.uri.queryParameters['parsha'],
                      year: int.tryParse(s.uri.queryParameters['year'] ?? ''),
                    ),
                    routes: [
                      GoRoute(
                        path: 'progress',
                        builder: (c, s) => ShnayimMikraProgressScreen(year: int.tryParse(s.uri.queryParameters['year'] ?? '')),
                      ),
                    ],
                  ),
                  // Opened from the Torah tab, so it doesn't add a tab to the bar.
                  GoRoute(path: 'shiurim', builder: (c, s) => const ShiurimScreen()),
                  GoRoute(
                    path: ':category',
                    builder: (c, s) => TorahCategoryScreen(category: s.pathParameters['category']!),
                    routes: [
                      GoRoute(
                        path: ':work',
                        builder: (c, s) => TorahWorkScreen(category: s.pathParameters['category']!, work: s.pathParameters['work']!),
                        routes: [
                          GoRoute(
                            path: 'read',
                            builder: (c, s) {
                              final q = s.uri.queryParameters;
                              return TorahReaderScreen(
                                key: ValueKey(s.uri.toString()),
                                category: s.pathParameters['category']!,
                                work: s.pathParameters['work']!,
                                siman: int.tryParse(q['siman'] ?? '') ?? 1,
                                from: int.tryParse(q['from'] ?? ''),
                                to: int.tryParse(q['to'] ?? ''),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ]),
            StatefulShellBranch(routes: [GoRoute(path: '/shiurim', builder: (c, s) => const ShiurimScreen())]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/settings',
                builder: (c, s) => const SettingsScreen(),
                routes: [
                  GoRoute(path: 'location', parentNavigatorKey: _rootKey, builder: (c, s) => const LocationScreen()),
                  GoRoute(path: 'fonts', parentNavigatorKey: _rootKey, builder: (c, s) => const FontGalleryScreen()),
                  GoRoute(path: 'offline', parentNavigatorKey: _rootKey, builder: (c, s) => const OfflineScreen()),
                  GoRoute(path: 'integrations', parentNavigatorKey: _rootKey, builder: (c, s) => const IntegrationsScreen()),
                  GoRoute(path: 'cards', parentNavigatorKey: _rootKey, builder: (c, s) => const CardGalleryScreen()),
                  GoRoute(path: 'rules', parentNavigatorKey: _rootKey, builder: (c, s) => const CustomRulesScreen()),
                  GoRoute(path: 'tabs', parentNavigatorKey: _rootKey, builder: (c, s) => const NavTabsScreen()),
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
        GoRoute(path: '/shared-note', parentNavigatorKey: _rootKey, builder: (c, s) => const SharedNoteScreen()),
        GoRoute(path: '/personal-dates', parentNavigatorKey: _rootKey, builder: (c, s) => const PersonalDatesScreen()),
        GoRoute(path: '/alerts', parentNavigatorKey: _rootKey, builder: (c, s) => const AlertsScreen()),
        GoRoute(path: '/calendar', parentNavigatorKey: _rootKey, builder: (c, s) => const CalendarScreen()),
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
    dateLocale = s.uiLanguage == UiLanguage.en ? 'en' : 'he';
    return MaterialApp.router(
      title: 'Amud',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(s, Brightness.light),
      darkTheme: buildTheme(s, Brightness.dark),
      themeMode: s.flutterThemeMode,
      routerConfig: ref.watch(routerProvider),
      locale: s.uiLanguage.locale,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: [for (final l in UiLanguage.values) l.locale],
      builder: (context, child) => AppText(lang: s.uiLanguage, ashkenazi: s.ashkenaziSpelling, child: ReaderDevice(child: LaunchAnimation(child: child!))),
    );
  }
}

/// The first screen of each tab, in [navTabs] order.
const _tabRoots = {'/', '/siddur', '/zmanim', '/torah', '/shiurim', '/settings'};

/// Native navigation chrome: Cupertino tab bar on iOS/macOS, Material 3
/// navigation bar on phones, navigation rail on wide screens (tablet/web).
class AdaptiveShell extends ConsumerWidget {
  final StatefulNavigationShell shell;

  /// The current tab is on its first screen, so swiping moves between tabs.
  final bool atTabRoot;
  const AdaptiveShell({super.key, required this.shell, this.atTabRoot = false});

  /// The branches on the bar, in the user's order (see [NavTabsScreen]).
  /// A hidden tab opened anyway (by a link, say) shows at the end while
  /// it's open, so the bar always marks where you are.
  List<int> _tabs(List<String> ids) {
    final tabs = [for (final id in ids) navTabs.indexWhere((t) => t.$1 == id)]..removeWhere((i) => i < 0);
    return tabs.contains(shell.currentIndex) ? tabs : [...tabs, shell.currentIndex];
  }

  void _go(int branch) => shell.goBranch(branch, initialLocation: branch == shell.currentIndex);

  /// The tabs on either side, for [TabSwipe]; none while focus mode hides
  /// the navigation.
  Widget _swipeable(bool focus, List<int> tabs) {
    final i = tabs.indexOf(shell.currentIndex);
    VoidCallback? to(int j) => !atTabRoot || focus || j < 0 || j >= tabs.length
        ? null
        : () {
            analytics.event('tab_swipe', {'to': navTabs[tabs[j]].$1});
            _go(tabs[j]);
          };
    return TabSwipe(onNext: to(i + 1), onPrevious: to(i - 1), child: shell);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final tabs = _tabs(ref.watch(settingsProvider.select((s) => s.navTabs)));
    final selected = tabs.indexOf(shell.currentIndex);
    void onTap(int i) => _go(tabs[i]);
    final shown = [for (final b in tabs) navTabs[b]];
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
                selectedIndex: selected,
                onDestinationSelected: onTap,
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final (_, o, s, _, l) in shown) NavigationRailDestination(icon: Icon(o), selectedIcon: Icon(s), label: Text(context.tr(l))),
                ],
              ),
              const VerticalDivider(width: 1),
            ]),
          ),
          Expanded(child: _swipeable(focus, tabs)),
        ]),
      );
    }
    if (isCupertinoPlatform) {
      return Scaffold(
        body: _swipeable(focus, tabs),
        bottomNavigationBar: away(vertical: true, CupertinoTabBar(
          currentIndex: selected,
          onTap: onTap,
          activeColor: Theme.of(context).colorScheme.primary,
          items: [for (final (_, _, _, c, l) in shown) BottomNavigationBarItem(icon: Icon(c), label: context.tr(l))],
        )),
      );
    }
    return Scaffold(
      body: _swipeable(focus, tabs),
      bottomNavigationBar: away(
        vertical: true,
        NavigationBar(
          selectedIndex: selected,
          onDestinationSelected: onTap,
          destinations: [for (final (_, o, s, _, l) in shown) NavigationDestination(icon: Icon(o), selectedIcon: Icon(s), label: context.tr(l))],
        ),
      ),
    );
  }
}
