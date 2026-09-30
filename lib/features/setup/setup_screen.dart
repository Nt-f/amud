import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:siddur_engine/siddur_engine.dart';

import '../../core/fonts.dart';
import '../../core/adaptive.dart';
import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../core/split_row.dart';
import '../alerts/alerts.dart';
import 'whats_new.dart';

/// First-run walkthrough of the main options. Every choice is saved as it
/// is made and can be changed later in Settings.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _pages = PageController();
  int _page = 0;

  static const _count = 7;

  void _set(AppSettings Function(AppSettings) f) => ref.read(settingsProvider.notifier).update(f);

  void _finish() {
    // Features are taught here, so none need announcing on Home.
    _set((x) => x.copyWith(setupDone: true, seenFeatures: latestFeature));
    context.go('/');
  }

  void _go(int page) {
    setState(() => _page = page);
    _pages.animateToPage(page, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = _page == _count - 1;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                child: Row(children: [
                  Expanded(child: LinearProgressIndicator(value: (_page + 1) / _count, borderRadius: BorderRadius.circular(4))),
                  TextButton(onPressed: _finish, child: Text(context.tr('Skip'))),
                ]),
              ),
              Expanded(
                child: PageView(
                  controller: _pages,
                  physics: const NeverScrollableScrollPhysics(),
                  children: const [
                    _WelcomePage(),
                    _LocationPage(),
                    _SiddurPage(),
                    _ReadingPage(),
                    _ZmanimPage(),
                    _AppearancePage(),
                    _NotificationsPage(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(children: [
                  if (_page > 0) TextButton.icon(onPressed: () => _go(_page - 1), icon: const Icon(Icons.arrow_back), label: Text(context.tr('Back'))),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: last ? _finish : () => _go(_page + 1),
                    icon: Icon(last ? Icons.check : Icons.arrow_forward),
                    label: Text(context.tr(last ? 'Start' : 'Next')),
                    style: FilledButton.styleFrom(minimumSize: const Size(140, 48), textStyle: theme.textTheme.titleMedium),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Shared page layout: a title, a short explanation and the options.
class _Page extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> children;
  const _Page({required this.icon, required this.title, this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 24), children: [
      Icon(icon, size: 40, color: theme.colorScheme.primary),
      const SizedBox(height: 12),
      Text(context.tr(title), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      if (subtitle != null) ...[
        const SizedBox(height: 6),
        Text(context.tr(subtitle!), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
      const SizedBox(height: 20),
      ...children,
    ]);
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(context.tr(text), style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
    );
  }
}

/// A full-width single-choice segmented control.
class _Choice<T> extends StatelessWidget {
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  const _Choice({required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) => ChoiceBar<T>(
        options: [for (final (v, l) in options) (v, context.tr(l), null)],
        selected: value,
        onChanged: onChanged,
      );
}

class _Switch extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Switch({required this.title, this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(context.tr(title)),
        subtitle: subtitle == null ? null : Text(context.tr(subtitle!)),
        value: value,
        onChanged: onChanged,
      );
}

class _WelcomePage extends ConsumerWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    void set(AppSettings Function(AppSettings) f) => ref.read(settingsProvider.notifier).update(f);
    return _Page(
      icon: Icons.waving_hand_outlined,
      title: 'Welcome',
      subtitle: "Let's set up your siddur. You can change any of this later in Settings.",
      children: [
        const _Label('Interface language'),
        _Choice<UiLanguage>(
          value: s.uiLanguage,
          options: [for (final l in UiLanguage.values) (l, l.native)],
          onChanged: (v) => set((x) => x.copyWith(uiLanguage: v)),
        ),
        const _Label('Spelling'),
        _Choice<bool>(
          value: s.ashkenaziSpelling,
          options: const [(true, 'Ashkenazi (Shabbos)'), (false, 'Sephardi (Shabbat)')],
          onChanged: (v) => set((x) => x.copyWith(ashkenaziSpelling: v)),
        ),
      ],
    );
  }
}

class _LocationPage extends ConsumerWidget {
  const _LocationPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    void set(AppSettings Function(AppSettings) f) => ref.read(settingsProvider.notifier).update(f);
    final theme = Theme.of(context);
    return _Page(
      icon: Icons.place_outlined,
      title: 'Location',
      subtitle: 'Used for zmanim, candle lighting and Israel or diaspora customs.',
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.location_city),
            title: Text(s.location.name, style: theme.textTheme.titleMedium),
            subtitle: Text('${s.location.tzid}${s.location.il ? ' · ${context.tr('Israel customs')}' : ''}'),
            trailing: FilledButton.tonal(onPressed: () => context.push('/settings/location'), child: Text(context.tr('Change'))),
          ),
        ),
        const SizedBox(height: 8),
        _Switch(
          title: 'Israel customs',
          subtitle: "One-day Yom Tov, Israeli parsha schedule, Tal U'Matar from 7 Cheshvan",
          value: s.location.il,
          onChanged: (v) => set((x) => x.copyWith(location: SavedLocation.fromJson({...x.location.toJson(), 'il': v}))),
        ),
        _Switch(
          title: 'Use elevation',
          subtitle: 'Sunrise and sunset as seen from your elevation',
          value: s.useElevation,
          onChanged: (v) => set((x) => x.copyWith(useElevation: v)),
        ),
      ],
    );
  }
}

class _SiddurPage extends ConsumerWidget {
  const _SiddurPage();

  static const _fonts = ['TaameyFrankCLM', 'FrankRuhlLibre', 'KeterYG', 'TaameyDavidCLM', 'EzraSIL', 'NotoSerifHebrew'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    void set(AppSettings Function(AppSettings) f) => ref.read(settingsProvider.notifier).update(f);
    final manifest = ref.watch(manifestProvider).value;
    final theme = Theme.of(context);
    final current = s.defaultBook ?? 'Siddur Ashkenaz';
    return _Page(
      icon: Icons.menu_book_outlined,
      title: 'Your siddur',
      subtitle: 'Choose your nusach, how prayers are shown and the Hebrew typeface.',
      children: [
        const _Label('Nusach'),
        if (manifest == null)
          const LinearProgressIndicator()
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: RadioGroup<String>(
              groupValue: current,
              onChanged: (v) => set((x) => x.copyWith(defaultBook: () => v)),
              child: Column(children: [
                for (final b in manifest.books)
                  RadioListTile<String>.adaptive(
                    value: b.title,
                    title: SplitRow(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      Text(context.term(b.title)),
                      Text(b.heTitle, textDirection: TextDirection.rtl, style: TextStyle(fontFamily: s.hebrewFont, fontSize: 16)),
                    ]),
                  ),
              ]),
            ),
          ),
        const _Label('Prayer text'),
        _Choice<TextLayout>(
          value: s.layout == TextLayout.translationOnly ? TextLayout.interleaved : s.layout,
          options: const [(TextLayout.hebrewOnly, 'Hebrew'), (TextLayout.interleaved, 'Bilingual'), (TextLayout.sideBySide, 'Side by side')],
          onChanged: (v) => set((x) => x.copyWith(layout: v)),
        ),
        const _Label('Hebrew font'),
        for (final f in _fonts)
          if (catalogFont(f) != null)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: s.hebrewFont == f ? theme.colorScheme.primary : Colors.transparent, width: 2),
              ),
              child: InkWell(
                onTap: () => set((x) => x.copyWith(hebrewFont: f)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    Expanded(
                      child: SplitRow(crossAxisAlignment: CrossAxisAlignment.center, children: [
                        Text(catalogFont(f)!.label, style: theme.textTheme.bodyMedium),
                        Text('בָּרוּךְ אַתָּה יְהֹוָה',
                            textDirection: TextDirection.rtl, style: TextStyle(fontFamily: f, fontSize: 22, height: 1.5)),
                      ]),
                    ),
                    if (s.hebrewFont == f) Padding(padding: const EdgeInsets.only(left: 8), child: Icon(Icons.check_circle, color: theme.colorScheme.primary)),
                  ]),
                ),
              ),
            ),
        TextButton.icon(
          onPressed: () => context.push('/settings/fonts'),
          icon: const Icon(Icons.font_download_outlined),
          label: Text(context.tr('More fonts')),
        ),
      ],
    );
  }
}

