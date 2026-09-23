const fs = require('fs');
const path = require('path');
const {
  default: makeWASocket,
  useMultiFileAuthState,
  fetchLatestBaileysVersion,
  DisconnectReason,
  downloadMediaMessage,
} = require('@whiskeysockets/baileys');
const { Boom } = require('@hapi/boom');
const QRCode = require('qrcode');
const pino = require('pino');

const config = require('./config');
const chatwoot = require('./chatwoot');

// 配对时要拉全量历史的收件箱白名单（逗号分隔的 inbox id）。空 = 谁都不拉。
const HISTORY_INBOXES = String(process.env.SYNC_HISTORY_INBOXES || '')
  .split(',')
  .map(x => x.trim())
  .filter(Boolean);

const logger = pino({ level: process.env.LOG_LEVEL || 'info' });

// In-memory registry of live sessions, keyed by Chatwoot inbox id.
// { sock, status, qr, phoneNumber, lastError, connecting }
const sessions = new Map();

const INDIVIDUAL_SUFFIX = '@s.whatsapp.net';
const LID_SUFFIX = '@lid';
const GROUP_SUFFIX = '@g.us';

function sessionDir(inboxId) {
  return path.join(config.authDir, String(inboxId));
}

function publicState(inboxId) {
  const s = sessions.get(inboxId);
  if (!s) return { status: 'disconnected', qr: null, phoneNumber: null };
  return {
    status: s.status,
    qr: s.status === 'qr' ? s.qr : null,
    phoneNumber: s.phoneNumber || null,
    lastError: s.lastError || null,
  };
}

// Extract the plain phone digits from a Baileys JID (e.g. "8613800000000:12@s.whatsapp.net" -> "8613800000000").
function jidToPhone(jid) {
  if (!jid) return null;
  return jid.split('@')[0].split(':')[0];
}

function extractText(message) {
  if (!message) return '';
  return (
    message.conversation ||
    message.extendedTextMessage?.text ||
    message.imageMessage?.caption ||
    message.videoMessage?.caption ||
    message.documentMessage?.caption ||
    ''
  );
}

// 入站媒体：客户发来的图片/视频/语音/文件。WhatsApp 的媒体是加密的，
// 必须由桥用消息里的密钥解密下载，Chatwoot 拿不到原始 URL 自己下。
//
// 贴纸(sticker)按图片收；产品/位置/名片这类结构化消息不在此列，仍按无媒体处理。
const MEDIA_KINDS = [
  ['imageMessage', 'image', 'jpg'],
  ['videoMessage', 'video', 'mp4'],
  ['audioMessage', 'audio', 'ogg'],
  ['documentMessage', 'document', 'bin'],
  ['stickerMessage', 'image', 'webp'],
];

// 取出这条消息里的媒体节点。documentWithCaptionMessage 是「文件+说明」的包装，
// 真正的 documentMessage 藏在里面一层，不拆就会漏掉带说明的文件。
function extractMedia(message) {
  if (!message) return null;
  const inner = message.documentWithCaptionMessage?.message || message;
  for (const [key, kind, ext] of MEDIA_KINDS) {
    const node = inner[key];
    if (!node) continue;
    const mimetype = node.mimetype || '';
    const filename =
      node.fileName ||
      `whatsapp-${kind}-${Date.now()}.${(mimetype.split('/')[1] || ext).split(';')[0]}`;
    return { kind, node, mimetype: mimetype || 'application/octet-stream', filename, key };
  }
  return null;
}

// 下载并解密。失败不让整条消息丢掉——宁可只落文字（或一条空消息占位），
// 也好过客户发来的东西在 CRM 里彻底不存在。
async function downloadMedia(sock, msg, media) {
  const declared = Number(media.node.fileLength || 0);
  if (declared > MEDIA_MAX_BYTES) {
    logger.warn({ size: declared, kind: media.kind }, 'inbound media too large, skipped');
    return null;
  }
  const buffer = await downloadMediaMessage(
    msg,
    'buffer',
    {},
    { logger, reuploadRequest: sock.updateMediaMessage },
  );
  if (!buffer || !buffer.length) return null;
  if (buffer.length > MEDIA_MAX_BYTES) {
    logger.warn({ size: buffer.length, kind: media.kind }, 'inbound media too large after download, skipped');
    return null;
  }
  return buffer;
}

