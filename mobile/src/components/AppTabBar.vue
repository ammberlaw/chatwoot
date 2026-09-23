<script setup>
import { ref, onMounted, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { Haptics, ImpactStyle } from '@capacitor/haptics';
import { Capacitor } from '@capacitor/core';
import { fetchApprovalCounts, fetchEmailCounts } from '@/api/crm';

// 全部一级页面共用这一个底栏，页面里不允许各写各的。
// 规范：五个固定入口 / 图标在上文字在下 / 高度 72 + 安全区 /
// 选中＝黑色主体 + 黄色标记 / 未选中 #6E6E73 / 轻微半透明磨砂，不做厚重卡片。
const TABS = [
  { name: 'home', label: '工作台', line: 'i-ri-dashboard-3-line', fill: 'i-ri-dashboard-3-fill' },
  { name: 'schedule', label: '日程', line: 'i-ri-calendar-line', fill: 'i-ri-calendar-fill' },
  { name: 'messages', label: '消息', line: 'i-ri-chat-3-line', fill: 'i-ri-chat-3-fill' },
  { name: 'mail', label: '邮件', line: 'i-ri-mail-line', fill: 'i-ri-mail-fill', badge: 'mailUnread' },
  { name: 'customers', label: '客户', line: 'i-ri-group-line', fill: 'i-ri-group-fill' },
];

const route = useRoute();
const router = useRouter();
const counts = ref({});

const loadCounts = async () => {
  const [a, m] = await Promise.allSettled([fetchApprovalCounts(), fetchEmailCounts()]);
  counts.value = {
    todo: a.status === 'fulfilled' ? a.value.data?.todo : 0,
    mailUnread: m.status === 'fulfilled' ? m.value.data?.unread : 0,
  };
};
onMounted(loadCounts);
watch(() => route.name, loadCounts);

const go = async tab => {
  if (route.name === tab.name) return;
  if (Capacitor.isNativePlatform()) {
    await Haptics.impact({ style: ImpactStyle.Light }).catch(() => {});
  }
  router.push({ name: tab.name });
};
</script>

<template>
  <nav class="absolute inset-x-0 bottom-0 z-30 wt-tabbar-blur pb-safeBottom">
    <div class="flex h-[56px]">
      <button
        v-for="tab in TABS"
        :key="tab.name"
        type="button"
        :aria-label="tab.label"
        class="relative flex flex-col items-center justify-center flex-1 gap-1 transition-opacity active:opacity-60"
        @click="go(tab)"
      >
        <span class="relative">
          <span
            class="block size-[22px]"
            :class="[
              route.name === tab.name ? tab.fill : tab.line,
              route.name === tab.name
                ? 'text-[color:var(--black)]'
                : 'text-[color:var(--tab-inactive)]',
            ]"
          />
          <!-- 未读角标 -->
          <span
            v-if="tab.badge && counts[tab.badge]"
            class="absolute -right-2.5 -top-1.5 min-w-[17px] px-1 rounded-full bg-[color:var(--yellow)] text-[10px] font-bold leading-[17px] text-center text-black"
          >
            {{ counts[tab.badge] > 99 ? '99+' : counts[tab.badge] }}
          </span>
        </span>

        <span
          class="text-[11px] leading-none"
          :class="
            route.name === tab.name
              ? 'text-[color:var(--black)] font-semibold'
              : 'text-[color:var(--tab-inactive)]'
          "
        >
          {{ tab.label }}
        </span>

        <!-- 选中的黄色标记 -->
        <span
          class="rounded-full size-1"
          :class="route.name === tab.name ? 'bg-[color:var(--yellow)]' : 'bg-transparent'"
        />
      </button>
    </div>
  </nav>
</template>
