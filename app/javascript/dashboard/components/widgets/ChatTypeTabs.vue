<script setup>
import { computed } from 'vue';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import wootConstants from 'dashboard/constants/globals';

const props = defineProps({
  items: {
    type: Array,
    default: () => [],
  },
  activeTab: {
    type: String,
    default: wootConstants.ASSIGNEE_TYPE.ME,
  },
});

const emit = defineEmits(['chatTabChange']);

const activeTabIndex = computed(() => {
  return props.items.findIndex(item => item.key === props.activeTab);
});

const onTabChange = selectedTabIndex => {
  if (selectedTabIndex >= 0 && selectedTabIndex < props.items.length) {
    const selectedItem = props.items[selectedTabIndex];
    if (selectedItem.key !== props.activeTab) {
      emit('chatTabChange', selectedItem.key);
    }
  }
};

const keyboardEvents = {
  'Alt+KeyN': {
    action: () => {
      if (props.activeTab === wootConstants.ASSIGNEE_TYPE.ALL) {
        onTabChange(0);
      } else {
        const nextIndex = (activeTabIndex.value + 1) % props.items.length;
        onTabChange(nextIndex);
      }
    },
  },
};

useKeyboardEvents(keyboardEvents);
</script>

<template>
  <!-- 用全站统一的「灰槽 + 深色选中块」页签（见 _next-colors.scss 的 data-tabbar）：
       容器挂标记、选中项用 aria-selected，颜色走 token，四套主题各取各的。
       page-block 是撑满容器那一档——会话列表这一栏只有 340px 宽，fit-content
       放不下 4 个页签会溢出；撑满均分反而每个都看得全。 -->
  <div class="px-3 pb-1 shrink-0">
    <div data-tabbar="page-block">
      <button
        v-for="(item, index) in items"
        :key="item.key"
        type="button"
        role="tab"
        :aria-selected="item.key === activeTab"
        class="flex items-center justify-center gap-1 whitespace-nowrap !px-2"
        @click="onTabChange(index)"
      >
        {{ item.name }}
        <span
          class="inline-grid h-4 min-w-4 place-items-center rounded-full px-1 text-xxs leading-none"
        >
          {{ item.count }}
        </span>
      </button>
    </div>
  </div>
</template>
