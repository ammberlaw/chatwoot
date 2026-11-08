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
  <!-- 保留全站灰槽页签样式；窄栏单行滚动，避免最后一项单独换行。 -->
  <div class="px-3 pb-1 shrink-0">
    <div
      data-tabbar="page-block"
      class="!flex-nowrap overflow-x-auto"
    >
      <button
        v-for="(item, index) in items"
        :key="item.key"
        type="button"
        role="tab"
        :aria-selected="item.key === activeTab"
        class="flex items-center justify-center gap-0.5 whitespace-nowrap !flex-[1_0_auto] !px-1"
        @click="onTabChange(index)"
      >
        {{ item.name }}
        <span
          class="inline-grid h-4 min-w-3.5 place-items-center rounded-full px-0.5 text-xxs leading-none"
        >
          {{ item.count }}
        </span>
      </button>
    </div>
  </div>
</template>
