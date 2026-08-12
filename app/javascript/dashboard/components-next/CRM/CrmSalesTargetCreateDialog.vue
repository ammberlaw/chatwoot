<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import MonthPicker from 'dashboard/components-next/monthpicker/MonthPicker.vue';

defineProps({
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['create']);

const { t } = useI18n();
const dialogRef = ref(null);

const currentMonth = () => new Date().toISOString().slice(0, 7);

const form = reactive({
  name: '',
  month: currentMonth(),
  amount: '',
  newCustomers: '',
});

const isFormInvalid = computed(() => !form.name.trim() || !form.month);

const resetForm = () => {
  form.name = '';
  form.month = currentMonth();
  form.amount = '';
  form.newCustomers = '';
};

const open = () => {
  resetForm();
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
    targetMonth: `${form.month}-01`,
    targetAmountMicros: form.amount
      ? Math.round(parseFloat(form.amount) * 1_000_000)
      : null,
    targetOrderCount: form.newCustomers ? Number(form.newCustomers) : null,
  });
};

defineExpose({ dialogRef, onSuccess, open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="2xl"
    overflow-y-auto
    :title="t('CRM.SALES_TARGETS.CREATE.TITLE')"
    :is-loading="isLoading"
    @confirm="handleConfirm"
    @close="resetForm"
  >
    <div class="flex flex-col gap-4">
      <Input
        v-model="form.name"
        :label="t('CRM.SALES_TARGETS.FORM.NAME')"
        autofocus
      />
      <div class="relative flex flex-col min-w-0 gap-1">
        <label class="mb-0.5 text-heading-3 text-n-slate-12">
          {{ t('CRM.SALES_TARGETS.FORM.MONTH') }}
        </label>
        <MonthPicker v-model="form.month" block />
      </div>
      <div class="grid grid-cols-2 gap-4">
        <Input
          v-model="form.amount"
          type="number"
          :label="t('CRM.SALES_TARGETS.FORM.AMOUNT')"
        />
        <Input
          v-model="form.newCustomers"
          type="number"
          :label="t('CRM.SALES_TARGETS.FORM.NEW_CUSTOMERS')"
        />
      </div>
    </div>
  </Dialog>
</template>
