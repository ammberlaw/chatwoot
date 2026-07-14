<script setup>
/* global axios */
import { ref, reactive, computed, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCrmKnowledgeDocsStore } from 'dashboard/stores/crm/knowledgeDocs';
import { useCrmKnowledgeCategoriesStore } from 'dashboard/stores/crm/knowledgeCategories';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

const { t } = useI18n();
const route = useRoute();
const { accountId } = useAccount();
const store = useCrmKnowledgeDocsStore();
const categoriesStore = useCrmKnowledgeCategoriesStore();

const activeFilter = ref(route.query.filter || 'company');
const searchQuery = ref('');
let searchTimer = null;

// 资料库归属由路由 meta 决定：销售资料(SALES) / 全公司知识(GENERAL)。同一组件两路由复用。
const currentLibrary = computed(() => route.meta.library || 'SALES');
const isGeneral = computed(() => currentLibrary.value === 'GENERAL');

const records = computed(() => store.getRecords);
const categories = computed(() => categoriesStore.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);

const crmBase = () => `/api/v1/accounts/${accountId.value}/crm`;

// 首字色块 / 列头胶囊配色：按名称散列取色（字面量 class，避免被 Tailwind purge）。
const PALETTE = [
  'bg-n-blue-3 text-n-blue-11',
  'bg-n-teal-3 text-n-teal-11',
  'bg-n-amber-3 text-n-amber-11',
  'bg-n-iris-3 text-n-iris-11',
  'bg-n-ruby-3 text-n-ruby-11',
];
const hash = str => {
  let sum = 0;
  for (const ch of str || '') sum += ch.charCodeAt(0);
  return sum;
};
const colorOf = name => PALETTE[hash(name) % PALETTE.length];
const initial = name => (name || '?').trim().charAt(0).toUpperCase();
const scopeLabel = scope => (scope === 'PERSONAL' ? '个人' : '公司');
const fmtDateTime = v => (v ? new Date(v).toLocaleString() : '');

// 看板列：分类表顺序 + 文档里出现但已不在分类表的（兜底，不丢文档）+ 未分类。
const columns = computed(() => {
  const known = categories.value.map(c => c.name);
  const orphans = [
    ...new Set(
      records.value
        .map(r => r.category)
        .filter(cat => cat && !known.includes(cat))
    ),
  ];
  const cols = [
    ...categories.value.map(c => ({ id: c.id, name: c.name })),
    ...orphans.map(name => ({ id: null, name })),
  ];
  const hasUncategorized = records.value.some(r => !r.category);
  if (hasUncategorized) cols.push({ id: null, name: '', uncategorized: true });
  return cols.map(col => ({
    ...col,
    docs: records.value.filter(doc =>
      col.uncategorized ? !doc.category : doc.category === col.name
    ),
  }));
});

const categoryOptions = computed(() =>
  categories.value.map(c => ({ value: c.name, label: c.name }))
);
const scopeOptions = [
  { value: 'COMPANY', label: '公司' },
  { value: 'PERSONAL', label: '个人' },
];

const filterTabs = [
  { key: 'company', label: t('CRM.KNOWLEDGE_DOCS.FILTERS.COMPANY') },
  { key: 'mine', label: t('CRM.KNOWLEDGE_DOCS.FILTERS.MINE') },
];

const fetchRecords = () => {
  store.get({
    library: currentLibrary.value,
    filter: activeFilter.value,
    q: searchQuery.value.trim() || undefined,
    per_page: 200,
  });
};

// 在两个资料库路由间切换时（同组件复用），重新拉取对应库的文档。
watch(currentLibrary, fetchRecords);

const setFilter = key => {
  activeFilter.value = key;
  fetchRecords();
};

const onSearchInput = () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(fetchRecords, 300);
};

const fmtDate = v => (v ? new Date(v).toLocaleDateString() : '');

// ── 拖拽：卡片跨列改分类 / 分类列排序 ──
const dragDocId = ref(null);
const dragColId = ref(null);

const onDropDoc = async col => {
  const id = dragDocId.value;
  dragDocId.value = null;
  if (id == null) return;
  const doc = records.value.find(d => d.id === id);
  if (!doc) return;
  const target = col.uncategorized ? null : col.name;
  if ((doc.category || null) === (target || null)) return;
  try {
    await store.update({ id, category: target });
  } catch {
    useAlert(t('CRM.KNOWLEDGE_DOCS.EDIT.ERROR'));
  }
};

