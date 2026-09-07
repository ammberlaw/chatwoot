const express = require('express');
const pino = require('pino');

const config = require('./config');
const sessions = require('./sessions');

const logger = pino({ level: process.env.LOG_LEVEL || 'info' });
const app = express();
app.use(express.json());

// Every control endpoint requires the shared bridge token.
app.use((req, res, next) => {
  if (req.path === '/health') return next();
  const token = req.get('X-Bridge-Token');
  if (!config.bridgeToken || token !== config.bridgeToken) {
    return res.status(401).json({ error: 'unauthorized' });
  }
  return next();
});

app.get('/health', (req, res) => res.json({ ok: true, sessions: sessions.sessions.size }));

// Start/resume a session and return its current state (status + qr data url if pending scan).
app.post('/sessions/:inboxId/connect', async (req, res) => {
  try {
    const state = await sessions.connect(req.params.inboxId);
    res.json(state);
  } catch (err) {
    logger.error({ err: err.message }, 'connect failed');
    res.status(500).json({ error: err.message });
  }
});

app.get('/sessions/:inboxId/status', (req, res) => {
  res.json(sessions.publicState(req.params.inboxId));
});

app.post('/sessions/:inboxId/logout', async (req, res) => {
  try {
    const state = await sessions.logout(req.params.inboxId);
    res.json(state);
  } catch (err) {
    logger.error({ err: err.message }, 'logout failed');
    res.status(500).json({ error: err.message });
  }
});

// Send an outgoing text. Called by Chatwoot's SendOnWhatsappWebService.
app.post('/sessions/:inboxId/send', async (req, res) => {
  const { phone, text } = req.body || {};
  if (!phone || !text) return res.status(422).json({ error: 'phone and text are required' });
  try {
    const messageId = await sessions.sendText(req.params.inboxId, String(phone), String(text));
    res.json({ message_id: messageId });
  } catch (err) {
    logger.error({ err: err.message }, 'send failed');
    res.status(500).json({ error: err.message });
  }
});

app.listen(config.port, () => {
  logger.info({ port: config.port }, 'wintouch-wa-bridge listening');
  sessions.restoreAll().catch(err => logger.error({ err: err.message }, 'restoreAll failed'));
});
