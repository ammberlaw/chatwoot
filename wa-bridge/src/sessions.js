const crypto = require('crypto');
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
// { sock, status, qr, phoneNumber, lastError, connecting,
//   nameBook, avatarState, avatarQueue, avatarBusy }
const sessions = new Map();

// 头像取回节流。取头像是要向 WhatsApp 发请求的（不像名字是人家主动推过来的），
// 一口气给整本通讯录取一遍很容易被当成自动化行为限流，个人号经不起。
// 所以：只给「真的在聊天的人」取，取过的 7 天内不再取，队列串行且每次之间歇一下。
const AVATAR_GAP_MS = 1500;
const AVATAR_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const AVATAR_MAX_BYTES = 2 * 1024 * 1024;
// 队列封顶。重连做状态同步时 contacts.update 可能一口气推来很多条，没有这道闸就会
// 排出几百个取头像请求。超出的直接丢（下次这人发消息时自然会补上）。
const AVATAR_QUEUE_MAX = 60;
// 单个头像的硬超时。Baileys 的 profilePictureUrl 和图片下载都可能一直挂着不返回，
// 没有这道闸一个坏 JID 就能把整条队列永久卡死（avatarBusy 再也清不掉）。
const AVATAR_STEP_TIMEOUT_MS = 15000;
// 联系人名单一批可能是整本通讯录，切批发，别把 Chatwoot 的 webhook 打满。
const CONTACT_BATCH = 200;

const sleep = ms => new Promise(r => setTimeout(r, ms));

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

  const session = sessions.get(inboxId);
  const payload = {
    inbox_id: Number(inboxId),
    source_id: remoteJid,
    phone: realPhone,
    // 自己发出的消息里 pushName 是「我」的名字，拿它当客户名会把联系人建错，
    // 所以只在收到客户消息时带 name；已有联系人不受影响。
    name: fromMe ? null : msg.pushName || realPhone || jidToPhone(remoteJid),
    // 业务员手机通讯录里存的备注名（从联系人名单缓存里取）。业务认的是这个名字，
    // 比对方自设的昵称可靠，Chatwoot 侧优先用它。自己发的消息也照样带——
    // 备注名是「我对他的称呼」，跟这条消息谁发的无关。
    book_name: session ? session.nameBook.get(remoteJid) || (msg.key.senderPn ? session.nameBook.get(msg.key.senderPn) : null) || null : null,
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
    // 真的在聊的人才取头像（7 天冷却），这样请求量跟着实际会话走，不会突然一大片。
    queueAvatar(inboxId, remoteJid);
  } catch (err) {
    logger.error({ inboxId, err: err.message }, 'failed to forward inbound message');
  }
}


function isIndividualJid(jid) {
  const v = String(jid || '');
  if (!v || v === 'status@broadcast') return false;
  if (v.endsWith(GROUP_SUFFIX) || v.endsWith('@newsletter')) return false;
  return v.endsWith(INDIVIDUAL_SUFFIX) || v.endsWith(LID_SUFFIX);
}

// 转发联系人资料。Baileys 的 contact.name 是「我自己手机通讯录里存的备注名」，
// contact.notify 才是「对方自己设的昵称」——两个都给 Chatwoot，那边按可靠性决定用哪个。
//
// allowAvatar：只有 contacts.update（手机上改了头像/备注，增量、量很小）才顺手取头像。
// contacts.upsert 在配对同步时会一次推来整本通讯录，跟着取头像等于几百上千个请求，不能干。
async function handleContacts(inboxId, list, { allowAvatar = false } = {}) {
  const session = sessions.get(inboxId);
  const rows = [];
  for (const c of list || []) {
    if (!isIndividualJid(c.id)) continue;
    const book = String(c.name || c.verifiedName || '').trim() || null;
    const notify = String(c.notify || '').trim() || null;
    if (session && book) {
      session.nameBook.set(c.id, book);
      if (c.lid) session.nameBook.set(c.lid, book);
    }
    if (allowAvatar && c.imgUrl) queueAvatar(inboxId, c.id, { force: true });
    if (!book && !notify) continue;
    rows.push({
      source_id: c.id,
      lid: c.lid || null,
      phone: c.id.endsWith(INDIVIDUAL_SUFFIX) ? jidToPhone(c.id) : null,
      name: book,
      notify,
    });
  }
  if (!rows.length) {
    logger.info({ inboxId, received: (list || []).length }, 'contacts event carried no usable name');
    return 0;
  }

  for (let i = 0; i < rows.length; i += CONTACT_BATCH) {
    try {
      await chatwoot.postContacts({ inbox_id: Number(inboxId), contacts: rows.slice(i, i + CONTACT_BATCH) });
    } catch (err) {
      logger.error({ inboxId, err: err.message }, 'contacts batch failed');
    }
  }
  logger.info({ inboxId, contacts: rows.length }, 'contacts forwarded');
  return rows.length;
}

