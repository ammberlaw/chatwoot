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

// 批量会话状态：Chatwoot 的「我的 WhatsApp」列表一次问全部，不用逐个号发请求。
// 列表原来读的是库里存的状态，桥接这边掉线了它不知道，于是界面一直显示「已连接」。
app.get('/sessions', (req, res) => {
  const out = {};
  for (const id of sessions.sessions.keys()) out[String(id)] = sessions.publicState(id).status;
  res.json({ sessions: out });
});

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
  // quoted：引用回复用。Chatwoot 传被引用消息的 WhatsApp id、是不是我方发的、以及摘要正文；
  // 不传就按原来的普通消息发。
  const { phone, text, quoted } = req.body || {};
  if (!phone || !text) return res.status(422).json({ error: 'phone and text are required' });
  try {
    const messageId = await sessions.sendText(req.params.inboxId, String(phone), String(text), quoted);
    res.json({ message_id: messageId });
  } catch (err) {
    logger.error({ err: err.message }, 'send failed');
    res.status(500).json({ error: err.message });
  }
});

// Send an outgoing attachment. Called by Chatwoot's SendOnWhatsappWebService.
app.post('/sessions/:inboxId/reaction', async (req, res) => {
  // 表情回应：emoji 为空字符串即撤销。target_id 是被回应那条的 WhatsApp 消息 id。
  const { phone, target_id: targetId, from_me: fromMe, emoji } = req.body || {};
  if (!phone || !targetId) return res.status(400).json({ error: 'phone and target_id required' });
  try {
    const messageId = await sessions.sendReaction(req.params.inboxId, String(phone), {
      targetId: String(targetId), fromMe: Boolean(fromMe), emoji: String(emoji || ''),
    });
    return res.json({ message_id: messageId });
  } catch (err) {
    return res.status(502).json({ error: err.message });
  }
});

app.post('/sessions/:inboxId/send-media', async (req, res) => {
  const { phone, url, filename, mimetype, caption, quoted } = req.body || {};
  if (!phone || !url) return res.status(422).json({ error: 'phone and url are required' });
  try {
    const messageId = await sessions.sendMedia(req.params.inboxId, String(phone), {
      url: String(url), filename, mimetype, caption, quoted,
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

// 撤回一条我方发出的消息（WhatsApp 的「为所有人删除」）。
// 时间窗和「只能撤自己发的」都在 Chatwoot 侧校验过了，这里只负责发出去。
app.post('/sessions/:inboxId/revoke', async (req, res) => {
  const { phone, target_id: targetId } = req.body || {};
  if (!phone || !targetId) return res.status(422).json({ error: 'phone and target_id are required' });
  try {
    const messageId = await sessions.revokeMessage(req.params.inboxId, String(phone), { targetId });
    res.json({ message_id: messageId });
  } catch (err) {
    logger.error({ err: err.message }, 'revoke failed');
    res.status(500).json({ error: err.message });
  }
});

// 编辑一条我方发出的消息（WhatsApp 限 15 分钟内，同样在 Chatwoot 侧卡过）。
app.post('/sessions/:inboxId/edit', async (req, res) => {
  const { phone, target_id: targetId, text } = req.body || {};
  if (!phone || !targetId || !text) {
    return res.status(422).json({ error: 'phone, target_id and text are required' });
  }
  try {
    const messageId = await sessions.editMessage(req.params.inboxId, String(phone), { targetId, text });
    res.json({ message_id: messageId });
  } catch (err) {
    logger.error({ err: err.message }, 'edit failed');
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
