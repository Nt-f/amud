# Brief: review and format one stretch of a siddur

You are formatting part of Amud's siddur text: one nusach, one stretch of
the davening. "Formatting" means everything the reader needs to show the
text correctly on any given day. You get the tags, splits, conditions,
roles, gestures, graph nodes and translations right. You do **not** change
the words of the prayers themselves (see "What you must not do").

The orchestrator who sent you will review your diff, run the full test
suite, and fold the rules you report into this brief for the next agent.
Be careful, be thorough, and say plainly what you didn't finish.

Your assignment (nusach, files, sections) is given at the end of the
message that launched you.

## Read first, in this order

1. `CLAUDE.md` (repo root): the project rules. The sections "Translations"
   and "Siddur text" apply to you in full.
2. `corpus/SCHEMA.md`: the format. Every field, every `kind`, every
   `role`, the gestures list, conditions, graph nodes. This is the
   authority; when this brief and SCHEMA disagree, SCHEMA wins, and you
   report the disagreement.
3. `python3 tool/corpus/edit.py help`: the edit language you will use.
4. `corpus/variables.json` (`edit.py vars`), `corpus/nodes.json`
   (`edit.py nodes`), `corpus/labels.json` (`edit.py labels`): the only
   condition variables, node keys and `if_…` labels that exist.

## The tools and how to call them

Run everything from the repo root, `/home/n/Downloads/flutter_siddur`.

    python3 tool/corpus/edit.py -n ashkenaz "@ Weekday/Minchah/Amida/Divine Might" "show"
    python3 tool/corpus/edit.py -n ashkenaz "lint in=Weekday/Minchah"
    python3 tool/corpus/edit.py -n ashkenaz "@ LEAF" "show he:3 full pointed"
    python3 tool/corpus/edit.py -n ashkenaz --apply "@ LEAF" "set he:2 when=roshChodesh" "tr en:2 he:2"

- Each argument is one command line. `@ LEAF` sets the leaf (full path,
  or a unique suffix). A run is atomic: if one command fails, nothing is
  written.
- **Without `--apply` it's a dry run** that prints the diff. Use dry runs
  to check a fix, then repeat with `--apply`.
- `show` gives each segment's ref, kind, tags and numbered words (niqqud
  stripped). `show ADDR full pointed` shows the real text. Address by ref
  and word number. **Never re-type Hebrew to find a spot.** Only type
  Hebrew when you write a new `he=` rendering or a new Hebrew instruction.
- Edit only through `edit.py`. Don't hand-edit the JSON. If `edit.py`
  can't express something, note it in your report and leave it.
  `edit.py undo` reverts its last write.
- To see the whole leaf as the app gets it (all fields):
  `python3 tool/corpus/export_plain_text.py --nusach ashkenaz --out-dir corpus/work/plain`
  (`corpus/work/` is git-ignored),
  then read the chunk's `.txt`.

Checks (run after each leaf or small group of leaves, and all of them at the end):

    python3 tool/corpus/fmt.py
    python3 tool/corpus/validate.py                         # 0 problems
    python3 tool/corpus/build_assets.py                     # needed before audit_tags and inspect
    python3 tool/corpus/audit_translations.py "^Weekday/Shacharit"   # your sections: "no gaps"
    python3 tool/corpus/audit_tags.py                       # only the tallis/tefillin meditations

**Resolve the service as the app will show it.** This is the most
important check, because a tag that looks right in the file can still show
the wrong thing on the wrong day:

    cd packages/siddur_engine && dart run tool/inspect.dart "Siddur Ashkenaz" "Weekday/Shacharit" 5787 9 7

The arguments are book title, section path, and Hebrew year, month and
day; add `il` for Israel. Months: 1 Nisan … 6 Elul, 7 Tishrei … 12 Adar
(Adar I in a leap year), 13 Adar II. 5787 is a leap year. Lines not said
that day are printed `{notToday: …}` or collapsed as `[N lines not said: …]`.

**A bare line in `inspect` tells you nothing about its tag.** A line said
today prints the same whether it has the right `when` or none at all. To
catch an untagged conditional line, resolve a day when it should be
*absent* and check that it's gone (summer against winter, Rosh Chodesh
against an ordinary day), or read its `when` in `show`. Don't "fix" a line
just because it printed bare.

