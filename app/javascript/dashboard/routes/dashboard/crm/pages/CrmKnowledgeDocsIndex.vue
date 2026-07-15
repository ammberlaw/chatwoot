<script setup>
/* global axios */
import { ref, reactive, computed, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { useCrmRole } from 'dashboard/composables/useCrmRole';
import { emitter } from 'shared/helpers/mitt';
import { useCrmKnowledgeDocsStore } from 'dashboard/stores/crm/knowledgeDocs';
import { useCrmKnowledgeCategoriesStore } from 'dashboard/stores/crm/knowledgeCategories';
import CrmMemberAPI from 'dashboard/api/crm/members';
import DocCenterSettingsAPI from 'dashboard/api/crm/docCenterSettings';
import DocSectionsAPI from 'dashboard/api/crm/docSections';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
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

// ── 权限：公司文档管理权=管理员/副管理员/部门负责人（文档中心另加指定负责人）；其他人只能浏览下载 ──
const currentUserId = useMapGetter('getCurrentUserID');
const { isAdmin, isCrmDeputyAdmin, isCrmManager } = useCrmRole();
const docCenterOwnerId = ref(null);
const docCenterOwnerName = ref('');
const members = ref([]);

const fetchDocCenterSetting = async () => {
  try {
    const { data } = await DocCenterSettingsAPI.get();
    docCenterOwnerId.value = data.owner_id;
    docCenterOwnerName.value = data.owner_name || '';
  } catch {
    docCenterOwnerId.value = null;
  }
};
const fetchMembers = async () => {
  try {
    const { data } = await CrmMemberAPI.get();
    members.value = data.payload || [];
  } catch {
    members.value = [];
  }
};
const memberOptions = computed(() => [
  { value: '', label: t('CRM.KNOWLEDGE_DOCS.OWNER.NONE') },
  ...members.value.map(m => ({ value: String(m.user_id), label: m.name })),
]);
const setDocCenterOwner = async value => {
  try {
    await DocCenterSettingsAPI.updateSetting({
      setting: { owner_id: value || null },
    });
    await fetchDocCenterSetting();
    useAlert(t('CRM.KNOWLEDGE_DOCS.OWNER.SAVED'));
  } catch {
    useAlert(t('CRM.KNOWLEDGE_DOCS.OWNER.SAVE_ERROR'));
  }
};

const canManageCompany = computed(
  () =>
    isAdmin.value ||
    isCrmDeputyAdmin.value ||
    isCrmManager.value ||
    (isGeneral.value && docCenterOwnerId.value === currentUserId.value)
);

// ── 资料板块（文档中心）：侧边栏子项经 ?section_id= 驱动切换；管理员可按部门配置各板块可见性 ──
const sections = ref([]);
const activeSectionId = ref(route.query.section_id || '');
const fetchSections = async () => {
  try {
    const { data } = await DocSectionsAPI.get();
    sections.value = data.payload || [];
  } catch {
    sections.value = [];
  }
};
const sectionFormOptions = computed(() => [
  { value: '', label: t('CRM.KNOWLEDGE_DOCS.SECTION.NONE') },
  ...sections.value.map(s => ({ value: String(s.id), label: s.name })),
]);

// 板块可见性设置弹窗（管理员）：每板块勾选可见部门，全不勾 = 全员可见
const sectionDialogRef = ref(null);
const departments = ref([]);
const sectionDraft = ref([]);
const savingSections = ref(false);
const newSectionName = ref('');
const addingSection = ref(false);
const pendingSectionDeleteId = ref(null);
const openSectionDialog = async () => {
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/org/departments`
    );
    departments.value = data.payload || [];
  } catch {
    departments.value = [];
  }
  sectionDraft.value = sections.value.map(s => ({
    id: s.id,
    name: s.name,
    isDefault: s.is_default,
    departmentIds: [...(s.department_ids || [])],
  }));
  newSectionName.value = '';
  pendingSectionDeleteId.value = null;
  sectionDialogRef.value?.open();
};
// 自定义新增板块：立即入库并追加到草稿；删除仅限自定义板块（两步确认）。
const addSection = async () => {
  const name = newSectionName.value.trim();
  if (!name || addingSection.value) return;
  addingSection.value = true;
  try {
    const { data } = await DocSectionsAPI.createSection({
      section: { name },
    });
    sectionDraft.value.push({
      id: data.id,
      name: data.name,
      isDefault: false,
      departmentIds: [...(data.department_ids || [])],
    });
    newSectionName.value = '';
    await fetchSections();
    emitter.emit('crmDocSectionsUpdated');
    useAlert(t('CRM.KNOWLEDGE_DOCS.SECTION.ADDED'));
  } catch {
    useAlert(t('CRM.KNOWLEDGE_DOCS.SECTION.ADD_ERROR'));
  } finally {
    addingSection.value = false;
  }
};
const deleteSection = async draft => {
  if (pendingSectionDeleteId.value !== draft.id) {
    pendingSectionDeleteId.value = draft.id;
    return;
  }
  pendingSectionDeleteId.value = null;
  try {
    await DocSectionsAPI.deleteSection(draft.id);
    sectionDraft.value = sectionDraft.value.filter(s => s.id !== draft.id);
    await fetchSections();
    emitter.emit('crmDocSectionsUpdated');
    useAlert(t('CRM.KNOWLEDGE_DOCS.SECTION.DELETED'));
  } catch {
    useAlert(t('CRM.KNOWLEDGE_DOCS.SECTION.DELETE_ERROR'));
  }
};
const toggleSectionDept = (draft, deptId) => {
  const idx = draft.departmentIds.indexOf(deptId);
  if (idx >= 0) draft.departmentIds.splice(idx, 1);
  else draft.departmentIds.push(deptId);
};
const saveSectionVisibility = async () => {
  savingSections.value = true;
  try {
    await Promise.all(
      sectionDraft.value.map(draft =>
        DocSectionsAPI.updateSection(draft.id, {
          section: { department_ids: draft.departmentIds },
        })
      )
    );
    await fetchSections();
    useAlert(t('CRM.KNOWLEDGE_DOCS.SECTION.SAVED'));
    sectionDialogRef.value?.close();
  } catch {
    useAlert(t('CRM.KNOWLEDGE_DOCS.SECTION.SAVE_ERROR'));
  } finally {
    savingSections.value = false;
  }
};
// 个人文档归属人可管；公司文档按上面的管理权。
const canManageDoc = doc =>
  doc?.scope === 'PERSONAL'
    ? doc.ownerId === currentUserId.value
    : canManageCompany.value;
// 新建入口：文档中心仅管理员/负责人；销售资料人人可建（业务员建的是个人文档）。
const canCreateDocs = computed(() =>
  isGeneral.value ? canManageCompany.value : true
);

const records = computed(() => store.getRecords);
const categories = computed(() => categoriesStore.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);

const crmBase = () => `/api/v1/accounts/${accountId.value}/crm`;

// 首字色块 / 列头胶囊配色：按名称散列取色（字面量 class，避免被 Tailwind purge）。
const PALETTE = [
  'bg-n-blue-3 text-n-blue-11',
  'bg-n-teal-3 text-n-teal-11',
  'bg-n-iris-3 text-n-iris-11',
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

// 文档中心（GENERAL）没有「我的文档」——个人资料在 CRM 知识库维护；此处只有公司文档（+管理员回收站）。
const filterTabs = computed(() => [
  { key: 'company', label: t('CRM.KNOWLEDGE_DOCS.FILTERS.COMPANY') },
  ...(isGeneral.value
    ? []
    : [{ key: 'mine', label: t('CRM.KNOWLEDGE_DOCS.FILTERS.MINE') }]),
  ...((isAdmin.value || isCrmDeputyAdmin.value) && isGeneral.value
    ? [{ key: 'recycle', label: t('CRM.KNOWLEDGE_DOCS.RECYCLE.TAB') }]
    : []),
]);

// ── 文档回收站（仅管理员）：删除的文档进这里，可恢复或彻底删除 ──
const isRecycle = computed(() => activeFilter.value === 'recycle');
const recycleDocs = ref([]);
const loadingRecycle = ref(false);
const pendingPurgeId = ref(null);
const pendingPurgeAll = ref(false);
const recycleUrl = path =>
  `/api/v1/accounts/${accountId.value}/crm/knowledge_docs${path}`;
const fetchRecycleBin = async () => {
  loadingRecycle.value = true;
  pendingPurgeId.value = null;
  pendingPurgeAll.value = false;
  try {
    const { data } = await axios.get(recycleUrl('/recycle_bin'));
    recycleDocs.value = data.payload || [];
  } catch {
    recycleDocs.value = [];
  } finally {
    loadingRecycle.value = false;
  }
};
const restoreDoc = async doc => {
  try {
    await axios.post(recycleUrl(`/${doc.id}/restore`));
    recycleDocs.value = recycleDocs.value.filter(d => d.id !== doc.id);
    useAlert(t('CRM.KNOWLEDGE_DOCS.RECYCLE.RESTORED'));
  } catch {
    useAlert(t('CRM.KNOWLEDGE_DOCS.RECYCLE.ERROR'));
  }
};
// 彻底删除/清空均两步确认。
const purgeDoc = async doc => {
  if (pendingPurgeId.value !== doc.id) {
    pendingPurgeId.value = doc.id;
    return;
  }
  pendingPurgeId.value = null;
  try {
    await axios.post(recycleUrl(`/${doc.id}/purge`));
    recycleDocs.value = recycleDocs.value.filter(d => d.id !== doc.id);
    useAlert(t('CRM.KNOWLEDGE_DOCS.RECYCLE.PURGED'));
  } catch {
    useAlert(t('CRM.KNOWLEDGE_DOCS.RECYCLE.ERROR'));
  }
};
const purgeAll = async () => {
  if (!pendingPurgeAll.value) {
    pendingPurgeAll.value = true;
    return;
  }
  pendingPurgeAll.value = false;
  try {
    await axios.post(recycleUrl('/purge_all'));
    recycleDocs.value = [];
    useAlert(t('CRM.KNOWLEDGE_DOCS.RECYCLE.PURGED_ALL'));
  } catch {
    useAlert(t('CRM.KNOWLEDGE_DOCS.RECYCLE.ERROR'));
  }
};

const fetchRecords = () => {
  if (isRecycle.value) {
    fetchRecycleBin();
    return;
  }
  store.get({
    library: currentLibrary.value,
    filter: activeFilter.value,
    section_id:
      isGeneral.value && activeSectionId.value
        ? activeSectionId.value
        : undefined,
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
          c.position !== i
            ? categoriesStore.update({ id: c.id, position: i })
            : null
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
  sectionId: '',
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
  // 文档中心一律公司文档；CRM 知识库里无公司文档管理权的成员只能建个人文档
  editForm.scope =
    isGeneral.value || canManageCompany.value ? 'COMPANY' : 'PERSONAL';
  editForm.sectionId = activeSectionId.value || '';
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
  editForm.sectionId = doc.sectionId ? String(doc.sectionId) : '';
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
    sectionId: isGeneral.value ? editForm.sectionId || null : null,
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
      const updated = await store.update({
        id: selectedDoc.value.id,
        ...payload,
      });
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

// 删除文档（管理员/负责人删公司文档；归属人删自己的个人文档）
const removeDoc = async () => {
  const doc = selectedDoc.value;
  const ok = window.confirm(
    t('CRM.KNOWLEDGE_DOCS.DELETE.CONFIRM', { name: doc.name })
  );
  if (!ok) return;
  try {
    await store.delete(doc.id);
    useAlert(t('CRM.KNOWLEDGE_DOCS.DELETE.SUCCESS'));
    closePanel();
    fetchRecords();
  } catch {
    useAlert(t('CRM.KNOWLEDGE_DOCS.DELETE.ERROR'));
  }
};

const fetchPermissionContext = () => {
  if (!isGeneral.value) return;
  fetchDocCenterSetting();
  fetchSections();
  if (isAdmin.value) fetchMembers();
};

onMounted(() => {
  fetchRecords();
  categoriesStore.get();
  fetchPermissionContext();
});
watch(currentLibrary, fetchPermissionContext);
watch(
  () => [route.query.filter, route.query.section_id],
  ([filter, sectionId]) => {
    activeFilter.value = filter || 'company';
    activeSectionId.value = sectionId || '';
    closePanel();
    fetchRecords();
  }
);
</script>

<template>
  <div
    class="flex w-full h-full overflow-hidden bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
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
        <div class="flex items-center gap-3">
          <!-- 文档中心负责人：管理员可指定，其他人只读展示 -->
          <template v-if="isGeneral">
            <span class="text-xs text-n-slate-10">
              {{ t('CRM.KNOWLEDGE_DOCS.OWNER.LABEL') }}
            </span>
            <Select
              v-if="isAdmin"
              :model-value="docCenterOwnerId ? String(docCenterOwnerId) : ''"
              :options="memberOptions"
              @update:model-value="setDocCenterOwner"
            />
            <span v-else class="text-xs font-medium text-n-slate-11">
              {{ docCenterOwnerName || t('CRM.KNOWLEDGE_DOCS.OWNER.NONE') }}
            </span>
          </template>
          <Button
            v-if="canCreateDocs && !isRecycle"
            :label="t('CRM.KNOWLEDGE_DOCS.NEW')"
            icon="i-lucide-plus"
            color="iris"
            @click="openCreatePanel()"
          />
        </div>
      </div>

      <div class="flex items-center gap-2 px-6 py-3 border-b border-n-weak">
        <Button
          v-for="tab in filterTabs"
          :key="tab.key"
          :label="tab.label"
          size="sm"
          :variant="activeFilter === tab.key ? 'solid' : 'faded'"
          :color="activeFilter === tab.key ? 'iris' : 'slate'"
          @click="setFilter(tab.key)"
        />
        <!-- 文档中心：板块经侧边栏切换；此处仅管理员的可见性设置入口 -->
        <Button
          v-if="isGeneral && isAdmin"
          size="sm"
          variant="faded"
          color="slate"
          icon="i-lucide-settings-2"
          :label="t('CRM.KNOWLEDGE_DOCS.SECTION.SETTINGS')"
          @click="openSectionDialog"
        />
        <Input
          v-model="searchQuery"
          :placeholder="t('CRM.KNOWLEDGE_DOCS.SEARCH_PLACEHOLDER')"
          class="ml-auto w-56"
          @input="onSearchInput"
        />
      </div>

      <div
        v-if="isFetching || loadingRecycle"
        class="flex items-center justify-center flex-1 text-base text-n-slate-11"
      >
        {{ t('CRM.KNOWLEDGE_DOCS.LOADING') }}
      </div>

      <!-- 文档回收站（仅管理员）：可恢复 / 彻底删除 / 清空 -->
      <div v-else-if="isRecycle" class="flex-1 px-6 py-4 overflow-y-auto">
        <div class="flex items-center justify-between mb-3">
          <p class="text-xs text-n-slate-10">
            {{ t('CRM.KNOWLEDGE_DOCS.RECYCLE.HINT') }}
          </p>
          <button
            v-if="recycleDocs.length"
            type="button"
            class="px-3 py-1.5 text-xs font-medium transition-colors rounded-full shrink-0"
            :class="
              pendingPurgeAll
                ? 'bg-n-ruby-9 text-white hover:bg-n-ruby-10'
                : 'text-n-ruby-11 hover:bg-n-ruby-3'
            "
            @click="purgeAll"
          >
            {{
              pendingPurgeAll
                ? t('CRM.KNOWLEDGE_DOCS.RECYCLE.CONFIRM_PURGE_ALL')
                : t('CRM.KNOWLEDGE_DOCS.RECYCLE.PURGE_ALL')
            }}
          </button>
        </div>

        <div
          v-if="!recycleDocs.length"
          class="flex flex-col items-center gap-2 mt-20 text-n-slate-10"
        >
          <span class="i-lucide-trash-2 size-8 opacity-40" />
          <p class="text-sm">{{ t('CRM.KNOWLEDGE_DOCS.RECYCLE.EMPTY') }}</p>
        </div>

        <table v-else class="w-full text-sm">
          <thead>
            <tr class="text-left border-b border-n-weak text-n-slate-10">
              <th class="py-2.5 pr-4 font-medium">
                {{ t('CRM.KNOWLEDGE_DOCS.RECYCLE.DOC_NAME') }}
              </th>
              <th class="py-2.5 pr-4 font-medium">
                {{ t('CRM.KNOWLEDGE_DOCS.RECYCLE.OWNER') }}
              </th>
              <th class="py-2.5 pr-4 font-medium">
                {{ t('CRM.KNOWLEDGE_DOCS.RECYCLE.DELETED_BY') }}
              </th>
              <th class="py-2.5 pr-4 font-medium">
                {{ t('CRM.KNOWLEDGE_DOCS.RECYCLE.DELETED_AT') }}
              </th>
              <th class="py-2.5 font-medium w-44" />
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="doc in recycleDocs"
              :key="doc.id"
              class="border-b border-n-weak hover:bg-n-alpha-1"
            >
              <td class="py-2.5 pr-4">
                <span class="font-medium text-n-slate-12">{{ doc.name }}</span>
                <span
                  class="ml-2 px-1.5 py-0.5 text-[11px] rounded-full bg-n-slate-3 text-n-slate-11"
                >
                  {{
                    doc.scope === 'PERSONAL'
                      ? t('CRM.KNOWLEDGE_DOCS.RECYCLE.SCOPE_PERSONAL')
                      : t('CRM.KNOWLEDGE_DOCS.RECYCLE.SCOPE_COMPANY')
                  }}
                </span>
              </td>
              <td class="py-2.5 pr-4 text-n-slate-11">
                {{ doc.owner_name || '—' }}
              </td>
              <td class="py-2.5 pr-4 text-n-slate-11">
                {{ doc.discarded_by_name || '—' }}
              </td>
              <td class="py-2.5 pr-4 text-n-slate-11 tabular-nums">
                {{ fmtDateTime(doc.discarded_at) }}
              </td>
              <td class="py-2.5">
                <div class="flex items-center justify-end gap-1.5">
                  <button
                    type="button"
                    class="px-2.5 py-1 text-xs font-medium transition-colors rounded-full text-n-iris-11 hover:bg-n-iris-3"
                    @click="restoreDoc(doc)"
                  >
                    {{ t('CRM.KNOWLEDGE_DOCS.RECYCLE.RESTORE') }}
                  </button>
                  <button
                    type="button"
                    class="px-2.5 py-1 text-xs font-medium transition-colors rounded-full"
                    :class="
                      pendingPurgeId === doc.id
                        ? 'bg-n-ruby-9 text-white hover:bg-n-ruby-10'
                        : 'text-n-ruby-11 hover:bg-n-ruby-3'
                    "
                    @click="purgeDoc(doc)"
                  >
                    {{
                      pendingPurgeId === doc.id
                        ? t('CRM.KNOWLEDGE_DOCS.RECYCLE.CONFIRM_PURGE')
                        : t('CRM.KNOWLEDGE_DOCS.RECYCLE.PURGE')
                    }}
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
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
              class="w-40 h-7 px-2 text-sm border rounded-md border-n-weak bg-n-solid-1 text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-8"
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
                v-if="col.id && canManageCompany"
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
              class="flex flex-col gap-2 p-3 text-left transition-all border cursor-grab active:cursor-grabbing rounded-xl bg-n-solid-1 border-n-weak hover:border-n-slate-6 hover:shadow-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-8"
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
              v-if="canCreateDocs"
              type="button"
              class="flex items-center gap-1 px-3 py-2 text-sm rounded-xl text-n-slate-10 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-8"
              @click="openCreatePanel(col.uncategorized ? undefined : col.name)"
            >
              <span class="i-lucide-plus size-4" />
              {{ t('CRM.KNOWLEDGE_DOCS.ADD_IN_COLUMN') }}
            </button>
          </div>
        </div>

        <!-- 新增分类列（仅公司文档管理权） -->
        <div v-if="canManageCompany" class="flex flex-col w-72 shrink-0">
          <input
            v-if="adding"
            v-model="newCategoryName"
            :placeholder="t('CRM.KNOWLEDGE_DOCS.CATEGORY.NAME_PLACEHOLDER')"
            class="h-8 px-2 text-sm border rounded-md border-n-weak bg-n-solid-1 text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-8"
            @keyup.enter="saveAdd"
            @blur="saveAdd"
          />
          <button
            v-else
            type="button"
            class="flex items-center gap-1 px-3 py-2 text-sm rounded-lg text-n-slate-10 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-8"
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
              {{
                isCreate
                  ? t('CRM.KNOWLEDGE_DOCS.PANEL.NEW_TITLE')
                  : selectedDoc.name
              }}
            </div>
            <div v-if="!isCreate" class="text-xs text-n-slate-10">
              {{
                selectedDoc.category || t('CRM.KNOWLEDGE_DOCS.UNCATEGORIZED')
              }}
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
                  selectedDoc.category || t('CRM.KNOWLEDGE_DOCS.UNCATEGORIZED')
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
                  v-if="canManageDoc(selectedDoc)"
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
                  v-if="canManageDoc(selectedDoc)"
                  type="button"
                  class="text-n-slate-10 hover:text-n-ruby-11 shrink-0"
                  @click="removeAttachment(file.id)"
                >
                  <span class="i-lucide-x size-4" />
                </button>
              </div>
            </div>

            <div v-if="canManageDoc(selectedDoc)" class="flex gap-2 pt-2">
              <Button
                :label="t('CRM.KNOWLEDGE_DOCS.PANEL.EDIT')"
                icon="i-lucide-pencil"
                size="sm"
                color="slate"
                variant="faded"
                @click="startEdit"
              />
              <Button
                :label="t('CRM.KNOWLEDGE_DOCS.DELETE.LABEL')"
                icon="i-lucide-trash-2"
                size="sm"
                color="ruby"
                variant="faded"
                @click="removeDoc"
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
                <Select
                  v-model="editForm.category"
                  :options="categoryOptions"
                />
              </div>
              <!-- 文档中心固定公司文档，不给选范围 -->
              <div
                v-if="canManageCompany && !isGeneral"
                class="flex flex-col min-w-0 gap-1"
              >
                <label class="mb-0.5 text-heading-3 text-n-slate-12">
                  {{ t('CRM.KNOWLEDGE_DOCS.FORM.SCOPE') }}
                </label>
                <Select v-model="editForm.scope" :options="scopeOptions" />
              </div>
            </div>
            <div v-if="isGeneral" class="flex flex-col min-w-0 gap-1">
              <label class="mb-0.5 text-heading-3 text-n-slate-12">
                {{ t('CRM.KNOWLEDGE_DOCS.FORM.SECTION') }}
              </label>
              <Select
                v-model="editForm.sectionId"
                :options="sectionFormOptions"
              />
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
                <span
                  class="flex items-center gap-2 text-sm truncate text-n-slate-12"
                >
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
                color="iris"
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

    <!-- 板块可见性设置（管理员）：每板块勾选可见部门，全不勾 = 全员可见 -->
    <Dialog
      ref="sectionDialogRef"
      width="2xl"
      overflow-y-auto
      confirm-button-color="iris"
      :title="t('CRM.KNOWLEDGE_DOCS.SECTION.SETTINGS')"
      :is-loading="savingSections"
      @confirm="saveSectionVisibility"
    >
      <p class="mb-4 text-xs text-n-slate-10">
        {{ t('CRM.KNOWLEDGE_DOCS.SECTION.SETTINGS_HINT') }}
      </p>
      <div class="flex flex-col gap-4">
        <div
          v-for="draft in sectionDraft"
          :key="draft.id"
          class="flex flex-col gap-2 pb-3 border-b border-n-weak last:border-b-0"
        >
          <div class="flex items-center justify-between gap-2">
            <div class="text-sm font-medium text-n-slate-12">
              {{ draft.name }}
            </div>
            <button
              v-if="!draft.isDefault"
              type="button"
              class="px-2.5 py-1 text-xs font-medium transition-colors rounded-full shrink-0"
              :class="
                pendingSectionDeleteId === draft.id
                  ? 'bg-n-ruby-9 text-white hover:bg-n-ruby-10'
                  : 'text-n-ruby-11 hover:bg-n-ruby-3'
              "
              @click="deleteSection(draft)"
            >
              {{
                pendingSectionDeleteId === draft.id
                  ? t('CRM.KNOWLEDGE_DOCS.SECTION.CONFIRM_DELETE')
                  : t('CRM.KNOWLEDGE_DOCS.SECTION.DELETE')
              }}
            </button>
          </div>
          <div class="flex flex-wrap gap-x-4 gap-y-1.5">
            <label
              v-for="dept in departments"
              :key="dept.id"
              class="flex items-center gap-1.5 text-sm text-n-slate-11"
            >
              <input
                type="checkbox"
                :checked="draft.departmentIds.includes(dept.id)"
                @change="toggleSectionDept(draft, dept.id)"
              />
              {{ dept.name }}
            </label>
            <span
              v-if="!draft.departmentIds.length"
              class="text-xs self-center text-n-slate-10"
            >
              {{ t('CRM.KNOWLEDGE_DOCS.SECTION.ALL_VISIBLE') }}
            </span>
          </div>
        </div>

        <!-- 新增自定义板块 -->
        <div class="flex flex-col gap-1.5 pt-1">
          <div class="text-sm font-medium text-n-slate-12">
            {{ t('CRM.KNOWLEDGE_DOCS.SECTION.ADD_TITLE') }}
          </div>
          <div class="flex items-center gap-2">
            <Input
              v-model="newSectionName"
              class="flex-1"
              :placeholder="t('CRM.KNOWLEDGE_DOCS.SECTION.ADD_PLACEHOLDER')"
              @keydown.enter.prevent="addSection"
            />
            <Button
              type="button"
              :label="t('CRM.KNOWLEDGE_DOCS.SECTION.ADD')"
              color="iris"
              size="sm"
              :is-loading="addingSection"
              :disabled="!newSectionName.trim()"
              @click="addSection"
            />
          </div>
          <p class="text-xs text-n-slate-10">
            {{ t('CRM.KNOWLEDGE_DOCS.SECTION.DELETE_NOTE') }}
          </p>
        </div>
      </div>
    </Dialog>
  </div>
</template>
