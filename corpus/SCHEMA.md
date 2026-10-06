# Amud's siddur text

Amud's five main siddurim (Ashkenaz, Sefard, Edot HaMizrach, Chabad and
Koren) are its own text. They began as Sefaria versions, were tagged by
hand and by model, and are now edited here directly: the words, the
formatting, the tags and the notes. Each segment says what it is (prayer,
instruction, note…), when it is said, who says it and how, and which unit
of the davening (graph node) it belongs to.

The app takes these books' table of contents from here, and lists the
text as the version "Amud", first, in each language. The Sefaria versions
in `assets/sefaria` stay as alternatives a reader can put first (Text
versions), with the engine's own analysis instead of these tags.

    corpus/siddur/<nusach>/book.json      the book's title and its sections' Hebrew titles
    corpus/siddur/<nusach>/<NN_chunk>.json  the text, in book order (by file name)
    corpus/labels.json                    what each personal circumstance (if_…) means
    corpus/nodes.json                     graph-node keys
    corpus/variables.json                 condition variables
    corpus/graph.json, units.json         the order of each service (see Service graph)
    corpus/ISSUES.md                      problems the taggers reported, to work through
    assets/rules/notes.json               the app's short notes, for every siddur (concise notes)

After editing:

    python3 tool/corpus/fmt.py            # canonical layout (one line per segment)
    python3 tool/corpus/validate.py       # must report 0 problems
    python3 tool/corpus/build_assets.py   # → assets/corpus/<nusach>.json.gz
    (cd packages/siddur_engine && flutter test)

## Editing

- **Fix a word, a vowel or formatting:** edit the segment's `text`. It's
  Sefaria-style HTML: `<b>` for the opening words, `<small>` for rubrics,
  `<br>` for line breaks, `<i>`/`<sup>` for footnotes in translations.
  Close every tag you open; the validator warns otherwise.
- **Add a note or an instruction:** add a segment (or a part) where it
  belongs, with a new `ref` that isn't used in that leaf (`"4a"`, `"n1"`).
  Refs only need to be unique within a leaf and language; their order in
  the file is the order shown.
- **Change when something is said:** edit its `when` (see Conditions).
- **Add a section:** add a leaf in the right place in the right chunk file,
  with a `path` under an existing section (or a new one, with its Hebrew
  title in `book.json`), a `title`, a `node`, and its segments. The book's
  table of contents is built from the leaves in order.
- **Leave a note for other editors:** `comment`, on a leaf, segment or part.
  It never reaches the app.

## book.json

```json
{
  "title": "Siddur Ashkenaz",
  "heTitle": "סידור אשכנז",
  "sources": {
    "he": {"The Metsudah siddur, 1981": {"license": "CC-BY", "source": "https://…"}},
    "en": {"Sefaria Community Translation": {"license": "CC0"}}
  },
  "sections": {
    "Weekday": "ימי חול",
    "Weekday/Shacharit": "תפילת שחרית"
  }
}
```

- `title` is the book's name in the app and in settings; don't change it.
  `heTitle` is its Hebrew name.
- `sources` credits the Sefaria versions the text came from, per language:
  every leaf's `version` must be listed. The app shows them, with their
  licenses, on the "Amud" version, whose own license is the most
  restrictive of them. Text you write yourself can keep its leaf's
  `version`.
- `sections` gives the Hebrew title of each section (any path that has
  leaves under it); the validator warns about one without. A section's
  English title is the last part of its path.

## Chunk file

```json
{
  "book": "Siddur Ashkenaz",
  "chunk": "Weekday/Shacharit [Preparatory Prayers .. Blessings of the Shema]",
  "leaves": [
    {
      "path": "Weekday/Shacharit/Amidah/Patriarchs",
      "title": "אבות",
      "node": "amidah.avot",
      "service": "shacharit",
      "he": {
        "version": "The Metsudah siddur, 1981",
        "segs": [
          {"ref": "1", "kind": "note", "en": "…", "cite": "קיצור שו\"ע יח", "text": "…"},
          {"ref": "4", "parts": [
            {"kind": "instruction", "en": "During the Ten Days of Repentance:", "text": "<small>בעשי\"ת:</small>"},
            {"kind": "prayer", "when": "aseretYemeiTeshuva", "text": " זָכְרֵֽנוּ לְחַיִּים … אֱלֹהִים חַיִּים:"}
          ]}
        ]
      },
      "en": {
        "version": "Translation based on the Metsudah linear siddur, by Avrohom Davis, 1981",
        "segs": [
          {"ref": "1", "translates": ["1"], "text": "…"}
        ]
      }
    }
  ]
}
```

