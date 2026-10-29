<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useErpTabs } from 'dashboard/composables/useErpTabs';
import ErpTabBar from './ErpTabBar.vue';

// ERP 板块布局壳：承载 router-view + 顶部标签条，并用 keep-alive 缓存各子页实例。
// erp-canvas 是「整页白卡」的挂钩层（与 MES 的 mes-canvas 同款，见 _next-colors.scss）：
// 经典灰主题下给内容区套白底圆角外框；紫玻璃默认主题下无样式 = 纯透传，不影响原布局。
//
// keep-alive 是「切页回来单据还在」的关键：不缓存的话子页会被销毁重建，
// 凭证填到一半切去查个科目余额、切回来就是一张空单（2026-10-29 反馈）。
// 与 MES 同一套做法，只是 ERP 没有产品线这一层，key 只认路由名。
const route = useRoute();
const { openTab } = useErpTabs();
const pageContent = ref(null);
const scrollPositions = new WeakMap();

const pageKey = computed(() => `erp-${route.name}`);

// keep-alive 保留实例，但 DOM 移出页面后浏览器可能重置滚动位置，切回来要还原。
watch(
  () => route.name,
  async () => {
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
  }
);

watch(() => route.fullPath, () => openTab(route), { immediate: true });
</script>

<template>
  <div class="erp-canvas flex flex-col w-full h-full">
    <div class="flex flex-col flex-1 min-w-0 min-h-0">
      <ErpTabBar />
      <div ref="pageContent" class="flex-1 min-w-0 min-h-0">
        <router-view v-slot="{ Component }">
          <keep-alive :max="12">
            <component :is="Component" :key="pageKey" />
          </keep-alive>
        </router-view>
      </div>
    </div>
  </div>
</template>
