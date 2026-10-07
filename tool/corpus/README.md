# Siddur text tools

Amud's siddur text is `corpus/siddur/<nusach>/` (format and editing guide:
`corpus/SCHEMA.md`). These scripts check it and build it into the app.

    python3 tool/corpus/fmt.py              # canonical layout, after editing
    python3 tool/corpus/validate.py         # problems and warnings, every siddur
    python3 tool/corpus/validate.py koren   # or just some
    python3 tool/corpus/build_assets.py     # → assets/corpus/<nusach>.json.gz

- `editor/server.py`: the visual editor (below).
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

## Visual editor

    python3 tool/corpus/editor/server.py        # http://127.0.0.1:8765

A browser editor for `corpus/siddur`, standard library only. It saves with
`source.dumps` and checks with `source.check_file`, the same code as `fmt.py`
and `validate.py`, so what it writes is canonical and what it flags is what
the build would reject. It listens on localhost and needs a per-run token.

- Book tree (by path or by file), go-to (Ctrl+P), problems panel.
- Visual editing of every leaf, segment and part field, with HTML tools,
  split/merge parts, English alignment, condition and node autocomplete.
- Raw leaf, raw file and book.json tabs (JSON, with error positions).
- Live preview for a simulated day. Its condition evaluator and rendering are
  a JavaScript approximation (`static/cond.js`, `preview.js`), not the Flutter
  engine: keep `cond.js` in step with `condition.dart`.
- Find and replace across a leaf, file, siddur or all five: niqqud-insensitive,
  tag-insensitive, regex, whole word, filtered by field, kind and role.
- Per-file undo, git diff, disk-change detection, and Build / tests buttons.

## Editing by agent (a free OpenRouter model)

    export OPENROUTER_API_KEY=sk-or-...        # or the editor's Agent tab, or ~/.config/amud/openrouter.key
    python3 tool/corpus/agent.py models         # free models available now
    python3 tool/corpus/agent.py -n ashkenaz --scope Weekday/Minchah "Tag the Rosh Chodesh additions…"

Language models spend most of their tokens re-typing Hebrew to say where an
edit goes. `edit.py` removes that: text is addressed by segment ref and word
number (`tag he:3 w4..9 when=roshChodesh`, `tagall ~"בעשרת ימי" voice=undertone`),
viewed as compact numbered words, and edited with a short command language
(`edit.py help`). `agent.py` runs a plain-text loop against any OpenRouter
model (no tool calling needed): the model reads with `outline`/`show`/`find`,
answers with one command block per turn, and each block is atomic and
validated. Old command output is collapsed, so context stays flat.

Nothing is written until you approve the diff: the CLI asks y/N, `--propose`
saves it for the editor's **Agent** tab (Approve / Reject; refused if the file
changed since), and `--apply` writes directly. Writes keep a backup
(`edit.py undo`). `--scope` limits the leaves the agent can read or edit.

    python3 tool/corpus/test_edit.py            # tests for the edit language
