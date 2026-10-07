import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hebcal/hebcal.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/l10n.dart';
import '../../core/adaptive.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/search.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../alerts/alert_editor.dart';
import 'custom_zman_editor.dart';
import 'zman_catalog.dart';

final _zmanimDateProvider = StateProvider<PlainDate?>((ref) => null);
final _showAllProvider = StateProvider<bool>((ref) => false);

class ZmanimScreen extends ConsumerWidget {
  const ZmanimScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final civil = ref.watch(todayProvider);
    final date = ref.watch(_zmanimDateProvider) ?? civil;
    final isToday = date == civil;
    final s = ref.watch(settingsProvider);
    final loc = ref.watch(locationProvider);
    final z = ref.watch(zmanimProvider(date));
    final custom = ref.watch(customZmanimProvider);
    final names = ref.watch(zmanResolverProvider);
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final showAll = ref.watch(_showAllProvider);
    final hd = HDate.fromAbs(date.abs);
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width > 900;

    // A search looks through every zman, whatever the opinion setting.
    final query = SearchQuery(ref.watch(pageSearchProvider('zmanim')));
    final searching = !query.isEmpty;
    final defs = searching
        ? [for (final d in builtInZmanim) if (query.matches([names.name(d.key), d.en, d.he, d.opinion])) d]
        : [for (final d in builtInZmanim) if (showAll || d.defaultFor.contains(s.opinion)) d];
    final customShown = searching ? [for (final c in custom) if (query.matches([c.name, c.describe()])) c] : custom;
    final times = {for (final d in defs) d.key: d.compute(z)};
    String? nextKey;
    if (isToday) {
      DateTime? best;
      for (final e in times.entries) {
        if (e.value != null && e.value!.isAfter(now) && (best == null || e.value!.isBefore(best))) {
          best = e.value;
          nextKey = e.key;
        }
      }
    }