### Leaf fields

| field | meaning |
| --- | --- |
| `path` | The leaf's place in the book; its last part is its English title. Unique in the siddur. Rules (`assets/rules/rules.json`), `units.json` and the app's shortcuts refer to sections by path, so rename with care. |
| `title` | Hebrew title. Defaults to the English one. |
| `node` | Default graph node for its segments (see Graph nodes). Required. |
| `when` | A condition for the whole leaf, for a leaf said only on some days ("Musaf for Rosh Chodesh"). |
| `service` | `shacharit`, `mincha`, `maariv`, `musaf` or `none`: the service its conditions are judged in. |
| `he`, `en` | The Hebrew and the English: `version`, the Sefaria version it came from (credited in the app), and `segs`. Either may be left out. |
| `comment` | For editors. |

### Segments and parts

A segment is one line (paragraph) of the reader. It has a `ref` and either
the part fields directly, which describe the whole segment, or `parts`: a
list of pieces with different tags, shown run together on one line.
English segments also have `translates`: the refs of the Hebrew segments
they translate, in order (`[]` for none). English without a counterpart
is shown with the line before it.

Split a segment into parts when it mixes things that need different tags:

- an instruction and the prayer it introduces (`<small>בר"ח:</small> יעלה ויבוא…`)
- two lines for different days (`בקיץ: מוריד הטל / בחורף: משיב הרוח…`)
- a congregational response inside the chazzan's text
- a halachic note at the end of a prayer line

### Part fields

`text` is required, and `kind` on Hebrew; the rest is optional.

| field | values | meaning |
| --- | --- | --- |
| `kind` | `prayer` | Words that are said, including responses, verses and piyyutim. |
|  | `instruction` | A short rubric: when or what to say or do ("On Rosh Chodesh:", "Bow", "The chazzan says:"). |
|  | `speaker` | Only a speaker label ("חזן:", "קהל:", "Chazzan:", "Congregation:"). |
|  | `note` | Halachic explanation, law, or "if one forgot…" ruling. |
|  | `heading` | A title line inside a leaf. |
|  | `commentary` | Explanation, kavanah or essay that isn't said and isn't law. |
| `text` | HTML | What is shown. |
| `when` | condition | When this part applies (see Conditions). Omit when always, in context. |
| `alt` | short id | Alternatives where exactly one is said share an `alt` id (e.g. `"geshem"` for מוריד הטל / משיב הרוח), each with its own `when`. |
| `node` | node key | Overrides the leaf's `node`. |
| `role` | see below | Who says it. |
| `voice` | `silent` \| `undertone` \| `aloud` | How it's said, when it matters (the silent Amidah is `silent`; Baruch shem kevod in the Shema is `undertone`; the chazzan's Kaddish is `aloud`). |
| `align` | `start` \| `center` \| `end` \| `justify` | How the reader sets the line (the segment takes its first part's): flush to the start (right for Hebrew), centered, flush to the end, or justified. Leave it out to let the reader decide by what the line is (the Shema and Kedushah are centered already); set it only where the siddur prints it differently. Instructions centre over a centered prayer by themselves. |
| `fold` | text | English title. Consecutive segments whose first part has the same `fold` collapse into one tappable row with that title (the zimun, Al Naharot); tap to open. Set it on the first part of each segment in the run. `foldHe` is the Hebrew title. |
| `select` | choice id | Draws a selector above this line for a choice the reader makes (`table`: whose table one ate at; `occasion`: bris, wedding, pidyon haben). The picked option answers the `if_…` conditions that follow, so tag the lines it governs with them. Choices are defined in `lib/features/siddur/reader_choices.dart`; the line itself should be an always-shown instruction. |
| `amidah` | `silent` \| `repetition` | Inside an Amidah: said only in the silent prayer or only in the chazzan's repetition (Kedushah, Modim d'Rabbanan, Birkat Kohanim…). |
| `minyan` | `true` | Requires a minyan (Kaddish, Barchu, Kedushah, repetition, Torah reading, Birkat Kohanim…). |
| `gestures` | list, see below | What to do while saying it. |
| `repeat` | whole number > 1 | Said this many times (Kadosh x3, Baruch Hashem LeOlam x2…). |
| `forgot` | `true` | A note about what to do if one forgot or erred. |
| `en` | text | Hebrew instructions, notes, headings and speakers: the English the app shows (instructions are shown in English). Give it for every one of these. |
| `he` | text | English-only instructions: a concise Hebrew rendering. |
| `gloss` | text | One line in English on why or when, where the siddur doesn't say and it isn't obvious. Use sparingly. |
| `cite` | text | A source cited in a note (`קיצור שו"ע יח`, `משנה ברורה קיד`). |
| `clean` | HTML | An instruction or note tidied (whitespace, brackets). Not shown yet. |
| `comment` | text | For editors. |

