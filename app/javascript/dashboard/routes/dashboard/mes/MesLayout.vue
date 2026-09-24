<script setup>
import { watch } from 'vue';
import { useRoute } from 'vue-router';
import { useMesProductLine } from 'dashboard/composables/useMesProductLine';
import { useMesTabs } from 'dashboard/composables/useMesTabs';
import MesTabBar from './MesTabBar.vue';

// MES 板块布局壳：承载 router-view，并用 keep-alive 缓存各子页实例。
// key = 产品线 + 路由名：切板块（换 route.name）走缓存，回到已查询的页保留搜索/筛选/分页/滚动，
// 不必重查；切产品线（换 activeProductLine）则 key 变化→该页重挂重跑 onMounted 按新线拉取。
// MesLayout 被各 MES 顶层路由复用（父级 router-view 无 key），故壳内 keep-alive 对整板块生效。
const { activeProductLine } = useMesProductLine();

// 每进一个 MES 页就把它登记进标签条（已开过的只激活、并更新带查询参数的路径）。
const route = useRoute();
const { openTab } = useMesTabs();
watch(
  () => route.fullPath,
  () => openTab(route),
  { immediate: true }
);
</script>

<template>
  <!-- mes-canvas：给 MES 裸页(无自带卡类)套整页圆弧外框的挂钩层（见 _next-colors.scss）。
       玻璃(默认)/蓝/beebot = 玻璃外框；经典灰 = 白卡外框；已自带卡的页由 :not 排除不叠加。 -->
  <div class="mes-canvas flex flex-col w-full h-full">
    <MesTabBar />
    <div class="flex-1 min-h-0">
      <router-view v-slot="{ Component }">
        <keep-alive :max="12">
          <component
            :is="Component"
            :key="`mes-${activeProductLine || 'all'}-${$route.name}`"
          />
        </keep-alive>
      </router-view>
    </div>
  </div>
</template>