async function handleIncoming(inboxId, msg, sock) {
  // 个人聊天的文字消息，双向都收。之前这里 `if (fromMe) return` 把业务员用手机回的话
  // 全丢了，CRM 里的对话只剩客户单边说 —— 实测线上一个号 221 条来件只对 2 条去件。
  // 从 CRM 发出的那条会由桥回写 source_id，入库时按 message_id 判重，不会重复。
  const fromMe = Boolean(msg.key.fromMe);
  const remoteJid = msg.key.remoteJid || '';
  if (remoteJid === 'status@broadcast') return;
  if (remoteJid.endsWith(GROUP_SUFFIX) || remoteJid.endsWith('@newsletter')) return; // groups/channels handled later
  // Accept both classic (…@s.whatsapp.net) and WhatsApp's newer LID addressing (…@lid).
  if (!remoteJid.endsWith(INDIVIDUAL_SUFFIX) && !remoteJid.endsWith(LID_SUFFIX)) return;

  const text = extractText(msg.message);
  const media = extractMedia(msg.message);
  // 纯文字、纯媒体、图片带文字三种都要收。以前这里是 `if (!text) return`，
  // 客户发来的图片/视频/语音/文件在 CRM 里直接不存在（业务员只能去手机上翻）。
  if (!text && !media) return;

  // Route by the full JID: WhatsApp Web addresses chats by JID, which may be a classic
  // phone (…@s.whatsapp.net) or the newer opaque LID (…@lid). We reply to this same JID.
  // The real phone number is only known for classic JIDs (or via senderPn on LID messages);
  // when unknown we leave it blank rather than storing the opaque LID as a fake number.
  const realPhone = remoteJid.endsWith(INDIVIDUAL_SUFFIX)
    ? jidToPhone(remoteJid)
    : msg.key.senderPn
      ? jidToPhone(msg.key.senderPn)
      : null;

  const payload = {
    inbox_id: Number(inboxId),
    source_id: remoteJid,
    phone: realPhone,
    // 自己发出的消息里 pushName 是「我」的名字，拿它当客户名会把联系人建错，
    // 所以只在收到客户消息时带 name；已有联系人不受影响。
    name: fromMe ? null : msg.pushName || realPhone || jidToPhone(remoteJid),
    text,
    message_id: msg.key.id,
    timestamp: Number(msg.messageTimestamp) || null,
    from_me: fromMe,
  };

  try {
    // 媒体下载失败（密钥过期/服务器已清理）不吞掉整条消息：退回纯文字投递，
    // 至少 CRM 里能看到「客户这时候发过东西」和它的文字说明。
    let buffer = null;
    if (media) {
      try {
        buffer = await downloadMedia(sock, msg, media);
      } catch (err) {
        logger.error({ inboxId, kind: media.kind, err: err.message }, 'inbound media download failed');
      }
    }
    if (buffer) {
      await chatwoot.postInboundMedia(payload, {
        buffer,
        filename: media.filename,
        mimetype: media.mimetype,
      });
    } else {
      await chatwoot.postInbound(payload);
    }
  } catch (err) {
    logger.error({ inboxId, err: err.message }, 'failed to forward inbound message');
  }
}


async function notifyStatus(inboxId) {
  const s = sessions.get(inboxId);
  if (!s) return;
  try {
    await chatwoot.postStatus({
      inbox_id: Number(inboxId),
      status: s.status,
      phone_number: s.phoneNumber || null,
    });
  } catch (err) {
    logger.warn({ inboxId, err: err.message }, 'failed to report status to chatwoot');
  }
}

