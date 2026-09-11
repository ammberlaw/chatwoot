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
