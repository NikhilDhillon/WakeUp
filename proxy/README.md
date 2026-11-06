# WakeUp proxy

A small Cloudflare Worker that holds your OpenAI key and forwards the app's photo checks, so other people can use WakeUp without a key of their own. It forwards only `POST /v1/decisions` and `POST /v1/responses`, only for allowed models, caps the request size, and limits each device and the whole service per day.

## Deploy

```bash
cd proxy
npm install
npx wrangler kv namespace create LIMITS     # paste the printed id into wrangler.toml
npx wrangler secret put OPENAI_API_KEY      # the real key
npx wrangler secret put APP_SECRET          # optional, see below
npm run deploy
```

Then in the app: **Settings > Check with > WakeUp service**, and enter the `https://…workers.dev` address.

Set a monthly spend limit on the OpenAI key as the hard stop.

## Settings

| Name | Default | Meaning |
|---|---|---|
| `DAILY_LIMIT` | 40 | Checks per device per day (a morning with retries and a follow-up uses about 5–10) |
| `GLOBAL_DAILY_LIMIT` | 2000 | Checks across everyone per day |
| `APP_SECRET` | unset | If set, requests must carry it in `X-WakeUp-App`. A casual guard only: it ships inside the app. |

## What it does and doesn't protect

- The app sends a random per-install ID as the bearer token. The proxy stores only a hash of it plus a counter, expiring after about a day.
- The counters use Workers KV, which isn't atomic, so a device can slip a few requests past its limit when it sends many at once. That's fine for a soft cap; the global cap and OpenAI's spend limit are the hard stops.
- A determined person can mint new IDs to get more checks. Real protection needs Apple App Attest (paid developer program).
- OpenAI's own 401 (the proxy's key is wrong) is returned as 502 so the app doesn't tell users their key is bad.

## Test

```bash
npm test
```
