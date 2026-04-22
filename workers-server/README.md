# Eggplant 🍆 Backend — Cloudflare Workers

Serverless backend running on Cloudflare's edge network.

- **API**         : Hono (Express-compatible router)
- **Database**    : D1 (serverless SQLite)
- **Storage**     : R2 (S3-compatible object storage, product images)
- **Realtime**    : Durable Objects + native WebSockets
  (ephemeral chat + WebRTC call signaling)
- **Auth**        : JWT (HS256) via `@tsndr/cloudflare-worker-jwt`
- **Custom domain**: `https://api.eggplant.life`

```
Android app ─► https://api.eggplant.life (Cloudflare proxied)
                    │
              ┌─────┴─────────────────────────────┐
              ▼                                    ▼
  REST  /api/auth/*        WebSocket  /socket?token=<jwt>
        /api/users/*                  (Durable Object "ChatHub")
        /api/products/*
        /uploads/<key>  ── ►  R2 bucket (eggplant-uploads)
                 │
                 └────────►  D1 (eggplant-db)
```

---

## 0. One-time prerequisites (do this on your PC)

```bash
# Node.js 20+ is required.
node --version

# Install Wrangler (Cloudflare CLI). One-shot via npx is fine too.
npm install -g wrangler

# Install this project's dependencies
cd workers-server
npm install

# Sign in with your Cloudflare account (opens browser).
wrangler login
```

---

## 1. Create D1 database

```bash
cd workers-server
npx wrangler d1 create eggplant-db
```

Wrangler prints something like:

```
[[d1_databases]]
binding = "DB"
database_name = "eggplant-db"
database_id = "abcd-1234-..."
```

**Copy the `database_id`** and paste it into `wrangler.toml` (replace
`REPLACE_WITH_YOUR_D1_ID`).

Apply the schema:

```bash
npx wrangler d1 migrations apply eggplant-db --remote
```

---

## 2. Create R2 bucket (product images)

```bash
npx wrangler r2 bucket create eggplant-uploads
```

(Optional, recommended) enable public access for faster image delivery:

1. Open the Cloudflare dashboard → **R2** → `eggplant-uploads` → **Settings**.
2. Click **Allow access** → Cloudflare R2 will give you a public URL like
   `https://pub-abcd1234.r2.dev`.
3. Paste it into `wrangler.toml` as `PUBLIC_UPLOAD_URL`:

```toml
[vars]
ENVIRONMENT = "production"
PUBLIC_UPLOAD_URL = "https://pub-abcd1234.r2.dev"
```

This makes `/uploads/<key>` return a 302 redirect to R2's CDN — free
bandwidth, much faster than going through the Worker.

---

## 3. Set the JWT secret

```bash
# Generate a long random secret (or invent one)
openssl rand -hex 32

# Store it as a Worker secret
npx wrangler secret put JWT_SECRET
# Paste the hex string when prompted
```

---

## 4. Deploy

```bash
npx wrangler deploy
```

On success Wrangler prints the Worker URL, for example:

```
https://eggplant-api.<your-subdomain>.workers.dev
```

Verify:

```bash
curl https://eggplant-api.<your-subdomain>.workers.dev/api/health
# {"ok":true,"name":"eggplant-api","runtime":"cloudflare-workers",...}
```

---

## 5. Connect the domain `api.eggplant.life`

### 5.1. Add `eggplant.life` to Cloudflare (first time only)

1. Cloudflare dashboard → **Add a site** → `eggplant.life` → **Free plan**.
2. Cloudflare gives you 2 nameservers (e.g. `amy.ns.cloudflare.com`, `bob.ns.cloudflare.com`).
3. Log into **가비아 (Gabia)** → DNS 관리 → change the nameservers to the
   two Cloudflare ones. Propagation: usually 1–2 h, max 24 h.
4. Back on Cloudflare, wait for the zone to become **Active** (green check).

### 5.2. Bind the Worker to `api.eggplant.life`

Open `wrangler.toml` and uncomment the `routes` block:

```toml
routes = [
  { pattern = "api.eggplant.life", custom_domain = true }
]
```

Redeploy:

```bash
npx wrangler deploy
```

Cloudflare auto-provisions an HTTPS certificate. Verify:

```bash
curl https://api.eggplant.life/api/health
```

---

## 6. Point the Flutter app at the new server

The APK build workflow (`_github_setup/build-apk.yml`) already defaults to:

```
API_BASE   = https://api.eggplant.life
SOCKET_URL = wss://api.eggplant.life/socket
```

If you previously set GitHub repository **Variables** `API_BASE` and
`SOCKET_URL` to a LAN IP (e.g. `http://192.168.3.41:3001`), **delete them**
(or update them) so the new defaults apply:

> GitHub → Settings → Secrets and variables → Actions → **Variables** tab
> → delete `API_BASE` and `SOCKET_URL`, or change them to the Cloudflare URLs.

Then run the workflow again from the **Actions** tab; the new APK will
connect directly to `https://api.eggplant.life` over the internet.

---

## Local development

```bash
cd workers-server
npm install

# First time: apply schema to a local D1 copy
npx wrangler d1 migrations apply eggplant-db --local

# Start Wrangler's local dev server on http://127.0.0.1:8787
npm run dev
```

Run the Flutter app against the local worker:

```bash
flutter run \
  --dart-define=API_BASE=http://127.0.0.1:8787 \
  --dart-define=SOCKET_URL=ws://127.0.0.1:8787/socket
```

(On Android emulator, replace `127.0.0.1` with `10.0.2.2`.)

---

## File layout

```
workers-server/
├── package.json
├── wrangler.toml            Bindings: DB (D1), UPLOADS (R2), CHAT_HUB (DO)
├── tsconfig.json
├── migrations/
│   └── 0001_init.sql        users, products, product_likes
└── src/
    ├── index.ts             Hono app, routing, R2 passthrough, WS upgrade
    ├── types.ts             Env, ProductRow, UserRow, AuthPayload
    ├── jwt.ts               signToken / verifyToken / middleware
    ├── chat-hub.ts          Durable Object: WebSocket chat + WebRTC signaling
    └── routes/
        ├── auth.ts          POST /register, /login | GET /me
        ├── users.ts         PUT /me
        └── products.ts      CRUD + /like toggle + /status
```

---

## Troubleshooting

| Symptom                                          | Fix                                                                 |
| ------------------------------------------------ | ------------------------------------------------------------------- |
| `Error: D1_ERROR: no such table: users`          | Run `npx wrangler d1 migrations apply eggplant-db --remote`.        |
| `401 Missing token` on WebSocket                 | Client must append `?token=<jwt>` to `/socket`. This is automatic in `ChatService`. |
| Images 404 on `/uploads/<key>`                   | Either the R2 bucket is empty, or `PUBLIC_UPLOAD_URL` is wrong. Check R2 object list in dashboard. |
| `nameserver not found` when creating the zone    | Domain not yet transferred to Cloudflare nameservers — wait and retry. |
| Workers deploy fails with `class_name mismatch`  | Don't remove the `new_sqlite_classes = ["ChatHub"]` migration — DO classes need exactly one create migration. |

---

## Free-tier limits (more than enough for a personal app)

- Workers: 100k requests/day
- D1      : 5 GB storage, 25M reads/day, 50k writes/day
- R2      : 10 GB storage, 1M Class A ops/month, 10M Class B ops/month, **zero egress fees**
- Durable Objects: 400k requests/day, 1 GB storage
