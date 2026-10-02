# Amud siddur corpus: tagging schema

The corpus is a structured copy of the bundled Sefaria siddurim. The app
reads it in place of guessing from the raw text. Each segment says what it
is (prayer, instruction, note…), when it is said, who says it and how, and
which unit of the davening (graph node) it belongs to.

    corpus/raw/<nusach>/<chunk>.json      export (tool/corpus/export.py), never edited
    corpus/tagged/<nusach>/<chunk>.json   annotations, one file per raw chunk
    corpus/nodes.json                     canonical graph-node keys
    corpus/variables.json                 condition variables

## The one hard rule

**Never change the words of a prayer.** Annotations point at segments by
id. They copy a segment's text only to split it into parts, and the
validator checks that the parts put back together have exactly the
original letters, niqqud and punctuation. You may *rewrite* only text you
add yourself (`clean`, `en`, `gloss`) for instructions and notes.

## Annotation file

```jsonc
{
  "nusach": "ashkenaz",
  "chunk": "Weekday/Shacharit/Amidah",          // copied from the raw file
  "leaves": {
    // every leaf path in the raw file
    "Weekday/Shacharit/Amidah/Patriarchs": {
      "node": "amidah.avot",                      // default node for its segments
      "when": "true",                             // optional: whole-leaf condition
      "service": "shacharit"                      // optional: shacharit|mincha|maariv|musaf|none
    }
  },
  "he": {
    // EVERY Hebrew segment id in the raw file, in order
    "he:Weekday/Shacharit/Amidah/Patriarchs:1": { "kind": "note", "clean": "…", "en": "…", "cite": "קיצור שו\"ע יח" },
    "he:Weekday/Shacharit/Amidah/Patriarchs:4": { "parts": [
        { "text": "<small>בעשי\"ת:</small>", "kind": "instruction", "en": "During the Ten Days of Repentance:" },
        { "text": " זָכְרֵֽנוּ לְחַיִּים … אֱלֹהִים חַיִּים:", "kind": "prayer", "when": "aseretYemeiTeshuva" }
    ]}
  },
  "en": {
    // EVERY English segment id in the raw file (omit the key if none)
    "en:Weekday/Shacharit/Amidah/Patriarchs:2": { "he": ["he:Weekday/Shacharit/Amidah/Patriarchs:2"] }
  },
  "issues": [
    { "id": "he:…:7", "type": "missing_text", "detail": "…" }
  ]
}
```

A segment entry holds either part fields directly, which describe the whole
segment, or a `parts` list when the segment has to be split. Each part
holds the same fields plus `text`.

### Splitting (`parts`)

Split when one Sefaria segment mixes things that need different tags:

- an instruction and the prayer it introduces (`<small>בר"ח:</small> יעלה ויבוא…`)
- two lines for different days (`בקיץ: מוריד הטל / בחורף: משיב הרוח…`)
- a congregational response inside the chazzan's text
- a halachic note at the end of a prayer line

`text` is the exact substring of the original HTML, and the parts in order
must make up the whole segment. Whitespace and HTML tags at the cut points
don't matter (the validator compares letters, niqqud and punctuation only),
so you can cut between `</small>` and the following word. Copy Hebrew
exactly, character for character, including meteg (ֽ), qamatz qatan and
every maqaf (־). Don't split when one set of tags fits the whole segment.

### Part fields

All fields are optional except `kind`.

| field | values | meaning |
| --- | --- | --- |
| `kind` | `prayer` | Words that are said, including responses, verses and piyyutim. |
|  | `instruction` | A short rubric: when or what to say or do ("On Rosh Chodesh:", "Bow", "The chazzan says:"). |
|  | `speaker` | Only a speaker label ("חזן:", "קהל:", "Chazzan:", "Congregation:"). |
|  | `note` | Halachic explanation, law, or "if one forgot…" ruling. |
|  | `heading` | A title line inside a leaf. |
|  | `commentary` | Explanation, kavanah or essay that isn't said and isn't law. |
| `when` | condition | When this part applies (see Conditions). Omit when always, in context. |
| `alt` | short id | Alternatives where exactly one is said share an `alt` id (e.g. `"geshem"` for מוריד הטל / משיב הרוח), each with its own `when`. |
| `node` | node key | Overrides the leaf's `node` (see Graph nodes). |
| `role` | see below | Who says it. |
| `voice` | `silent` \| `undertone` \| `aloud` | How it's said, when it matters (the silent Amidah is `silent`; Baruch shem kevod in the Shema is `undertone`; the chazzan's Kaddish is `aloud`). |
| `amidah` | `silent` \| `repetition` | Inside an Amidah: said only in the silent prayer or only in the chazzan's repetition (Kedushah, Modim d'Rabbanan, Birkat Kohanim, the chazzan's Aneinu as its own blessing…). |
| `minyan` | `true` | Requires a minyan (Kaddish, Barchu, Kedushah, repetition, Torah reading, Birkat Kohanim…). |
| `gestures` | list, see below | What to do while saying it. |
| `repeat` | int | Said this many times (Kadosh x3, Baruch Hashem LeOlam x2, verses said three times…). |
| `clean` | HTML | Instructions and notes only: the same text tidied: whitespace, broken tags, stray punctuation, brackets. Keep the wording and language. Omit if nothing changes. |
| `en` | text | Instructions, notes, headings and speakers in Hebrew: a faithful, concise English rendering. **Always give this for Hebrew instructions, speakers and headings**, and for notes. |
| `he` | text | The same for English-only instructions (a concise Hebrew rendering), on `en` entries. |
| `cite` | text | A source cited in a note (`קיצור שו"ע יח`, `משנה ברורה קיד`), taken out of the text. |
| `gloss` | text | One line in English on why or when, if the siddur doesn't say and it isn't obvious ("Said only when there is a minyan of ten"). Use sparingly. |
| `forgot` | `true` | A note about what to do if one forgot or erred. |

