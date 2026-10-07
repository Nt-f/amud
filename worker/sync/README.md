# amud-sync: the sync mailbox

A tiny Cloudflare Worker (one SQLite-backed Durable Object per mailbox) that
holds a single **end-to-end encrypted** blob for the app's cross-device
settings sync. It can't read your settings: the key never leaves your devices.
It sees an IP address, a random 128-bit mailbox id, a hash of a bearer token,
and ciphertext. No accounts, no emails.

## Run your own

```sh
cd worker/sync
npm install
npx wrangler deploy
```

Then in Amud: Settings → Advanced → Sync between devices → Advanced → Worker
URL, and paste the `https://amud-sync.<you>.workers.dev` it prints. Devices you
pair carry that URL in the pairing code.

## Protocol (v1)

All paths `https://<worker>/v1/…`. `<id>` is 32 hex chars. Every mailbox call
sends `Authorization: Bearer <token>` (≥16 chars); the first successful `PUT`
claims the mailbox for that token and every later call must match it.

| Call | Meaning |
|---|---|
| `GET /v1/health` | `{ok:true, app:"amud-sync", v:1}`, no auth; used to validate a custom URL |
| `GET /v1/<id>` | `200 {rev, blob}` (or `{rev:0}` if never written), `404` if unclaimed |
| `PUT /v1/<id>` | body `{blob}`, header `If-Match: <rev>` (`0` to create). `200 {rev}`; `409 {error:"conflict", rev, blob}` if it moved, so merge and retry |
| `DELETE /v1/<id>` | wipe the mailbox |

`blob` is a base64 string, ≤256 KB. Mailboxes untouched for 180 days delete
themselves. The Worker sets `Access-Control-Allow-Origin: *` so the web build
can use it; it relies on the secrecy of the mailbox id and token, not origin.

Abuse: anyone can create mailboxes. If yours is public, add a Cloudflare rate
limiting rule on `PUT /v1/*`.

## Text reports

`POST /v1/report` takes `{uid, location, type, text, details, correction, app}`
(`uid` = 32 hex chars, a random id the app makes once per install; it is not
derived from anything and is never used for sync). Rows go into one SQLite
Durable Object (`Reports`, table `reports`), at most 20 per uid per day. No
auth to send, no IP stored. To read them, set a secret
(`npx wrangler secret put ADMIN_TOKEN`) and `GET /v1/report` with
`Authorization: Bearer <that token>` (newest 500).
