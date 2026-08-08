<script setup>
import { ref, computed, onMounted, reactive } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCrmEmailTemplatesStore } from 'dashboard/stores/crm/emailTemplates';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';
import TemplatesAPI from 'dashboard/api/crm/emailTemplates';

const { t } = useI18n();
const store = useCrmEmailTemplatesStore();
const dialogRef = ref(null);

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);

// 分类：标签 + 色块（颜色写成字面量类，防 purge）。
const CATEGORY_META = {
  DEVELOPMENT: { label: '开发信', chip: 'bg-n-blue-3 text-n-blue-11' },
  QUOTATION: { label: '报价', chip: 'bg-n-iris-3 text-n-iris-11' },
  FOLLOW_UP: { label: '跟进', chip: 'bg-n-teal-3 text-n-teal-11' },
  PAYMENT_REMINDER: { label: '催款', chip: 'bg-n-ruby-3 text-n-ruby-11' },
  GREETING: { label: '节日问候', chip: 'bg-n-iris-3 text-n-iris-11' },
  OTHER: { label: '其他', chip: 'bg-n-slate-3 text-n-slate-11' },
};
const categoryOptions = Object.entries(CATEGORY_META).map(([value, m]) => ({
  value,
  label: m.label,
}));

const L = {
  new: '新建模板',
  hint: '常用邮件范本，写信时一键套用（开发信 / 报价 / 跟进 / 催款…）。',
  empty: '还没有模板，点右上「新建模板」开始',
  all: '全部',
  subjectLabel: '主题：',
  noBody: '（无正文）',
  edit: '编辑模板',
  delete: '删除',
  deleteConfirm: '确定删除该模板？',
  saved: '已保存',
  deleted: '已删除',
  error: '操作失败',
  bodyLabel: '正文（可插入图片）',
  attachLabel: '附件（套用模板时随邮件带出）',
  addFile: '加附件',
};

const activeCategory = ref('');
const filteredRecords = computed(() =>
  activeCategory.value
    ? records.value.filter(r => r.category === activeCategory.value)
    : records.value
);

const editingId = ref(null);
const form = reactive({
  name: '',
  category: 'DEVELOPMENT',
  subjectTemplate: '',
  body: '',
  description: '',
});

// 附件：existingFiles=编辑时已有(可删)、newFiles=本次新上传、removedFileIds=勾掉的已有附件id。
const existingFiles = ref([]);
const newFiles = ref([]);
const removedFileIds = ref([]);
const fileInput = ref(null);

const resetForm = () => {
  Object.assign(form, {
    name: '',
    category: 'DEVELOPMENT',
    subjectTemplate: '',
    body: '',
    description: '',
  });
  existingFiles.value = [];
  newFiles.value = [];
  removedFileIds.value = [];
};

const pickFiles = e => {
  newFiles.value = [...newFiles.value, ...Array.from(e.target.files || [])];
  e.target.value = '';
};
const removeNewFile = i => newFiles.value.splice(i, 1);
const removeExistingFile = f => {
  removedFileIds.value.push(f.id);
  existingFiles.value = existingFiles.value.filter(x => x.id !== f.id);
};
const fmtSize = n => {
  if (n < 1024) return `${n}B`;
  if (n < 1048576) return `${Math.round(n / 1024)}KB`;
  return `${(n / 1048576).toFixed(1)}MB`;
};

const openCreate = () => {
  editingId.value = null;
  resetForm();
  dialogRef.value?.open();
};

const openEdit = record => {
  editingId.value = record.id;
  Object.assign(form, {
    name: record.name || '',
    category: record.category || 'OTHER',
    subjectTemplate: record.subjectTemplate || '',
    body: record.body || '',
    description: record.description || '',
  });
  existingFiles.value = record.files || [];
  newFiles.value = [];
  removedFileIds.value = [];
  dialogRef.value?.open();
};