Use these dates (weekdays all checked):

| date | weekday | what it is |
| --- | --- | --- |
| 5787 10 19 | Tue | **ordinary weekday, winter**: mashiv haruach and tal umatar |
| 5787 4 8 | Tue | **ordinary weekday, summer**: morid hatal, no tal umatar, no Omer |
| 5787 9 7 | Tue | ordinary weekday: mashiv haruach, but tal umatar not yet outside Israel (it is with `il`) |
| 5787 10 18 | Mon | Monday/Thursday: Torah reading, long Tachanun |
| 5787 8 1 | Mon | Rosh Chodesh Cheshvan (day 2), also a Monday |
| 5787 9 30 | Thu | Rosh Chodesh Tevet + Chanukah |
| 5787 9 26 | Sun | Chanukah |
| 5787 10 10 | Sun | Asara B'Tevet (public fast) |
| 5787 13 13 | Mon | Ta'anit Esther |
| 5787 13 14 | Tue | Purim |
| 5787 1 20 | Tue | Chol HaMoed Pesach, Omer, summer (morid hatal) |
| 5787 2 5 | Wed | Yom Ha'atzmaut (Omer) |
| 5787 5 9 | Thu | Tisha B'Av |
| 5787 6 20 | Wed | Elul |
| 5788 7 3 | Mon | Tzom Gedaliah, Ten Days of Repentance |
| 5788 7 4 | Tue | Ten Days of Repentance |
| 5788 7 6 | Thu | Ten Days of Repentance |
| 5788 7 18 | Tue | Chol HaMoed Sukkot |

Resolve each service for **the two ordinary Tuesdays first** (winter and summer). Read the output
from top to bottom and ask, for every line, "is this really said on an
ordinary Tuesday?" Then resolve each occasion you touched. To keep the
output short, pass a smaller section path (`Weekday/Shacharit/Amidah`).

## Read the whole text

**Read every leaf and every segment, Hebrew and English, in full, in book
order.** Don't grep, sample or skim. Plain `show` truncates long segments
("… (52 more) …"), so use `show LEAF full pointed`, or read the chunk's
whole `.txt` from `export_plain_text.py`. Finish reading a leaf before you
edit it. `lint`, `find`, the audits and `inspect` are checks you run after
reading; they don't replace it. Your report lists every leaf you read in
full.

## What to check, leaf by leaf

Go through your sections in book order. For each leaf, read it in full,
run `lint`, and check the following.

**Kind.**
- Vowelled words that are said are `prayer`, even when they're short (a
  response, a verse, "אמן"). Never tag them `instruction`, `note`,
  `heading` or `commentary`, because the app shows those in English only
  and the Hebrew prayer disappears. (`audit_tags.py` catches the obvious
  cases.)