    final list = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final g in ZmanGroup.values)
        if (defs.any((d) => d.group == g)) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
            child: Text(context.term(_groupName(g)), style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
          ),
          Card(
            child: Column(children: [
              for (final d in defs.where((d) => d.group == g))
                _ZmanRow(
                  name: names.name(d.key),
                  he: d.he,
                  opinion: d.opinion,
                  time: times[d.key],
                  loc: loc,
                  hour12: s.hour12,
                  isNext: d.key == nextKey,
                  passed: isToday && times[d.key] != null && times[d.key]!.isBefore(now),
                  onTap: () => _zmanActions(context, ref, d.key, names.name(d.key)),
                ),
            ]),
          ),
        ],
      if (searching && defs.isEmpty && customShown.isEmpty)
        Padding(
          padding: const EdgeInsets.all(32),
          child: Text(context.tr('Nothing found for “{q}”', {'q': query.raw}),
              textAlign: TextAlign.center, style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.outline)),
        ),
      if (!searching || customShown.isNotEmpty)
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
        child: Row(children: [
          Expanded(child: Text(context.tr('My zmanim'), style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary))),
          TextButton.icon(
            onPressed: () => showCustomZmanEditor(context, ref),
            icon: const Icon(Icons.add, size: 18),
            label: Text(context.tr('Custom zman')),
          ),
        ]),
      ),
      if (customShown.isNotEmpty)
        Card(
          child: Column(children: [
            for (final c in customShown)
              _ZmanRow(
                name: c.name,
                he: c.describe(),
                time: c.compute(z),
                loc: loc,
                hour12: s.hour12,
                isNext: false,
                passed: isToday && (c.compute(z)?.isBefore(now) ?? false),
                onTap: () => _zmanActions(context, ref, c.key, c.name, custom: c),
              ),
          ]),
        ),
    ]);

    final side = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _SunArcCard(z: z, loc: loc, now: isToday ? now : null, hour12: s.hour12),
      const SizedBox(height: 12),
      _SpecialTimes(date: date, hd: hd),
    ]);

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.tr('Zmanim')),
          Text(loc.getName() ?? '', style: theme.textTheme.bodySmall),
        ]),
        actions: [
          IconButton(tooltip: context.tr('Alerts'), icon: const Icon(Icons.notifications_active_outlined), onPressed: () => context.push('/alerts')),
          IconButton(tooltip: context.tr('Location'), icon: const Icon(Icons.place_outlined), onPressed: () => context.push('/settings/location')),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(PageSearchBar.height),
          child: PageSearchBar(page: 'zmanim', hint: context.tr('Search zmanim')),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(wide ? 32 : 16, 8, wide ? 32 : 16, 32),
        children: [
          _DateNav(date: date, hd: hd, isToday: isToday),
          const SizedBox(height: 8),
          // While searching, the results come first.
          if (!searching)
          ChoiceBar<Object>(
            options: [
              (ZmanimOpinion.gra, 'GRA', null),
              (ZmanimOpinion.mga, 'MGA', null),
              (ZmanimOpinion.baalHatanya, context.term('Baal HaTanya'), null),
              ('all', context.tr('All'), null),
            ],
            selected: showAll ? 'all' : s.opinion,
            onChanged: (sel) {
              if (sel == 'all') {
                ref.read(_showAllProvider.notifier).state = true;
              } else {
                ref.read(_showAllProvider.notifier).state = false;
                ref.read(settingsProvider.notifier).update((x) => x.copyWith(opinion: sel as ZmanimOpinion));
              }
            },
          ),
          const SizedBox(height: 8),
          if (searching)
            list
          else if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 5, child: list),
              const SizedBox(width: 24),
              Expanded(flex: 4, child: Padding(padding: const EdgeInsets.only(top: 16), child: side)),
            ])
          else ...[
            side,
            list,
          ],
          const SizedBox(height: 16),
          Text(
            'Calculated on-device with the NOAA algorithm (Hebcal port). '
            '${s.useElevation ? 'Elevation-adjusted sunrise/sunset. ' : ''}Times may differ slightly from your local luach; consult your rav.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  static String _groupName(ZmanGroup g) => switch (g) {
        ZmanGroup.dawn => 'Dawn',
        ZmanGroup.morning => 'Morning',
        ZmanGroup.afternoon => 'Afternoon',
        ZmanGroup.evening => 'Evening',
        ZmanGroup.night => 'Night',
        ZmanGroup.shabbat => 'Shabbat & Yom Tov',
      };

  void _zmanActions(BuildContext context, WidgetRef ref, String key, String name, {CustomZman? custom}) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(name, style: Theme.of(ctx).textTheme.titleMedium)),
          ListTile(
            leading: const Icon(Icons.add_alert_outlined),
            title: Text(context.tr('Notify me')),
            subtitle: Text(context.tr('Set a reminder before or after this zman')),
            onTap: () {
              Navigator.pop(ctx);
              showAlertEditor(context, ref, zmanKey: key);
            },
          ),
          if (custom != null) ...[
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(context.tr('Edit custom zman')),
              onTap: () {
                Navigator.pop(ctx);
                showCustomZmanEditor(context, ref, existing: custom);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(context.tr('Delete custom zman')),
              onTap: () {
                ref.read(customZmanimProvider.notifier).remove(custom.id);
                Navigator.pop(ctx);
              },
            ),
          ],
        ]),
      ),
    );
  }
}

