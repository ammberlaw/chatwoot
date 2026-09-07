<script setup>
import { useRoute, useRouter } from 'vue-router';
import { Haptics, ImpactStyle } from '@capacitor/haptics';
import { Capacitor } from '@capacitor/core';

const route = useRoute();
const router = useRouter();

const TABS = [
  { name: 'home', label: '工作台', icon: 'i-lucide-layout-dashboard' },
  { name: 'customers', label: '客户', icon: 'i-lucide-users' },
  { name: 'scan', label: '扫码', icon: 'i-lucide-scan-line' },
  { name: 'mail', label: '邮件', icon: 'i-lucide-mail' },
  { name: 'approvals', label: '审批', icon: 'i-lucide-check-square' },
];

const go = async tab => {
  if (route.name === tab.name) return;
  if (Capacitor.isNativePlatform()) {
    await Haptics.impact({ style: ImpactStyle.Light }).catch(() => {});
  }
  router.push({ name: tab.name });
};
</script>

<template>
  <nav
    class="flex-none border-t border-n-weak bg-n-solid-1/95 backdrop-blur-xl pb-safeBottom"
  >
    <div class="flex items-stretch">
      <button
        v-for="tab in TABS"
        :key="tab.name"
        type="button"
        class="flex flex-col items-center justify-center flex-1 gap-1 min-h-[52px] active:bg-n-alpha-1"
        :class="
          route.name === tab.name ? 'text-n-iris-11' : 'text-n-slate-10'
        "
        @click="go(tab)"
      >
        <span class="size-5" :class="tab.icon" />
        <span class="text-[10px] font-medium leading-none">{{ tab.label }}</span>
      </button>
    </div>
  </nav>
</template>
