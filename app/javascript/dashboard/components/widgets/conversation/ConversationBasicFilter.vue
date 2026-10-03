<script setup>
import { computed, ref, nextTick, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useToggle } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useMapGetter, useStore } from 'dashboard/composables/store.js';
import wootConstants from 'dashboard/constants/globals';
import SelectMenu from 'dashboard/components-next/selectmenu/SelectMenu.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

defineProps({
  isOnExpandedLayout: {
    type: Boolean,
    required: true,
  },
});

const emit = defineEmits(['changeFilter']);

const store = useStore();
const { t } = useI18n();

const { updateUISettings } = useUISettings();

const chatStatusFilter = useMapGetter('getChatStatusFilter');
const chatSortFilter = useMapGetter('getChatSortFilter');

const [showActionsDropdown, toggleDropdown] = useToggle();

// 这个下拉原来是 absolute 定位、长在会话列表那一栏里，而那一栏是 overflow-hidden 的
// 玻璃卡片（backdrop-filter），下拉一宽就被裁掉右半边（「按顺序排序」只剩「按顺序排」）。
// 和高级过滤面板同一套解法：teleport 到 body、改 fixed、按触发按钮的位置算坐标。
const triggerRef = ref(null);
const panelStyle = ref({});

const placePanel = () => {
  const el = triggerRef.value?.$el || triggerRef.value;
  if (!el) return;
  const r = el.getBoundingClientRect();
  const width = 288; // w-72
  // 贴着按钮右边缘展开，并且不许超出视口左右两侧。
  const left = Math.min(
    Math.max(8, r.right - width),
    window.innerWidth - width - 8
  );
  panelStyle.value = { top: `${r.bottom + 4}px`, left: `${left}px` };
};

const onToggle = async () => {
  toggleDropdown();
  if (!showActionsDropdown.value) return;
  await nextTick();
  placePanel();
};

// 面板是 fixed 的，页面一滚/一改尺寸它不会自己跟着走，得重新算。
window.addEventListener('resize', placePanel);
window.addEventListener('scroll', placePanel, true);
onBeforeUnmount(() => {
  window.removeEventListener('resize', placePanel);
  window.removeEventListener('scroll', placePanel, true);
});

const currentStatusFilter = computed(() => {
  return chatStatusFilter.value || wootConstants.STATUS_TYPE.OPEN;
});

const currentSortBy = computed(() => {
  return (
    chatSortFilter.value || wootConstants.SORT_BY_TYPE.LAST_ACTIVITY_AT_DESC
  );
});

const chatStatusOptions = computed(() => [
  {
    label: t('CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.open.TEXT'),
    value: 'open',
  },
  {
    label: t('CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.resolved.TEXT'),
    value: 'resolved',
  },
  {
    label: t('CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.pending.TEXT'),
    value: 'pending',
  },
  {
    label: t('CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.snoozed.TEXT'),
    value: 'snoozed',
  },
  {
    label: t('CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.all.TEXT'),
    value: 'all',
  },
]);

const chatSortOptions = computed(() => [
  {
    label: t('CHAT_LIST.SORT_ORDER_ITEMS.last_activity_at_asc.TEXT'),
    value: 'last_activity_at_asc',
  },
  {
    label: t('CHAT_LIST.SORT_ORDER_ITEMS.last_activity_at_desc.TEXT'),
    value: 'last_activity_at_desc',
  },
  {
    label: t('CHAT_LIST.SORT_ORDER_ITEMS.created_at_desc.TEXT'),
    value: 'created_at_desc',
  },
  {
    label: t('CHAT_LIST.SORT_ORDER_ITEMS.created_at_asc.TEXT'),
    value: 'created_at_asc',
  },
  {
    label: t('CHAT_LIST.SORT_ORDER_ITEMS.unread.TEXT'),
    value: 'unread',
  },
  {
    label: t('CHAT_LIST.SORT_ORDER_ITEMS.priority_desc.TEXT'),
    value: 'priority_desc',
  },
  {
    label: t('CHAT_LIST.SORT_ORDER_ITEMS.priority_asc.TEXT'),
    value: 'priority_asc',
  },
  {
    label: t('CHAT_LIST.SORT_ORDER_ITEMS.priority_desc_created_at_asc.TEXT'),
    value: 'priority_desc_created_at_asc',
  },
  {
    label: t('CHAT_LIST.SORT_ORDER_ITEMS.waiting_since_asc.TEXT'),
    value: 'waiting_since_asc',
  },
  {
    label: t('CHAT_LIST.SORT_ORDER_ITEMS.waiting_since_desc.TEXT'),
    value: 'waiting_since_desc',
  },
]);

const activeChatStatusLabel = computed(
  () =>
    chatStatusOptions.value.find(m => m.value === chatStatusFilter.value)
      ?.label || ''
);

const activeChatSortLabel = computed(
  () =>
    chatSortOptions.value.find(m => m.value === chatSortFilter.value)?.label ||
    ''
);

const saveSelectedFilter = (type, value) => {
  updateUISettings({
    conversations_filter_by: {
      status: type === 'status' ? value : currentStatusFilter.value,
      order_by: type === 'sort' ? value : currentSortBy.value,
    },
  });
};

const handleStatusChange = value => {
  emit('changeFilter', value, 'status');
  store.dispatch('setChatStatusFilter', value);
  saveSelectedFilter('status', value);
};

const handleSortChange = value => {
  emit('changeFilter', value, 'sort');
  store.dispatch('setChatSortFilter', value);
  saveSelectedFilter('sort', value);
};
</script>

<template>
  <div class="relative flex">
    <NextButton
      ref="triggerRef"
      v-tooltip.right="$t('CHAT_LIST.SORT_TOOLTIP_LABEL')"
      icon="i-lucide-arrow-up-down"
      slate
      faded
      xs
      @click="onToggle"
    />
    <Teleport to="body">
      <div
        v-if="showActionsDropdown"
        v-on-click-outside="[
          () => toggleDropdown(false),
          { ignore: [triggerRef] },
        ]"
        class="bg-n-alpha-3 backdrop-blur-[100px] border border-n-weak w-72 rounded-xl p-4 fixed z-[60]"
        :style="panelStyle"
      >
        <div class="flex items-center justify-between last:mt-4 gap-2">
          <span class="text-sm truncate text-n-slate-12">
            {{ $t('CHAT_LIST.CHAT_SORT.STATUS') }}
          </span>
          <SelectMenu
            :model-value="chatStatusFilter"
            :options="chatStatusOptions"
            :label="activeChatStatusLabel"
            :sub-menu-position="isOnExpandedLayout ? 'left' : 'right'"
            @update:model-value="handleStatusChange"
          />
        </div>
        <div class="flex items-center justify-between last:mt-4 gap-2">
          <span class="text-sm truncate text-n-slate-12">
            {{ $t('CHAT_LIST.CHAT_SORT.ORDER_BY') }}
          </span>
          <SelectMenu
            :model-value="chatSortFilter"
            :options="chatSortOptions"
            :label="activeChatSortLabel"
            :sub-menu-position="isOnExpandedLayout ? 'left' : 'right'"
            @update:model-value="handleSortChange"
          />
        </div>
      </div>
    </Teleport>
  </div>
</template>