// Start (or restart) a Baileys socket for an inbox. Safe to call repeatedly.
async function connect(inboxId) {
  const existing = sessions.get(inboxId);
  if (existing && (existing.status === 'open' || existing.connecting)) {
    return publicState(inboxId);
  }

  const dir = sessionDir(inboxId);
  fs.mkdirSync(dir, { recursive: true });
  const { state, saveCreds } = await useMultiFileAuthState(dir);
  const { version } = await fetchLatestBaileysVersion();

  const sock = makeWASocket({
    version,
    auth: state,
    logger: pino({ level: 'silent' }),
    browser: [config.browserName, 'Chrome', '1.0.0'],
    // 历史同步只在「配对那一刻」由 WhatsApp 推送，事后 fetchMessageHistory 要不到
    // （实测请求被接受但无响应）。所以要历史就必须在配对时开着这个开关。
    // 按收件箱控制：SYNC_HISTORY_INBOXES 是逗号分隔的 inbox id 白名单，
    // 没列进去的号照旧不拉历史，免得别人重连时白拖一大坨数据。
    syncFullHistory: HISTORY_INBOXES.includes(String(inboxId)),
    markOnlineOnConnect: false,
  });

  const session = { sock, status: 'connecting', qr: null, phoneNumber: null, lastError: null, connecting: true };
  sessions.set(inboxId, session);

  sock.ev.on('creds.update', saveCreds);

  sock.ev.on('connection.update', async update => {
    const { connection, lastDisconnect, qr } = update;

    if (qr) {
      session.status = 'qr';
      session.qr = await QRCode.toDataURL(qr);
      logger.info({ inboxId }, 'qr generated');
      notifyStatus(inboxId);
    }

    if (connection === 'open') {
      session.status = 'open';
      session.qr = null;
      session.connecting = false;
      session.phoneNumber = jidToPhone(sock.user?.id);
      logger.info({ inboxId, phone: session.phoneNumber }, 'session open');
      notifyStatus(inboxId);
    }

    if (connection === 'close') {
      session.connecting = false;
      const statusCode = new Boom(lastDisconnect?.error)?.output?.statusCode;
      session.lastError = lastDisconnect?.error?.message || null;

      if (statusCode === DisconnectReason.loggedOut) {
        // Customer/agent unlinked the device (or we logged out). Drop creds; require a fresh scan.
        session.status = 'disconnected';
        sessions.delete(inboxId);
        fs.rmSync(dir, { recursive: true, force: true });
        logger.info({ inboxId }, 'logged out, session cleared');
        notifyStatus(inboxId);
        return;
      }

      // Transient drop — reconnect automatically.
      session.status = 'close';
      logger.warn({ inboxId, statusCode }, 'connection closed, reconnecting');
      notifyStatus(inboxId);
      setTimeout(() => connect(inboxId).catch(err => logger.error({ inboxId, err: err.message }, 'reconnect failed')), 3000);
    }
  });


  // === HISTORY PROBE（验证用，不入库）===
  // WhatsApp 是端到端加密、消息只在手机上，历史其实是向已配对的手机请求的。
  // 这里把推来的批次统计后落盘，供评估「能拉回多少、媒体丢多少、时间范围多大」。
  sock.ev.on('messaging-history.set', async ev => {
    try {
      const msgs = ev.messages || [];
      const stamps = msgs.map(m => Number(m.messageTimestamp) || 0).filter(Boolean);
      const kinds = {};
      let withMedia = 0;
      for (const m of msgs) {
        const k = Object.keys(m.message || {})[0] || 'empty';
        kinds[k] = (kinds[k] || 0) + 1;
        if (/image|video|document|audio|sticker/i.test(k)) withMedia += 1;
      }
      const summary = {
        at: new Date().toISOString(),
        inboxId,
        syncType: ev.syncType,
        isLatest: ev.isLatest,
        progress: ev.progress,
        chats: (ev.chats || []).length,
        contacts: (ev.contacts || []).length,
        messages: msgs.length,
        namesFound: (ev.contacts || []).filter(c => c.name || c.notify).length,
        fromMe: msgs.filter(m => m.key?.fromMe).length,
        withMedia,
        kinds,
        oldest: stamps.length ? new Date(Math.min(...stamps) * 1000).toISOString() : null,
        newest: stamps.length ? new Date(Math.max(...stamps) * 1000).toISOString() : null,
      };
      logger.info(summary, 'HISTORY batch');
      fs.appendFileSync('/tmp/wa-history-probe.jsonl', JSON.stringify(summary) + '\n');
      await shipHistory(inboxId, msgs, nameByJid(ev));
    } catch (err) {
      logger.error({ inboxId, err: err.message }, 'HISTORY PROBE failed');
    }
  });

  sock.ev.on('messages.upsert', async ({ messages, type }) => {
    if (type !== 'notify') return;
    for (const msg of messages) {
      await handleIncoming(inboxId, msg, sock);
    }
  });

  // Delivery/read receipts for our own outgoing messages. Baileys reports the WhatsApp
  // message status enum: 3 = delivered, 4 = read, 5 = played (treat as read).
  sock.ev.on('messages.update', async updates => {
    for (const u of updates) {
      if (u.key?.fromMe !== true) continue;
      const status = u.update?.status;
      const mapped = status === 3 ? 'delivered' : status >= 4 ? 'read' : null;
      if (!mapped || !u.key?.id) continue;
      try {
        await chatwoot.postReceipt({ inbox_id: Number(inboxId), message_id: u.key.id, status: mapped });
      } catch (err) {
        logger.warn({ inboxId, err: err.message }, 'failed to forward receipt');
      }
    }
  });

  return publicState(inboxId);
}

