import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hebcal/hebcal.dart';

import 'app.dart';
import 'core/fonts.dart';
import 'core/providers.dart';
import 'core/storage.dart';
import 'features/alerts/alerts.dart';
import 'features/alerts/notification_backend.dart';
import 'features/home/card_registry.dart';
import 'features/update/update_service.dart';
import 'features/home/cards/builtin_cards.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initHebcal(); // IANA tz database + learning schedules
  final storage = await Storage.open();

  // Cards are modular: each feature registers its card types here.
  final registry = CardRegistry();
  registerBuiltInCards(registry);

  final container = ProviderContainer(overrides: [
    storageProvider.overrideWithValue(storage),
    cardRegistryProvider.overrideWithValue(registry),
  ]);
  await container.read(fontsProvider.notifier).loadAll();

  runApp(UncontrolledProviderScope(container: container, child: const _Lifecycle(child: SiddurApp())));

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
    _taps = notificationTaps.stream.listen((route) => ref.read(routerProvider).go(route));
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
      ref.invalidate(nowProvider);
      ref.read(alertSchedulerProvider).reschedule();
      // Back from the "Install unknown apps" setting during an update.
      ref.read(updateProvider.notifier).resumed();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
