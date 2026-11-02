<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useMesProductLine } from 'dashboard/composables/useMesProductLine';
import { useMesTabs } from 'dashboard/composables/useMesTabs';
import MesTabBar from './MesTabBar.vue';

// MES 板块布局壳：承载 router-view，并用 keep-alive 缓存各子页实例。
// key = 产品线 + 路由名：切板块（换 route.name）走缓存，回到已查询的页保留搜索/筛选/分页/滚动，
// 不必重查；切产品线（换 activeProductLine）则 key 变化→该页重挂重跑 onMounted 按新线拉取。
// MesLayout 被各 MES 顶层路由复用（父级 router-view 无 key），故壳内 keep-alive 对整板块生效。
const { activeProductLine } = useMesProductLine();

// 建档页（新建/编辑单据的整页表单）的 key 要带上 query：不带的话，编辑完单 A 再点
// 单 B 会沿用 A 的表单内容、onMounted 也不再跑。带上之后每张单各有各的缓存实例，
// 采购填到一半切去产品档案/供应商档案查料、再切回来，单子还在原样——否则建档页被
// 销毁，每次切标签都要弹一次「当前内容还没保存」。
const INTAKE_ROUTES = [
  'mes_bom_intake_index',
  'mes_purchase_order_intake_index',
];

// 每进一个 MES 页就把它登记进标签条（已开过的只激活、并更新带查询参数的路径）。
const route = useRoute();
const { openTab } = useMesTabs();
const pageContent = ref(null);
const scrollPositions = new WeakMap();

const pageKey = computed(() => {
  const base = `mes-${activeProductLine.value || 'all'}-${route.name}`;
  if (!INTAKE_ROUTES.includes(route.name)) return base;

  // 排序后拼，保证同一张单不会因为参数顺序不同被当成两个实例。
  const query = Object.keys(route.query)
    .sort()
    .map(k => `${k}=${route.query[k]}`)
    .join('&');
  return query ? `${base}?${query}` : base;
});

// keep-alive 保留实例，但 DOM 移出页面后浏览器可能重置滚动位置。
watch([() => route.name, activeProductLine], async () => {
  pageContent.value?.querySelectorAll('*').forEach(element => {
    if (
      element.scrollTop ||
      element.scrollLeft ||
      scrollPositions.has(element)
    ) {
      scrollPositions.set(element, [element.scrollTop, element.scrollLeft]);
    }
  });
  await nextTick();
  pageContent.value?.querySelectorAll('*').forEach(element => {
    const position = scrollPositions.get(element);
    if (position) [element.scrollTop, element.scrollLeft] = position;
  });
});
watch(
  () => route.fullPath,
  () => openTab(route),
  { immediate: true }
);
</script>

<template>
  <!-- 页签与正文共用 mes-canvas 的一个外框，避免分别生成圆角卡片。
       keep-alive 始终挂载，页签显隐不影响页面输入、筛选和滚动状态。 -->
  <div class="mes-canvas flex flex-col w-full h-full">
    <div class="flex flex-col flex-1 min-w-0 min-h-0">
      <MesTabBar />
      <div ref="pageContent" class="flex-1 min-w-0 min-h-0 [&_table]:!border-separate [&_table]:!border-spacing-0 [&_table>thead>tr>th]:!bg-white [&_table>thead>tr>th]:!text-n-slate-11 [&_table>thead>tr>th]:!font-medium [&_table>thead>tr>th]:!py-2.5 [&_table>thead>tr>th]:border-b [&_table>thead>tr>th]:border-n-weak [&_table>tbody>tr>td]:border-b [&_table>tbody>tr>td]:border-n-weak">
        <router-view v-slot="{ Component }">
          <keep-alive :max="12">
            <component :is="Component" :key="pageKey" />
          </keep-alive>
        </router-view>
      </div>
    </div>
  </div>
</template>