const onColDrop = async targetCol => {
  const id = dragColId.value;
  dragColId.value = null;
  if (!id || !targetCol.id || id === targetCol.id) return;
  const list = [...categories.value];
  const from = list.findIndex(c => c.id === id);
  const to = list.findIndex(c => c.id === targetCol.id);
  if (from < 0 || to < 0) return;
  const [moved] = list.splice(from, 1);
  list.splice(to, 0, moved);
  try {
    await Promise.all(
      list
        .map((c, i) =>
          c.position !== i ? categoriesStore.update({ id: c.id, position: i }) : null
        )
        .filter(Boolean)
    );
    await categoriesStore.get();
  } catch {
    useAlert(t('CRM.KNOWLEDGE_DOCS.CATEGORY.SAVE_ERROR'));
  }
};

// 列上的 drop 同时承接「卡片改分类」和「列排序」，按当前拖拽对象分流。
const onColumnDrop = col => {
  if (dragColId.value != null) onColDrop(col);
  else onDropDoc(col);
};

// ── 右侧详情侧边栏（查看 / 内联编辑 / 新建 / 时间轴）──
const PANEL_TABS = [
  { key: 'detail', label: t('CRM.KNOWLEDGE_DOCS.PANEL.DETAIL') },
  { key: 'timeline', label: t('CRM.KNOWLEDGE_DOCS.PANEL.TIMELINE') },
];
const panelMode = ref(null); // 'view' | 'edit' | 'create' | null
const isForm = computed(
  () => panelMode.value === 'edit' || panelMode.value === 'create'
);
const isCreate = computed(() => panelMode.value === 'create');
const selectedDoc = ref(null);
const panelTab = ref('detail');
const panelAudits = ref([]);
const panelAttachments = ref([]);
const pendingFiles = ref([]);
const saving = ref(false);
const uploading = ref(false);
const panelFileInput = ref(null);
const editForm = reactive({
  name: '',
  category: '',
  scope: 'COMPANY',
  summary: '',
  body: '',
});

const AUDIT_FIELD_LABELS = {
  name: '标题',
  category: '分类',
  scope: '范围',
  summary: '摘要',
  body: '正文',
  owner_id: '归属人',
};
const auditMessage = audit => {
  if (audit.action === 'create') return '创建了文档';
  const fields = (audit.changed_fields || [])
    .filter(f => AUDIT_FIELD_LABELS[f])
    .map(f => AUDIT_FIELD_LABELS[f]);
  return fields.length ? `编辑了 ${fields.join('、')}` : '编辑了文档';
};

const resetForm = (category = '') => {
  editForm.name = '';
  editForm.category = category || categories.value[0]?.name || '';
  editForm.scope = 'COMPANY';
  editForm.summary = '';
  editForm.body = '';
};

const openPanel = doc => {
  selectedDoc.value = doc;
  panelMode.value = 'view';
  panelTab.value = 'detail';
  panelAudits.value = [];
  panelAttachments.value = doc.files || [];
};
const openCreatePanel = category => {
  selectedDoc.value = null;
  panelMode.value = 'create';
  panelTab.value = 'detail';
  pendingFiles.value = [];
  resetForm(category);
};
const closePanel = () => {
  panelMode.value = null;
  selectedDoc.value = null;
};

const fetchAudits = async () => {
  try {
    const { data } = await axios.get(
      `${crmBase()}/knowledge_docs/${selectedDoc.value.id}/audits`
    );
    panelAudits.value = data.payload || [];
  } catch {
    panelAudits.value = [];
  }
};
const setPanelTab = key => {
  panelTab.value = key;
  if (key === 'timeline' && !panelAudits.value.length) fetchAudits();
};

const startEdit = () => {
  const doc = selectedDoc.value;
  editForm.name = doc.name || '';
  editForm.category = doc.category || '';
  editForm.scope = doc.scope || 'COMPANY';
  editForm.summary = doc.summary || '';
  editForm.body = doc.body || '';
  panelMode.value = 'edit';
};
const cancelForm = () => {
  if (isCreate.value) closePanel();
  else panelMode.value = 'view';
};