// 把一个 JID 排进头像队列。force 用于「头像确实变了」和 CRM 主动回填，绕过 7 天冷却。
function queueAvatar(inboxId, jid, { force = false } = {}) {
  const session = sessions.get(inboxId);
  if (!session || session.status !== 'open' || !isIndividualJid(jid)) return;
  const seen = session.avatarState.get(jid);
  if (!force && seen && Date.now() - seen.at < AVATAR_TTL_MS) return;
  if (session.avatarQueue.includes(jid)) return;
  if (session.avatarQueue.length >= AVATAR_QUEUE_MAX) return;
  session.avatarQueue.push(jid);
  drainAvatars(inboxId).catch(err => logger.warn({ inboxId, err: err.message }, 'avatar drain failed'));
}

// 串行出队，每个之间歇 AVATAR_GAP_MS。同一会话只有一个 drain 在跑。
async function drainAvatars(inboxId) {
  const session = sessions.get(inboxId);
  if (!session || session.avatarBusy) return;
  session.avatarBusy = true;
  try {
    while (session.avatarQueue.length && session.status === 'open') {
      const jid = session.avatarQueue.shift();
      // 再包一层总超时：syncAvatar 内部每步都有超时了，这里兜住任何漏网的挂起。
      // 定时器必须显式清掉——留着的话 45 秒后照样触发，把已经同步好的 hash 抹成 null。
      let timer;
      const timedOut = await Promise.race([
        syncAvatar(inboxId, session, jid).then(() => false),
        new Promise(resolve => {
          timer = setTimeout(() => resolve(true), AVATAR_STEP_TIMEOUT_MS * 3);
        }),
      ]);
      clearTimeout(timer);
      if (timedOut) {
        logger.warn({ inboxId, jid }, 'avatar sync timed out, skipped');
        session.avatarState.set(jid, { hash: null, at: Date.now() });
      }
      await sleep(AVATAR_GAP_MS);
    }
  } finally {
    session.avatarBusy = false;
  }
}

async function syncAvatar(inboxId, session, jid) {
  try {
    // 没设头像 / 对方隐私设置不让看 → profilePictureUrl 抛错或给空。
    // 照样记一笔时间，免得每来一条消息就再问一次。
    const url = await session.sock.profilePictureUrl(jid, 'image', AVATAR_STEP_TIMEOUT_MS).catch(() => null);
    if (!url) {
      session.avatarState.set(jid, { hash: null, at: Date.now() });
      return;
    }
    const res = await fetch(url, { signal: AbortSignal.timeout(AVATAR_STEP_TIMEOUT_MS) });
    if (!res.ok) throw new Error(`profile picture ${res.status}`);
    const buffer = Buffer.from(await res.arrayBuffer());
    if (!buffer.length || buffer.length > AVATAR_MAX_BYTES) {
      session.avatarState.set(jid, { hash: null, at: Date.now() });
      return;
    }
    const hash = crypto.createHash('sha256').update(buffer).digest('hex');
    const prev = session.avatarState.get(jid);
    session.avatarState.set(jid, { hash, at: Date.now() });
    // 图没换就不用再传一遍（Chatwoot 那边也会按 hash 判一次，这里先省掉一次上传）。
    if (prev && prev.hash === hash) return;

    await chatwoot.postAvatar(
      {
        inbox_id: Number(inboxId),
        source_id: jid,
        phone: jid.endsWith(INDIVIDUAL_SUFFIX) ? jidToPhone(jid) : null,
        img_hash: hash,
      },
      {
        buffer,
        mimetype: (res.headers.get('content-type') || 'image/jpeg').split(';')[0],
        filename: 'whatsapp-avatar.jpg',
      },
    );
  } catch (err) {
    logger.warn({ inboxId, jid, err: err.message }, 'avatar sync failed');
  }
}

