<script setup>
/* global axios */
import { ref, reactive, computed, onMounted, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { useCrmRole } from 'dashboard/composables/useCrmRole';
import { emitter } from 'shared/helpers/mitt';
import { useCrmKnowledgeDocsStore } from 'dashboard/stores/crm/knowledgeDocs';
import { useCrmKnowledgeCategoriesStore } from 'dashboard/stores/crm/knowledgeCategories';
import CrmMemberAPI from 'dashboard/api/crm/members';
import DocSectionsAPI from 'dashboard/api/crm/docSections';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
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
const members = ref([]);

// 成员列表：供「文档负责人」多选（仅超管/管理员分配）。
const fetchMembers = async () => {
  try {
    const { data } = await CrmMemberAPI.get();
    members.value = data.payload || [];
  } catch {
    members.value = [];
  }
};

const isAdminLike = computed(() => isAdmin.value || isCrmDeputyAdmin.value);

const canManageCompany = computed(
  () => isAdminLike.value || isCrmManager.value
);

// 我的资料视图：看板列是个人分类，人人可自建自管；公司视图的分类仍按公司管理权。
const isMineView = computed(
  () => !isGeneral.value && activeFilter.value === 'mine'
);
const canManageBoard = computed(
  () => isMineView.value || canManageCompany.value
);

// 当前侧栏选中的板块 id（?section_id= 驱动）；分类隔离与板块负责人展示都依赖它。
const activeSectionId = ref(route.query.section_id || '');
// 公司分类按板块隔离：SALES 库映射到「销售资料」板块，GENERAL 取当前板块（聚合视图无板块）。
const sectionParam = () =>
  isGeneral.value && activeSectionId.value ? activeSectionId.value : undefined;
const fetchCategories = () =>
  categoriesStore.get(
    isMineView.value
      ? { view: 'mine' }
      : { library: currentLibrary.value, section_id: sectionParam() }
  );

// ── 资料板块（文档中心）：侧边栏子项经 ?section_id= 驱动切换；管理员可按部门配置各板块可见性 ──
const sections = ref([]);
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

// 当前侧栏选中的板块（用于展示/设置板块负责人）。
const activeSection = computed(() =>
  sections.value.find(s => String(s.id) === String(activeSectionId.value))
);

// ── 板块负责人（可多人）：页面上直接展示；超管/管理员点「设置负责人」勾选成员 ──
const ownerDialogRef = ref(null);
const ownerDraftIds = ref([]);
const ownerSearch = ref('');
const savingOwners = ref(false);
const ownerCandidates = computed(() => {
  const kw = ownerSearch.value.trim().toLowerCase();
  if (!kw) return members.value;
  return members.value.filter(m =>
    `${m.name} ${m.email}`.toLowerCase().includes(kw)
  );
});
const openOwnerDialog = () => {
  if (!activeSection.value) return;
  ownerDraftIds.value = [...(activeSection.value.manager_ids || [])];
  ownerSearch.value = '';
  ownerDialogRef.value?.open();
};
const toggleOwner = userId => {
  const idx = ownerDraftIds.value.indexOf(userId);
  if (idx >= 0) ownerDraftIds.value.splice(idx, 1);
  else ownerDraftIds.value.push(userId);
};
const saveSectionOwners = async () => {
  if (!activeSection.value) return;
  savingOwners.value = true;
  try {
    await DocSectionsAPI.updateSection(activeSection.value.id, {
      section: { manager_ids: ownerDraftIds.value },
    });
    await fetchSections();
    emitter.emit('crmDocSectionsUpdated');
    ownerDialogRef.value?.close();
    useAlert(t('CRM.KNOWLEDGE_DOCS.SECTION.OWNER_SAVED'));
  } catch {
    useAlert(t('CRM.KNOWLEDGE_DOCS.SECTION.OWNER_ERROR'));
  } finally {
    savingOwners.value = false;
  }
};

// ── 板块可见成员（可多人）：空=全员可见；超管/管理员点「设置可见成员」搜索勾选 ──
const viewerDialogRef = ref(null);
const viewerDraftIds = ref([]);
const viewerSearch = ref('');
const savingViewers = ref(false);
const viewerCandidates = computed(() => {
  const kw = viewerSearch.value.trim().toLowerCase();
  if (!kw) return members.value;
  return members.value.filter(m =>
    `${m.name} ${m.email}`.toLowerCase().includes(kw)
  );
});
const openViewerDialog = () => {
  if (!activeSection.value) return;
  viewerDraftIds.value = [...(activeSection.value.viewer_ids || [])];
  viewerSearch.value = '';
  viewerDialogRef.value?.open();
};
const toggleViewer = userId => {
  const idx = viewerDraftIds.value.indexOf(userId);
  if (idx >= 0) viewerDraftIds.value.splice(idx, 1);
  else viewerDraftIds.value.push(userId);
};
const saveSectionViewers = async () => {
  if (!activeSection.value) return;
  savingViewers.value = true;
  try {
    await DocSectionsAPI.updateSection(activeSection.value.id, {
      section: { viewer_ids: viewerDraftIds.value },
    });
    await fetchSections();
    emitter.emit('crmDocSectionsUpdated');
    viewerDialogRef.value?.close();
    useAlert(t('CRM.KNOWLEDGE_DOCS.SECTION.VIEWER_SAVED'));
  } catch {
    useAlert(t('CRM.KNOWLEDGE_DOCS.SECTION.VIEWER_ERROR'));
  } finally {
    savingViewers.value = false;
  }
};

// 板块管理弹窗（管理员）：新增/删除自定义板块。可见性（可见成员）在各板块顶栏就地设置。
const sectionDialogRef = ref(null);
const sectionDraft = ref([]);
const newSectionName = ref('');
const addingSection = ref(false);
const pendingSectionDeleteId = ref(null);
const openSectionDialog = () => {
  sectionDraft.value = sections.value.map(s => ({
    id: s.id,
    name: s.name,
    isDefault: s.is_default,
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
// 当前用户负责的板块 id 集合（板块负责人可管该板块下所有公司文档）。
const managedSectionIds = computed(() =>
  sections.value
    .filter(s => (s.manager_ids || []).includes(currentUserId.value))
    .map(s => s.id)
);
// 个人文档归属人可管；公司文档=超管/管理员+该文档所属板块负责人；销售资料另放开部门负责人。
const canManageDoc = doc => {
  if (doc?.scope === 'PERSONAL') return doc.ownerId === currentUserId.value;
  if (isAdminLike.value) return true;
  if (doc?.sectionId && managedSectionIds.value.includes(doc.sectionId))
    return true;
  return !isGeneral.value && isCrmManager.value;
};
// 新建入口：超管/管理员随处；板块负责人在自己负责的板块；销售资料人人可建（个人文档）。
const canCreateDocs = computed(() => {
  if (isAdminLike.value) return true;
  if (activeSectionId.value)
    return managedSectionIds.value.includes(Number(activeSectionId.value));
  return !isGeneral.value;
});

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

const categoryOptions = computed(() =>
  categories.value.map(c => ({ value: c.name, label: c.name }))
);
const scopeOptions = [
  { value: 'COMPANY', label: '公司' },
  { value: 'PERSONAL', label: '个人' },
];

// ── 三级目录导航：path 栈（板块 → 分类 → 子分类）。当前节点决定显示的子文件夹与文档 ──
// path 元素：{ type:'section'|'category'|'orphan'|'uncategorized', id, name }
const pathStack = ref([]); // 空=根
const selectedFolderKey = ref(null); // 单击选中的文件夹（驱动右侧 Info 面板）
const isSearching = computed(() => !!searchQuery.value.trim());

const currentNode = computed(() =>
  pathStack.value.length ? pathStack.value[pathStack.value.length - 1] : null
);
const currentCategoryId = computed(() =>
  currentNode.value?.type === 'category' ? currentNode.value.id : null
);
// 新建文档时归属的分类名（分类/孤儿节点=其名；未分类/板块=无）
const currentDocCategory = computed(() => {
  const n = currentNode.value;
  return n?.type === 'category' || n?.type === 'orphan' ? n.name : undefined;
});
// 当前层能否新建子文件夹：有管理权 + 非搜索 + 非 GENERAL 根(板块由「板块设置」维护) + 非叶子(孤儿/未分类)
const canAddFolderHere = computed(
  () =>
    canManageBoard.value &&
    !isSearching.value &&
    !(isGeneral.value && !currentNode.value) &&
    !['orphan', 'uncategorized'].includes(currentNode.value?.type)
);
// 当前层能否新建文档：需处于分类/孤儿/未分类叶子里
const canCreateDocsHere = computed(
  () =>
    canCreateDocs.value &&
    !isSearching.value &&
    ['category', 'orphan', 'uncategorized'].includes(currentNode.value?.type)
);
// 文档中心根层能否新建板块（左侧栏的文档分组项）：管理员/副管理员，与「板块设置」同权
const canAddSectionHere = computed(
  () =>
    isGeneral.value &&
    !isSearching.value &&
    !currentNode.value &&
    (isAdmin.value || isCrmDeputyAdmin.value)
);

// 分类树：按 parentId 取子分类；名字在同板块内唯一，故文档按名字归属。
const childrenOf = parentId =>
  categories.value.filter(c => (c.parentId ?? null) === (parentId ?? null));
const descendantNames = catId => {
  const names = [];
  const self = categories.value.find(c => c.id === catId);
  if (self) names.push(self.name);
  const walk = id =>
    childrenOf(id).forEach(c => {
      names.push(c.name);
      walk(c.id);
    });
  walk(catId);
  return names;
};
// 分类文件夹的子树文档（该分类及其所有后代分类下的文档）
const subtreeDocsOf = catId => {
  const names = new Set(descendantNames(catId));
  return records.value.filter(d => d.category && names.has(d.category));
};

// 某父级下的分类文件夹；顶层（parentId 为空）追加孤儿/未分类兜底，避免丢文档。
const buildCatFolders = parentId => {
  const folders = childrenOf(parentId).map(c => ({
    type: 'category',
    id: c.id,
    name: c.name,
    docs: subtreeDocsOf(c.id),
    childCount: childrenOf(c.id).length,
  }));
  if (parentId == null) {
    const known = categories.value.map(c => c.name);
    [
      ...new Set(
        records.value.map(r => r.category).filter(n => n && !known.includes(n))
      ),
    ].forEach(name =>
      folders.push({
        type: 'orphan',
        id: name,
        name,
        docs: records.value.filter(d => d.category === name),
        childCount: 0,
      })
    );
    if (records.value.some(r => !r.category)) {
      folders.push({
        type: 'uncategorized',
        id: '__uncat__',
        name: '',
        uncategorized: true,
        docs: records.value.filter(d => !d.category),
        childCount: 0,
      });
    }
  }
  return folders;
};

// 当前节点下的子文件夹
const currentFolders = computed(() => {
  const n = currentNode.value;
  if (!n) {
    if (isGeneral.value) {
      return sections.value.map(s => ({
        type: 'section',
        id: s.id,
        name: s.name,
        docs: [],
        childCount: null,
      }));
    }
    return buildCatFolders(null);
  }
  if (n.type === 'section') return buildCatFolders(null);
  if (n.type === 'category') return buildCatFolders(n.id);
  return [];
});

// 当前节点下直接归属的文档（分类/孤儿/未分类叶子才有；搜索时平铺全部命中）
const currentDocs = computed(() => {
  if (isSearching.value) return records.value;
  const n = currentNode.value;
  if (!n) return [];
  if (n.type === 'uncategorized') return records.value.filter(d => !d.category);
  if (n.type === 'orphan' || n.type === 'category')
    return records.value.filter(d => d.category === n.name);
  return [];
});

// 面包屑：板块名从 sections 兜底解析
const breadcrumb = computed(() =>
  pathStack.value.map(n =>
    n.type === 'section'
      ? {
          ...n,
          label:
            sections.value.find(x => x.id === n.id)?.name ||
            n.name ||
            t('CRM.KNOWLEDGE_DOCS.SECTION.NONE'),
        }
      : {
          ...n,
          label: n.uncategorized
            ? t('CRM.KNOWLEDGE_DOCS.UNCATEGORIZED')
            : n.name,
        }
  )
);

const folderClass = f =>
  f.uncategorized ? 'bg-n-slate-3 text-n-slate-11' : colorOf(f.name);

// 文件夹大小 = 其（子树）文档附件字节和；最近修改 = 其文档最新 updatedAt
const folderBytes = f =>
  (f.docs || []).reduce(
    (sum, d) =>
      sum + (d.files || []).reduce((s, x) => s + (x.byteSize || 0), 0),
    0
  );
const SIZE_UNITS = ['B', 'KB', 'MB', 'GB', 'TB'];
const fmtSize = bytes => {
  if (!bytes) return '';
  const i = Math.min(
    SIZE_UNITS.length - 1,
    Math.floor(Math.log(bytes) / Math.log(1024))
  );
  const n = bytes / 1024 ** i;
  return `${n.toFixed(i === 0 || n >= 100 ? 0 : 1)} ${SIZE_UNITS[i]}`;
};
const folderLastModified = f => {
  const times = (f.docs || []).map(d => d.updatedAt).filter(Boolean);
  return times.length ? times.reduce((a, b) => (a > b ? a : b)) : null;
};

// ── 文件夹选中（Info 面板） + 进入/返回导航 ──
const folderKeyOf = f => `${f.type}:${f.id}`;
const selectedFolder = computed(() =>
  selectedFolderKey.value == null
    ? null
    : currentFolders.value.find(
        f => folderKeyOf(f) === selectedFolderKey.value
      ) || null
);
const isFolderSelected = f => selectedFolderKey.value === folderKeyOf(f);
const selectFolder = f => {
  selectedFolderKey.value = folderKeyOf(f);
};
const clearFolderSelection = () => {
  selectedFolderKey.value = null;
};

// 进入文件夹：板块→经路由切 section_id（由 route watcher 同步 path 并拉数据、也同步侧栏/URL）；分类/叶子→压栈
const enterFolder = f => {
  clearFolderSelection();
  if (f.type === 'section') {
    router.replace({ query: { ...route.query, section_id: f.id } });
    return;
  }
  pathStack.value = [
    ...pathStack.value,
    { type: f.type, id: f.id, name: f.name, uncategorized: f.uncategorized },
  ];
};
// 面包屑跳转：i<0 回根（GENERAL 在板块内则经路由清 section_id）
const goToDepth = i => {
  clearFolderSelection();
  if (i < 0) {
    if (isGeneral.value && route.query.section_id) {
      router.replace({ query: { ...route.query, section_id: undefined } });
    } else {
      pathStack.value = [];
    }
    return;
  }
  pathStack.value = pathStack.value.slice(0, i + 1);
};
// 回根（库切换/筛选切换时复位）
const backToFolders = () => {
  pathStack.value = [];
  selectedFolderKey.value = null;
};

// ── Filter：文件夹排序（默认顺序 / 名称 / 文档数 / 大小 / 最近修改）──
const FOLDER_SORTS = [
  { value: 'default', label: '默认顺序' },
  { value: 'name', label: '按名称' },
  { value: 'count', label: '按文档数' },
  { value: 'size', label: '按大小' },
  { value: 'recent', label: '按最近修改' },
];
const folderSort = ref('default');
const sortedFolders = computed(() => {
  const list = [...currentFolders.value];
  switch (folderSort.value) {
    case 'name':
      return list.sort((a, b) => (a.name || '').localeCompare(b.name || '', 'zh')); // prettier-ignore
    case 'count':
      return list.sort((a, b) => b.docs.length - a.docs.length);
    case 'size':
      return list.sort((a, b) => folderBytes(b) - folderBytes(a));
    case 'recent':
      return list.sort((a, b) =>
        (folderLastModified(b) || '').localeCompare(folderLastModified(a) || '')
      );
    default:
      return list;
  }
});

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
watch(currentLibrary, () => {
  backToFolders();
  fetchRecords();
});

const setFilter = key => {
  activeFilter.value = key;
  backToFolders();
  fetchRecords();
  fetchCategories();
};

const onSearchInput = () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(fetchRecords, 300);
};

const fmtDate = v => (v ? new Date(v).toLocaleDateString() : '');

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
    !isGeneral.value && (isMineView.value || !canManageCompany.value)
      ? 'PERSONAL'
      : 'COMPANY';
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
    await categoriesStore.create({
      name,
      position: categories.value.length,
      personal: isMineView.value,
      library: currentLibrary.value,
      section_id: sectionParam(),
      parent_id: currentCategoryId.value, // 在某分类里新建=其子分类
    });
    await fetchCategories();
  } catch {
    useAlert(t('CRM.KNOWLEDGE_DOCS.CATEGORY.SAVE_ERROR'));
  }
};

// ── 根层新建板块（左侧栏文档分组项）：与「板块设置」同一后端，建完即时进网格 + 侧栏 ──
const addingRootSection = ref(false);
const newRootSectionName = ref('');
const startAddSection = () => {
  addingRootSection.value = true;
  newRootSectionName.value = '';
};
const saveAddSection = async () => {
  const name = newRootSectionName.value.trim();
  addingRootSection.value = false;
  if (!name) return;
  try {
    await DocSectionsAPI.createSection({ section: { name } });
    await fetchSections();
    emitter.emit('crmDocSectionsUpdated'); // 通知左侧栏刷新
    useAlert(t('CRM.KNOWLEDGE_DOCS.SECTION.ADDED'));
  } catch {
    useAlert(t('CRM.KNOWLEDGE_DOCS.SECTION.ADD_ERROR'));
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
    await fetchCategories();
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
  fetchSections();
  if (isAdminLike.value) fetchMembers();
};

onMounted(() => {
  // 侧栏带 ?section_id= 进来时，直接定位到该板块层
  if (route.query.section_id) {
    pathStack.value = [
      { type: 'section', id: Number(route.query.section_id), name: '' },
    ];
  }
  fetchRecords();
  fetchCategories();
  fetchPermissionContext();
});
watch(currentLibrary, fetchPermissionContext);
watch(
  () => [route.query.filter, route.query.section_id],
  ([filter, sectionId]) => {
    activeFilter.value = filter || 'company';
    activeSectionId.value = sectionId || '';
    closePanel();
    clearFolderSelection();
    // 侧栏切板块→落到该板块层；无板块→回根（GENERAL 显示板块网格）
    pathStack.value = sectionId
      ? [{ type: 'section', id: Number(sectionId), name: '' }]
      : [];
    fetchRecords();
    fetchCategories();
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
        <!-- 文档中心：板块（文件夹）管理入口——新增/删除自定义板块、按部门配置可见性 -->
        <Button
          v-if="isGeneral && (isAdmin || isCrmDeputyAdmin)"
          size="sm"
          variant="faded"
          color="slate"
          icon="i-lucide-settings-2"
          :label="t('CRM.KNOWLEDGE_DOCS.SECTION.SETTINGS')"
          @click="openSectionDialog"
        />
        <!-- Filter：文件夹排序 -->
        <SelectCard
          v-if="!isRecycle"
          v-model="folderSort"
          :options="FOLDER_SORTS"
          align="right"
          class="ml-auto"
          trigger-class="w-32 h-9"
        />
        <Input
          v-model="searchQuery"
          :placeholder="t('CRM.KNOWLEDGE_DOCS.SEARCH_PLACEHOLDER')"
          :class="isRecycle ? 'ml-auto w-56' : 'w-56'"
          @input="onSearchInput"
        />
      </div>

      <!-- 板块负责人 + 可见范围：选中某板块时展示，超管/管理员可就地设置 -->
      <div
        v-if="isGeneral && activeSection && !isRecycle"
        class="flex flex-col gap-1.5 px-6 py-2.5 border-b border-n-weak bg-n-alpha-1/40"
      >
        <!-- 负责人（能管该板块文档的人，人人可见） -->
        <div class="flex flex-wrap items-center gap-2">
          <span class="text-xs font-medium text-n-slate-11">
            {{ activeSection.name }} ·
            {{ t('CRM.KNOWLEDGE_DOCS.SECTION.OWNER') }}
          </span>
          <template v-if="(activeSection.manager_names || []).length">
            <span
              v-for="name in activeSection.manager_names"
              :key="name"
              class="inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded-full bg-n-iris-3 text-n-iris-12"
            >
              <span class="i-lucide-user-round size-3" />
              {{ name }}
            </span>
          </template>
          <span v-else class="text-xs text-n-slate-10">
            {{ t('CRM.KNOWLEDGE_DOCS.SECTION.OWNER_NONE') }}
          </span>
          <Button
            v-if="isAdmin || isCrmDeputyAdmin"
            size="xs"
            variant="ghost"
            color="slate"
            icon="i-lucide-pencil"
            :label="t('CRM.KNOWLEDGE_DOCS.SECTION.OWNER_SET')"
            @click="openOwnerDialog"
          />
        </div>
        <!-- 可见范围（可见成员白名单，空=全员可见） -->
        <div class="flex flex-wrap items-center gap-2">
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('CRM.KNOWLEDGE_DOCS.SECTION.VIEWER') }}
          </span>
          <template v-if="(activeSection.viewer_names || []).length">
            <span
              v-for="name in activeSection.viewer_names"
              :key="name"
              class="inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded-full bg-n-teal-3 text-n-teal-12"
            >
              <span class="i-lucide-eye size-3" />
              {{ name }}
            </span>
          </template>
          <span v-else class="text-xs text-n-slate-10">
            {{ t('CRM.KNOWLEDGE_DOCS.SECTION.VIEWER_ALL') }}
          </span>
          <Button
            v-if="isAdmin || isCrmDeputyAdmin"
            size="xs"
            variant="ghost"
            color="slate"
            icon="i-lucide-pencil"
            :label="t('CRM.KNOWLEDGE_DOCS.SECTION.VIEWER_SET')"
            @click="openViewerDialog"
          />
        </div>
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

      <!-- 三级目录浏览器：面包屑 + 子文件夹网格 + 本层文档（搜索时平铺命中）-->
      <div v-else class="flex flex-col flex-1 overflow-hidden">
        <!-- 面包屑 -->
        <div
          class="flex items-center gap-1.5 px-6 py-3 text-sm border-b border-n-weak min-w-0"
        >
          <button
            v-if="pathStack.length || isSearching"
            type="button"
            class="flex items-center justify-center rounded-lg size-7 shrink-0 text-n-slate-11 hover:bg-n-alpha-1"
            :title="t('CRM.KNOWLEDGE_DOCS.VIEW.BACK')"
            @click="
              isSearching ? (searchQuery = '') : goToDepth(pathStack.length - 2)
            "
          >
            <span class="i-lucide-arrow-left size-4" />
          </button>
          <button
            type="button"
            class="shrink-0 text-n-slate-10 hover:text-n-slate-12"
            @click="goToDepth(-1)"
          >
            {{
              isGeneral
                ? t('CRM.KNOWLEDGE_DOCS.HEADER_GENERAL')
                : t('CRM.KNOWLEDGE_DOCS.HEADER')
            }}
          </button>
          <template v-if="isSearching">
            <span
              class="i-lucide-chevron-right size-3.5 text-n-slate-8 shrink-0"
            />
            <span class="font-medium text-n-slate-12">
              {{ t('CRM.KNOWLEDGE_DOCS.VIEW.SEARCH_RESULT') }}
            </span>
            <span class="shrink-0 text-n-slate-10">
              {{
                t('CRM.KNOWLEDGE_DOCS.VIEW.COUNT', {
                  count: currentDocs.length,
                })
              }}
            </span>
          </template>
          <template v-else>
            <template v-for="(node, i) in breadcrumb" :key="i">
              <span
                class="i-lucide-chevron-right size-3.5 text-n-slate-8 shrink-0"
              />
              <button
                type="button"
                class="truncate shrink-0 max-w-[10rem]"
                :class="
                  i === breadcrumb.length - 1
                    ? 'font-medium text-n-slate-12'
                    : 'text-n-slate-10 hover:text-n-slate-12'
                "
                @click="goToDepth(i)"
              >
                {{ node.label }}
              </button>
            </template>
          </template>
        </div>

        <div class="flex-1 px-6 py-4 overflow-y-auto">
          <!-- 空态 -->
          <div
            v-if="
              isSearching
                ? !currentDocs.length
                : !sortedFolders.length &&
                  !currentDocs.length &&
                  !canAddFolderHere &&
                  !canAddSectionHere &&
                  !canCreateDocsHere
            "
            class="flex flex-col items-center gap-2 mt-20 text-n-slate-10"
          >
            <span
              class="size-8 opacity-40"
              :class="
                isSearching ? 'i-lucide-file-text' : 'i-lucide-folder-open'
              "
            />
            <p class="text-sm">
              {{
                isSearching
                  ? t('CRM.KNOWLEDGE_DOCS.VIEW.NO_MATCH')
                  : currentNode
                    ? t('CRM.KNOWLEDGE_DOCS.VIEW.EMPTY_FOLDER')
                    : t('CRM.KNOWLEDGE_DOCS.EMPTY')
              }}
            </p>
          </div>

          <!-- 子文件夹网格（非搜索）-->
          <div
            v-if="
              !isSearching &&
              (sortedFolders.length || canAddFolderHere || canAddSectionHere)
            "
            class="grid grid-cols-4 gap-3 sm:grid-cols-5 xl:grid-cols-6"
          >
            <div
              v-for="folder in sortedFolders"
              :key="folderKeyOf(folder)"
              class="relative group/folder"
            >
              <!-- 重命名内联输入（仅分类文件夹）-->
              <input
                v-if="
                  editingId &&
                  folder.type === 'category' &&
                  editingId === folder.id
                "
                v-model="editingName"
                class="absolute z-10 left-3 right-3 top-1/2 -translate-y-1/2 h-8 px-2 text-sm border rounded-md border-n-iris-8 bg-n-solid-1 text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-8"
                @keyup.enter="saveRename"
                @blur="saveRename"
                @click.stop
              />
              <!-- 单击选中看信息，双击进入 -->
              <button
                type="button"
                class="relative block w-full pt-2 text-left cursor-pointer transition-transform group-hover/folder:-translate-y-1"
                @click="selectFolder(folder)"
                @dblclick="enterFolder(folder)"
              >
                <!-- 露出的纸张（两层玻璃叠纸） -->
                <div
                  class="absolute h-6 -top-1 inset-x-4 rounded-t-lg border border-b-0 border-white/40 bg-white/25 backdrop-blur-sm"
                />
                <div
                  class="absolute shadow-sm h-7 inset-x-3 -top-0 rounded-t-lg border border-b-0 border-white/60 bg-white/40 backdrop-blur-md"
                />
                <!-- 文件夹主体（玻璃）-->
                <div
                  class="relative flex flex-col justify-end p-3 overflow-hidden transition-all border shadow-sm h-28 rounded-xl rounded-tl-md ring-1 ring-inset backdrop-blur-xl backdrop-saturate-150"
                  :class="
                    isFolderSelected(folder)
                      ? 'border-white/20 ring-white/20 bg-gradient-to-br from-n-iris-9/75 to-n-iris-10/60 shadow-lg shadow-n-iris-9/25'
                      : 'border-white/60 ring-white/40 bg-gradient-to-br from-white/50 to-n-iris-3/25 group-hover/folder:from-white/70 group-hover/folder:shadow-md'
                  "
                >
                  <span
                    class="absolute i-lucide-folder top-2.5 right-2.5 size-4"
                    :class="
                      isFolderSelected(folder)
                        ? 'text-white/70'
                        : 'text-n-slate-9'
                    "
                  />
                  <!-- 选中时露出首篇文档预览 -->
                  <div
                    v-if="isFolderSelected(folder) && folder.docs.length"
                    class="absolute text-xs leading-snug left-3 right-8 top-2.5 line-clamp-1 text-white/85"
                  >
                    {{ folder.docs[0].summary || folder.docs[0].name }}
                  </div>
                  <div class="relative min-w-0">
                    <div
                      class="text-sm font-semibold truncate"
                      :class="
                        isFolderSelected(folder)
                          ? 'text-white'
                          : 'text-n-slate-12'
                      "
                    >
                      {{
                        folder.uncategorized
                          ? t('CRM.KNOWLEDGE_DOCS.UNCATEGORIZED')
                          : folder.name
                      }}
                    </div>
                    <!-- 板块：显示「板块」；其余：文档数(+子文件夹) + 大小 -->
                    <div
                      v-if="folder.type === 'section'"
                      class="mt-0.5 text-xs"
                      :class="
                        isFolderSelected(folder)
                          ? 'text-white/75'
                          : 'text-n-slate-10'
                      "
                    >
                      {{ t('CRM.KNOWLEDGE_DOCS.VIEW.SECTION_LABEL') }}
                    </div>
                    <template v-else>
                      <div
                        class="mt-0.5 text-xs"
                        :class="
                          isFolderSelected(folder)
                            ? 'text-white/75'
                            : 'text-n-slate-10'
                        "
                      >
                        {{
                          t('CRM.KNOWLEDGE_DOCS.VIEW.COUNT', {
                            count: folder.docs.length,
                          })
                        }}
                        <span v-if="folder.childCount">
                          ·
                          {{
                            t('CRM.KNOWLEDGE_DOCS.VIEW.SUBFOLDERS', {
                              count: folder.childCount,
                            })
                          }}
                        </span>
                      </div>
                      <div
                        v-if="folderBytes(folder)"
                        class="mt-0.5 text-xs tabular-nums"
                        :class="
                          isFolderSelected(folder)
                            ? 'text-white/60'
                            : 'text-n-slate-9'
                        "
                      >
                        {{ fmtSize(folderBytes(folder)) }}
                      </div>
                    </template>
                  </div>
                </div>
              </button>

              <!-- 悬停操作：重命名 / 删除（仅分类文件夹，空且无子文件夹才可删）-->
              <div
                v-if="
                  folder.type === 'category' &&
                  canManageBoard &&
                  editingId !== folder.id
                "
                class="absolute z-10 flex items-center gap-0.5 top-4 right-2 opacity-0 group-hover/folder:opacity-100"
              >
                <button
                  type="button"
                  class="flex items-center justify-center rounded size-6 bg-n-solid-1/80 text-n-slate-11 hover:text-n-slate-12 hover:bg-n-solid-1"
                  :title="t('CRM.KNOWLEDGE_DOCS.CATEGORY.RENAME')"
                  @click.stop="startRename(folder)"
                >
                  <span class="i-lucide-pencil size-3.5" />
                </button>
                <button
                  v-if="!folder.docs.length && !folder.childCount"
                  type="button"
                  class="flex items-center justify-center rounded size-6 bg-n-solid-1/80 text-n-slate-11 hover:text-n-ruby-11 hover:bg-n-solid-1"
                  :title="t('CRM.KNOWLEDGE_DOCS.CATEGORY.DELETE')"
                  @click.stop="removeCategory(folder)"
                >
                  <span class="i-lucide-trash-2 size-3.5" />
                </button>
              </div>
            </div>

            <!-- 新建文件夹（当前层允许时）-->
            <div v-if="canAddFolderHere" class="flex flex-col pt-2">
              <div
                class="flex items-center justify-center border border-dashed h-28 rounded-xl border-white/60 bg-white/15 backdrop-blur-xl"
              >
                <input
                  v-if="adding"
                  v-model="newCategoryName"
                  :placeholder="
                    t('CRM.KNOWLEDGE_DOCS.CATEGORY.NAME_PLACEHOLDER')
                  "
                  class="w-11/12 h-8 px-2 text-sm border rounded-md border-n-weak bg-n-solid-1 text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-8"
                  @keyup.enter="saveAdd"
                  @blur="saveAdd"
                />
                <button
                  v-else
                  type="button"
                  class="flex flex-col items-center gap-1 text-sm text-n-slate-10 hover:text-n-slate-12"
                  @click="startAdd"
                >
                  <span class="i-lucide-folder-plus size-6" />
                  {{ t('CRM.KNOWLEDGE_DOCS.VIEW.ADD_FOLDER') }}
                </button>
              </div>
            </div>

            <!-- 新建板块（文档中心根层；建完即时进网格 + 左侧栏）-->
            <div v-if="canAddSectionHere" class="flex flex-col pt-2">
              <div
                class="flex items-center justify-center border border-dashed h-28 rounded-xl border-n-iris-6 bg-n-iris-3/40 backdrop-blur-xl"
              >
                <input
                  v-if="addingRootSection"
                  v-model="newRootSectionName"
                  :placeholder="
                    t('CRM.KNOWLEDGE_DOCS.VIEW.ADD_SECTION_PLACEHOLDER')
                  "
                  class="w-11/12 h-8 px-2 text-sm border rounded-md border-n-weak bg-n-solid-1 text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-8"
                  @keyup.enter="saveAddSection"
                  @blur="saveAddSection"
                />
                <button
                  v-else
                  type="button"
                  class="flex flex-col items-center gap-1 text-sm text-n-iris-11 hover:text-n-iris-12"
                  @click="startAddSection"
                >
                  <span class="i-lucide-folder-plus size-6" />
                  {{ t('CRM.KNOWLEDGE_DOCS.VIEW.ADD_SECTION') }}
                </button>
              </div>
            </div>
          </div>

          <!-- 本层文档（搜索时平铺命中；分类/叶子节点显示其文档）-->
          <div
            v-if="currentDocs.length || (!isSearching && canCreateDocsHere)"
            :class="!isSearching && sortedFolders.length ? 'mt-6' : ''"
          >
            <div
              v-if="!isSearching && sortedFolders.length && currentDocs.length"
              class="mb-2 text-xs font-medium text-n-slate-10"
            >
              {{ t('CRM.KNOWLEDGE_DOCS.VIEW.DOCS_HERE') }}
            </div>
            <div class="grid grid-cols-1 gap-2.5 sm:grid-cols-2 xl:grid-cols-3">
              <button
                v-for="doc in currentDocs"
                :key="doc.id"
                type="button"
                class="flex flex-col gap-2 p-3 text-left transition-all border rounded-xl bg-n-solid-1 border-n-weak hover:border-n-slate-6 hover:shadow-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-8"
                :class="
                  selectedDoc && selectedDoc.id === doc.id
                    ? 'border-n-blue-8 ring-1 ring-n-blue-8'
                    : ''
                "
                @click="openPanel(doc)"
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
                  <span class="truncate">
                    {{ doc.summary || t('CRM.KNOWLEDGE_DOCS.PANEL.SUMMARY') }}
                  </span>
                </div>
                <div
                  class="flex items-center gap-1 pt-1.5 text-xs border-t text-n-slate-10 border-n-weak"
                >
                  <span v-if="isSearching && doc.category" class="truncate">
                    {{ doc.category }}
                  </span>
                  <span v-else class="i-lucide-clock size-3 shrink-0" />
                  <span :class="isSearching && doc.category ? 'ml-auto' : ''">
                    {{ fmtDate(doc.updatedAt) }}
                  </span>
                </div>
              </button>

              <button
                v-if="!isSearching && canCreateDocsHere"
                type="button"
                class="flex items-center justify-center gap-1 p-3 text-sm border border-dashed rounded-xl text-n-slate-10 border-n-weak hover:bg-n-alpha-1 hover:text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-8"
                @click="openCreatePanel(currentDocCategory)"
              >
                <span class="i-lucide-plus size-4" />
                {{ t('CRM.KNOWLEDGE_DOCS.NEW') }}
              </button>
            </div>
          </div>
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

    <!-- 右侧文件夹信息面板（参考图 Info）：网格里选中文件夹时展示其属性 -->
    <aside
      v-if="!panelMode && selectedFolder && !isSearching && !isRecycle"
      class="flex flex-col w-[340px] flex-shrink-0 overflow-hidden border-l border-n-weak bg-n-solid-1"
    >
      <div
        class="flex items-center justify-between px-5 py-4 border-b border-n-weak"
      >
        <span class="text-base font-semibold text-n-slate-12">
          {{ t('CRM.KNOWLEDGE_DOCS.INFO.TITLE') }}
        </span>
        <button
          type="button"
          class="p-1 rounded text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-1"
          @click="clearFolderSelection"
        >
          <span class="i-lucide-x size-4" />
        </button>
      </div>

      <div class="flex flex-col flex-1 gap-5 p-5 overflow-y-auto">
        <!-- 文件夹标识 -->
        <div class="flex items-center gap-3">
          <span
            class="flex items-center justify-center rounded-lg shrink-0 size-9"
            :class="folderClass(selectedFolder)"
          >
            <span class="i-lucide-folder size-4" />
          </span>
          <div class="min-w-0">
            <div class="text-base font-semibold truncate text-n-slate-12">
              {{
                selectedFolder.uncategorized
                  ? t('CRM.KNOWLEDGE_DOCS.UNCATEGORIZED')
                  : selectedFolder.name
              }}
            </div>
            <div class="text-xs text-n-slate-10">
              {{
                t('CRM.KNOWLEDGE_DOCS.VIEW.COUNT', {
                  count: selectedFolder.docs.length,
                })
              }}
            </div>
          </div>
        </div>

        <!-- 概要数字 -->
        <div class="grid grid-cols-2 gap-3">
          <div class="p-3 border rounded-xl border-n-weak">
            <div class="text-2xl font-semibold tabular-nums text-n-slate-12">
              {{ selectedFolder.docs.length }}
            </div>
            <div class="text-xs text-n-slate-10">
              {{ t('CRM.KNOWLEDGE_DOCS.INFO.DOC_COUNT') }}
            </div>
          </div>
          <div class="p-3 border rounded-xl border-n-weak">
            <div class="text-2xl font-semibold tabular-nums text-n-slate-12">
              {{ fmtSize(folderBytes(selectedFolder)) || '—' }}
            </div>
            <div class="text-xs text-n-slate-10">
              {{ t('CRM.KNOWLEDGE_DOCS.INFO.SIZE') }}
            </div>
          </div>
        </div>

        <!-- 属性 -->
        <div>
          <div class="mb-2 text-xs font-medium text-n-slate-10">
            {{ t('CRM.KNOWLEDGE_DOCS.INFO.PROPERTIES') }}
          </div>
          <div class="flex flex-col gap-2 text-sm">
            <div class="flex items-center justify-between">
              <span class="text-n-slate-10">
                {{ t('CRM.KNOWLEDGE_DOCS.INFO.SIZE') }}
              </span>
              <span class="text-n-slate-12 tabular-nums">
                {{ fmtSize(folderBytes(selectedFolder)) || '—' }}
              </span>
            </div>
            <div class="flex items-center justify-between">
              <span class="text-n-slate-10">
                {{ t('CRM.KNOWLEDGE_DOCS.INFO.LAST_MODIFIED') }}
              </span>
              <span class="text-n-slate-12 tabular-nums">
                {{ fmtDate(folderLastModified(selectedFolder)) || '—' }}
              </span>
            </div>
          </div>
        </div>

        <!-- 标签 -->
        <div>
          <div class="mb-2 text-xs font-medium text-n-slate-10">
            {{ t('CRM.KNOWLEDGE_DOCS.INFO.TAGS') }}
          </div>
          <div class="flex flex-wrap gap-1.5">
            <span
              v-if="activeSection"
              class="px-2 py-0.5 text-xs rounded-full bg-n-iris-3 text-n-iris-11"
            >
              {{ activeSection.name }}
            </span>
            <span
              class="px-2 py-0.5 text-xs rounded-full bg-n-teal-3 text-n-teal-11"
            >
              {{ t('CRM.KNOWLEDGE_DOCS.INFO.SCOPE_COMPANY') }}
            </span>
          </div>
        </div>
      </div>

      <div class="px-5 py-4 border-t border-n-weak">
        <Button
          :label="t('CRM.KNOWLEDGE_DOCS.INFO.OPEN')"
          icon="i-lucide-folder-open"
          color="iris"
          class="justify-center w-full"
          @click="enterFolder(selectedFolder)"
        />
      </div>
    </aside>

    <!-- 板块管理（管理员）：新增/删除自定义板块。可见性在各板块顶栏「设置可见成员」 -->
    <Dialog
      ref="sectionDialogRef"
      width="md"
      overflow-y-auto
      confirm-button-color="iris"
      :title="t('CRM.KNOWLEDGE_DOCS.SECTION.SETTINGS')"
      @confirm="sectionDialogRef?.close()"
    >
      <p class="mb-4 text-xs text-n-slate-10">
        {{ t('CRM.KNOWLEDGE_DOCS.SECTION.MANAGE_HINT') }}
      </p>
      <div class="flex flex-col gap-4">
        <div class="flex flex-col">
          <div
            v-for="draft in sectionDraft"
            :key="draft.id"
            class="flex items-center justify-between gap-2 py-1.5 border-b border-n-weak last:border-b-0"
          >
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

    <!-- 板块负责人设置（超管/管理员）：勾选成员，负责人可管该板块下全部公司文档 -->
    <Dialog
      ref="ownerDialogRef"
      confirm-button-color="iris"
      :title="
        activeSection
          ? `${activeSection.name} · ${t('CRM.KNOWLEDGE_DOCS.SECTION.OWNER_SET')}`
          : t('CRM.KNOWLEDGE_DOCS.SECTION.OWNER_SET')
      "
      :is-loading="savingOwners"
      @confirm="saveSectionOwners"
    >
      <div class="flex flex-col gap-3">
        <p class="text-xs text-n-slate-10">
          {{ t('CRM.KNOWLEDGE_DOCS.SECTION.OWNER_HINT') }}
        </p>
        <Input
          v-model="ownerSearch"
          :placeholder="t('CRM.KNOWLEDGE_DOCS.SECTION.OWNER_SEARCH')"
        />
        <div
          class="flex flex-col gap-1 p-2 overflow-y-auto border rounded-lg max-h-64 border-n-weak"
        >
          <label
            v-for="m in ownerCandidates"
            :key="m.user_id"
            class="flex items-center gap-2.5 px-2 py-1.5 rounded-md cursor-pointer hover:bg-n-alpha-1"
          >
            <input
              type="checkbox"
              class="accent-n-brand"
              :checked="ownerDraftIds.includes(m.user_id)"
              @change="toggleOwner(m.user_id)"
            />
            <span class="flex-1 min-w-0">
              <span class="block text-sm truncate text-n-slate-12">
                {{ m.name }}
              </span>
              <span class="block text-xs truncate text-n-slate-10">
                {{ m.email }}
              </span>
            </span>
          </label>
        </div>
      </div>
    </Dialog>

    <!-- 板块可见成员设置（超管/管理员）：搜索勾选成员，空=全员可见 -->
    <Dialog
      ref="viewerDialogRef"
      confirm-button-color="iris"
      :title="
        activeSection
          ? `${activeSection.name} · ${t('CRM.KNOWLEDGE_DOCS.SECTION.VIEWER_SET')}`
          : t('CRM.KNOWLEDGE_DOCS.SECTION.VIEWER_SET')
      "
      :is-loading="savingViewers"
      @confirm="saveSectionViewers"
    >
      <div class="flex flex-col gap-3">
        <p class="text-xs text-n-slate-10">
          {{ t('CRM.KNOWLEDGE_DOCS.SECTION.VIEWER_HINT') }}
        </p>
        <Input
          v-model="viewerSearch"
          :placeholder="t('CRM.KNOWLEDGE_DOCS.SECTION.VIEWER_SEARCH')"
        />
        <div
          class="flex flex-col gap-1 p-2 overflow-y-auto border rounded-lg max-h-64 border-n-weak"
        >
          <label
            v-for="m in viewerCandidates"
            :key="m.user_id"
            class="flex items-center gap-2.5 px-2 py-1.5 rounded-md cursor-pointer hover:bg-n-alpha-1"
          >
            <input
              type="checkbox"
              class="accent-n-brand"
              :checked="viewerDraftIds.includes(m.user_id)"
              @change="toggleViewer(m.user_id)"
            />
            <span class="flex-1 min-w-0">
              <span class="block text-sm truncate text-n-slate-12">
                {{ m.name }}
              </span>
              <span class="block text-xs truncate text-n-slate-10">
                {{ m.email }}
              </span>
            </span>
          </label>
        </div>
      </div>
    </Dialog>
  </div>
</template>
