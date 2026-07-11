<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useCrmCustomersStore } from 'dashboard/stores/crm/customers';
import { useCrmOpportunitiesStore } from 'dashboard/stores/crm/opportunities';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

defineProps({
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['create', 'update']);

const { t } = useI18n();
const dialogRef = ref(null);
const editingId = ref(null);
const orderNo = ref('');
const customersStore = useCrmCustomersStore();
const opportunitiesStore = useCrmOpportunitiesStore();

const today = () => new Date().toISOString().slice(0, 10);

const form = reactive({
  name: '',
  crmCustomerId: '',
  crmOpportunityId: '',
  status: 'PENDING_CONFIRMATION',
  orderDate: today(),
  deliveryDate: '',
  amount: '',
  cost: '',
  orderCurrency: 'CNY',
  exchangeRate: '',
  remark: '',
});

const statusOptions = [
  { value: 'PENDING_CONFIRMATION', label: '待确认' },
  { value: 'IN_PRODUCTION', label: '生产中' },
  { value: 'PENDING_SHIPMENT', label: '待出货' },
  { value: 'SHIPPED', label: '已出货' },
  { value: 'COMPLETED', label: '已完成' },
  { value: 'CANCELLED', label: '已取消' },
];

const currencyOptions = ['CNY', 'USD', 'EUR'].map(v => ({
  value: v,
  label: v,
}));

const CURRENCY_SYMBOL = { CNY: '¥', USD: '$', EUR: '€' };

const customerOptions = computed(() =>
  customersStore.getCustomers.map(c => ({ value: String(c.id), label: c.name }))
);

// 关联商机：选了客户则只显示该客户的商机，否则显示全部
const opportunityOptions = computed(() => {
  const records = opportunitiesStore.getRecords || [];
  const filtered = form.crmCustomerId
    ? records.filter(o => String(o.crmCustomerId) === String(form.crmCustomerId))
    : records;
  return [
    { value: '', label: '— 无 —' },
    ...filtered.map(o => ({ value: String(o.id), label: o.name })),
  ];
});

// 利润 = 订单金额 - 成本金额；利润率 = 利润 / 订单金额 × 100
const profit = computed(() => {
  const a = parseFloat(form.amount);
  const c = parseFloat(form.cost);
  if (Number.isNaN(a)) return null;
  return a - (Number.isNaN(c) ? 0 : c);
});
const profitRate = computed(() => {
  const a = parseFloat(form.amount);
  if (Number.isNaN(a) || a === 0 || profit.value == null) return null;
  return Math.round((profit.value / a) * 10000) / 100;
});
const profitDisplay = computed(() =>
  profit.value == null
    ? '—'
    : `${CURRENCY_SYMBOL[form.orderCurrency] || ''}${profit.value.toLocaleString()}`
);
const profitRateDisplay = computed(() =>
  profitRate.value == null ? '—' : `${profitRate.value}%`
);

const isEditing = computed(() => editingId.value !== null);
const isFormInvalid = computed(() => !form.name.trim() || !form.orderDate);

const resetForm = () => {
  editingId.value = null;
  orderNo.value = '';
  form.name = '';
  form.crmCustomerId = '';
  form.crmOpportunityId = '';
  form.status = 'PENDING_CONFIRMATION';
  form.orderDate = today();
  form.deliveryDate = '';
  form.amount = '';
  form.cost = '';
  form.orderCurrency = 'CNY';
  form.exchangeRate = '';
  form.remark = '';
};

const open = record => {
  resetForm();
  if (record) {
    editingId.value = record.id;
    orderNo.value = record.orderNo || '';
    form.name = record.name || '';
    form.crmCustomerId = record.crmCustomerId ? String(record.crmCustomerId) : '';
    form.crmOpportunityId = record.crmOpportunityId ? String(record.crmOpportunityId) : '';
    form.status = record.status || 'PENDING_CONFIRMATION';
    form.orderDate = record.orderDate ? record.orderDate.slice(0, 10) : today();
    form.deliveryDate = record.deliveryDate ? record.deliveryDate.slice(0, 10) : '';
    form.amount = record.orderAmountMicros ? String(record.orderAmountMicros / 1_000_000) : '';
    form.cost = record.costAmountMicros ? String(record.costAmountMicros / 1_000_000) : '';
    form.orderCurrency = record.orderCurrency || 'CNY';
    form.exchangeRate = record.exchangeRate != null ? String(record.exchangeRate) : '';
    form.remark = record.remark || '';
  }
  if (!customersStore.getCustomers.length) customersStore.get({ page: 1 });
  if (!opportunitiesStore.getRecords.length) {
    opportunitiesStore.get({ page: 1, perPage: 100 });
  }
  dialogRef.value?.open();
};

const onSuccess = () => {
  resetForm();
  dialogRef.value?.close();
};

const handleConfirm = () => {
  if (isFormInvalid.value) return;

  const payload = {
    name: form.name.trim(),
    crmCustomerId: form.crmCustomerId || null,
    crmOpportunityId: form.crmOpportunityId || null,
    status: form.status,
    orderDate: form.orderDate,
    deliveryDate: form.deliveryDate || null,
    orderAmountMicros: form.amount
      ? Math.round(parseFloat(form.amount) * 1_000_000)
      : null,
    costAmountMicros: form.cost
      ? Math.round(parseFloat(form.cost) * 1_000_000)
      : null,
    profitAmountMicros:
      profit.value == null ? null : Math.round(profit.value * 1_000_000),
    profitRate: profitRate.value,
    orderCurrency: form.orderCurrency,
    exchangeRate: form.exchangeRate ? parseFloat(form.exchangeRate) : null,
    remark: form.remark.trim() || null,
  };
  if (isEditing.value) {
    emit('update', { id: editingId.value, ...payload });
  } else {
    emit('create', payload);
  }
};

defineExpose({ dialogRef, onSuccess, open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="3xl"
    overflow-y-auto
    :title="isEditing ? t('CRM.SALES_ORDERS.EDIT.TITLE') : t('CRM.SALES_ORDERS.CREATE.TITLE')"
    :description="t('CRM.SALES_ORDERS.CREATE.DESCRIPTION')"
    :is-loading="isLoading"
    @confirm="handleConfirm"
    @close="resetForm"
  >
    <div class="flex flex-col gap-4">
      <div class="grid grid-cols-2 gap-4">
        <Input
          v-model="form.name"
          :label="t('CRM.SALES_ORDERS.FORM.NAME')"
          autofocus
        />
        <div v-if="isEditing" class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CRM.SALES_ORDERS.FORM.ORDER_NO') }}
          </label>
          <div
            class="flex items-center h-10 px-3 text-sm rounded-lg bg-n-slate-3 text-n-slate-11"
          >
            {{ orderNo }}
          </div>
        </div>
      </div>

      <div class="grid grid-cols-2 gap-4">
        <Select
          v-model="form.crmCustomerId"
          :label="t('CRM.SALES_ORDERS.FORM.CUSTOMER')"
          :options="customerOptions"
        />
        <Select
          v-model="form.crmOpportunityId"
          :label="t('CRM.SALES_ORDERS.FORM.OPPORTUNITY')"
          :options="opportunityOptions"
        />
      </div>

      <div class="grid grid-cols-3 gap-4">
        <Select
          v-model="form.status"
          :label="t('CRM.SALES_ORDERS.FORM.STATUS')"
          :options="statusOptions"
        />
        <Input
          v-model="form.orderDate"
          type="date"
          :label="t('CRM.SALES_ORDERS.FORM.ORDER_DATE')"
        />
        <Input
          v-model="form.deliveryDate"
          type="date"
          :label="t('CRM.SALES_ORDERS.FORM.DELIVERY_DATE')"
        />
      </div>

      <div class="grid grid-cols-3 gap-4">
        <Input
          v-model="form.amount"
          type="number"
          :label="t('CRM.SALES_ORDERS.FORM.AMOUNT')"
        />
        <Input
          v-model="form.cost"
          type="number"
          :label="t('CRM.SALES_ORDERS.FORM.COST')"
        />
        <Select
          v-model="form.orderCurrency"
          :label="t('CRM.SALES_ORDERS.FORM.CURRENCY')"
          :options="currencyOptions"
        />
      </div>

      <div class="grid grid-cols-3 gap-4">
        <Input
          v-model="form.exchangeRate"
          type="number"
          :label="t('CRM.SALES_ORDERS.FORM.EXCHANGE_RATE')"
        />
        <div class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CRM.SALES_ORDERS.FORM.PROFIT') }}
          </label>
          <div
            class="flex items-center h-10 px-3 text-sm font-medium rounded-lg bg-n-teal-2 text-n-teal-11"
          >
            {{ profitDisplay }}
          </div>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CRM.SALES_ORDERS.FORM.PROFIT_RATE') }}
          </label>
          <div
            class="flex items-center h-10 px-3 text-sm font-medium rounded-lg bg-n-teal-2 text-n-teal-11"
          >
            {{ profitRateDisplay }}
          </div>
        </div>
      </div>

      <TextArea
        v-model="form.remark"
        :label="t('CRM.SALES_ORDERS.FORM.REMARK')"
      />
    </div>
  </Dialog>
</template>
