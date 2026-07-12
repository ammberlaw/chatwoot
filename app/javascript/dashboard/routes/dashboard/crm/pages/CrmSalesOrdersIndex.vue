<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCrmSalesOrdersStore } from 'dashboard/stores/crm/salesOrders';

import Button from 'dashboard/components-next/button/Button.vue';
import CrmSalesOrderCreateDialog from 'dashboard/components-next/CRM/CrmSalesOrderCreateDialog.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';

// 与后端 SalesOrdersController::RESULTS_PER_PAGE 保持一致。
const ITEMS_PER_PAGE = 15;

const { t } = useI18n();
const route = useRoute();
const store = useCrmSalesOrdersStore();

const createDialogRef = ref(null);
const activeFilter = ref(route.query.filter || 'all');
const currentPage = ref(1);

const records = computed(() => store.getRecords);
const uiFlags = computed(() => store.getUIFlags);
const isFetching = computed(() => uiFlags.value.fetchingList);
const isCreating = computed(() => uiFlags.value.creatingItem);
const totalCount = computed(() => store.getMeta.count || 0);

const STATUSES = {
  PENDING_CONFIRMATION: { label: '待确认', class: 'bg-n-slate-3 text-n-slate-11' },
  IN_PRODUCTION: { label: '生产中', class: 'bg-n-blue-3 text-n-blue-11' },
  PENDING_SHIPMENT: { label: '待出货', class: 'bg-n-amber-3 text-n-amber-11' },
  SHIPPED: { label: '已出货', class: 'bg-n-iris-3 text-n-iris-11' },
  COMPLETED: { label: '已完成', class: 'bg-n-teal-3 text-n-teal-11' },
  CANCELLED: { label: '已取消', class: 'bg-n-ruby-3 text-n-ruby-11' },
};

const filterTabs = [
  { key: 'all', label: t('CRM.SALES_ORDERS.FILTERS.ALL') },
  { key: 'mine', label: t('CRM.SALES_ORDERS.FILTERS.MINE') },
  { key: 'no_customer', label: t('CRM.SALES_ORDERS.FILTERS.NO_CUSTOMER') },
];

const fetchRecords = () => {
  const filter = activeFilter.value === 'all' ? undefined : activeFilter.value;
  store.get({ page: currentPage.value, filter });
};

const setFilter = key => {
  activeFilter.value = key;
  currentPage.value = 1;
  fetchRecords();
};

const onPageChange = page => {
  currentPage.value = page;
  fetchRecords();
};

const openCreateDialog = () => createDialogRef.value?.open();
const openEditDialog = record => createDialogRef.value?.open(record);

const createRecord = async payload => {
  try {
    await store.create(payload);
    createDialogRef.value?.onSuccess();
    useAlert(t('CRM.SALES_ORDERS.CREATE.SUCCESS'));
  } catch {
    useAlert(t('CRM.SALES_ORDERS.CREATE.ERROR'));
  }
};

const updateRecord = async payload => {
  try {
    await store.update(payload);
    createDialogRef.value?.onSuccess();
    useAlert(t('CRM.SALES_ORDERS.EDIT.SUCCESS'));
  } catch {
    useAlert(t('CRM.SALES_ORDERS.EDIT.ERROR'));
  }
};

onMounted(fetchRecords);
watch(
  () => route.query.filter,
  value => {
    activeFilter.value = value || 'all';
    currentPage.value = 1;
    fetchRecords();
  }
);

const CURRENCY_SYMBOL = { CNY: '¥', USD: '$', EUR: '€' };
const fmtMoney = (micros, currency) =>
  micros == null
    ? '—'
    : `${CURRENCY_SYMBOL[currency] || ''}${Math.round(micros / 1_000_000).toLocaleString()}`;
const fmtDate = value => (value ? new Date(value).toLocaleDateString() : '—');

const AVATAR = [
  'bg-n-blue-9',
  'bg-n-teal-9',
  'bg-n-iris-9',
  'bg-n-amber-9',
  'bg-n-ruby-9',
];
const avatarCls = name =>
  AVATAR[((name || '?').charCodeAt(0) || 0) % AVATAR.length];
const initial = name => (name || '?').trim().charAt(0).toUpperCase();
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-background">
    <div
      class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak"
    >
      <h1 class="text-xl font-medium text-n-slate-12">
        {{ t('CRM.SALES_ORDERS.HEADER') }}
      </h1>
      <Button
        :label="t('CRM.SALES_ORDERS.NEW')"
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

    <div class="flex-1 px-6 py-4 overflow-auto">
      <div
        v-if="isFetching"
        class="flex items-center justify-center p-8 text-base text-n-slate-11"
      >
        {{ t('CRM.SALES_ORDERS.LOADING') }}
      </div>
      <div
        v-else-if="!records.length"
        class="flex items-center justify-center p-8 text-base text-n-slate-11"
      >
        {{ t('CRM.SALES_ORDERS.EMPTY') }}
      </div>
      <table v-else class="w-full text-sm text-left border-collapse">
        <thead class="text-n-slate-11">
          <tr class="border-b border-n-weak">
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.SALES_ORDERS.TABLE.NAME') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.SALES_ORDERS.TABLE.ORDER_NO') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.SALES_ORDERS.TABLE.CUSTOMER') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.SALES_ORDERS.TABLE.STATUS') }}
            </th>
            <th class="px-3 py-2 font-medium text-right">
              {{ t('CRM.SALES_ORDERS.TABLE.AMOUNT') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.SALES_ORDERS.TABLE.ORDER_DATE') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.SALES_ORDERS.TABLE.DELIVERY_DATE') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.SALES_ORDERS.TABLE.OWNER') }}
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
              {{ record.name }}
            </td>
            <td class="px-3 py-2 text-n-slate-11 whitespace-nowrap">
              {{ record.orderNo }}
            </td>
            <td class="px-3 py-2 text-n-slate-11 whitespace-nowrap">
              {{ record.customerName || '—' }}
            </td>
            <td class="px-3 py-2 whitespace-nowrap">
              <span
                class="px-2 py-0.5 rounded text-xs font-medium"
                :class="STATUSES[record.status]?.class"
              >
                {{ STATUSES[record.status]?.label || record.status }}
              </span>
            </td>
            <td class="px-3 py-2 text-right text-n-slate-12 whitespace-nowrap">
              {{ fmtMoney(record.orderAmountMicros, record.orderCurrency) }}
            </td>
            <td class="px-3 py-2 text-n-slate-11 whitespace-nowrap">
              {{ fmtDate(record.orderDate) }}
            </td>
            <td class="px-3 py-2 text-n-slate-11 whitespace-nowrap">
              {{ fmtDate(record.deliveryDate) }}
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
          </tr>
        </tbody>
      </table>
    </div>

    <PaginationFooter
      v-if="totalCount > ITEMS_PER_PAGE"
      :current-page="currentPage"
      :total-items="totalCount"
      :items-per-page="ITEMS_PER_PAGE"
      class="flex-shrink-0"
      @update:current-page="onPageChange"
    />

    <CrmSalesOrderCreateDialog
      ref="createDialogRef"
      :is-loading="isCreating"
      @create="createRecord"
      @update="updateRecord"
      @refresh="fetchRecords"
    />
  </div>
</template>
