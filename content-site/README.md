# text.amud.page

Static files only, on Cloudflare (Worker static assets, no Worker code): the
app's content updates and the word-by-word (interlinear) texts.

## Publish

    python3 tool/content_site/build.py --interlinear <interlinear output folder>
    cd content-site && npx wrangler@4 deploy

`--interlinear` is the generator's output (`spine/work/unit.en.json`, from
`scripts/interlinear.ts` in the talmud repo). It (or `--live`) is required: a deploy
replaces the whole site.

To publish only the printed daf (`--daf-print build/daf/place`, from
`tool/daf/shas.py render`) without touching anything else, use
`--live DIR` instead of `--interlinear`: DIR is a copy of the live site's
`content/v1`, `interlinear/v1` and `daf/v2` (each file checked against its
sha256), deployed as is. DIR can't be inside the output (`content-site/dist`
is emptied first), so copy it elsewhere. `--live` refuses a `content/v1` that
lists a file older than the latest release's copy, or one neither that
release nor this checkout has: apps up to 0.14 would take it in place of their newer text (this put
October's siddurim back into every app in November 2026). `--drop-stale`
takes those off the list, and apps go back to their own copies.

## Content fixes without an app release

Edit the corpus as usual (`corpus/siddur` → `fmt.py` → `validate.py` →
`build_assets.py`), then publish. The site lists every file under
`assets/corpus`, `assets/sefaria`, `assets/rules`, `assets/tehillim` and
`assets/integrations/cards.json` with its sha256 and `replaces`: the sha256
of every earlier version of it committed in this checkout's history (so
build from a full clone, at or after the latest release). Apps check every
six hours and right after an app update (`lib/core/content.dart`), download
a file only if their own bundled copy is in its `replaces` (a later version
of what they ship), check each hash, and use it from the next start. A site
published before a release therefore never puts older text back into it. A
file the app doesn't ship is new and taken, unless the site is behind on a
file it does ship. A file removed from the site, or not newer, goes back to
the bundled one. The web app skips all of this: it is redeployed with its
assets.

Apps up to 0.14 ignore `replaces` and take every file that differs from
their own copy, so the site must never list a file older than the newest
release's: publish after a release from that release's checkout or later,
and keep `--live` deploys checked (above).

A change old apps can't read needs a new format: bump `FORMAT` in
`build.py` and `_format` in `content.dart`. Keep building the old format
from the old app's assets for as long as old apps are in use.

## Interlinear

`interlinear/v1/index.json` names each work's bundle
(`interlinear/v1/<spine>/<slug>.<sha8>.json`, all of its units). Opening one
amud downloads and saves its whole tractate. When a work's bundle changes,
the next check deletes the saved copy, so it is fetched again when opened.
