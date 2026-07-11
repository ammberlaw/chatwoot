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

const emit = defineEmits(['create', 'update']);

const { t } = useI18n();
const dialogRef = ref(null);
const editingId = ref(null);

const form = reactive({
  name: '',
  customerCode: '',
  customerStatus: '',
  customerLevel: '',
  customerGroup: '',
  sourceChannel: '',
  tradeCountry: '',
  whatsApp: '',
  wechat: '',
  customerRemark: '',
});

const statusOptions = [
  { value: 'PROSPECT', label: '潜在客户' },
  { value: 'FOLLOWING', label: '跟进中' },
  { value: 'WON', label: '成交客户' },
  { value: 'DORMANT', label: '沉默客户' },
  { value: 'LOST', label: '流失客户' },
];

const levelOptions = ['A', 'B', 'C', 'D'].map(v => ({ value: v, label: v }));

const groupOptions = [
  { value: 'KEY_ACCOUNT_WON', label: '成交重点客户' },
  { value: 'WON', label: '成交客户' },
  { value: 'SAMPLE_WON', label: '成交样品客户' },
  { value: 'NOT_WON', label: '未成交客户' },
  { value: 'SOCIAL_MEDIA', label: '社媒开发客户' },
];

const sourceOptions = [
  { value: 'ALIBABA', label: '阿里巴巴国际站' },
  { value: 'WEBSITE', label: '官网' },
  { value: 'EXHIBITION', label: '展会' },
  { value: 'REFERRAL', label: '转介绍' },
  { value: 'EMAIL', label: '邮件开发' },
  { value: 'OTHER', label: '其他' },
];

const COUNTRIES = [
  'USA', 'GERMANY', 'UK', 'FRANCE', 'ITALY', 'SPAIN', 'CANADA', 'AUSTRALIA',
  'JAPAN', 'SOUTH_KOREA', 'INDIA', 'RUSSIA', 'BRAZIL', 'MEXICO', 'NETHERLANDS',
  'BELGIUM', 'SWITZERLAND', 'SWEDEN', 'NORWAY', 'DENMARK', 'FINLAND', 'AUSTRIA',
  'POLAND', 'CZECH', 'TURKEY', 'UAE', 'SAUDI_ARABIA', 'SINGAPORE', 'MALAYSIA',
  'THAILAND', 'VIETNAM', 'INDONESIA', 'PHILIPPINES', 'SOUTH_AFRICA', 'ARGENTINA',
  'CHILE', 'COLOMBIA', 'PERU', 'ISRAEL', 'EGYPT', 'NIGERIA', 'KENYA', 'GREECE',
  'PORTUGAL', 'IRELAND', 'NEW_ZEALAND', 'TAIWAN', 'HONG_KONG', 'PAKISTAN',
  'BANGLADESH', 'UKRAINE', 'ROMANIA', 'HUNGARY', 'BULGARIA', 'CROATIA',
  'MOROCCO', 'IRAN', 'IRAQ', 'QATAR', 'KUWAIT', 'OMAN', 'MYANMAR', 'CAMBODIA',
  'LAOS', 'KAZAKHSTAN', 'UZBEKISTAN', 'OTHER',
];
const countryOptions = COUNTRIES.map(v => ({ value: v, label: v }));

const isEditing = computed(() => editingId.value !== null);
const isFormInvalid = computed(() => !form.name.trim());

const resetForm = () => {
  editingId.value = null;
  Object.keys(form).forEach(key => {
    form[key] = '';
  });
};

// 传 record 进入编辑模式；不传为新建。
const open = record => {
  resetForm();
  if (record) {
    editingId.value = record.id;
    Object.keys(form).forEach(key => {
      form[key] = record[key] || '';
    });
  }
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

  const payload = {
    name: form.name.trim(),
    customerCode: form.customerCode.trim() || null,
    customerStatus: form.customerStatus || null,
    customerLevel: form.customerLevel || null,
    customerGroup: form.customerGroup || null,
    sourceChannel: form.sourceChannel || null,
    tradeCountry: form.tradeCountry || null,
    whatsApp: form.whatsApp.trim() || null,
    wechat: form.wechat.trim() || null,
    customerRemark: form.customerRemark.trim() || null,
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
    @confirm="handleConfirm"
    @close="resetForm"
  >
    <div class="flex flex-col gap-6">
      <span class="py-1 text-sm font-medium text-n-slate-12">
        {{ isEditing ? t('CRM.CUSTOMERS.EDIT.TITLE') : t('CRM.CUSTOMERS.CREATE.TITLE') }}
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
        <Select
          v-model="form.customerGroup"
          :options="groupOptions"
          placeholder="客户分组"
        />
        <Select
          v-model="form.sourceChannel"
          :options="sourceOptions"
          placeholder="客户来源"
        />
        <Select
          v-model="form.tradeCountry"
          :options="countryOptions"
          placeholder="国家地区"
        />
        <Input v-model="form.whatsApp" label="WhatsApp" :disabled="isLoading" />
        <Input v-model="form.wechat" label="微信" :disabled="isLoading" />
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
          :label="isEditing ? t('CRM.CUSTOMERS.EDIT.SAVE') : t('CRM.CUSTOMERS.NEW')"
          color="blue"
          type="submit"
          :disabled="isFormInvalid || isLoading"
          :is-loading="isLoading"
        />
      </div>
    </template>
  </Dialog>
</template>
