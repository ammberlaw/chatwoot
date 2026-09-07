const path = require('path');

// All bridge config comes from the environment so the same image runs in dev/prod.
module.exports = {
  port: Number(process.env.PORT || 3025),
  // Shared secret. Chatwoot sends it on every call; the bridge sends it back on inbound webhooks.
  bridgeToken: process.env.BRIDGE_TOKEN || '',
  // Where Baileys auth state (creds/keys) is persisted, one folder per inbox.
  authDir: process.env.AUTH_DIR || path.join(__dirname, '..', 'sessions'),
  // Chatwoot base URL the bridge posts inbound messages to (e.g. http://localhost:3000).
  chatwootUrl: (process.env.CHATWOOT_URL || 'http://localhost:3000').replace(/\/$/, ''),
  // Browser label shown in the customer's WhatsApp "linked devices" list.
  browserName: process.env.BRIDGE_BROWSER_NAME || 'Wintouch CRM',
};
