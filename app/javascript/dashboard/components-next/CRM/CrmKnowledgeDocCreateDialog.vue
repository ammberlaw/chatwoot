<script setup>
/* global axios */
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

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
  category: 'PRODUCT_CATALOG',
  scope: 'COMPANY',
  summary: '',
  body: '',
});

// 附件：新建时暂存内存(pendingFiles)随创建 multipart 提交；编辑时对已存在文档即时 attach/detach。
const fileInputRef = ref(null);
const pendingFiles = ref([]); // File[]（新建模式）
const attachments = ref([]); // 已保存附件（编辑模式）
const uploading = ref(false);

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

const isEditing = computed(() => editingId.value !== null);
const isFormInvalid = computed(() => !form.name.trim());

const resetForm = () => {
  editingId.value = null;
  pendingFiles.value = [];
  attachments.value = [];
  form.name = '';
  form.category = 'PRODUCT_CATALOG';
  form.scope = 'COMPANY';
  form.summary = '';
  form.body = '';
};

const open = record => {
  resetForm();
  if (record) {
    editingId.value = record.id;
    attachments.value = record.files || [];
    form.name = record.name || '';
    form.category = record.category || 'PRODUCT_CATALOG';
    form.scope = record.scope || 'COMPANY';
    form.summary = record.summary || '';
    form.body = record.body || '';
  }
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
    category: form.category,
    scope: form.scope,
    summary: form.summary.trim() || null,
    body: form.body || null,
  };
  if (isEditing.value) {
    emit('update', { id: editingId.value, ...payload });
  } else {
    emit('create', { ...payload, __files: pendingFiles.value });
  }
};

// ── 附件 ──
const triggerUpload = () => fileInputRef.value?.click();

const attachApi = () =>
  `/api/v1/accounts/${accountId.value}/crm/knowledge_docs/${editingId.value}/attach`;

const onFilesSelected = async event => {
  const files = Array.from(event.target.files || []);
  event.target.value = '';
  if (!files.length) return;

  // 新建模式：暂存内存，随创建一起提交。
  if (!isEditing.value) {
    pendingFiles.value = [...pendingFiles.value, ...files];
    return;
  }

  // 编辑模式：即时上传到已存在文档。
  uploading.value = true;
  const fd = new FormData();
  files.forEach(f => fd.append('files[]', f));
  try {
    const { data } = await axios.post(attachApi(), fd, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
    attachments.value = data.files || [];
    emit('refresh');
    useAlert(t('CRM.KNOWLEDGE_DOCS.ATTACH.UPLOAD_SUCCESS'));
  } catch {
    useAlert(t('CRM.KNOWLEDGE_DOCS.ATTACH.UPLOAD_ERROR'));
  } finally {
    uploading.value = false;
  }
};

const removePending = index => {
  pendingFiles.value = pendingFiles.value.filter((_, i) => i !== index);
};

const removeAttachment = async id => {
  try {
    const { data } = await axios.delete(`${attachApi()}/${id}`);
    attachments.value = data.files || [];
    emit('refresh');
  } catch {
    useAlert(t('CRM.KNOWLEDGE_DOCS.ATTACH.DELETE_ERROR'));
  }
};

defineExpose({ dialogRef, onSuccess, open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="3xl"
    overflow-y-auto
    :title="
      isEditing
        ? t('CRM.KNOWLEDGE_DOCS.EDIT.TITLE')
        : t('CRM.KNOWLEDGE_DOCS.CREATE.TITLE')
    "
    :is-loading="isLoading"
    :disable-confirm-button="isFormInvalid"
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

      <!-- 附件（产品目录 / 资质 / 手册等）-->
      <div class="flex flex-col gap-2">
        <div class="flex items-center justify-between">
          <span
            class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
          >
            {{ t('CRM.KNOWLEDGE_DOCS.ATTACH.TITLE') }}
          </span>
          <button
            type="button"
            class="flex items-center gap-1 h-8 px-3 text-sm border rounded-lg border-n-weak text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-50"
            :disabled="uploading"
            @click="triggerUpload"
          >
            <span class="i-lucide-paperclip size-4" />
            {{
              uploading
                ? t('CRM.KNOWLEDGE_DOCS.ATTACH.UPLOADING')
                : t('CRM.KNOWLEDGE_DOCS.ATTACH.ADD')
            }}
          </button>
          <input
            ref="fileInputRef"
            type="file"
            multiple
            class="hidden"
            @change="onFilesSelected"
          />
        </div>

        <div
          v-if="!pendingFiles.length && !attachments.length"
          class="text-xs text-n-slate-10"
        >
          {{ t('CRM.KNOWLEDGE_DOCS.ATTACH.EMPTY_HINT') }}
        </div>

        <!-- 待提交文件（新建模式）-->
        <div
          v-for="(file, index) in pendingFiles"
          :key="`pending-${index}`"
          class="flex items-center justify-between px-3 py-2 border rounded-lg border-n-weak bg-n-solid-1"
        >
          <span class="flex items-center gap-2 text-sm text-n-slate-12">
            <span class="i-lucide-file size-4" />
            {{ file.name }}
          </span>
          <button
            type="button"
            class="text-n-slate-10 hover:text-n-ruby-11"
            :title="t('CRM.KNOWLEDGE_DOCS.ATTACH.REMOVE')"
            @click="removePending(index)"
          >
            <span class="i-lucide-x size-4" />
          </button>
        </div>

        <!-- 已保存附件（编辑模式，可下载）-->
        <div
          v-for="file in attachments"
          :key="file.id"
          class="flex items-center justify-between px-3 py-2 border rounded-lg border-n-weak bg-n-solid-1"
        >
          <a
            :href="file.url"
            target="_blank"
            rel="noopener noreferrer"
            class="flex items-center gap-2 text-sm text-n-blue-11 hover:underline"
          >
            <span class="i-lucide-file size-4" />
            {{ file.filename }}
          </a>
          <button
            type="button"
            class="text-n-slate-10 hover:text-n-ruby-11"
            :title="t('CRM.KNOWLEDGE_DOCS.ATTACH.REMOVE')"
            @click="removeAttachment(file.id)"
          >
            <span class="i-lucide-x size-4" />
          </button>
        </div>
      </div>
    </div>
  </Dialog>
</template>