### `role`: who says it, and how the kahal and chazzan share it

| value | meaning | examples |
| --- | --- | --- |
| `individual` | Each person, at their own pace (default). | Pesukei Dezimra, the silent Amidah |
| `chazzan` | The chazzan (or reader) alone; the kahal listens and answers Amen. | Kaddish, the repetition, Haftarah blessings |
| `congregation` | The kahal alone, out loud: a response. | אמן יהא שמיה רבא, ברוך ה' המבורך לעולם ועד |
| `congregation_then_chazzan` | The kahal says it first, then the chazzan repeats it aloud. | Kedushah verses (Kadosh, Baruch, Yimloch) in many nusachim; Avinu Malkeinu lines where the chazzan repeats; Hoshanot |
| `chazzan_then_congregation` | The chazzan leads each line and the kahal repeats it. | Shema Yisrael and Echad when taking out the Torah; Gadlu; the Thirteen Attributes in Selichot; Ki Hinei KaChomer |
| `together` | Chazzan and kahal say it aloud together. | Avinu Malkeinu, chaneinu va'aneinu; the last verse of Shirat HaYam; Shema Koleinu in Selichot |
| `responsive` | Alternating verses between chazzan and kahal. | Hallel (Hodu, Ana HaShem), Anim Zemirot |
| `kohanim` | The kohanim. | Birkat Kohanim when duchening |
| `mourner` | Those saying Kaddish; the kahal answers. | Mourner's Kaddish, Kaddish d'Rabbanan |
| `oleh` | The person called to the Torah; the kahal answers. | Birkot HaTorah for an aliyah, Birkat HaGomel |
| `head_of_household` | The person making Kiddush, Havdalah, leading a seder or Zimun. | Kiddush, Havdalah, the Zimun call |

Tag a role where the siddur says so or where the custom of the nusach is
clear and widespread; the siddur's own instructions take precedence. When
a part's role depends on whether there's a minyan, tag the minyan reading
and add `minyan: true`. In practice:

- Kaddish: the chazzan's lines are `chazzan` and `aloud` (Mourner's Kaddish
  and Kaddish d'Rabbanan: `mourner`); the responses (אמן, יהא שמיה רבא,
  בריך הוא) are `congregation`, split out when printed inline.
- Barchu: the call is `chazzan`; the response is `congregation_then_chazzan`.
- Avinu Malkeinu: `ark_open` on its first line, `ark_close` after it. In
  Ashkenaz the lines from "החזירנו בתשובה" through "כתבנו / זכרנו" are
  `chazzan_then_congregation`; the last line ("חננו ועננו") is `together`
  and `undertone`; the rest is `together`.
- The individual's own prayer (Pesukei Dezimra, the silent Amidah, Shema)
  needs no role.
- An instruction that only names a speaker is `kind: speaker`, with the
  role it introduces.

### `gestures`

`stand`, `sit`, `bow` (at the start or end of a blessing), `bow_full`
(Aleinu, Modim), `knees_bend`, `rise_on_toes` (Kadosh), `feet_together`,
`three_steps_back`, `three_steps_forward`, `cover_eyes` (Shema),
`kiss_tzitzit`, `gather_tzitzit`, `touch_tefillin`, `head_down` (Tachanun),
`face_ark`, `ark_open`, `ark_close`, `hold_torah`, `shake_lulav`,
`hold_cup`, `look_at_candles`, `look_at_fingernails`, `strike_chest`,
`look_at_moon`, `raise_hands` (kohanim), `turn_west` (Lecha Dodi's Bo'i
VeShalom), `bow_left_right_center` (Oseh Shalom).

Put gestures on the part where they happen, and on an instruction that
describes them.

## Conditions

`when` uses the engine's condition language
(`packages/siddur_engine/lib/src/condition.dart`), built from the variables
in `corpus/variables.json`:

    roshChodesh || cholHamoed
    !shabbat && (aseretYemeiTeshuva || publicFast)
    dow in [1, 4]
    omerDay == 33
    il && !shabbat

