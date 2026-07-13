<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import camelcaseKeys from 'camelcase-keys';
import MailAccountsAPI from 'dashboard/api/crm/mailAccounts';
import EmailTemplatesAPI from 'dashboard/api/crm/emailTemplates';
import CrmCustomerAPI from 'dashboard/api/crm/customers';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

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
  bccAddress: '',
  subject: '',
  body: '',
  templateId: '',
  crmCustomerId: null,
  contactId: null,
});

const showCcBcc = ref(false);
const attachments = ref([]);
const fileInputRef = ref(null);

// 客户搜索联动
const customerQuery = ref('');
const customerResults = ref([]);
const showCustomerResults = ref(false);
const selectedCustomerName = ref('');
let customerTimer = null;

const accountOptions = computed(() =>
  mailAccounts.value.map(a => ({
    value: a.emailAddress,
    label: `${a.name} <${a.emailAddress}>`,
  }))
);

const templateOptions = computed(() => [
  { value: '', label: t('CRM.EMAILS.COMPOSE.NO_TEMPLATE') },
  ...templates.value.map(tp => ({ value: String(tp.id), label: tp.name })),
]);

const activeAccount = computed(() =>
  mailAccounts.value.find(a => a.emailAddress === form.fromAddress)
);

const isFormInvalid = computed(
  () => !form.fromAddress || !form.toAddress.trim()
);

const applyTemplate = () => {
  const tpl = templates.value.find(x => String(x.id) === form.templateId);
  if (!tpl) return;
  form.subject = tpl.subjectTemplate || form.subject;
  form.body = tpl.body || form.body;
};

const insertSignature = () => {
  const signature = activeAccount.value?.signature;
  if (!signature) return;
  form.body = `${form.body || ''}\n\n${signature}`;
};

// 客户搜索：输入防抖查我的客户，选中后带出收件邮箱 + 关联。
const searchCustomers = () => {
  clearTimeout(customerTimer);
  const term = customerQuery.value.trim();
  if (!term) {
    customerResults.value = [];
    return;
  }
  customerTimer = setTimeout(async () => {
    const { data } = await CrmCustomerAPI.get({ q: term, page: 1 });
    customerResults.value = camelcaseKeys(data.payload || [], { deep: true });
    showCustomerResults.value = true;
  }, 300);
};

const pickCustomer = customer => {
  form.crmCustomerId = customer.id;
  selectedCustomerName.value = customer.name;
  customerQuery.value = customer.name;
  showCustomerResults.value = false;
  if (customer.contactEmail && !form.toAddress.trim()) {
    form.toAddress = customer.contactEmail;
  }
};

const clearCustomer = () => {
  form.crmCustomerId = null;
  form.contactId = null;
  selectedCustomerName.value = '';
  customerQuery.value = '';
  customerResults.value = [];
};

const onPickFiles = event => {
  attachments.value.push(...Array.from(event.target.files || []));
  event.target.value = '';
};

const removeAttachment = index => {
  attachments.value.splice(index, 1);
};

const fmtSize = bytes => {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
};

const resetForm = () => {
  form.fromAddress = mailAccounts.value[0]?.emailAddress || '';
  form.toAddress = '';
  form.ccAddress = '';
  form.bccAddress = '';
  form.subject = '';
  form.body = '';
  form.templateId = '';
  form.crmCustomerId = null;
  form.contactId = null;
  showCcBcc.value = false;
  attachments.value = [];
  customerQuery.value = '';
  customerResults.value = [];
  selectedCustomerName.value = '';
};

// prefill 用于回复/转发预填。
const open = async prefill => {
  const [{ data: accountsData }, { data: templatesData }] = await Promise.all([
    MailAccountsAPI.get({ filter: 'mine' }),
    EmailTemplatesAPI.get(),
  ]);
  mailAccounts.value = camelcaseKeys(accountsData.payload || [], {
    deep: true,
  }).filter(a => a.isActive);
  templates.value = camelcaseKeys(templatesData.payload || [], { deep: true });
  resetForm();
  if (prefill && typeof prefill === 'object') {
    Object.assign(form, prefill);
    if (prefill.ccAddress) showCcBcc.value = true;
  }
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
    bccAddress: form.bccAddress.trim() || null,
    subject: form.subject.trim() || null,
    body: form.body,
    crmCustomerId: form.crmCustomerId,
    contactId: form.contactId,
    folder: 'DRAFT',
    sendNow: true,
    ...(attachments.value.length ? { __files: attachments.value } : {}),
  });
};

watch(customerQuery, () => {
  if (
    selectedCustomerName.value &&
    customerQuery.value !== selectedCustomerName.value
  ) {
    form.crmCustomerId = null;
    selectedCustomerName.value = '';
  }
});

