// 客户首字母头像。
// 曾经按名字散列出不同色相，但那个颜色不携带任何信息——列表里认人靠的是名字。
// 装饰色会把真正需要颜色的地方（警示、主行动）淹掉，所以一律中性。
const NEUTRAL = { bg: 'bg-black/[0.05]', fg: 'text-[color:var(--pb-ink-2)]' };

export const avatarTint = () => NEUTRAL;

// 中文取首字，英文取首字母
export const avatarText = name => {
  const s = String(name || '').trim();
  if (!s) return '?';
  const c = s[0];
  return /[a-z]/i.test(c) ? c.toUpperCase() : c;
};
