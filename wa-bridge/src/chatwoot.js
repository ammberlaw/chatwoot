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

// 带媒体的入站消息。走 multipart 而不是把文件 base64 塞进 JSON：
// base64 有 33% 膨胀，一个几十 MB 的视频会变成上百 MB 的字符串，Rails 那边解析就爆了。
// 字段名与 postInbound 的 JSON 键一一对应，Rails 侧用同一套 params 读。
async function postInboundMedia(payload, media) {
  const form = new FormData();
  for (const [key, value] of Object.entries(payload)) {
    if (value !== null && value !== undefined) form.append(key, String(value));
  }
  form.append('media', new Blob([media.buffer], { type: media.mimetype }), media.filename);

  const res = await fetch(`${config.chatwootUrl}/webhooks/whatsapp_web`, {
    method: 'POST',
    // 不要手写 Content-Type：multipart 的 boundary 由 fetch 按 FormData 自动生成，
    // 手写会覆盖掉 boundary，Rails 收到的就是一坨解析不了的 body。
    headers: { 'X-Bridge-Token': config.bridgeToken },
    body: form,
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`chatwoot inbound media ${res.status}: ${body.slice(0, 300)}`);
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


// 配对时 WhatsApp 推来的历史消息，按批转给 Chatwoot。筛选（只留已建档客户的会话）
// 和落库都在 Chatwoot 侧做——桥不知道谁是客户。
async function postHistory(payload) {
  const res = await fetch(`${config.chatwootUrl}/webhooks/whatsapp_web/history`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Bridge-Token': config.bridgeToken,
    },
    body: JSON.stringify(payload),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`chatwoot history ${res.status}: ${body.slice(0, 300)}`);
  }
}

// 联系人资料：手机通讯录里的备注名（name）+ 对方自设的昵称（notify）。
// WhatsApp 是主动推这些的（配对同步 / 手机上改了备注），桥只负责转发，不额外问网络。
async function postContacts(payload) {
  const res = await fetch(`${config.chatwootUrl}/webhooks/whatsapp_web/contacts`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Bridge-Token': config.bridgeToken,
    },
    body: JSON.stringify(payload),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`chatwoot contacts ${res.status}: ${body.slice(0, 300)}`);
  }
}

// 联系人头像。头像在 pps.whatsapp.net 上，生产机（深圳）连不通那个域，
// 所以必须由桥（香港）下载完再把字节 multipart 传过去，不能只给 URL。
async function postAvatar(payload, media) {
  const form = new FormData();
  for (const [key, value] of Object.entries(payload)) {
    if (value !== null && value !== undefined) form.append(key, String(value));
  }
  form.append('avatar', new Blob([media.buffer], { type: media.mimetype }), media.filename);

  const res = await fetch(`${config.chatwootUrl}/webhooks/whatsapp_web/avatar`, {
    method: 'POST',
    headers: { 'X-Bridge-Token': config.bridgeToken },
    body: form,
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`chatwoot avatar ${res.status}: ${body.slice(0, 300)}`);
  }
}

module.exports = { postInbound, postInboundMedia, postStatus, postReceipt, postHistory, postContacts, postAvatar };
