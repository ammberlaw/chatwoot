# wintouch-wa-bridge

Lightweight Baileys bridge that lets Wintouch CRM agents bind their **personal WhatsApp number**
(WhatsApp Web protocol) alongside the official Cloud API channel.

A single Node process manages many sessions (one per Chatwoot inbox). Auth state is persisted to
disk, so sessions survive restarts. **No extra database or Redis** — all customer data and message
history live in Chatwoot's own DB, so unbinding an agent keeps the history.

## How it fits

```
customer WhatsApp  <──►  Baileys (this bridge)  ──POST /webhooks/whatsapp_web──►  Chatwoot
                                    ▲                                                  │
                                    └──────  POST /sessions/:inboxId/send  ◄───────────┘
```

- **Inbound**: bridge receives a message → POSTs to Chatwoot's `whatsapp_web` webhook →
  Chatwoot builds contact + conversation + message via the normal WhatsApp builders.
- **Outbound**: agent replies in Chatwoot → `SendOnWhatsappWebService` → `POST /sessions/:id/send`.
- **Binding**: the CRM "我的 WhatsApp" page calls `connect` and polls `status` to show the QR code.

## Endpoints (all require `X-Bridge-Token`)

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/health` | liveness (no auth) |
| POST | `/sessions/:inboxId/connect` | start/resume a session, returns `{status, qr}` |
| GET | `/sessions/:inboxId/status` | current `{status, qr, phoneNumber}` |
| POST | `/sessions/:inboxId/logout` | unlink + clear creds |
| POST | `/sessions/:inboxId/send` | body `{phone, text}` → send a text |

`status` is one of `connecting | qr | open | close | disconnected`.

## Run locally

```bash
cd wa-bridge
cp .env.example .env   # set BRIDGE_TOKEN + CHATWOOT_URL
npm install
npm start
```

Set the matching env on the Rails side:

```
WHATSAPP_BRIDGE_URL=http://localhost:3025
WHATSAPP_BRIDGE_TOKEN=<same as BRIDGE_TOKEN>
```

## Notes / scope

- Milestone 1 handles **individual text chats only**. Groups (`@g.us`) and media are skipped for now.
- Keep `AUTH_DIR` on a persistent volume in production.
