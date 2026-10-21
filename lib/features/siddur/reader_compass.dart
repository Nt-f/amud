import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/heading.dart';
import '../../core/l10n.dart';
import '../../core/settings.dart';

/// Mizrach: due east, in degrees from north.
const _east = 90.0;

/// Within this many degrees either side, the reader is facing east.
const _facing = 10.0;

final _headingProvider = StreamProvider.autoDispose<DeviceHeading>((ref) {
  final at = ref.watch(settingsProvider.select((s) => s.location));
  return deviceHeadings(latitude: at.latitude, longitude: at.longitude, elevation: at.elevation);
});

/// Whether the app is in front: the compass only listens while it is.
final _inFrontProvider = Provider.autoDispose<bool>((ref) {
  final state = SchedulerBinding.instance.lifecycleState;
  final front = state == null || state == AppLifecycleState.resumed;
  final life = AppLifecycleListener(onStateChange: (s) {
    if ((s == AppLifecycleState.resumed) != front) ref.invalidateSelf();
  });
  ref.onDispose(life.dispose);
  return front;
});

/// How far, in degrees (-180 to 180, clockwise positive), to turn to face
/// east. Null where the reader's compass isn't shown (turned off, the app
/// behind others, or no reading from the device), so the reader leaves no
/// room for it.
final readerCompassTurnProvider = Provider.autoDispose<double?>((ref) {
  final s = ref.watch(settingsProvider);
  if (!compassPossible || !s.readerCompass || !ref.watch(_inFrontProvider)) return null;
  final heading = ref.watch(_headingProvider).valueOrNull;
  if (heading == null) return null;
  return (_east - heading.degrees + 540) % 360 - 180;
});

/// A small dial in the reader's app bar that points east,
/// while [readerCompassTurnProvider] has a reading. Tap it for more.
class ReaderCompass extends ConsumerWidget {
  const ReaderCompass({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final turn = ref.watch(readerCompassTurnProvider);
    if (turn == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: _Dial(
        turn: turn,
        size: 36,
        onTap: () => showModalBottomSheet<void>(context: context, builder: (_) => const _CompassSheet()),
      ),
    );
  }
}

/// A needle pointing [turn] degrees from straight ahead, filled in when
/// that is east. Gives a tick when it comes into line.
class _Dial extends StatefulWidget {
  final double turn;
  final double size;
  final VoidCallback? onTap;
  const _Dial({required this.turn, required this.size, this.onTap});

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
      label: _facingNow ? context.tr('Facing east') : context.tr('Compass to the east'),
      child: Tooltip(
        message: context.tr('Compass to the east'),
        child: Material(
          shape: const CircleBorder(),
          color: _facingNow ? scheme.primaryContainer : big ? scheme.surfaceContainerHigh : Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onTap,
            child: SizedBox.square(
              dimension: widget.size,
              child: AnimatedRotation(
                turns: _turns,
                duration: const Duration(milliseconds: 180),
                child: CustomPaint(
                    painter: _Needle(
                        color: _facingNow ? scheme.primary : scheme.onSurfaceVariant,
                        ticks: big ? scheme.outlineVariant : null,
                        ring: big || _facingNow ? null : scheme.outlineVariant)),
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
  final Color? ring;
  const _Needle({required this.color, this.ticks, this.ring});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    if (ring != null) {
      canvas.drawCircle(c, r - 1, Paint()..color = ring!..style = PaintingStyle.stroke..strokeWidth = 1.5);
    }
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
  bool shouldRepaint(_Needle old) => old.color != color || old.ticks != ticks || old.ring != ring;
}

class _CompassSheet extends ConsumerWidget {
  const _CompassSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);
    final turn = ref.watch(readerCompassTurnProvider);
    final calibrate = ref.watch(_headingProvider).valueOrNull?.calibrate ?? false;
    final degrees = turn?.abs().round();
    return SafeArea(
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
        Text(context.tr('Compass to the east'), style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        Center(child: turn == null ? const SizedBox.square(dimension: 200) : _Dial(turn: turn, size: 200)),
        const SizedBox(height: 16),
        Text(
          turn == null
              ? ''
              : turn.abs() <= _facing
                  ? context.tr('Facing east')
                  : turn > 0
                      ? context.tr('Turn right {degrees}°', {'degrees': '$degrees'})
                      : context.tr('Turn left {degrees}°', {'degrees': '$degrees'}),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        Text(context.tr('Due east, 90° from north'), textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        if (calibrate)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(context.tr('The compass needs calibrating: move the phone in a figure eight, away from metal.'),
                textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          ),
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
