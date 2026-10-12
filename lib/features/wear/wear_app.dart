import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hebcal/hebcal.dart';

import '../../core/l10n.dart';
import '../../core/settings.dart';
import '../integrations/watch_prayers.dart';
import '../integrations/widget_snapshot.dart';
import '../home/today.dart';
import '../zmanim/zman_catalog.dart';

/// The watch app. Round screens clip the corners, so every screen is inset by
/// [_inset] of its width on the sides and more at the top and bottom.
class WearApp extends ConsumerWidget {
  const WearApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return AppText(
      lang: settings.uiLanguage,
      ashkenazi: settings.ashkenaziSpelling,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Colors.black,
          colorScheme: const ColorScheme.dark(primary: Color(0xFF8AB4F8)),
        ),
        home: const _Home(),
      ),
    );
  }
}

class _Round extends StatelessWidget {
  final List<Widget> children;
  const _Round({required this.children});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.fromLTRB(w * 0.14, w * 0.2, w * 0.14, w * 0.22),
        children: children,
      ),
    );
  }
}

class _Home extends ConsumerStatefulWidget {
  const _Home();

  @override
  ConsumerState<_Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<_Home> {
  Future<List<Map<String, Object?>>>? _prayers;
  int _prayersDay = 0;
  bool _locating = false;

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 20)),
      );
      final zone = (await FlutterTimezone.getLocalTimezone()).identifier;
      final il = zone == 'Asia/Jerusalem';
      ref.read(settingsProvider.notifier).update(
            (s) => s.copyWith(
              location: SavedLocation(
                name: 'Current location',
                latitude: position.latitude,
                longitude: position.longitude,
                elevation: position.altitude.clamp(0, 9000).toDouble(),
                tzid: zone,
                il: il,
              ),
            ),
          );
    } catch (_) {
      // Keep the saved location.
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final snap = ref.watch(todaySnapshotProvider);
    final resolver = ref.watch(zmanResolverProvider);
    final entry = activeWidgetEntry(buildWidgetTimeline(settings, resolver, snap.now, days: 2), snap.now);
    final day = snap.halachic.abs();
    if (_prayers == null || _prayersDay != day) {
      _prayersDay = day;
      _prayers = buildWatchPrayers(ref, HDate.fromAbs(day));
    }
    final omer = entry?['omer'] as int? ?? 0;
    final theme = Theme.of(context).textTheme;
    return _Round(children: [
      Text('${entry?['hebrewDate'] ?? ''}', textAlign: TextAlign.center, style: theme.titleLarge),
      const SizedBox(height: 6),
      Text('${entry?['parsha'] ?? ''}', textAlign: TextAlign.center, style: theme.bodyMedium),
      const SizedBox(height: 10),
      Text('${entry?['nextZman'] ?? ''}', textAlign: TextAlign.center, style: theme.bodyLarge),
      Text('${entry?['nextZmanTime'] ?? ''}', textAlign: TextAlign.center, style: theme.headlineSmall),
      if (omer > 0) ...[
        const SizedBox(height: 6),
        Text(context.tr('Omer · {n}', {'n': omer}), textAlign: TextAlign.center, style: theme.bodyMedium),
      ],
      const SizedBox(height: 10),
      FutureBuilder(
        future: _prayers,
        builder: (context, state) => Column(children: [
          for (final prayer in state.data ?? const <Map<String, Object?>>[])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: FilledButton.tonal(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _Reader(prayer: prayer))),
                child: Text(context.tr('${prayer['title']}'), textAlign: TextAlign.center),
              ),
            ),
        ]),
      ),
      OutlinedButton(
        onPressed: _locating ? null : _useMyLocation,
        child: Text(_locating ? context.tr('Locating…') : '${settings.location.name} · ${context.tr('Use my location')}', textAlign: TextAlign.center),
      ),
    ]);
  }
}

class _Reader extends StatelessWidget {
  final Map<String, Object?> prayer;
  const _Reader({required this.prayer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return _Round(children: [
      Text('${prayer['hebrewTitle']}', textAlign: TextAlign.center, textDirection: TextDirection.rtl, style: theme.titleLarge),
      const SizedBox(height: 10),
      Directionality(
        textDirection: TextDirection.rtl,
        child: Text('${prayer['text']}', textAlign: TextAlign.center, style: theme.titleLarge?.copyWith(height: 1.5)),
      ),
      const SizedBox(height: 10),
      FilledButton.tonal(onPressed: () => Navigator.of(context).pop(), child: Text(context.tr('Back'))),
    ]);
  }
}
