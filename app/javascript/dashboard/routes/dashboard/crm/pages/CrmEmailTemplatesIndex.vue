<script setup>
import { ref, computed, onMounted, reactive } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCrmRole } from 'dashboard/composables/useCrmRole';
import { useMapGetter } from 'dashboard/composables/store';
import { useCrmEmailTemplatesStore } from 'dashboard/stores/crm/emailTemplates';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';
import TemplatesAPI from 'dashboard/api/crm/emailTemplates';
import { uploadInlineDataUriImages } from 'dashboard/helper/uploadHelper';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';

const { t } = useI18n();
const store = useCrmEmailTemplatesStore();
const dialogRef = ref(null);

// 企业模版可管理者：超管/副管/主管；个人模版仅归属人。与销售资料同口径。
const { isAdmin, isCrmDeputyAdmin, isCrmManager } = useCrmRole();
const meId = useMapGetter('getCurrentUserID');
const canManageCompany = computed(
  () => isAdmin.value || isCrmDeputyAdmin.value || isCrmManager.value
);
const canManage = record =>
  record.scope === 'PERSONAL'
    ? record.ownerId === meId.value
    : canManageCompany.value;

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);

// 归属范围：企业模版(全员可用) / 个人模版(本人私有)。
const SCOPE_META = {
  COMPANY: { label: '企业模版', chip: 'bg-n-iris-3 text-n-iris-11' },
  PERSONAL: { label: '个人模版', chip: 'bg-n-teal-3 text-n-teal-11' },
};
const activeScope = ref('');
const readonly = ref(false);

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
  allScope: '全部',
  scopeLabel: '归属范围',
  readonlyHint:
    '企业模版仅管理员/主管可编辑；你可查看或复制内容，或另存为个人模版。',
};

// 建模板可选归属：有企业管理权可建企业/个人，否则只能建个人。
const scopeOptions = computed(() =>
  (canManageCompany.value ? ['COMPANY', 'PERSONAL'] : ['PERSONAL']).map(v => ({
    value: v,
    label: SCOPE_META[v].label,
  }))
);

const activeCategory = ref('');
const filteredRecords = computed(() =>
  records.value.filter(
    r =>
      (!activeScope.value || r.scope === activeScope.value) &&
      (!activeCategory.value || r.category === activeCategory.value)
  )
);

const editingId = ref(null);
const form = reactive({
  name: '',
  category: 'DEVELOPMENT',
  scope: 'PERSONAL',
  subjectTemplate: '',
  body: '',
  description: '',
});
const { isDirty, markPristine } = useDirtyGuard(() => form);

// 附件：existingFiles=编辑时已有(可删)、newFiles=本次新上传、removedFileIds=勾掉的已有附件id。
const existingFiles = ref([]);
const newFiles = ref([]);
const removedFileIds = ref([]);
const fileInput = ref(null);

