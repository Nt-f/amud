import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:hebcal/hebcal.dart';
import 'package:quick_actions/quick_actions.dart';

import '../../app.dart';
import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import '../home/today.dart';
import '../zmanim/zman_catalog.dart';
import 'desktop_tray.dart';
import 'prayer_links.dart';
import 'shortcut_preferences.dart';
import 'omer_badge.dart';
import 'travel_location.dart';
import 'watch_prayers.dart';
import 'widget_snapshot.dart';
import 'web_integrations.dart';

const integrationChannel = MethodChannel('amud/integrations');
const widgetAppGroup = 'group.page.amud';

class PlatformRuntime extends ConsumerStatefulWidget {
  final Widget child;
  const PlatformRuntime({super.key, required this.child});
  @override
  ConsumerState<PlatformRuntime> createState() => _PlatformRuntimeState();
}

class _PlatformRuntimeState extends ConsumerState<PlatformRuntime>
    with WidgetsBindingObserver {
  StreamSubscription<Uri>? _links;
  late final DesktopTray _tray = DesktopTray(_navigate);
  Map<String, Object?>? _timeline;
  String? _timelineKey;
  Future<void> _pending = Future.value();
  bool _refreshAgain = false, _refreshing = false, _travelChecking = false;
  DateTime? _lastTravel;
  String? _dismissedTravel;

  bool get _mobile =>
      !kIsWeb &&
      {
        TargetPlatform.android,
        TargetPlatform.iOS,
      }.contains(defaultTargetPlatform);
  bool get _apple =>
      !kIsWeb &&
      {
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    integrationChannel.setMethodCallHandler((call) async {
      if (call.method == 'openRoute' && call.arguments is String) {
        _openLink(Uri.parse(call.arguments as String));
      }
    });
    if (!kIsWeb) {
      _links = AppLinks().uriLinkStream.listen(
        _openLink,
        onError: (Object e) => debugPrint('App link: $e'),
      );
      AppLinks().getInitialLink().then((uri) {
        if (uri != null) _openLink(uri);
      });
    }
    ref.listenManual(shortcutPreferencesProvider, (_, _) {
      if (_mobile) _setShortcuts();
    });
    ref.listenManual(omerCountedProvider, (_, _) => _scheduleRefresh());
    ref.listenManual(todaySnapshotProvider, (_, _) => _scheduleRefresh());
    ref.listenManual(settingsProvider, (previous, next) {
      _scheduleRefresh();
      if (next.travelPrompts && previous?.travelPrompts != true) _checkTravel();
    });
    ref.listenManual(customRulesProvider, (_, _) {
      _timelineKey = null;
      _scheduleRefresh();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_mobile) {
        const actions = QuickActions();
        await actions.initialize(
          (key) => _navigate('/pray/${normalizePrayer(key)}'),
        );
        await _setShortcuts();
      }
      if (_apple) await _readPendingIntent();
      final shared = await takeSharedNote();
      if (shared != null) {
        ref.read(pendingSharedNoteProvider.notifier).state = shared;
        _navigate('/shared-note');
      }
      _scheduleRefresh();
      _checkTravel();
    });
  }

  Future<void> _setShortcuts() async {
    try {
      await const QuickActions().setShortcutItems([
        for (final key in ref.read(shortcutPreferencesProvider))
          ShortcutItem(type: key, localizedTitle: prayerShortcuts[key]!),
      ]);
    } catch (e) {
      debugPrint('Launcher shortcuts: $e');
    }
  }

  void _navigate(String route) {
    if (mounted) openFromOutside(ref.read(routerProvider), route);
  }

  void _openLink(Uri uri) {
    final route = routeFromLink(uri);
    if (route != null) _navigate(route);
  }

  Future<void> _readPendingIntent() async {
    try {
      final route = await integrationChannel.invokeMethod<String>(
        'takePendingRoute',
      );
      if (route != null) _openLink(Uri.parse(route));
    } on MissingPluginException {
      /* Other platforms have no App Intents. */
    }
  }

  void _scheduleRefresh() {
    if (!mounted) return;
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    _pending = _pending.then((_) async {
      do {
        _refreshAgain = false;
        try {
          await _refresh();
        } catch (e) {
          debugPrint('Platform integration: $e');
        }
      } while (_refreshAgain && mounted);
      _refreshing = false;
    });
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final s = ref.read(settingsProvider);
    final snap = ref.read(todaySnapshotProvider);
    final resolver = ref.read(zmanResolverProvider);
    final key =
        '${snap.civil}|${jsonEncode(s.toJson())}|${jsonEncode(ref.read(customZmanimProvider).map((z) => z.toJson()).toList())}';
    if (_timeline == null || key != _timelineKey) {
      final timeline = buildWidgetTimeline(s, resolver, snap.now);
      if (_mobile || _apple) {
        timeline['prayerDays'] = [
          for (var day = 0; day < 8; day++)
            {
              'day': snap.civil.addDays(day).abs,
              'prayers': await buildWatchPrayers(
                ref,
                HDate.fromAbs(snap.civil.addDays(day).abs),
              ),
            },
        ];
        if (!mounted) return;
      }
      final json = jsonEncode(timeline);
      if (_mobile) {
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          await HomeWidget.setAppGroupId(widgetAppGroup);
        }
        await HomeWidget.saveWidgetData<String>('amudTimeline', json);
        await HomeWidget.updateWidget(
          androidName: 'AmudWidgetProvider',
          iOSName: 'AmudWidget',
        );
      }
      if (_mobile || _apple) {
        try {
          await integrationChannel.invokeMethod<void>('publishTimeline', json);
        } catch (e) {
          debugPrint('Watch/widget publishing: $e');
        }
      }
      _timeline = timeline;
      _timelineKey = key;
    }
    final entry = activeWidgetEntry(_timeline!, snap.now);
    try {
      await _tray.update(s.desktopTray, entry);
    } catch (e) {
      debugPrint('Desktop tray: $e');
    }
    await updateOmerBadge(
      s.omerBadge && ref.read(omerCountedProvider) != snap.halachic.abs()
          ? (entry?['omer'] as int? ?? 0)
          : 0,
    );
  }

  Future<void> _checkTravel() async {
    if (_travelChecking ||
        !mounted ||
        !ref.read(settingsProvider).travelPrompts) {
      return;
    }
    if (_lastTravel != null &&
        DateTime.now().difference(_lastTravel!) < const Duration(hours: 1)) {
      return;
    }
    _travelChecking = true;
    _lastTravel = DateTime.now();
    try {
      final saved = ref.read(settingsProvider).location;
      final suggestion = await travelSuggestion(saved);
      if (!mounted ||
          suggestion == null ||
          ref.read(settingsProvider).location != saved) {
        return;
      }
      final key =
          '${suggestion.latitude.toStringAsFixed(1)}|${suggestion.longitude.toStringAsFixed(1)}|${suggestion.tzid}';
      if (key == _dismissedTravel) return;
      final context = ref
          .read(routerProvider)
          .routerDelegate
          .navigatorKey
          .currentContext;
      if (context == null || !context.mounted) return;
      var israel = saved.il;
      final use = await showDialog<bool>(
        context: context,
        builder: (c) => StatefulBuilder(
          builder: (c, update) => AlertDialog(
            title: Text(c.tr('Update zmanim for this location?')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${saved.name} → ${suggestion.latitude.toStringAsFixed(2)}, ${suggestion.longitude.toStringAsFixed(2)} · ${suggestion.tzid}',
                ),
                SwitchListTile.adaptive(
                  title: Text(c.tr('Israel customs')),
                  value: israel,
                  onChanged: (v) => update(() => israel = v),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(c.tr('Keep saved location')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(c.tr('Use current location')),
              ),
            ],
          ),
        ),
      );
      if (!mounted) return;
      if (use == true) {
        ref
            .read(settingsProvider.notifier)
            .update(
              (s) => s.copyWith(
                location: SavedLocation(
                  name: suggestion.name,
                  latitude: suggestion.latitude,
                  longitude: suggestion.longitude,
                  elevation: suggestion.elevation,
                  tzid: suggestion.tzid,
                  il: israel,
                ),
              ),
            );
      } else {
        _dismissedTravel = key;
      }
    } catch (e) {
      debugPrint('Travel location check: $e');
    } finally {
      _travelChecking = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleRefresh();
      _checkTravel();
      if (_apple) _readPendingIntent();
    }
  }

  @override
  void dispose() {
    _links?.cancel();
    integrationChannel.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_tray.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