class _DateNav extends ConsumerWidget {
  final PlainDate date;
  final HDate hd;
  final bool isToday;
  const _DateNav({required this.date, required this.hd, required this.isToday});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final il = ref.watch(settingsProvider.select((s) => s.location.il));
    final hol = getHolidaysOnDate(hd, il).where((e) => !e.hasFlag(Flags.yomKippurKatan) && !e.hasFlag(Flags.behab));
    void go(int d) => ref.read(_zmanimDateProvider.notifier).state = date.addDays(d);
    final halachic = ref.watch(halachicTodayProvider);
    final tonight = isToday && !halachic.isSameDate(hd) ? halachic : null;
    return Row(children: [
      IconButton(onPressed: () => go(-1), icon: const Icon(Icons.chevron_left)),
      Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final p = await showDatePicker(context: context, initialDate: date.toDateTime(), firstDate: DateTime(1900), lastDate: DateTime(2200));
            if (p != null) ref.read(_zmanimDateProvider.notifier).state = PlainDate.fromDateTime(p);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(children: [
              Text(formatPlainDate(date), style: theme.textTheme.titleMedium),
              Text('${hd.render(context.hebcalLocale)} · ${hd.renderGematriya(true)}', style: theme.textTheme.bodySmall),
              if (tonight != null)
                Text(context.tr('Tonight: {date}', {'date': '${tonight.render(context.hebcalLocale)} · ${tonight.renderGematriya(true)}'}),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
              if (hol.isNotEmpty)
                Text(hol.map((e) => e.render(context.hebcalLocale)).join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.tertiary), textAlign: TextAlign.center),
            ]),
          ),
        ),
      ),
      if (!isToday)
        TextButton(onPressed: () => ref.read(_zmanimDateProvider.notifier).state = null, child: Text(context.tr('Today'))),
      IconButton(onPressed: () => go(1), icon: const Icon(Icons.chevron_right)),
    ]);
  }
}

