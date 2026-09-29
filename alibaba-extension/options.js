const $ = id => document.getElementById(id);
const show = (cls, text) => {
  const el = $('status');
  el.className = cls;
  el.textContent = text;
};

chrome.storage.local.get(['baseUrl', 'token']).then(cfg => {
  $('baseUrl').value = cfg.baseUrl || 'https://wintouchspace.com';
  $('token').value = cfg.token || '';
});

$('save').addEventListener('click', async () => {
  const baseUrl = $('baseUrl').value.trim();
  const token = $('token').value.trim();
  if (!baseUrl || !token) return show('err', '地址和令牌都要填');

  $('save').disabled = true;
  show('', '');
  await chrome.storage.local.set({ baseUrl, token });
  const res = await chrome.runtime.sendMessage({ type: 'verify' });
  $('save').disabled = false;

  if (!res?.ok) return show('err', `验证失败：${res?.error || '未知错误'}`);
  show('ok', `已连接：${res.data.name}（${res.data.email}）· 账户 ${res.data.account}`);
});
