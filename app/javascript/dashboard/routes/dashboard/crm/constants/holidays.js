// 外贸重点市场重要节日（只读背景标记，供业务给客户发问候参考）。
// 三类来源：①固定公历日期；②按年计算(复活节/感恩节/母亲节等)；③农历/伊斯兰历查表(2026–2027，含少量近似)。
// 每条：{ name, region, emoji }。holidaysFor(dateKey='YYYY-MM-DD') 返回当天节日数组（可能多条）。

// ① 固定公历：'MM-DD' → 节日
const FIXED = {
  '01-01': [{ name: '元旦 New Year', region: '全球', emoji: '🎉' }],
  '02-14': [{ name: '情人节 Valentine', region: '欧美', emoji: '💝' }],
  '03-08': [{ name: '国际妇女节', region: '多国', emoji: '🌷' }],
  '03-17': [{ name: '圣帕特里克节', region: '爱尔兰/欧美', emoji: '☘️' }],
  '04-01': [{ name: '愚人节', region: '欧美', emoji: '🃏' }],
  '05-01': [{ name: '国际劳动节', region: '多国', emoji: '⚙️' }],
  '06-12': [{ name: '俄罗斯国庆', region: '俄罗斯', emoji: '🇷🇺' }],
  '07-01': [{ name: '加拿大国庆', region: '加拿大', emoji: '🇨🇦' }],
  '07-04': [{ name: '美国独立日', region: '美国', emoji: '🇺🇸' }],
  '07-14': [{ name: '法国国庆', region: '法国', emoji: '🇫🇷' }],
  '08-15': [{ name: '光复节/圣母升天', region: '韩国/南欧', emoji: '🕊️' }],
  '09-16': [{ name: '墨西哥独立日', region: '墨西哥', emoji: '🇲🇽' }],
  '10-01': [{ name: '中国国庆', region: '中国', emoji: '🇨🇳' }],
  '10-03': [{ name: '德国统一日', region: '德国', emoji: '🇩🇪' }],
  '10-31': [{ name: '万圣节 Halloween', region: '欧美', emoji: '🎃' }],
  '11-11': [{ name: '双十一购物节', region: '中国', emoji: '🛍️' }],
  '12-06': [{ name: '西班牙宪法日', region: '西班牙', emoji: '🇪🇸' }],
  '12-25': [{ name: '圣诞节 Christmas', region: '全球', emoji: '🎄' }],
  '12-26': [{ name: '节礼日 Boxing Day', region: '英联邦', emoji: '🎁' }],
  '12-31': [{ name: '跨年夜 New Year Eve', region: '全球', emoji: '🎆' }],
};

// ③ 农历/伊斯兰历（每年不同，查表；伊斯兰历按月相略有浮动，标注为近似）。
const LOOKUP = {
  '2026-02-17': [{ name: '中国春节', region: '中国', emoji: '🧧' }],
  '2027-02-06': [{ name: '中国春节', region: '中国', emoji: '🧧' }],
  '2026-09-25': [{ name: '中秋节', region: '中国/东南亚', emoji: '🥮' }],
  '2027-09-15': [{ name: '中秋节', region: '中国/东南亚', emoji: '🥮' }],
  '2026-03-20': [
    { name: '开斋节 Eid al-Fitr(约)', region: '中东/穆斯林市场', emoji: '🌙' },
  ],
  '2027-03-10': [
    { name: '开斋节 Eid al-Fitr(约)', region: '中东/穆斯林市场', emoji: '🌙' },
  ],
  '2026-05-27': [
    { name: '宰牲节 Eid al-Adha(约)', region: '中东/穆斯林市场', emoji: '🐑' },
  ],
  '2027-05-17': [
    { name: '宰牲节 Eid al-Adha(约)', region: '中东/穆斯林市场', emoji: '🐑' },
  ],
  '2026-11-08': [{ name: '排灯节 Diwali', region: '印度', emoji: '🪔' }],
  '2027-10-29': [{ name: '排灯节 Diwali', region: '印度', emoji: '🪔' }],
};

const pad = n => String(n).padStart(2, '0');
const key = d =>
  `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

// 复活节星期日（Meeus/Jones/Butcher 算法，公历）。
const easterSunday = year => {
  const a = year % 19;
  const b = Math.floor(year / 100);
  const c = year % 100;
  const d = Math.floor(b / 4);
  const e = b % 4;
  const f = Math.floor((b + 8) / 25);
  const g = Math.floor((b - f + 1) / 3);
  const h = (19 * a + b - d - g + 15) % 30;
  const i = Math.floor(c / 4);
  const k = c % 4;
  const l = (32 + 2 * e + 2 * i - h - k) % 7;
  const m = Math.floor((a + 11 * h + 22 * l) / 451);
  const month = Math.floor((h + l - 7 * m + 114) / 31);
  const day = ((h + l - 7 * m + 114) % 31) + 1;
  return new Date(year, month - 1, day);
};

const addDays = (d, n) =>
  new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
// 某月第 n 个星期几（weekday 0=周日）。
const nthWeekday = (year, month0, weekday, n) => {
  const first = new Date(year, month0, 1);
  const offset = (weekday - first.getDay() + 7) % 7;
  return new Date(year, month0, 1 + offset + (n - 1) * 7);
};

// 按年计算的节日 → { 'YYYY-MM-DD': [...] }
const computedForYear = year => {
  const out = {};
  const push = (d, h) => {
    (out[key(d)] ||= []).push(h);
  };
  const easter = easterSunday(year);
  push(addDays(easter, -2), {
    name: '耶稣受难日 Good Friday',
    region: '欧美',
    emoji: '✝️',
  });
  push(easter, { name: '复活节 Easter', region: '欧美', emoji: '🐣' });
  push(addDays(easter, 1), {
    name: '复活节星期一',
    region: '欧美',
    emoji: '🐰',
  });
  push(nthWeekday(year, 4, 0, 2), {
    name: '母亲节 Mother’s Day',
    region: '欧美/多国',
    emoji: '💐',
  });
  push(nthWeekday(year, 5, 0, 3), {
    name: '父亲节 Father’s Day',
    region: '欧美/多国',
    emoji: '👔',
  });
  const thanksgiving = nthWeekday(year, 10, 4, 4); // 11月第4个周四
  push(thanksgiving, {
    name: '感恩节 Thanksgiving',
    region: '美国',
    emoji: '🦃',
  });
  push(addDays(thanksgiving, 1), {
    name: '黑色星期五 Black Friday',
    region: '欧美',
    emoji: '🛒',
  });
  push(addDays(thanksgiving, 4), {
    name: '网络星期一 Cyber Monday',
    region: '欧美',
    emoji: '💻',
  });
  return out;
};

const cache = {};
const forYear = year => {
  if (cache[year]) return cache[year];
  const map = { ...computedForYear(year) };
  Object.entries(LOOKUP).forEach(([k, v]) => {
    if (k.startsWith(`${year}-`)) (map[k] ||= []).push(...v);
  });
  cache[year] = map;
  return map;
};

// 某天的节日数组（'YYYY-MM-DD'）；合并固定 + 按年 + 查表。
export const holidaysFor = dateKey => {
  if (!dateKey || dateKey.length < 10) return [];
  const [y, m, d] = dateKey.split('-');
  return [
    ...(FIXED[`${m}-${d}`] || []),
    ...(forYear(Number(y))[dateKey] || []),
  ];
};