- Unvowelled rubrics ("בר"ח:", "אומרים", "החזן אומר") are `instruction`.
  A bare speaker label ("חזן:", "קהל:") is `speaker`, with the `role` it
  introduces. Halachic rulings are `note`, with `forgot=true` for an "if
  one forgot" ruling and `cite` for the source. Kavanot and explanations
  are `commentary`. Titles inside a leaf are `heading`.

**Splits.** When one segment mixes things that need different tags, split
it into parts (`split ADDR wN`, `tag ADDR wA..B k=v`):
- a rubric glued to the prayer it introduces (`<small>בר"ח:</small> יעלה…`)
- day-specific words inline in a prayer, like the Ten Days' "לְעֵֽלָּא
  לְעֵֽלָּא" in Kaddish, or "המלך הקדוש" against "האל הקדוש": the
  day-specific words get a `when`, and alternatives share an `alt`
- a congregational response printed inside the chazzan's text: it gets
  its own `role=congregation`
- a note at the end of a prayer line

After splitting, re-check the English alignment (`tr`).

**Conditions (`when`).**
- Anything not said every day needs a `when`, using the most specific
  variable there is (see SCHEMA "Conditions"). Use `tachanunShacharit`, not
  your own combination of days. The Daily Psalm, one per weekday, is
  `dow == N` with `plain=true`.
- An instruction that announces a conditional line gets the same `when`
  as that line.
- Alternatives where exactly one is said (summer/winter, the Ten Days)
  share an `alt` id and each have their own `when`, which together cover
  every day.
- The test is the resolved service. On the ordinary Tuesday there must be
  no Daily Psalm for other days, no Avinu Malkeinu, no Aneinu, no Al
  HaNissim, no Ya'aleh VeYavo, no Hallel, and no Ten Days insertions. On
  each occasion, everything said that day must be present.

**Who, how and what to do** (SCHEMA "role", "voice", "gestures", `minyan`, `amidah`).
- Kaddish: the chazzan's or mourner's lines, and the congregation's
  responses split out as `role=congregation`. Its graph node must be a
  `kaddish.*` node (`kaddish.half`, `kaddish.shalem`, `kaddish.mourners`,
  `kaddish.derabbanan`, `kaddish.burial`, `kaddish.siyum`).
- Barchu, Kedushah, Modim d'Rabbanan and Birkat Kohanim: `minyan=true`.
  Inside the Amidah they're `amidah=repetition`. Kedushah verses are
  `congregation_then_chazzan` where the nusach does that.
- The silent Amidah is `voice=silent`. Baruch Shem in the Shema is
  `undertone`.
- Gestures go on the part where the action happens (bow at Baruch and at
  Modim, `three_steps_back` at Oseh Shalom, `cover_eyes` at Shema,
  `kiss_tzitzit`, `head_down` for Tachanun, `ark_open` and `ark_close`).
  Tag only what the siddur prints or the nusach's clear, widespread custom.

**Graph nodes.** Each unit gets its own node (`edit.py nodes`). A leaf that
holds several units (Ashrei → Uva LeTziyon → Kaddish → Aleinu) overrides
`node` on the parts that belong to another unit. Notes take the node of
what they're about.

**Lint items.** Fix everything `lint` lists for your sections: `tidy`,
`balance`, `verse` (only the verse numbers lint proposes, copied exactly,
several in one part in descending word order), and missing `en=`.

**Translations.**
- Every Hebrew prayer segment needs an English segment whose `translates`
  lists its ref (`tr en:N he:M`). `translates: []` or a wrong ref counts
  as missing. Where the Hebrew was split into several segments and one
  English segment covers them, list them all (`tr en:4 he:4,5`).
- Every instruction, note, heading and speaker needs `en=`. Keep it short,
  say only what the Hebrew says, and use the Israeli transliteration
  (`Shabbat`, `Rosh Chodesh`, `Kedushah`).
- Where a prayer has no English, write it yourself as a new English
  segment with `comment="Amud translation"`: `new en:REF after en:N
  comment="Amud translation" text="…"`, then `tr en:REF he:M` in the same
  run. (`new` silently ignores a `translates=` argument, so you must use `tr`.) Check that "Amud
  translation" is in `corpus/siddur/<nusach>/book.json` `sources.en`, and
  report it if it isn't. Translate faithfully, in plain dignified English
  matching the register of the neighbouring translation. Never put your
  wording under another version's name.
- **Every transliterated word you write** (an `en=` or English text) must
  have an Ashkenazi form in `_ashkenazi` in `lib/core/l10n.dart`
  (`Shabbat` → `Shabbos`). Don't edit Dart. List any word that's missing
  from that map in your report, and the orchestrator will add it with its
  test.

**Display rules from the owner.**
- Text not said today is hidden, not dimmed. Don't add labels for what's
  true on an ordinary day.
- Don't set `align` unless the printed siddur clearly differs from what
  the reader would choose.
- A `fold` (collapsible run) needs `foldHe`. A `select` line needs `en`.
  `edit.py` can't set `fold`, `foldHe` or `select` (its field list ends
  at `comment`), so report any that are missing or wrong.

## What you must not do

- Don't change the words, vowels or punctuation of a prayer or of its
  existing translation. If you see a typo, a missing word, a duplicated
  passage, footnote numbers glued into words (`forever,7God’s`), or
  commentary mixed into a translation, **report it** with the leaf and ref,
  and leave it as it is.
- Don't edit `assets/corpus` by hand. `build_assets.py` writes it.
- Don't edit app code, tests, `variables.json`, `nodes.json`,
  `labels.json`, `graph.json` or `units.json`. If you need a new
  variable, node or label, report it, with what it should mean.