class _ReadingPage extends ConsumerWidget {
  const _ReadingPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    void set(AppSettings Function(AppSettings) f) => ref.read(settingsProvider.notifier).update(f);
    return _Page(
      icon: Icons.auto_awesome_outlined,
      title: 'Today-aware display',
      subtitle: 'The siddur knows the date and shows what is said today.',
      children: [
        const _Label('Text not said today'),
        _Choice<ExcludedDisplay>(
          value: s.excludedDisplay,
          options: const [(ExcludedDisplay.collapse, 'Collapse'), (ExcludedDisplay.dim, 'Dim'), (ExcludedDisplay.hide, 'Hide')],
          onChanged: (v) => set((x) => x.copyWith(excludedDisplay: v)),
        ),
        const _Label('Instructions & notes'),
        _Choice<NotesLanguage>(
          value: s.notesLanguage,
          options: const [(NotesLanguage.bilingual, 'Bilingual'), (NotesLanguage.english, 'English'), (NotesLanguage.hebrew, 'Hebrew')],
          onChanged: (v) => set((x) => x.copyWith(notesLanguage: v)),
        ),
        const SizedBox(height: 8),
        _Switch(title: 'Highlight what applies today', value: s.highlightToday, onChanged: (v) => set((x) => x.copyWith(highlightToday: v))),
        _Switch(title: 'Show instructions', value: s.showInstructions, onChanged: (v) => set((x) => x.copyWith(showInstructions: v))),
        _Switch(title: 'Show halachic notes', value: s.showNotes, onChanged: (v) => set((x) => x.copyWith(showNotes: v))),
        if (s.showNotes)
          _Switch(
            title: 'Short notes',
            subtitle: "Brief notes only when they apply today, instead of the siddur's full notes",
            value: s.conciseNotes,
            onChanged: (v) => set((x) => x.copyWith(conciseNotes: v)),
          ),
        if (s.showNotes && !s.conciseNotes)
          _Switch(
            title: 'Collapse halachic notes',
            subtitle: 'Show a one-line note; tap to read it',
            value: s.collapseNotes,
            onChanged: (v) => set((x) => x.copyWith(collapseNotes: v)),
          ),
        _Switch(
          title: 'Praying with a minyan',
          subtitle: 'Shows Kedusha, Chazarat HaShatz and Kaddish as applicable',
          value: s.minhagim.withMinyan,
          onChanged: (v) => set((x) => x.copyWith(minhagim: x.minhagim.copyWith(withMinyan: v))),
        ),
        _Switch(
          title: 'Collapse Chazarat HaShatz',
          subtitle: 'Kedusha, Birkat Kohanim and Modim DeRabbanan fold into a row',
          value: s.collapseChazarah,
          onChanged: (v) => set((x) => x.copyWith(collapseChazarah: v)),
        ),
        for (final f in features) Padding(padding: const EdgeInsets.only(top: 16), child: FeatureTile(f)),
      ],
    );
  }
}