- Conditions are relative to the service the text is in. A line inside the
  Shabbat Shacharit Amidah that says "on Rosh Chodesh" is just `roshChodesh`.
- Use the most specific variable there is: `tishaBav`, not
  `fastDay && hMonth == 5`; `moridHatal`, not `!mashivHaruach`. The same
  goes for `talUmatar`, `tachanunShacharit`/`tachanunMincha`,
  `avinuMalkeinu`, `avHarachamim`, `tzidkatcha`, `hallel`/`wholeHallel`/
  `halfHallel`, `torahReading`, `kohanim`, `birkatKohanimChazzan`.
- A new day or minhag: add the variable to `variables.json` and compute it
  in `packages/siddur_engine/lib/src/day_context.dart`.
- **Personal circumstances** the app can't know (zimun, which foods were
  eaten, saying it for a man or a woman) are `if_…` identifiers with a
  label in `labels.json` ("Three or more ate together"). The line is shown
  marked "If: …" for the reader to decide.
- An instruction that only announces a conditional line ("בר"ח
  אומרים:") gets the same `when` as the line it announces, so both
  appear and disappear together.
- A leaf for one occasion ("Musaf for Rosh Chodesh") gets `when` on the
  leaf. Outside the daily sections, a leaf condition that only names the
  section's own occasion (`shabbat` in the Shabbat section) is unnecessary,
  and wrong when one reads ahead on Friday afternoon.

## Graph nodes

`node` names the unit of the davening a segment belongs to, using the keys
in `corpus/nodes.json` (Avot, Ashrei, Aleinu, Kaddish Shalem…), the same in
every nusach. Set it on the leaf, and override it on parts where a leaf
holds several units (a "Concluding Prayers" leaf goes Ashrei → Uva LeTziyon
→ Kaddish → Aleinu). Notes and instructions take the node of what they're
about. The same text in a different place is still the same node: Ashrei in
Mincha is `mincha.ashrei`, in Pesukei Dezimra `pz.ashrei`; Kaddish anywhere
is a `kaddish.*` node. A unit with no key can use an `x.` prefix
(`x.zemirot.yah_ribon`); add it to `nodes.json` when it's used for anything.

## Service graph

`corpus/graph.json` is the order of each service, the same for every
nusach; `corpus/units.json` says where each of its units is in each
siddur (a leaf or section path). A step is either an **anchor**, part of
the service as the siddur prints it (`shacharit.weekday.amidah`), or an
**insert**, a unit from elsewhere in the book said only `when` (Hallel,
Musaf for Rosh Chodesh, the fast's Selichot, Hoshanot). `only` limits a
step to some nusachim where the order differs (Hoshanot after Hallel, or
after Musaf in Ashkenaz).

`tool/corpus/build_assets.py` checks every unit path and derives each
siddur's insertions: an insert goes after the nearest anchor before it that
the siddur has, else before the nearest one after it. A siddur without the
unit leaves it out. These replace the hand-written `inserts` in
`assets/rules/rules.json` for these siddurim.

A service with a `unit` (weekday Shacharit, Mincha and Maariv) is also
built into each siddur's asset as `services`: its own sections in order
(the unit is a section path, `{path, except}` leaving some out, or
`{from, to}` for a run of sibling sections, as in Koren's "Weekdays") with
its placed inserts. The app's Today plan lists weekday services from these;
a section holding a placement is opened into its parts so the plan is in
the order things are said. `whenBy` gives a step a different condition in
some nusachim (Koren's Hoshana Raba has its own Hoshanot).

To add a day's addition: add the unit's path per siddur to `units.json`,
add an insert step in the right place in `graph.json`, rebuild, and add an
order test to `packages/siddur_engine/test/corpus_books_test.dart`.

## Short notes for every siddur

`assets/rules/notes.json` holds the app's short notes ("Add Ya'aleh
VeYavo. Forgot it? …"), shown with concise notes on, on the days they
apply, in place of the siddur's long halachic notes. They aren't tied to
one siddur: each is found by a Hebrew `anchor` within a section (`within`:
`amidah`, `mazon` or a path regex). A note for one siddur only, or one
place, goes in that siddur's text as a segment of `kind: note`. The file
is bundled as it is; there is nothing to build.

## History

Until October 2026 the text was exported from Sefaria (`corpus/raw`),
tagged by Claude and a local model (`corpus/tagged`), and corrected at
build time by `tool/corpus/reconcile.py`. All three were folded into
`corpus/siddur` and removed; they are in git history. A leaf condition
corrected in that review says so in its `comment`.
