// 定时发送时区换算辅助：外贸场景下按「客户当地时间」定时，换算成真实发送时刻。
// 不依赖第三方库，用 Intl API 精确取任意 IANA 时区在某时刻的 UTC 偏移（含夏令时）。

// 常用外贸时区（value=IANA 时区，region=中文区域），偏移在渲染时用 tzOffsetLabel 实时算。
export const CURATED_ZONES = [
  { value: 'Asia/Shanghai', region: '北京 / 香港 / 台湾 / 新加坡时段' },
  { value: 'Asia/Tokyo', region: '日本 / 韩国' },
  { value: 'Asia/Singapore', region: '新加坡 / 马来西亚 / 菲律宾' },
  { value: 'Asia/Bangkok', region: '泰国 / 越南 / 印尼西部' },
  { value: 'Asia/Kolkata', region: '印度 / 斯里兰卡' },
  { value: 'Asia/Karachi', region: '巴基斯坦 / 哈萨克斯坦' },
  { value: 'Asia/Dubai', region: '阿联酋 / 阿曼 / 海湾地区' },
  { value: 'Asia/Riyadh', region: '沙特 / 卡塔尔 / 科威特' },
  { value: 'Europe/Moscow', region: '俄罗斯 · 莫斯科' },
  { value: 'Europe/Istanbul', region: '土耳其' },
  { value: 'Europe/Athens', region: '希腊 / 东欧 / 埃及' },
  { value: 'Europe/Paris', region: '德国 / 法国 / 意大利 / 西班牙 / 荷比' },
  { value: 'Europe/London', region: '英国 / 葡萄牙 / 爱尔兰' },
  { value: 'Africa/Lagos', region: '尼日利亚 / 西非' },
  { value: 'Africa/Johannesburg', region: '南非 / 南部非洲' },
  { value: 'Africa/Nairobi', region: '肯尼亚 / 东非' },
  { value: 'America/New_York', region: '美国东部 / 加拿大东部' },
  { value: 'America/Chicago', region: '美国中部' },
  { value: 'America/Denver', region: '美国山地' },
  { value: 'America/Los_Angeles', region: '美国西部' },
  { value: 'America/Mexico_City', region: '墨西哥' },
  { value: 'America/Sao_Paulo', region: '巴西' },
  { value: 'America/Argentina/Buenos_Aires', region: '阿根廷 / 智利' },
  { value: 'Australia/Sydney', region: '澳大利亚东部' },
  { value: 'Pacific/Auckland', region: '新西兰' },
];