class _ZmanimPage extends ConsumerWidget {
  const _ZmanimPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    void set(AppSettings Function(AppSettings) f) => ref.read(settingsProvider.notifier).update(f);
    return _Page(
      icon: Icons.wb_twilight_outlined,
      title: 'Zmanim',
      subtitle: 'Which opinion to show by default. The Zmanim page can show all of them.',
      children: [
        const _Label('Opinion'),
        _Choice<ZmanimOpinion>(
          value: s.opinion,
          options: [(ZmanimOpinion.gra, 'GRA'), (ZmanimOpinion.mga, 'MGA'), (ZmanimOpinion.baalHatanya, context.term('Baal HaTanya'))],
          onChanged: (v) => set((x) => x.copyWith(opinion: v)),
        ),
        const _Label('Time format'),
        _Choice<int>(
          value: s.hour12 == null ? 0 : (s.hour12! ? 12 : 24),
          options: const [(0, 'Automatic'), (12, '12-hour'), (24, '24-hour')],
          onChanged: (v) => set((x) => x.copyWith(hour12: () => v == 0 ? null : v == 12)),
        ),
        const _Label('Candle lighting'),
        _Choice<int>(
          value: const [18, 20, 22, 30, 40].contains(s.candleLightingMins) ? s.candleLightingMins : 18,
          options: const [(18, '18 min'), (20, '20'), (22, '22'), (30, '30'), (40, '40')],
          onChanged: (v) => set((x) => x.copyWith(candleLightingMins: v)),
        ),
        const SizedBox(height: 4),
        Text(context.tr('Minutes before sunset'), style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _AppearancePage extends ConsumerWidget {
  const _AppearancePage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    void set(AppSettings Function(AppSettings) f) => ref.read(settingsProvider.notifier).update(f);
    return _Page(
      icon: Icons.palette_outlined,
      title: 'Appearance',
      children: [
        const _Label('Theme'),
        _Choice<AppThemeMode>(
          value: s.themeMode,
          options: const [(AppThemeMode.system, 'System'), (AppThemeMode.light, 'Light'), (AppThemeMode.dark, 'Dark')],
          onChanged: (v) => set((x) => x.copyWith(themeMode: v)),
        ),
        const _Label('Warmth'),
        Row(children: [
          const Icon(Icons.ac_unit, size: 18),
          Expanded(child: Slider.adaptive(value: s.warmth, divisions: 20, onChanged: (v) => set((x) => x.copyWith(warmth: v)))),
          const Icon(Icons.local_fire_department_outlined, size: 18),
        ]),
        const _Label('Color'),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final c in const [0xFF3B5BA5, 0xFF7B5EA7, 0xFF00796B, 0xFFB5651D, 0xFF8E2C48, 0xFF455A64, 0xFF2E7D32])
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => set((x) => x.copyWith(seedColor: c)),
              child: CircleAvatar(
                radius: 20,
                backgroundColor: Color(c),
                child: s.seedColor == c ? const Icon(Icons.check, color: Colors.white) : null,
              ),
            ),
        ]),
        const _Label('Text size'),
        Row(children: [
          const Icon(Icons.text_decrease, size: 18),
          Expanded(
            child: Slider.adaptive(
              value: s.textScale,
              min: 0.7,
              max: 2.2,
              divisions: 30,
              onChanged: (v) => set((x) => x.copyWith(textScale: v)),
            ),
          ),
          const Icon(Icons.text_increase, size: 18),
        ]),
        Text('בָּרוּךְ אַתָּה יְהֹוָה אֱלֹהֵֽינוּ מֶֽלֶךְ הָעוֹלָם',
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: s.hebrewFont, fontSize: 22 * s.textScale, height: 1.6)),
      ],
    );
  }
}

