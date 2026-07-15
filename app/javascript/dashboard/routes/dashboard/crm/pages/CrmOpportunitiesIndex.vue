<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCrmOpportunitiesStore } from 'dashboard/stores/crm/opportunities';
import { useCrmRole } from 'dashboard/composables/useCrmRole';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import CrmOpportunityCreateDialog from 'dashboard/components-next/CRM/CrmOpportunityCreateDialog.vue';

const { t } = useI18n();
const route = useRoute();
const store = useCrmOpportunitiesStore();

const createDialogRef = ref(null);
const { isCrmSales } = useCrmRole();
// 普通业务只看个人商机：无「全部」视图，默认落在「我的」。
const normalizeFilter = value =>
  isCrmSales.value && (!value || value === 'all') ? 'mine' : value || 'all';
const activeFilter = ref(normalizeFilter(route.query.filter));

const records = computed(() => store.getRecords);
const uiFlags = computed(() => store.getUIFlags);
const isFetching = computed(() => uiFlags.value.fetchingList);
const isCreating = computed(() => uiFlags.value.creatingItem);

const STAGES = {
  NEEDS_CONFIRMED: { label: '需求确认（已报价）', class: 'bg-n-blue-3 text-n-blue-11' },
  SAMPLING: { label: '样品中', class: 'bg-n-iris-3 text-n-iris-11' },
  WON: { label: '已成交', class: 'bg-n-teal-3 text-n-teal-11' },
  LOST: { label: '输单', class: 'bg-n-ruby-3 text-n-ruby-11' },
};

const LOSS_REASONS = {
  PRICE: '价格',
  DELIVERY: '交期',
  QUALITY: '质量',
  COMPETITOR: '竞品',
  CANCELLED: '客户取消',
  NEED_CHANGED: '需求变化',
};

const AVATAR = [
  'bg-n-blue-9',
  'bg-n-teal-9',
  'bg-n-iris-9',
  'bg-n-iris-9',
  'bg-n-ruby-9',
];
const avatarCls = name =>
  AVATAR[((name || '?').charCodeAt(0) || 0) % AVATAR.length];
const initial = name => (name || '?').trim().charAt(0).toUpperCase();

const filterTabs = computed(() => [
  ...(isCrmSales.value
    ? []
    : [{ key: 'all', label: t('CRM.OPPORTUNITIES.FILTERS.ALL') }]),
  { key: 'mine', label: t('CRM.OPPORTUNITIES.FILTERS.MINE') },
  { key: 'open', label: t('CRM.OPPORTUNITIES.FILTERS.OPEN') },
]);

const fetchRecords = () => {
  const filter = activeFilter.value === 'all' ? undefined : activeFilter.value;
  store.get({ page: 1, filter });
};

const setFilter = key => {
  activeFilter.value = key;
  fetchRecords();
};

const openEditDialog = record => createDialogRef.value?.open(record);

const removeRecord = async record => {
  if (!window.confirm(t('CRM.OPPORTUNITIES.DELETE.CONFIRM', { name: record.name })))
    return;
  try {
    await store.delete(record.id);
    useAlert(t('CRM.OPPORTUNITIES.DELETE.SUCCESS'));
    fetchRecords();
  } catch {
    useAlert(t('CRM.OPPORTUNITIES.DELETE.ERROR'));
  }
};

const updateRecord = async payload => {
  try {
    await store.update(payload);
    createDialogRef.value?.onSuccess();
    useAlert(t('CRM.OPPORTUNITIES.EDIT.SUCCESS'));
  } catch {
    useAlert(t('CRM.OPPORTUNITIES.EDIT.ERROR'));
  }
};

onMounted(fetchRecords);
watch(
  () => route.query.filter,
  value => {
    activeFilter.value = normalizeFilter(value);
    fetchRecords();
  }
);

const CURRENCY_SYMBOL = { CNY: '¥', USD: '$', EUR: '€' };
const fmtMoney = (micros, currency) =>
  micros == null
    ? '—'
    : `${CURRENCY_SYMBOL[currency] || ''}${Math.round(micros / 1_000_000).toLocaleString()}`;
