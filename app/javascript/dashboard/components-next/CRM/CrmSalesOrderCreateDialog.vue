<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useCrmCustomersStore } from 'dashboard/stores/crm/customers';

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
const customersStore = useCrmCustomersStore();

const today = () => new Date().toISOString().slice(0, 10);

const form = reactive({
  name: '',
  crmCustomerId: '',
  status: 'PENDING_CONFIRMATION',
  orderDate: today(),
  deliveryDate: '',
  amount: '',
  orderCurrency: 'CNY',
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

const customerOptions = computed(() =>
  customersStore.getCustomers.map(c => ({ value: String(c.id), label: c.name }))
);

const isEditing = computed(() => editingId.value !== null);
const isFormInvalid = computed(() => !form.name.trim() || !form.orderDate);

const resetForm = () => {
  editingId.value = null;
  form.deliveryDate = '';
  form.name = '';
  form.crmCustomerId = '';
  form.status = 'PENDING_CONFIRMATION';
  form.orderDate = today();
  form.amount = '';
  form.orderCurrency = 'CNY';
  form.remark = '';
};

const open = record => {
  resetForm();
  if (record) {
    editingId.value = record.id;
    form.name = record.name || '';
    form.crmCustomerId = record.crmCustomerId ? String(record.crmCustomerId) : '';
    form.status = record.status || 'PENDING_CONFIRMATION';
    form.orderDate = record.orderDate ? record.orderDate.slice(0, 10) : today();
    form.deliveryDate = record.deliveryDate ? record.deliveryDate.slice(0, 10) : '';
    form.amount = record.orderAmountMicros ? String(record.orderAmountMicros / 1_000_000) : '';
    form.orderCurrency = record.orderCurrency || 'CNY';
    form.remark = record.remark || '';
  }
  if (!customersStore.getCustomers.length) customersStore.get({ page: 1 });
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
    status: form.status,
    orderDate: form.orderDate,
    orderAmountMicros: form.amount
      ? Math.round(parseFloat(form.amount) * 1_000_000)
      : null,
    orderCurrency: form.orderCurrency,
    remark: form.remark.trim() || null,
    deliveryDate: form.deliveryDate || null,
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
      <Input
        v-model="form.name"
        :label="t('CRM.SALES_ORDERS.FORM.NAME')"
        autofocus
      />
      <div class="grid grid-cols-2 gap-4">
        <Select
          v-model="form.crmCustomerId"
          :label="t('CRM.SALES_ORDERS.FORM.CUSTOMER')"
          :options="customerOptions"
        />
        <Select
          v-model="form.status"
          :label="t('CRM.SALES_ORDERS.FORM.STATUS')"
          :options="statusOptions"
        />
      </div>
      <div class="grid grid-cols-3 gap-4">
        <Input
          v-model="form.orderDate"
          type="date"
          :label="t('CRM.SALES_ORDERS.FORM.ORDER_DATE')"
        />
        <Input
          v-model="form.amount"
          type="number"
          :label="t('CRM.SALES_ORDERS.FORM.AMOUNT')"
        />
        <Select
          v-model="form.orderCurrency"
          :label="t('CRM.SALES_ORDERS.FORM.CURRENCY')"
          :options="currencyOptions"
        />
      </div>
      <Input
        v-model="form.deliveryDate"
        type="date"
        label="交期"
      />
      <TextArea
        v-model="form.remark"
        :label="t('CRM.SALES_ORDERS.FORM.REMARK')"
      />
    </div>
  </Dialog>
</template>
