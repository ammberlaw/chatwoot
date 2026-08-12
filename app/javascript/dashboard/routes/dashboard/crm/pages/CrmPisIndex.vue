<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import camelcaseKeys from 'camelcase-keys';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import PisAPI from 'dashboard/api/crm/pis';

import Button from 'dashboard/components-next/button/Button.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import CrmPiFormDialog from 'dashboard/components-next/CRM/CrmPiFormDialog.vue';
import CrmPiSellerProfileDialog from 'dashboard/components-next/CRM/CrmPiSellerProfileDialog.vue';

const ITEMS_PER_PAGE = 15;

const { t } = useI18n();
const { accountId } = useAccount();

const records = ref([]);
const totalCount = ref(0);
const currentPage = ref(1);
const isFetching = ref(false);
const activeStatus = ref('');
const searchQuery = ref('');
const formRef = ref(null);
const sellerProfileRef = ref(null);

const STATUSES = {
  DRAFT: {
    label: t('CRM.PI.STATUS.DRAFT'),
    class: 'bg-n-slate-3 text-n-slate-11',
  },
  PAID: { label: t('CRM.PI.STATUS.PAID'), class: 'bg-n-teal-3 text-n-teal-11' },
  VOID: { label: t('CRM.PI.STATUS.VOID'), class: 'bg-n-ruby-3 text-n-ruby-11' },
};

const statusFilterOptions = [
  { value: '', label: t('CRM.PI.FILTERS.ALL_STATUS') },
  ...Object.entries(STATUSES).map(([value, { label }]) => ({ value, label })),
];

const CURRENCY_SYMBOL = { USD: 'US$', CNY: '¥', EUR: '€' };
const fmtMoney = (micros, currency) =>
  micros == null
    ? '—'
    : `${CURRENCY_SYMBOL[currency] || ''}${(micros / 1_000_000).toLocaleString(
        'en-US',
        { minimumFractionDigits: 2, maximumFractionDigits: 2 }
      )}`;
const fmtDate = v => (v ? String(v).slice(0, 10) : '—');

const fetchRecords = async () => {
  isFetching.value = true;
  try {
    const { data } = await PisAPI.list(accountId.value, {
      page: currentPage.value,
      status: activeStatus.value || undefined,
      q: searchQuery.value.trim() || undefined,
    });
    records.value = camelcaseKeys(data.payload || [], { deep: true });
    totalCount.value = data.meta?.count || 0;
  } catch {
    records.value = [];
  } finally {
    isFetching.value = false;
  }
};

let searchTimer = null;
const onSearchInput = () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => {
    currentPage.value = 1;
    fetchRecords();
  }, 300);
};
const setStatus = value => {
  activeStatus.value = value;
  currentPage.value = 1;
  fetchRecords();
};
const onPageChange = page => {
  currentPage.value = page;
  fetchRecords();
};

const openCreate = () => formRef.value?.open();
const openEdit = record => formRef.value?.open(record);
const openSellerProfile = () => sellerProfileRef.value?.open();
const onSaved = () => fetchRecords();

// 导出失败时取后端返回的具体提示（xlsx 走 blob，422 的 JSON 在 Blob 里）。
const extractError = async error => {
  const data = error?.response?.data;
  if (data instanceof Blob) {
    try {
      return JSON.parse(await data.text()).error;
    } catch {
      return null;
    }
  }
  return data?.error || null;
};

const exportingXlsxId = ref(null);
const exportXlsx = async record => {
  exportingXlsxId.value = record.id;
  try {
    const { data } = await PisAPI.xlsx(accountId.value, record.id);
    const url = URL.createObjectURL(data);
    const a = document.createElement('a');
    a.href = url;
    a.download = `PI-${record.piNo || 'export'}.xlsx`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  } catch (error) {
    const msg = await extractError(error);
    useAlert(msg || t('CRM.PI.EXPORT.XLSX_ERROR'));
  } finally {
    exportingXlsxId.value = null;
  }
};

const removeRecord = async record => {
  if (!window.confirm(t('CRM.PI.DELETE.CONFIRM', { no: record.piNo }))) return;
  try {
    await PisAPI.remove(accountId.value, record.id);
    useAlert(t('CRM.PI.DELETE.SUCCESS'));
    fetchRecords();
  } catch {
    useAlert(t('CRM.PI.DELETE.ERROR'));
  }
};

const buyerLabel = r => r.buyerCompany || r.customerName || '—';
const totalPages = computed(() => Math.ceil(totalCount.value / ITEMS_PER_PAGE));