// 主动把通讯录重新同步一遍。恢复会话时 WhatsApp 不会再推一次通讯录（配对那会儿推过、
// 版本号存在本地了），所以存量联系人的备注名靠等是等不来的。这里强制从头拉一遍
// critical_unblock_low 这个 app-state 集合——联系人名字（contactAction）就在里面，
// Baileys 收到后会按 contacts.upsert 吐出来，走我们已有的那条转发路径。
async function resyncContacts(inboxId, collections) {
  const session = sessions.get(inboxId);
  if (!session || session.status !== 'open') {
    throw new Error(`session for inbox ${inboxId} is not connected`);
  }
  const names = collections && collections.length ? collections : ['critical_unblock_low'];
  logger.info({ inboxId, collections: names }, 'resync app state requested');
  await session.sock.resyncAppState(names, true);
  logger.info({ inboxId }, 'resync app state done');
  return { ok: true, collections: names };
}

// CRM 主动回填：把它手上已有的联系人 JID 交过来补头像（存量联系人一个头像都没有，
// 等他们下次发消息才慢慢补太久）。强制重取，但照样走同一个节流队列。
function syncAvatars(inboxId, jids) {
  const session = sessions.get(inboxId);
  if (!session || session.status !== 'open') {
    throw new Error(`session for inbox ${inboxId} is not connected`);
  }
  const list = (jids || []).filter(isIndividualJid);
  for (const jid of list) queueAvatar(inboxId, jid, { force: true });
  return { queued: list.length, pending: session.avatarQueue.length };
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

  const session = {
    sock,
    status: 'connecting',
    qr: null,
    phoneNumber: null,
    lastError: null,
    connecting: true,
    // jid -> 手机通讯录里的备注名。实时消息本身只带对方自设的昵称，备注名要靠
    // WhatsApp 推来的联系人名单，所以在这里留一份，发消息时一起带给 Chatwoot。
    nameBook: new Map(),
    // jid -> { hash, at }，头像取回的去重与冷却
    avatarState: new Map(),
    avatarQueue: [],
    avatarBusy: false,
  };
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
      // 这一批里连通讯录名单一起推来了（备注名只有这里有）。先转发并灌进 nameBook，
      // 后面的历史消息和之后的实时消息都能带上备注名。重连时也会走这条路，
      // 等于每次重连自动把存量联系人的备注名补一遍。
      await handleContacts(inboxId, ev.contacts);
      await shipHistory(inboxId, msgs, nameByJid(ev), bookByJid(ev));
    } catch (err) {
      logger.error({ inboxId, err: err.message }, 'HISTORY PROBE failed');
    }
  });

  // 联系人名单。upsert 多半是配对/重连时 WhatsApp 推来的整本通讯录（备注名就在这里面），
  // update 是手机上改了备注名或换了头像的增量——只有后者才顺手取头像，见 handleContacts。
  sock.ev.on('contacts.upsert', cs => {
    handleContacts(inboxId, cs).catch(err => logger.warn({ inboxId, err: err.message }, 'contacts.upsert failed'));
  });
  sock.ev.on('contacts.update', cs => {
    handleContacts(inboxId, cs, { allowAvatar: true }).catch(err =>
      logger.warn({ inboxId, err: err.message }, 'contacts.update failed'),
    );
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

// 只认「我自己存的备注名」的那一份（contact.name / chat.name）。nameByJid 是兜底用的
// 混合名单（备注名没有就退到对方昵称），两者不能混，否则 Chatwoot 分不清名字来源、
// 会让对方改昵称把业务存的备注名顶掉。
function bookByJid(ev) {
  const map = new Map();
  for (const c of ev.contacts || []) {
    if (c.id && c.name) map.set(c.id, c.name);
  }
  for (const c of ev.chats || []) {
    if (c.id && c.name && !map.has(c.id)) map.set(c.id, c.name);
  }
  return map;
}

// 历史消息分批投给 Chatwoot。一个号能推一万条，一次性砸过去会把 Rails 打满，
// 所以切成小批、批间让一让。只发文字消息——历史里的媒体在 WhatsApp 服务器上多已过期。
const HISTORY_BATCH = 200;

async function shipHistory(inboxId, msgs, names = new Map(), books = new Map()) {
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
      // 备注名单独给，Chatwoot 侧优先用它、且不许被昵称顶掉。
      book_name: books.get(jid) || (m.key.senderPn ? books.get(m.key.senderPn) : null) || null,
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

module.exports = { connect, sendText, sendMedia, fetchHistory, checkNumber, logout, restoreAll, publicState, syncAvatars, resyncContacts, sessions };
