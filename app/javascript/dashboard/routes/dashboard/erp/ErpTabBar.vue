<script setup>
import { nextTick, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useErpTabs, ERP_TAB_LABELS } from 'dashboard/composables/useErpTabs';
import Icon from 'dashboard/components-next/icon/Icon.vue';

// 顶部标签条：开过的 ERP 页留在这里，点回去还是原来的筛选/分页/滚动位置
// （状态由 ErpLayout 的 keep-alive 保着，这里只负责跳转与关闭）
const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const { tabs, activeName, closeTab, moveTab } = useErpTabs();

// 拖动标签改顺序：拖到哪一个头上就插到它前面
const draggingName = ref('');
const onDragStart = name => {
  draggingName.value = name;
};
const onDrop = name => {
  moveTab(draggingName.value, name);
  draggingName.value = '';
};
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

// ERP 侧栏用的是中文字面量（不像 MES 走 i18n 键），这里直接取。
const titleOf = name => ERP_TAB_LABELS[name] || name;

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
      draggable="true"
      :title="titleOf(tab.name) + '（可拖动调整顺序）'"
      class="group flex shrink-0 items-center gap-2 border-b-2 transition-colors cursor-move"
      :class="[
        tab.name === activeName
          ? 'border-n-iris-9 text-n-slate-12'
          : 'border-transparent text-n-slate-11',
        draggingName === tab.name ? 'opacity-40' : '',
      ]"
      @dragstart="onDragStart(tab.name)"
      @dragover.prevent
      @drop.prevent="onDrop(tab.name)"
      @dragend="draggingName = ''"
    >
      <button
        type="button"
        class="px-0 py-3 rounded-none text-sm whitespace-nowrap hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-iris-9"
        :class="{ 'font-semibold': tab.name === activeName }"
        :aria-current="tab.name === activeName ? 'page' : undefined"
        @click="go(tab)"
      >
        {{ titleOf(tab.name) }}
      </button>
      <button
        type="button"
        class="flex items-center justify-center size-5 shrink-0 p-0 rounded text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-iris-9"
        :aria-label="`${t('GENERAL.CLOSE')} ${titleOf(tab.name)}`"
        @click="onClose(tab.name)"
      >
        <Icon icon="i-lucide-x" class="size-3 shrink-0" />
      </button>
    </div>
  </div>
</template>