onMounted(fetchRecords);
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-hidden">
    <div
      class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak"
    >
      <div>
        <h1 class="text-xl font-medium text-n-slate-12">
          {{ t('CRM.PI.HEADER') }}
        </h1>
        <p class="mt-0.5 text-xs text-n-slate-10">{{ t('CRM.PI.SUBTITLE') }}</p>
      </div>
      <div class="flex items-center gap-2">
        <Button
          :label="t('CRM.PI.SELLER_PROFILE.BUTTON')"
          icon="i-lucide-contact"
          variant="faded"
          color="slate"
          @click="openSellerProfile"
        />
        <Button
          :label="t('CRM.PI.NEW')"
          icon="i-lucide-plus"
          color="iris"
          @click="openCreate"
        />
      </div>
    </div>

    <div class="flex items-center gap-2 px-6 py-3 border-b border-n-weak">
      <SelectCard
        :model-value="activeStatus"
        :options="statusFilterOptions"
        class="w-40"
        @update:model-value="setStatus"
      />
      <Input
        v-model="searchQuery"
        :placeholder="t('CRM.PI.SEARCH_PLACEHOLDER')"
        class="ml-auto w-64"
        @input="onSearchInput"
      />
    </div>

    <div
      v-if="isFetching"
      class="flex items-center justify-center flex-1 text-sm text-n-slate-11"
    >
      {{ t('CRM.PI.LOADING') }}
    </div>
    <div
      v-else-if="!records.length"
      class="flex flex-col items-center justify-center flex-1 gap-2 text-n-slate-10"
    >
      <span class="i-lucide-file-text size-8 opacity-40" />
      <p class="text-sm">{{ t('CRM.PI.EMPTY') }}</p>
    </div>

    <div v-else class="flex-1 px-6 py-3 overflow-y-auto">
      <table class="w-full text-sm">
        <thead>
          <tr class="text-left border-b border-n-weak text-n-slate-10">
            <th class="py-2.5 pr-4 font-medium">{{ t('CRM.PI.COL.PI_NO') }}</th>
            <th class="py-2.5 pr-4 font-medium">{{ t('CRM.PI.COL.BUYER') }}</th>
            <th class="py-2.5 pr-4 font-medium">
              {{ t('CRM.PI.COL.AMOUNT') }}
            </th>
            <th class="py-2.5 pr-4 font-medium">
              {{ t('CRM.PI.COL.STATUS') }}
            </th>
            <th class="py-2.5 pr-4 font-medium">{{ t('CRM.PI.COL.DATE') }}</th>
            <th class="py-2.5 pr-4 font-medium">
              {{ t('CRM.PI.COL.CREATOR') }}
            </th>
            <th class="py-2.5 font-medium w-32" />
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="record in records"
            :key="record.id"
            class="border-b border-n-weak hover:bg-n-alpha-1"
          >
            <td class="py-2.5 pr-4 font-medium text-n-slate-12">
              {{ record.piNo }}
            </td>
            <td class="py-2.5 pr-4 text-n-slate-11">
              <span class="block truncate max-w-56">{{
                buyerLabel(record)
              }}</span>
            </td>
            <td class="py-2.5 pr-4 text-n-slate-12 tabular-nums">
              {{ fmtMoney(record.totalAmountMicros, record.currency) }}
            </td>
            <td class="py-2.5 pr-4">
              <span
                class="inline-flex px-2 py-0.5 text-xs rounded-md"
                :class="STATUSES[record.status]?.class"
              >
                {{ STATUSES[record.status]?.label || record.status }}
              </span>
            </td>
            <td class="py-2.5 pr-4 text-n-slate-11 tabular-nums">
              {{ fmtDate(record.piDate) }}
            </td>
            <td class="py-2.5 pr-4 text-n-slate-11">
              {{ record.ownerName || '—' }}
            </td>
            <td class="py-2.5">
              <div class="flex items-center justify-end gap-1">
                <button
                  type="button"
                  class="p-1.5 rounded text-n-slate-10 hover:text-n-teal-11 hover:bg-n-alpha-1 disabled:opacity-50"
                  :title="t('CRM.PI.ACTION.XLSX')"
                  :disabled="exportingXlsxId === record.id"
                  @click="exportXlsx(record)"
                >
                  <span
                    class="size-4"
                    :class="
                      exportingXlsxId === record.id
                        ? 'i-lucide-loader-circle animate-spin'
                        : 'i-lucide-sheet'
                    "
                  />
                </button>
                <button
                  type="button"
                  class="p-1.5 rounded text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-1"
                  :title="t('CRM.PI.ACTION.EDIT')"
                  @click="openEdit(record)"
                >
                  <span class="i-lucide-pencil size-4" />
                </button>
                <button
                  type="button"
                  class="p-1.5 rounded text-n-slate-10 hover:text-n-ruby-11 hover:bg-n-alpha-1"
                  :title="t('CRM.PI.ACTION.DELETE')"
                  @click="removeRecord(record)"
                >
                  <span class="i-lucide-trash-2 size-4" />
                </button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <PaginationFooter
      v-if="totalPages > 1"
      :current-page="currentPage"
      :total-items="totalCount"
      :items-per-page="ITEMS_PER_PAGE"
      class="flex-shrink-0 px-6 py-3 border-t border-n-weak"
      @update:current-page="onPageChange"
    />

    <CrmPiFormDialog ref="formRef" @saved="onSaved" />
    <CrmPiSellerProfileDialog ref="sellerProfileRef" />
  </div>
</template>
