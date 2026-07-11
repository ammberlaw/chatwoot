<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import camelcaseKeys from 'camelcase-keys';
import MailAccountsAPI from 'dashboard/api/crm/mailAccounts';
import EmailTemplatesAPI from 'dashboard/api/crm/emailTemplates';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

defineProps({
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['send']);

const { t } = useI18n();
const dialogRef = ref(null);

const mailAccounts = ref([]);
const templates = ref([]);

const form = reactive({
  fromAddress: '',
  toAddress: '',
  ccAddress: '',
  subject: '',
  body: '',
  templateId: '',
});

const accountOptions = computed(() =>
  mailAccounts.value.map(a => ({ value: a.emailAddress, label: a.emailAddress }))
);

const templateOptions = computed(() => [
  { value: '', label: t('CRM.EMAILS.COMPOSE.NO_TEMPLATE') },
  ...templates.value.map(tp => ({ value: String(tp.id), label: tp.name })),
]);

const isFormInvalid = computed(
  () => !form.fromAddress || !form.toAddress.trim()
);

const applyTemplate = () => {
  const tpl = templates.value.find(x => String(x.id) === form.templateId);
  if (!tpl) return;
  form.subject = tpl.subjectTemplate || form.subject;
  form.body = tpl.body || form.body;
};

const resetForm = () => {
  form.fromAddress = mailAccounts.value[0]?.emailAddress || '';
  form.toAddress = '';
  form.ccAddress = '';
  form.subject = '';
  form.body = '';
  form.templateId = '';
};

const open = async () => {
  const [{ data: accountsData }, { data: templatesData }] = await Promise.all([
    MailAccountsAPI.get({ filter: 'mine' }),
    EmailTemplatesAPI.get(),
  ]);
  mailAccounts.value = camelcaseKeys(accountsData.payload || [], {
    deep: true,
  }).filter(a => a.isActive);
  templates.value = camelcaseKeys(templatesData.payload || [], { deep: true });
  resetForm();
  dialogRef.value?.open();
};

const onSuccess = () => {
  resetForm();
  dialogRef.value?.close();
};

const handleConfirm = () => {
  if (isFormInvalid.value) return;

  emit('send', {
    fromAddress: form.fromAddress,
    toAddress: form.toAddress.trim(),
    ccAddress: form.ccAddress.trim() || null,
    subject: form.subject.trim() || null,
    body: form.body,
    folder: 'DRAFT',
    sendNow: true,
  });
};

defineExpose({ dialogRef, onSuccess, open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="3xl"
    overflow-y-auto
    :title="t('CRM.EMAILS.COMPOSE.TITLE')"
    :confirm-button-label="t('CRM.EMAILS.COMPOSE.SEND')"
    :is-loading="isLoading"
    @confirm="handleConfirm"
    @close="resetForm"
  >
    <div class="flex flex-col gap-4">
      <div
        v-if="!accountOptions.length"
        class="p-3 text-sm rounded-lg bg-n-amber-3 text-n-amber-11"
      >
        {{ t('CRM.EMAILS.COMPOSE.NO_ACCOUNT') }}
      </div>
      <div class="grid grid-cols-2 gap-4">
        <Select
          v-model="form.fromAddress"
          :label="t('CRM.EMAILS.COMPOSE.FROM')"
          :options="accountOptions"
        />
        <Select
          v-model="form.templateId"
          :label="t('CRM.EMAILS.COMPOSE.TEMPLATE')"
          :options="templateOptions"
          @change="applyTemplate"
        />
      </div>
      <Input
        v-model="form.toAddress"
        :label="t('CRM.EMAILS.COMPOSE.TO')"
        :placeholder="t('CRM.EMAILS.COMPOSE.TO_PLACEHOLDER')"
      />
      <Input v-model="form.ccAddress" :label="t('CRM.EMAILS.COMPOSE.CC')" />
      <Input v-model="form.subject" :label="t('CRM.EMAILS.COMPOSE.SUBJECT')" />
      <TextArea
        v-model="form.body"
        :label="t('CRM.EMAILS.COMPOSE.BODY')"
        :rows="8"
      />
    </div>
  </Dialog>
</template>
