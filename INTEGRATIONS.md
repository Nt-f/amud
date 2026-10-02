# Device integrations

Settings → Reading & device controls reader wake lock, system bars, travel
prompts, desktop tray and the Omer badge. These are opt-in. Widgets, shortcuts &
voice contains launcher choices, prayer links and web push. Personal dates and
the card gallery have their own settings entries. Custom siddur rules now has a
builder and presets alongside the existing JSON editor.

## Widgets and watches

Add Amud from the Android, iOS or macOS widget picker. The widget uses the saved
location, candle-lighting offset and zmanim opinions. Its eight-day timeline
updates Hebrew dates at sunset and stops displaying expired calculations.
Operating systems can delay widget refreshes. Reopen Amud regularly and after
changing location or prayer versions.

Android builds also produce `build/wear/outputs/apk/debug/wear-debug.apk` (or the
release equivalent). Install the companion on a paired Wear OS watch. Phone and
watch must share application ID `page.amud` and the signing certificate. The
watch supplies a tile, next-zman/Omer complications and a small offline siddur:
Tefillat HaDerech, Birkat HaMazon and bedtime Shema, when available in the chosen
text. It exports eight dated variants through the Wear Data Layer; oversized
prayers are omitted rather than truncated.

The iOS project embeds AmudWatch, AmudWatchWidgets and AmudWidgets; macOS embeds
AmudWidgets. In Xcode select your signing team for every target, enable App
Groups with `group.page.amud`, and provision the matching entitlements. Watch
data transfers through WatchConnectivity. App Intents require iOS 16/macOS 13;
the watch companion requires watchOS 10. Apple targets and Windows runner code
require validation on their respective hosts; Linux cannot compile them.
Unsigned or independently re-signed Apple bundles may not share their app group.

## Shortcuts, voice and links

Choose up to four icon-menu prayers; Android can additionally pin any of the
five prayers. Siri/Shortcuts intents open a chosen prayer and answer next-zman
and Omer queries from fresh saved data. Android declares OPEN_APP_FEATURE
capabilities for prayers, zmanim and Omer; assistant availability depends on
device, language and distribution. Android voice actions open the relevant
screen. Validate them with the assistant tooling before release.

Examples:

* `https://amud.page/app/siddur/ashkenaz/mincha`
* `https://amud.page/app/#/siddur/ashkenaz/mincha` (existing web hash links)
* `amud://pray/derech`

The web bootstrap opens canonical path links in the same router. HTTPS links
open installed mobile apps only after publishing real signing associations:

```sh
python3 tool/integrations/generate_associations.py \
  --android-fingerprint YOUR_RELEASE_CERTIFICATE_SHA256 \
  --apple-team-id YOUR_APPLE_TEAM_ID
```

Build/deploy the site after generating `landing/.well-known/` files. Use the
Play App Signing certificate when applicable. The manifests and entitlements
already declare the domain; no fabricated signing identities are included.
Windows registers `amud://` per user when launched. For an installed Linux
bundle run `bash tool/integrations/install_linux_links.sh /path/to/amud`.
HTTPS browser-to-desktop app selection depends on the browser/OS; the custom
scheme is the explicit desktop entry point.

Linux tray builds need `libayatana-appindicator3-dev`; installed systems need
the corresponding runtime library and a desktop environment that supports
tray icons. Reader keys 1–9 select jump-bar sections and PgUp/PgDn page.

## PWA

The manifest accepts shared text/title/URLs through a GET share target. Shared
content is previewed and saved as a note card only when the user chooses Save.
The Omer badge uses the browser Badging API; mark the day counted on the Omer
card to clear it. Browser support varies; on iOS web push requires an installed
home-screen PWA. Location checks happen when Amud opens/resumes, rather than
continuously in the background.

Closed-app reminders require the optional push sidecar and real VAPID keys.
Set `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_CONTACT` and
`PUSH_PUBLIC_ORIGIN` in your deployment environment, then:

```sh
docker compose --profile push up -d --build
```

Keep private keys out of the repository. The public HTTPS origin must match
the deployed app. Compose assigns nginx a dedicated proxy address; the sidecar
trusts only that address (`PUSH_TRUSTED_PROXIES`) when accepting nginx's overwritten
`X-Amud-Client-IP` header for per-client registration quotas. If you change the
Compose subnet, update both addresses and the trusted proxy CIDR. For an additional
upstream reverse proxy, configure nginx's real-IP handling for that trusted peer
so `$remote_addr` remains the browser address. Never trust arbitrary client headers.
Nginx forwards `/app/api/push/` to the sidecar, which persists
subscriptions and dated schedules in `push-data`. Enable Web reminders in
Widgets, shortcuts & voice, then configure reminders normally. Opting in sends
the subscription and notification schedule (including reminder text) to this
server. Reopen the app to renew schedules. Without a configured server the
switch is disabled and existing open-app web reminders continue to work.
End-to-end push delivery needs a deployed server and supported browser.

## Hebrew dates, rules and cards

Personal dates store the original Hebrew date and use Hebcal anniversary rules
for leap years and variable month lengths. Bar mitzvah dates start at thirteen;
their parsha follows the saved Israel/diaspora setting. Reminders can use the
previous evening's sunset or 09:00 on the date in the saved location's zone.
Notification scheduling respects each platform's pending-notification limit;
reopening Amud refreshes the schedule.

Kiddush Levana already existed in Holidays & Seasons. It now also has a
dashboard window card and optional nightly reminders inside the selected
three/seven-day window. Birkat HaChama adds a next-occurrence card, optional
sunrise reminder and a blessing reader if the selected corpus lacks one.
Add these cards through the dashboard card editor.

The bundled JS gallery index is `assets/integrations/cards.json`. The gallery
also accepts HTTPS community indexes using that version-1 schema, including
GitHub raw URLs. Scripts are shown and previewed before installation and run in
the existing sandbox. There is no automatic subscription to an external index.
