// 所有网络请求都走这里：content script 直接 fetch 会被阿里页面的 CORS 挡掉，
// service worker 拿着 host_permissions 发起的请求不受页面同源策略约束。
// 另外令牌只存在这一侧，不进阿里页面的 JS 上下文。

const DEFAULTS = { baseUrl: 'https://wintouchspace.com', token: '', accountId: null, userId: null };

const getConfig = async () => ({ ...DEFAULTS, ...(await chrome.storage.local.get(Object.keys(DEFAULTS))) });

// 生产 nginx 会丢掉带下划线的请求头（api_access_token 恒返 401），必须用连字符形式。
const authHeaders = token => ({ 'api-access-token': token, 'Content-Type': 'application/json' });

const call = async (path, { method = 'GET', body } = {}) => {
  const cfg = await getConfig();
  if (!cfg.token) return { ok: false, error: '还没填令牌，请先打开插件设置' };

  const url = `${cfg.baseUrl.replace(/\/+$/, '')}${path}`;
  let res;
  try {
    res = await fetch(url, {
      method,
      headers: authHeaders(cfg.token),
      body: body ? JSON.stringify(body) : undefined,
    });
  } catch (e) {
    return { ok: false, error: `连不上 ${cfg.baseUrl}（${e.message}）` };
  }

  const text = await res.text();
  let data = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    // 非 JSON（多半是被挡在登录页或网关错误页），原样截一段带回去好排查
    return { ok: false, error: `返回的不是 JSON（HTTP ${res.status}）：${text.slice(0, 120)}` };
  }
  if (res.status === 401) return { ok: false, error: '令牌无效或已失效，请到插件设置里重填' };
  if (!res.ok) return { ok: false, error: data?.message || data?.error || `HTTP ${res.status}` };
  return { ok: true, data };
};

// 验令牌：顺带把账户 id 和本人 id 探出来，用户只需要填一个令牌。
const verify = async () => {
  const me = await call('/api/v1/profile');
  if (!me.ok) return me;

  const accounts = me.data.accounts || [];
  const account = accounts.find(a => /wintouch/i.test(a.name)) || accounts[0];
  if (!account) return { ok: false, error: '这个令牌名下没有任何账户' };

  await chrome.storage.local.set({ accountId: account.id, userId: me.data.id });
  return { ok: true, data: { name: me.data.name, email: me.data.email, account: account.name } };
};

const checkDuplicate = async fields => {
  const { accountId } = await getConfig();
  const q = new URLSearchParams();
  if (fields.alibaba_account) q.set('alibaba_account', fields.alibaba_account);
  if (fields.contact_email) q.set('email', fields.contact_email);
  if (fields.name) q.set('name', fields.name);
  return call(`/api/v1/accounts/${accountId}/crm/customers/check_duplicate?${q}`);
};

const createCustomer = async fields => {
  const { accountId, userId } = await getConfig();
  const customer = { ...fields, source_channel: 'ALIBABA', account_owner_id: userId };
  Object.keys(customer).forEach(k => {
    if (customer[k] === '' || customer[k] == null) delete customer[k];
  });
  return call(`/api/v1/accounts/${accountId}/crm/customers`, { method: 'POST', body: { customer } });
};

const HANDLERS = { verify, checkDuplicate, createCustomer, getConfig };

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  const handler = HANDLERS[msg?.type];
  if (!handler) return false;
  handler(msg.payload).then(sendResponse);
  return true; // 异步回复
});

chrome.action.onClicked.addListener(() => chrome.runtime.openOptionsPage());