const fmtDate = value => (value ? new Date(value).toLocaleDateString() : '—');
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5">
    <div
      class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak"
    >
      <h1 class="text-xl font-medium text-n-slate-12">
        {{ t('CRM.OPPORTUNITIES.HEADER') }}
      </h1>
    </div>

    <div class="flex items-center gap-2 px-6 py-3 border-b border-n-weak">
      <Button
        v-for="tab in filterTabs"
        :key="tab.key"
        :label="tab.label"
        size="sm"
        :variant="activeFilter === tab.key ? 'solid' : 'faded'"
        :color="activeFilter === tab.key ? 'iris' : 'slate'"
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
            <th class="px-3 py-2 font-medium text-right">
              {{ t('CRM.OPPORTUNITIES.TABLE.PROBABILITY') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.OPPORTUNITIES.TABLE.EXPECTED_CLOSE') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.OPPORTUNITIES.TABLE.OWNER') }}
            </th>
            <th class="px-3 py-2 font-medium text-right">
              {{ t('CRM.OPPORTUNITIES.TABLE.ACTIONS') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="record in records"
            :key="record.id"
            class="border-b cursor-pointer border-n-weak hover:bg-n-alpha-1"
            @click="openEditDialog(record)"
          >
            <td class="px-3 py-2 font-medium text-n-slate-12 whitespace-nowrap">
              <span
                v-if="record.important"
                class="inline-block i-lucide-star size-3.5 text-n-blue-9 me-1 align-[-2px]"
                :title="t('CRM.OPPORTUNITIES.IMPORTANT')"
              />
              {{ record.name }}
            </td>
            <td class="px-3 py-2 text-n-slate-11 whitespace-nowrap">
              {{ record.customerName || '—' }}
            </td>
            <td class="px-3 py-2 whitespace-nowrap">
              <span
                class="px-2 py-0.5 rounded text-xs font-medium"
                :class="STAGES[record.salesStage]?.class"
              >
                {{ STAGES[record.salesStage]?.label || record.salesStage }}
              </span>
              <span
                v-if="record.salesStage === 'LOST' && record.lossReason"
                class="ml-1 px-1.5 py-0.5 rounded text-xs bg-n-ruby-3 text-n-ruby-11"
              >
                {{ LOSS_REASONS[record.lossReason] || record.lossReason }}
              </span>
            </td>
            <td class="px-3 py-2 text-right text-n-slate-12 whitespace-nowrap">
              {{ fmtMoney(record.amountMicros, record.currency) }}
            </td>
            <td class="px-3 py-2 text-right text-n-slate-11">
              {{ record.probability != null ? `${record.probability}%` : '—' }}
            </td>
            <td class="px-3 py-2 text-n-slate-11 whitespace-nowrap">
              {{ fmtDate(record.expectedCloseDate) }}
            </td>
            <td class="px-3 py-2 whitespace-nowrap">
              <span
                v-if="record.ownerName"
                class="inline-flex items-center gap-1.5 text-n-slate-11"
              >
                <span
                  class="flex items-center justify-center w-5 h-5 text-xs font-semibold text-white rounded"
                  :class="avatarCls(record.ownerName)"
                >
                  {{ initial(record.ownerName) }}
                </span>
                {{ record.ownerName }}
              </span>
              <span v-else class="text-n-slate-10">—</span>
            </td>
            <td class="px-3 py-2 text-right whitespace-nowrap">
              <button
                type="button"
                :title="t('CRM.OPPORTUNITIES.DELETE.LABEL')"
                class="inline-flex items-center justify-center transition-colors rounded-md size-7 text-n-slate-10 hover:bg-n-ruby-3 hover:text-n-ruby-11"
                @click.stop="removeRecord(record)"
              >
                <Icon icon="i-lucide-trash-2" class="size-4" />
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <CrmOpportunityCreateDialog
      ref="createDialogRef"
      :is-loading="isCreating"
      @update="updateRecord"
    />
  </div>
</template>
