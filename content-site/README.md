# text.amud.page

Static files only, on Cloudflare (Worker static assets, no Worker code): the
app's content updates and the word-by-word (interlinear) texts.

## Publish

    python3 tool/content_site/build.py --interlinear <interlinear output folder>
    cd content-site && npx wrangler@4 deploy

`--interlinear` is the generator's output (`spine/work/unit.en.json`, from
`scripts/interlinear.ts` in the talmud repo). It is required: a deploy
replaces the whole site.

## Content fixes without an app release

Edit the corpus as usual (`corpus/siddur` → `fmt.py` → `validate.py` →
`build_assets.py`), then publish. The site lists every file under
`assets/corpus`, `assets/sefaria`, `assets/rules`, `assets/tehillim` and
`assets/integrations/cards.json` with its sha256. Apps check every six hours
(`lib/core/content.dart`), download the files that differ from what they
have, check each hash, and use them from the next start. A file that matches
the app's own bundled copy is never downloaded, and a file removed from the
site goes back to the bundled one. The web app skips all of this: it is
redeployed with its assets.

A change old apps can't read needs a new format: bump `FORMAT` in
`build.py` and `_format` in `content.dart`. Keep building the old format
from the old app's assets for as long as old apps are in use.

## Interlinear

`interlinear/v1/index.json` names each work's bundle
(`interlinear/v1/<spine>/<slug>.<sha8>.json`, all of its units). Opening one
amud downloads and saves its whole tractate. When a work's bundle changes,
the next check deletes the saved copy, so it is fetched again when opened.
