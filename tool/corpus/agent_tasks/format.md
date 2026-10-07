Format this leaf: fix only what `lint` lists, using the command printed after each `→`.

Steps:
1. Run `lint`. If it says `clean`, reply DONE.
2. Answer in ONE block with the fixing commands:
   - `verse he:A wK` or `verse he:A wK glued n=N`: bakes a real verse number (a small numeral before a verse). Copy the command exactly as lint prints it. Several verse commands for the same part go in DESCENDING word order (highest wK first) so the word numbers stay valid.
   - `balance ADDR`: closes unclosed tags and drops stray closing tags. `tidy ADDR`: collapses double spaces.
   - `X has no en=`: `show` the part and add a short plain English line: `set ADDR en="Bow"` for an instruction, a one-sentence English rendering for a note or heading, `en="The chazzan:"` for a speaker. Say only what the Hebrew says.
3. Run `lint` again. If it is `clean`, or only lists things you are told not to touch, reply DONE.

Rules:
- Never invent a verse number. Only bake the ones lint lists with `→ verse`. Acrostic letters at the start of words (Ashrei's ט י כ ל…) are NOT verse numbers; lint never lists them, so leave them.
- Do not retag, retext, split, merge or reorder anything. Do not touch `when`, `role`, `voice`, `node`, `kind` or any Hebrew text. No other edits "while you are there".
- Never write Hebrew in a command. If a fix seems to need Hebrew, leave it and say so in your reply.
- If a command errors, read the error, fix that one command, and resend the block. After two failures on the same item, skip it.