const saveForm = async () => {
  if (!editForm.name.trim()) return;
  saving.value = true;
  const payload = {
    name: editForm.name.trim(),
    category: editForm.category || null,
    scope: editForm.scope,
    library: currentLibrary.value,
    summary: editForm.summary.trim() || null,
    body: editForm.body || null,
  };
  try {
    if (isCreate.value) {
      const created = await store.create({
        ...payload,
        __files: pendingFiles.value,
      });
      useAlert(t('CRM.KNOWLEDGE_DOCS.CREATE.SUCCESS'));
      fetchRecords();
      if (created) openPanel(created);
      else closePanel();
    } else {
      const updated = await store.update({ id: selectedDoc.value.id, ...payload });
      selectedDoc.value = updated || selectedDoc.value;
      panelMode.value = 'view';
      panelAudits.value = [];
      fetchRecords();
      useAlert(t('CRM.KNOWLEDGE_DOCS.EDIT.SUCCESS'));
    }
  } catch {
    useAlert(
      isCreate.value
        ? t('CRM.KNOWLEDGE_DOCS.CREATE.ERROR')
        : t('CRM.KNOWLEDGE_DOCS.EDIT.ERROR')
    );
  } finally {
    saving.value = false;
  }
};

const triggerPanelUpload = () => panelFileInput.value?.click();
const onPanelFiles = async event => {
  const files = Array.from(event.target.files || []);
  event.target.value = '';
  if (!files.length) return;

  // 新建模式：附件暂存内存，随创建 multipart 提交。
  if (isCreate.value) {
    pendingFiles.value = [...pendingFiles.value, ...files];
    return;
  }

  uploading.value = true;
  const fd = new FormData();
  files.forEach(f => fd.append('files[]', f));
  try {
    const { data } = await axios.post(
      `${crmBase()}/knowledge_docs/${selectedDoc.value.id}/attach`,
      fd,
      { headers: { 'Content-Type': 'multipart/form-data' } }
    );
    panelAttachments.value = data.files || [];
    fetchRecords();
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
    const { data } = await axios.delete(
      `${crmBase()}/knowledge_docs/${selectedDoc.value.id}/attach/${id}`
    );
    panelAttachments.value = data.files || [];
    fetchRecords();
  } catch {
    useAlert(t('CRM.KNOWLEDGE_DOCS.ATTACH.DELETE_ERROR'));
  }
};

// ── 分类管理（新增 / 重命名 / 删除空分类）──
const adding = ref(false);
const newCategoryName = ref('');
const editingId = ref(null);
const editingName = ref('');

const startAdd = () => {
  adding.value = true;
  newCategoryName.value = '';
};
const saveAdd = async () => {
  const name = newCategoryName.value.trim();
  adding.value = false;
  if (!name) return;
  try {
    await categoriesStore.create({ name, position: categories.value.length });
    await categoriesStore.get();
  } catch {
    useAlert(t('CRM.KNOWLEDGE_DOCS.CATEGORY.SAVE_ERROR'));
  }
};

const startRename = col => {
  editingId.value = col.id;
  editingName.value = col.name;
};
const saveRename = async () => {
  const id = editingId.value;
  const name = editingName.value.trim();
  editingId.value = null;
  if (!id || !name) return;
  try {
    await categoriesStore.update({ id, name });
    await categoriesStore.get();
    fetchRecords();
  } catch {
    useAlert(t('CRM.KNOWLEDGE_DOCS.CATEGORY.SAVE_ERROR'));
  }
};

const removeCategory = async col => {
  if (!col.id || col.docs.length) return;
  try {
    await categoriesStore.delete(col.id);
  } catch {
    useAlert(t('CRM.KNOWLEDGE_DOCS.CATEGORY.DELETE_ERROR'));
  }
};

onMounted(() => {
  fetchRecords();
  categoriesStore.get();
});
watch(
  () => route.query.filter,
  value => {
    activeFilter.value = value || 'company';
    closePanel();
    fetchRecords();
  }
);
</script>

