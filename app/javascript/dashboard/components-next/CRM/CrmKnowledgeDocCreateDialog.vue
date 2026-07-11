<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';

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
  category: 'PRODUCT_CATALOG',
  scope: 'COMPANY',
  summary: '',
  body: '',
});

const categoryOptions = [
  { value: 'PRODUCT_CATALOG', label: '产品目录' },
  { value: 'FAQ', label: 'FAQ' },
  { value: 'AFTER_SALES', label: '售后政策' },
  { value: 'QUOTE_TEMPLATE', label: '报价模板' },
  { value: 'COMPANY_CERT', label: '公司资质' },
  { value: 'USER_MANUAL', label: '操作手册' },
  { value: 'PRODUCT_SPEC', label: '产品规格书' },
  { value: 'PAYMENT_ACCOUNT', label: '收款账户' },
];

const scopeOptions = [
  { value: 'COMPANY', label: '公司' },
  { value: 'PERSONAL', label: '个人' },
];

const isFormInvalid = computed(() => !form.name.trim());

const resetForm = () => {
  form.name = '';
  form.category = 'PRODUCT_CATALOG';
  form.scope = 'COMPANY';
  form.summary = '';
  form.body = '';
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
    category: form.category,
    scope: form.scope,
    summary: form.summary.trim() || null,
    body: form.body || null,
  });
};

defineExpose({ dialogRef, onSuccess, open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="3xl"
    overflow-y-auto
    :title="t('CRM.KNOWLEDGE_DOCS.CREATE.TITLE')"
    :is-loading="isLoading"
    @confirm="handleConfirm"
    @close="resetForm"
  >
    <div class="flex flex-col gap-4">
      <Input
        v-model="form.name"
        :label="t('CRM.KNOWLEDGE_DOCS.FORM.NAME')"
        autofocus
      />
      <div class="grid grid-cols-2 gap-4">
        <Select
          v-model="form.category"
          :label="t('CRM.KNOWLEDGE_DOCS.FORM.CATEGORY')"
          :options="categoryOptions"
        />
        <Select
          v-model="form.scope"
          :label="t('CRM.KNOWLEDGE_DOCS.FORM.SCOPE')"
          :options="scopeOptions"
        />
      </div>
      <Input
        v-model="form.summary"
        :label="t('CRM.KNOWLEDGE_DOCS.FORM.SUMMARY')"
      />
      <TextArea
        v-model="form.body"
        :label="t('CRM.KNOWLEDGE_DOCS.FORM.BODY')"
        :rows="6"
      />
    </div>
  </Dialog>
</template>
