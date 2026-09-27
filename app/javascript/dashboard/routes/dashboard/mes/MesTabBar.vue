<script setup>
import { nextTick, ref, watch } from 'vue';
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
const tabBar = ref(null);
watch(
  activeName,
  async () => {
    await nextTick();
    tabBar.value
      ?.querySelector('[aria-current="page"]')
      ?.parentElement?.scrollIntoView({ block: 'nearest', inline: 'nearest' });
  },
  { immediate: true }
);

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
  <div
    v-if="tabs.length > 1"
    ref="tabBar"
    class="flex shrink-0 items-center gap-4 px-4 sm:px-6 overflow-x-auto border-b border-n-weak"
  >
    <div
      v-for="tab in tabs"
      :key="tab.name"
      class="group flex shrink-0 items-center gap-2 border-b-2 transition-colors"
      :class="
        tab.name === activeName
          ? 'border-n-iris-9 text-n-slate-12'
          : 'border-transparent text-n-slate-11'
      "
    >
      <button
        type="button"
        class="py-3 text-sm whitespace-nowrap hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-iris-9"
        :class="{ 'font-semibold': tab.name === activeName }"
        :aria-current="tab.name === activeName ? 'page' : undefined"
        @click="go(tab)"
      >
        {{ titleOf(tab.name) }}
      </button>
      <button
        type="button"
        class="flex items-center justify-center size-5 rounded text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-iris-9"
        :aria-label="`${t('GENERAL.CLOSE')} ${titleOf(tab.name)}`"
        @click="onClose(tab.name)"
      >
        <Icon icon="i-lucide-x" class="size-3" />
      </button>
    </div>
  </div>
</template>