### `role`: who says it, and how the kahal and chazzan share it

| value | meaning | examples |
| --- | --- | --- |
| `individual` | Each person, at their own pace (default). | Pesukei Dezimra, the silent Amidah |
| `chazzan` | The chazzan (or reader) alone; the kahal listens and answers Amen. | Kaddish, the repetition, Haftarah blessings |
| `congregation` | The kahal alone, out loud: a response. | אמן יהא שמיה רבא, ברוך ה' המבורך לעולם ועד |
| `congregation_then_chazzan` | The kahal says it first, then the chazzan repeats it aloud. | Kedushah verses (Kadosh, Baruch, Yimloch) in many nusachim; Avinu Malkeinu lines where the chazzan repeats; Hoshanot |
| `chazzan_then_congregation` | The chazzan leads each line and the kahal repeats it. | Shema Yisrael and Echad when taking out the Torah; Gadlu; the Thirteen Attributes in Selichot; Ki Hinei KaChomer |
| `together` | Chazzan and kahal say it aloud together. | Avinu Malkeinu, chaneinu va'aneinu; the last verse of Shirat HaYam; Shema Koleinu in Selichot; Hoshia et Amecha in some customs |
| `responsive` | Alternating verses between chazzan and kahal. | Hallel (Hodu, Ana HaShem), Anim Zemirot, the opening of Lecha Dodi in some customs |
| `kohanim` | The kohanim. | Birkat Kohanim when duchening |
| `mourner` | Those saying Kaddish (mourners, or someone saying it for them); the kahal answers. | Mourner's Kaddish, Kaddish d'Rabbanan |
| `oleh` | The person called to the Torah (Barchu and the aliyah blessings); the kahal answers. | Birkot HaTorah for an aliyah, Birkat HaGomel |
| `head_of_household` | The person making Kiddush, Havdalah, leading a seder or Zimun. | Kiddush, Havdalah, the Zimun call |

Tag a role only where the siddur says so or where the custom of the
nusach is clear and widespread. Avinu Malkeinu, for example, is said
`together` or `chazzan_then_congregation` depending on the nusach and the
line, and the siddur's own instructions take precedence. When a part's role
depends on whether there's a minyan, tag the minyan reading and add
`minyan: true`.

### `gestures`

`stand`, `sit`, `bow` (at the start or end of a blessing), `bow_full`
(Aleinu, Modim), `knees_bend`, `rise_on_toes` (Kadosh), `feet_together`,
`three_steps_back`, `three_steps_forward`, `cover_eyes` (Shema),
`kiss_tzitzit`, `gather_tzitzit`, `touch_tefillin`, `head_down` (Tachanun),
`face_ark`, `ark_open`, `ark_close`, `hold_torah`, `shake_lulav`,
`hold_cup`, `look_at_candles`, `look_at_fingernails`, `strike_chest`,
`look_at_moon`, `raise_hands` (kohanim), `turn_west` (Lecha Dodi's Bo'i
VeShalom), `bow_left_right_center` (Oseh Shalom).

Put gestures on the part where they happen, not on an instruction that only
describes them (tag that instruction too, with the same gesture).

## Conditions

`when` uses the engine's condition language, built from the variables in
`corpus/variables.json` (`proposed: true` ones are fine to use too):

    roshChodesh || cholHamoed
    !shabbat && (aseretYemeiTeshuva || publicFast)
    mashivHaruach
    dow in [1, 4]
    omerDay == 33
    il && !shabbat

- Conditions are relative to the service the text is in. A line inside the
  Shabbat Shacharit Amidah that says "on Rosh Chodesh" is just `roshChodesh`.
- Use the most specific variable available: `tishaBav`, not `fastDay && hMonth == 5`.
- If a condition needs a variable that doesn't exist, use `x_<camelCase>`
  (e.g. `x_shabbatShira`) and report it in `issues` with type
  `new_variable` and a definition.
- A minhag choice the user makes (rather than the calendar) also gets
  `x_…`, e.g. `x_saysPatachEliyahu`. Report it the same way.
