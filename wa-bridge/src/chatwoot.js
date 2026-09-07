const config = require('./config');

// Posts an inbound WhatsApp message into Chatwoot's whatsapp_web webhook.
// Chatwoot turns it into a contact + conversation + message via the normal builders.
async function postInbound(payload) {
  const res = await fetch(`${config.chatwootUrl}/webhooks/whatsapp_web`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Bridge-Token': config.bridgeToken,
    },
    body: JSON.stringify(payload),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`chatwoot inbound ${res.status}: ${body.slice(0, 300)}`);
  }
}

// Reports a session's connection state (open/close/qr + phone number) back to Chatwoot
// so it can persist phone_number and surface status without polling the bridge for it.
async function postStatus(payload) {
  const res = await fetch(`${config.chatwootUrl}/webhooks/whatsapp_web/status`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Bridge-Token': config.bridgeToken,
    },
    body: JSON.stringify(payload),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`chatwoot status ${res.status}: ${body.slice(0, 300)}`);
  }
}

// Reports a delivery/read receipt for one of our outgoing messages so Chatwoot can
// advance its status (sent → delivered → read) and render the WhatsApp-style ticks.
async function postReceipt(payload) {
  const res = await fetch(`${config.chatwootUrl}/webhooks/whatsapp_web/receipt`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Bridge-Token': config.bridgeToken,
    },
    body: JSON.stringify(payload),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`chatwoot receipt ${res.status}: ${body.slice(0, 300)}`);
  }
}

module.exports = { postInbound, postStatus, postReceipt };
