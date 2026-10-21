import '../../features/gemara/gemara_user.dart';
import '../../features/tehillim/tehillim_progress.dart';
import '../../features/torah/shnayim_mikra.dart';
import '../../features/torah/torah_settings.dart';
import '../../features/shiurim/shiurim_settings.dart';
import '../settings.dart';
import 'sync_doc.dart';

/// One stored key and how it syncs.
///
/// A key whose JSON is a map syncs field by field (changing the font on one
/// device and the theme on another both survive). Anything else syncs whole.
class SyncSource {
  const SyncSource(this.key, {this.fields, this.defaults, this.perField = true})
      : group = null,
        split = null,
        join = null;

  /// A list or other value that is replaced as a whole.
  const SyncSource.whole(this.key)
      : fields = null,
        defaults = null,
        perField = false,
        group = null,
        split = null,
        join = null;

  /// Progress, kept in many small parts ('completed/Berakhot:2a') so marks
  /// made on two devices add up, and unmarking one removes just that one.
  /// Syncs only when its [group] is included (see [syncGroups]).
  const SyncSource.parts(this.key, {required String this.group, required Map<String, Object?> Function(Object? stored) this.split, required Object? Function(Map<String, Object?> parts) this.join})
      : fields = null,
        defaults = null,
        perField = true;

  final String key;
  final bool perField;

  /// The optional group this source belongs to; null syncs always.
  final String? group;

  /// The stored value as parts (a part left out holds its default), and back.
  final Map<String, Object?> Function(Object? stored)? split;
  final Object? Function(Map<String, Object?> parts)? join;

  bool get isParts => split != null;

  /// The fields that sync; null means every field. Anything not listed stays
  /// on its device (see [localSettingsFields]).
  final Set<String>? fields;

  /// What an untouched install holds, so a device that never changed a
  /// value doesn't overwrite another device's choice when it joins.
  final Map<String, Object?> Function()? defaults;

  String entryName(String field) => perField ? '$key/$field' : key;
}

/// AppSettings fields that stay on the device: tied to where it is, to its
/// platform, to its form factor, to consent given on it, or to a first run.
/// `test/sync_test.dart` fails when a new setting is in neither list.
const localSettingsFields = {
  'v', 'location', 'useElevation', 'exactAlarms', 'setupDone', 'seenFeatures', 'shareUsage', //
  'keepReaderAwake', 'fullscreenReader', 'readerDnd', 'readerCompass', 'travelPrompts', 'desktopTray', 'omerBadge',
  'levanaReminder', 'levanaHeadsUp', 'hachamaReminder', 'omerReminder', 'navTabs', 'navLabels', 'expandedSettings',
};

/// AppSettings fields that sync: how the app looks, reads and counts.
const syncedSettingsFields = {
  'hour12', 'candleLightingMins', 'havdalahMins', 'opinion', 'defaultBook', 'hebrewVersions', 'translationVersions', //
  'layout', 'linearStyle', 'notesLanguage', 'titleLanguage', 'uiLanguage', 'ashkenaziSpelling', 'showTeamim', 'showNikud', 'preferTrop',
  'textScale', 'hebrewFont', 'sefardiFont', 'latinFont', 'excludedDisplay', 'showNotes', 'conciseNotes', 'collapseNotes', 'collapseChazarah',
  'choices', 'showInstructions', 'highlightToday', 'highlightColor', 'typesetting', 'justifyText', 'typeContrast', 'minhagim', 'themeMode',
  'warmth', 'seedColor', 'openLicensesOnly', 'learningSchedules',
};

final syncSources = <SyncSource>[
  SyncSource('settings', fields: syncedSettingsFields, defaults: () => const AppSettings().toJson()),
  SyncSource('torahSettings', defaults: () => const TorahSettings().toJson()),
  SyncSource('shiurimSettings', defaults: () => const ShiurimSettings().toJson()),
  SyncSource('shnayimMikraSettings', defaults: () => const ShnayimMikraSettings().toJson()),
  const SyncSource.whole('personalDates'),
  const SyncSource.whole('customRules'),
  const SyncSource.whole('customZmanim'),
  SyncSource.parts('gemaraMarks', group: 'learning',
      split: (j) => splitRecord(j, const GemaraMarks().toJson(), sets: {'completed'}, maps: {'notes', 'highlights'}),
      join: (p) => joinRecord(p, const GemaraMarks().toJson(), sets: {'completed'}, maps: {'notes', 'highlights'})),
  SyncSource.parts('shnayimMikraDone', group: 'shnayimMikra', split: _splitByYear, join: _joinByYear),
  SyncSource.parts('tehillim', group: 'tehillim',
      split: (j) => splitRecord(j, const TehillimState().toJson(), sets: {'read'}),
      join: (p) => joinRecord(p, const TehillimState().toJson(), sets: {'read'}, intSets: {'read'})),
];

