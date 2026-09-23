// 客户本地时间。客户表没有时区字段，按国家推。
// 只是给业务员一个「现在打过去合不合适」的参考，所以：
//  · 跨多个时区的大国取商务主时区（美国取东部、俄罗斯取莫斯科）
//  · 不做夏令时——差一小时不影响「现在是不是深夜」这个判断，
//    真要精确得让后端存客户所在城市的 IANA 时区
const OFFSETS = {
  CHINA: 8, HONG_KONG: 8, TAIWAN: 8, SINGAPORE: 8, MALAYSIA: 8, PHILIPPINES: 8,
  JAPAN: 9, SOUTH_KOREA: 9, AUSTRALIA: 10, NEW_ZEALAND: 12,
  THAILAND: 7, VIETNAM: 7, INDONESIA: 7,
  INDIA: 5.5, PAKISTAN: 5, UAE: 4, SAUDI_ARABIA: 3, ISRAEL: 3, TURKEY: 3, RUSSIA: 3,
  EGYPT: 2, SOUTH_AFRICA: 2, GREECE: 3, FINLAND: 3, UKRAINE: 3, ROMANIA: 3,
  GERMANY: 2, FRANCE: 2, ITALY: 2, SPAIN: 2, NETHERLANDS: 2, BELGIUM: 2,
  SWITZERLAND: 2, SWEDEN: 2, NORWAY: 2, DENMARK: 2, AUSTRIA: 2, POLAND: 2, CZECH: 2,
  UK: 1, IRELAND: 1, PORTUGAL: 1,
  BRAZIL: -3, ARGENTINA: -3, CHILE: -4, COLOMBIA: -5, PERU: -5,
  USA: -4, CANADA: -4, MEXICO: -6,
};

const ISO2 = {
  CN: 'CHINA', US: 'USA', GB: 'UK', DE: 'GERMANY', FR: 'FRANCE', IT: 'ITALY',
  ES: 'SPAIN', CA: 'CANADA', AU: 'AUSTRALIA', JP: 'JAPAN', KR: 'SOUTH_KOREA',
  IN: 'INDIA', RU: 'RUSSIA', BR: 'BRAZIL', MX: 'MEXICO', NL: 'NETHERLANDS',
  AE: 'UAE', SA: 'SAUDI_ARABIA', SG: 'SINGAPORE', MY: 'MALAYSIA', TH: 'THAILAND',
  VN: 'VIETNAM', ID: 'INDONESIA', PH: 'PHILIPPINES', ZA: 'SOUTH_AFRICA',
  TR: 'TURKEY', IL: 'ISRAEL', EG: 'EGYPT', PT: 'PORTUGAL', GR: 'GREECE',
  IE: 'IRELAND', NZ: 'NEW_ZEALAND', TW: 'TAIWAN', HK: 'HONG_KONG', PK: 'PAKISTAN',
  UA: 'UKRAINE', RO: 'ROMANIA', PL: 'POLAND', SE: 'SWEDEN', NO: 'NORWAY',
  DK: 'DENMARK', FI: 'FINLAND', AT: 'AUSTRIA', CH: 'SWITZERLAND', BE: 'BELGIUM',
  CZ: 'CZECH', AR: 'ARGENTINA', CL: 'CHILE', CO: 'COLOMBIA', PE: 'PERU',
};

export const countryOffset = code => {
  if (!code) return null;
  const key = OFFSETS[code] !== undefined ? code : ISO2[String(code).toUpperCase()];
  const off = OFFSETS[key];
  return off === undefined ? null : off;
};

// 返回 { time: '07:07', zone: 'UTC+4' }，推不出来就是 null
export const localTimeOf = code => {
  const off = countryOffset(code);
  if (off === null) return null;
  const d = new Date(Date.now() + off * 3600000);
  const hh = String(d.getUTCHours()).padStart(2, '0');
  const mm = String(d.getUTCMinutes()).padStart(2, '0');
  const sign = off >= 0 ? '+' : '-';
  const abs = Math.abs(off);
  const label = Number.isInteger(abs) ? abs : abs.toFixed(1).replace('.0', '');
  return { time: `${hh}:${mm}`, zone: `UTC${sign}${label}` };
};