// 客户 trade_country（国家码）→ 上面某个时区，用于选中客户后自动预选。
// 跨多时区的大国（美/俄/加/澳/巴）取主要商业时区。
export const COUNTRY_TZ = {
  USA: 'America/New_York',
  CANADA: 'America/New_York',
  MEXICO: 'America/Mexico_City',
  BRAZIL: 'America/Sao_Paulo',
  ARGENTINA: 'America/Argentina/Buenos_Aires',
  CHILE: 'America/Argentina/Buenos_Aires',
  COLOMBIA: 'America/New_York',
  PERU: 'America/New_York',
  VENEZUELA: 'America/New_York',
  BOLIVIA: 'America/New_York',
  ECUADOR: 'America/New_York',
  URUGUAY: 'America/Sao_Paulo',
  PARAGUAY: 'America/Sao_Paulo',
  COSTA_RICA: 'America/Mexico_City',
  GUATEMALA: 'America/Mexico_City',
  HONDURAS: 'America/Mexico_City',
  EL_SALVADOR: 'America/Mexico_City',
  NICARAGUA: 'America/Mexico_City',
  PANAMA: 'America/New_York',
  DOMINICAN_REPUBLIC: 'America/New_York',
  JAMAICA: 'America/New_York',
  HAITI: 'America/New_York',
  CUBA: 'America/New_York',
  BAHAMAS: 'America/New_York',
  BARBADOS: 'America/New_York',
  TRINIDAD_AND_TOBAGO: 'America/New_York',
  UK: 'Europe/London',
  IRELAND: 'Europe/London',
  PORTUGAL: 'Europe/London',
  ICELAND: 'Europe/London',
  GERMANY: 'Europe/Paris',
  FRANCE: 'Europe/Paris',
  ITALY: 'Europe/Paris',
  SPAIN: 'Europe/Paris',
  NETHERLANDS: 'Europe/Paris',
  BELGIUM: 'Europe/Paris',
  SWITZERLAND: 'Europe/Paris',
  AUSTRIA: 'Europe/Paris',
  SWEDEN: 'Europe/Paris',
  NORWAY: 'Europe/Paris',
  DENMARK: 'Europe/Paris',
  POLAND: 'Europe/Paris',
  CZECH: 'Europe/Paris',
  HUNGARY: 'Europe/Paris',
  CROATIA: 'Europe/Paris',
  SLOVAKIA: 'Europe/Paris',
  SLOVENIA: 'Europe/Paris',
  SERBIA: 'Europe/Paris',
  BOSNIA: 'Europe/Paris',
  ALBANIA: 'Europe/Paris',
  NORTH_MACEDONIA: 'Europe/Paris',
  LUXEMBOURG: 'Europe/Paris',
  MALTA: 'Europe/Paris',
  FINLAND: 'Europe/Athens',
  GREECE: 'Europe/Athens',
  ROMANIA: 'Europe/Athens',
  BULGARIA: 'Europe/Athens',
  UKRAINE: 'Europe/Athens',
  ESTONIA: 'Europe/Athens',
  LATVIA: 'Europe/Athens',
  LITHUANIA: 'Europe/Athens',
  CYPRUS: 'Europe/Athens',
  BELARUS: 'Europe/Moscow',
  RUSSIA: 'Europe/Moscow',
  TURKEY: 'Europe/Istanbul',
  GEORGIA: 'Asia/Dubai',
  ARMENIA: 'Asia/Dubai',
  AZERBAIJAN: 'Asia/Dubai',
  UAE: 'Asia/Dubai',
  OMAN: 'Asia/Dubai',
  SAUDI_ARABIA: 'Asia/Riyadh',
  QATAR: 'Asia/Riyadh',
  KUWAIT: 'Asia/Riyadh',
  BAHRAIN: 'Asia/Riyadh',
  IRAQ: 'Asia/Riyadh',
  IRAN: 'Asia/Dubai',
  JORDAN: 'Europe/Athens',
  LEBANON: 'Europe/Athens',
  SYRIA: 'Europe/Athens',
  ISRAEL: 'Europe/Athens',
  YEMEN: 'Asia/Riyadh',
  EGYPT: 'Europe/Athens',
  LIBYA: 'Europe/Athens',
  MOROCCO: 'Europe/London',
  ALGERIA: 'Europe/Paris',
  TUNISIA: 'Europe/Paris',
  NIGERIA: 'Africa/Lagos',
  GHANA: 'Africa/Lagos',
  SENEGAL: 'Africa/Lagos',
  IVORY_COAST: 'Africa/Lagos',
  CAMEROON: 'Africa/Lagos',
  BENIN: 'Africa/Lagos',
  TOGO: 'Africa/Lagos',
  BURKINA_FASO: 'Africa/Lagos',
  MALI: 'Africa/Lagos',
  GUINEA: 'Africa/Lagos',
  SIERRA_LEONE: 'Africa/Lagos',
  GABON: 'Africa/Lagos',
  CONGO: 'Africa/Lagos',
  DR_CONGO: 'Africa/Lagos',
  ANGOLA: 'Africa/Lagos',
  CAPE_VERDE: 'Europe/London',
  SOUTH_AFRICA: 'Africa/Johannesburg',
  BOTSWANA: 'Africa/Johannesburg',
  ZIMBABWE: 'Africa/Johannesburg',
  ZAMBIA: 'Africa/Johannesburg',
  MOZAMBIQUE: 'Africa/Johannesburg',
  MALAWI: 'Africa/Johannesburg',
  NAMIBIA: 'Africa/Johannesburg',
  KENYA: 'Africa/Nairobi',
  TANZANIA: 'Africa/Nairobi',
  UGANDA: 'Africa/Nairobi',
  ETHIOPIA: 'Africa/Nairobi',
  SOMALIA: 'Africa/Nairobi',
  RWANDA: 'Africa/Nairobi',
  SUDAN: 'Africa/Nairobi',
  SOUTH_SUDAN: 'Africa/Nairobi',
  MADAGASCAR: 'Africa/Nairobi',
  MAURITIUS: 'Asia/Dubai',
  REUNION: 'Asia/Dubai',
  INDIA: 'Asia/Kolkata',
  SRI_LANKA: 'Asia/Kolkata',
  NEPAL: 'Asia/Kolkata',
  BANGLADESH: 'Asia/Kolkata',
  PAKISTAN: 'Asia/Karachi',
  KAZAKHSTAN: 'Asia/Karachi',
  UZBEKISTAN: 'Asia/Karachi',
  AFGHANISTAN: 'Asia/Karachi',
  MALDIVES: 'Asia/Karachi',
  MYANMAR: 'Asia/Bangkok',
  THAILAND: 'Asia/Bangkok',
  VIETNAM: 'Asia/Bangkok',
  CAMBODIA: 'Asia/Bangkok',
  LAOS: 'Asia/Bangkok',
  INDONESIA: 'Asia/Bangkok',
  SINGAPORE: 'Asia/Singapore',
  MALAYSIA: 'Asia/Singapore',
  PHILIPPINES: 'Asia/Singapore',
  BRUNEI: 'Asia/Singapore',
  TAIWAN: 'Asia/Shanghai',
  HONG_KONG: 'Asia/Shanghai',
  MONGOLIA: 'Asia/Shanghai',
  JAPAN: 'Asia/Tokyo',
  SOUTH_KOREA: 'Asia/Tokyo',
  AUSTRALIA: 'Australia/Sydney',
  NEW_ZEALAND: 'Pacific/Auckland',
  FIJI: 'Pacific/Auckland',
  VANUATU: 'Australia/Sydney',
  PAPUA_NEW_GUINEA: 'Australia/Sydney',
};