const handleConfirm = async () => {
  if (!form.name.trim()) return;
  // 含附件走 multipart；文本字段一并用 FormData 传（后端 params.require(:template)）。
  const fd = new FormData();
  fd.append('template[name]', form.name.trim());
  fd.append('template[category]', form.category);
  fd.append('template[subject_template]', form.subjectTemplate.trim());
  fd.append('template[body]', form.body || '');
  fd.append('template[description]', form.description.trim());
  newFiles.value.forEach(f => fd.append('template[files][]', f));
  removedFileIds.value.forEach(id =>
    fd.append('template[remove_file_ids][]', id)
  );
  try {
    if (editingId.value) {
      await TemplatesAPI.updateWithFiles(editingId.value, fd);
    } else {
      await TemplatesAPI.createWithFiles(fd);
    }
    await store.get();
    dialogRef.value?.close();
    useAlert(L.saved);
  } catch {
    useAlert(L.error);
  }
};

const removeRecord = async () => {
  // eslint-disable-next-line no-alert
  if (!editingId.value || !window.confirm(L.deleteConfirm)) return;
  try {
    await store.delete(editingId.value);
    dialogRef.value?.close();
    useAlert(L.deleted);
  } catch {
    useAlert(L.error);
  }
};

onMounted(() => store.get());
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div
      class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak"
    >
      <div>
        <h1 class="text-xl font-medium text-n-slate-12">
          {{ t('CRM.EMAIL_TEMPLATES.HEADER') }}
        </h1>
        <p class="mt-0.5 text-xs text-n-slate-10">{{ L.hint }}</p>
      </div>
      <Button
        :label="L.new"
        icon="i-lucide-plus"
        color="iris"
        @click="openCreate"
      />
    </div>

    <!-- 分类筛选 -->
    <div class="flex flex-wrap gap-1.5 px-6 pt-4">
      <button
        class="px-3 py-1 text-xs border rounded-full transition-colors"
        :class="
          activeCategory === ''
            ? 'border-n-iris-9 bg-n-iris-9 text-white'
            : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
        "
        @click="activeCategory = ''"
      >
        {{ L.all }}
      </button>
      <button
        v-for="opt in categoryOptions"
        :key="opt.value"
        class="px-3 py-1 text-xs border rounded-full transition-colors"
        :class="
          activeCategory === opt.value
            ? 'border-n-iris-9 bg-n-iris-9 text-white'
            : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
        "
        @click="activeCategory = opt.value"
      >
        {{ opt.label }}
      </button>
    </div>

    <div class="flex-1 px-6 py-4">
      <div v-if="isFetching" class="p-8 text-sm text-center text-n-slate-11">
        {{ t('CRM.EMAILS.LOADING') }}
      </div>
      <div
        v-else-if="!filteredRecords.length"
        class="p-8 text-sm text-center text-n-slate-11"
      >
        {{ L.empty }}
      </div>
      <div v-else class="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3">
        <div
          v-for="record in filteredRecords"
          :key="record.id"
          class="relative flex flex-col gap-2 p-4 transition-shadow border cursor-pointer group rounded-2xl border-n-weak bg-n-solid-1 hover:shadow-sm hover:border-n-iris-7"
          @click="openEdit(record)"
        >
          <div class="flex items-start justify-between gap-2">
            <h3 class="font-medium truncate text-n-slate-12">
              {{ record.name }}
            </h3>
            <span
              class="px-2 py-0.5 rounded-full text-[11px] flex-shrink-0"
              :class="CATEGORY_META[record.category]?.chip"
            >
              {{ CATEGORY_META[record.category]?.label || record.category }}
            </span>
          </div>
          <p
            v-if="record.subjectTemplate"
            class="text-xs truncate text-n-slate-11"
          >
            {{ L.subjectLabel }}{{ record.subjectTemplate }}
          </p>
          <p class="text-xs whitespace-pre-wrap line-clamp-3 text-n-slate-10">
            {{ record.body || L.noBody }}
          </p>
          <p
            v-if="record.description"
            class="text-[11px] text-n-slate-9 truncate"
          >
            {{ record.description }}
          </p>
        </div>
      </div>
    </div>

    <Dialog
      ref="dialogRef"
      width="3xl"
      overflow-y-auto
      :title="editingId ? L.edit : t('CRM.EMAIL_TEMPLATES.CREATE.TITLE')"
      confirm-button-color="iris"
      @confirm="handleConfirm"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-2 gap-4">
          <Input
            v-model="form.name"
            :label="t('CRM.EMAIL_TEMPLATES.FORM.NAME')"
            autofocus
          />
          <div>
            <label class="block mb-0.5 text-heading-3 text-n-slate-12">
              {{ t('CRM.EMAIL_TEMPLATES.FORM.CATEGORY') }}
            </label>
            <Select
              v-model="form.category"
              class="w-full"
              :options="categoryOptions"
            />
          </div>
        </div>
        <Input
          v-model="form.subjectTemplate"
          :label="t('CRM.EMAIL_TEMPLATES.FORM.SUBJECT')"
        />
        <div>
          <label class="block mb-0.5 text-heading-3 text-n-slate-12">
            {{ L.bodyLabel }}
          </label>
          <div
            class="overflow-y-auto border rounded-lg reset-base border-n-weak bg-n-solid-1 min-h-[180px] max-h-[360px] px-3 py-2"
          >
            <Editor
              v-model="form.body"
              editor-key="crm-email-template"
              channel-type="Channel::Email"
              enable-text-color
              :enable-canned-responses="false"
              :show-character-count="false"
            />
          </div>
        </div>

        <!-- 附件 -->
        <div>
          <label class="block mb-1 text-heading-3 text-n-slate-12">
            {{ L.attachLabel }}
          </label>
          <div class="flex flex-wrap items-center gap-2">
            <span
              v-for="f in existingFiles"
              :key="`ex-${f.id}`"
              class="inline-flex items-center gap-1 px-2 py-1 text-xs rounded-md bg-n-slate-3 text-n-slate-12"
            >
              <Icon icon="i-lucide-paperclip" class="size-3" />
              <span class="truncate max-w-[160px]">{{ f.filename }}</span>
              <button
                class="i-lucide-x size-3 text-n-slate-10 hover:text-n-slate-12"
                @click="removeExistingFile(f)"
              />
            </span>
            <span
              v-for="(f, i) in newFiles"
              :key="`new-${i}`"
              class="inline-flex items-center gap-1 px-2 py-1 text-xs rounded-md bg-n-teal-3 text-n-teal-11"
            >
              <Icon icon="i-lucide-paperclip" class="size-3" />
              <span class="truncate max-w-[160px]">{{ f.name }}</span>
              <span class="text-n-teal-11/70">{{ fmtSize(f.size) }}</span>
              <button
                class="i-lucide-x size-3 hover:opacity-70"
                @click="removeNewFile(i)"
              />
            </span>
            <button
              class="inline-flex items-center gap-1 px-2 py-1 text-xs border border-dashed rounded-md border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
              @click="fileInput?.click()"
            >
              <Icon icon="i-lucide-plus" class="size-3" />
              {{ L.addFile }}
            </button>
            <input
              ref="fileInput"
              type="file"
              multiple
              class="hidden"
              @change="pickFiles"
            />
          </div>
        </div>

        <Input
          v-model="form.description"
          :label="t('CRM.EMAIL_TEMPLATES.FORM.DESCRIPTION')"
        />
        <button
          v-if="editingId"
          class="inline-flex items-center self-start gap-1 text-xs text-n-ruby-11 hover:underline"
          @click="removeRecord"
        >
          <Icon icon="i-lucide-trash-2" class="size-3.5" />
          {{ L.delete }}
        </button>
      </div>
    </Dialog>
  </div>
</template>
