import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/adaptive.dart';
import '../../core/heading.dart';
import '../../core/l10n.dart';
import '../../core/settings.dart';

/// The Kodesh HaKodashim, on the Temple Mount.
const _templeLat = 31.77805, _templeLon = 35.23540;

/// Degrees from north, clockwise, from ([lat], [lon]) toward the Temple
/// Mount: along the shortest route, or with [rhumbLine] a constant bearing.
double bearingToJerusalem(double lat, double lon, {bool rhumbLine = false}) {
  double rad(double d) => d * pi / 180;
  final p1 = rad(lat), p2 = rad(_templeLat);
  var dl = rad(_templeLon - lon);
  if (dl > pi) dl -= 2 * pi;
  if (dl < -pi) dl += 2 * pi;
  final t = rhumbLine
      ? atan2(dl, log(tan(pi / 4 + p2 / 2) / tan(pi / 4 + p1 / 2)))
      : atan2(sin(dl) * cos(p2), cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl));
  return (t * 180 / pi + 360) % 360;
}

/// Kilometres from ([lat], [lon]) to the Temple Mount.
double kmToJerusalem(double lat, double lon) {
  double rad(double d) => d * pi / 180;
  final a = pow(sin(rad(_templeLat - lat) / 2), 2) + cos(rad(lat)) * cos(rad(_templeLat)) * pow(sin(rad(_templeLon - lon) / 2), 2);
  return 6371 * 2 * atan2(sqrt(a), sqrt(1 - a));
}

/// Within this many degrees either side, the reader is facing Jerusalem.
const _facing = 10.0;

final _headingProvider = StreamProvider.autoDispose<DeviceHeading>((ref) {
  final at = ref.watch(settingsProvider.select((s) => s.location));
  return deviceHeadings(latitude: at.latitude, longitude: at.longitude, elevation: at.elevation);
});

/// How far, in degrees (-180 to 180, clockwise positive), to turn to face
/// Jerusalem; null until the compass has a reading.
double? _turnBy(WidgetRef ref) {
  final heading = ref.watch(_headingProvider).valueOrNull;
  if (heading == null) return null;
  final s = ref.watch(settingsProvider);
  final bearing = bearingToJerusalem(s.location.latitude, s.location.longitude, rhumbLine: s.compassRhumbLine);
  return (bearing - heading.degrees + 540) % 360 - 180;
}

/// A small dial over the reader that points toward Jerusalem. It appears
/// once the device's compass gives a reading (so never where there is
/// none), and only while the app is in front. Tap it for more.
class ReaderCompass extends ConsumerStatefulWidget {
  const ReaderCompass({super.key});

  @override
  ConsumerState<ReaderCompass> createState() => _ReaderCompassState();
}

class _ReaderCompassState extends ConsumerState<ReaderCompass> {
  late final AppLifecycleListener _life;
  bool _front = true;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(onStateChange: (s) {
      final front = s == AppLifecycleState.resumed;
      if (front != _front) setState(() => _front = front);
    });
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    // At the Temple Mount itself there is no direction to give.
    if (!s.readerCompass || !_front || kmToJerusalem(s.location.latitude, s.location.longitude) < 0.1) return const SizedBox.shrink();
    final turn = _turnBy(ref);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: turn == null
          ? const SizedBox.shrink()
          : _Dial(
              key: const ValueKey('dial'),
              turn: turn,
              size: 48,
              onTap: () => showModalBottomSheet<void>(context: context, builder: (_) => const _CompassSheet()),
            ),
    );
  }
}

/// A needle pointing [turn] degrees from straight ahead, filled in when
/// that is Jerusalem. Gives a tick when it comes into line.
class _Dial extends StatefulWidget {
  final double turn;
  final double size;
  final VoidCallback? onTap;
  const _Dial({super.key, required this.turn, required this.size, this.onTap});

  @override
  State<_Dial> createState() => _DialState();
}

class _DialState extends State<_Dial> {
  /// The needle's angle in turns, unwrapped so that crossing south doesn't
  /// spin it all the way round.
  late double _turns = widget.turn / 360;
  late bool _facingNow = widget.turn.abs() <= _facing;

