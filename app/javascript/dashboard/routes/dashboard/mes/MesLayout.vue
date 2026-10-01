<script setup>
import { nextTick, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useMesProductLine } from 'dashboard/composables/useMesProductLine';
import { useMesTabs } from 'dashboard/composables/useMesTabs';
import MesTabBar from './MesTabBar.vue';

// MES 板块布局壳：承载 router-view，并用 keep-alive 缓存各子页实例。
// key = 产品线 + 路由名：切板块（换 route.name）走缓存，回到已查询的页保留搜索/筛选/分页/滚动，
// 不必重查；切产品线（换 activeProductLine）则 key 变化→该页重挂重跑 onMounted 按新线拉取。
// MesLayout 被各 MES 顶层路由复用（父级 router-view 无 key），故壳内 keep-alive 对整板块生效。
const { activeProductLine } = useMesProductLine();

// 建档页（新建/编辑单据的整页表单）不缓存：keep-alive 的 key 里没有 query，
// 缓存着再点另一张单进来会沿用上一单的表单内容、onMounted 也不再跑。
const INTAKE_PAGES = ['MesBomIntakeIndex', 'MesPurchaseOrderIntakeIndex'];

// 每进一个 MES 页就把它登记进标签条（已开过的只激活、并更新带查询参数的路径）。
const route = useRoute();
const { openTab } = useMesTabs();
const pageContent = ref(null);
const scrollPositions = new WeakMap();

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
      <div ref="pageContent" class="flex-1 min-w-0 min-h-0">
        <router-view v-slot="{ Component }">
          <keep-alive :max="12" :exclude="INTAKE_PAGES">
            <component
              :is="Component"
              :key="`mes-${activeProductLine || 'all'}-${$route.name}`"
            />
          </keep-alive>
        </router-view>
      </div>
    </div>
  </div>
</template>