- An instruction that only announces a conditional line ("בר"ח
  אומרים:") gets the same `when` as the line it announces, so both
  appear and disappear together.
- A whole leaf for one occasion ("Musaf for Rosh Chodesh") gets `when` on
  the leaf.

### Pitfalls (from the first tagged chunk)

- **Use the specific variable that exists.** Morid HaTal is `moridHatal`
  (Ashkenaz outside Israel says nothing in summer), not `!mashivHaruach`.
  The same goes for `talUmatar`, `tachanunShacharit`/`tachanunMincha`,
  `avinuMalkeinu`, `avHarachamim`, `tzidkatcha`, `hallel`/`wholeHallel`/
  `halfHallel`, `torahReading`, `kohanim`, `birkatKohanimChazzan`. Read
  `variables.json` before you write a condition.
- **Customs that vary aren't calendar rules.** When communities within the
  nusach differ on whether something is said (Vidui and the 13 Middot
  every day or only Monday and Thursday, Patach Eliyahu, LeDavid in Elul at
  Mincha), don't guess a calendar condition. Combine the calendar condition
  with an `x_` minhag variable (`tachanunShacharit && x_viduiDaily`) and
  report it as `new_minhag`.
- **Tag `role` throughout the public parts of the service, not only where
  there's a speaker label.** This is how the app shows how a passage is
  read. In particular:
  - Avinu Malkeinu: `ark_open` on its first line, `ark_close` after it.
    In Ashkenaz the lines from "החזירנו בתשובה" through the
    "כתבנו / זכרנו" lines are `chazzan_then_congregation`. The last line
    ("חננו ועננו") is `together`, said quietly (`undertone`). The rest is
    `together`, unless the nusach or the siddur says otherwise.
  - Kaddish: the chazzan's lines are `chazzan` and `aloud` (Mourner's Kaddish and Kaddish d'Rabbanan: `mourner`); the responses
    (אמן, יהא שמיה רבא, בריך הוא) are `congregation` (split them out when
    they're printed inline).
  - Barchu: the call is `chazzan`; the response is `congregation_then_chazzan`.
  - Kedushah, Modim d'Rabbanan, Birkat Kohanim: as in the role table.
  - Taking out and returning the Torah, Hallel, Selichot, Hoshanot,
    Lecha Dodi, Ein KeElokeinu, Anim Zemirot, Adon Olam and Yigdal at the
    end: tag the customary way each line is read.
  - The individual's own prayer (Pesukei Dezimra, the silent Amidah,
    Shema) needs no role.
- An instruction that only names a speaker belongs in `kind: speaker`,
  with the role it introduces.

## Graph nodes

`node` names the unit of the davening a segment belongs to, using the keys
in `corpus/nodes.json` (Avot, Ashrei, Aleinu, Kaddish Shalem…), the same in
every nusach. Set it on the leaf, and override it on parts where a leaf
holds several units (a "Concluding Prayers" leaf goes Ashrei → Uva LeTziyon
→ Kaddish → Aleinu). Notes and instructions take the node of what they're
about.

The same text in a different place is still the same node: Ashrei in
Mincha is `mincha.ashrei`, Ashrei in Pesukei Dezimra is `pz.ashrei`. Kaddish
anywhere is a `kaddish.*` node.

For a unit that has no key, invent one with an `x.` prefix in the same
style (`x.selichot.shema_koleinu`, `x.zemirot.yah_ribon`) and use it
consistently in the chunk. The tagging run collects and reconciles them.

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
`assets/rules/rules.json` for the tagged siddurim.

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

## English segments (`en`)

Every English segment id gets an entry:

- `he`: the Hebrew segment ids it translates, in order (one-to-one
  usually, sometimes one-to-many or many-to-one). Use `[]` if there's no
  counterpart.
- `kind`, and any other field, only when it differs from the Hebrew it
  translates. Instructions present only in English need `kind` and `when`.
- `parts`, if an English segment mixes a rubric and prayer text, as for
  Hebrew. The same copy-exactly rule applies.

## `issues`

Report problems in the source text that the app should fix or work around.
Each issue has `id`, `type` and `detail`.

- `missing_text`: a line, blessing or paragraph that should be there isn't (e.g. the first lines of the Shema empty).
- `misplaced`: text that is in the wrong section, or out of order.
- `duplicate`: the same text twice where it should appear once.
- `wrong_vowel`: an evident typo in vowels or letters. Report it; never fix it.
- `ambiguous`: a rubric whose condition you couldn't decide.
- `new_variable`, `new_minhag`: as above.
- `alignment`: English and Hebrew that don't line up.
- `engine_bug_risk`: anything that would make a naive reader show the wrong text on some day.

## Validating

    python3 tool/corpus/validate.py corpus/tagged/<nusach>/<chunk>.json

This must print `OK` before the chunk is done. It checks that every id is
covered, that parts put back together match the original text, that the
enum values are valid, that conditions parse with known (or `x_`)
variables, and that the node keys exist (or start with `x.`).
