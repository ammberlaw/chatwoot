// 后端凡是走 SQL SUM 的金额都是 BigDecimal，JSON 里是字符串（如 "407499542000.0"）。
// 直接 += 会变成字符串拼接，几次之后算出 NaN，所以入口统一过一遍 Number。
export const num = v => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};

// 后端金额一律存 micros（元 × 1e6）。移动端只展示整数元，位数多时不够看。
const SYMBOLS = { USD: '$', CNY: '¥', EUR: '€' };

export const money = (micros, currency = 'CNY') =>
  `${SYMBOLS[currency] || ''}${Math.round(num(micros) / 1e6).toLocaleString('zh-CN')}`;

export const shortDate = value =>
  value
    ? new Date(value).toLocaleDateString('zh-CN', {
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
      })
    : '—';

// 日程的 starts_at/ends_at 存的是「墙上时间」（9 点的会就是 9 点），
// 但接口把它序列化成了带 Z 的串，`new Date()` 解析会按 UTC 折算，
// 在 +08 区就变成 17 点。网页端一律用切片读它，App 也照这个口径，两端才一致。
export const wallTime = value => (value ? String(value).slice(11, 16) : '—');

export const wallDateTime = value => {
  if (!value) return '—';
  const s = String(value);
  return `${Number(s.slice(5, 7))}/${Number(s.slice(8, 10))} ${s.slice(11, 16)}`;
};

export const shortDateTime = value =>
  value
    ? new Date(value).toLocaleString('zh-CN', {
        month: 'numeric',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '—';

// 距今多久：跟进记录/最近联系用相对时间更好读
export const fromNow = value => {
  if (!value) return '—';
  const days = Math.floor((Date.now() - new Date(value).getTime()) / 86400000);
  if (days <= 0) return '今天';
  if (days === 1) return '昨天';
  if (days < 30) return `${days} 天前`;
  if (days < 365) return `${Math.floor(days / 30)} 个月前`;
  return `${Math.floor(days / 365)} 年前`;
};

// WhatsApp 深链只认纯数字号码
export const waLink = phone =>
  `https://wa.me/${String(phone || '').replace(/\D/g, '')}`;

// 邮件地址串 "张三 <a@b.com>" → 优先显示名，没有就显示地址；多个收件人只显示第一个 + 余数
export const addressLabel = raw => {
  const parts = String(raw || '')
    .split(',')
    .map(s => s.trim())
    .filter(Boolean);
  if (!parts.length) return '—';
  const first = parts[0];
  const m = first.match(/^(.*?)\s*<(.+)>$/);
  const label = (m ? m[1].replace(/^["']|["']$/g, '').trim() || m[2] : first);
  return parts.length > 1 ? `${label} 等 ${parts.length} 人` : label;
};

// 列表里显示「对方」：发件箱看收件人，其余看发件人
export const counterpartyOf = email =>
  addressLabel(email.folder === 'SENT' ? email.to_address : email.from_address);

// 邮件列表的摘要行。列表接口本来就带 body（详情要用），这里就地截一段，
// 不额外请求也不改后端。
// ⚠️ HTML 邮件的 body 存的是标签源码，直接截会得到「<!DOCTYPE html PUBLIC…」。
// 用 DOMParser 取纯文本：只解析不挂载，不会执行里面的脚本。
const htmlToText = html => {
  try {
    const doc = new DOMParser().parseFromString(html, 'text/html');
    doc.querySelectorAll('style,script,head').forEach(n => n.remove());
    return doc.body?.textContent || '';
  } catch {
    return String(html).replace(/<[^>]*>/g, ' ');
  }
};

export const snippet = (body, max = 70) => {
  if (!body) return '';
  const raw = /<[a-z!][\s\S]*>/i.test(body) ? htmlToText(body) : String(body);
  // 引用块和签名分隔线之后的内容丢掉，否则一列全是「> 原邮件」
  const head = raw.split(/\n-{2,}|\n_{2,}|\n> /)[0];
  const flat = head.replace(/\s+/g, ' ').trim();
  return flat.length > max ? `${flat.slice(0, max)}…` : flat;
};
