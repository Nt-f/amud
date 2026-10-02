import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hebcal/hebcal.dart';
import 'package:siddur_engine/siddur_engine.dart';
import 'package:timezone/timezone.dart' as tz;

import 'day_start.dart';
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

/// Books with a tagged corpus (assets/corpus, built by
/// tool/corpus/build_assets.py).
const corpusFiles = {
  'Siddur Ashkenaz': 'assets/corpus/ashkenaz.json.gz',
  'Weekday Siddur Chabad': 'assets/corpus/chabad.json.gz',
  'Siddur Sefard': 'assets/corpus/sefard.json.gz',
  'Siddur Edot HaMizrach': 'assets/corpus/edot_hamizrach.json.gz',
  'The Koren Shalem Siddur; Ashkenaz': 'assets/corpus/koren.json.gz',
};

final corpusProvider = FutureProvider.family<Corpus?, String>((ref, bookTitle) async {
  final file = corpusFiles[bookTitle];
  if (file == null) return null;
  final List<int> bytes;
  try {
    bytes = await _BundleSource().readBytes(file);
  } catch (_) {
    return null; // Not tagged yet: the engine's own analysis is used.
  }
  return Corpus.fromJson(jsonDecode(utf8.decode(_gunzip(bytes))) as Map<String, Object?>);
});

final resolverProvider = FutureProvider.family<SiddurResolver, String>((ref, bookTitle) async {
  final rules = await ref.watch(rulesProvider.future);
  final custom = ref.watch(customRulesProvider);
  final corpus = await ref.watch(corpusProvider(bookTitle).future);
  final bookRules = (rules[bookTitle] as Map<String, dynamic>?) ?? const {};
  return SiddurResolver().withOverrides(bookRules).withOverrides({'sections': custom}).withCorpus(corpus);
});

/// Ticks every 30 seconds (and immediately) so countdowns stay fresh.
final nowProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 30), (_) => DateTime.now());
});

final locationProvider = Provider<Location>((ref) => ref.watch(settingsProvider.select((s) => s.location)).toLocation());

tz.Location tzLocationOf(Location l) => l.tzLocation;

/// Today's date at the user's location, turning over at dawn by their
/// opinion rather than midnight (see dayAt): until dawn it's still the
/// night before, for the siddur, zmanim, learning and calendar alike.
final todayProvider = Provider<PlainDate>((ref) {
  final now = ref.watch(nowProvider).value ?? DateTime.now();
  final s = ref.watch(settingsProvider.select((s) => (s.useElevation, s.opinion)));
  return dayAt(now, ref.watch(locationProvider), useElevation: s.$1, opinion: s.$2);
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
  return HDate.fromAbs(ref.watch(todayProvider).abs);
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
