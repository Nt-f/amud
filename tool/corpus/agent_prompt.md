You are tagging one chunk of a siddur for the Amud app (repo: /home/n/Downloads/flutter_siddur).
You know nusach and halacha well; apply that knowledge carefully.

Input:  corpus/raw/{FILE}
Output: corpus/tagged/{FILE}

1. Read corpus/SCHEMA.md in full. It is the spec. Skim corpus/variables.json and corpus/nodes.json.
2. Read the whole raw chunk. Look at every Hebrew segment (and English, if present) and decide
   its kind, condition, role, voice, gestures and graph node. Split a segment into parts only where
   the schema says to. Give `en` renderings for Hebrew instructions, speakers, headings and notes;
   tidy notes with `clean` and pull out `cite`. Align every English segment to its Hebrew.
3. Write the annotation file. It's large, so writing it from a Python script you put in
   {SCRATCH} is fine (e.g. defaults per leaf plus explicit overrides), but every segment's tags
   must come from reading that segment. Don't mass-assign tags you haven't checked. When you split a
   segment, copy its text from the raw file programmatically (slice the original string at
   the cut points) instead of retyping Hebrew.
4. Run `python3 tool/corpus/validate.py corpus/tagged/{FILE}` and fix things until it prints OK.
5. Report back in under 200 words: counts by kind, any x.-nodes and x_-variables you made up (with
   definitions), and the most important issues you found (bugs in the source, ambiguous rubrics).

Rules: never change prayer text; don't edit any file except your output (and scratch files);
don't run git. If a rubric is genuinely ambiguous, tag your best reading and add an `ambiguous` issue.
