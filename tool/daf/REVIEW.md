# Reviewing line maps

`review.py` writes a packet for each amud: `build/daf/review/<Book>_<amud>/`
with `packet.json` and one picture per line, `NN.png`, where NN is the line's
`id` in two digits. A reviewer, whether a person or an agent, says which
words are printed on each line and writes the answers to `answers.json` in
the same folder. `review.py --apply Book amud` then checks the answers and
adds them to `tool/daf/corrections/<Book>_<amud>.json`, which `linemap.py`
applies.

## The packet

Each entry in `lines` has these fields:

- `stream`: `main` is the Gemara, in square letters. `inner` is Rashi and
  `outer` is Tosafot, both in Rashi script. (In Nedarim the inner margin is
  the Ran.)
- `given`: the words [from, to) currently on the line.
- `words`: [[index, word], …], the text's words around it, numbered. They
  come from Sefaria, not from the print.
- `read`: an OCR reading of the line. It may be wrong.
- `flag`: why the line is in the packet. `shift`, `low`, `missed`, `split`
  and `skip` come from check.py. `sample` means a line the check passed,
  included to measure what the check misses. Treat a sample like any other
  line: it may be right or wrong.

## How to answer

1. Read the boxed row on the picture yourself, right to left: a line's
   first word is at its right end. The red box can miss part of the
   printed row. The line is the whole row of text at the box's height,
   within its column. Columns are separated by gaps much wider than a word
   space.
2. Find in `words` the first and last word printed on that row. Sefaria
   differs from the print in a few ways:
   - It spells out abbreviations: the print's דב"ש is Sefaria's דבית שמאי.
   - It adds verse and page references in parentheses, like (שמות כא, ו)
     or (פסחים דף מ:). The print sets these in the margin, or as a small
     mark, not as words of the line.
   - A Sefaria word between two printed words of a row belongs to that row.
     A reference in parentheses at either end of a row isn't printed in
     it, so it doesn't matter which row it goes with. Leave it where
     `given` has it.
3. If the row ends one comment and starts another that Sefaria has
   elsewhere (the print orders comments differently), give both runs in
   printed order: `"words": [[a, b], [c, d]]`. The packet's `words` show
   only the text near `given`. `texts` has each stream whole, as
   `index:word`, so search it for the other comment's words. Don't guess
   indices: if you can't find them, say so in `unsure`.
4. If the row is part of another body text than `stream` says, answer with
   that text and its words: `"stream": "inner", "words": [a, b]`. Find
   them in `texts`. A row that holds two texts (two columns read as one
   line) is `unsure`: it needs two boxes.
5. If the row isn't part of this text at all (a heading, a note, another
   commentary), answer `"drop": true`.
6. If you can't read both ends with certainty, answer `"unsure"` with the
   reason. A person will look at it. An honest unsure is better than a
   guess.

A row that holds two texts gets one entry per text in the corrections file,
each with `"split": true` and the x range of its part (`x0`, `x1`, in page
pixels): the row's OCR words are divided between them by where they stand.
A person can mark the cut by drawing a green line on the picture.

`to` is one past the last word's index. Always give a `why` that names the
words you read at both ends of the row.

```json
[{"id": 0, "words": [49, 54], "why": "row reads מרבנן … רבינא"},
 {"id": 1, "words": [[113, 115], [40, 43]], "why": "ends לדרשא אחרינא:, then the comment אינו צ\"ל חריש"},
 {"id": 2, "drop": true, "why": "Hagahot HaBach heading"},
 {"id": 3, "unsure": "left end hidden by a stain"}]
```