async function sendText(inboxId, to, text) {
  const session = sessions.get(inboxId);
  if (!session || session.status !== 'open') {
    throw new Error(`session for inbox ${inboxId} is not connected`);
  }
  // `to` is the conversation's source_id: either a full JID (…@lid / …@s.whatsapp.net)
  // or a bare phone number (legacy). Send to the JID as-is; append the classic suffix otherwise.
  const jid = String(to).includes('@') ? String(to) : `${to}${INDIVIDUAL_SUFFIX}`;
  const sent = await session.sock.sendMessage(jid, { text });
  return sent?.key?.id || null;
}

// Send an outgoing file. Chatwoot passes the attachment's public URL; we fetch it here
// (the blob URL redirects to object storage, so redirects must be followed) and push the
// bytes through Baileys. Images go as `image` so they preview inline in WhatsApp; anything
// else goes as `document` so the customer sees the real filename.
const MEDIA_MAX_BYTES = 64 * 1024 * 1024;

async function sendMedia(inboxId, to, { url, filename, mimetype, caption }) {
  const session = sessions.get(inboxId);
  if (!session || session.status !== 'open') {
    throw new Error(`session for inbox ${inboxId} is not connected`);
  }
  const res = await fetch(url, { redirect: 'follow' });
  if (!res.ok) throw new Error(`fetch attachment failed: HTTP ${res.status}`);
  const buffer = Buffer.from(await res.arrayBuffer());
  if (buffer.length > MEDIA_MAX_BYTES) throw new Error(`attachment too large: ${buffer.length} bytes`);

  const type = String(mimetype || res.headers.get('content-type') || 'application/octet-stream');
  const jid = String(to).includes('@') ? String(to) : `${to}${INDIVIDUAL_SUFFIX}`;
  const payload = type.startsWith('image/')
    ? { image: buffer, mimetype: type, caption: caption || undefined }
    : { document: buffer, mimetype: type, fileName: filename || 'file', caption: caption || undefined };
  const sent = await session.sock.sendMessage(jid, payload);
  return sent?.key?.id || null;
}

// 按需向手机请求更早的历史（HISTORY PROBE 验证用）。
// oldestMsgKey 必须是该会话里我们已知的「最早那条」，WhatsApp 从它往前给 count 条。
async function fetchHistory(inboxId, { count, remoteJid, oldestMsgId, oldestMsgTimestamp, fromMe }) {
  const session = sessions.get(inboxId);
  if (!session || session.status !== 'open') {
    throw new Error(`session for inbox ${inboxId} is not connected`);
  }
  const key = { remoteJid, id: oldestMsgId, fromMe: Boolean(fromMe) };
  const reqId = await session.sock.fetchMessageHistory(Number(count), key, Number(oldestMsgTimestamp));
  return reqId;
}

// 历史批次里 WhatsApp 会连联系人名单一起推（contacts / chats 两个数组）。
// 不用它的话，凡是「自己先发话」的会话，落库时拿不到对方名字，联系人就只剩一串 JID 数字。
function nameByJid(ev) {
  const map = new Map();
  for (const c of ev.contacts || []) {
    const n = c.name || c.notify || c.verifiedName;
    if (c.id && n) map.set(c.id, n);
  }
  for (const c of ev.chats || []) {
    if (c.id && c.name && !map.has(c.id)) map.set(c.id, c.name);
  }
  return map;
}

