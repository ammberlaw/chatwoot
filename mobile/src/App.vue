<script setup>
import { computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useColorScheme } from '@/composables/useColorScheme';
import AppTabBar from '@/components/AppTabBar.vue';
import OfflineNotice from '@/components/OfflineNotice.vue';
import { useAuthStore } from '@/stores/auth';
import { useNetworkStore } from '@/stores/network';
import { setNetworkErrorHandler } from '@/api/client';

const route = useRoute();
const auth = useAuthStore();
const net = useNetworkStore();
const { init: initColorScheme } = useColorScheme();

const showTabs = computed(() => !!route.meta.tab);

onMounted(async () => {
  // 网络监听先于任何 await 注册，避免前面的异步失败把它挡掉
  setNetworkErrorHandler(
    () => net.reportRequestFailure(),
    () => net.reportRequestSuccess()
  );
  net.init();
  // 深浅色跟随系统（含状态栏反色）
  initColorScheme();
  // 视觉方案 A/B 对比用：?theme=overlay 或 localStorage.wtTheme
  const theme =
    new URLSearchParams(location.search).get('theme') || localStorage.getItem('wtTheme');
  if (theme === 'overlay') document.documentElement.classList.add('theme-overlay');
  await auth.restore();
});
</script>

<template>
  <div class="relative flex flex-col h-full overflow-hidden wt-aurora bg-n-background">
    <!-- 断网横幅：飞行模式下仍有可读界面，不是白屏 -->
    <OfflineNotice v-if="!net.online" />
    <router-view v-slot="{ Component }">
      <keep-alive :include="['HomePage', 'SchedulePage', 'CustomersPage', 'MailPage', 'ApprovalsPage']">
        <component :is="Component" class="flex-1 min-h-0" />
      </keep-alive>
    </router-view>
    <AppTabBar v-if="showTabs" />
  </div>
</template>
