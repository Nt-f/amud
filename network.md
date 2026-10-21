# Network

Every domain the app talks to, and when and why. The siddurim, zmanim,
calendar and notifications work fully offline. The network is only for
optional extras, downloads the user starts, and updates.

"Fetch" means the app makes the request itself. "Link" means it only opens the
URL in the browser when the user taps it.

## Amud's own servers

| Domain | What | When |
|---|---|---|
| `text.amud.page` | Content updates (`/content/v1/manifest.json`, `/files/…`): corrected siddur text, Sefaria texts, rules, Tehillim. Also the interlinear Gemara texts (`/interlinear/v1/…`). | Content: checked in the background at most every 6 hours, and the update takes effect on the next launch. Not on the web, which gets new content when the site is redeployed. Interlinear: when a daf is opened in the interlinear view. Printed-page line maps (`/daf/v1/…`, a tractate per file): when a Bavli amud is opened in the page view, once per tractate (then saved; the content check drops them when the site's copy changes). `lib/core/content.dart`, `lib/features/gemara/interlinear.dart`, `lib/features/gemara/daf_print.dart`. The user can change the interlinear server in the Gemara settings. |
| `video.amud.page` | Daf Yomi and Kitzur video shiurim, as HLS from the `amud-video` R2 bucket. `/daf/index.json` lists which units have a video. | `index.json`: once per run, when a Gemara or Kitzur screen asks whether a video exists. The streams load only when the user presses play. `lib/features/gemara/daf_video.dart`. A build can change this with `--dart-define=DAF_VIDEO_BASE`, or turn it off with an empty value. |
| `worker.amud.page` | Settings sync: an end-to-end encrypted mailbox (`/v1/{mailbox}`, `/v1/health`). Also receives text error reports (`/v1/report`). | Sync: only after the user turns on Settings → Advanced → Sync between devices. The user can enter their own Worker URL instead. Reports: when the user sends a text report from the reader's selection menu. Without a Worker, the report opens a GitHub issue instead. `lib/core/sync/`, `lib/core/text_report.dart`. |
| `amud.page` | The web app and landing page are hosted here (Cloudflare). The web app fetches its own files from this origin: the app, the bundled texts, `voice-model/…` for offline voice on the web, and `app/api/push/` for web push if that's ever deployed. Links: `amud.page/privacy/` (Settings) and `amud.page/app/…` share links. | The web build loads from here and caches everything offline in its service worker. Native apps only open links here. They also handle incoming `amud.page/app/*` links as app links / universal links (`.well-known/assetlinks.json`, `apple-app-site-association`). |

## Third-party fetches

| Domain | What | When |
|---|---|---|
| `www.sefaria.org` | `api/v3/texts/…`: Gemara (Davidson / Wikisource), Mishnah, Kitzur, and commentaries. `api/v2/raw/index/…`: a tractate's perakim. Also the Torah library books and Shnayim Mikra texts. | When the user opens a Gemara/Mishnah/Kitzur unit or commentary that isn't cached, opens the perek list of a tractate for the first time (then saved), or downloads a Torah library book or Shnayim Mikra (on demand, then stored offline). `lib/features/gemara/gemara_data.dart`, `gemara_perakim.dart`, `lib/features/torah/torah_library.dart`, `shnayim_mikra.dart`. |
| `raw.githubusercontent.com` | Google Fonts Hebrew families (`google/fonts/main/ofl/…`). Also community card-gallery indexes. | Fonts: when the user picks a downloadable font. Built-in fonts never use the network. `lib/core/fonts.dart`. Card gallery: when the user enters an index URL and presses Load index. |
| `api.github.com`, `github.com` (+ `objects.githubusercontent.com` / `release-assets.githubusercontent.com` via redirect) | Release check (`repos/Nt-f/amud/releases/latest`), release notes for the installed version, and the APK download. | Builds not installed from Google Play: the update check, plus release notes on the What's New screen. The APK downloads only when the user taps Update (Android sideload). `lib/features/update/update_service.dart`. |
| `huggingface.co` | The offline voice model (`csukuangfj/sherpa-onnx-whisper-small`, pinned revision, checked by SHA-256). | Native only, when the user turns on offline voice and the model downloads (resumable). `lib/features/voice/voice_model.dart`. |
| Any `https://` host | Home cards written in JavaScript can call `fetch()`. Limits: https only, 10 requests per update, 2 MB, 10 s, GETs cached 5 minutes. | Only for JS cards the user added. `lib/features/js_cards/js_fetch.dart`. |
| Google Play (Play services) | In-app update check and the immediate update flow. | Play builds only (`appFlavor == 'play'`). Falls back to a link to `play.google.com/store/apps/details?id=page.amud`. |

## Analytics (only if "Share usage" is on)

Nothing is sent, and on the web the Firebase scripts aren't even loaded,
while Share usage is off. Debug builds send nothing unless built with
`ANALYTICS_DEBUG`. `lib/core/analytics.dart`.

| Domain | Platform |
|---|---|
| Firebase Analytics SDK: `app-measurement.com`, `firebaseinstallations.googleapis.com`, `firebase.googleapis.com` and the like (project `amud-7a475`) | Android, iOS, macOS |
| `www.gstatic.com/firebasejs/…` (scripts, cached by the service worker), `*.google-analytics.com` | Web |
| `www.google-analytics.com/mp/collect` (GA4 Measurement Protocol, batched) | Windows, Linux. Only when the build has `GA_API_SECRET`. |

## Web build extras

- `fonts.gstatic.com` / `fonts.googleapis.com`: Flutter web may load
  fallback glyph fonts (emoji, rare scripts) from here. The service worker
  caches them for offline use.
- The CanvasKit/skwasm renderers are served from `amud.page` itself
  (`--no-web-resources-cdn`), not Google's CDN. `hls.js` and `pdf.js` are
  bundled in `web/`.
- Web push, if `app/api/push/` is ever deployed: the browser registers with
  its own push service (FCM, Mozilla, Apple), not with a domain the app picks.

## Links only (opened in the browser, never fetched)

- `www.hebcal.com`: holiday, parasha and Omer pages (from `packages/hebcal`)
- `www.sefaria.org`: learning schedule entries the app can't show itself,
  version sources, Shnayim Mikra
- `www.chabad.org`: Sefer HaMitzvos daily study
- `www.dafyomi.org`: Me'ilah dapim
- `godaven.com`: the Find a minyan card. The GoDaven API isn't integrated
  yet (`available: false`), so nothing is fetched.
- `github.com/Nt-f/amud/issues/new`: a text report when no Worker is set
- Siddur version sources (Versions screen): `sefaria.org`, `nli.org.il`,
  `korenpub.co.il`, `daat.ac.il`, `sacred-texts.com`, `toratemetfreeware.com`

## Not used anymore

- `talmud.dev`: the old default interlinear server. Saved settings that
  point to it are reset to `text.amud.page`.