defineExpose({ dialogRef, onSuccess, open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="3xl"
    overflow-y-auto
    :title="t('CRM.EMAILS.COMPOSE.TITLE')"
    :confirm-button-label="t('CRM.EMAILS.COMPOSE.SEND')"
    confirm-button-color="amber"
    :is-loading="isLoading"
    :disable-confirm-button="isFormInvalid"
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
        <div>
          <label class="block mb-0.5 text-heading-3 text-n-slate-12">
            {{ t('CRM.EMAILS.COMPOSE.FROM') }}
          </label>
          <Select
            v-model="form.fromAddress"
            class="w-full"
            :options="accountOptions"
          />
        </div>
        <div>
          <label class="block mb-0.5 text-heading-3 text-n-slate-12">
            {{ t('CRM.EMAILS.COMPOSE.TEMPLATE') }}
          </label>
          <Select
            v-model="form.templateId"
            class="w-full"
            :options="templateOptions"
            @change="applyTemplate"
          />
        </div>
      </div>

      <!-- 关联客户搜索 -->
      <div class="relative">
        <label class="block mb-0.5 text-heading-3 text-n-slate-12">
          {{ t('CRM.EMAILS.COMPOSE.CUSTOMER') }}
        </label>
        <div class="relative">
          <input
            v-model="customerQuery"
            type="text"
            :placeholder="t('CRM.EMAILS.COMPOSE.CUSTOMER_PLACEHOLDER')"
            class="w-full h-10 px-3 pr-8 text-sm border rounded-lg reset-base bg-n-alpha-1 border-n-weak text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-amber-9"
            @input="searchCustomers"
            @focus="showCustomerResults = customerResults.length > 0"
          />
          <button
            v-if="form.crmCustomerId"
            class="absolute -translate-y-1/2 right-2 top-1/2 text-n-slate-10 hover:text-n-slate-12"
            @click="clearCustomer"
          >
            <Icon icon="i-lucide-x" class="size-4" />
          </button>
        </div>
        <div
          v-if="showCustomerResults && customerResults.length"
          class="absolute z-20 w-full mt-1 overflow-y-auto border rounded-lg shadow-lg max-h-56 bg-n-solid-1 border-n-weak"
        >
          <button
            v-for="customer in customerResults"
            :key="customer.id"
            class="flex flex-col w-full gap-0.5 px-3 py-2 text-left hover:bg-n-alpha-1"
            @click="pickCustomer(customer)"
          >
            <span class="text-sm text-n-slate-12">{{ customer.name }}</span>
            <span v-if="customer.contactEmail" class="text-xs text-n-slate-10">
              {{ customer.contactEmail }}
            </span>
          </button>
        </div>
      </div>

      <Input
        v-model="form.toAddress"
        :label="t('CRM.EMAILS.COMPOSE.TO')"
        :placeholder="t('CRM.EMAILS.COMPOSE.TO_PLACEHOLDER')"
      />

      <div v-if="!showCcBcc">
        <button
          class="inline-flex items-center gap-1 text-xs text-n-amber-11 hover:underline"
          @click="showCcBcc = true"
        >
          <Icon icon="i-lucide-plus" class="size-3" />
          {{ t('CRM.EMAILS.COMPOSE.ADD_CC') }}
        </button>
      </div>
      <template v-else>
        <Input v-model="form.ccAddress" :label="t('CRM.EMAILS.COMPOSE.CC')" />
        <Input v-model="form.bccAddress" :label="t('CRM.EMAILS.COMPOSE.BCC')" />
      </template>

      <Input v-model="form.subject" :label="t('CRM.EMAILS.COMPOSE.SUBJECT')" />

      <div>
        <div class="flex items-center justify-between mb-0.5">
          <label class="text-heading-3 text-n-slate-12">
            {{ t('CRM.EMAILS.COMPOSE.BODY') }}
          </label>
          <button
            v-if="activeAccount?.signature"
            class="inline-flex items-center gap-1 text-xs text-n-amber-11 hover:underline"
            @click="insertSignature"
          >
            <Icon icon="i-lucide-signature" class="size-3.5" />
            {{ t('CRM.EMAILS.COMPOSE.INSERT_SIGNATURE') }}
          </button>
        </div>
        <TextArea v-model="form.body" :rows="8" />
      </div>

      <!-- 附件 -->
      <div>
        <input
          ref="fileInputRef"
          type="file"
          multiple
          class="hidden"
          @change="onPickFiles"
        />
        <Button
          :label="t('CRM.EMAILS.COMPOSE.ADD_ATTACHMENT')"
          icon="i-lucide-paperclip"
          size="sm"
          variant="faded"
          color="slate"
          @click="fileInputRef?.click()"
        />
        <div v-if="attachments.length" class="flex flex-col gap-1.5 mt-2">
          <div
            v-for="(file, index) in attachments"
            :key="index"
            class="flex items-center justify-between gap-3 px-3 py-2 text-sm border rounded-lg border-n-weak"
          >
            <span class="flex items-center min-w-0 gap-2">
              <Icon
                icon="i-lucide-file"
                class="flex-shrink-0 size-4 text-n-amber-11"
              />
              <span class="truncate text-n-slate-12">{{ file.name }}</span>
              <span class="flex-shrink-0 text-xs text-n-slate-10">
                {{ fmtSize(file.size) }}
              </span>
            </span>
            <button
              class="flex-shrink-0 text-n-slate-10 hover:text-n-ruby-11"
              @click="removeAttachment(index)"
            >
              <Icon icon="i-lucide-x" class="size-4" />
            </button>
          </div>
        </div>
      </div>
    </div>
  </Dialog>
</template>
