<script setup>
import { computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { StatusBar, Style } from '@capacitor/status-bar';
import { Capacitor } from '@capacitor/core';
import TabBar from '@/components/TabBar.vue';
import OfflineNotice from '@/components/OfflineNotice.vue';
import { useAuthStore } from '@/stores/auth';
import { useNetworkStore } from '@/stores/network';
import { setNetworkErrorHandler } from '@/api/client';

const route = useRoute();
const auth = useAuthStore();
const net = useNetworkStore();

const showTabs = computed(() => !!route.meta.tab);

onMounted(async () => {
  // 网络监听先于任何 await 注册，避免前面的异步失败把它挡掉
  setNetworkErrorHandler(
    () => net.reportRequestFailure(),
    () => net.reportRequestSuccess()
  );
  net.init();
  await auth.restore();
  if (Capacitor.isNativePlatform()) {
    await StatusBar.setStyle({ style: Style.Light }).catch(() => {});
  }
});
</script>

<template>
  <div class="flex flex-col h-full bg-n-background">
    <!-- 断网横幅：飞行模式下仍有可读界面，不是白屏 -->
    <OfflineNotice v-if="!net.online" />
    <router-view v-slot="{ Component }">
      <keep-alive :include="['HomePage', 'CustomersPage', 'MailPage', 'ApprovalsPage']">
        <component :is="Component" class="flex-1 min-h-0" />
      </keep-alive>
    </router-view>
    <TabBar v-if="showTabs" />
  </div>
</template>