// 历史消息分批投给 Chatwoot。一个号能推一万条，一次性砸过去会把 Rails 打满，
// 所以切成小批、批间让一让。只发文字消息——历史里的媒体在 WhatsApp 服务器上多已过期。
const HISTORY_BATCH = 200;

async function shipHistory(inboxId, msgs, names = new Map()) {
  const rows = [];
  for (const m of msgs) {
    const jid = m.key?.remoteJid || '';
    if (jid === 'status@broadcast') continue;
    if (jid.endsWith(GROUP_SUFFIX) || jid.endsWith('@newsletter')) continue;
    if (!jid.endsWith(INDIVIDUAL_SUFFIX) && !jid.endsWith(LID_SUFFIX)) continue;
    const text = extractText(m.message);
    if (!text) continue;
    const fromMe = Boolean(m.key.fromMe);
    const phone = jid.endsWith(INDIVIDUAL_SUFFIX)
      ? jidToPhone(jid)
      : m.key.senderPn
        ? jidToPhone(m.key.senderPn)
        : null;
    rows.push({
      source_id: jid,
      phone,
      // 名字来源按可靠性排：历史名单（按 LID 查，查不到再按 senderPn 手机号 JID 查，
      // LID 会话在名单里常按手机号登记）→ 这条消息的 pushName（自己发的那条里是「我」，不能用）
      // → 手机号。全都没有就留空，让 Chatwoot 用 JID 兜底，至少不会把「我」写成客户名。
      name:
        names.get(jid) ||
        (m.key.senderPn ? names.get(m.key.senderPn) : null) ||
        (fromMe ? null : m.pushName) ||
        phone ||
        null,
      text,
      message_id: m.key.id,
      timestamp: Number(m.messageTimestamp) || null,
      from_me: fromMe,
    });
  }
  for (let i = 0; i < rows.length; i += HISTORY_BATCH) {
    try {
      await chatwoot.postHistory({ inbox_id: Number(inboxId), messages: rows.slice(i, i + HISTORY_BATCH) });
    } catch (err) {
      logger.error({ inboxId, err: err.message }, 'history batch failed');
    }
    await new Promise(r => setTimeout(r, 300));
  }
  logger.info({ inboxId, shipped: rows.length }, 'history shipped');
}

// 号码是否注册了 WhatsApp。手机上「直接输号码就能聊」靠的就是这个查询：
// 号没注册的话发过去是石沉大海，先问清楚再建会话，别让业务对着空气发消息。
// 返回注册用的 JID——有些号回来的 JID 和输入的号码不同（携号转网/LID），要用它发消息。
async function checkNumber(inboxId, phone) {
  const session = sessions.get(inboxId);
  if (!session || session.status !== 'open') {
    throw new Error(`session for inbox ${inboxId} is not connected`);
  }
  const digits = String(phone).replace(/\D/g, '');
  if (!digits) throw new Error('phone is required');
  const [hit] = await session.sock.onWhatsApp(`${digits}${INDIVIDUAL_SUFFIX}`);
  return { exists: Boolean(hit?.exists), jid: hit?.jid || null, phone: digits };
}

async function logout(inboxId) {
  const session = sessions.get(inboxId);
  if (session?.sock) {
    try {
      await session.sock.logout();
    } catch (err) {
      logger.warn({ inboxId, err: err.message }, 'logout call failed, clearing anyway');
    }
  }
  sessions.delete(inboxId);
  fs.rmSync(sessionDir(inboxId), { recursive: true, force: true });
  notifyStatus(inboxId);
  return { status: 'disconnected' };
}

// Re-attach to any sessions that already have persisted creds (survives bridge restarts).
async function restoreAll() {
  if (!fs.existsSync(config.authDir)) return;
  const dirs = fs.readdirSync(config.authDir, { withFileTypes: true }).filter(d => d.isDirectory());
  for (const d of dirs) {
    logger.info({ inboxId: d.name }, 'restoring session');
    connect(d.name).catch(err => logger.error({ inboxId: d.name, err: err.message }, 'restore failed'));
  }
}

module.exports = { connect, sendText, sendMedia, fetchHistory, checkNumber, logout, restoreAll, publicState, sessions };
