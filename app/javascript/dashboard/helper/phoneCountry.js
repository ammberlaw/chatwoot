import { parsePhoneNumberFromString } from 'libphonenumber-js';

// 从手机号(如 WhatsApp 客户号码)推断所属国家/地区。
// 返回 { iso, code, name } 或 null:
//   iso  - ISO2 大写(如 'CN')
//   code - ISO2 小写(给 flag-icons 用:class="fi fi-cn")
//   name - 本地化国名(优先中文,浏览器不支持时退回 ISO2)
// 说明:WhatsApp 客户没有网页访客的 country_code(那是 IP 定位),但号码本身带国家区号,
//       用 libphonenumber-js 解析比只看区号更准(能区分 +1 美国/加拿大等共享区号)。

let regionNames = null;
try {
  regionNames = new Intl.DisplayNames(['zh-CN'], { type: 'region' });
} catch (e) {
  regionNames = null;
}

export function countryFromPhone(raw) {
  if (!raw) return null;
  let str = String(raw).trim();
  if (!str) return null;

  // WhatsApp 号码常见形式是不带 + 的国家码+号码(如 8613800138000),补上 + 便于解析。
  if (!str.startsWith('+')) {
    const digits = str.replace(/\D/g, '');
    if (!digits) return null;
    str = `+${digits}`;
  }

  let parsed = null;
  try {
    parsed = parsePhoneNumberFromString(str);
  } catch (e) {
    return null;
  }

  const iso = parsed && parsed.country;
  if (!iso) return null;

  let name = iso;
  try {
    name = (regionNames && regionNames.of(iso)) || iso;
  } catch (e) {
    name = iso;
  }

  return { iso, code: iso.toLowerCase(), name };
}
