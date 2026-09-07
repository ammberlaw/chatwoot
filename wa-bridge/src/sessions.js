const fs = require('fs');
const path = require('path');
const {
  default: makeWASocket,
  useMultiFileAuthState,
  fetchLatestBaileysVersion,
  DisconnectReason,
} = require('@whiskeysockets/baileys');
const { Boom } = require('@hapi/boom');
const QRCode = require('qrcode');
const pino = require('pino');

const config = require('./config');
const chatwoot = require('./chatwoot');

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

async function handleIncoming(inboxId, msg) {
  // Slice 1: individual text chats only. Skip our own echoes, status broadcasts, groups and channels.
  if (msg.key.fromMe) return;
  const remoteJid = msg.key.remoteJid || '';
  if (remoteJid === 'status@broadcast') return;
  if (remoteJid.endsWith(GROUP_SUFFIX) || remoteJid.endsWith('@newsletter')) return; // groups/channels handled later
  // Accept both classic (…@s.whatsapp.net) and WhatsApp's newer LID addressing (…@lid).
  if (!remoteJid.endsWith(INDIVIDUAL_SUFFIX) && !remoteJid.endsWith(LID_SUFFIX)) return;

  const text = extractText(msg.message);
  if (!text) return; // media-only handled later

  // Route by the full JID: WhatsApp Web addresses chats by JID, which may be a classic
  // phone (…@s.whatsapp.net) or the newer opaque LID (…@lid). We reply to this same JID.
  // The real phone number is only known for classic JIDs (or via senderPn on LID messages);
  // when unknown we leave it blank rather than storing the opaque LID as a fake number.
  const realPhone = remoteJid.endsWith(INDIVIDUAL_SUFFIX)
    ? jidToPhone(remoteJid)
    : msg.key.senderPn
      ? jidToPhone(msg.key.senderPn)
      : null;

  try {
    await chatwoot.postInbound({
      inbox_id: Number(inboxId),
      source_id: remoteJid,
      phone: realPhone,
      name: msg.pushName || realPhone || jidToPhone(remoteJid),
      text,
      message_id: msg.key.id,
      timestamp: Number(msg.messageTimestamp) || null,
    });
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
    syncFullHistory: false,
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

  sock.ev.on('messages.upsert', async ({ messages, type }) => {
    if (type !== 'notify') return;
    for (const msg of messages) {
      await handleIncoming(inboxId, msg);
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

module.exports = { connect, sendText, logout, restoreAll, publicState, sessions };