  @override
  void didUpdateWidget(_Dial old) {
    super.didUpdateWidget(old);
    final target = widget.turn / 360;
    var delta = (target - _turns) % 1;
    if (delta > 0.5) delta -= 1;
    _turns += delta;
    final facing = widget.turn.abs() <= _facing;
    if (facing && !_facingNow) HapticFeedback.selectionClick();
    _facingNow = facing;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final big = widget.size > 100;
    return Semantics(
      button: widget.onTap != null,
      label: _facingNow ? context.tr('Facing Jerusalem') : context.tr('Compass toward Jerusalem'),
      child: Tooltip(
        message: context.tr('Compass toward Jerusalem'),
        child: Material(
          shape: const CircleBorder(),
          elevation: big ? 0 : 3,
          color: _facingNow ? scheme.primaryContainer : scheme.surfaceContainerHigh.withValues(alpha: big ? 1 : 0.92),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onTap,
            child: SizedBox.square(
              dimension: widget.size,
              child: AnimatedRotation(
                turns: _turns,
                duration: const Duration(milliseconds: 180),
                child: CustomPaint(painter: _Needle(color: _facingNow ? scheme.primary : scheme.onSurfaceVariant, ticks: big ? scheme.outlineVariant : null)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Needle extends CustomPainter {
  final Color color;
  final Color? ticks;
  const _Needle({required this.color, this.ticks});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    if (ticks != null) {
      final tick = Paint()..color = ticks!..strokeWidth = 2..strokeCap = StrokeCap.round;
      for (var i = 0; i < 24; i++) {
        final a = i * pi / 12;
        final dir = Offset(sin(a), -cos(a));
        canvas.drawLine(c + dir * r * (i % 6 == 0 ? 0.8 : 0.86), c + dir * r * 0.92, tick);
      }
    }
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(c.dx, c.dy - r * 0.62)
      ..lineTo(c.dx + r * 0.3, c.dy + r * 0.42)
      ..lineTo(c.dx, c.dy + r * 0.24)
      ..lineTo(c.dx - r * 0.3, c.dy + r * 0.42)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_Needle old) => old.color != color || old.ticks != ticks;
}

class _CompassSheet extends ConsumerWidget {
  const _CompassSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);
    final turn = _turnBy(ref);
    final calibrate = ref.watch(_headingProvider).valueOrNull?.calibrate ?? false;
    final bearing = bearingToJerusalem(s.location.latitude, s.location.longitude, rhumbLine: s.compassRhumbLine).round() % 360;
    final degrees = turn?.abs().round();
    return SafeArea(
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
        Text(context.tr('Compass toward Jerusalem'), style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        Center(child: turn == null ? const SizedBox.square(dimension: 200) : _Dial(turn: turn, size: 200)),
        const SizedBox(height: 16),
        Text(
          turn == null
              ? ''
              : turn.abs() <= _facing
                  ? context.tr('Facing Jerusalem')
                  : turn > 0
                      ? context.tr('Turn right {degrees}°', {'degrees': '$degrees'})
                      : context.tr('Turn left {degrees}°', {'degrees': '$degrees'}),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        Text(context.tr('{degrees}° from north, from {place}', {'degrees': '$bearing', 'place': s.location.name}),
            textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        if (calibrate)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(context.tr('The compass needs calibrating: move the phone in a figure eight, away from metal.'),
                textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          ),
        SheetLabel(context.tr('Direction')),
        ChoiceBar<bool>(
          options: [
            (false, context.tr('Shortest route'), null),
            (true, context.tr('Constant bearing'), null),
          ],
          selected: s.compassRhumbLine,
          onChanged: (v) => n.update((x) => x.copyWith(compassRhumbLine: v)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              context.tr('The shortest route runs along the globe (northeast from America). A constant bearing keeps one compass heading the whole way (east from America).'),
              style: theme.textTheme.bodySmall),
        ),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(context.tr('Show the compass in the siddur')),
          value: s.readerCompass,
          onChanged: (v) {
            n.update((x) => x.copyWith(readerCompass: v));
            if (!v) Navigator.pop(context);
          },
        ),
      ]),
    );
  }
}
