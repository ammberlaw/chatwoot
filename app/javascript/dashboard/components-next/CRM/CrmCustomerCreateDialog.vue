<script setup>
/* global axios */
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import { COUNTRY_LABELS } from 'dashboard/routes/dashboard/crm/constants/countries';

defineProps({
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['create', 'update', 'refresh']);

const { t } = useI18n();
const { accountId } = useAccount();
const dialogRef = ref(null);
const editingId = ref(null);

const form = reactive({
  name: '',
  customerCode: '',
  website: '',
  customerStatus: '',
  customerLevel: '',
  customerGroup: '',
  productGroup: '',
  sourceChannel: '',
  tradeCountry: '',
  primaryContactName: '',
  contactJobTitle: '',
  contactEmail: '',
  contactPhone: '',
  whatsApp: '',
  wechat: '',
  linkedin: '',
  address: '',
  contactPreference: '',
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
const productGroupOptions = [
  { value: 'TABLET', label: '平板电脑' },
  { value: 'COMMERCIAL_DISPLAY', label: '商显' },
  { value: 'INDUSTRIAL_CONTROL', label: '工控' },
];
const sourceOptions = [
  { value: 'ALIBABA', label: '阿里巴巴国际站' },
  { value: 'WEBSITE', label: '官网' },
  { value: 'EXHIBITION', label: '展会' },
  { value: 'EMAIL', label: '邮件开发' },
  { value: 'SOCIAL_MEDIA', label: '社媒开发' },
  { value: 'OTHER', label: '其他' },
];
const preferenceOptions = [
  { value: 'EMAIL', label: '邮件' },
  { value: 'PHONE', label: '电话' },
  { value: 'WHATSAPP', label: 'WhatsApp' },
  { value: 'WECHAT', label: '微信' },
];

const countryOptions = Object.entries(COUNTRY_LABELS).map(([value, label]) => ({
  value,
  label,
}));

const isEditing = computed(() => editingId.value !== null);
const isFormInvalid = computed(() => !form.name.trim());

// 附件
const attachments = ref([]);
const uploading = ref(false);
const fileInputRef = ref(null);

const resetForm = () => {
  editingId.value = null;
  Object.keys(form).forEach(key => {
    form[key] = '';
  });
  attachments.value = [];
};

// 传 record 进入编辑模式；不传为新建。
const open = record => {
  resetForm();
  if (record) {
    editingId.value = record.id;
    Object.keys(form).forEach(key => {
      form[key] = record[key] || '';
    });
    attachments.value = record.files || [];
  }
  dialogRef.value?.open();
};

const closeDialog = () => dialogRef.value?.close();
const onSuccess = () => {
  resetForm();
  closeDialog();
};

const handleConfirm = () => {
  if (isFormInvalid.value) return;
  const payload = {
    name: form.name.trim(),
    website: form.website.trim() || null,
    customerStatus: form.customerStatus || null,
    customerLevel: form.customerLevel || null,
    customerGroup: form.customerGroup || null,
    productGroup: form.productGroup || null,
    sourceChannel: form.sourceChannel || null,
    tradeCountry: form.tradeCountry || null,
    primaryContactName: form.primaryContactName.trim() || null,
    contactJobTitle: form.contactJobTitle.trim() || null,
    contactEmail: form.contactEmail.trim() || null,
    contactPhone: form.contactPhone.trim() || null,
    whatsApp: form.whatsApp.trim() || null,
    wechat: form.wechat.trim() || null,
    linkedin: form.linkedin.trim() || null,
    address: form.address.trim() || null,
    contactPreference: form.contactPreference || null,
    customerRemark: form.customerRemark.trim() || null,
  };
  if (isEditing.value) {
    emit('update', { id: editingId.value, ...payload });
  } else {
    emit('create', payload);
  }
};

// ── 附件上传 / 删除（独立于字段保存，即时生效）──
const attachApi = () =>
  `/api/v1/accounts/${accountId.value}/crm/customers/${editingId.value}/attach`;

const triggerUpload = () => fileInputRef.value?.click();

const onFilesSelected = async event => {
  const files = Array.from(event.target.files || []);
  if (!files.length || !editingId.value) return;
  uploading.value = true;
  const fd = new FormData();
  files.forEach(f => fd.append('files[]', f));
  try {
    const { data } = await axios.post(attachApi(), fd, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
    attachments.value = data.files || [];
    emit('refresh');
    useAlert(t('CRM.CUSTOMERS.ATTACH.UPLOAD_SUCCESS'));
  } catch {
    useAlert(t('CRM.CUSTOMERS.ATTACH.UPLOAD_ERROR'));
  } finally {
    uploading.value = false;
    event.target.value = '';
  }
};

const removeAttachment = async id => {
  try {
    const { data } = await axios.delete(`${attachApi()}/${id}`);
    attachments.value = data.files || [];
    emit('refresh');
  } catch {
    useAlert(t('CRM.CUSTOMERS.ATTACH.DELETE_ERROR'));
  }
};

const prettySize = bytes => {
  if (!bytes) return '';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
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
    <div class="flex flex-col gap-5">
      <span class="py-1 text-sm font-medium text-n-slate-12">
        {{ isEditing ? t('CRM.CUSTOMERS.EDIT.TITLE') : t('CRM.CUSTOMERS.CREATE.TITLE') }}
      </span>

      <!-- 基本 -->
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
          disabled
        />
        <Input v-model="form.website" label="公司网址 / 域名" :disabled="isLoading" />
        <Select
          v-model="form.tradeCountry"
          :options="countryOptions"
          placeholder="国家地区"
        />
      </div>

      <!-- 业务 -->
      <div class="text-xs font-semibold tracking-wide uppercase text-n-slate-10">
        业务信息
      </div>
      <div class="grid w-full grid-cols-1 gap-4 sm:grid-cols-2">
        <Select
          v-model="form.customerStatus"
          :options="statusOptions"
          placeholder="客户状态"
        />
        <Select
          v-model="form.customerLevel"
          :options="levelOptions"
          placeholder="客户等级"
        />
        <Select
          v-model="form.customerGroup"
          :options="groupOptions"
          placeholder="客户分组"
        />
        <Select
          v-model="form.productGroup"
          :options="productGroupOptions"
          placeholder="产品分组"
        />
        <Select
          v-model="form.sourceChannel"
          :options="sourceOptions"
          placeholder="客户来源"
        />
      </div>

      <!-- 联系 -->
      <div class="text-xs font-semibold tracking-wide uppercase text-n-slate-10">
        联系信息
      </div>
      <div class="grid w-full grid-cols-1 gap-4 sm:grid-cols-2">
        <Input v-model="form.primaryContactName" label="主要联系人" :disabled="isLoading" />
        <Input v-model="form.contactJobTitle" label="职位" :disabled="isLoading" />
        <Input v-model="form.contactEmail" label="联系邮箱" :disabled="isLoading" />
        <Input v-model="form.contactPhone" label="联系电话" :disabled="isLoading" />
        <Input v-model="form.whatsApp" label="WhatsApp" :disabled="isLoading" />
        <Input v-model="form.wechat" label="微信" :disabled="isLoading" />
        <Input v-model="form.linkedin" label="Linkedin" :disabled="isLoading" />
        <Select
          v-model="form.contactPreference"
          :options="preferenceOptions"
          placeholder="联系偏好"
        />
        <Input v-model="form.address" label="地址" :disabled="isLoading" class="sm:col-span-2" />
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

      <!-- 附件（仅编辑模式）-->
      <div v-if="isEditing" class="flex flex-col gap-2">
        <div class="flex items-center justify-between">
          <span class="text-xs font-semibold tracking-wide uppercase text-n-slate-10">
            附件
          </span>
          <button
            type="button"
            class="flex items-center gap-1 h-8 px-3 text-sm border rounded-lg border-n-weak text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-50"
            :disabled="uploading"
            @click="triggerUpload"
          >
            <span class="i-lucide-paperclip size-4" />
            {{ uploading ? '上传中…' : '添加附件' }}
          </button>
          <input
            ref="fileInputRef"
            type="file"
            multiple
            class="hidden"
            @change="onFilesSelected"
          />
        </div>
        <div v-if="!attachments.length" class="text-xs text-n-slate-10">
          暂无附件。可上传合同、报价单、名片等文件。
        </div>
        <div
          v-for="file in attachments"
          :key="file.id"
          class="flex items-center justify-between px-3 py-2 border rounded-lg border-n-weak bg-n-solid-1"
        >
          <a
            :href="file.url"
            target="_blank"
            rel="noopener"
            class="flex items-center gap-2 text-sm text-n-blue-11 hover:underline"
          >
            <span class="i-lucide-file size-4" />
            {{ file.filename }}
            <span class="text-xs text-n-slate-10">{{ prettySize(file.byte_size) }}</span>
          </a>
          <button
            type="button"
            class="text-n-slate-10 hover:text-n-ruby-11"
            title="删除"
            @click="removeAttachment(file.id)"
          >
            <span class="i-lucide-x size-4" />
          </button>
        </div>
      </div>
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
          color="iris"
          type="submit"
          :disabled="isFormInvalid || isLoading"
          :is-loading="isLoading"
        />
      </div>
    </template>
  </Dialog>
</template>
