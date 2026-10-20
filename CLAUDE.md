# Amud (flutter_siddur)

A Flutter siddur. The app is `lib/`; the prayer text is `corpus/siddur`, built
into `assets/corpus`; the engine that resolves a day's service is
`packages/siddur_engine`.

## Before you say "done"

Run what applies to your change:

    flutter test                                         # the app, including the translation check
    (cd packages/siddur_engine && flutter test)          # after any corpus change
    python3 tool/corpus/validate.py                      # must report 0 problems
    python3 tool/corpus/audit_translations.py "REGEX"    # each section you touched: must print "no gaps"
    python3 tool/corpus/audit_tags.py                    # must list only the tallis/tefillin meditations

**In the Claude desktop app's sandbox** `flutter` isn't on the PATH and the
user's `~/flutter` can't be seen. A Flutter 3.41.2 is installed there for
every session:

    . ~/.var/app/com.anthropic.Claude/data/flutter-env.sh

Never run `flutter` in this checkout from the sandbox: `pub get` rewrites
`.dart_tool/package_config.json` with sandbox paths and breaks the user's own
builds. Copy the project into your session's scratchpad (`$SCRATCH` below)
and run it there, copying `lib/` and `test/` over again after each edit:

    mkdir -p "$SCRATCH/proj"
    tar -c --exclude=./build --exclude=./.dart_tool --exclude=./.git --exclude=./worker -f - . | tar -x -C "$SCRATCH/proj"

If you can't run the tests, say so and list them for the user. Don't say they
pass.

Then say in your reply which translations you added or confirmed, which
gaps you found and left, and what you checked.

## Translations: nothing is done until it's translated

A missing translation fails silently: English shows instead, or a line has
no English at all. Check every time, for new code and for old code in a
place you touch.

- **Interface strings** need Hebrew and Yiddish in `_strings` in
  `lib/core/l10n.dart`. `test/l10n_test.dart` only sees literals written
  straight into `tr('…')`. Check these by hand, because it misses them:
  - ternaries: `context.tr(open ? 'Open now' : 'Closed')`
  - strings a widget translates inside: `CardFrame(title:)`,
    `CardType(title:, description:, shownWhen:)`, setup's `_Page`, `_Label`,
    `_Switch` and `_Choice` options, `Feature` titles and bodies
  - notification text made with `AppText(...).tr`

  Never weaken the test or add to its exemptions without a reason.
- **Ashkenazi spelling.** English is written in the Israeli spelling
  (`Shabbat`, `Sefirat`) and the reader's Ashkenazi setting rewrites it with
  `_ashkenazi` in `l10n.dart`. Every transliterated word you write must be in
  that map (`Naharot` → `Naharos`), with a case in `test/l10n_test.dart`.
- **Prayer text.** Every Hebrew prayer segment needs an English segment whose
  `translates` lists its ref, in the leaf's `en`. `translates: []` or the
  wrong refs count as missing. Re-check after adding, moving or splitting a
  line.
- **Instructions, notes, headings and speakers** need `en` (English-only ones
  need `he`). A `fold` needs `foldHe`; a `select` line needs `en`.
- **Your own translations** are normal English segments with
  `comment: "Amud translation"`, and "Amud translation" must be in the book's
  `sources.en`. Never put your wording under another version's name.
- As of October 2026 thousands of corpus lines still have no English
  (Ashkenaz about 1600, Chabad 700, Edot HaMizrach 2100, Koren 300, Sefard
  3400). Birkat HaMazon is clean; keep it that way, and fix gaps in any
  section you work in.

## Siddur text

- Edit `corpus/siddur`, never `assets/corpus`. Then `tool/corpus/fmt.py` →
  `validate.py` → `build_assets.py` → the engine tests. The format is in
  `corpus/SCHEMA.md`.
- Use `tool/corpus/edit.py` (`edit.py help` lists the commands). It addresses
  text by ref and word number, so you never retype Hebrew to find a spot.
  Start with `lint in=PREFIX`. It's a dry run until `--apply`.
- Never tag a vowelled prayer `instruction`, `note` or `heading`. The app
  shows those in English only, so the Hebrew prayer disappears.
- Text not said today is hidden, not dimmed. No labels for what's true on an
  ordinary day.
- **Weekday services:** read the whole service, not just your edit. Resolve it
  for an ordinary Tuesday and for each occasion you touched, and check that
  nothing conditional shows every day (all six days' Daily Psalm, Avinu
  Malkeinu, Aneinu), that nothing said is missing, and that Kaddish, Kedushah
  and Birkat Kohanim group and label correctly (graph node `kaddish.*`,
  `amidah: repetition`). Say which sections and siddurim you read.

## App code

- **A new setting** goes into `AppSettings` (`lib/core/settings.dart`) in five
  places: the field, the constructor default, `copyWith`, `toJson` and
  `fromJson`. Add its name to `localSettingsFields` or `syncedSettingsFields`
  in `lib/core/sync/sync_registry.dart` (`test/sync_test.dart` fails
  otherwise). If it changes notifications, add it to the `ref.listen` in
  `alertSchedulerProvider` (`lib/features/alerts/alerts.dart`).
- **Reminders** are planned by pure functions (`planSeasonalReminders` in
  `lib/features/integrations/seasonal_windows.dart`, `planNotifications` in
  `alerts.dart`), tested in `test/integrations_test.dart`. A switch that turns
  one on asks for notification permission first.
- **Home cards** register in `lib/features/home/cards/builtin_cards.dart` or
  `registerSeasonalCards`. Changing the default arrangement needs a dashboard
  migration in `lib/features/home/card_registry.dart`.
- **Which day it is:** `todayProvider` is the civil date, turning over at
  dawn; `halachicTodayProvider` turns over at sunset; `TodaySnapshot.afterSunset`
  is the time between.
- **Sample text** (font and text-size previews) never writes a Name of God.
  Use `previewText` in `lib/core/fonts.dart`.
- Don't run `dart format` on whole files; it rewrites unrelated lines.

## Narrow phones

Samsung phones are 360dp wide (320dp with Screen zoom or on a Fold's cover
screen), often with larger text. Check any layout you change at 360 and 320dp
with text at 1.3×. A word must never break mid-word, and a name must never be
cut to "Shach…".

- Don't fix a column count for phones. Count what fits at this width and text
  size: `textWidth` and `widestWord` in `lib/core/adaptive.dart` measure with
  the reader's text scale.
- A title with something at the other edge is a `SplitRow`, not a `Row` with
  `Expanded`. Nothing wide goes in a `ListTile.trailing`.
- An app bar with three or more icons uses `fitBarActions`, which moves the
  extras into a ⋮ menu when they would cut the title short.
- A short label that must stay on one line (a time, a tile's name) goes in a
  `FittedBox(fit: BoxFit.scaleDown)`. Times come from `formatTime`, which
  keeps "AM" with its time; a Hebrew date after English text goes through
  `keepTogether`.
- To look at it: `flutter build web -o DIR` in the scratch copy, serve DIR with
  `python3 -m http.server` from `.claude/launch.json`, open it in the browser
  pane at 360 or 320 wide, and run
  `document.documentElement.style.fontSize = '20.8px'` for 1.3× text.
  Reload the page after a rebuild; changing only the `#/` route keeps the old
  build.
- `test/narrow_layout_test.dart` sets the screen width and text size with
  `tester.view` and `textScaleFactorTestValue`; add cases there.

## Git

Don't commit unless asked. `web-dist/` stays out of git.
