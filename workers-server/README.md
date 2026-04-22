# 🍆 Eggplant API — Cloudflare Workers

The backend for the Eggplant marketplace, running entirely on Cloudflare:

| Concern | Service |
| --- | --- |
| HTTP API | Cloudflare Workers (Hono router) |
| Database | D1 (SQLite) |
| File storage | R2 (product images) |
| Realtime | Durable Objects + WebSocket (chat + WebRTC signaling) |
| Domain | `api.eggplant.life` (Cloudflare DNS + Worker route) |

**Cost: $0/month** (well within free tier).

---

## 1. Prerequisites

```bash
# One-time tools
npm install -g wrangler        # Cloudflare CLI

# Log in once (opens browser)
wrangler login
```

Install project dependencies:

```bash
cd workers-server
npm install
```

---

## 2. First-time Cloudflare setup

> Run each command from `workers-server/`. Copy the IDs that Wrangler prints
> into `wrangler.toml` where indicated.

### 2.1 Create the D1 database

```bash
npm run db:create
```

Wrangler will print something like:

```
database_name = "eggplant-db"
database_id   = "abcd1234-5678-90ef-ghij-klmnopqrstuv"
```

Open `wrangler.toml` and replace `REPLACE_WITH_YOUR_D1_ID` with the printed
`database_id`.

Apply the schema to the remote database:

```bash
npm run db:migrate:remote
```

(For local development use `npm run db:migrate:local`.)

### 2.2 Create the R2 bucket

```bash
npm run r2:create
```

Optional but recommended — enable public access so image URLs are served
from Cloudflare's CDN:

1. Dashboard → R2 → `eggplant-uploads` → Settings → **Public access** → Allow.
2. Copy the public URL (e.g. `https://pub-xxxxxxxx.r2.dev`).
3. Paste it into `wrangler.toml` under `PUBLIC_UPLOAD_URL`.

If you skip this, images are still served through the Worker at
`/uploads/<key>` (works fine, just slightly costlier).

### 2.3 Set the JWT secret

```bash
npm run secret:jwt
# Paste a long random string at the prompt, e.g.:
#   openssl rand -hex 32
```

This secret is used to sign the JSON Web Tokens issued by `/api/auth/*`.
**Never commit it.**

---

## 3. Deploy

```bash
npm run deploy
```

Wrangler uploads the Worker and its Durable Object, then prints the default
URL, something like:

```
https://eggplant-api.<your-account>.workers.dev
```

Quick smoke test:

```bash
curl https://eggplant-api.<your-account>.workers.dev/api/health
# -> {"ok":true,"name":"eggplant-api", ... }
```

---

## 4. Point `api.eggplant.life` at the Worker

1. **Add the zone to Cloudflare** (if not already done):
   - Dashboard → *Add a site* → `eggplant.life` → Free plan.
   - Cloudflare gives you two nameservers (e.g. `amy.ns.cloudflare.com`).
   - In Gabia, replace the current nameservers with these two. DNS propagation
     typically takes 1–2 hours (up to 24 h).
2. **Add a DNS record** for the API subdomain:
   - Cloudflare → DNS → *Add record*:
     `Type = AAAA, Name = api, IPv4 = 100::` (placeholder), **Proxied (orange cloud)**.
     *(Workers custom domains don't need a real origin — the placeholder is
     ignored once the Worker route is bound.)*
3. **Attach the Worker to the domain**:
   - Open `wrangler.toml` and **uncomment** the `routes` block:
     ```toml
     routes = [
       { pattern = "api.eggplant.life", custom_domain = true }
     ]
     ```
   - Redeploy:
     ```bash
     npm run deploy
     ```
   - Cloudflare provisions the TLS certificate automatically (~30 s).

Verify:

```bash
curl https://api.eggplant.life/api/health
```

---

## 5. Update the Flutter app

The app now targets `https://api.eggplant.life` and `wss://api.eggplant.life/socket`
by default (see `lib/app/constants.dart`). No code change is needed once the
domain is live — just rebuild the APK:

- GitHub Actions → *🍆 Build Android APK* → *Run workflow*.
- When the build finishes, download the universal APK from the latest release.

If you want to override the URLs for a local dev build:

```bash
flutter run \
  --dart-define=API_BASE=http://10.0.2.2:8787 \
  --dart-define=SOCKET_URL=ws://10.0.2.2:8787/socket
```

---

## 6. Local development

```bash
npm run dev
# Worker runs at http://127.0.0.1:8787
```

The first run initialises a local D1 SQLite file. Apply migrations once:

```bash
npm run db:migrate:local
```

Set a dev JWT secret in `.dev.vars` (gitignored):

```dotenv
JWT_SECRET=dev-insecure-secret
```

Seed a user:

```bash
curl -X POST http://127.0.0.1:8787/api/auth/register \
  -H 'content-type: application/json' \
  -d '{"nickname":"tester","device_uuid":"dev-1"}'
```

---

## 7. Logs & observability

```bash
npm run tail           # live stream of production logs
```

Dashboard → Workers & Pages → `eggplant-api` → *Logs* and *Metrics*.

---

## 8. API surface

| Method | Path | Auth | Description |
| --- | --- | --- | --- |
| GET  | `/api/health`        | —  | Health check |
| POST | `/api/auth/register` | —  | Create or upsert anonymous user |
| POST | `/api/auth/login`    | —  | Login by `device_uuid` |
| GET  | `/api/auth/me`       | ✅ | Current user profile |
| PUT  | `/api/users/me`      | ✅ | Update nickname / region |
| GET  | `/api/products`      | opt | List with filters |
| POST | `/api/products`      | ✅ | Create (multipart images → R2) |
| GET  | `/api/products/:id`  | opt | Detail (bumps `view_count`) |
| POST | `/api/products/:id/like`   | ✅ | Toggle like |
| PUT  | `/api/products/:id/status` | ✅ | `sale` / `reserved` / `sold` |
| DELETE | `/api/products/:id`      | ✅ | Delete (also removes R2 images) |
| GET  | `/api/products/my/likes`   | ✅ | My liked products |
| GET  | `/api/products/my/selling` | ✅ | My listings |
| GET  | `/uploads/:key`      | —  | Image passthrough from R2 |
| WS   | `/socket?token=<jwt>` | ✅ | Chat + WebRTC signaling |

See `src/chat-hub.ts` for the WebSocket message protocol.

---

## 9. Troubleshooting

- **`database_id` missing** — run `npm run db:create` and paste the ID into
  `wrangler.toml`.
- **`401 Invalid token` on WS** — the JWT must be the same one you got from
  `/api/auth/register`; make sure the Flutter app is rebuilt against
  `api.eggplant.life` (not an older build pointing at `192.168.x.x:3001`).
- **R2 uploads return 200 but images don't render** — either enable R2 public
  access and set `PUBLIC_UPLOAD_URL`, or keep the default Worker passthrough
  (no config needed; just slower).
- **Durable Object migration error on deploy** — this only happens the *very
  first time*; Wrangler creates the class automatically. Subsequent deploys
  re-use it.
