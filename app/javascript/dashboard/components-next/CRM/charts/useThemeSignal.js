import { ref } from 'vue';

// 主题信号：body 的 class（主题配色 / 明暗）变化时自增。
// 图表用 chartPalette() 读 DOM 变量、非响应式，切主题不会自动重绘；
// 让 computed / :key 依赖此信号，即可在切主题时触发重算与重绘（无需刷新）。
const themeSignal = ref(0);
let observing = false;

const ensureObserver = () => {
  if (observing || typeof document === 'undefined') return;
  observing = true;
  const observer = new MutationObserver(() => {
    themeSignal.value += 1;
  });
  observer.observe(document.body, {
    attributes: true,
    attributeFilter: ['class'],
  });
};

export const useThemeSignal = () => {
  ensureObserver();
  return themeSignal;
};
