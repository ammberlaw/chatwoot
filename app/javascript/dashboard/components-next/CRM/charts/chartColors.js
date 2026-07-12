// 从 CSS 变量读取主题色，返回 canvas 可用的 rgb 字符串（随明暗主题自适应）。
// n- token 的 CSS 变量存的是空格分隔的通道值，如 --teal-9: "12 158 130"。
export const themeColor = (name, alpha = 1) => {
  if (typeof window === 'undefined') return '#000';
  const raw = getComputedStyle(document.documentElement)
    .getPropertyValue(`--${name}`)
    .trim();
  if (!raw) return '#000';
  return alpha === 1 ? `rgb(${raw})` : `rgb(${raw} / ${alpha})`;
};

// 常用图表色板（惰性求值，确保在浏览器环境读取当前主题）。
export const chartPalette = () => ({
  brand: themeColor('amber-9'),
  brandSoft: themeColor('amber-9', 0.15),
  teal: themeColor('teal-9'),
  tealSoft: themeColor('teal-9', 0.15),
  amber: themeColor('amber-9'),
  ruby: themeColor('ruby-9'),
  iris: themeColor('iris-9'),
  blue: themeColor('blue-9'),
  track: themeColor('slate-4'),
  grid: themeColor('slate-4', 0.6),
  ink: themeColor('slate-12'),
  muted: themeColor('slate-11'),
});

export const FONT_FAMILY =
  'Inter,-apple-system,system-ui,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif';
