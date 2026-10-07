import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hebcal/hebcal.dart';
import 'package:siddur_engine/siddur_engine.dart';

import 'analytics.dart';
import 'l10n.dart';
import 'providers.dart';

/// Where the user is, for zmanim and Israel/diaspora customs.
class SavedLocation {
  final String name;
  final double latitude;
  final double longitude;
  final double elevation;
  final String tzid;
  final String? countryCode;
  final bool il;

  const SavedLocation({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.tzid,
    this.elevation = 0,
    this.countryCode,
    this.il = false,
  });

  static const jerusalem = SavedLocation(
      name: 'Jerusalem', latitude: 31.76904, longitude: 35.21633, elevation: 786, tzid: 'Asia/Jerusalem', countryCode: 'IL', il: true);
  static const newYork = SavedLocation(
      name: 'New York', latitude: 40.71427, longitude: -74.00597, elevation: 57, tzid: 'America/New_York', countryCode: 'US');

  Location toLocation() => Location(latitude, longitude, il, tzid,
      cityName: name, countryCode: countryCode, elevation: elevation);

  factory SavedLocation.fromLocation(Location l) => SavedLocation(
        name: l.getName() ?? 'Location',
        latitude: l.latitude,
        longitude: l.longitude,
        elevation: l.elevation,
        tzid: l.getTzid(),
        countryCode: l.getCountryCode(),
        il: l.getIsrael(),
      );

  Map<String, Object?> toJson() => {
        'name': name,
        'lat': latitude,
        'lon': longitude,
        'elev': elevation,
        'tzid': tzid,
        'cc': countryCode,
        'il': il,
      };

  factory SavedLocation.fromJson(Map<String, Object?> j) => SavedLocation(
        name: j['name'] as String,
        latitude: (j['lat'] as num).toDouble(),
        longitude: (j['lon'] as num).toDouble(),
        elevation: (j['elev'] as num?)?.toDouble() ?? 0,
        tzid: j['tzid'] as String,
        countryCode: j['cc'] as String?,
        il: j['il'] == true,
      );
}

enum TextLayout { sideBySide, interleaved, hebrewOnly, translationOnly }

/// Languages for instructions and notes, chosen separately from the prayer
/// text layout.
enum NotesLanguage { bilingual, english, hebrew }

/// Language of prayer and section titles, chosen apart from the interface
/// language. [auto] shows both with an English interface and Hebrew only
/// otherwise.
enum TitleLanguage { auto, english, hebrew, both }

enum AppThemeMode {
  system('System'),
  light('Light'),
  dark('Dark');

  final String label;
  const AppThemeMode(this.label);
}

/// Which zmanim methodology to show by default.
enum ZmanimOpinion { gra, mga, baalHatanya }

/// Every tab the navigation bar can show (see NavTabsScreen); the default
/// bar shows all but the Shiurim tab.
const allNavTabIds = {'home', 'siddur', 'zmanim', 'torah', 'shiurim', 'settings'};

/// Every shortcut the navigation bar can show beside its tabs (see
/// navShortcuts in nav_tabs_screen.dart).
const navShortcutIds = {'calendar', 'tehillim', 'learning', 'alerts', 'personal-dates'};

/// Marks a version list saved before Amud's own text existed (see
/// AppSettings.fromJson). Never shown; saving the list drops it.
const preCorpusVersions = '#before-amud';

class AppSettings {
  final SavedLocation location;
  final bool useElevation;
  final bool? hour12;
  final int candleLightingMins;
  final int? havdalahMins;
  final ZmanimOpinion opinion;

  /// Book title (from the manifest) the Siddur tab opens.
  final String? defaultBook;

  /// Per-book ordered Hebrew/translation version titles.
  final Map<String, List<String>> hebrewVersions;
  final Map<String, List<String>> translationVersions;
  final TextLayout layout;
  final NotesLanguage notesLanguage;
  final TitleLanguage titleLanguage;
  final UiLanguage uiLanguage;
  final bool ashkenaziSpelling;

  /// Show cantillation marks and vowel points in Hebrew text.
  final bool showTeamim;
  final bool showNikud;

