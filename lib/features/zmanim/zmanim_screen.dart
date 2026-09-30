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
    final civil = ref.watch(civilTodayProvider);
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

    final defs = [for (final d in builtInZmanim) if (showAll || d.defaultFor.contains(s.opinion)) d];
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
      if (custom.isNotEmpty)
        Card(
          child: Column(children: [
            for (final c in custom)
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
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(wide ? 32 : 16, 8, wide ? 32 : 16, 32),
        children: [
          _DateNav(date: date, hd: hd, isToday: isToday),
          const SizedBox(height: 8),
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
          if (wide)
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

/// Sky-colored card with the sun's path from sunrise to sunset.
class _SunArcCard extends StatelessWidget {
  final Zmanim z;
  final Location loc;
  final DateTime? now;
  final bool? hour12;
  const _SunArcCard({required this.z, required this.loc, required this.now, required this.hour12});

  @override
  Widget build(BuildContext context) {
    final rise = z.sunrise();
    final set = z.sunset();
    final alot = z.alotHaShachar();
    final tzeit = z.tzeit();
    final theme = Theme.of(context);
    double? progress;
    if (now != null && rise != null && set != null) {
      progress = (now!.millisecondsSinceEpoch - rise.millisecondsSinceEpoch) /
          (set.millisecondsSinceEpoch - rise.millisecondsSinceEpoch);
    }
    final dayLen = rise != null && set != null ? set.difference(rise) : null;
    final night = progress != null && (progress < 0 || progress > 1);
    final gradient = night
        ? const [Color(0xFF0B1437), Color(0xFF28306B)]
        : const [Color(0xFF7EC8F2), Color(0xFFFFE3A3)];
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: gradient)),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(children: [
          SizedBox(
            height: 130,
            child: CustomPaint(
              painter: _ArcPainter(progress: progress, night: night),
              size: const Size.fromHeight(130),
            ),
          ),
          const SizedBox(height: 8),
          DefaultTextStyle(
            style: theme.textTheme.bodySmall!.copyWith(color: night ? Colors.white : Colors.black87),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _cap(context.term('Alot'), formatTime(alot, loc, hour12: hour12)),
              _cap('Netz', formatTime(rise, loc, hour12: hour12)),
              _cap('Shkiah', formatTime(set, loc, hour12: hour12)),
              _cap(context.term('Tzeit'), formatTime(tzeit, loc, hour12: hour12)),
            ]),
          ),
          if (dayLen != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Day ${dayLen.inHours}h ${dayLen.inMinutes % 60}m · shaah zmanit ${(dayLen.inSeconds / 12 / 60).toStringAsFixed(1)} min',
                style: theme.textTheme.bodySmall?.copyWith(color: night ? Colors.white70 : Colors.black54),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _cap(String a, String b) => Column(children: [Text(a), Text(b, style: const TextStyle(fontWeight: FontWeight.w700))]);
}

class _ArcPainter extends CustomPainter {
  final double? progress;
  final bool night;
  _ArcPainter({required this.progress, required this.night});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h - 8);
    final r = math.min(w / 2 - 16, h - 16);
    final horizon = Paint()
      ..color = (night ? Colors.white : Colors.black).withValues(alpha: 0.35)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(8, center.dy), Offset(w - 8, center.dy), horizon);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = (night ? Colors.white : Colors.orange.shade800).withValues(alpha: 0.6);
    canvas.drawArc(Rect.fromCircle(center: center, radius: r), math.pi, math.pi, false, arc);
    if (progress != null) {
      final p = progress!.clamp(-0.08, 1.08);
      final angle = math.pi + p * math.pi;
      final pos = Offset(center.dx + r * math.cos(angle), center.dy + r * math.sin(angle));
      if (!night) {
        canvas.drawCircle(pos, 16, Paint()..color = Colors.yellow.withValues(alpha: 0.35));
        canvas.drawCircle(pos, 10, Paint()..color = Colors.orange);
      } else {
        canvas.drawCircle(Offset(w - 36, 24), 10, Paint()..color = Colors.white.withValues(alpha: 0.9));
        canvas.drawCircle(Offset(w - 31, 21), 9, Paint()..color = const Color(0xFF1A2255));
        final star = Paint()..color = Colors.white70;
        for (final o in const [Offset(0.2, 0.2), Offset(0.35, 0.45), Offset(0.6, 0.15), Offset(0.12, 0.6), Offset(0.8, 0.5)]) {
          canvas.drawCircle(Offset(o.dx * w, o.dy * h), 1.5, star);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.progress != progress || old.night != night;
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
