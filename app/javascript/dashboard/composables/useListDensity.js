import { ref } from 'vue';

// 列表行高：宽松（默认）/ 紧凑。反馈点名「间距太长，可以自己拉短」。
// 做成一个全局开关挂在 body 上（样式见 _base.scss 的 body.list-compact），
// 而不是每张表各自实现拖拽——几十张表逐一做既没人用也记不住，
// 真实诉求就是「一屏多看几行」。
const STORAGE_KEY = 'list_density_compact';

const read = () => {
  try {
    return window.localStorage.getItem(STORAGE_KEY) === '1';
  } catch {
    return false;
  }
};

// 模块级单例：多个页面共用同一份状态，切一次全站生效。
const compact = ref(read());

const paint = () => {
  document.body.classList.toggle('list-compact', compact.value);
};
paint();

export function useListDensity() {
  const toggleDensity = () => {
    compact.value = !compact.value;
    try {
      window.localStorage.setItem(STORAGE_KEY, compact.value ? '1' : '0');
    } catch {
      // 隐私模式下存不住就只在本次会话生效，不影响使用
    }
    paint();
  };
  return { compact, toggleDensity };
}
