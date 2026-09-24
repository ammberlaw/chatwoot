<script setup>
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import {
  useMesTabs,
  MES_TAB_LABEL_KEYS,
} from 'dashboard/composables/useMesTabs';
import Icon from 'dashboard/components-next/icon/Icon.vue';

// 顶部标签条：开过的 MES 页留在这里，点回去还是原来的筛选/分页/滚动位置
// （状态由 MesLayout 的 keep-alive 保着，这里只负责跳转与关闭）
const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const { tabs, activeName, closeTab } = useMesTabs();

const titleOf = name => t(MES_TAB_LABEL_KEYS[name] || name);

const go = tab => {
  if (tab.name === route.name) return;
  router.push(tab.fullPath);
};

const onClose = name => {
  const nextPath = closeTab(name);
  if (nextPath) router.push(nextPath);
};
</script>

<template>
  <div class="shrink-0">
    <div
      v-if="tabs.length > 1"
      class="flex gap-1 items-center px-1 pt-1 -mb-px overflow-x-auto"
    >
      <button
        v-for="tab in tabs"
        :key="tab.name"
        type="button"
        class="group flex items-center gap-1 shrink-0 px-3 py-1.5 text-xs rounded-t-lg border border-b-0 transition-colors"
        :class="
          tab.name === activeName
            ? 'bg-n-solid-1 border-n-weak text-n-slate-12 font-medium'
            : 'bg-transparent border-transparent text-n-slate-11 hover:bg-n-solid-1/60'
        "
        @click="go(tab)"
      >
        <span>{{ titleOf(tab.name) }}</span>
        <Icon
          icon="i-lucide-x"
          class="size-3 opacity-0 transition-opacity group-hover:opacity-60 hover:!opacity-100"
          @click.stop="onClose(tab.name)"
        />
      </button>
    </div>
  </div>
</template>
