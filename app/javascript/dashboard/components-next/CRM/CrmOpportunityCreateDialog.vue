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

const form = reactive({
  name: '',
  crmCustomerId: '',
  salesStage: 'NEEDS_CONFIRMED',
  amount: '',
  currency: 'USD',
  probability: '',
  expectedCloseDate: '',
  opportunityRemark: '',
  lossReason: '',
});

const stageOptions = [
  { value: 'NEEDS_CONFIRMED', label: '需求确认（已报价）' },
  { value: 'SAMPLING', label: '样品中' },
  { value: 'WON', label: '已成交' },
  { value: 'LOST', label: '输单' },
];

const currencyOptions = ['USD', 'CNY', 'EUR'].map(v => ({
  value: v,
  label: v,
}));

const customerOptions = computed(() =>
  customersStore.getCustomers.map(c => ({ value: String(c.id), label: c.name }))
);

const lossReasonOptions = [
  { value: 'PRICE', label: '价格原因' },
  { value: 'DELIVERY', label: '交期原因' },
  { value: 'QUALITY', label: '质量原因' },
  { value: 'COMPETITOR', label: '竞品成交' },
  { value: 'CANCELLED', label: '客户取消' },
  { value: 'NEED_CHANGED', label: '需求变化' },
];

const isEditing = computed(() => editingId.value !== null);
const isFormInvalid = computed(() => !form.name.trim());

const resetForm = () => {
  editingId.value = null;
  form.lossReason = '';
  form.name = '';
  form.crmCustomerId = '';
  form.salesStage = 'NEEDS_CONFIRMED';
  form.amount = '';
  form.currency = 'USD';
  form.probability = '';
  form.expectedCloseDate = '';
  form.opportunityRemark = '';
};

const open = record => {
  resetForm();
  if (record) {
    editingId.value = record.id;
    form.name = record.name || '';
    form.crmCustomerId = record.crmCustomerId ? String(record.crmCustomerId) : '';
    form.salesStage = record.salesStage || 'NEEDS_CONFIRMED';
    form.amount = record.amountMicros ? String(record.amountMicros / 1_000_000) : '';
    form.currency = record.currency || 'USD';
    form.probability = record.probability != null ? String(record.probability) : '';
    form.expectedCloseDate = record.expectedCloseDate ? record.expectedCloseDate.slice(0, 10) : '';
    form.opportunityRemark = record.opportunityRemark || '';
    form.lossReason = record.lossReason || '';
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
    salesStage: form.salesStage,
    amountMicros: form.amount
      ? Math.round(parseFloat(form.amount) * 1_000_000)
      : null,
    currency: form.currency,
    probability: form.probability ? Number(form.probability) : null,
    expectedCloseDate: form.expectedCloseDate || null,
    opportunityRemark: form.opportunityRemark.trim() || null,
    lossReason: form.lossReason || null,
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
    :title="isEditing ? t('CRM.OPPORTUNITIES.EDIT.TITLE') : t('CRM.OPPORTUNITIES.CREATE.TITLE')"
    :is-loading="isLoading"
    @confirm="handleConfirm"
    @close="resetForm"
  >
    <div class="flex flex-col gap-4">
      <Input
        v-model="form.name"
        :label="t('CRM.OPPORTUNITIES.FORM.NAME')"
        :placeholder="t('CRM.OPPORTUNITIES.FORM.NAME_PLACEHOLDER')"
      />
      <div class="grid grid-cols-2 gap-4">
        <Select
          v-model="form.crmCustomerId"
          :label="t('CRM.OPPORTUNITIES.FORM.CUSTOMER')"
          :options="customerOptions"
        />
        <Select
          v-model="form.salesStage"
          :label="t('CRM.OPPORTUNITIES.FORM.STAGE')"
          :options="stageOptions"
        />
      </div>
      <div class="grid grid-cols-3 gap-4">
        <Input
          v-model="form.amount"
          type="number"
          :label="t('CRM.OPPORTUNITIES.FORM.AMOUNT')"
        />
        <Select
          v-model="form.currency"
          :label="t('CRM.OPPORTUNITIES.FORM.CURRENCY')"
          :options="currencyOptions"
        />
        <Input
          v-model="form.probability"
          type="number"
          :label="t('CRM.OPPORTUNITIES.FORM.PROBABILITY')"
        />
      </div>
      <Input
        v-model="form.expectedCloseDate"
        type="date"
        :label="t('CRM.OPPORTUNITIES.FORM.EXPECTED_CLOSE')"
      />
      <Select
        v-if="form.salesStage === 'LOST'"
        v-model="form.lossReason"
        label="丢单原因"
        :options="lossReasonOptions"
      />
      <TextArea
        v-model="form.opportunityRemark"
        :label="t('CRM.OPPORTUNITIES.FORM.REMARK')"
      />
    </div>
  </Dialog>
</template>
