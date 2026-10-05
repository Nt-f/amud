import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'features/torah/shnayim_mikra_screen.dart';
import 'features/integrations/platform_runtime.dart';
import 'features/integrations/prayer_links.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hebcal/hebcal.dart';

import 'app.dart';
import 'core/analytics.dart';
import 'core/fonts.dart';
import 'core/providers.dart';
import 'core/settings.dart';
import 'core/storage.dart';
import 'features/alerts/alerts.dart';
import 'features/alerts/notification_backend.dart';
import 'features/home/card_registry.dart';
import 'features/update/update_service.dart';
import 'features/home/cards/builtin_cards.dart';
import 'features/integrations/seasonal_windows.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) AppLinks(); // Capture a cold-start link before asynchronous initialization.
  initHebcal(); // IANA tz database + learning schedules
  final storage = await Storage.open();

  // Cards are modular: each feature registers its card types here.
  final registry = CardRegistry();
  registerBuiltInCards(registry);
  registerSeasonalCards(registry);
  registerShnayimMikraCard(registry);

  final initialLink = args.map(Uri.tryParse).whereType<Uri>().map(routeFromLink).whereType<String>().firstOrNull;
  final container = ProviderContainer(overrides: [
    storageProvider.overrideWithValue(storage),
    cardRegistryProvider.overrideWithValue(registry),
  ]);
  await container.read(fontsProvider.notifier).loadAll();

  final onFlutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    analytics.error(details.exception, fatal: false);
    onFlutterError?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    analytics.error(error, fatal: true);
    return false;
  };

  runApp(UncontrolledProviderScope(container: container, child: const PlatformRuntime(child: _Lifecycle(child: SiddurApp()))));
  if (initialLink != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => openFromOutside(container.read(routerProvider), initialLink));
  }

  // Analytics starts after the first frame too; events before then wait.
  final settings = container.read(settingsProvider);
  analytics.trackScreens(container.read(routerProvider));
  analytics.event('app_launch', {'fonts': container.read(fontsProvider).length});
  unawaited(analytics.init(settings, storage));

  // Plan notifications after first frame (never blocks startup).
  Future<void>.delayed(const Duration(seconds: 1), () => container.read(alertSchedulerProvider).reschedule());
  // Look for a new release in the background (daily; Android/desktop).
  Future<void>.delayed(const Duration(seconds: 5), () => container.read(updateProvider.notifier).autoCheck());
}

/// Re-plans notifications when the app returns to the foreground (dates,
/// DST and the 64-notification iOS window move on).
class _Lifecycle extends ConsumerStatefulWidget {
  final Widget child;
  const _Lifecycle({required this.child});

  @override
  ConsumerState<_Lifecycle> createState() => _LifecycleState();
}

class _LifecycleState extends ConsumerState<_Lifecycle> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _taps = notificationTaps.stream.listen((route) {
      analytics.event('alert_tap', {'route': route});
      ref.read(routerProvider).go(route);
    });
  }

  StreamSubscription<String>? _taps;

  @override
  void dispose() {
    _taps?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      analytics.event('app_resume');
      analytics.checkIn();
      ref.invalidate(nowProvider);
      ref.read(alertSchedulerProvider).reschedule();
      // Back from the "Install unknown apps" setting during an update.
      ref.read(updateProvider.notifier).resumed();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