  /// Prefer text versions with te'amim (e.g. the Shema) where available.
  final bool preferTrop;
  final double textScale;
  final String hebrewFont;
  final String? latinFont;
  final ExcludedDisplay excludedDisplay;
  final bool showNotes;

  /// Short notes from the app, shown only on the days they matter, in place
  /// of the siddur's own long halachic notes.
  final bool conciseNotes;

  /// Show halachic notes as a one-line row that expands on tap.
  final bool collapseNotes;

  /// Fold the chazzan's repetition (Kedushah, Birkas Kohanim, Modim
  /// DeRabbanan) into a tappable row.
  final bool collapseChazarah;

  /// The reader's answers to choices drawn in the text (id → option), e.g.
  /// `table` → `own`.
  final Map<String, String> choices;
  final bool showInstructions;
  final bool highlightToday;

  /// Set the reader's text like a printed siddur (see core/typeset): sizes
  /// that follow what each paragraph is, ornaments between sections.
  final bool typesetting;

  /// Justify the lines of the reader's paragraphs (with [typesetting]).
  final bool justifyText;

  /// How much paragraph sizes differ from one another, 0 (uniform) to 1.
  final double typeContrast;
  final Minhagim minhagim;
  final AppThemeMode themeMode;

  /// Color temperature of the page, 0 (neutral) to 1 (warm paper/sepia).
  final double warmth;
  final int seedColor;

  /// Only redistributable (PD / Creative Commons) text versions are offered.
  final bool openLicensesOnly;

  /// Use exact alarms on Android (requires the user to grant permission).
  final bool exactAlarms;

  /// Daily learning schedules shown on the learning screen.
  final List<String> learningSchedules;

  /// The first-run setup has been completed.
  final bool setupDone;

  /// The newest feature announced to this user (see whats_new.dart).
  final int seenFeatures;

  /// Send anonymous usage statistics (see analytics.dart).
  final bool shareUsage;
  final bool keepReaderAwake;
  final bool fullscreenReader;

  /// Android: turn on Do Not Disturb while reading (and back off after).
  final bool readerDnd;
  final bool travelPrompts;
  final bool desktopTray;
  final bool omerBadge;
  final bool levanaReminder;
  final bool hachamaReminder;

  /// The tabs and shortcuts on the navigation bar, in order (see
  /// nav_tabs_screen.dart). Settings is always among them, so the bar can be
  /// changed back.
  final List<String> navTabs;

  /// The navigation bar shows labels under its icons.
  final bool navLabels;

  /// The Settings sections that are open; the rest show only their header.
  final List<String> expandedSettings;

  const AppSettings({
    this.location = SavedLocation.newYork,
    this.useElevation = false,
    this.hour12,
    this.candleLightingMins = 18,
    this.havdalahMins,
    this.opinion = ZmanimOpinion.gra,
    this.defaultBook,
    this.hebrewVersions = const {},
    this.translationVersions = const {},
    this.layout = TextLayout.hebrewOnly,
    this.notesLanguage = NotesLanguage.english,
    this.titleLanguage = TitleLanguage.auto,
    this.uiLanguage = UiLanguage.en,
    this.ashkenaziSpelling = true,
    this.showTeamim = true,
    this.showNikud = true,
    this.preferTrop = true,
    this.textScale = 1.0,
    this.hebrewFont = 'TaameyFrankCLM',
    this.latinFont,
    this.excludedDisplay = ExcludedDisplay.hide,
    this.showNotes = true,
    this.conciseNotes = true,
    this.collapseNotes = true,
    this.collapseChazarah = true,
    this.choices = const {},
    this.showInstructions = true,
    this.highlightToday = true,
    this.typesetting = true,
    this.justifyText = true,
    this.typeContrast = 0.5,
    this.minhagim = const Minhagim(),
    this.themeMode = AppThemeMode.system,
    this.warmth = 0,
    this.seedColor = 0xFF3B5BA5,
    this.openLicensesOnly = false,
    this.exactAlarms = true,
    this.learningSchedules = const ['dafYomi', 'mishnaYomi', 'nachYomi', 'rambam1', 'psalms', 'chofetzChaim'],
    this.setupDone = false,
    this.seenFeatures = 0,
    this.shareUsage = true,
    this.keepReaderAwake = true,
    this.fullscreenReader = false,
    this.readerDnd = false,
    this.travelPrompts = false,
    this.desktopTray = false,
    this.omerBadge = false,
    this.levanaReminder = false,
    this.hachamaReminder = false,
    this.navTabs = const ['home', 'siddur', 'zmanim', 'torah', 'settings'],
    this.navLabels = true,
    this.expandedSettings = const ['location'],
  });

