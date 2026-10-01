import { onActivated, onDeactivated, watch } from 'vue';
import { useRoute } from 'vue-router';

/**
 * 「带参数再次进入同一个页面」时重新套用 query。
 *
 * MES 各页在 MesLayout 的 <keep-alive> 里缓存着（保留筛选/滚动，切回来不重查）。
 * 代价是：从站内通知点「待接单 MO2609001」跳过来时，组件是复用的、onMounted 不再跑，
 * 于是 q / view 这些参数全不生效，页面还停在上次的样子——表现就是「订单刷不出来」或一片空白。
 *
 * 两种情况都要管：
 *   · 从别的页跳回来（走 onActivated）
 *   · 人已经在本页，只换了 query（不会触发 activated，靠 watch）
 * 首次挂载那次跳过，交给页面自己的 onMounted，否则首屏会白拉两次。
 *
 * @param {(query: Record<string, any>) => void} apply 套用参数（通常是设筛选 + 重新取数）
 */
export function useRouteQueryReentry(apply) {
  const route = useRoute();
  let lastKey = null;
  let booted = false;
  let active = true;

  const run = () => {
    const key = JSON.stringify(route.query);
    if (!booted) {
      booted = true;
      lastKey = key;
      return;
    }
    if (key === lastKey) return;
    lastKey = key;
    apply(route.query);
  };

  onActivated(() => {
    active = true;
    run();
  });
  onDeactivated(() => {
    active = false;
  });

  // 停在本页只换 query：activated 不会触发，这里补。
  // 页面被切走时不处理——等它重新 activated 时统一套用，避免后台页白拉数据。
  watch(
    () => route.query,
    () => {
      if (active) run();
    }
  );
}
