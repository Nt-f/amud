import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hebcal/hebcal.dart';

import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';

enum ZmanGroup { dawn, morning, afternoon, evening, night, shabbat }

/// A named halachic time computed from a [Zmanim] calculator.
class ZmanDef {
  final String key;
  final String en;
  final String he;
  final String? opinion;
  final ZmanGroup group;
  final DateTime? Function(Zmanim z) compute;

  /// Shown in the default (condensed) list for this opinion set.
  final Set<ZmanimOpinion> defaultFor;
  const ZmanDef(this.key, this.en, this.he, this.group, this.compute, {this.opinion, this.defaultFor = const {}});
}

const _all = {ZmanimOpinion.gra, ZmanimOpinion.mga, ZmanimOpinion.baalHatanya};

final List<ZmanDef> builtInZmanim = [
  ZmanDef('alot72', 'Dawn (72 min)', 'עלות השחר (72 דק׳)', ZmanGroup.dawn, (z) => z.alotHaShachar72(),
      opinion: 'MGA', defaultFor: {ZmanimOpinion.mga}),
  ZmanDef('alot16_1', 'Dawn (16.1°)', 'עלות השחר', ZmanGroup.dawn, (z) => z.alotHaShachar(),
      opinion: '16.1°', defaultFor: {ZmanimOpinion.gra}),
  ZmanDef('alotBaalHatanya', 'Dawn (Baal HaTanya)', 'עלות השחר (בעל התניא)', ZmanGroup.dawn, (z) => z.alosBaalHatanya(),
      opinion: '16.9°', defaultFor: {ZmanimOpinion.baalHatanya}),
  ZmanDef('misheyakir', 'Earliest tallit & tefillin', 'משיכיר', ZmanGroup.dawn, (z) => z.misheyakir(),
      opinion: '11.5°', defaultFor: _all),
  ZmanDef('misheyakirMachmir', 'Misheyakir (machmir)', 'משיכיר (מחמיר)', ZmanGroup.dawn, (z) => z.misheyakirMachmir(), opinion: '10.2°'),
  ZmanDef('dawn', 'Civil dawn', 'שחר אזרחי', ZmanGroup.dawn, (z) => z.dawn(), opinion: '6°'),
  ZmanDef('sunrise', 'Sunrise (Netz)', 'הנץ החמה', ZmanGroup.morning, (z) => z.sunrise(), defaultFor: _all),
  ZmanDef('seaLevelSunrise', 'Sea-level sunrise', 'הנץ (גובה פני הים)', ZmanGroup.morning, (z) => z.seaLevelSunrise()),
  ZmanDef('sofZmanShmaMGA', 'Latest Shema (MGA)', 'סוף זמן ק״ש מג״א', ZmanGroup.morning, (z) => z.sofZmanShmaMGA(),
      opinion: 'MGA 72', defaultFor: {ZmanimOpinion.mga, ZmanimOpinion.gra}),
  ZmanDef('sofZmanShmaMGA16', 'Latest Shema (MGA 16.1°)', 'סוף זמן ק״ש מג״א 16.1°', ZmanGroup.morning, (z) => z.sofZmanShmaMGA16Point1(), opinion: 'MGA 16.1°'),
  ZmanDef('sofZmanShma', 'Latest Shema (GRA)', 'סוף זמן ק״ש גר״א', ZmanGroup.morning, (z) => z.sofZmanShma(),
      opinion: 'GRA', defaultFor: {ZmanimOpinion.gra, ZmanimOpinion.mga}),
  ZmanDef('sofZmanShmaBaalHatanya', 'Latest Shema (Baal HaTanya)', 'סוף זמן ק״ש (בעל התניא)', ZmanGroup.morning, (z) => z.sofZmanShmaBaalHatanya(),
      defaultFor: {ZmanimOpinion.baalHatanya}),
  ZmanDef('sofZmanTfillaMGA', 'Latest Shacharit (MGA)', 'סוף זמן תפילה מג״א', ZmanGroup.morning, (z) => z.sofZmanTfillaMGA(),
      opinion: 'MGA 72', defaultFor: {ZmanimOpinion.mga}),
  ZmanDef('sofZmanTfilla', 'Latest Shacharit (GRA)', 'סוף זמן תפילה גר״א', ZmanGroup.morning, (z) => z.sofZmanTfilla(),
      opinion: 'GRA', defaultFor: {ZmanimOpinion.gra, ZmanimOpinion.mga}),
  ZmanDef('sofZmanTfilaBaalHatanya', 'Latest Shacharit (Baal HaTanya)', 'סוף זמן תפילה (בעל התניא)', ZmanGroup.morning, (z) => z.sofZmanTfilaBaalHatanya(),
      defaultFor: {ZmanimOpinion.baalHatanya}),
  ZmanDef('chatzot', 'Midday (Chatzot)', 'חצות היום', ZmanGroup.afternoon, (z) => z.chatzot(), defaultFor: _all),
  ZmanDef('minchaGedola', 'Earliest Mincha', 'מנחה גדולה', ZmanGroup.afternoon, (z) => z.minchaGedola(), opinion: 'GRA', defaultFor: {ZmanimOpinion.gra, ZmanimOpinion.mga}),
  ZmanDef('minchaGedolaMGA', 'Earliest Mincha (MGA)', 'מנחה גדולה מג״א', ZmanGroup.afternoon, (z) => z.minchaGedolaMGA(), opinion: 'MGA'),
  ZmanDef('minchaGedolaBaalHatanya', 'Earliest Mincha (Baal HaTanya)', 'מנחה גדולה (בעל התניא)', ZmanGroup.afternoon, (z) => z.minchaGedolaBaalHatanya(),
      defaultFor: {ZmanimOpinion.baalHatanya}),
  ZmanDef('minchaKetana', 'Mincha Ketana', 'מנחה קטנה', ZmanGroup.afternoon, (z) => z.minchaKetana(), opinion: 'GRA', defaultFor: {ZmanimOpinion.gra, ZmanimOpinion.mga}),
  ZmanDef('minchaKetanaBaalHatanya', 'Mincha Ketana (Baal HaTanya)', 'מנחה קטנה (בעל התניא)', ZmanGroup.afternoon, (z) => z.minchaKetanaBaalHatanya(),
      defaultFor: {ZmanimOpinion.baalHatanya}),
  ZmanDef('plagHaMincha', 'Plag HaMincha', 'פלג המנחה', ZmanGroup.afternoon, (z) => z.plagHaMincha(), opinion: 'GRA', defaultFor: {ZmanimOpinion.gra, ZmanimOpinion.mga}),
  ZmanDef('plagHaminchaBaalHatanya', 'Plag HaMincha (Baal HaTanya)', 'פלג המנחה (בעל התניא)', ZmanGroup.afternoon, (z) => z.plagHaminchaBaalHatanya(),
      defaultFor: {ZmanimOpinion.baalHatanya}),
  ZmanDef('sunset', 'Sunset (Shkiah)', 'שקיעת החמה', ZmanGroup.evening, (z) => z.sunset(), defaultFor: _all),
  ZmanDef('seaLevelSunset', 'Sea-level sunset', 'שקיעה (גובה פני הים)', ZmanGroup.evening, (z) => z.seaLevelSunset()),
  ZmanDef('dusk', 'Civil dusk', 'דמדומים', ZmanGroup.evening, (z) => z.dusk(), opinion: '6°'),
  ZmanDef('beinHaShmashos', 'Bein HaShmashot (R. Tam)', 'בין השמשות ר״ת', ZmanGroup.evening, (z) => z.beinHaShmashos()),
  ZmanDef('tzeitBaalHatanya', 'Nightfall (Baal HaTanya)', 'צאת הכוכבים (בעל התניא)', ZmanGroup.evening, (z) => z.tzaisBaalHatanya(),
      opinion: '6°', defaultFor: {ZmanimOpinion.baalHatanya}),
  ZmanDef('tzeit7_083', 'Nightfall (3 medium stars)', 'צאת הכוכבים (7.083°)', ZmanGroup.evening, (z) => z.tzeit(7.083),
      opinion: '7.083°', defaultFor: {ZmanimOpinion.gra, ZmanimOpinion.mga}),
  ZmanDef('tzeit8_5', 'Nightfall (3 small stars)', 'צאת הכוכבים (8.5°)', ZmanGroup.evening, (z) => z.tzeit(8.5), opinion: '8.5°', defaultFor: {ZmanimOpinion.gra}),
  ZmanDef('tzeit6_45', 'Nightfall (R. Tucazinsky)', 'צאת הכוכבים (6.45°)', ZmanGroup.evening, (z) => z.tzeit(6.45), opinion: '6.45°'),
  ZmanDef('tzeit72', 'Nightfall (Rabbeinu Tam, 72 min)', 'צאת הכוכבים ר״ת', ZmanGroup.evening, (z) => z.tzeit72(),
      opinion: '72 min', defaultFor: {ZmanimOpinion.mga}),
  ZmanDef('chatzotNight', 'Midnight (Chatzot HaLailah)', 'חצות הלילה', ZmanGroup.night, (z) => z.chatzotNight(), defaultFor: _all),
];

