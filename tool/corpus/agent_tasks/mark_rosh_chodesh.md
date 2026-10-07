Mark the Rosh Chodesh additions in this section and give each an English instruction.

Steps:
1. `outline`, then `show` the leaves in scope. Find the lines said only on Rosh Chodesh (they usually follow a rubric such as ר"ח / בראש חודש, or contain יעלה ויבוא).
2. Look at `vars rosh` for the exact variable name, then tag only those words: `tag he:A wK..L when=roshChodesh`.
3. Add or fix the rubric that introduces them: `set he:A.1 kind=instruction when=roshChodesh en="On Rosh Chodesh:"`.
4. `show` the result and reply DONE.

Rules: change nothing that is said every day; never write Hebrew in a command; use `find ~phrase` to locate words instead of guessing word numbers; if you are not sure a line is Rosh Chodesh only, leave it and say so.
