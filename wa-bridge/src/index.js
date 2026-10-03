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

// Send an outgoing attachment. Called by Chatwoot's SendOnWhatsappWebService.
app.post('/sessions/:inboxId/send-media', async (req, res) => {
  const { phone, url, filename, mimetype, caption } = req.body || {};
  if (!phone || !url) return res.status(422).json({ error: 'phone and url are required' });
  try {
    const messageId = await sessions.sendMedia(req.params.inboxId, String(phone), {
      url: String(url), filename, mimetype, caption,
    });
    res.json({ message_id: messageId });
  } catch (err) {
    logger.error({ err: err.message }, 'send-media failed');
    res.status(500).json({ error: err.message });
  }
});

// 按需拉历史（HISTORY PROBE 验证用）。返回 WhatsApp 的请求 id；
// 实际数据异步经 messaging-history.set 推回，统计写 /tmp/wa-history-probe.jsonl。
app.post('/sessions/:inboxId/fetch-history', async (req, res) => {
  const { count, remoteJid, oldestMsgId, oldestMsgTimestamp, fromMe } = req.body || {};
  if (!remoteJid || !oldestMsgId || !oldestMsgTimestamp) {
    return res.status(422).json({ error: 'remoteJid, oldestMsgId and oldestMsgTimestamp are required' });
  }
  try {
    const requestId = await sessions.fetchHistory(req.params.inboxId, {
      count: count || 50, remoteJid, oldestMsgId, oldestMsgTimestamp, fromMe,
    });
    res.json({ request_id: requestId });
  } catch (err) {
    logger.error({ err: err.message }, 'fetch-history failed');
    res.status(500).json({ error: err.message });
  }
});

// 查号码是否注册了 WhatsApp（发起新会话前用）。
app.post('/sessions/:inboxId/check-number', async (req, res) => {
  const { phone } = req.body || {};
  if (!phone) return res.status(422).json({ error: 'phone is required' });
  try {
    res.json(await sessions.checkNumber(req.params.inboxId, phone));
  } catch (err) {
    logger.error({ err: err.message }, 'check-number failed');
    res.status(500).json({ error: err.message });
  }
});

// 主动重拉通讯录（存量备注名回填用）。恢复会话时 WhatsApp 不会主动再推一次。
app.post('/sessions/:inboxId/resync-contacts', async (req, res) => {
  try {
    res.json(await sessions.resyncContacts(req.params.inboxId, (req.body || {}).collections));
  } catch (err) {
    logger.error({ err: err.message }, 'resync-contacts failed');
    res.status(500).json({ error: err.message });
  }
});

// 存量联系人头像回填：CRM 把它手上的 JID 列表交过来，桥按节流队列逐个取头像回传。
// 日常新联系人不走这里（发消息时自动取），这个口子是为「上线时把老联系人补齐」留的。
app.post('/sessions/:inboxId/sync-avatars', (req, res) => {
  const { jids } = req.body || {};
  if (!Array.isArray(jids) || !jids.length) return res.status(422).json({ error: 'jids is required' });
  try {
    res.json(sessions.syncAvatars(req.params.inboxId, jids));
  } catch (err) {
    logger.error({ err: err.message }, 'sync-avatars failed');
    res.status(500).json({ error: err.message });
  }
});

app.listen(config.port, () => {
  logger.info({ port: config.port }, 'wintouch-wa-bridge listening');
  sessions.restoreAll().catch(err => logger.error({ err: err.message }, 'restoreAll failed'));
});