  AppSettings copyWith({
    SavedLocation? location,
    bool? useElevation,
    bool? Function()? hour12,
    int? candleLightingMins,
    int? Function()? havdalahMins,
    ZmanimOpinion? opinion,
    String? Function()? defaultBook,
    Map<String, List<String>>? hebrewVersions,
    Map<String, List<String>>? translationVersions,
    TextLayout? layout,
    NotesLanguage? notesLanguage,
    TitleLanguage? titleLanguage,
    UiLanguage? uiLanguage,
    bool? ashkenaziSpelling,
    bool? showTeamim,
    bool? showNikud,
    bool? preferTrop,
    double? textScale,
    String? hebrewFont,
    String? Function()? latinFont,
    ExcludedDisplay? excludedDisplay,
    bool? showNotes,
    bool? conciseNotes,
    bool? collapseNotes,
    bool? collapseChazarah,
    Map<String, String>? choices,
    bool? showInstructions,
    bool? highlightToday,
    bool? typesetting,
    bool? justifyText,
    double? typeContrast,
    Minhagim? minhagim,
    AppThemeMode? themeMode,
    double? warmth,
    int? seedColor,
    bool? openLicensesOnly,
    bool? exactAlarms,
    List<String>? learningSchedules,
    bool? setupDone,
    int? seenFeatures,
    bool? shareUsage,
    bool? keepReaderAwake,
    bool? fullscreenReader,
    bool? readerDnd,
    bool? travelPrompts,
    bool? desktopTray,
    bool? omerBadge,
    bool? levanaReminder,
    bool? hachamaReminder,
    List<String>? navTabs,
    bool? navLabels,
    List<String>? expandedSettings,
  }) =>
      AppSettings(
        location: location ?? this.location,
        useElevation: useElevation ?? this.useElevation,
        hour12: hour12 != null ? hour12() : this.hour12,
        candleLightingMins: candleLightingMins ?? this.candleLightingMins,
        havdalahMins: havdalahMins != null ? havdalahMins() : this.havdalahMins,
        opinion: opinion ?? this.opinion,
        defaultBook: defaultBook != null ? defaultBook() : this.defaultBook,
        hebrewVersions: hebrewVersions ?? this.hebrewVersions,
        translationVersions: translationVersions ?? this.translationVersions,
        layout: layout ?? this.layout,
        notesLanguage: notesLanguage ?? this.notesLanguage,
        titleLanguage: titleLanguage ?? this.titleLanguage,
        uiLanguage: uiLanguage ?? this.uiLanguage,
        ashkenaziSpelling: ashkenaziSpelling ?? this.ashkenaziSpelling,
        showTeamim: showTeamim ?? this.showTeamim,
        showNikud: showNikud ?? this.showNikud,
        preferTrop: preferTrop ?? this.preferTrop,
        textScale: textScale ?? this.textScale,
        hebrewFont: hebrewFont ?? this.hebrewFont,
        latinFont: latinFont != null ? latinFont() : this.latinFont,
        excludedDisplay: excludedDisplay ?? this.excludedDisplay,
        showNotes: showNotes ?? this.showNotes,
        conciseNotes: conciseNotes ?? this.conciseNotes,
        collapseNotes: collapseNotes ?? this.collapseNotes,
        collapseChazarah: collapseChazarah ?? this.collapseChazarah,
        choices: choices ?? this.choices,
        showInstructions: showInstructions ?? this.showInstructions,
        highlightToday: highlightToday ?? this.highlightToday,
        typesetting: typesetting ?? this.typesetting,
        justifyText: justifyText ?? this.justifyText,
        typeContrast: typeContrast ?? this.typeContrast,
        minhagim: minhagim ?? this.minhagim,
        themeMode: themeMode ?? this.themeMode,
        warmth: warmth ?? this.warmth,
        seedColor: seedColor ?? this.seedColor,
        openLicensesOnly: openLicensesOnly ?? this.openLicensesOnly,
        exactAlarms: exactAlarms ?? this.exactAlarms,
        learningSchedules: learningSchedules ?? this.learningSchedules,
        setupDone: setupDone ?? this.setupDone,
        seenFeatures: seenFeatures ?? this.seenFeatures,
        shareUsage: shareUsage ?? this.shareUsage,
        keepReaderAwake: keepReaderAwake ?? this.keepReaderAwake,
        fullscreenReader: fullscreenReader ?? this.fullscreenReader,
        readerDnd: readerDnd ?? this.readerDnd,
        travelPrompts: travelPrompts ?? this.travelPrompts,
        desktopTray: desktopTray ?? this.desktopTray,
        omerBadge: omerBadge ?? this.omerBadge,
        levanaReminder: levanaReminder ?? this.levanaReminder,
        hachamaReminder: hachamaReminder ?? this.hachamaReminder,
        navTabs: navTabs ?? this.navTabs,
        navLabels: navLabels ?? this.navLabels,
        expandedSettings: expandedSettings ?? this.expandedSettings,
      );

