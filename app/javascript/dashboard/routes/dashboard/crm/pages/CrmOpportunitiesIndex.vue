<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCrmOpportunitiesStore } from 'dashboard/stores/crm/opportunities';

import Button from 'dashboard/components-next/button/Button.vue';
import CrmOpportunityCreateDialog from 'dashboard/components-next/CRM/CrmOpportunityCreateDialog.vue';

const { t } = useI18n();
const route = useRoute();
const store = useCrmOpportunitiesStore();

const createDialogRef = ref(null);
const activeFilter = ref(route.query.filter || 'all');

const records = computed(() => store.getRecords);
const uiFlags = computed(() => store.getUIFlags);
const isFetching = computed(() => uiFlags.value.fetchingList);
const isCreating = computed(() => uiFlags.value.creatingItem);

const STAGES = {
  INITIAL_CONTACT: { label: '初步接触', class: 'bg-n-slate-3 text-n-slate-11' },
  NEEDS_CONFIRMED: { label: '需求确认', class: 'bg-n-blue-3 text-n-blue-11' },
  QUOTED: { label: '已报价', class: 'bg-n-iris-3 text-n-iris-11' },
  NEGOTIATING: { label: '谈判中', class: 'bg-n-amber-3 text-n-amber-11' },
  SAMPLING: { label: '样品中', class: 'bg-n-amber-3 text-n-amber-11' },
  WON: { label: '已成交', class: 'bg-n-teal-3 text-n-teal-11' },
  LOST: { label: '已丢单', class: 'bg-n-ruby-3 text-n-ruby-11' },
};

const filterTabs = [
  { key: 'all', label: t('CRM.OPPORTUNITIES.FILTERS.ALL') },
  { key: 'mine', label: t('CRM.OPPORTUNITIES.FILTERS.MINE') },
  { key: 'open', label: t('CRM.OPPORTUNITIES.FILTERS.OPEN') },
];

const fetchRecords = () => {
  const filter = activeFilter.value === 'all' ? undefined : activeFilter.value;
  store.get({ page: 1, filter });
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
    useAlert(t('CRM.OPPORTUNITIES.CREATE.SUCCESS'));
  } catch {
    useAlert(t('CRM.OPPORTUNITIES.CREATE.ERROR'));
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

const fmtMoney = (micros, currency) =>
  micros == null
    ? '—'
    : `${currency || ''} ${(micros / 1_000_000).toLocaleString()}`;
const fmtDate = value => (value ? new Date(value).toLocaleDateString() : '—');
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-background">
    <div
      class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak"
    >
      <h1 class="text-xl font-medium text-n-slate-12">
        {{ t('CRM.OPPORTUNITIES.HEADER') }}
      </h1>
      <Button
        :label="t('CRM.OPPORTUNITIES.NEW')"
        icon="i-lucide-plus"
        color="blue"
        @click="openCreateDialog"
      />
    </div>

    <div class="flex items-center gap-2 px-6 py-3 border-b border-n-weak">
      <Button
        v-for="tab in filterTabs"
        :key="tab.key"
        :label="tab.label"
        size="sm"
        :variant="activeFilter === tab.key ? 'solid' : 'faded'"
        :color="activeFilter === tab.key ? 'blue' : 'slate'"
        @click="setFilter(tab.key)"
      />
    </div>

    <div class="flex-1 px-6 py-4">
      <div
        v-if="isFetching"
        class="flex items-center justify-center p-8 text-base text-n-slate-11"
      >
        {{ t('CRM.OPPORTUNITIES.LOADING') }}
      </div>
      <div
        v-else-if="!records.length"
        class="flex items-center justify-center p-8 text-base text-n-slate-11"
      >
        {{ t('CRM.OPPORTUNITIES.EMPTY') }}
      </div>
      <table v-else class="w-full text-sm text-left border-collapse">
        <thead class="text-n-slate-11">
          <tr class="border-b border-n-weak">
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.OPPORTUNITIES.TABLE.NAME') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.OPPORTUNITIES.TABLE.CUSTOMER') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.OPPORTUNITIES.TABLE.STAGE') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.OPPORTUNITIES.TABLE.AMOUNT') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.OPPORTUNITIES.TABLE.PROBABILITY') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.OPPORTUNITIES.TABLE.EXPECTED_CLOSE') }}
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
              {{ record.customerName || '—' }}
            </td>
            <td class="px-3 py-2">
              <span
                class="px-2 py-0.5 rounded-full text-xs font-medium"
                :class="STAGES[record.salesStage]?.class"
              >
                {{ STAGES[record.salesStage]?.label || record.salesStage }}
              </span>
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ fmtMoney(record.amountMicros, record.currency) }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ record.probability != null ? `${record.probability}%` : '—' }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ fmtDate(record.expectedCloseDate) }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <CrmOpportunityCreateDialog
      ref="createDialogRef"
      :is-loading="isCreating"
      @create="createRecord"
    />
  </div>
</template>
