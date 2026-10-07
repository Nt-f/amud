import '../../features/torah/shnayim_mikra.dart';
import '../../features/torah/torah_settings.dart';
import '../../features/shiurim/shiurim_settings.dart';
import '../settings.dart';

/// One stored key and how it syncs.
///
/// A key whose JSON is a map syncs field by field (changing the font on one
/// device and the theme on another both survive). Anything else syncs whole.
class SyncSource {
  const SyncSource(this.key, {this.fields, this.defaults, this.perField = true});

  /// A list or other value that is replaced as a whole.
  const SyncSource.whole(this.key)
      : fields = null,
        defaults = null,
        perField = false;

  final String key;
  final bool perField;

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
  'keepReaderAwake', 'fullscreenReader', 'readerDnd', 'travelPrompts', 'desktopTray', 'omerBadge',
  'levanaReminder', 'hachamaReminder', 'navTabs',
};

/// AppSettings fields that sync: how the app looks, reads and counts.
const syncedSettingsFields = {
  'hour12', 'candleLightingMins', 'havdalahMins', 'opinion', 'defaultBook', 'hebrewVersions', 'translationVersions', //
  'layout', 'linearStyle', 'notesLanguage', 'titleLanguage', 'uiLanguage', 'ashkenaziSpelling', 'showTeamim', 'showNikud', 'preferTrop',
  'textScale', 'hebrewFont', 'latinFont', 'excludedDisplay', 'showNotes', 'conciseNotes', 'collapseNotes', 'collapseChazarah',
  'choices', 'showInstructions', 'highlightToday', 'typesetting', 'justifyText', 'typeContrast', 'minhagim', 'themeMode',
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
];

/// Fonts a user uploaded ('user_…') or downloaded ('gf_…') exist only on the
/// device that has them, so they never sync and an incoming one is ignored.
bool syncableValue(String field, Object? value) =>
    !((field == 'hebrewFont' || field == 'latinFont') && value is String && (value.startsWith('user_') || value.startsWith('gf_')));
