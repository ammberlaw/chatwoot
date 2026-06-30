<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
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

const form = reactive({
  name: '',
  customerCode: '',
  customerStatus: '',
  customerLevel: '',
  customerRemark: '',
});

const statusOptions = [
  { value: 'PROSPECT', label: 'Prospect 潜在客户' },
  { value: 'FOLLOWING', label: 'Following 跟进中' },
  { value: 'WON', label: 'Won 成交客户' },
  { value: 'DORMANT', label: 'Dormant 沉默客户' },
  { value: 'LOST', label: 'Lost 流失客户' },
];

const levelOptions = [
  { value: 'A', label: 'A' },
  { value: 'B', label: 'B' },
  { value: 'C', label: 'C' },
  { value: 'D', label: 'D' },
];

const isFormInvalid = computed(() => !form.name.trim());

const resetForm = () => {
  form.name = '';
  form.customerCode = '';
  form.customerStatus = '';
  form.customerLevel = '';
  form.customerRemark = '';
};

const open = () => {
  resetForm();
  dialogRef.value?.open();
};

const closeDialog = () => {
  dialogRef.value?.close();
};

const onSuccess = () => {
  resetForm();
  closeDialog();
};

const handleConfirm = () => {
  if (isFormInvalid.value) return;

  emit('create', {
    name: form.name.trim(),
    customerCode: form.customerCode.trim() || null,
    customerStatus: form.customerStatus || null,
    customerLevel: form.customerLevel || null,
    customerRemark: form.customerRemark.trim() || null,
  });
};

defineExpose({ dialogRef, onSuccess, open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="3xl"
    overflow-y-auto
    @confirm="handleConfirm"
    @close="resetForm"
  >
    <div class="flex flex-col gap-6">
      <span class="py-1 text-sm font-medium text-n-slate-12">
        {{ t('CRM.CUSTOMERS.CREATE.TITLE') }}
      </span>
      <div class="grid w-full grid-cols-1 gap-4 sm:grid-cols-2">
        <Input
          v-model="form.name"
          :label="t('CRM.CUSTOMERS.CREATE.FIELDS.NAME')"
          :disabled="isLoading"
          autofocus
        />
        <Input
          v-model="form.customerCode"
          :label="t('CRM.CUSTOMERS.CREATE.FIELDS.CODE')"
          :disabled="isLoading"
        />
        <Select
          v-model="form.customerStatus"
          :options="statusOptions"
          :placeholder="t('CRM.CUSTOMERS.CREATE.FIELDS.STATUS')"
        />
        <Select
          v-model="form.customerLevel"
          :options="levelOptions"
          :placeholder="t('CRM.CUSTOMERS.CREATE.FIELDS.LEVEL')"
        />
      </div>
      <TextArea
        v-model="form.customerRemark"
        :placeholder="t('CRM.CUSTOMERS.CREATE.FIELDS.REMARK')"
        :disabled="isLoading"
        :max-length="280"
        class="w-full"
        show-character-count
        auto-height
      />
    </div>

    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <Button
          :label="t('DIALOG.BUTTONS.CANCEL')"
          variant="link"
          type="reset"
          class="h-10 hover:!no-underline hover:text-n-brand"
          @click="closeDialog"
        />
        <Button
          :label="t('CRM.CUSTOMERS.NEW')"
          color="blue"
          type="submit"
          :disabled="isFormInvalid || isLoading"
          :is-loading="isLoading"
        />
      </div>
    </template>
  </Dialog>
</template>
