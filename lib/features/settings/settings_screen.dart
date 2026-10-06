import 'dart:convert';
import 'package:geolocator/geolocator.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:siddur_engine/siddur_engine.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n.dart';
import '../../core/adaptive.dart';
import '../../core/search.dart';
import '../../core/fonts.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../core/titles.dart';
import '../update/update_service.dart';
import '../alerts/alerts.dart';
import '../integrations/reader_device.dart';
import 'nav_tabs_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final manifest = ref.watch(manifestProvider).value;
    final fonts = ref.watch(fontsProvider);
    final update = ref.watch(updateProvider);
    void set(AppSettings Function(AppSettings) f) => n.update(f);
    void minhag(Minhagim Function(Minhagim) f) => n.update((x) => x.copyWith(minhagim: f(x.minhagim)));

    final query = SearchQuery(ref.watch(pageSearchProvider('settings')));
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Settings')),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(PageSearchBar.height),
          child: PageSearchBar(page: 'settings', hint: context.tr('Search settings')),
        ),
      ),
      body: ListFilter(
        query: query,
        child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        AdaptiveSection(header: context.tr('Location'), children: [
          AdaptiveNavTile(
            icon: Icons.place_outlined,
            title: s.location.name,
            subtitle: '${s.location.latitude.toStringAsFixed(4)}, ${s.location.longitude.toStringAsFixed(4)} · ${s.location.tzid}'
                '${s.location.elevation > 0 ? ' · ${s.location.elevation.round()} m' : ''}',
            onTap: () => context.push('/settings/location'),
          ),
          AdaptiveSwitchTile(
            title: context.tr('Israel customs'),
            subtitle: context.tr('One-day Yom Tov, Israeli parsha schedule, Tal U\'Matar from 7 Cheshvan'),
            value: s.location.il,
            onChanged: (v) => set((x) => x.copyWith(
                location: SavedLocation(
                    name: x.location.name,
                    latitude: x.location.latitude,
                    longitude: x.location.longitude,
                    elevation: x.location.elevation,
                    tzid: x.location.tzid,
                    countryCode: x.location.countryCode,
                    il: v))),
          ),
        ]),
        AdaptiveSection(header: context.tr('Zmanim'), children: [
          AdaptiveNavTile(
            icon: Icons.rule,
            title: context.tr('Default opinion'),
            subtitle: switch (s.opinion) {
              ZmanimOpinion.gra => 'GRA',
              ZmanimOpinion.mga => 'Magen Avraham',
              ZmanimOpinion.baalHatanya => 'Baal HaTanya',
            },
            onTap: () async {
              final v = await showAdaptivePicker(context, title: context.tr('Opinion'), selected: s.opinion, options: const [
                (ZmanimOpinion.gra, 'GRA'),
                (ZmanimOpinion.mga, 'Magen Avraham'),
                (ZmanimOpinion.baalHatanya, 'Baal HaTanya'),
              ]);
              if (v != null) set((x) => x.copyWith(opinion: v));
            },
          ),
          AdaptiveSwitchTile(
            title: context.tr('Elevation-adjusted sunrise/sunset'),
            value: s.useElevation,
            onChanged: (v) => set((x) => x.copyWith(useElevation: v)),
          ),
          AdaptiveNavTile(
            icon: Icons.local_fire_department_outlined,
            title: context.tr('Candle lighting'),
            subtitle: context.tr('{n} minutes before sunset', {'n': s.candleLightingMins}),
            onTap: () async {
              final v = await showAdaptivePicker(context,
                  title: context.tr('Candle lighting'),
                  selected: s.candleLightingMins,
                  options: [for (final m in const [15, 18, 20, 22, 24, 30, 40]) (m, context.tr('{n} minutes', {'n': m}))]);
              if (v != null) set((x) => x.copyWith(candleLightingMins: v));
            },
          ),
          AdaptiveNavTile(
            icon: Icons.auto_awesome_outlined,
            title: context.tr('Havdalah'),
            subtitle: s.havdalahMins == null ? context.tr('Nightfall (8.5°)') : context.tr('{n} minutes after sunset', {'n': s.havdalahMins}),
            onTap: () async {
              final v = await showAdaptivePicker<int>(context, title: context.tr('Havdalah'), selected: s.havdalahMins ?? 0, options: [
                (0, context.tr('Nightfall (8.5°)')),
                for (final m in const [42, 50, 72]) (m, context.tr('{n} minutes', {'n': m})),
              ]);
              if (v != null) set((x) => x.copyWith(havdalahMins: () => v == 0 ? null : v));
            },
          ),
          AdaptiveNavTile(
            icon: Icons.schedule,
            title: context.tr('Time format'),
            subtitle: context.tr(s.hour12 == null ? 'Automatic' : (s.hour12! ? '12-hour' : '24-hour')),
            onTap: () async {
              final v = await showAdaptivePicker<int>(context, title: context.tr('Time format'), options: [
                (0, context.tr('Automatic')),
                (12, context.tr('12-hour')),
                (24, context.tr('24-hour')),
              ]);
              if (v != null) set((x) => x.copyWith(hour12: () => v == 0 ? null : v == 12));
            },
          ),
        ]),
        AdaptiveSection(header: context.tr('Siddur'), children: [
          AdaptiveNavTile(
            icon: Icons.menu_book,
            title: context.tr('Default siddur'),
            subtitle: () {
              final b = manifest?.book(s.defaultBook ?? 'Siddur Ashkenaz');
              return b == null ? context.term(s.defaultBook ?? 'Siddur Ashkenaz') : context.prayerTitle(s, b.title, b.heTitle);
            }(),
            onTap: manifest == null
                ? null
                : () async {
                    final v = await showAdaptivePicker(context,
                        title: context.tr('Default siddur'),
                        selected: s.defaultBook,
                        options: [for (final b in manifest.books) (b.title, context.prayerTitle(s, b.title, b.heTitle))]);
                    if (v != null) set((x) => x.copyWith(defaultBook: () => v));
                  },
          ),
          AdaptiveSwitchTile(
            title: context.tr('Open-licensed texts only'),
            subtitle: context.tr('Only offer versions under public domain / Creative Commons licenses'),
            value: s.openLicensesOnly,
            onChanged: (v) => set((x) => x.copyWith(openLicensesOnly: v)),
          ),
          AdaptiveNavTile(
            icon: Icons.translate,
            title: context.tr('Prayer text'),
            subtitle: context.tr(_layoutLabel(s.layout)),
            onTap: () async {
              final v = await showAdaptivePicker(context, title: context.tr('Prayer text'), selected: s.layout, options: [
                for (final l in const [TextLayout.hebrewOnly, TextLayout.interleaved, TextLayout.sideBySide]) (l, context.tr(_layoutLabel(l))),
              ]);
              if (v != null) set((x) => x.copyWith(layout: v));
            },
          ),
          AdaptiveNavTile(
            icon: Icons.sticky_note_2_outlined,
            title: context.tr('Instructions & notes language'),
            subtitle: context.tr(_notesLabel(s.notesLanguage)),
            onTap: () async {
              final v = await showAdaptivePicker(context,
                  title: context.tr('Instructions & notes'), selected: s.notesLanguage, options: [for (final l in NotesLanguage.values) (l, context.tr(_notesLabel(l)))]);
              if (v != null) set((x) => x.copyWith(notesLanguage: v));
            },
          ),
          AdaptiveNavTile(
            icon: Icons.title,
            title: context.tr('Prayer title language'),
            subtitle: context.tr(titleLanguageLabel(s.titleLanguage)),
            onTap: () async {
              final v = await showAdaptivePicker(context,
                  title: context.tr('Prayer title language'),
                  selected: s.titleLanguage,
                  options: [for (final l in TitleLanguage.values) (l, context.tr(titleLanguageLabel(l)))]);
              if (v != null) set((x) => x.copyWith(titleLanguage: v));
            },
          ),
          AdaptiveNavTile(
            icon: Icons.visibility_off_outlined,
            title: context.tr('Text not said today'),
            subtitle: context.tr(_excludedLabel(s.excludedDisplay)),
            onTap: () async {
              final v = await showAdaptivePicker(context,
                  title: context.tr('Text not said today'),
                  selected: s.excludedDisplay,
                  options: [for (final e in ExcludedDisplay.values) (e, context.tr(_excludedLabel(e)))]);
              if (v != null) set((x) => x.copyWith(excludedDisplay: v));
            },
          ),
          AdaptiveSwitchTile(title: context.tr('Show halachic notes'), value: s.showNotes, onChanged: (v) => set((x) => x.copyWith(showNotes: v))),
          if (s.showNotes)
            AdaptiveSwitchTile(
                title: context.tr('Short notes'),
                subtitle: context.tr("Brief notes only when they apply today, instead of the siddur's full notes"),
                value: s.conciseNotes,
                onChanged: (v) => set((x) => x.copyWith(conciseNotes: v))),
          if (s.showNotes && !s.conciseNotes)
            AdaptiveSwitchTile(
                title: context.tr('Collapse halachic notes'),
                subtitle: context.tr('Show a one-line note; tap to read it'),
                value: s.collapseNotes,
                onChanged: (v) => set((x) => x.copyWith(collapseNotes: v))),
          AdaptiveSwitchTile(
              title: context.tr('Collapse Chazarat HaShatz'),
              subtitle: context.tr("Kedusha, Birkat Kohanim and Modim DeRabbanan fold into a row"),
              value: s.collapseChazarah,
              onChanged: (v) => set((x) => x.copyWith(collapseChazarah: v))),
        ]),
        AdaptiveSection(header: context.tr('Customs (minhagim)'), children: [
          AdaptiveSwitchTile(title: context.tr('Praying with a minyan'), value: s.minhagim.withMinyan, onChanged: (v) => minhag((m) => m.copyWith(withMinyan: v))),
          AdaptiveSwitchTile(
              title: context.tr('LeDavid through Shmini Atzeret'),
              subtitle: context.tr('Otherwise until Hoshana Raba'),
              value: s.minhagim.ledavidThroughShminiAtzeret,
              onChanged: (v) => minhag((m) => m.copyWith(ledavidThroughShminiAtzeret: v))),
          AdaptiveSwitchTile(
              title: context.tr('Walled city (Shushan Purim)'),
              subtitle: context.tr('Celebrate Purim on the 15th of Adar (e.g. Jerusalem)'),
              value: s.minhagim.walledCity,
              onChanged: (v) => minhag((m) => m.copyWith(walledCity: v))),
          AdaptiveSwitchTile(
              title: context.tr('Kiddush Levana from 3 days'),
              subtitle: context.tr('Otherwise from 7 days after the molad'),
              value: s.minhagim.kiddushLevana3Days,
              onChanged: (v) => minhag((m) => m.copyWith(kiddushLevana3Days: v))),
          AdaptiveSwitchTile(
              title: context.tr('Tefillin on Chol HaMoed'),
              subtitle: context.tr('Otherwise not worn on Chol HaMoed'),
              value: s.minhagim.tefillinCholHamoed,
              onChanged: (v) => minhag((m) => m.copyWith(tefillinCholHamoed: v))),
          AdaptiveSwitchTile(title: context.tr('Mourner (aveil)'), value: s.minhagim.mourner, onChanged: (v) => minhag((m) => m.copyWith(mourner: v))),
        ]),
        AdaptiveSection(header: context.tr('Appearance'), children: [
          AdaptiveNavTile(
            icon: Icons.language,
            title: context.tr('Interface language'),
            subtitle: s.uiLanguage.native,
            onTap: () async {
              final v = await showAdaptivePicker(context,
                  title: context.tr('Interface language'), selected: s.uiLanguage, options: [for (final l in UiLanguage.values) (l, l.native)]);
              if (v != null) set((x) => x.copyWith(uiLanguage: v));
            },
          ),
          AdaptiveSwitchTile(
            title: context.tr('Ashkenazi spelling'),
            subtitle: context.tr('Shabbos, Sukkos, Shacharis in English text'),
            value: s.ashkenaziSpelling,
            onChanged: (v) => set((x) => x.copyWith(ashkenaziSpelling: v)),
          ),
          AdaptiveNavTile(
            icon: Icons.palette_outlined,
            title: context.tr('Theme'),
            subtitle: context.tr(s.themeMode.label),
            onTap: () async {
              final v = await showAdaptivePicker(context,
                  title: context.tr('Theme'), selected: s.themeMode, options: [for (final m in AppThemeMode.values) (m, context.tr(m.label))]);
              if (v != null) set((x) => x.copyWith(themeMode: v));
            },
          ),
          FilterKeywords(
            keywords: [context.tr('Warmth'), context.tr('Theme'), 'sepia'],
            child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(children: [
              const Icon(Icons.thermostat_outlined, size: 20),
              const SizedBox(width: 12),
              Text(context.tr('Warmth')),
              Expanded(
                child: Slider.adaptive(
                  value: s.warmth,
                  divisions: 20,
                  label: s.warmth == 0 ? context.tr('Neutral') : '${(s.warmth * 100).round()}%',
                  onChanged: (v) => set((x) => x.copyWith(warmth: v)),
                ),
              ),
            ]),
          ),
          ),
          FilterKeywords(
            keywords: [context.tr('Color'), context.tr('Theme')],
            child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Wrap(spacing: 10, runSpacing: 10, children: [
              for (final c in const [0xFF3B5BA5, 0xFF7B5EA7, 0xFF00796B, 0xFFB5651D, 0xFF8E2C48, 0xFF455A64, 0xFF2E7D32])
                InkWell(
                  onTap: () => set((x) => x.copyWith(seedColor: c)),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(c),
                    child: s.seedColor == c ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                  ),
                ),
            ]),
          ),
          ),
          AdaptiveNavTile(
            icon: Icons.font_download_outlined,
            title: context.tr('Fonts'),
            subtitle: '${fontLabel(s.hebrewFont, fonts)} · ${context.tr('{n} fonts to preview', {'n': fontCatalog.length + fonts.length})}',
            onTap: () => context.push('/settings/fonts'),
          ),
          AdaptiveNavTile(
            icon: Icons.view_week_outlined,
            title: context.tr('Navigation bar'),
            subtitle: [for (final id in s.navTabs) context.tr(navTabs.firstWhere((t) => t.$1 == id).$5)].join(' · '),
            onTap: () => context.push('/settings/tabs'),
          ),
        ]),
        AdaptiveSection(header: context.tr('Reading & device'), children: [
          AdaptiveSwitchTile(title: context.tr('Keep screen on while reading'), value: s.keepReaderAwake,
            onChanged: (v) => set((x) => x.copyWith(keepReaderAwake: v))),
          AdaptiveSwitchTile(title: context.tr('Full-screen reader'), subtitle: context.tr('Hide the phone status and navigation bars while reading'), value: s.fullscreenReader,
            onChanged: (v) => set((x) => x.copyWith(fullscreenReader: v))),
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
            AdaptiveSwitchTile(
                title: context.tr('Do Not Disturb while reading'),
                subtitle: context.tr('Silence calls and notifications in the siddur, and restore them after'),
                value: s.readerDnd,
                onChanged: (v) async {
                  if (v && !await readerDndAccess()) {
                    // Android asks once, on its own settings screen.
                    await openReaderDndSettings();
                    if (!await readerDndAccess()) return;
                  }
                  set((x) => x.copyWith(readerDnd: v));
                }),
          if (kIsWeb || defaultTargetPlatform != TargetPlatform.linux)
          AdaptiveSwitchTile(title: context.tr('Offer to update location when traveling'), value: s.travelPrompts,
            onChanged: (v) async {
              if (v) {
                var permission = await Geolocator.checkPermission();
                if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
                if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
              }
              set((x) => x.copyWith(travelPrompts: v));
            }),
          if (!kIsWeb && {TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux}.contains(defaultTargetPlatform))
          AdaptiveSwitchTile(title: context.tr('Show next zman in desktop tray'), value: s.desktopTray,
            onChanged: (v) => set((x) => x.copyWith(desktopTray: v))),
          if (kIsWeb)
          AdaptiveSwitchTile(title: context.tr('Omer reminder badge'), value: s.omerBadge,
            onChanged: (v) => set((x) => x.copyWith(omerBadge: v))),
        ]),
        AdaptiveSection(header: context.tr('Notifications & learning'), children: [
          AdaptiveNavTile(icon: Icons.notifications_active_outlined, title: context.tr('Zman alerts'), onTap: () => context.push('/alerts')),
          AdaptiveSwitchTile(
            title: context.tr('Exact alarms (Android)'),
            subtitle: context.tr('Requires permission; otherwise alerts may be delayed a few minutes'),
            value: s.exactAlarms,
            onChanged: (v) async {
              set((x) => x.copyWith(exactAlarms: v));
              if (v) await ref.read(notificationBackendProvider).requestPermission(exact: true);
            },
          ),
          AdaptiveNavTile(icon: Icons.event_repeat, title: context.tr('Personal Hebrew dates'), onTap: () => context.push('/personal-dates')),
          AdaptiveSwitchTile(title: context.tr('Kiddush Levana reminder'), subtitle: context.tr('At nightfall while the window is open'), value: s.levanaReminder,
            onChanged: (v) async { if (v && !await ref.read(notificationBackendProvider).requestPermission()) return; set((x) => x.copyWith(levanaReminder: v)); }),
          AdaptiveSwitchTile(title: context.tr('Birkat HaChama reminder'), value: s.hachamaReminder,
            onChanged: (v) async { if (v && !await ref.read(notificationBackendProvider).requestPermission()) return; set((x) => x.copyWith(hachamaReminder: v)); }),
          AdaptiveNavTile(icon: Icons.menu_book_outlined, title: context.tr('Daily learning'), onTap: () => context.push('/learning')),
        ]),
        AdaptiveSection(header: context.tr('Offline'), children: [
          AdaptiveNavTile(
            icon: Icons.offline_pin_outlined,
            title: context.tr('Offline & storage'),
            subtitle: context.tr('What works without a connection, downloads, and the room they take'),
            onTap: () => context.push('/settings/offline'),
          ),
        ]),
        AdaptiveSection(header: context.tr('Advanced'), children: [
          AdaptiveNavTile(icon: Icons.widgets_outlined, title: context.tr('Card gallery'), onTap: () => context.push('/settings/cards')),
          AdaptiveNavTile(icon: Icons.link, title: context.tr('Widgets, shortcuts & voice'), onTap: () => context.push('/settings/integrations')),

          AdaptiveSwitchTile(
            title: context.tr('Share anonymous usage'),
            subtitle: context.tr('Which screens, features and prayers or texts are opened, to improve Amud. Nothing you type, no names, no exact location.'),
            value: s.shareUsage,
            onChanged: (v) => set((x) => x.copyWith(shareUsage: v)),
          ),
          AdaptiveNavTile(
            icon: Icons.tune,
            title: context.tr('Custom siddur rules'),
            subtitle: context.tr('Show or hide sections by condition'),
            onTap: () => context.push('/settings/rules'),
          ),
        ]),
        AdaptiveSection(header: context.tr('About'), children: [
          if (updatesSupported || playUpdates)
            AdaptiveNavTile(
              icon: Icons.system_update_outlined,
              title: context.tr('App updates'),
              subtitle: update.pending != null
                  ? context.tr('Version {v} is available', {'v': update.pending!.version})
                  : update.playPending
                      ? context.tr('A new version is available')
                      : update.currentVersion.isEmpty
                      ? null
                      : context.tr('Version {v}', {'v': update.currentVersion}),
              onTap: () => context.push('/update'),
            ),
          AdaptiveNavTile(
            icon: Icons.info_outline,
            title: context.tr('Licenses & sources'),
            subtitle: context.tr('Sefaria texts, Hebcal (GPL-2.0), fonts (OFL)'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Amud',
              applicationLegalese: 'Calendar and zmanim: a Dart port of Hebcal (GPL-2.0-or-later) and @hebcal/noaa (LGPL-2.1). '
                  'Liturgical texts: Sefaria and the respective translators/publishers, under each version\'s license. '
                  'Tehillim: Miqra according to the Masorah (CC-BY-SA) and JPS 1917 (public domain), via Sefaria. '
                  'Fonts: SIL Open Font License; Culmus fonts under GPL-2.0 with the font exception.',
            ),
          ),
          AdaptiveNavTile(
            icon: Icons.privacy_tip_outlined,
            title: context.tr('Privacy policy'),
            onTap: () => launchUrl(Uri.parse('https://amud.page/privacy/'), mode: LaunchMode.externalApplication),
          ),
        ]),
        ]),
      ),
    );
  }
}

