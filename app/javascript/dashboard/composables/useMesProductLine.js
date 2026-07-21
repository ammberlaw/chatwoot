import { ref, computed } from 'vue';

// 产品线（页面分流维度）。空值 = 全部产线（不过滤）。
export const MES_PRODUCT_LINES = [
  { value: '', label: '全部产线' },
  { value: 'DISPLAY', label: '商显/工控' },
  { value: 'TABLET', label: '平板电脑' },
];

const LABELS = { DISPLAY: '商显/工控', TABLET: '平板电脑' };
const STORAGE_KEY = 'mes_product_line';

const readStored = () => {
  try {
    return window.localStorage.getItem(STORAGE_KEY) || '';
  } catch {
    return '';
  }
};

// 模块级单例：组件（响应式）与 axios 拦截器（普通读）共用同一份。
const activeProductLine = ref(readStored());

export const getActiveProductLine = () => activeProductLine.value;

export const setActiveProductLine = value => {
  activeProductLine.value = value || '';
  try {
    window.localStorage.setItem(STORAGE_KEY, activeProductLine.value);
  } catch {
    /* localStorage 不可用时仅内存保留 */
  }
};

export const productLineLabel = code => LABELS[code] || '';

export function useMesProductLine() {
  const label = computed(() => LABELS[activeProductLine.value] || '全部产线');
  return {
    activeProductLine,
    options: MES_PRODUCT_LINES,
    label,
    setActiveProductLine,
    productLineLabel,
  };
}
