// 客户星级：按累计成交额（人民币）自动评定 0–5 星。阈值为产品定义，全站统一，
// 与后端 Crm::Customer::STAR_TIERS_RMB / #customer_star 同口径。
export const STAR_TIERS_RMB = [20000, 100000, 300000, 1000000, 3000000];

// 累计成交额（micros，人民币，1 元 = 1,000,000 micros）→ 星级 0–5。
export const customerStarFromMicros = micros => {
  const rmb = Number(micros || 0) / 1e6;
  return STAR_TIERS_RMB.reduce((n, t) => (rmb >= t ? n + 1 : n), 0);
};

// 悬浮解释用的分档说明（下标 = 星级 0…5）。
export const STAR_TIER_HINTS = [
  '0 星：累计成交额 < ¥20,000',
  '1 星：¥20,000 ≤ 累计成交额 < ¥100,000',
  '2 星：¥100,000 ≤ 累计成交额 < ¥300,000',
  '3 星：¥300,000 ≤ 累计成交额 < ¥1,000,000',
  '4 星：¥1,000,000 ≤ 累计成交额 < ¥3,000,000',
  '5 星：累计成交额 ≥ ¥3,000,000',
];