- Don't run `flutter` (Dart's `dart run tool/inspect.dart` is fine), don't
  run `dart format`, and don't commit.
- Don't work outside your assigned sections. If a problem clearly
  continues into another section, report it.
- Don't guess at minhag. If you're unsure whether something is said, or by
  whom, leave the tag off and put the question in your report.

## Cross-nusach texts

Some texts are, or should be, essentially the same in every nusach: Birkat
HaMazon, Kiddush Levana, Asher Yatzar, Birkot HaShachar, Kaddish, Aleinu,
Ashrei, Tefillat HaDerech, Krias Shema al HaMitah, Sefirat HaOmer,
Hallel. As you go, list each such text you meet: its path in your
nusach, and the matching paths in the other four (search with
`python3 tool/corpus/edit.py -n sefard "outline Kiddush"`, and likewise
for `chabad`, `koren` and `edot_hamizrach`). Note how its formatting
differs between them (one is well tagged and another isn't, one is split
and another isn't). **Only list them. Don't edit other nusachim.** The
owner may later share formatting or text between them.

## Your report (your final message)

Write it to the file named in your assignment (under `corpus/work/`) **and**
return the same text as your final message. Plain text, in this order:

1. **Done:** the sections you finished, with a few lines for each on what
   you changed (counts are fine: "12 instructions given en, Kaddish
   responses split in 4 leaves").
2. **Not finished / left alone:** each item with leaf and ref, and why.
3. **Text problems seen** (typos, glued footnotes, mixed commentary) for
   the owner, with leaf and ref.
4. **Questions** on minhag or intent that need the owner.
5. **Missing pieces:** variables, nodes or labels you needed, and
   transliterations missing from `_ashkenazi`.
6. **Cross-nusach list** (above).
7. **New rules learned:** each rule you worked out that isn't already in
   this brief or SCHEMA.md, written as an instruction for the next agent
   ("When X, do Y, because Z"), with one example (leaf and ref). Include
   tool quirks (an `edit.py` command that behaves unexpectedly, or a
   check that misleads you). These are the most valuable part of your
   report, so be concrete.
8. **Checks:** the final output summary of validate, audit_translations
   (per section), audit_tags, and which dates you resolved for which
   services.

## Rules learned by earlier agents

These were found in review and checked by the orchestrator. Batch 1 was
Ashkenaz Weekday, files 01–05, in November 2026.

**The engine and the checks**

1. **Section rules by title.** `defaultSectionRules` in
   `packages/siddur_engine/lib/src/rules.dart` gives sections a condition
   by their English title (Avinu Malkeinu, Hallel, Sefirat HaOmer,
   Kiddush Levana, LeDavid…), and for most of them **the title rule wins
   over the leaf's `when`**. Only the Tachanun and Monday/Thursday rules
   are `corpusDecides`: in these siddurim, every leaf under them must
   carry its own `when` (Ashkenaz "God of Israel" is
   `tachanunShacharit && monThu`). If a leaf's `when` disagrees with its
   title rule, resolve it to see which one shows, and report it. Don't
   assume your `when` takes effect. Several leaf conditions were never
   live and are weaker than the rule (Ashkenaz Shabbat Birkat Hachodesh
   is only `torahReading`).
2. **Maariv dates.** `inspect` on a Maariv resolves the evening that
   *starts* the next day, so for the Maariv of day D pass D−1. (`5787 1 20`
   gives the Maariv of 21 Nisan, which is Yom Tov.) `inspect` is diaspora
   unless you add `il`. In an Ashkenaz diaspora summer neither morid hatal
   nor mashiv haruach shows, which is correct.
3. **Rebuild first.** `inspect` and `audit_tags` read `assets/corpus`, so
   run `build_assets.py` after editing or they show the old text.
   `inspect` also cuts lines at 70 characters, so a hidden part inside a
   long line can look shown. Read its `when` with `show`.
4. **Commentary needs English too.** `audit_translations` counts a
   `commentary` segment as said, so it needs a real English segment
   (`new en:REF …` then `tr`), not just `en=`. An `en=` attribute is
   enough for instructions, notes, headings and speakers.

**Tagging**

5. **A Ten Days word that replaces another.** In Oseh Shalom, "(השלום)"
   replaces "שלום". Tag the replaced word
   `when=!aseretYemeiTeshuva alt=X` and the replacement
   `when=aseretYemeiTeshuva alt=X`, and leave the words always said
   ("עשה", "במרומיו…") with no `when`. Then resolve a Ten Days date and
   look for doubled or missing words. (All three weekday Amidot had one or
   the other.)
6. **English follows the Hebrew's alternatives.** When the Hebrew has
   `alt` parts, split the English the same way and give each English part
   the same `when` and `alt`, so the reader doesn't show both endings.
   Examples: `Amidah/Justice en:1`, `Amidah/Kedushah en:14`.
7. **Don't combine a variable that already knows the service.**
   `birkatKohanimChazzan` is already limited to the right services (Mincha
   only on a fast or Tisha B'Av). `publicFast && birkatKohanimChazzan` hid
   it on Tisha B'Av. Note that `publicFast` excludes Tisha B'Av and
   `fastDay` includes it.
8. **A conditional psalm with its own Kaddish** takes the `when` on the
   leaf, so the Kaddish is hidden with it. Example: `Concluding
   Prayers/LeDavid`, which is `when=ledavid`.
9. **A rubric that only states the ordinary day** ("on weekdays the
   chazzan says Kaddish Shalem") gets `when=false`, by the owner's rule of
   no ordinary-day labels (the owner confirmed this). Its counterpart for
   the special day keeps its own `when`.
10. **Gestures.** Use `bow_full` on "מודים אנחנו" in Modim and on "ואנחנו
    כורעים ומשתחוים ומודים" in Aleinu, split so it sits on just those
    words. Plain `bow` isn't used. Oseh Shalom gets `three_steps_back` on
    "עשה" (and on the instruction that describes it) and
    `bow_left_right_center` on "עשה" and on the last part.
    `feet_together` goes on "אדני שפתי תפתח" only, never on a note.
11. **Make the copies agree, in the right direction.** The same text in
    Shacharit, Minchah and Maariv is often tagged differently. After
    fixing one, fix the others. Where they disagree, choose by the rules,
    not by majority. Never remove a correct `when` to match a copy that
    lacks one. (The HaEl HaKadosh "if one erred" note had
    `when=aseretYemeiTeshuva` only in Minchah, and an agent removed it to
    match the others. The fix was to add it to the others.)
12. **When you split the work** among helpers, give each one this whole
    brief, and read each helper's diff yourself before reporting.

**`edit.py` quirks**

13. `tag ADDR wA..B` splits the part and renumbers the parts after it.
    Run `show` again before the next edit. When you tag two places in one
    segment, do the later one first.
14. `set ADDR k=` (empty) removes a field. `lset when="a && b"` needs the
    quotes. A short leaf suffix like `@ Concluding Prayers/Alenu` can match
    several services, so use the full path. `lint in=…/Post` also matches
    "Post Amidah".
16. **Ten Days wording is always highlighted.** Everything said only in
    the Ten Days (Zochreinu, Mi Chamocha, HaMelech HaKadosh, HaMelech
    HaMishpat, Uchtov, BeSefer Chayim, Oseh HaShalom, Kaddish's
    "le'eila le'eila") must be tagged `when=aseretYemeiTeshuva`. Its
    everyday counterpart is tagged `when=!aseretYemeiTeshuva` with the same
    `alt`. The reader then highlights the Ten Days wording on every one of
    the ten days. (Only the seasonal switches, like Mashiv HaRuach, stop
    being highlighted after 30 days.) Check it in `inspect` on a Ten Days
    date: each one must print `{today: …}` or `today:` in its run labels.
    The owner's own rule: an "if one forgot" note for the Ten Days is
    hidden outside them, but the wording itself must be highlighted.
17. **Kedushah is tagged by part** (confirmed by the owner). The lines the
    congregation says first and the chazzan repeats are
    `congregation_then_chazzan`: נקדש / נעריצך, קדוש קדוש קדוש, ברוך כבוד,
    and ימלוך. Ashkenaz prints "קהל וחזן" over them. The chazzan's
    connecting lines (לעמתם ברוך יאמרו, ובדברי קדשך כתוב לאמר, לדור ודור)
    are `chazzan`. `feet_together` goes on the first verse,
    `rise_on_toes` on Kadosh, Baruch and Yimloch.
18. **Touching the tefillin** is `touch_tefillin_yad` on the words for the
    shel yad (עַל יָדֶךָ) and `touch_tefillin_rosh` on those for the shel
    rosh (בֵּין עֵינֶיךָ). Split the part so the gesture covers just those
    words. The reader draws a small bayit with יד or ראש beneath it, always
    in Hebrew, before the first word, instead of a label above the line.
    Don't use plain `touch_tefillin` in new tagging.
19. In zsh an unquoted `$var` isn't split into words. Pass `inspect`'s
    date as three separate words, not one string.

**Batch 2: Ashkenaz Festivals, Selichot, Berachot and Kaddish, November 2026**

20. **No leaf `when` that only names the section's occasion.** Don't give
    the leaves of Rosh Chodesh, Hallel, Chanukah, the Shalosh Regalim or
    Sukkot a `when` like `roshChodesh`, `yomTov` or `chanukah` (SCHEMA,
    "Conditions"). The service graph's insert and the title rules already
    decide when these sections are said. A leaf `when` adds a "today"
    label to every heading. It also hides the text from someone reading
    ahead on erev Yom Tov, and gets it wrong outright: `yomTov` alone on
    Musaf would hide it on Chol HaMoed, and `chanukah` risks the first
    night, lit on the evening of 24 Kislev. An agent added 38 of these;
    all were reverted. Use a leaf `when` only to pick between leaves in
    the same section (one Hosha'ana per day).
21. **Kaddish "Oseh shalom" follows rule 5.** "עושה" is always said; only
    "שלום" is `when=!aseretYemeiTeshuva alt=oseh` against "(השלום)". Eleven
    Kaddish copies had both words conditioned, which dropped "עושה" in the
    Ten Days. Check every Kaddish you touch on a Ten Days date.
22. **Starting English on a leaf with none.** `new en:` now creates the
    leaf's `en` block under "Amud translation". Check that "Amud
    translation" is in the book's `sources.en` first. For many lines, build
    the argument list in Python and call `edit.py --apply "@ LEAF" …` once
    per leaf: `new en:REF end comment="Amud translation" text="…"`, then
    `tr en:REF he:A,B`. `new en:R before en:N` keeps the order among
    existing segments.
23. **English parts with conditions:** `new en:R end when=… alt=… text=…`
    for the first part, then `ins en:R.1 after when=… text=…` for each
    next one. Where all the Hebrew parts share one `when`, the English
    needs none, because it is hidden through `translates`.
24. **Piyyutim are hard; say so.** Liturgy you know well (the Thirteen
    Attributes, Vidui, Kel Melech, Tehillim) can be translated
    confidently. A piyyut's obscure lines need care, and a guess is worse
    than a plain rendering: "מאת אהוביך שוטן השבת" is "from those You love
    You silenced the accuser", not "the adversary of the Shabbat". List
    every line you weren't sure of in your report, with leaf and ref, so
    the owner can check them.
25. **`inspect` on a leaf with no `service`** (the first group of the
    Shalosh Regalim Amidah) resolves as Mincha. For leaves split by
    service, read the `when`s with `show` instead.
26. **Transliterations:** names that are simply English (Mordechai,
    Zerubbabel, Bethel) need no `_ashkenazi` entry. Only words whose
    Ashkenazi form differs do (ת without dagesh: Gittit → Gittis,
    Matityahu → Mattisyahu). List those.

**Sefard batch 1: weekday services, November 2026**

27. **Sefaria's broken Kaddish markup.** Many Kaddish copies carry the Ten
    Days wording in one recurring broken shape: an empty `<small>` part,
    with the ordinary words after it swallowed into the Ten Days part. So
    ordinary days lose the end of a line and the Ten Days lose its start.
    Find them by resolving an ordinary Tuesday against a Ten Days date,
    and with `grep '"text": "<small>"'`. Fix them per rules 5 and 21:
    "מן כל" (`when=!aseretYemeiTeshuva alt=leela`) against "(ולעלא מכל)"
    (`when=aseretYemeiTeshuva alt=leela`), and "שלום" against "(השלום)"
    (`alt=oseh`). The words said every day get no `when`, and the
    congregation's responses are split out. Koren and Edot HaMizrach have
    the same shape.
28. **A leaf holding several units must not carry the first unit's
    `when`.** Sefard's "Weekday Mincha/Tachanun" leaf was
    `when=tachanunMincha`, which hid the Kaddish and Aleinu after it on
    every day without Tachanun. Put the condition on the parts of the unit
    it belongs to. Check every long leaf this way, in every nusach.
29. **Every element of a dated sequence needs its own `when`.** Only 5 of
    Sefard's 49 Omer count lines had `omerDay == N`, so 44 showed every
    night. The Daily Psalm, the Omer and the Hosha'anot are the usual
    cases.
30. **An occasion leaf that repeats a service's tail** (a Motzaei Shabbat
    leaf with its own end of Maariv) shows on top of the service's own
    tail. Resolve that occasion and look for doubled text.
31. **The right variables:**
    - The blessing of the years is `talUmatar`, not `mashivHaruach`.
      Outside Israel, טל ומטר starts in December.
    - Ya'aleh VeYavo's festival words use `cholHamoedPesach` and
      `cholHamoedSukkot`.
    - Aneinu in the chazzan's repetition and at Mincha is `fastDay`, which
      includes Tisha B'Av.
32. **The vanishing-prayer check misses short or lightly vowelled
    lines.** `audit_tags` only flags long vowelled parts. Read every
    `instruction` and `speaker` part's text yourself, since a short
    vowelled response tagged so disappears from the Hebrew. About 80 of
    Sefard's Perek Shirah verses had vanished this way.
33. **`edit.py` traps:**
    - `set ADDR when=…` on a whole segment overwrites every part's own
      `when`. Address the part (`he:5.2`).
    - `split` copies all of a part's fields to both halves, so set the
      new `when`, `alt`, `en` and `cite` right after.
    - Clear stray `cite`, `en` or `he` fields before splitting, or both
      halves keep them.
34. **`audit_translations` can say "no gaps" while `translates` is shifted
    by one.** Spot-check that each English segment really renders its
    Hebrew; Sefard's Shacharit Amidah was off by one from he:81 to he:97.
35. **Helpers' scratch files need unique names.** Helpers share one
    scratchpad, and same-named scripts overwrite each other.

36. **Minhag facts are researched, not guessed.** `corpus/work/minhag_research.md`
    has sourced answers: the Hosha'anot order, doubling in Hallel, when
    אדיר במרום is said, leaving the sukkah, Yom Kippur Katan, מגדול, Avinu
    Malkeinu on Tzom Gedaliah, and Nusach Sefard's Sim Shalom, Morid HaTal and
    Kaddish. Use them. For a minhag question not answered there, don't guess:
    put it in your report, and the orchestrator will research it.

**Sefard batch 2: Sefard special days and Berachot, November 2026**

37. **God's Name in English follows the book's own translation.** Ashkenaz
    and Sefard write the Tetragrammaton as "Adonoy" (over 1,000 times
    each), so Amud translations there do too: not "Hashem", not "the
    Lord". 637 parts were normalized. Before translating for another book,
    count what its existing English uses and follow it.
38. **Al HaNissim units end where Al HaNissim ends.** "ועל כלם יתברך",
    "וכל החיים יודוך" and Modim's closing blessing are said every day. Don't
    give them Al HaNissim's `chanukah || purim` or its node. Four copies
    had it: Sefard Rosh Chodesh Musaf, Sefard Erev Shabbat Mincha, Koren
    Shabbat Maariv, and Ashkenaz Shabbat Minchah. In the last, the end of
    Modim sat inside the Purim leaf and was hidden every other day; it
    was moved to a leaf of its own. Resolve an ordinary day and read
    Modim to its last word.
39. **In a Torah table, שני / שלישי / רביעי are aliyot, not weekdays.**
    Remove any `dow ==` a model put on them; every aliyah is read on every
    day the table serves. A parenthesised word in a verse is the ketiv:
    make the mark a `note`, and the vowelled verse around it `prayer`.
40. **A leaf printed for several services** (a Yom Tov Amidah for Maariv,
    Shacharit and Mincha) gets `lset service=any`. Then its parts tagged
    `mincha`, `!shacharit`, `maariv && motzaeiShabbat` and so on show
    labelled ("For Mincha") instead of being judged in one fixed service,
    which hid every other service's lines. Don't set `service=shacharit`
    on such a leaf.
41. **Reuse identical translations.** Before translating liturgy found in
    other books (Selichot, the Thirteen Attributes, Tehillim), build a
    map from niqqud-stripped Hebrew (about 20 characters minimum) to
    existing Amud English, and reuse it where the Hebrew is identical,
    with the destination book's Name convention (rule 37). Never reuse
    another version's English as Amud's.
42. **Scan for vanished prayers mechanically.** Any non-prayer part with
    two or more niqqud marks is suspect (rule 32). This batch found
    Vaya'avor tagged as an instruction 39 times, plus the Ta'anit Esther
    Vidui and רבותי נברך.
43. **Bentching:** resolve an ordinary Tuesday, Shabbat, Rosh Chodesh,
    Chanukah, Purim and Chol HaMoed every time. Al HaNissim, Retzei and
    Ya'aleh VeYavo had shown every day. Forget-blessings that can fall on
    the same day (Shabbat and Yom Tov) must exclude each other.
44. **`edit.py`, more traps:**
    - `show he:A he:B` shows only the last address.
    - `merge` refuses parts with different tags; make them alike first.
    - `set he:N role=` on a segment with parts clears every part's role.
    - `lint in=` with a space in the path is ignored.
    - `ins en:R.1 after …` adds conditional English parts in order.
45. **Parallel helpers** must not run `fmt.py` or `undo`, since both act
    on files other helpers are editing. Each helper re-checks that its
    edits persisted. A helper killed by a content filter before editing
    is re-run on a smaller set of leaves.

46. **An inserted occasion that repeats the service's end** (Sefard
    Rosh Chodesh Musaf printed with Kaveh … Aleinu) is fixed by splitting
    the repeated end into its own leaf after it ("Rosh Chodesh/After
    Mussaf"). The service graph inserts only the first leaf, and browsing
    the section still shows both. Don't hide the end with `when=false`,
    which would cut it from the section too.
47. **BaHaB's three days** are `behabDay == 1` (first Monday), `2`
    (Thursday) and `3` (second Monday). Each siddur's full Selichot for a
    day is a graph insert of its own (`selichot.behab_first`, `_thursday`
    and `_second` in `units.json`), and the BaHaB title rule is
    `corpusDecides`.

**Koren batch 1: weekday services, November 2026**

48. **Read every blessing to its closing (chatimah).** Sefaria-era
    `when`s sometimes hide a blessing's ending. In Koren, "אור חדש … יוצר
    המאורות" and "והביאנו … הבוחר" were `roshChodesh||yomTov||chanukah`, so
    Yotzer and Ahavah Rabbah lost their endings on every ordinary day.
    Resolve an ordinary day and check that every blessing ends.
49. **Ten Days insertions have two halves:** Zochreinu … וכתבנו, Mi
    Chamocha … זוכר יצוריו, BeSefer Chayim … נזכר ונכתב. Earlier taggers
    often conditioned only the first, so the second showed every day.
50. **A rubric about where to start isn't a skip.** "On Sunday, Tuesday …
    begin here" doesn't mean the text above it is skipped on other days:
    Koren's Nefilat Apayim was `!monThu` because of one. Read the rubric's
    words.
51. **Find stray `translates` mechanically.** List every English segment
    whose `translates` differs from its own ref, and check those. Koren
    had over 60 pointing at the wrong line, which `audit_translations`
    can't see. To split one English segment shared by two Hebrew lines:
    `dup en:N as M`, then `del en:M.k` from the end.
52. **`forgot=true` belongs only on "if one forgot" notes.** Koren had it
    on whole prayers (the Mourner's Kaddish, Oseh Shalom, Aneinu,
    Tachanun). Scan for `forgot` on `kind=prayer` and clear it.
53. **English-only rubrics** (`translates: []`) attach to the line
    before. Point them with `tr` at the Hebrew they introduce, so they
    hide along with it (Avinu Malkeinu's "On Fast Days:").
54. **English words inside a Hebrew segment** ("Quietly:", "then") are
    split off as their own instruction.
55. **Use `moridHatal`,** which already knows Israel and Sefardi custom.
    Don't use `!mashivHaruach && il` (Sefard's `!mashivHaruach` is right,
    because Nusach Sefard says Morid HaTal everywhere).
