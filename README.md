# Amud

An offline, interactive siddur. It uses Sefaria texts, a full Hebcal port for
the calendar and zmanim, and has reminders and a customizable home screen.
It runs on Android, Windows, macOS, Linux and the web (as an installable
PWA). iOS builds are released unsigned, for sideloading.

- **Website:** https://amud.page (the web app is at https://amud.page/app/)
- **Apps:** [latest release](https://github.com/Nt-f/amud/releases/latest):
  `amud-android.apk`, `amud-windows.zip`, `amud-macos.zip`,
  `amud-linux-x64.tar.gz`, `amud-ios-unsigned.ipa`, and `amud-web.zip` (the
  built site). The apps check for new releases. Android downloads and
  installs them in the app; Windows and Linux open the download (Settings →
  App updates).

## Features

- **Siddur:** Ashkenaz, Sefard, Edot HaMizrach, Chabad and Koren siddurim from
  Sefaria, all bundled, with a choice of translations and "Text versions"
  per book. The text follows the day: Ya'aleh VeYavo, Hallel, Al HaNissim,
  Tachanun, the Omer and so on are shown or hidden by rules in
  `assets/rules/rules.json`, which you can add to under Settings → Custom siddur rules.
- **Jump through the davening:** opening Shacharis, Mincha or Maariv (from
  Home, the Siddur tab or a siddur's contents) shows a bar of its key points,
  such as Shema, Shemoneh Esrei, Hallel and the Torah reading, and of what's
  added today from elsewhere in the siddur, like Musaf or the day's Hoshana.
- **Why today?** Open the date guide from Home or the reader to see why
  additions and omissions apply. Inspect a prayer's conditions, including
  custom rules, and preview another date without changing the reader's date.
- **Explain this line:** Select words in the reader and choose *Explain this
  line* for the bundled translation, a small offline vocabulary glossary,
  curated context where available, biblical references, and text sources.
- **Prepare for tomorrow:** Open tomorrow's guide from Home, or add its
  dashboard card. It shows special additions, omissions, and changes in
  seasonal wording, with links to the bundled prayers.
- **Print a siddur:** Use the print button in the Siddur tab or date guide.
  Choose any date, services, and Hebrew and/or translation, then preview,
  print, or save a PDF. Text follows the same calendar and customs as the
  reader; evening services belong to the next Hebrew date. PDFs include
  source credits. Festival services use the available bundled texts; days
  requiring a machzor are marked as incomplete.
- **Holidays & Seasons:** Hoshanos, Lulav, Selichos, Chanukah candles,
  Hakafos and other holiday prayers in one place, gathered from the bundled
  siddurim (your nusach first), with today's marked.
- **Reading:** Hebrew and translation side by side, interleaved or alone.
  There are about 40 bundled Hebrew fonts, and an optional Ashkenazi
  spelling for English text (Shabbos, Shacharis). Double-tap the text for **focus
  mode**, which hides the top and bottom bars.
- **Home:** a dashboard of cards you can rearrange and resize (*Edit
  dashboard* is below the cards). Cards include:
  - the Hebrew date and parsha
  - Sefirat HaOmer, shown only while it's being counted
  - what changes in davening today
  - quick prayers (davening, after meals, Tefillat HaDerech, bedtime Shema)
  - daily learning
  - finding a minyan (GoDaven)
  - candle lighting
  - the next zman, a month calendar, and a list of zmanim
  - upcoming days
  - notes, and your own cards written in JavaScript, which can fetch data
    from the web (guide: [`skills/js-card/SKILL.md`](skills/js-card/SKILL.md),
    also usable as an AI agent skill)
- **Zmanim and calendar:** GRA, Magen Avraham or Baal HaTanya opinions,
  custom zmanim, and a Jewish calendar (a Home card) with holidays and parshiyos.
- **Torah:** texts downloaded from Sefaria on request (not bundled) and kept
  for offline learning. Halacha has the Kitzur Shulchan Aruch, with today's
  Kitzur Yomi highlighted; Chumash, Gemara and the other categories are still
  in progress.
- **Tehillim:** the day's portion by month or by week, Shir shel Yom, and your progress saved.
- **Reminders:** notifications before any zman, such as candle lighting or
  the latest Shema.
- **Languages:** English, Hebrew and Yiddish interface. Prayer titles can
  be shown in English, Hebrew or both, apart from the interface language.
- **Offline:** every siddur text and font ships with the app (Torah tab
  books are a one-time download). The web app caches itself on the first visit.

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
| `lib/features/` | one folder per screen or area: `home` (dashboard and card registry), `siddur`, `torah` (downloadable texts), `zmanim`, `calendar`, `tehillim`, `alerts`, `setup` (first-run walkthrough, "What's new" and the launch animation), `update`, and others |
| `packages/hebcal/` | Dart port of Hebcal: dates, holidays, zmanim, learning schedules |
| `packages/siddur_engine/` | parses Sefaria siddurim and applies the day's rules |
| `assets/sefaria/` | bundled texts, from `dart run tool/sefaria_sync.dart` |
| `assets/rules/rules.json` | which sections and inserts are said on which days |
| `assets/brand/` | the Amud logo as SVG |
| `landing/` | the static landing page at amud.page's root (the app is under `/app/`) |
| `tool/` | web build, service worker generator, Sefaria and Tehillim sync, `make_icons.py` (every platform's app icon from the logo; needs ImageMagick with librsvg) |

### Adding a feature announcement

When you add something users should know about, add a `Feature` to
`features` in `lib/features/setup/whats_new.dart` with the next `id`. New
users see it in the setup walkthrough. People who already finished setup get
a one-time "What's new" card on Home.

## Analytics

Anonymous usage analytics go to one Google Analytics 4 property (Firebase
project `amud-7a475`, `lib/core/analytics.dart`). Android, iOS, macOS and
the web use Firebase Analytics. Windows and Linux send to the same
property's web data stream with the GA4 Measurement Protocol.

Events say what was used and read (screens, sections and text versions,
simanim, psalms, searches, settings) but nothing links them to a person:
there's no user id or user properties, no advertising id, and the app gets
a new anonymous id each time it starts (a session cookie on the web).
Active users are counted by check-ins instead of an id: each install sends
`active_day` once a day and `active_month` once a calendar month, so MAU is
the count of `active_month` events for a month (GA's own "users" figure
counts app starts). Users can turn it off under Settings → Advanced → Share anonymous usage.
It's off in debug builds unless you pass `--dart-define=ANALYTICS_DEBUG=true`.

`lib/firebase_options.dart` is generated by `flutterfire configure
--platforms=android,ios,macos,web`. For Windows and Linux, create a
Measurement Protocol API secret on the web data stream and build with
`--dart-define=GA_API_SECRET=<secret>`; without it they send nothing.

## Releasing

**Apps:** write the release notes in `release-notes/<version>.md` (the app
shows them before and after updating), then push a version tag, for example:

    git tag v0.4.0 && git push origin v0.4.0

GitHub Actions runs the tests, builds every platform (Android, Windows,
Linux, macOS, unsigned iOS and the web site) and publishes them as a GitHub
Release, which the in-app updater picks up. Android signing needs
these repository secrets:

- `SIDDUR_KEYSTORE_BASE64`
- `SIDDUR_KEYSTORE_PASSWORD`
- `SIDDUR_KEY_ALIAS`
- `SIDDUR_KEY_PASSWORD`

They must hold the same key as local builds (`android/key.properties`, not
committed). Otherwise Android won't install one build over the other.

**Web:** see [DEPLOY.md](DEPLOY.md).

## Licenses

Amud is free software under the GNU General Public License, version 3
(GPL-3.0); see [LICENSE](LICENSE).

Texts are from [Sefaria](https://www.sefaria.org). Each version keeps its own
license, which is listed in `assets/sefaria/manifest.json` and shown in the
app (Settings → Licenses & sources). Hebcal is GPL-2.0-or-later. Font licenses are
in `assets/fonts/`.
