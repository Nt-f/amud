import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hebcal/hebcal.dart';
import 'package:siddur_engine/siddur_engine.dart';
import 'package:timezone/timezone.dart' as tz;

import 'settings.dart';
import 'storage.dart';

/// Overridden in main() once Hive is open.
final storageProvider = Provider<Storage>((ref) => throw UnimplementedError('storage not initialized'));

class _BundleSource implements TextSource {
  @override
  Future<List<int>> readBytes(String file) async {
    final data = await rootBundle.load(file);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}

List<int> _gunzip(List<int> bytes) => const GZipDecoder().decodeBytes(bytes);

final libraryProvider = Provider<SiddurLibrary>((ref) => SiddurLibrary(_BundleSource(), _gunzip));

final manifestProvider = FutureProvider<Manifest>((ref) => ref.watch(libraryProvider).manifest());

/// Per-book rule overrides from assets/rules/rules.json.
final rulesProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final raw = await rootBundle.loadString('assets/rules/rules.json');
  return jsonDecode(raw) as Map<String, dynamic>;
});

/// User-authored custom section rules (Settings → Advanced).
class CustomRulesNotifier extends Notifier<List<Map<String, Object?>>> {
  @override
  List<Map<String, Object?>> build() =>
      ref.watch(storageProvider).readJson('customRules', (j) => (j as List).cast<Map>().map((m) => m.cast<String, Object?>()).toList()) ??
      const [];

  void set(List<Map<String, Object?>> rules) {
    state = rules;
    ref.read(storageProvider).writeJson('customRules', rules);
  }
}

final customRulesProvider = NotifierProvider<CustomRulesNotifier, List<Map<String, Object?>>>(CustomRulesNotifier.new);

final resolverProvider = FutureProvider.family<SiddurResolver, String>((ref, bookTitle) async {
  final rules = await ref.watch(rulesProvider.future);
  final custom = ref.watch(customRulesProvider);
  final bookRules = (rules[bookTitle] as Map<String, dynamic>?) ?? const {};
  return SiddurResolver().withOverrides(bookRules).withOverrides({'sections': custom});
});

/// Ticks every 30 seconds (and immediately) so countdowns stay fresh.
final nowProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 30), (_) => DateTime.now());
});

final locationProvider = Provider<Location>((ref) => ref.watch(settingsProvider.select((s) => s.location)).toLocation());

tz.Location tzLocationOf(Location l) => l.tzLocation;

/// The civil (wall-clock) date at the user's location.
final civilTodayProvider = Provider<PlainDate>((ref) {
  final now = ref.watch(nowProvider).value ?? DateTime.now();
  final loc = ref.watch(locationProvider);
  final local = tz.TZDateTime.from(now, loc.tzLocation);
  return PlainDate(local.year, local.month, local.day);
});

/// The current halachic Hebrew date (advances at sunset).
final halachicTodayProvider = Provider<HDate>((ref) {
  final now = ref.watch(nowProvider).value ?? DateTime.now();
  final loc = ref.watch(locationProvider);
  final useElevation = ref.watch(settingsProvider.select((s) => s.useElevation));
  return Zmanim.makeSunsetAwareHDate(loc, now.toUtc(), useElevation);
});

final zmanimProvider = Provider.family<Zmanim, PlainDate>((ref, date) {
  final loc = ref.watch(locationProvider);
  final useElevation = ref.watch(settingsProvider.select((s) => s.useElevation));
  return Zmanim(loc, date, useElevation);
});

/// [DayContext] for a civil daytime Hebrew date (by abs) and service;
/// Maariv shifts to the next Hebrew day. Reacts to location/customs.
final dayContextProvider = Provider.family<DayContext, (int, Service)>((ref, k) {
  final s = ref.watch(settingsProvider.select((x) => (x.location.il, x.minhagim)));
  return DayContext.forService(HDate.fromAbs(k.$1), k.$2, il: s.$1, minhagim: s.$2);
});

/// Context for the reader: the civil day's daytime Hebrew date (so Maariv
/// after sunset still resolves correctly) unless the user picked a date.
final readerDateProvider = StateProvider<HDate?>((ref) => null);

/// Reader focus mode (double-tap the text): the app bars slide away.
final focusModeProvider = StateProvider<bool>((ref) => false);

final readerDaytimeDateProvider = Provider<HDate>((ref) {
  final picked = ref.watch(readerDateProvider);
  if (picked != null) return picked;
  final civil = ref.watch(civilTodayProvider);
  return HDate.fromAbs(civil.abs);
});

/// Holidays/events for a Hebrew year (cached by hebcal).
final calendarMonthProvider = Provider.family<List<Event>, (int, int)>((ref, ym) {
  final (year, month) = ym;
  final s = ref.watch(settingsProvider);
  return calendar(CalOptions(
    year: year,
    month: month,
    location: ref.watch(locationProvider),
    il: s.location.il,
    candlelighting: true,
    candleLightingMins: s.candleLightingMins,
    havdalahMins: s.havdalahMins,
    sedrot: true,
    omer: true,
    shabbatMevarchim: true,
    useElevation: s.useElevation,
    hour12: s.hour12,
  ));
});