// 浏览器所在时区（用户本地），换算与默认值的基准。
export function browserTz() {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || 'Asia/Shanghai';
  } catch {
    return 'Asia/Shanghai';
  }
}

// 某 IANA 时区在给定时刻相对 UTC 的偏移（毫秒，含夏令时）。
function tzOffsetMs(timeZone, date) {
  const dtf = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hour12: false,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
  const parts = dtf.formatToParts(date).reduce((acc, p) => {
    acc[p.type] = p.value;
    return acc;
  }, {});
  let hour = Number(parts.hour);
  if (hour === 24) hour = 0;
  const asUTC = Date.UTC(
    Number(parts.year),
    Number(parts.month) - 1,
    Number(parts.day),
    hour,
    Number(parts.minute),
    Number(parts.second)
  );
  // 时区偏移必为整分钟；date 可能带毫秒而 asUTC 只到秒，取整到分钟避免 +7:59 这类误差。
  return Math.round((asUTC - date.getTime()) / 60000) * 60000;
}

// 把「某时区的钟面时间」(YYYY-MM-DDTHH:mm) 换算成真实 UTC 时刻。
export function zonedWallClockToUtc(wallStr, timeZone) {
  const [datePart, timePart] = String(wallStr).split('T');
  if (!datePart || !timePart) return new Date(NaN);
  const [y, mo, d] = datePart.split('-').map(Number);
  const [h, mi] = timePart.split(':').map(Number);
  const guess = Date.UTC(y, mo - 1, d, h, mi);
  const offset = tzOffsetMs(timeZone, new Date(guess));
  return new Date(guess - offset);
}

// 时区当前偏移的短标签，如 'UTC+8' / 'UTC-5' / 'UTC+5:30'。
export function tzOffsetLabel(timeZone, date = new Date()) {
  const ms = tzOffsetMs(timeZone, date);
  const sign = ms >= 0 ? '+' : '-';
  const abs = Math.abs(ms);
  const h = Math.floor(abs / 3600000);
  const m = Math.floor((abs % 3600000) / 60000);
  return `UTC${sign}${h}${m ? `:${String(m).padStart(2, '0')}` : ''}`;
}