/// Progress that syncs and goes into a settings file only if the reader
/// includes it (Settings → Advanced → Sync between devices).
const syncGroups = ['learning', 'shnayimMikra', 'tehillim'];

/// Whether [s] syncs with these groups included.
bool includesSource(SyncSource s, Set<String> groups) => s.group == null || groups.contains(s.group);

/// A JSON record as parts: each member of a [sets] field ('read/12': true)
/// and each entry of a [maps] field ('notes/Berakhot:2a:3': 'text') is a part
/// of its own; any other field is one part. Values equal to [defaults] are
/// left out.
Map<String, Object?> splitRecord(Object? j, Map<String, Object?> defaults, {Set<String> sets = const {}, Set<String> maps = const {}}) {
  final out = <String, Object?>{};
  if (j is! Map) return out;
  for (final e in j.entries) {
    final k = '${e.key}';
    final v = e.value;
    if (sets.contains(k)) {
      if (v is List) out.addAll({for (final x in v) '$k/$x': true});
    } else if (maps.contains(k)) {
      if (v is Map) out.addAll({for (final x in v.entries) '$k/${x.key}': x.value});
    } else if (canon(v) != canon(defaults[k])) {
      out[k] = v;
    }
  }
  return out;
}

/// The record [splitRecord] took apart; members of [intSets] are numbers.
Map<String, Object?> joinRecord(Map<String, Object?> parts, Map<String, Object?> defaults,
    {Set<String> sets = const {}, Set<String> maps = const {}, Set<String> intSets = const {}}) {
  final out = <String, Object?>{
    ...defaults,
    for (final k in sets) k: <Object>[],
    for (final k in maps) k: <String, Object?>{},
  };
  for (final e in parts.entries) {
    final slash = e.key.indexOf('/');
    final field = slash < 0 ? e.key : e.key.substring(0, slash);
    final rest = slash < 0 ? '' : e.key.substring(slash + 1);
    if (sets.contains(field) && slash >= 0) {
      if (e.value != true) continue;
      final Object? member = intSets.contains(field) ? int.tryParse(rest) : rest;
      if (member != null) (out[field] as List).add(member);
    } else if (maps.contains(field) && slash >= 0) {
      (out[field] as Map)[rest] = e.value;
    } else if (slash < 0) {
      out[field] = e.value;
    }
  }
  for (final k in sets) {
    (out[k] as List).sort((a, b) => a is int && b is int ? a.compareTo(b) : '$a'.compareTo('$b'));
  }
  return out;
}

/// Shnayim Mikra marks ({"5787": ["Noach:3"]}) as '5787/Noach:3'.
Map<String, Object?> _splitByYear(Object? j) => {
      if (j is Map)
        for (final y in j.entries)
          if (y.value is List)
            for (final x in y.value as List) '${y.key}/$x': true,
    };

Map<String, Object?> _joinByYear(Map<String, Object?> parts) {
  final out = <String, List<String>>{};
  for (final e in parts.entries) {
    final slash = e.key.indexOf('/');
    if (slash < 0 || e.value != true) continue;
    out.putIfAbsent(e.key.substring(0, slash), () => []).add(e.key.substring(slash + 1));
  }
  for (final l in out.values) {
    l.sort();
  }
  return out;
}

/// Fonts a user uploaded ('user_…') or downloaded ('gf_…') exist only on the
/// device that has them, so they never sync and an incoming one is ignored.
bool syncableValue(String field, Object? value) =>
    !((field == 'hebrewFont' || field == 'latinFont') && value is String && (value.startsWith('user_') || value.startsWith('gf_')));
