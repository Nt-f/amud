import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app.dart';
import '../../core/settings.dart';
import 'prayer_links.dart';

/// Owns device state independently of routes retained beneath the reader.
class ReaderDevice extends ConsumerStatefulWidget {
  final Widget child;
  const ReaderDevice({super.key, required this.child});
  @override
  ConsumerState<ReaderDevice> createState() => _ReaderDeviceState();
}

class _ReaderDeviceState extends ConsumerState<ReaderDevice>
    with WidgetsBindingObserver {
  Future<void> _pending = Future.value();
  bool _resumed = true;
  (bool, bool, bool)? _last;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(routerProvider).routeInformationProvider.addListener(_sync);
    ref.listenManual(
      settingsProvider.select((s) => (s.keepReaderAwake, s.fullscreenReader, s.readerDnd)),
      (_, _) => _sync(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  void _sync() {
    if (!mounted) return;
    final s = ref.read(settingsProvider);
    final reading =
        _resumed &&
        isReaderRoute(
          ref.read(routerProvider).routeInformationProvider.value.uri.path,
        );
    final state = (reading && s.keepReaderAwake, reading && s.fullscreenReader, reading && s.readerDnd);
    if (_last == state) return;
    _last = state;
    _pending = _pending.then((_) async {
      try {
        await WakelockPlus.toggle(enable: state.$1);
      } catch (e) {
        debugPrint('Reader wake lock: $e');
      }
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        try {
          if (defaultTargetPlatform == TargetPlatform.android) {
            await const MethodChannel(
              'amud/integrations',
            ).invokeMethod<void>('setReaderFullscreen', state.$2);
            // Without access granted this does nothing; settings asks for it.
            await const MethodChannel('amud/integrations').invokeMethod<bool>('setReaderDnd', state.$3);
          } else {
            await SystemChrome.setEnabledSystemUIMode(
              state.$2 ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
            );
          }
        } catch (e) {
          debugPrint('Reader system bars: $e');
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    // Android/the browser may have revoked the wake lock while suspended.
    _last = null;
    _sync();
  }

  @override
  void dispose() {
    if (_last?.$3 ?? false) {
      unawaited(const MethodChannel('amud/integrations').invokeMethod<bool>('setReaderDnd', false).catchError((Object e) {
        debugPrint('$e');
        return null;
      }));
    }
    ref.read(routerProvider).routeInformationProvider.removeListener(_sync);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(
      _pending.then((_) => WakelockPlus.disable()).catchError((Object e) {
        debugPrint('$e');
      }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Android: whether the app may change Do Not Disturb.
Future<bool> readerDndAccess() async {
  try {
    return await const MethodChannel('amud/integrations').invokeMethod<bool>('readerDndAccess') ?? false;
  } catch (_) {
    return false;
  }
}

/// Android: the system screen that grants Do Not Disturb access. Returns
/// once the user comes back to the app.
Future<void> openReaderDndSettings() async {
  try {
    await const MethodChannel('amud/integrations').invokeMethod<void>('openReaderDndSettings');
    // The settings screen is another activity: wait until we're back.
    final done = Completer<void>();
    late final AppLifecycleListener listener;
    listener = AppLifecycleListener(onResume: () {
      listener.dispose();
      if (!done.isCompleted) done.complete();
    });
    await done.future.timeout(const Duration(minutes: 5), onTimeout: listener.dispose);
  } catch (e) {
    debugPrint('DND settings: $e');
  }
}