final Map<String, ZmanDef> builtInByKey = {for (final z in builtInZmanim) z.key: z};

/// How a user-defined zman is calculated.
enum CustomZmanKind { degrees, offset, shaahZmanit }

/// A user-defined zman, e.g. "Sunset − 13.5 min", "Sun 7.5° below
/// horizon (evening)" or "4.5 shaos zmaniyos (GRA)".
class CustomZman {
  final String id;
  final String name;
  final CustomZmanKind kind;

  /// degrees: angle below horizon; shaahZmanit: number of hours.
  final double value;

  /// degrees: true = morning. offset: base zman key.
  final bool rising;
  final String baseKey;

  /// offset: minutes relative to [baseKey] (negative = before).
  final double minutes;

  /// shaahZmanit: 'gra' | 'mga' | 'baalHatanya' | 'deg16_1'
  final String system;

  const CustomZman({
    required this.id,
    required this.name,
    required this.kind,
    this.value = 0,
    this.rising = false,
    this.baseKey = 'sunset',
    this.minutes = 0,
    this.system = 'gra',
  });

  String get key => 'custom:$id';

  String describe() => switch (kind) {
        CustomZmanKind.degrees => 'Sun ${value.toStringAsFixed(2)}° below horizon (${rising ? 'morning' : 'evening'})',
        CustomZmanKind.offset =>
          '${minutes >= 0 ? '+' : '−'}${minutes.abs().toStringAsFixed(minutes % 1 == 0 ? 0 : 1)} min from ${builtInByKey[baseKey]?.en ?? baseKey}',
        CustomZmanKind.shaahZmanit => '${value.toStringAsFixed(2)} shaos zmaniyos ($system)',
      };

