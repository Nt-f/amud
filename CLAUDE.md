# Amud (flutter_siddur)

## TRANSLATIONS: NOTHING IS DONE UNTIL IT IS TRANSLATED

**Every piece of text the app can show needs every translation, always. This
covers new work and old work.** Missing translations fail silently (English
shows instead, or the line has no English at all), so they are only found by
checking. Do not assume something is translated; check it, and say what you
checked.

1. **Prayer text in the corpus needs an English translation.** Every Hebrew
   prayer segment must be translated by an English segment whose `translates`
   lists its ref, in the leaf's `en` block. A new or edited line, a line you
   moved, a split segment: re-check its alignment. English text that exists but
   has `translates: []` or the wrong refs counts as missing.
2. **Instructions, notes, headings and speakers need `en`** (and English-only
   ones need `he`). A `fold` needs `foldHe`; a `select` line needs `en`.
3. **Interface strings need Hebrew and Yiddish.** Every string passed to
   `context.tr('…')` needs an entry in `_strings` in `lib/core/l10n.dart`.
   `test/l10n_test.dart` scans `lib/` and fails when one is missing; never
   weaken it or add to its exemptions without a reason.
4. **Ashkenazi spelling.** English the app shows is written in the Israeli
   spelling; the reader's Ashkenazi setting rewrites it with `_ashkenazi` in
   `lib/core/l10n.dart`. Every transliterated Hebrew word you write must be in
   that map (`Naharot` → `Naharos`); add the missing ones and a case in
   `test/l10n_test.dart`.
5. **Translations you write yourself** go in as normal English segments with
   `comment: "Amud translation"`, and "Amud translation" must be in the book's
   `sources.en`. Never put your wording under another version's name.

**Old things must be checked too.** When you touch a section, audit it, and fix
what you find, even if it was already broken:

    python3 tool/corpus/audit_translations.py "REGEX of the section"   # lists gaps; must print "no gaps"
    python3 tool/corpus/audit_translations.py                          # counts per siddur

`validate.py` and `flutter test` must pass. As of October 2026 the whole
corpus still has thousands of untranslated lines (whole sections with no English
version at all: 1600 Ashkenaz, 700 Chabad, 2100 Edot HaMizrach, 300 Koren,
3400 Sefard). Birkat HaMazon is clean; keep it that way, and chip away at the
rest whenever you are in a section. When finishing any task, report which
translations you added or confirmed and which gaps you found and left.

## Tagging and weekday services

- **A vowelled prayer must never be tagged `instruction`, `note` or `heading`:** the app shows those in
  English only, so the Hebrew prayer disappears. Run `python3 tool/corpus/audit_tags.py`; it must list only
  the optional tallis/tefillin meditations.
- **Read the whole weekday service before calling it done**, not just what you edited: resolve it for an
  ordinary Tuesday and for the occasions you touched, and check that nothing conditional shows every day
  (all six days' Daily Psalm, Avinu Malkeinu, Aneinu), that nothing said is missing, and that Kaddish,
  Kedushah and Birkat Kohanim group and label correctly (graph node `kaddish.*`, `amidah: repetition`).
- **Say what you checked.** List the sections and siddurim you reviewed and what you found.

## Text and wording

- **Siddur text is edited in `corpus/siddur`**, then `tool/corpus/fmt.py` → `validate.py` → `build_assets.py`
  and the engine tests; see `corpus/SCHEMA.md`. Never edit `assets/corpus` by hand.
- Don't re-type Hebrew prayer text to locate an edit: address segments by ref/word number.
- Don't run `dart format` on whole files; it rewrites unrelated lines.
- Text not said today is hidden, not dimmed. No labels for what's true on an ordinary day.
- Don't commit unless asked. `web-dist/` stays out of git.