class _NotificationsPage extends ConsumerStatefulWidget {
  const _NotificationsPage();

  @override
  ConsumerState<_NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<_NotificationsPage> {
  bool? _granted;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final backend = ref.watch(notificationBackendProvider);
    final theme = Theme.of(context);
    return _Page(
      icon: Icons.notifications_active_outlined,
      title: 'Zman alerts',
      subtitle: 'Get a reminder before a zman, like the latest time for Shema or candle lighting.',
      children: [
        FilledButton.tonalIcon(
          onPressed: () async {
            final ok = await backend.requestPermission(exact: s.exactAlarms);
            setState(() => _granted = ok);
          },
          icon: Icon(_granted == true ? Icons.check : Icons.notifications_outlined),
          label: Text(context.tr(_granted == true ? 'Notifications allowed' : 'Allow notifications')),
        ),
        if (_granted == false)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(context.tr('Permission was not granted. You can allow it later in your device settings.'),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          ),
        if (!backend.firesWhenClosed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(context.tr('On this platform alerts fire while the app is open.'), style: theme.textTheme.bodySmall),
          ),
        const SizedBox(height: 8),
        _Switch(
          title: 'Exact alarms (Android)',
          subtitle: 'Requires permission; otherwise alerts may be delayed a few minutes',
          value: s.exactAlarms,
          onChanged: (v) => ref.read(settingsProvider.notifier).update((x) => x.copyWith(exactAlarms: v)),
        ),
        const SizedBox(height: 8),
        Text(context.tr('Add alerts any time from the Zmanim page: tap a zman, then “Notify me”.'), style: theme.textTheme.bodySmall),
      ],
    );
  }
}
