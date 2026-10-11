<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCrmSalesTargetsStore } from 'dashboard/stores/crm/salesTargets';

import Button from 'dashboard/components-next/button/Button.vue';
import CrmSalesTargetCreateDialog from 'dashboard/components-next/CRM/CrmSalesTargetCreateDialog.vue';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
const { t } = useI18n();
const route = useRoute();
const store = useCrmSalesTargetsStore();

const createDialogRef = ref(null);
const activeFilter = ref(route.query.filter || 'all');

const records = computed(() => store.getRecords);
const uiFlags = computed(() => store.getUIFlags);
const isFetching = computed(() => uiFlags.value.fetchingList);
const isCreating = computed(() => uiFlags.value.creatingItem);

const filterTabs = [
  { key: 'all', label: t('CRM.SALES_TARGETS.FILTERS.ALL') },
  { key: 'mine', label: t('CRM.SALES_TARGETS.FILTERS.MINE') },
];

const fetchRecords = () => {
  const filter = activeFilter.value === 'all' ? undefined : activeFilter.value;
  store.get({ filter });
};

const setFilter = key => {
  activeFilter.value = key;
  fetchRecords();
};

const openCreateDialog = () => createDialogRef.value?.open();

const createRecord = async payload => {
  try {
    await store.create(payload);
    createDialogRef.value?.onSuccess();
    useAlert(t('CRM.SALES_TARGETS.CREATE.SUCCESS'));
  } catch {
    useAlert(t('CRM.SALES_TARGETS.CREATE.ERROR'));
  }
};

onMounted(fetchRecords);
watch(
  () => route.query.filter,
  value => {
    activeFilter.value = value || 'all';
    fetchRecords();
  }
);

const fmtMonth = value => {
  if (!value) return '—';
  const d = new Date(value);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
};
const fmtMoney = micros =>
  micros == null ? '—' : `¥ ${(micros / 1_000_000).toLocaleString()}`;
</script>

<template>
  <HScrollButtons />
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div
      class="flex items-center justify-between flex-shrink-0 px-4 py-3 sm:px-6 sm:py-4 border-b border-n-weak [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:sm:!px-8"
    >
      <h1 class="text-xl font-medium text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8">
        {{ t('CRM.SALES_TARGETS.HEADER') }}
      </h1>
      <Button
        :label="t('CRM.SALES_TARGETS.NEW')"
        icon="i-lucide-plus"
        color="iris"
        @click="openCreateDialog"
      />
    </div>

    <div
      class="flex flex-wrap items-center gap-2 px-4 py-3 sm:px-6 border-b border-n-weak [.theme-classic_&]:sm:!px-8"
    >
      <div class="contents" data-tabbar="page" data-tabbar-theme="classic">
        <Button
          v-for="tab in filterTabs"
          :key="tab.key"
          :label="tab.label"
          size="sm"
          :aria-selected="activeFilter === tab.key"
          :variant="activeFilter === tab.key ? 'solid' : 'faded'"
          :color="activeFilter === tab.key ? 'iris' : 'slate'"
          @click="setFilter(tab.key)"
        />
      </div>
    </div>

    <div class="flex-1 px-4 py-3 sm:px-6 sm:py-4 [.theme-classic_&]:sm:!px-8">
      <div
        v-if="isFetching"
        class="flex items-center justify-center p-8 text-base text-n-slate-11"
      >
        {{ t('CRM.SALES_TARGETS.LOADING') }}
      </div>
      <div
        v-else-if="!records.length"
        class="flex items-center justify-center p-8 text-base text-n-slate-11"
      >
        {{ t('CRM.SALES_TARGETS.EMPTY') }}
      </div>
      <template v-else>
        <div class="flex flex-col gap-2 md:hidden">
          <div
            v-for="record in records"
            :key="record.id"
            class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl active:bg-n-alpha-1"
          >
            <div class="flex items-center gap-2">
              <span class="font-medium text-n-slate-12 truncate">
                {{ record.name }}
              </span>
            </div>
            <div
              class="flex flex-wrap gap-x-3 gap-y-1 mt-2 text-xs text-n-slate-11"
            >
              <span>
                {{ t('CRM.SALES_TARGETS.TABLE.MONTH') }}:
                {{ fmtMonth(record.targetMonth) }}
              </span>
              <span>
                {{ t('CRM.SALES_TARGETS.TABLE.AMOUNT') }}:
                {{ fmtMoney(record.targetAmountMicros) }}
              </span>
              <span>
                {{ t('CRM.SALES_TARGETS.TABLE.NEW_CUSTOMERS') }}:
                {{ record.targetOrderCount ?? '—' }}
              </span>
            </div>
          </div>
        </div>
        <table class="hidden md:table w-full text-sm text-left border-collapse">
          <thead class="text-n-slate-11">
            <tr class="border-b border-n-weak">
              <th class="px-3 py-2 font-medium">
                {{ t('CRM.SALES_TARGETS.TABLE.NAME') }}
              </th>
              <th class="px-3 py-2 font-medium">
                {{ t('CRM.SALES_TARGETS.TABLE.MONTH') }}
              </th>
              <th class="px-3 py-2 font-medium">
                {{ t('CRM.SALES_TARGETS.TABLE.AMOUNT') }}
              </th>
              <th class="px-3 py-2 font-medium">
                {{ t('CRM.SALES_TARGETS.TABLE.NEW_CUSTOMERS') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="record in records"
              :key="record.id"
              class="border-b border-n-weak hover:bg-n-alpha-1"
            >
              <td class="px-3 py-2 font-medium text-n-slate-12">
                {{ record.name }}
              </td>
              <td class="px-3 py-2 text-n-slate-11">
                {{ fmtMonth(record.targetMonth) }}
              </td>
              <td class="px-3 py-2 text-n-slate-11">
                {{ fmtMoney(record.targetAmountMicros) }}
              </td>
              <td class="px-3 py-2 text-n-slate-11">
                {{ record.targetOrderCount ?? '—' }}
              </td>
            </tr>
          </tbody>
        </table>
      </template>
    </div>

    <CrmSalesTargetCreateDialog
      ref="createDialogRef"
      :is-loading="isCreating"
      @create="createRecord"
    />
  </div>
</template>