  DateTime? compute(Zmanim z) {
    switch (kind) {
      case CustomZmanKind.degrees:
        return z.timeAtAngle(value, rising);
      case CustomZmanKind.offset:
        final base = builtInByKey[baseKey]?.compute(z);
        return base?.add(Duration(milliseconds: (minutes * 60000).round()));
      case CustomZmanKind.shaahZmanit:
        DateTime? start;
        DateTime? end;
        switch (system) {
          case 'mga':
            start = z.sunriseOffset(-72, false, true);
            end = z.sunsetOffset(72, false, true);
          case 'baalHatanya':
            start = z.timeAtAngle(1.583, true);
            end = z.timeAtAngle(1.583, false);
          case 'deg16_1':
            start = z.timeAtAngle(16.1, true);
            end = z.timeAtAngle(16.1, false);
          default:
            start = z.sunrise();
            end = z.sunset();
        }
        if (start == null || end == null) return null;
        final hour = (end.millisecondsSinceEpoch - start.millisecondsSinceEpoch) / 12;
        return start.add(Duration(milliseconds: (hour * value).round()));
    }
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'value': value,
        'rising': rising,
        'baseKey': baseKey,
        'minutes': minutes,
        'system': system,
      };

  factory CustomZman.fromJson(Map<String, Object?> j) => CustomZman(
        id: j['id'] as String,
        name: j['name'] as String,
        kind: CustomZmanKind.values.byName(j['kind'] as String),
        value: (j['value'] as num?)?.toDouble() ?? 0,
        rising: j['rising'] == true,
        baseKey: (j['baseKey'] as String?) ?? 'sunset',
        minutes: (j['minutes'] as num?)?.toDouble() ?? 0,
        system: (j['system'] as String?) ?? 'gra',
      );
}

class CustomZmanimNotifier extends Notifier<List<CustomZman>> {
  @override
  List<CustomZman> build() =>
      ref.watch(storageProvider).readJson(
          'customZmanim', (j) => [for (final e in (j as List).cast<Map>()) CustomZman.fromJson(e.cast<String, Object?>())]) ??
      const [];

  void save(List<CustomZman> list) {
    state = list;
    ref.read(storageProvider).writeJson('customZmanim', [for (final z in list) z.toJson()]);
  }

  void upsert(CustomZman z) => save([...state.where((e) => e.id != z.id), z]);
  void remove(String id) => save(state.where((e) => e.id != id).toList());
}

final customZmanimProvider = NotifierProvider<CustomZmanimNotifier, List<CustomZman>>(CustomZmanimNotifier.new);

/// Resolves a zman key (built-in or `custom:<id>`) to a display name and
/// calculator.
class ZmanResolver {
  final Map<String, CustomZman> custom;

  /// Ashkenazi transliteration of built-in names ("Chatzos", "Tzeis").
  final bool ashkenazi;

  /// Hebrew or Yiddish interface: [label] gives the Hebrew name.
  final bool hebrew;
  ZmanResolver(List<CustomZman> list, {this.ashkenazi = false, this.hebrew = false}) : custom = {for (final c in list) c.key: c};

  String _spell(String en) => ashkenazi ? ashkenaziSpelling(en) : en;

  String name(String key) => builtInByKey[key] != null ? _spell(builtInByKey[key]!.en) : custom[key]?.name ?? key;
  String nameHe(String key) => builtInByKey[key]?.he ?? custom[key]?.name ?? key;

  /// The name in the interface language.
  String label(String key) => hebrew ? nameHe(key) : name(key);

  DateTime? compute(String key, Zmanim z) {
    final b = builtInByKey[key];
    if (b != null) return b.compute(z);
    return custom[key]?.compute(z);
  }

  Iterable<(String, String)> get allKeys sync* {
    for (final z in builtInZmanim) {
      yield (z.key, _spell(z.en));
    }
    for (final c in custom.values) {
      yield (c.key, c.name);
    }
  }
}

final zmanResolverProvider = Provider<ZmanResolver>((ref) =>
    ZmanResolver(ref.watch(customZmanimProvider),
        ashkenazi: ref.watch(settingsProvider.select((s) => s.ashkenaziSpelling)),
        hebrew: ref.watch(settingsProvider.select((s) => s.uiLanguage != UiLanguage.en))));
