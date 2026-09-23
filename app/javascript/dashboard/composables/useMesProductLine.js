import { ref, computed } from 'vue';

// 产品线（页面分流维度）。空值 = 全部产线（不过滤）。short 供窄侧栏切换器显示。
export const MES_PRODUCT_LINES = [
  { value: '', label: '全部产线', short: '全部' },
  { value: 'COMMERCIAL_DISPLAY', label: '商显工控', short: '商显工控' },
  { value: 'TABLET', label: '平板电脑', short: '平板' },
];

// 建单表单专用：不含「全部产线」。新建的单子必须落在具体产线上，
// 留着空值选项等于让人建出一条谁都看不见的单（BOM 上这么丢过 3 条）。
export const MES_PRODUCT_LINE_CHOICES = MES_PRODUCT_LINES.filter(o => o.value);

const LABELS = {
  COMMERCIAL_DISPLAY: '商显工控',
  TABLET: '平板电脑',
};
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
    formOptions: MES_PRODUCT_LINE_CHOICES,
    label,
    setActiveProductLine,
    productLineLabel,
  };
}