  /// Bumped when defaults change in a way existing installs should adopt.
  static const schemaVersion = 3;

  Map<String, Object?> toJson() => {
        'v': schemaVersion,
        'location': location.toJson(),
        'useElevation': useElevation,
        'hour12': hour12,
        'candleLightingMins': candleLightingMins,
        'havdalahMins': havdalahMins,
        'opinion': opinion.name,
        'defaultBook': defaultBook,
        'hebrewVersions': hebrewVersions,
        'translationVersions': translationVersions,
        'layout': layout.name,
        'notesLanguage': notesLanguage.name,
        'titleLanguage': titleLanguage.name,
        'uiLanguage': uiLanguage.name,
        'ashkenaziSpelling': ashkenaziSpelling,
        'showTeamim': showTeamim,
        'showNikud': showNikud,
        'preferTrop': preferTrop,
        'textScale': textScale,
        'hebrewFont': hebrewFont,
        'latinFont': latinFont,
        'excludedDisplay': excludedDisplay.name,
        'showNotes': showNotes,
        'conciseNotes': conciseNotes,
        'collapseNotes': collapseNotes,
        'collapseChazarah': collapseChazarah,
        'choices': choices,
        'showInstructions': showInstructions,
        'highlightToday': highlightToday,
        'typesetting': typesetting,
        'justifyText': justifyText,
        'typeContrast': typeContrast,
        'minhagim': minhagim.toJson(),
        'themeMode': themeMode.name,
        'warmth': warmth,
        'seedColor': seedColor,
        'openLicensesOnly': openLicensesOnly,
        'exactAlarms': exactAlarms,
        'learningSchedules': learningSchedules,
        'setupDone': setupDone,
        'seenFeatures': seenFeatures,
        'shareUsage': shareUsage,
        'keepReaderAwake': keepReaderAwake,
        'fullscreenReader': fullscreenReader,
        'readerDnd': readerDnd,
        'travelPrompts': travelPrompts,
        'desktopTray': desktopTray,
        'omerBadge': omerBadge,
        'levanaReminder': levanaReminder,
        'hachamaReminder': hachamaReminder,
        'navTabs': navTabs,
        'navLabels': navLabels,
        'expandedSettings': expandedSettings,
      };

