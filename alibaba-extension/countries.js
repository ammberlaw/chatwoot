// 页面上的国家写法 → CRM 的 trade_country 枚举。认不出就留空，
// 宁可业务员进 CRM 补一个，也别塞个非法值让整条建档失败。
var WTS = window.WTS || {};

WTS.toCountry = raw => {
  const t = String(raw || '').trim().toLowerCase().replace(/[.\s]+/g, ' ');
  if (!t) return '';
  const MAP = {
    'china': 'CHINA', 'cn': 'CHINA', '中国': 'CHINA',
    'united states': 'USA', 'usa': 'USA', 'us': 'USA', 'america': 'USA', '美国': 'USA',
    'germany': 'GERMANY', 'de': 'GERMANY', '德国': 'GERMANY',
    'united kingdom': 'UK', 'uk': 'UK', 'gb': 'UK', 'england': 'UK', '英国': 'UK',
    'france': 'FRANCE', 'fr': 'FRANCE', '法国': 'FRANCE',
    'italy': 'ITALY', 'it': 'ITALY', '意大利': 'ITALY',
    'spain': 'SPAIN', 'es': 'SPAIN', '西班牙': 'SPAIN',
    'canada': 'CANADA', 'ca': 'CANADA', '加拿大': 'CANADA',
    'australia': 'AUSTRALIA', 'au': 'AUSTRALIA', '澳大利亚': 'AUSTRALIA',
    'japan': 'JAPAN', 'jp': 'JAPAN', '日本': 'JAPAN',
    'south korea': 'SOUTH_KOREA', 'korea': 'SOUTH_KOREA', 'kr': 'SOUTH_KOREA', '韩国': 'SOUTH_KOREA',
    'india': 'INDIA', 'in': 'INDIA', '印度': 'INDIA',
    'russia': 'RUSSIA', 'ru': 'RUSSIA', '俄罗斯': 'RUSSIA',
    'brazil': 'BRAZIL', 'br': 'BRAZIL', '巴西': 'BRAZIL',
    'mexico': 'MEXICO', 'mx': 'MEXICO', '墨西哥': 'MEXICO',
    'netherlands': 'NETHERLANDS', 'nl': 'NETHERLANDS', '荷兰': 'NETHERLANDS',
    'turkey': 'TURKEY', 'tr': 'TURKEY', '土耳其': 'TURKEY',
    'united arab emirates': 'UAE', 'uae': 'UAE', 'ae': 'UAE', '阿联酋': 'UAE',
    'saudi arabia': 'SAUDI_ARABIA', 'sa': 'SAUDI_ARABIA', '沙特': 'SAUDI_ARABIA',
    'singapore': 'SINGAPORE', 'sg': 'SINGAPORE', '新加坡': 'SINGAPORE',
    'malaysia': 'MALAYSIA', 'my': 'MALAYSIA', '马来西亚': 'MALAYSIA',
    'thailand': 'THAILAND', 'th': 'THAILAND', '泰国': 'THAILAND',
    'vietnam': 'VIETNAM', 'vn': 'VIETNAM', '越南': 'VIETNAM',
    'indonesia': 'INDONESIA', 'id': 'INDONESIA', '印尼': 'INDONESIA',
    'philippines': 'PHILIPPINES', 'ph': 'PHILIPPINES', '菲律宾': 'PHILIPPINES',
    'south africa': 'SOUTH_AFRICA', 'za': 'SOUTH_AFRICA', '南非': 'SOUTH_AFRICA',
    'poland': 'POLAND', 'pl': 'POLAND', '波兰': 'POLAND',
    'nigeria': 'NIGERIA', 'ng': 'NIGERIA', '尼日利亚': 'NIGERIA',
    'kenya': 'KENYA', 'ke': 'KENYA', '肯尼亚': 'KENYA',
    'israel': 'ISRAEL', 'il': 'ISRAEL', '以色列': 'ISRAEL',
    'egypt': 'EGYPT', 'eg': 'EGYPT', '埃及': 'EGYPT',
    'taiwan': 'TAIWAN', 'tw': 'TAIWAN', '台湾': 'TAIWAN',
    'hong kong': 'HONG_KONG', 'hk': 'HONG_KONG', '香港': 'HONG_KONG',
    'new zealand': 'NEW_ZEALAND', 'nz': 'NEW_ZEALAND', '新西兰': 'NEW_ZEALAND',
  };
  return MAP[t] || '';
};

window.WTS = WTS;
