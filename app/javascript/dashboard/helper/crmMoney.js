// CRM 金额显示：micros（1 元 = 1_000_000）→ 两位小数 + 千分位。
// PI、报价单、销售订单、提成表都是要和客户/业务对账的数，抹成整数就对不上账，
// 所以显示一律走这里，别再各页面各写一套 Math.round。
// 与 helper/erpMoney.js 同口径，区别只是 CRM 有几个页面按 en-US 分组。

const YUAN = 1_000_000;

const TWO_DECIMALS = { minimumFractionDigits: 2, maximumFractionDigits: 2 };

export const fmtYuan = (micros, locale) =>
  (Number(micros || 0) / YUAN).toLocaleString(locale, TWO_DECIMALS);