  factory AppSettings.fromJson(Map<String, Object?> j) {
    const d = AppSettings();
    // Settings saved before v2 adopt the newer defaults for spelling, font
    // and notes (they were never shown a choice).
    if (((j['v'] as num?) ?? 1) < 2) {
      j = {...j}..removeWhere((k, _) => const {'ashkenaziSpelling', 'hebrewFont', 'showNotes', 'exactAlarms'}.contains(k));
    }
    // Version choices saved before v3 predate Amud's own text (the version
    // "Amud"); they're marked, and Amud takes the place of the Sefaria
    // version it was made from (see versionOrderProvider).
    if (((j['v'] as num?) ?? 1) < 3) {
      j = {...j};
      for (final k in const ['hebrewVersions', 'translationVersions']) {
        final m = j[k];
        if (m is Map) {
          j[k] = {
            for (final e in m.entries) e.key: e.value is List ? [preCorpusVersions, ...e.value as List] : e.value,
          };
        }
      }
    }
    T pick<T>(String k, T fallback) => j[k] is T ? j[k] as T : fallback;
    E byName<E extends Enum>(List<E> values, String k, E fallback) {
      final v = j[k];
      return values.firstWhere((e) => e.name == v, orElse: () => fallback);
    }

    // One unreadable value (say, from a newer or older version) falls back
    // on its own instead of resetting every setting.
    T orElse<T>(T Function() read, T fallback) {
      try {
        return read();
      } catch (_) {
        return fallback;
      }
    }

    Map<String, List<String>> lists(String k) => orElse(
        () => {
              for (final e in ((j[k] as Map?) ?? const {}).entries)
                if (e.value is List) e.key as String: [for (final v in e.value as List) if (v is String) v],
            },
        const {});
    return AppSettings(
      location: orElse(() => SavedLocation.fromJson((j['location'] as Map).cast<String, Object?>()), d.location),
      useElevation: pick('useElevation', d.useElevation),
      hour12: j['hour12'] is bool ? j['hour12'] as bool : null,
      candleLightingMins: orElse(() => (j['candleLightingMins'] as num).toInt(), d.candleLightingMins),
      havdalahMins: j['havdalahMins'] is num ? (j['havdalahMins'] as num).toInt() : null,
      opinion: byName(ZmanimOpinion.values, 'opinion', d.opinion),
      defaultBook: j['defaultBook'] is String ? j['defaultBook'] as String : null,
      hebrewVersions: lists('hebrewVersions'),
      translationVersions: lists('translationVersions'),
      layout: byName(TextLayout.values, 'layout', d.layout),
      notesLanguage: byName(NotesLanguage.values, 'notesLanguage', d.notesLanguage),
      titleLanguage: byName(TitleLanguage.values, 'titleLanguage', d.titleLanguage),
      uiLanguage: byName(UiLanguage.values, 'uiLanguage', d.uiLanguage),
      ashkenaziSpelling: pick('ashkenaziSpelling', d.ashkenaziSpelling),
      showTeamim: pick('showTeamim', d.showTeamim),
      showNikud: pick('showNikud', d.showNikud),
      preferTrop: pick('preferTrop', d.preferTrop),
      textScale: orElse(() => (j['textScale'] as num).toDouble(), d.textScale),
      hebrewFont: pick('hebrewFont', d.hebrewFont),
      latinFont: j['latinFont'] is String ? j['latinFont'] as String : null,
      excludedDisplay: byName(ExcludedDisplay.values, 'excludedDisplay', d.excludedDisplay),
      showNotes: pick('showNotes', d.showNotes),
      conciseNotes: pick('conciseNotes', d.conciseNotes),
      collapseNotes: pick('collapseNotes', d.collapseNotes),
      collapseChazarah: pick('collapseChazarah', d.collapseChazarah),
      choices: orElse(
          () => {
                for (final e in ((j['choices'] as Map?) ?? const {}).entries)
                  if (e.value is String) e.key as String: e.value as String,
              },
          const {}),
      showInstructions: pick('showInstructions', d.showInstructions),
      highlightToday: pick('highlightToday', d.highlightToday),
      typesetting: pick('typesetting', d.typesetting),
      justifyText: pick('justifyText', d.justifyText),
      typeContrast: orElse(() => (j['typeContrast'] as num).toDouble().clamp(0.0, 1.0), d.typeContrast),
      minhagim: orElse(() => Minhagim.fromJson((j['minhagim'] as Map).cast<String, Object?>()), d.minhagim),
      // The former sepia theme is light with a warm temperature.
      themeMode: j['themeMode'] == 'sepia' ? AppThemeMode.light : byName(AppThemeMode.values, 'themeMode', d.themeMode),
      warmth: orElse(() => (j['warmth'] as num).toDouble().clamp(0.0, 1.0), j['themeMode'] == 'sepia' ? 0.8 : d.warmth),
      seedColor: orElse(() => (j['seedColor'] as num).toInt(), d.seedColor),
      openLicensesOnly: pick('openLicensesOnly', d.openLicensesOnly),
      exactAlarms: pick('exactAlarms', d.exactAlarms),
      learningSchedules: orElse(() => [for (final v in j['learningSchedules'] as List) if (v is String) v], d.learningSchedules),
      setupDone: pick('setupDone', d.setupDone),
      seenFeatures: orElse(() => (j['seenFeatures'] as num).toInt(), d.seenFeatures),
      shareUsage: pick('shareUsage', d.shareUsage),
      keepReaderAwake: pick('keepReaderAwake', d.keepReaderAwake),
      fullscreenReader: pick('fullscreenReader', d.fullscreenReader),
      readerDnd: pick('readerDnd', d.readerDnd),
      travelPrompts: pick('travelPrompts', d.travelPrompts),
      desktopTray: pick('desktopTray', d.desktopTray),
      omerBadge: pick('omerBadge', d.omerBadge),
      levanaReminder: pick('levanaReminder', d.levanaReminder),
      hachamaReminder: pick('hachamaReminder', d.hachamaReminder),
      navTabs: orElse(() {
        final tabs = {for (final v in j['navTabs'] as List) if (v is String && (allNavTabIds.contains(v) || navShortcutIds.contains(v))) v};
        final list = tabs.contains('settings') ? tabs.toList() : [...tabs, 'settings'];
        // The bar needs two items at least.
        return list.length >= 2 ? list : d.navTabs;
      }, d.navTabs),
      navLabels: pick('navLabels', d.navLabels),
      expandedSettings: orElse(() => [for (final v in j['expandedSettings'] as List) if (v is String) v], d.expandedSettings),
    );
  }