<template>
  <div class="flex w-full h-full overflow-hidden bg-n-background">
    <div class="flex flex-col flex-1 min-w-0 overflow-hidden">
      <div
        class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak"
      >
        <div>
          <h1 class="text-xl font-medium text-n-slate-12">
            {{
              isGeneral
                ? t('CRM.KNOWLEDGE_DOCS.HEADER_GENERAL')
                : t('CRM.KNOWLEDGE_DOCS.HEADER')
            }}
          </h1>
          <p class="mt-0.5 text-xs text-n-slate-10">
            {{
              isGeneral
                ? t('CRM.KNOWLEDGE_DOCS.SUBTITLE_GENERAL')
                : t('CRM.KNOWLEDGE_DOCS.SUBTITLE')
            }}
          </p>
        </div>
        <Button
          :label="t('CRM.KNOWLEDGE_DOCS.NEW')"
          icon="i-lucide-plus"
          color="amber"
          @click="openCreatePanel()"
        />
      </div>

      <div class="flex items-center gap-2 px-6 py-3 border-b border-n-weak">
        <Button
          v-for="tab in filterTabs"
          :key="tab.key"
          :label="tab.label"
          size="sm"
          :variant="activeFilter === tab.key ? 'solid' : 'faded'"
          :color="activeFilter === tab.key ? 'amber' : 'slate'"
          @click="setFilter(tab.key)"
        />
        <Input
          v-model="searchQuery"
          :placeholder="t('CRM.KNOWLEDGE_DOCS.SEARCH_PLACEHOLDER')"
          class="ml-auto w-56"
          @input="onSearchInput"
        />
      </div>

      <div
        v-if="isFetching"
        class="flex items-center justify-center flex-1 text-base text-n-slate-11"
      >
        {{ t('CRM.KNOWLEDGE_DOCS.LOADING') }}
      </div>

      <!-- 分类看板：一列一分类，横向滚动，分类可增/改/删 -->
      <div v-else class="flex flex-1 gap-4 px-6 py-4 overflow-x-auto">
        <div
          v-for="col in columns"
          :key="col.id || col.name || 'uncategorized'"
          class="flex flex-col group/col w-72 shrink-0 rounded-xl"
          :class="dragDocId != null ? 'transition-colors' : ''"
          @dragover.prevent
          @drop="onColumnDrop(col)"
        >
          <div class="flex items-center gap-1.5 mb-3">
            <input
              v-if="editingId && editingId === col.id"
              v-model="editingName"
              class="w-40 h-7 px-2 text-sm border rounded-md border-n-weak bg-n-solid-1 text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-amber-8"
              @keyup.enter="saveRename"
              @blur="saveRename"
            />
            <template v-else>
              <span
                class="px-2 py-0.5 text-sm font-medium rounded-md"
                :class="[
                  col.uncategorized
                    ? 'bg-n-slate-3 text-n-slate-11'
                    : colorOf(col.name),
                  col.id ? 'cursor-grab active:cursor-grabbing' : '',
                ]"
                :draggable="col.id ? 'true' : 'false'"
                @dragstart.stop="dragColId = col.id"
                @dragend="dragColId = null"
              >
                {{
                  col.uncategorized
                    ? t('CRM.KNOWLEDGE_DOCS.UNCATEGORIZED')
                    : col.name
                }}
              </span>
              <span class="text-sm text-n-slate-10">
                {{ col.docs.length || '' }}
              </span>
              <div
                v-if="col.id"
                class="flex items-center gap-0.5 ml-auto opacity-0 group-hover/col:opacity-100"
              >
                <button
                  type="button"
                  class="p-1 rounded text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-1"
                  :title="t('CRM.KNOWLEDGE_DOCS.CATEGORY.RENAME')"
                  @click="startRename(col)"
                >
                  <span class="i-lucide-pencil size-3.5" />
                </button>
                <button
                  v-if="!col.docs.length"
                  type="button"
                  class="p-1 rounded text-n-slate-10 hover:text-n-ruby-11 hover:bg-n-alpha-1"
                  :title="t('CRM.KNOWLEDGE_DOCS.CATEGORY.DELETE')"
                  @click="removeCategory(col)"
                >
                  <span class="i-lucide-trash-2 size-3.5" />
                </button>
              </div>
            </template>
          </div>

          <div class="flex flex-col gap-2">
            <button
              v-for="doc in col.docs"
              :key="doc.id"
              type="button"
              draggable="true"
              class="flex flex-col gap-2 p-3 text-left transition-all border cursor-grab active:cursor-grabbing rounded-xl bg-n-solid-1 border-n-weak hover:border-n-slate-6 hover:shadow-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-amber-8"
              :class="[
                selectedDoc && selectedDoc.id === doc.id
                  ? 'border-n-blue-8 ring-1 ring-n-blue-8'
                  : '',
                dragDocId === doc.id ? 'opacity-40' : '',
              ]"
              @click="openPanel(doc)"
              @dragstart.stop="dragDocId = doc.id"
              @dragend="dragDocId = null"
            >
              <div class="flex items-center gap-2 min-w-0">
                <span
                  class="flex items-center justify-center text-xs font-semibold rounded shrink-0 size-6"
                  :class="colorOf(doc.name)"
                >
                  {{ initial(doc.name) }}
                </span>
                <span class="text-sm font-medium truncate text-n-slate-12">
                  {{ doc.name }}
                </span>
                <span
                  v-if="doc.files && doc.files.length"
                  class="inline-flex items-center gap-0.5 ml-auto text-xs shrink-0 text-n-slate-10"
                >
                  <span class="i-lucide-paperclip size-3" />
                  {{ doc.files.length }}
                </span>
              </div>
              <div class="flex items-center gap-1.5 text-xs text-n-slate-10">
                <span class="i-lucide-align-left size-3.5 shrink-0" />
                <span class="truncate">{{ doc.summary || '摘要' }}</span>
              </div>
              <div
                class="flex items-center gap-1 pt-1.5 text-xs border-t text-n-slate-10 border-n-weak"
              >
                <span class="i-lucide-clock size-3 shrink-0" />
                {{ fmtDate(doc.updatedAt) }}
              </div>
            </button>

            <button
              type="button"
              class="flex items-center gap-1 px-3 py-2 text-sm rounded-xl text-n-slate-10 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-amber-8"
              @click="openCreatePanel(col.uncategorized ? undefined : col.name)"
            >
              <span class="i-lucide-plus size-4" />
              {{ t('CRM.KNOWLEDGE_DOCS.ADD_IN_COLUMN') }}
            </button>
          </div>
        </div>

        <!-- 新增分类列 -->
        <div class="flex flex-col w-72 shrink-0">
          <input
            v-if="adding"
            v-model="newCategoryName"
            :placeholder="t('CRM.KNOWLEDGE_DOCS.CATEGORY.NAME_PLACEHOLDER')"
            class="h-8 px-2 text-sm border rounded-md border-n-weak bg-n-solid-1 text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-amber-8"
            @keyup.enter="saveAdd"
            @blur="saveAdd"
          />
          <button
            v-else
            type="button"
            class="flex items-center gap-1 px-3 py-2 text-sm rounded-lg text-n-slate-10 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-amber-8"
            @click="startAdd"
          >
            <span class="i-lucide-plus size-4" />
            {{ t('CRM.KNOWLEDGE_DOCS.CATEGORY.ADD') }}
          </button>
        </div>
      </div>
    </div>

    <!-- 右侧详情侧边栏 -->
    <aside
      v-if="panelMode"
      class="flex flex-col w-[420px] flex-shrink-0 overflow-hidden border-l border-n-weak bg-n-solid-1"
    >
      <div
        class="flex items-start justify-between gap-2 px-5 py-4 border-b border-n-weak"
      >
        <div class="flex items-center gap-2.5 min-w-0">
          <span
            v-if="isCreate"
            class="flex items-center justify-center rounded-lg shrink-0 size-9 bg-n-blue-3 text-n-blue-11"
          >
            <span class="i-lucide-file-plus size-5" />
          </span>
          <span
            v-else
            class="flex items-center justify-center text-sm font-semibold rounded-lg shrink-0 size-9"
            :class="colorOf(selectedDoc.name)"
          >
            {{ initial(selectedDoc.name) }}
          </span>
          <div class="min-w-0">
            <div class="text-base font-semibold truncate text-n-slate-12">
              {{ isCreate ? t('CRM.KNOWLEDGE_DOCS.PANEL.NEW_TITLE') : selectedDoc.name }}
            </div>
            <div v-if="!isCreate" class="text-xs text-n-slate-10">
              {{ selectedDoc.category || t('CRM.KNOWLEDGE_DOCS.UNCATEGORIZED') }}
            </div>
          </div>
        </div>
        <button
          type="button"
          class="p-1 rounded text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-1"
          @click="closePanel"
        >
          <span class="i-lucide-x size-4" />
        </button>
      </div>

      <div v-if="!isCreate" class="flex gap-1 px-5 pt-3 border-b border-n-weak">
        <button
          v-for="tab in PANEL_TABS"
          :key="tab.key"
          type="button"
          class="px-3 py-2 text-sm font-medium border-b-2 -mb-px"
          :class="
            panelTab === tab.key
              ? 'border-n-blue-9 text-n-slate-12'
              : 'border-transparent text-n-slate-10 hover:text-n-slate-12'
          "
          @click="setPanelTab(tab.key)"
        >
          {{ tab.label }}
        </button>
      </div>

      <div class="flex-1 overflow-y-auto">
        <!-- 详情 / 编辑 / 新建 -->
        <div v-if="panelTab === 'detail'" class="flex flex-col gap-4 p-5">
          <template v-if="!isForm">
            <div class="flex items-center gap-2">
              <span
                class="px-2 py-0.5 text-xs font-medium rounded-full"
                :class="colorOf(selectedDoc.category)"
              >
                {{
                  selectedDoc.category ||
                  t('CRM.KNOWLEDGE_DOCS.UNCATEGORIZED')
                }}
              </span>
              <span
                class="px-2 py-0.5 text-xs font-medium rounded-full bg-n-alpha-2 text-n-slate-11"
              >
                {{ scopeLabel(selectedDoc.scope) }}
              </span>
            </div>

            <div>
              <div class="mb-1 text-xs font-medium text-n-slate-10">
                {{ t('CRM.KNOWLEDGE_DOCS.PANEL.SUMMARY') }}
              </div>
              <p class="text-sm whitespace-pre-wrap text-n-slate-12">
                {{ selectedDoc.summary || '—' }}
              </p>
            </div>

            <div>
              <div class="mb-1 text-xs font-medium text-n-slate-10">
                {{ t('CRM.KNOWLEDGE_DOCS.PANEL.BODY') }}
              </div>
              <p
                class="text-sm leading-relaxed whitespace-pre-wrap text-n-slate-12"
              >
                {{ selectedDoc.body || '—' }}
              </p>
            </div>

            <div>
              <div
                class="flex items-center justify-between mb-1.5 text-xs font-medium text-n-slate-10"
              >
                <span>{{ t('CRM.KNOWLEDGE_DOCS.PANEL.ATTACHMENTS') }}</span>
                <button
                  type="button"
                  class="inline-flex items-center gap-1 text-n-blue-11 hover:underline disabled:opacity-50"
                  :disabled="uploading"
                  @click="triggerPanelUpload"
                >
                  <span class="i-lucide-paperclip size-3.5" />
                  {{
                    uploading
                      ? t('CRM.KNOWLEDGE_DOCS.ATTACH.UPLOADING')
                      : t('CRM.KNOWLEDGE_DOCS.ATTACH.ADD')
                  }}
                </button>
              </div>
              <div
                v-if="!panelAttachments.length"
                class="text-xs text-n-slate-10"
              >
                —
              </div>
              <div
                v-for="file in panelAttachments"
                :key="file.id"
                class="flex items-center justify-between px-3 py-2 mb-1.5 border rounded-lg border-n-weak"
              >
                <a
                  :href="file.url"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="flex items-center gap-2 text-sm truncate text-n-blue-11 hover:underline"
                >
                  <span class="i-lucide-file size-4 shrink-0" />
                  <span class="truncate">{{ file.filename }}</span>
                </a>
                <button
                  type="button"
                  class="text-n-slate-10 hover:text-n-ruby-11 shrink-0"
                  @click="removeAttachment(file.id)"
                >
                  <span class="i-lucide-x size-4" />
                </button>
              </div>
            </div>

            <div class="pt-2">
              <Button
                :label="t('CRM.KNOWLEDGE_DOCS.PANEL.EDIT')"
                icon="i-lucide-pencil"
                size="sm"
                color="slate"
                variant="faded"
                @click="startEdit"
              />
            </div>
          </template>

          <!-- 内联编辑 / 新建表单 -->
          <template v-else>
            <Input
              v-model="editForm.name"
              :label="t('CRM.KNOWLEDGE_DOCS.FORM.NAME')"
              autofocus
            />
            <div class="grid grid-cols-2 gap-3">
              <div class="flex flex-col min-w-0 gap-1">
                <label class="mb-0.5 text-heading-3 text-n-slate-12">
                  {{ t('CRM.KNOWLEDGE_DOCS.FORM.CATEGORY') }}
                </label>
                <Select v-model="editForm.category" :options="categoryOptions" />
              </div>
              <div class="flex flex-col min-w-0 gap-1">
                <label class="mb-0.5 text-heading-3 text-n-slate-12">
                  {{ t('CRM.KNOWLEDGE_DOCS.FORM.SCOPE') }}
                </label>
                <Select v-model="editForm.scope" :options="scopeOptions" />
              </div>
            </div>
            <Input
              v-model="editForm.summary"
              :label="t('CRM.KNOWLEDGE_DOCS.FORM.SUMMARY')"
            />
            <TextArea
              v-model="editForm.body"
              :label="t('CRM.KNOWLEDGE_DOCS.FORM.BODY')"
            />

            <!-- 新建模式：附件暂存内存 -->
            <div v-if="isCreate">
              <div
                class="flex items-center justify-between mb-1.5 text-xs font-medium text-n-slate-10"
              >
                <span>{{ t('CRM.KNOWLEDGE_DOCS.PANEL.ATTACHMENTS') }}</span>
                <button
                  type="button"
                  class="inline-flex items-center gap-1 text-n-blue-11 hover:underline"
                  @click="triggerPanelUpload"
                >
                  <span class="i-lucide-paperclip size-3.5" />
                  {{ t('CRM.KNOWLEDGE_DOCS.ATTACH.ADD') }}
                </button>
              </div>
              <div
                v-for="(file, index) in pendingFiles"
                :key="`pending-${index}`"
                class="flex items-center justify-between px-3 py-2 mb-1.5 border rounded-lg border-n-weak"
              >
                <span class="flex items-center gap-2 text-sm truncate text-n-slate-12">
                  <span class="i-lucide-file size-4 shrink-0" />
                  <span class="truncate">{{ file.name }}</span>
                </span>
                <button
                  type="button"
                  class="text-n-slate-10 hover:text-n-ruby-11 shrink-0"
                  @click="removePending(index)"
                >
                  <span class="i-lucide-x size-4" />
                </button>
              </div>
            </div>

            <div class="flex gap-2 pt-1">
              <Button
                :label="
                  isCreate
                    ? t('CRM.KNOWLEDGE_DOCS.PANEL.CREATE')
                    : t('CRM.KNOWLEDGE_DOCS.PANEL.SAVE')
                "
                size="sm"
                color="amber"
                :is-loading="saving"
                :disabled="!editForm.name.trim()"
                @click="saveForm"
              />
              <Button
                :label="t('CRM.KNOWLEDGE_DOCS.PANEL.CANCEL')"
                size="sm"
                color="slate"
                variant="faded"
                @click="cancelForm"
              />
            </div>
          </template>

          <input
            ref="panelFileInput"
            type="file"
            multiple
            class="hidden"
            @change="onPanelFiles"
          />
        </div>

        <!-- 时间轴 -->
        <div v-else-if="panelTab === 'timeline'" class="p-5">
          <div
            v-if="!panelAudits.length"
            class="py-6 text-sm text-center text-n-slate-10"
          >
            {{ t('CRM.KNOWLEDGE_DOCS.PANEL.NO_HISTORY') }}
          </div>
          <div v-else class="flex flex-col">
            <div
              v-for="(a, i) in panelAudits"
              :key="a.id"
              class="relative flex gap-3 pb-5"
            >
              <span
                v-if="i < panelAudits.length - 1"
                class="absolute left-[4px] top-4 bottom-0 w-px bg-n-weak"
              />
              <span
                class="z-10 mt-1 border-2 rounded-full size-2.5 shrink-0 border-n-blue-9 bg-n-solid-1"
              />
              <div class="min-w-0">
                <div class="text-xs text-n-slate-10">
                  {{ fmtDateTime(a.created_at) }}
                </div>
                <div class="mt-0.5 text-sm text-n-slate-12">
                  <span class="font-medium">{{ a.user_name }}</span>
                  {{ auditMessage(a) }}
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </aside>
  </div>
</template>
