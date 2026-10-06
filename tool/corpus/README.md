# Siddur text tools

Amud's siddur text is `corpus/siddur/<nusach>/` (format and editing guide:
`corpus/SCHEMA.md`). These scripts check it and build it into the app.

    python3 tool/corpus/fmt.py              # canonical layout, after editing
    python3 tool/corpus/validate.py         # problems and warnings, every siddur
    python3 tool/corpus/validate.py koren   # or just some
    python3 tool/corpus/build_assets.py     # → assets/corpus/<nusach>.json.gz

- `source.py`: loading, checking and the file layout, shared by the others.
- `fmt.py`: one line per segment (or per part of a split segment), fields
  in a fixed order with the text last, so diffs show exactly what changed.
  It never changes content.
- `validate.py`: fields and values, conditions (variables from
  `corpus/variables.json`, `if_…` from `corpus/labels.json`), graph nodes,
  unique paths and refs, English alignment. Warns about HTML tags that
  aren't closed in order (some come from Sefaria).
- `build_assets.py`: validates, then writes one gzip JSON per siddur with
  its table of contents, text, `if_` labels and the service graph's
  insertions and services (`corpus/graph.json`, `corpus/units.json`).
  Editors' `comment`s are left out.

Then run the engine's tests, which resolve every day of a year in each
siddur and check the services' order:

    (cd packages/siddur_engine && flutter test)
