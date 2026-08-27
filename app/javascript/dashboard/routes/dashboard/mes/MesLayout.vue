<script setup>
import { useMesProductLine } from 'dashboard/composables/useMesProductLine';

// MES 板块布局壳：承载 router-view，并用 keep-alive 缓存各子页实例。
// key = 产品线 + 路由名：切板块（换 route.name）走缓存，回到已查询的页保留搜索/筛选/分页/滚动，
// 不必重查；切产品线（换 activeProductLine）则 key 变化→该页重挂重跑 onMounted 按新线拉取。
// MesLayout 被各 MES 顶层路由复用（父级 router-view 无 key），故壳内 keep-alive 对整板块生效。
const { activeProductLine } = useMesProductLine();
</script>

<template>
  <!-- mes-canvas：给 MES 裸页(无自带卡类)套整页圆弧外框的挂钩层（见 _next-colors.scss）。
       玻璃(默认)/蓝/beebot = 玻璃外框；经典灰 = 白卡外框；已自带卡的页由 :not 排除不叠加。 -->
  <div class="mes-canvas w-full h-full">
    <router-view v-slot="{ Component }">
      <keep-alive :max="12">
        <component
          :is="Component"
          :key="`mes-${activeProductLine || 'all'}-${$route.name}`"
        />
      </keep-alive>
    </router-view>
  </div>
</template>