class _ZmanRow extends StatelessWidget {
  final String name;
  final String he;
  final String? opinion;
  final DateTime? time;
  final Location loc;
  final bool? hour12;
  final bool isNext;
  final bool passed;
  final VoidCallback onTap;
  const _ZmanRow({
    required this.name,
    required this.he,
    this.opinion,
    required this.time,
    required this.loc,
    required this.hour12,
    required this.isNext,
    required this.passed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = SiddurColors.of(context);
    final color = passed ? theme.disabledColor : (isNext ? theme.colorScheme.primary : null);
    return InkWell(
      onTap: onTap,
      child: Container(
        color: isNext ? colors.todayFill : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          if (isNext) Padding(padding: const EdgeInsets.only(right: 8), child: Icon(Icons.play_arrow, size: 16, color: colors.todayBar)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: theme.textTheme.bodyLarge?.copyWith(color: color, fontWeight: isNext ? FontWeight.w700 : null)),
              Text(opinion == null ? he : '$he · $opinion', style: theme.textTheme.bodySmall?.copyWith(color: passed ? theme.disabledColor : null)),
            ]),
          ),
          Text(formatTime(time, loc, hour12: hour12),
              style: theme.textTheme.titleMedium?.copyWith(
                  color: color, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }
}

/// The day's sky: its colors follow the sun from alot through netz,
/// midday, shkiah and tzeit; by day the sun crosses its arc between netz
/// and shkiah, by night the moon (in its phase) crosses the sky between
/// them, under twinkling stars. It moves gently unless the device asks
/// for less motion.
class _SunArcCard extends StatefulWidget {
  final Zmanim z;
  final Location loc;
  final DateTime? now;
  final bool? hour12;
  const _SunArcCard({required this.z, required this.loc, required this.now, required this.hour12});

  @override
  State<_SunArcCard> createState() => _SunArcCardState();
}

class _SunArcCardState extends State<_SunArcCard> with SingleTickerProviderStateMixin {
  // A slow loop for the twinkle, the drifting clouds and the shooting star.
  late final _clock = AnimationController(vsync: this, duration: const Duration(seconds: 24));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _clock.stop();
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final z = widget.z;
    final now = widget.now;
    final rise = z.sunrise();
    final set = z.sunset();
    final alot = z.alotHaShachar();
    final tzeit = z.tzeit();
    final theme = Theme.of(context);
    final sky = _Sky.at(now ?? (rise != null && set != null ? rise.add(set.difference(rise) ~/ 2) : null), alot: alot, rise: rise, set: set, tzeit: tzeit);
    final dayLen = rise != null && set != null ? set.difference(rise) : null;
    String t(DateTime? d) => formatTime(d, widget.loc, hour12: widget.hour12);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _SkyPainter(sky: sky, moonPhase: now == null ? null : _moonPhase(now), clock: _clock, motion: !MediaQuery.disableAnimationsOf(context)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(children: [
            const SizedBox(height: 138),
            DefaultTextStyle(
              style: theme.textTheme.bodySmall!.copyWith(color: Colors.white, shadows: _legible),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _cap(context.term('Alot'), t(alot)),
                _cap('Netz', t(rise)),
                _cap('Shkiah', t(set)),
                _cap(context.term('Tzeit'), t(tzeit)),
              ]),
            ),
            if (dayLen != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Day ${dayLen.inHours}h ${dayLen.inMinutes % 60}m · shaah zmanit ${(dayLen.inSeconds / 12 / 60).toStringAsFixed(1)} min',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70, shadows: _legible),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  /// A soft shadow under the times, so they read on the land.
  static const _legible = [Shadow(color: Color(0x73000000), blurRadius: 6)];

  // Shrinks rather than overflowing on narrow phones and with large text.
  Widget _cap(String a, String b) => Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(children: [Text(a), Text(b, style: const TextStyle(fontWeight: FontWeight.w700))]),
        ),
      );
}

/// The moon's age as a fraction of its month: 0 new, 0.5 full. From the
/// mean synodic month and a known new moon; close enough to draw it.
double _moonPhase(DateTime t) {
  const synodic = 29.530588853;
  final days = t.toUtc().difference(DateTime.utc(2000, 1, 6, 18, 14)).inMinutes / 1440;
  return (days / synodic) % 1;
}

/// Where the sky is at a moment: its colors, and where the sun or moon is
/// on its arc (0 at the eastern horizon, 1 at the western).
class _Sky {
  final Color top;
  final Color bottom;

  /// A glow along the horizon at dawn and dusk.
  final Color glow;

  /// The sun's place on its arc, by day; null at night.
  final double? sun;

  /// The moon's place across the night; null by day.
  final double? moon;

  /// How dark it is: 0 by day, 1 at night, for the stars and the text.
  final double night;
  const _Sky(this.top, this.bottom, this.glow, {this.sun, this.moon, required this.night});

  bool get dark => night > 0.45;

  static const _night = (Color(0xFF050A24), Color(0xFF16204A));
  static const _dawn = (Color(0xFF283271), Color(0xFFE79A86));
  static const _sunrise = (Color(0xFF5C8FD8), Color(0xFFFFCB8E));
  static const _day = (Color(0xFF3F97E3), Color(0xFFBFE4FF));
  static const _golden = (Color(0xFF5E86CC), Color(0xFFFFC77D));
  static const _sunset = (Color(0xFF3A3A86), Color(0xFFFF8358));
  static const _dusk = (Color(0xFF151A48), Color(0xFF5B3C7E));

  factory _Sky.at(DateTime? now, {DateTime? alot, DateTime? rise, DateTime? set, DateTime? tzeit}) {
    if (now == null || rise == null || set == null) return _Sky(_day.$1, _day.$2, Colors.transparent, night: 0);
    final a = alot ?? rise.subtract(const Duration(minutes: 72));
    final tz = tzeit ?? set.add(const Duration(minutes: 40));
    final hour = const Duration(hours: 1);
    // Key moments and their colors; the sky blends between neighbours.
    final stops = <(DateTime, (Color, Color), Color, double)>[
      (a.subtract(hour), _night, Colors.transparent, 1),
      (a, _night, const Color(0x00E79A86), 1),
      (rise.subtract(const Duration(minutes: 20)), _dawn, const Color(0x66FF9A7A), 0.6),
      (rise, _sunrise, const Color(0x55FFB36B), 0.15),
      (rise.add(hour), _day, Colors.transparent, 0),
      (set.subtract(hour), _day, Colors.transparent, 0),
      (set.subtract(const Duration(minutes: 25)), _golden, const Color(0x44FFB45C), 0.05),
      (set, _sunset, const Color(0x77FF6E4A), 0.3),
      (tz, _dusk, const Color(0x337A4AA0), 0.8),
      (tz.add(hour), _night, Colors.transparent, 1),
    ];
    var colors = _night;
    var glow = Colors.transparent;
    var night = 1.0;
    for (var i = 0; i < stops.length - 1; i++) {
      final (t0, c0, g0, n0) = stops[i];
      final (t1, c1, g1, n1) = stops[i + 1];
      if (!now.isBefore(t0) && now.isBefore(t1)) {
        final f = now.difference(t0).inSeconds / t1.difference(t0).inSeconds;
        colors = (Color.lerp(c0.$1, c1.$1, f)!, Color.lerp(c0.$2, c1.$2, f)!);
        glow = Color.lerp(g0, g1, f)!;
        night = n0 + (n1 - n0) * f;
        break;
      }
    }
    final day = set.difference(rise).inSeconds;
    final sun = now.difference(rise).inSeconds / day;
    double? moon;
    if (sun < 0 || sun > 1) {
      // Across the night, from shkiah to the next netz (a day on).
      final dusk = sun > 1 ? set : set.subtract(const Duration(days: 1));
      final dawn = sun > 1 ? rise.add(const Duration(days: 1)) : rise;
      moon = now.difference(dusk).inSeconds / dawn.difference(dusk).inSeconds;
    }
    return _Sky(colors.$1, colors.$2, glow, sun: sun >= -0.06 && sun <= 1.06 ? sun : null, moon: moon, night: night);
  }
}

class _SkyPainter extends CustomPainter {
  final _Sky sky;
  final double? moonPhase;
  final Animation<double> clock;
  final bool motion;
  _SkyPainter({required this.sky, required this.moonPhase, required this.clock, required this.motion}) : super(repaint: clock);

  // The same stars every night: placed once from a fixed seed.
  static final _stars = () {
    final r = math.Random(5779);
    return [for (var i = 0; i < 70; i++) (r.nextDouble(), r.nextDouble() * 0.78, 0.5 + r.nextDouble() * 1.1, r.nextDouble() * math.pi * 2)];
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final t = motion ? clock.value : 0.0;
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [sky.top, sky.bottom]).createShader(rect));

    // The arc, its horizon at the foot of the drawing.
    final horizonY = 146.0;
    final center = Offset(w / 2, horizonY);
    final r = math.min(w / 2 - 28, horizonY - 26);
    Offset on(double p, {double lift = 1}) {
      final angle = math.pi + p * math.pi;
      return Offset(center.dx + r * math.cos(angle), center.dy + r * lift * math.sin(angle));
    }

    // Glow along the horizon at dawn and dusk, on the side the sun is.
    if (sky.glow.a > 0) {
      // Dawn in the east (the left, where the arc starts), dusk in the west.
      final east = sky.sun != null ? sky.sun! < 0.5 : (sky.moon ?? 0) > 0.5;
      final at = Offset(east ? w * 0.18 : w * 0.82, horizonY);
      canvas.drawCircle(at, w * 0.7,
          Paint()..shader = RadialGradient(colors: [sky.glow, sky.glow.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: at, radius: w * 0.7)));
    }

    // Stars, fading in with the dark, each twinkling at its own pace.
    if (sky.night > 0.05) {
      for (final (i, (x, y, s, ph)) in _stars.indexed) {
        final twinkle = 0.55 + 0.45 * math.sin(t * math.pi * 2 * (2 + i % 5) + ph);
        final a = (sky.night * twinkle).clamp(0.0, 1.0);
        final p = Offset(x * w, y * h);
        canvas.drawCircle(p, s, Paint()..color = Colors.white.withValues(alpha: a * 0.9));
        if (s > 1.4) canvas.drawCircle(p, s * 3, Paint()..color = Colors.white.withValues(alpha: a * 0.08));
      }
      // Now and then a shooting star, once around the loop.
      final st = (t * 3) % 1;
      if (sky.night > 0.7 && st < 0.12) {
        final f = st / 0.12;
        final start = Offset(w * 0.25, h * 0.12);
        final head = start + Offset(w * 0.32 * f, h * 0.18 * f);
        final tail = head - Offset(w * 0.08, h * 0.045);
        canvas.drawLine(
            tail,
            head,
            Paint()
              ..strokeWidth = 1.6
              ..strokeCap = StrokeCap.round
              ..shader = LinearGradient(colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: (1 - f) * 0.9)])
                  .createShader(Rect.fromPoints(tail, head)));
      }
    }

    // Clouds drifting by day.
    if (sky.night < 0.6) {
      final a = (1 - sky.night / 0.6) * 0.55;
      for (final (i, (y, s, speed)) in const [(0.18, 1.0, 1), (0.36, 0.75, 2), (0.1, 0.6, 1)].indexed) {
        final x = ((i * 0.37 + t * speed) % 1.3 - 0.15) * w;
        _cloud(canvas, Offset(x, y * h), 18 * s, Colors.white.withValues(alpha: a));
      }
    }

    // The path: dashed by night, a soft line by day.
    final path = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = (sky.dark ? Colors.white : const Color(0xFFB35A00)).withValues(alpha: sky.dark ? 0.25 : 0.45);
    canvas.drawArc(Rect.fromCircle(center: center, radius: r), math.pi, math.pi, false, path);


    // The sun by day, with a slow-turning glow; the moon by night.
    if (sky.sun case final p?) {
      final pos = on(p.clamp(-0.06, 1.06));
      final low = 1 - math.sin(math.pi * p.clamp(0.0, 1.0)); // 1 at the horizon
      final core = Color.lerp(const Color(0xFFFFE27A), const Color(0xFFFF8A3D), low)!;
      canvas.drawCircle(pos, 34, Paint()..shader = RadialGradient(colors: [core.withValues(alpha: 0.45), core.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: pos, radius: 34)));
      final rays = Paint()
        ..color = core.withValues(alpha: 0.35)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 12; i++) {
        final a = t * math.pi * 2 / 3 + i * math.pi / 6;
        canvas.drawLine(pos + Offset(math.cos(a), math.sin(a)) * 15, pos + Offset(math.cos(a), math.sin(a)) * (i.isEven ? 23 : 20), rays);
      }
      canvas.drawCircle(pos, 11, Paint()..color = core);
    } else if (sky.moon case final m?) {
      final pos = on(m.clamp(0.0, 1.0), lift: 0.92);
      canvas.drawCircle(pos, 30, Paint()..shader = RadialGradient(colors: [const Color(0x55DDE6FF), const Color(0x00DDE6FF)]).createShader(Rect.fromCircle(center: pos, radius: 30)));
      _moon(canvas, pos, 11, moonPhase ?? 0.5);
    }

    // The land, in front of the sun and moon so they rise and set behind
    // it: hills in two layers, tinted by the sky and dark enough under the
    // times to read them in white.
    final land = Color.lerp(const Color(0xFF1E3A34), const Color(0xFF060A1C), sky.night)!;
    _hills(canvas, size, horizonY - 4, Color.lerp(sky.bottom, land, 0.55)!, 0.0, 9);
    _hills(canvas, size, horizonY + 4, Color.lerp(sky.bottom, land, 0.82)!, 1.7, 7);
  }

  /// The moon at [phase]: the dark disc faint, the lit part bright, the
  /// terminator an ellipse (waxing lit on the right, waning on the left).
  void _moon(Canvas canvas, Offset c, double r, double phase) {
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF2A3360));
    final waxing = phase < 0.5;
    final side = waxing ? 1.0 : -1.0;
    // The terminator's reach toward the lit edge: all of it when new, none
    // at the quarters, across to the far edge when full.
    final k = r * math.cos(2 * math.pi * phase);
    final lit = Path();
    const n = 32;
    for (var i = 0; i <= n; i++) {
      final a = -math.pi / 2 + math.pi * i / n;
      final p = c + Offset(side * r * math.cos(a), r * math.sin(a));
      i == 0 ? lit.moveTo(p.dx, p.dy) : lit.lineTo(p.dx, p.dy);
    }
    for (var i = n; i >= 0; i--) {
      final a = -math.pi / 2 + math.pi * i / n;
      lit.lineTo(c.dx + side * k * math.cos(a), c.dy + r * math.sin(a));
    }
    lit.close();
    canvas.drawPath(lit, Paint()..color = const Color(0xFFF4F1E1));
    // A couple of maria, faint, for texture.
    canvas.save();
    canvas.clipPath(lit);
    final mare = Paint()..color = const Color(0x22000000);
    canvas.drawCircle(c + Offset(-r * 0.3, -r * 0.25), r * 0.28, mare);
    canvas.drawCircle(c + Offset(r * 0.25, r * 0.3), r * 0.2, mare);
    canvas.restore();
  }

  void _cloud(Canvas canvas, Offset at, double s, Color color) {
    final p = Paint()..color = color;
    canvas.drawCircle(at, s, p);
    canvas.drawCircle(at + Offset(s * 0.9, s * 0.25), s * 0.8, p);
    canvas.drawCircle(at + Offset(-s * 0.9, s * 0.3), s * 0.7, p);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(at.dx - s * 1.5, at.dy, s * 3.1, s * 0.85), Radius.circular(s * 0.4)), p);
  }

  void _hills(Canvas canvas, Size size, double y, Color color, double shift, double height) {
    final path = Path()..moveTo(0, size.height);
    for (var x = 0.0; x <= size.width; x += 6) {
      final f = x / size.width * math.pi * 2;
      path.lineTo(x, y - height * (0.5 + 0.3 * math.sin(f * 1.3 + shift) + 0.2 * math.sin(f * 3.1 + shift * 2)));
    }
    path
      ..lineTo(size.width, y - height * 0.5)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SkyPainter old) => old.sky.top != sky.top || old.sky.sun != sky.sun || old.sky.moon != sky.moon || old.moonPhase != moonPhase || old.motion != motion;
}

