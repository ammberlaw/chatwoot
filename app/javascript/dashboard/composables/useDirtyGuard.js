import { computed, ref } from 'vue';
import { useUnsavedGuard } from './useUnsavedGuard';

/**
 * 表单「未保存」守卫。把原来每个页面各写一遍的快照比对收成一行。
 *
 * 配套的拦截 UI 在 Dialog.vue 里：把 isDirty 传给 `:dirty`，
 * 用户点 X / 取消 / 点外部 / 按 Esc 时它自己弹三选一，页面不用再逐个入口接线。
 * 保存成功后照常调 dialogRef.close()——那是程序化关闭，不走拦截。
 *
 * @param {() => any} source 返回要监控的表单对象（用函数，才能让 computed 收集依赖）
 * @param {string[]} options.ignore 不算用户改动的字段名（深层同名字段一并忽略），
 *        比如选料时服务端带回来的实时库存 onHand——算进去会让刚打开的单子就被判成已修改
 */
export function useDirtyGuard(source, { ignore = [] } = {}) {
  const snapshot = () =>
    JSON.stringify(source(), (key, value) =>
      ignore.includes(key) ? undefined : value
    );

  // 基线必须用「当前表单」初始化：给空串的话，组件一挂载就 pristine !== 快照，
  // 什么都没动就被判成已修改，浏览器刷新拦截会一直挂着。
  const pristine = ref(snapshot());

  /** 表单填好后（打开弹窗、保存成功、放弃改动）重新取基线。 */
  const markPristine = () => {
    pristine.value = snapshot();
  };

  const isDirty = computed(() => pristine.value !== snapshot());

  // 刷新 / 关标签页那一层浏览器只认原生提示，一并挂上。
  useUnsavedGuard(isDirty);

  return { isDirty, markPristine };
}
