import { watch, onBeforeUnmount } from 'vue';

/**
 * 浏览器级的「未保存」拦截：表单有改动时，刷新 / 关标签 / 前进后退
 * 会弹出浏览器原生确认框。
 *
 * 弹窗内的「取消」由各页自己拦（能给出「继续编辑 / 不保存 / 存草稿」三选一，
 * 体验更好）；这里只补浏览器那一层——刷新和关标签是拦不住的，只能靠原生提示。
 *
 * 浏览器的限制（不是我们能改的）：
 *   · 提示文案由浏览器决定，自定义文字一律被忽略
 *   · 页面必须有过交互（点击/输入）才会弹，直接打开就刷新不会弹
 *
 * @param {import('vue').Ref<boolean>|import('vue').ComputedRef<boolean>} isDirty
 */
export function useUnsavedGuard(isDirty) {
  // 现代浏览器只看 preventDefault / returnValue，文案给了也不显示。
  const handler = event => {
    event.preventDefault();
    event.returnValue = '';
  };

  const attach = () => window.addEventListener('beforeunload', handler);
  const detach = () => window.removeEventListener('beforeunload', handler);

  watch(isDirty, dirty => (dirty ? attach() : detach()), { immediate: true });

  // 组件卸载时务必摘掉，否则换页之后仍然拦着刷新。
  onBeforeUnmount(detach);
}