/// Editor for user section rules (JSON), applied on top of built-ins.
class CustomRulesScreen extends ConsumerStatefulWidget {
  const CustomRulesScreen({super.key});

  @override
  ConsumerState<CustomRulesScreen> createState() => _CustomRulesScreenState();
}

class _CustomRulesScreenState extends ConsumerState<CustomRulesScreen> {
  late final _ctrl = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(ref.read(customRulesProvider)));
  String? _error;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _addRule(Map<String, Object?> rule) {
    try {
      final rules = (jsonDecode(_ctrl.text) as List).cast<Map>().map((m) => m.cast<String, Object?>()).toList();
      SectionRule.fromJson(rule).condition;
      rules.insert(0, rule); // custom rules are first-match wins
      setState(() { _ctrl.text = const JsonEncoder.withIndent('  ').convert(rules); _error = null; });
    } catch (e) { setState(() => _error = '$e'); }
  }

  Future<void> _buildRule() async {
    final title = TextEditingController(), label = TextEditingController();
    var condition = 'true';
    var regex = false;
    var invert = false;
    final result = await showDialog<Map<String, Object?>>(context: context, builder: (c) => StatefulBuilder(builder: (c, update) => AlertDialog(
      title: Text(context.tr('Build a rule')),
      content: SizedBox(width: 400, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: InputDecoration(labelText: context.tr('Section title'))),
        SwitchListTile.adaptive(title: Text(context.tr('Match with a regular expression')), value: regex, onChanged: (v) => update(() => regex = v)),
        DropdownButtonFormField<String>(initialValue: condition, items: [
          const DropdownMenuItem(value: 'true', child: Text('Every day')),
          for (final variable in ['weekday', 'shabbat', 'yomTov', 'roshChodesh', 'chanukah', 'omer', 'minyan', 'mourner', 'tachanun'])
            DropdownMenuItem(value: variable, child: Text(DayContext.variableDocs[variable]!)),
        ], onChanged: (v) => condition = v!),
        SwitchListTile.adaptive(title: Text(context.tr('Hide when this condition is true')), value: invert, onChanged: (v) => update(() => invert = v)),
        TextField(controller: label, decoration: InputDecoration(labelText: context.tr('Explanation shown in the reader'))),
      ]))), actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(context.tr('Cancel'))),
        FilledButton(onPressed: () {
          if (title.text.trim().isEmpty) return;
          final rule = <String, Object?>{'title': regex ? title.text.trim() : '^${RegExp.escape(title.text.trim())}\$',
            'when': invert ? '!($condition)' : condition, 'labelEn': label.text.trim()};
          try { SectionRule.fromJson(rule).condition; Navigator.pop(c, rule); }
          catch (e) { ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('$e'))); }
        }, child: Text(context.tr('Add rule')))])));
    title.dispose(); label.dispose();
    if (result != null) _addRule(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Custom rules')), actions: [
        TextButton(
          onPressed: () {
            try {
              final list = (jsonDecode(_ctrl.text) as List).cast<Map>().map((m) => m.cast<String, Object?>()).toList();
              for (final r in list) {
                SectionRule.fromJson(r).condition; // validates regex & condition
              }
              ref.read(customRulesProvider.notifier).set(list);
              setState(() => _error = null);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Rules saved'))));
            } catch (e) {
              setState(() => _error = '$e');
            }
          },
          child: Text(context.tr('Save')),
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        FilledButton.icon(onPressed: _buildRule, icon: const Icon(Icons.add), label: Text(context.tr('Build a rule'))),
        const SizedBox(height: 12),
        Text(context.tr('Custom presets'), style: theme.textTheme.titleSmall),
        Wrap(spacing: 8, children: [
          ActionChip(label: Text(context.tr('Say Tachanun on Pesach Sheni')), onPressed: () => _addRule({
            'title': r'tachanun|supplication',
            'when': 'tachanun || (hMonth == 2 && hDay == 14 && weekday && (shacharit || mincha))',
            'labelEn': 'Tachanun on Pesach Sheni by my custom',
          })),
          ActionChip(label: Text(context.tr('Skip Korbanot')), onPressed: () => _addRule({'title': r'korbanot|korbanos|sacrifices', 'when': 'false', 'labelEn': 'Skipped by my custom'})),
          ActionChip(label: Text(context.tr('Omit Tachanun')), onPressed: () => _addRule({'title': r'tachanun|supplication', 'when': 'false', 'labelEn': 'Omitted by my custom'})),
        ]),
        const SizedBox(height: 12),
        Text(
          'Each rule matches sections by English title (regex) and shows them only when the condition is true. '
          'Fields: title, within?, notWithin?, when, labelEn?, labelHe?, service?.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ctrl,
          maxLines: 14,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: InputDecoration(border: const OutlineInputBorder(), errorText: _error, errorMaxLines: 4),
        ),
        const SizedBox(height: 16),
        Text(context.tr('Condition variables'), style: theme.textTheme.titleSmall),
        for (final e in DayContext.variableDocs.entries)
          ListTile(dense: true, title: Text(e.key, style: const TextStyle(fontFamily: 'monospace')), subtitle: Text(e.value)),
      ]),
    );
  }
}

String _layoutLabel(TextLayout l) => switch (l) {
      TextLayout.hebrewOnly => 'Hebrew only',
      TextLayout.interleaved => 'Hebrew & English',
      TextLayout.sideBySide => 'Side by side',
      TextLayout.translationOnly => 'English only',
    };

String _notesLabel(NotesLanguage l) => switch (l) {
      NotesLanguage.bilingual => 'Hebrew & English',
      NotesLanguage.english => 'English only',
      NotesLanguage.hebrew => 'Hebrew only',
    };

String titleLanguageLabel(TitleLanguage l) => switch (l) {
      TitleLanguage.auto => 'Same as the app',
      TitleLanguage.english => 'English',
      TitleLanguage.hebrew => 'Hebrew',
      TitleLanguage.both => 'English & Hebrew',
    };

String _excludedLabel(ExcludedDisplay e) => switch (e) {
      ExcludedDisplay.collapse => 'Collapse',
      ExcludedDisplay.dim => 'Dim',
      ExcludedDisplay.hide => 'Hide',
    };