/// Candle lighting, havdalah, fasts, chametz and molad for the date.
class _SpecialTimes extends ConsumerWidget {
  final PlainDate date;
  final HDate hd;
  const _SpecialTimes({required this.date, required this.hd});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final loc = ref.watch(locationProvider);
    final theme = Theme.of(context);
    final events = calendar(CalOptions(
      start: hd,
      end: hd,
      location: loc,
      il: s.location.il,
      candlelighting: true,
      candleLightingMins: s.candleLightingMins,
      havdalahMins: s.havdalahMins,
      useElevation: s.useElevation,
      molad: true,
      hour12: s.hour12,
    ));
    final rows = <(String, String)>[];
    for (final e in events) {
      if (e is TimedEvent) rows.add((e.renderBrief(context.hebcalLocale), formatTime(e.eventTime, loc, hour12: s.hour12)));
      if (e is TimedChanukahEvent && e.eventTime != null) {
        rows.add((context.term('Chanukah candles'), formatTime(e.eventTime, loc, hour12: s.hour12)));
      }
      if (e is MoladEvent) rows.add(('Molad', e.molad.render('en', s.hour12)));
    }
    final z = ref.watch(zmanimProvider(date));
    final kl3 = z.getTchilasZmanKidushLevana3Days();
    final kl7 = z.getTchilasZmanKidushLevana7Days();
    final klEnd = z.getSofZmanKidushLevana15Days();
    if (kl3 != null) rows.add((context.term('Kiddush Levana from (3 days)'), formatTime(kl3, loc, hour12: s.hour12)));
    if (kl7 != null) rows.add((context.term('Kiddush Levana from (7 days)'), formatTime(kl7, loc, hour12: s.hour12)));
    if (klEnd != null) rows.add((context.term('Kiddush Levana until'), formatTime(klEnd, loc, hour12: s.hour12)));
    final molad = z.getZmanMolad();
    if (molad != null) rows.add(('Molad (local time)', formatTime(molad, loc, hour12: s.hour12)));
    if (rows.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.term('Today\'s special times'), style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
          const SizedBox(height: 8),
          for (final (a, b) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [Expanded(child: Text(a)), Flexible(child: Text(b, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600)))]),
            ),
        ]),
      ),
    );
  }
}

/// Offset → nicely formatted wall-clock (exported for alerts).
String zonedHm(DateTime t, Location loc) {
  final l = tz.TZDateTime.from(t, loc.tzLocation);
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}
