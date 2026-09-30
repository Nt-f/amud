# Siddur

An offline, interactive siddur. It uses Sefaria texts, a full Hebcal port for
the calendar and zmanim, and has reminders and a customizable home screen.
It runs on Android, Windows and the web (as an installable PWA). The Linux,
macOS and iOS projects build too, but nothing is released for them.

- **Web:** https://siddur.nt-wrks.xyz
- **Android / Windows:** [latest release](https://github.com/Nt-f/flutter_siddur/releases/latest)
  (`siddur-android.apk`, `siddur-windows.zip`). The apps check for new
  releases and offer to install them (Settings → App updates).

## Features

- **Siddur:** Ashkenaz, Sefard, Edot HaMizrach, Chabad and Koren siddurim from
  Sefaria, all bundled, with a choice of translations and "Text versions"
  per book. The text follows the day: Ya'aleh VeYavo, Hallel, Al HaNissim,
  Tachanun, the Omer and so on are shown or hidden by rules in
  `assets/rules/rules.json`, which you can add to under Settings → Custom siddur rules.
- **Reading:** Hebrew and translation side by side, interleaved or alone.
  There are about 40 bundled Hebrew fonts, and an optional Ashkenazi
  spelling for English text (Shabbos, Shacharis). Double-tap the text for **focus
  mode**, which hides the top and bottom bars.
- **Home:** a dashboard of cards you can rearrange and resize (tap the
  dashboard icon to edit). Cards include:
  - the Hebrew date and parsha
  - Sefirat HaOmer, shown only while it's being counted
  - what changes in davening today
  - quick prayers (davening, after meals, Tefillat HaDerech, bedtime Shema)
  - daily learning
  - finding a minyan (GoDaven)
  - candle lighting
  - the next zman and a list of zmanim
  - upcoming days
  - notes, and your own cards written in JavaScript
- **Zmanim and calendar:** GRA, Magen Avraham or Baal HaTanya opinions,
  custom zmanim, and a Jewish calendar with holidays and parshiyos.
- **Tehillim:** the day's portion by month or by week, Shir shel Yom, and your progress saved.
- **Reminders:** notifications before any zman, such as candle lighting or
  the latest Shema.
- **Languages:** English, Hebrew and Yiddish interface.
- **Offline:** everything, including every text and font, ships with the
  app. The web app caches itself on the first visit.

## Development

Requires Flutter 3.41 (the version CI uses is in `.github/workflows/build.yml`).

    flutter pub get
    flutter run                 # or: flutter run -d chrome
    flutter analyze
    flutter test

Layout:

| Path | What |
| --- | --- |
| `lib/core/` | settings, theme, routing helpers, localization (`l10n.dart`: `tr()` for translations, `term()` for Ashkenazi spellings) |
| `lib/features/` | one folder per screen or area: `home` (dashboard and card registry), `siddur`, `zmanim`, `calendar`, `tehillim`, `alerts`, `setup` (first-run walkthrough and "What's new"), `update`, and others |
| `packages/hebcal/` | Dart port of Hebcal: dates, holidays, zmanim, learning schedules |
| `packages/siddur_engine/` | parses Sefaria siddurim and applies the day's rules |
| `assets/sefaria/` | bundled texts, from `dart run tool/sefaria_sync.dart` |
| `assets/rules/rules.json` | which sections and inserts are said on which days |
| `tool/` | web build, service worker generator, Sefaria and Tehillim sync |

### Adding a feature announcement

When you add something users should know about, add a `Feature` to
`features` in `lib/features/setup/whats_new.dart` with the next `id`. New
users see it in the setup walkthrough. People who already finished setup get
a one-time "What's new" card on Home.

## Releasing

**Apps:** push a version tag, for example:

    git tag v0.2.0 && git push origin v0.2.0

GitHub Actions builds the Android APK and the Windows zip and publishes them
as a GitHub Release, which the in-app updater picks up. Android signing needs
these repository secrets:

- `SIDDUR_KEYSTORE_BASE64`
- `SIDDUR_KEYSTORE_PASSWORD`
- `SIDDUR_KEY_ALIAS`
- `SIDDUR_KEY_PASSWORD`

They must hold the same key as local builds (`android/key.properties`, not
committed). Otherwise Android won't install one build over the other.

**Web:** see [DEPLOY.md](DEPLOY.md).

## Licenses

Texts are from [Sefaria](https://www.sefaria.org). Each version keeps its own
license, which is listed in `assets/sefaria/manifest.json` and shown in the
app (Settings → Licenses & sources). Hebcal is GPL-2.0. Font licenses are
in `assets/fonts/`.
