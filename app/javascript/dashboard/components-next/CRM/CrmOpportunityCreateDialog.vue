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

const emit = defineEmits(['create']);

const { t } = useI18n();
const dialogRef = ref(null);
const customersStore = useCrmCustomersStore();

const form = reactive({
  name: '',
  crmCustomerId: '',
  salesStage: 'INITIAL_CONTACT',
  amount: '',
  currency: 'USD',
  probability: '',
  expectedCloseDate: '',
  opportunityRemark: '',
});

const stageOptions = [
  { value: 'INITIAL_CONTACT', label: '初步接触' },
  { value: 'NEEDS_CONFIRMED', label: '需求确认' },
  { value: 'QUOTED', label: '已报价' },
  { value: 'NEGOTIATING', label: '谈判中' },
  { value: 'SAMPLING', label: '样品中' },
  { value: 'WON', label: '已成交' },
  { value: 'LOST', label: '已丢单' },
];

const currencyOptions = ['USD', 'CNY', 'EUR'].map(v => ({
  value: v,
  label: v,
}));

const customerOptions = computed(() =>
  customersStore.getCustomers.map(c => ({ value: String(c.id), label: c.name }))
);

const isFormInvalid = computed(() => !form.name.trim());

const resetForm = () => {
  form.name = '';
  form.crmCustomerId = '';
  form.salesStage = 'INITIAL_CONTACT';
  form.amount = '';
  form.currency = 'USD';
  form.probability = '';
  form.expectedCloseDate = '';
  form.opportunityRemark = '';
};

const open = () => {
  resetForm();
  if (!customersStore.getCustomers.length) customersStore.get({ page: 1 });
  dialogRef.value?.open();
};

const onSuccess = () => {
  resetForm();
  dialogRef.value?.close();
};

const handleConfirm = () => {
  if (isFormInvalid.value) return;

  emit('create', {
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
  });
};

defineExpose({ dialogRef, onSuccess, open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="3xl"
    overflow-y-auto
    :title="t('CRM.OPPORTUNITIES.CREATE.TITLE')"
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
      <TextArea
        v-model="form.opportunityRemark"
        :label="t('CRM.OPPORTUNITIES.FORM.REMARK')"
      />
    </div>
  </Dialog>
</template>
