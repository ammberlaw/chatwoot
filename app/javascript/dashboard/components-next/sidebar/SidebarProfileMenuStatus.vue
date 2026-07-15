<script setup>
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import wootConstants from 'dashboard/constants/globals';
import { useI18n } from 'vue-i18n';

import { DropdownSection, DropdownItem } from 'next/dropdown-menu/base';
import Icon from 'next/icon/Icon.vue';

const { t } = useI18n();
const currentUser = useMapGetter('getCurrentUser');
const currentAccountId = useMapGetter('getCurrentAccountId');

// 取 presence 派生的实时状态（availability_status），而非手动配置值。
const currentUserAvailability = computed(() => {
  const { accounts = [] } = currentUser.value || {};
  const account = accounts.find(a => a.id === currentAccountId.value) || {};
  return account.availability_status || account.availability;
});

const { AVAILABILITY_STATUS_KEYS } = wootConstants;
const statusList = computed(() => {
  return [
    t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.ONLINE'),
    t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.BUSY'),
    t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.OFFLINE'),
  ];
});

const statusColors = ['bg-n-teal-9', 'bg-n-amber-9', 'bg-n-slate-9'];

// 状态由系统按实时连接判定，成员不可手动设置。
const activeStatus = computed(() => {
  const index = AVAILABILITY_STATUS_KEYS.indexOf(currentUserAvailability.value);
  const safeIndex = index === -1 ? 2 : index;
  return {
    label: statusList.value[safeIndex],
    color: statusColors[safeIndex],
  };
});
</script>

<template>
  <DropdownSection>
    <DropdownItem class="gap-1">
      <div class="flex-grow flex items-center gap-1 min-w-0">
        当前状态
        <Icon
          v-tooltip.top="'在线/离线由系统实时判定，无需手动设置'"
          icon="i-lucide-info"
          class="inline-block align-middle ms-1 size-4 text-n-slate-10"
        />
      </div>
      <div class="flex gap-1.5 items-center shrink-0 text-sm text-n-slate-12">
        <div class="size-2 rounded-sm" :class="activeStatus.color" />
        {{ activeStatus.label }}
      </div>
    </DropdownItem>
  </DropdownSection>
</template>