  bool get showHebrewText => layout != TextLayout.translationOnly;
  bool get showTranslationText => layout != TextLayout.hebrewOnly;
  bool get showHebrewNotes => notesLanguage != NotesLanguage.english;
  bool get showEnglishNotes => notesLanguage != NotesLanguage.hebrew;

  ThemeMode get flutterThemeMode => switch (themeMode) {
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
        AppThemeMode.system => ThemeMode.system,
      };
}

class SettingsNotifier extends Notifier<AppSettings> {
  static const _key = 'settings';

  @override
  AppSettings build() {
    final storage = ref.watch(storageProvider);
    return storage.readJson(_key, (j) => AppSettings.fromJson((j as Map).cast<String, Object?>())) ??
        const AppSettings();
  }

  void update(AppSettings Function(AppSettings s) change) {
    final old = state;
    state = change(state);
    ref.read(storageProvider).writeJson(_key, state.toJson());
    _logChanges(old, state);
  }

  /// Which settings people change, and to what (for analytics).
  static void _logChanges(AppSettings old, AppSettings now) {
    if (old.shareUsage != now.shareUsage) analytics.setEnabled(now.shareUsage);
    final a = old.toJson(), b = now.toJson();
    for (final k in b.keys) {
      if (const {'v', 'seenFeatures', 'setupDone', 'shareUsage'}.contains(k)) continue;
      if (jsonEncode(a[k]) == jsonEncode(b[k])) continue;
      if (k == 'minhagim') {
        final ma = a[k] as Map, mb = b[k] as Map;
        for (final m in mb.keys) {
          if (jsonEncode(ma[m]) != jsonEncode(mb[m])) analytics.settingChanged('minhag_$m', mb[m]);
        }
        continue;
      }
      // Only the country of a location, and only the book names of versions.
      final value = switch (k) {
        'location' => now.location.countryCode ?? (now.location.il ? 'IL' : null),
        'hebrewVersions' || 'translationVersions' || 'learningSchedules' => null,
        _ => b[k],
      };
      analytics.settingChanged(k, value);
    }
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