const resetForm = () => {
  Object.assign(form, {
    name: '',
    category: 'DEVELOPMENT',
    // 有企业管理权默认建企业模版，否则只能建个人模版。
    scope: canManageCompany.value ? 'COMPANY' : 'PERSONAL',
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
  readonly.value = false;
  resetForm();
  markPristine();
  dialogRef.value?.open();
};

const openEdit = record => {
  editingId.value = record.id;
  readonly.value = !canManage(record); // 无权者（如业务员看企业模版）只读查看
  Object.assign(form, {
    name: record.name || '',
    category: record.category || 'OTHER',
    scope: record.scope || 'COMPANY',
    subjectTemplate: record.subjectTemplate || '',
    body: record.body || '',
    description: record.description || '',
  });
  existingFiles.value = record.files || [];
  newFiles.value = [];
  removedFileIds.value = [];
  markPristine();
  dialogRef.value?.open();
};

const handleConfirm = async () => {
  if (readonly.value || !form.name.trim()) return;
  // 正文里若有粘贴进来的 base64 内联图，先上传换成短链接：
  // 否则单张图几百 KB 就把正文撑爆（模板正文有 2 万字上限），保存直接失败。
  let body = form.body || '';
  try {
    body = await uploadInlineDataUriImages(body);
    form.body = body;
  } catch {
    useAlert(L.error);
    return;
  }
  // 含附件走 multipart；文本字段一并用 FormData 传（后端 params.require(:template)）。
  const fd = new FormData();
  fd.append('template[name]', form.name.trim());
  fd.append('template[category]', form.category);
  fd.append('template[scope]', form.scope);
  fd.append('template[subject_template]', form.subjectTemplate.trim());
  fd.append('template[body]', body);
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
      class="flex items-center justify-between flex-shrink-0 gap-2 px-4 py-3 border-b border-n-weak sm:px-6 sm:py-4"
    >
      <div class="min-w-0">
        <h1 class="text-xl font-medium text-n-slate-12">
          {{ t('CRM.EMAIL_TEMPLATES.HEADER') }}
        </h1>
        <p class="mt-0.5 text-xs text-n-slate-10">{{ L.hint }}</p>
      </div>
      <Button
        :label="L.new"
        icon="i-lucide-plus"
        color="iris"
        class="shrink-0"
        @click="openCreate"
      />
    </div>

    <!-- 归属范围：企业模版 / 个人模版 -->
    <div class="flex flex-wrap gap-1.5 px-4 pt-4 sm:px-6">
      <button
        v-for="opt in [
          { value: '', label: L.allScope },
          { value: 'COMPANY', label: SCOPE_META.COMPANY.label },
          { value: 'PERSONAL', label: SCOPE_META.PERSONAL.label },
        ]"
        :key="opt.value"
        class="px-3.5 py-1 text-sm font-medium rounded-lg transition-colors"
        :class="
          activeScope === opt.value
            ? 'bg-n-iris-9 text-white'
            : 'text-n-slate-11 hover:bg-n-alpha-1'
        "
        @click="activeScope = opt.value"
      >
        {{ opt.label }}
      </button>
    </div>

    <!-- 分类筛选 -->
    <div class="flex flex-wrap gap-1.5 px-4 pt-3 sm:px-6">
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

    <div class="flex-1 px-4 py-3 sm:px-6 sm:py-4">
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
            <div class="flex flex-shrink-0 gap-1">
              <span
                class="px-2 py-0.5 rounded-full text-[11px]"
                :class="SCOPE_META[record.scope]?.chip"
              >
                {{ SCOPE_META[record.scope]?.label }}
              </span>
              <span
                class="px-2 py-0.5 rounded-full text-[11px]"
                :class="CATEGORY_META[record.category]?.chip"
              >
                {{ CATEGORY_META[record.category]?.label || record.category }}
              </span>
            </div>
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
      :show-confirm-button="!readonly"
      :dirty="isDirty"
      dirty-save-label="保存"
      @confirm="handleConfirm"
      @close="markPristine"
      @save="handleConfirm"
    >
      <div class="flex flex-col gap-4">
        <div
          v-if="readonly"
          class="flex items-center gap-2 px-3 py-2 text-xs rounded-lg bg-n-slate-3 text-n-slate-11"
        >
          <Icon icon="i-lucide-lock" class="size-3.5" />
          {{ L.readonlyHint }}
        </div>
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
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
          <div>
            <label class="block mb-0.5 text-heading-3 text-n-slate-12">
              {{ L.scopeLabel }}
            </label>
            <!-- 归属：新建可选(有权者含企业)；编辑时固定不可改 -->
            <Select
              v-if="!editingId"
              v-model="form.scope"
              class="w-full"
              :options="scopeOptions"
            />
            <div
              v-else
              class="inline-flex items-center h-9 px-2.5 rounded-lg text-sm"
              :class="SCOPE_META[form.scope]?.chip"
            >
              {{ SCOPE_META[form.scope]?.label }}
            </div>
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
                type="button"
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
                type="button"
                class="i-lucide-x size-3 hover:opacity-70"
                @click="removeNewFile(i)"
              />
            </span>
            <button
              type="button"
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
          v-if="editingId && !readonly"
          type="button"
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
