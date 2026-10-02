# Resume siddur corpus conversion

The exporter and schema were started during the Claude Code conversion.
`convert.py` continues unfinished raw chunks using an OpenAI-compatible server.
It preserves existing validated annotation files and checkpoints each successful
batch under `corpus/work/`. Only fully validated chunks enter `corpus/tagged/`.

```bash
python3 tool/corpus/convert.py \
  --base-url http://100.110.29.120:8000/v1 \
  --model siddur
```

`--workers N` converts N chunks at once (one child process per chunk, so
checkpoints never collide; vLLM batches the requests). Each child logs to
`corpus/work/logs/<nusach>/<chunk>.log`; the main log gets START/OK/INCOMPLETE
lines.

Use `--limit 1` to finish one new chunk, or `--chunk nusach/filename.json`
to select a chunk. `--max-batches 1` saves one pilot batch without publishing
an incomplete chunk; `--leaf 'exact/path'` selects one leaf for review.
Repeating a command resumes from checkpoints. Do not run
two converters against the same chunk at once. For authentication, set
`VLLM_API_KEY` (or choose another variable with `--api-key-env`).

After exhausted retries, a failed batch is recorded under `corpus/work/failures/`
and other batches continue. Incomplete or invalid chunks are never published to
`corpus/tagged/`. Running the converter again retries missing batches while
preserving successful checkpoints. Resolving a batch removes its failure record.
Full runs make two passes by default (`--passes 2`), so deferred batches get
another chance after other chunks have progressed. The final log reports any
chunks still incomplete; a finished process does not imply a complete corpus.

Defaults: up to 48 Hebrew and 48 English segments per batch, an 8,192 output
token ceiling, a 600-second request timeout, and two retries. The model receives
the schema, variables, nodes, and nearby leaf context. Thinking is disabled.
This configuration is intended for a 64K context server.

Python handles IDs, candidate formatting boundaries, exact source slicing,
repeated rubric translations, checkpoint merging, and final JSON generation.
The model returns compact typed commands (`tag`, `split`, `align`, `leaf`,
`issue`) and explicit review coverage. It does not return copied prayers or
whole annotation documents. Unchanged prayer defaults need no tag command,
but every selected segment still requires explicit model review. Formatting
classifications are tentative and must be checked by the model.

These commands are a bounded JSON protocol interpreted by `commands.py`, not
shell commands. Arbitrary execution, file paths, and source-text replacement
are rejected. Additional split markers identify source locations; Python
copies original substrings without changing letters, vowels, HTML, or punctuation.
Every English segment requires an explicit alignment command. Exact repeated
instruction text may reuse an English rendering, but calendar conditions and
roles are not reused blindly.

Logs include timestamps, elapsed batch time, output token counts, and command
counts. Successful command responses are archived under `corpus/work/commands/`.

```bash
python3 tool/corpus/validate.py --all
```

Validation checks structure and segment coverage, allowed tags and conditions,
English alignment IDs, and preservation of split source text. The converter
also requires English renderings for Hebrew rubrics and notes. Validation
rejects some observable mixed-rubric errors and confusion between ten diners
and a prayer minyan. Every generated split is built from exact source substrings.
Validation does not establish that religious interpretations, roles, translations, or
conditions are correct; inspect samples before accepting a full run.
