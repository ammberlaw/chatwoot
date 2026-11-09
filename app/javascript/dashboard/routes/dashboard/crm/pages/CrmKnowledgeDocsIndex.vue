<script setup>
import CrmFolderArtwork from 'dashboard/components-next/CRM/CrmFolderArtwork.vue';
/* global axios */
import { ref, reactive, computed, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { useCrmRole } from 'dashboard/composables/useCrmRole';
import { emitter } from 'shared/helpers/mitt';
import * as XLSX from 'xlsx';
import { useCrmKnowledgeDocsStore } from 'dashboard/stores/crm/knowledgeDocs';
import { useCrmKnowledgeCategoriesStore } from 'dashboard/stores/crm/knowledgeCategories';
import DocSectionsAPI from 'dashboard/api/crm/docSections';
import { useDocFolderStyle } from 'dashboard/composables/useDocFolderStyle';
import CrmFolderStylePicker from 'dashboard/components-next/CRM/CrmFolderStylePicker.vue';

import CrmDocSectionManager from 'dashboard/components-next/CRM/CrmDocSectionManager.vue';
import CrmCredentialVault from 'dashboard/components-next/CRM/CrmCredentialVault.vue';
import CrmFileIcon from 'dashboard/components-next/CRM/CrmFileIcon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

const { t } = useI18n();
const route = useRoute();
const { accountId } = useAccount();
const store = useCrmKnowledgeDocsStore();
const categoriesStore = useCrmKnowledgeCategoriesStore();
const { folderStyleKey, styleForFolder } = useDocFolderStyle();
const folderStylePicker = ref(null);

const activeFilter = ref(route.query.filter || 'company');
// 文档中心「板块」筛选：侧栏板块子项带 ?section=<id>；为空=「全公司文档」(全部板块)。
const activeSectionId = ref(
  route.query.section ? Number(route.query.section) : null
);
const searchQuery = ref('');
let searchTimer = null;

// 管理板块面板（管理员）。改动后广播，侧栏板块即时刷新；当前视图也重拉。
const showSectionManager = ref(false);
const onSectionsUpdated = () => {
  emitter.emit('crmDocSectionsUpdated');
  fetchDocSections();
  fetchCategories();
};

// 资料库归属由路由 meta 决定：销售资料(SALES) / 全公司知识(GENERAL)。同一组件两路由复用。
const currentLibrary = computed(() => route.meta.library || 'SALES');
const isGeneral = computed(() => currentLibrary.value === 'GENERAL');

// ── 权限：公司文档管理权=管理员/副管理员/部门负责人（文档中心另加指定负责人）；其他人只能浏览下载 ──
const currentUserId = useMapGetter('getCurrentUserID');
const { isAdmin, isCrmDeputyAdmin, isCrmManager } = useCrmRole();

const isAdminLike = computed(() => isAdmin.value || isCrmDeputyAdmin.value);

const canManageCompany = computed(
  () => isAdminLike.value || isCrmManager.value
);

// 文档中心「板块负责人」(manager_ids)：可管理/上传/编辑该板块下的公司文档。
// 板块数据带 manager_ids，从 doc_sections 接口取（与侧栏同源）。
const docSections = ref([]);
const fetchDocSections = async () => {
  try {
    const { data } = await DocSectionsAPI.get();
    docSections.value = data.payload || [];
  } catch {
    docSections.value = [];
  }
};
const managedSectionIds = computed(() =>
  docSections.value
    .filter(s => (s.manager_ids || []).includes(currentUserId.value))
    .map(s => s.id)
);
// 当前板块是否由本人负责（仅文档中心 GENERAL 库按板块授权）。
const managesActiveSection = computed(
  () =>
    isGeneral.value &&
    !!activeSectionId.value &&
    managedSectionIds.value.includes(activeSectionId.value)
);
// 当前板块负责人（展示给全员，让大家知道该板块归谁、该找谁）。
const activeSection = computed(
  () => docSections.value.find(s => s.id === activeSectionId.value) || null
);
const activeSectionManagerNames = computed(
  () => activeSection.value?.manager_names || []
);

// 面包屑根节点标签：文档中心内选中板块显板块名（销售资料/公司制度…），未选＝「全公司文档」；
// 避免「文档中心」在标题/侧栏/面包屑重复三次。销售资料库仍用其固定标题。
const rootLabel = computed(() => {
  if (!isGeneral.value) return t('CRM.KNOWLEDGE_DOCS.HEADER');
  if (activeSection.value) return activeSection.value.name;
  return t('CRM.KNOWLEDGE_DOCS.ALL_COMPANY');
});

// 我的资料视图：看板列是个人分类，人人可自建自管；公司视图的分类仍按公司管理权。
const isMineView = computed(
  () => !isGeneral.value && activeFilter.value === 'mine'
);
const canManageBoard = computed(
  () => isMineView.value || canManageCompany.value || managesActiveSection.value
);

// 文档中心：选中板块则取该板块文件夹；「全公司文档」取全部。
const fetchCategories = () => {
  if (isMineView.value) return categoriesStore.get({ view: 'mine' });
  const params = { library: currentLibrary.value };
  if (isGeneral.value && activeSectionId.value) {
    params.section_id = activeSectionId.value;
  }
  return categoriesStore.get(params);
};

// 个人文档归属人可管；公司文档=超管/管理员；销售资料另放开部门负责人。
const canManageDoc = doc => {
  if (doc?.scope === 'PERSONAL') return doc.ownerId === currentUserId.value;
  if (isAdminLike.value) return true;
  // 板块负责人可管本板块下的公司文档。
  if (doc?.sectionId && managedSectionIds.value.includes(doc.sectionId)) {
    return true;
  }
  return !isGeneral.value && isCrmManager.value;
};
// 新建入口：超管/管理员随处；销售资料人人可建（个人文档）；板块负责人可在自己板块建。
const canCreateDocs = computed(
  () => isAdminLike.value || !isGeneral.value || managesActiveSection.value
);

const records = computed(() => store.getRecords);
// 真实总数（后端 meta.count，不受一次拉取上限影响）。
const totalCount = computed(() => store.meta?.count || 0);
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

// ── 纯文件识别：直传的文件=单附件 + 标题就是文件名 + 没写正文/摘要。
// 这类当「文件」处理（图标+大小、点击直接下载），不再弹文档详情壳子；
// 写了正文/摘要或多附件的仍是「文档」，照旧开详情。
const isFileDoc = doc => {
  const files = doc.files || [];
  if (files.length !== 1) return false;
  const hasText =
    (doc.body && doc.body.trim()) || (doc.summary && doc.summary.trim());
  return !hasText; // 单附件 + 没写正文/摘要 = 文件（改名后仍是文件）
};
// 图片文件在宫格里直接出缩略图——一屏几十个随机文件名（c475031b…），
// 光看一模一样的蓝色图片图标认不出是哪张。缩略图由后端出变体链接（files[].thumbUrl）。
// 多附件的条目不走缩略图：那是「文档」，不是单张图。
const thumbBroken = reactive({});
const docThumb = doc => {
  const files = doc.files || [];
  if (files.length !== 1 || thumbBroken[doc.id]) return '';
  return files[0].thumbUrl || '';
};

// 文件列表用的是 CrmFileIcon（折角纸页）；这里只剩预览弹窗标题那处的小号线性图标。
const FILE_ICONS = [
  { ext: ['pdf'], icon: 'i-lucide-file-text' },
  { ext: ['xls', 'xlsx', 'csv'], icon: 'i-lucide-file-spreadsheet' },
  { ext: ['doc', 'docx'], icon: 'i-lucide-file-text' },
  {
    ext: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg'],
    icon: 'i-lucide-image',
  },
  { ext: ['zip', 'rar', '7z', 'tar', 'gz'], icon: 'i-lucide-file-archive' },
];
const fileMeta = filename => {
  const ext = (filename || '').split('.').pop().toLowerCase();
  return FILE_ICONS.find(m => m.ext.includes(ext)) || { icon: 'i-lucide-file' };
};
// 下载一律走 downloadUrl（强制 attachment，带真文件名）；url 是预览用的 inline 链接，
// 拿它下载会被命名成对象存储的随机 key。
const fileHref = file => file?.downloadUrl || file?.download_url || file?.url;
const openDocFile = doc => {
  const href = fileHref((doc.files || [])[0]);
  if (href) window.open(href, '_blank', 'noopener');
};

// ── 在线预览：视频/图片/PDF/音频直接看；Excel/Word 前端解析；其余提示下载 ──
const PREVIEW_KINDS = {
  video: ['mp4', 'webm', 'ogv', 'mov', 'm4v'],
  image: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg', 'avif'],
  pdf: ['pdf'],
  audio: ['mp3', 'wav', 'm4a', 'aac', 'oga', 'ogg'],
  excel: ['xlsx', 'xls', 'csv'],
  word: ['docx'], // 仅 docx（旧 .doc 二进制前端转不了）
};
// 超过此大小不在线转换（大文件前端解析会卡死/撑爆浏览器），直接提示下载。
const PREVIEW_SIZE_LIMIT = 20 * 1024 * 1024;
const previewDoc = ref(null);
const excelHtml = ref('');
const excelLoading = ref(false);
const wordHtml = ref('');
const wordLoading = ref(false);
// 预览类型按【实际文件扩展名】判定（文档标题可能没带扩展名，之前用标题会误判成「不支持」）。
const extOf = s => {
  const parts = (s || '').toLowerCase().split('.');
  return parts.length > 1 ? parts.pop() : '';
};
const previewExt = () =>
  extOf(previewDoc.value?.files?.[0]?.filename) ||
  extOf(previewDoc.value?.name);
const previewKind = computed(() => {
  const ext = previewExt();
  return (
    Object.keys(PREVIEW_KINDS).find(k => PREVIEW_KINDS[k].includes(ext)) ||
    'other'
  );
});
const previewUrl = computed(() => previewDoc.value?.files?.[0]?.url || '');
// PDF 预览走同源代理链接：它的末段是真文件名，而 url 会 302 到对象存储、末段变成随机 key。
// 浏览器设了「下载 PDF 而不是在浏览器中打开」时，后者在 iframe 里只剩一张以 key 命名的占位页。
const previewPdfUrl = computed(
  () => previewDoc.value?.files?.[0]?.proxyUrl || previewUrl.value
);
const previewTooLarge = computed(
  () => (previewDoc.value?.files?.[0]?.byteSize || 0) > PREVIEW_SIZE_LIMIT
);
// Excel 前端解析成 HTML 表格预览（不用后端、不用公开文件）
const loadExcel = async () => {
  excelLoading.value = true;
  excelHtml.value = '';
  try {
    const buf = await (await fetch(previewUrl.value)).arrayBuffer();
    const wb = XLSX.read(buf, { type: 'array' });
    const sheet = wb.Sheets[wb.SheetNames[0]];
    excelHtml.value = sheet ? XLSX.utils.sheet_to_html(sheet) : '';
  } catch {
    excelHtml.value = '';
  } finally {
    excelLoading.value = false;
  }
};
// Word(docx) 前端用 mammoth 转 HTML，DOMPurify 消毒后展示。
const loadWord = async () => {
  wordLoading.value = true;
  wordHtml.value = '';
  try {
    const [{ default: mammoth }, { default: DOMPurify }] = await Promise.all([
      import('mammoth'),
      import('dompurify'),
    ]);
    const buf = await (await fetch(previewUrl.value)).arrayBuffer();
    const { value } = await mammoth.convertToHtml({ arrayBuffer: buf });
    wordHtml.value = DOMPurify.sanitize(value || '');
  } catch {
    wordHtml.value = '';
  } finally {
    wordLoading.value = false;
  }
};
const openPreview = doc => {
  previewDoc.value = doc;
  excelHtml.value = '';
  wordHtml.value = '';
  if (previewTooLarge.value) return; // 大文件不在线转换，模板提示下载
  const ext = previewExt();
  if (['xlsx', 'xls', 'csv'].includes(ext)) loadExcel();
  else if (ext === 'docx') loadWord();
};
const initial = name => (name || '?').trim().charAt(0).toUpperCase();
const scopeLabel = scope => (scope === 'PERSONAL' ? '个人' : '公司');
const fmtDateTime = v => (v ? new Date(v).toLocaleString() : '');

// 分类全路径标签（多级目录里同名文件夹靠路径区分），供建档表单下拉。
const categoryById = id => categories.value.find(c => c.id === id);
const categoryPath = cat => {
  const parts = [];
  const seen = new Set();
  let cur = cat;
  while (cur && !seen.has(cur.id)) {
    seen.add(cur.id);
    parts.unshift(cur.name);
    cur = cur.parentId ? categoryById(cur.parentId) : null;
  }
  return parts.join(' / ');
};
const categoryOptions = computed(() => [
  { value: null, label: t('CRM.KNOWLEDGE_DOCS.FORM.ROOT') },
  ...categories.value.map(c => ({ value: c.id, label: categoryPath(c) })),
]);
const scopeOptions = [
  { value: 'COMPANY', label: '公司' },
  { value: 'PERSONAL', label: '个人' },
];

// ── 三级目录导航：path 栈（板块 → 分类 → 子分类）。当前节点决定显示的子文件夹与文档 ──
// path 元素：{ type:'section'|'category'|'orphan'|'uncategorized', id, name }
const pathStack = ref([]); // 空=根
const isSearching = computed(() => !!searchQuery.value.trim());
// 已加载数 < 真实总数 = 超一次拉取上限被截断，显式提示，绝不静默吞掉文档。
const isTruncated = computed(
  () => !isSearching.value && totalCount.value > records.value.length
);

const currentNode = computed(() =>
  pathStack.value.length ? pathStack.value[pathStack.value.length - 1] : null
);
// 当前所在文件夹 ID（分类节点=其 id；板块/根=null，即松散文件）
const currentCategoryId = computed(() =>
  currentNode.value?.type === 'category' ? currentNode.value.id : null
);
// 能否在当前层新建子文件夹：有管理权 + 非搜索（根层与任意文件夹内都可，像电脑盘）
const canAddFolderHere = computed(
  () => canManageBoard.value && !isSearching.value
);
// 能否在当前层新建文档/传文件：文件夹内或根层（松散文件）
const canCreateDocsHere = computed(() => {
  if (!canCreateDocs.value || isSearching.value) return false;
  const type = currentNode.value?.type;
  return type === 'category' || !currentNode.value;
});

// 分类树：按 parentId 取子分类；文档按 category_id 归属（支持任意层级 + 同名子文件夹）。
const childrenOf = parentId =>
  categories.value.filter(c => (c.parentId ?? null) === (parentId ?? null));
const descendantIds = catId => {
  const ids = [catId];
  const walk = id =>
    childrenOf(id).forEach(c => {
      ids.push(c.id);
      walk(c.id);
    });
  walk(catId);
  return ids;
};
// 分类文件夹的子树文档（该分类及其所有后代分类下的文档）
const subtreeDocsOf = catId => {
  const ids = new Set(descendantIds(catId));
  return records.value.filter(d => d.categoryId && ids.has(d.categoryId));
};

// 某父级下的分类文件夹
const buildCatFolders = parentId =>
  childrenOf(parentId).map(c => ({
    type: 'category',
    id: c.id,
    name: c.name,
    docs: subtreeDocsOf(c.id),
    childCount: childrenOf(c.id).length,
  }));

// 当前节点下的子文件夹（根层=顶层文件夹）
const currentFolders = computed(() => {
  const n = currentNode.value;
  if (!n) return buildCatFolders(null);
  if (n.type === 'category') return buildCatFolders(n.id);
  return [];
});

// 当前节点下直接归属的文档（按 category_id）；根层显示未归档的松散文件。
const currentDocs = computed(() => {
  if (isSearching.value) return records.value;
  const n = currentNode.value;
  if (!n) return records.value.filter(d => !d.categoryId);
  if (n.type === 'category')
    return records.value.filter(d => d.categoryId === n.id);
  return [];
});

// 面包屑
const breadcrumb = computed(() =>
  pathStack.value.map(n => ({ ...n, label: n.name }))
);

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

// ── 进入 / 返回导航（像电脑文件夹逐级下钻）──
const folderKeyOf = f => `${f.type}:${f.id}`;

// 进入文件夹：逐级压栈（像电脑文件夹下钻）
const enterFolder = f => {
  pathStack.value = [
    ...pathStack.value,
    { type: f.type, id: f.id, name: f.name },
  ];
};
// 面包屑跳转：i<0 回根
const goToDepth = i => {
  pathStack.value = i < 0 ? [] : pathStack.value.slice(0, i + 1);
};
// 回根（库切换/筛选切换时复位）
const backToFolders = () => {
  pathStack.value = [];
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
  ...(isGeneral.value ? [{ key: 'vault', label: '账号密码' }] : []),
  ...(isGeneral.value
    ? []
    : [{ key: 'mine', label: t('CRM.KNOWLEDGE_DOCS.FILTERS.MINE') }]),
  ...((isAdmin.value || isCrmDeputyAdmin.value) && isGeneral.value
    ? [{ key: 'recycle', label: t('CRM.KNOWLEDGE_DOCS.RECYCLE.TAB') }]
    : []),
]);

// 账号密码：与文档是两套存储，只共用文档中心这个入口（谁能看由分组名单定，组件内自理）。
const isVault = computed(() => activeFilter.value === 'vault');

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
    per_page: 5000,
  });
};

// 在两个资料库路由间切换时（同组件复用），重新拉取对应库的文档。
watch(currentLibrary, () => {
  backToFolders();
  fetchRecords();
});

// 侧栏切换板块 / 视图（同一路由改 query）时同步状态并重新拉取。
watch(
  () => [route.query.section, route.query.filter],
  () => {
    activeSectionId.value = route.query.section
      ? Number(route.query.section)
      : null;
    activeFilter.value = route.query.filter || 'company';
    backToFolders();
    fetchRecords();
    fetchCategories();
  }
);

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
  categoryId: null,
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

const openPanel = doc => {
  selectedDoc.value = doc;
  panelMode.value = 'view';
  panelTab.value = 'detail';
  panelAudits.value = [];
  panelAttachments.value = doc.files || [];
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
  editForm.categoryId = doc.categoryId ?? null;
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
    categoryId: editForm.categoryId ?? null,
    scope: editForm.scope,
    library: currentLibrary.value,
    summary: editForm.summary.trim() || null,
    body: editForm.body || null,
  };
  try {
    if (isCreate.value) {
      const created = await store.create({
        ...payload,
        sectionId: isGeneral.value ? activeSectionId.value : undefined,
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

// ── 网盘式直传：选/拖文件 → 每个文件直接成一条文档（标题=文件名，免填摘要正文）──
const directFileInput = ref(null);
const directUploading = ref(false);
const directProgress = reactive({ done: 0, total: 0 });
const isDragging = ref(false);

const defaultDocScope = () =>
  !isGeneral.value && (isMineView.value || !canManageCompany.value)
    ? 'PERSONAL'
    : 'COMPANY';

const triggerDirectUpload = () => directFileInput.value?.click();

const uploadFilesAsDocs = async fileList => {
  const files = Array.from(fileList || []).filter(Boolean);
  if (!files.length) return;
  if (!canCreateDocsHere.value) {
    useAlert(t('CRM.KNOWLEDGE_DOCS.UPLOAD.NO_PERMISSION'));
    return;
  }
  directUploading.value = true;
  directProgress.total = files.length;
  directProgress.done = 0;
  let ok = 0;
  // 逐个建档：复用 create（含权限/板块/分类校验 + multipart 附件）。
  // eslint-disable-next-line no-restricted-syntax
  for (const file of files) {
    try {
      // eslint-disable-next-line no-await-in-loop
      await store.create({
        name: file.name,
        categoryId: currentCategoryId.value,
        sectionId: isGeneral.value ? activeSectionId.value : undefined,
        scope: defaultDocScope(),
        library: currentLibrary.value,
        summary: null,
        body: null,
        __files: [file],
      });
      ok += 1;
    } catch {
      // 单个失败不中断，继续传其余文件
    }
    directProgress.done += 1;
  }
  directUploading.value = false;
  fetchRecords();
  const fail = files.length - ok;
  if (!fail) useAlert(t('CRM.KNOWLEDGE_DOCS.UPLOAD.SUCCESS', { count: ok }));
  else if (ok) useAlert(t('CRM.KNOWLEDGE_DOCS.UPLOAD.PARTIAL', { ok, fail }));
  else useAlert(t('CRM.KNOWLEDGE_DOCS.UPLOAD.ERROR'));
};

const onDirectFiles = event => {
  // 先拷成数组再清空 input：直接持有实时 FileList 再置空 value 会把它清空。
  const files = Array.from(event.target.files || []);
  event.target.value = '';
  uploadFilesAsDocs(files);
};

const onContentDragOver = () => {
  if (canCreateDocsHere.value && !directUploading.value)
    isDragging.value = true;
};
const onContentDragLeave = () => {
  isDragging.value = false;
};
const onContentDrop = event => {
  isDragging.value = false;
  uploadFilesAsDocs(event.dataTransfer?.files);
};

// ── 分类管理（新增 / 重命名 / 删除空分类）──
const editingId = ref(null);
const editingName = ref('');
// 当前悬停的文件夹（用 JS 控制改名/删除按钮显隐，比 CSS group-hover 稳）
const hoveredFolderId = ref(null);

// 就地重命名输入框自动聚焦并全选（仅首次挂载时；已聚焦则跳过，避免每次输入被重新全选）
const focusRename = el => {
  if (!el || el === document.activeElement) return;
  el.focus();
  el.select?.();
};

// Finder 式新建文件夹：立刻建「未命名文件夹」（同层自动去重）并进入就地改名。
//
// creatingFolder 防的是连点：两次调用会算出同一个「未命名文件夹 N」，
// 一个建成、另一个撞同层重名的唯一索引报 500（2026-11-06 生产日志里就有一次）。
const creatingFolder = ref(false);
const createUnnamedFolder = async () => {
  if (creatingFolder.value) return;
  creatingFolder.value = true;
  const base = t('CRM.KNOWLEDGE_DOCS.VIEW.NEW_FOLDER_DEFAULT');
  const siblings = new Set(
    currentFolders.value.filter(f => f.type === 'category').map(f => f.name)
  );
  let name = base;
  let i = 2;
  while (siblings.has(name)) {
    name = `${base} ${i}`;
    i += 1;
  }
  try {
    const created = await categoriesStore.create({
      name,
      position: categories.value.length,
      personal: isMineView.value,
      library: currentLibrary.value,
      parent_id: currentCategoryId.value, // 在某分类里新建=其子分类
      section_id: isGeneral.value ? activeSectionId.value : undefined, // 在板块内新建=归该板块
    });
    await fetchCategories();
    if (created?.id) {
      editingId.value = created.id;
      editingName.value = created.name;
    }
  } catch {
    useAlert(t('CRM.KNOWLEDGE_DOCS.CATEGORY.SAVE_ERROR'));
  } finally {
    creatingFolder.value = false;
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

// ── 文件（网格卡片）就地改名 / 删除 ──
const hoveredDocId = ref(null);
const editingDocId = ref(null);
const editingDocName = ref('');
const startRenameDoc = doc => {
  editingDocId.value = doc.id;
  editingDocName.value = doc.name;
};
const saveRenameDoc = async () => {
  const id = editingDocId.value;
  const name = editingDocName.value.trim();
  editingDocId.value = null;
  if (!id || !name) return;
  try {
    await store.update({ id, name });
    fetchRecords();
  } catch {
    useAlert(t('CRM.KNOWLEDGE_DOCS.EDIT.ERROR'));
  }
};
const removeDocDirect = async doc => {
  const ok = window.confirm(
    t('CRM.KNOWLEDGE_DOCS.DELETE.CONFIRM', { name: doc.name })
  );
  if (!ok) return;
  try {
    await store.delete(doc.id);
    fetchRecords();
  } catch {
    useAlert(t('CRM.KNOWLEDGE_DOCS.DELETE.ERROR'));
  }
};

onMounted(() => {
  fetchRecords();
  fetchCategories();
  if (isGeneral.value) fetchDocSections();
});
watch(
  () => route.query.filter,
  filter => {
    activeFilter.value = filter || 'company';
    closePanel();
    pathStack.value = [];
    fetchRecords();
    fetchCategories();
  }
);
</script>

<template>
  <div
    class="flex w-full h-full overflow-hidden backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border bg-n-solid-1/80 border-n-weak/70 shadow-wintouch-glass"
  >
    <div class="flex flex-col flex-1 min-w-0 overflow-hidden">
      <div
        class="flex items-center justify-between flex-shrink-0 gap-3 px-4 py-3 border-b sm:px-6 sm:py-4 border-n-weak [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:sm:!px-8"
      >
        <div class="min-w-0">
          <h1 class="truncate text-n-slate-12 text-heading-1">
            {{
              isGeneral
                ? t('CRM.KNOWLEDGE_DOCS.HEADER_GENERAL')
                : t('CRM.KNOWLEDGE_DOCS.HEADER')
            }}
          </h1>
          <!-- 副标题只留给「文档中心」：销售资料页的那句说明用户不要了。 -->
          <p v-if="isGeneral" class="mt-0.5 text-xs text-n-slate-10">
            {{ t('CRM.KNOWLEDGE_DOCS.SUBTITLE_GENERAL') }}
          </p>
        </div>
        <div class="flex items-center gap-3 shrink-0">
          <Button
            v-if="(isGeneral || isMineView) && !isVault && !isRecycle"
            :label="t('CRM.KNOWLEDGE_DOCS.FOLDER_STYLE.TITLE')"
            icon="i-lucide-palette"
            variant="outline"
            color="slate"
            size="sm"
            @click="folderStylePicker.open()"
          />
          <Button
            v-if="isGeneral && isAdminLike && !isVault"
            label="管理板块"
            icon="i-lucide-folder-cog"
            variant="outline"
            color="slate"
            size="sm"
            @click="showSectionManager = true"
          />
        </div>
      </div>

      <div
        class="flex flex-wrap items-center gap-2 px-4 py-3 border-b sm:px-6 border-n-weak [.theme-classic_&]:sm:!px-8"
      >
        <div class="contents" data-tabbar="page" data-tabbar-theme="classic">
          <Button
            v-for="tab in filterTabs"
            :key="tab.key"
            :label="tab.label"
            size="sm"
            :aria-selected="activeFilter === tab.key"
            :variant="activeFilter === tab.key ? 'solid' : 'faded'"
            :color="activeFilter === tab.key ? 'iris' : 'slate'"
            @click="setFilter(tab.key)"
          />
        </div>
        <!-- Filter：文件夹排序 -->
        <SelectCard
          v-if="!isRecycle && !isVault"
          v-model="folderSort"
          :options="FOLDER_SORTS"
          align="right"
          class="ml-auto"
          trigger-class="w-32 h-9"
        />
        <Input
          v-if="!isVault"
          v-model="searchQuery"
          :placeholder="t('CRM.KNOWLEDGE_DOCS.SEARCH_PLACEHOLDER')"
          :class="isRecycle ? 'w-full sm:ml-auto sm:w-56' : 'w-full sm:w-56'"
          @input="onSearchInput"
        />
      </div>

      <CrmCredentialVault v-if="isVault" />

      <div
        v-else-if="isFetching || loadingRecycle"
        class="flex items-center justify-center flex-1 text-base text-n-slate-11"
      >
        {{ t('CRM.KNOWLEDGE_DOCS.LOADING') }}
      </div>

      <!-- 文档回收站（仅管理员）：可恢复 / 彻底删除 / 清空 -->
      <div
        v-else-if="isRecycle"
        class="flex-1 px-4 py-3 overflow-y-auto sm:px-6 sm:py-4 [.theme-classic_&]:sm:!px-8"
      >
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

        <template v-else>
          <!-- 手机卡片 -->
          <div class="flex flex-col gap-2 md:hidden">
            <div
              v-for="doc in recycleDocs"
              :key="`m-${doc.id}`"
              class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl"
            >
              <div class="flex items-center gap-2">
                <span class="font-medium truncate text-n-slate-12">
                  {{ doc.name }}
                </span>
                <span
                  class="px-1.5 py-0.5 shrink-0 bg-n-slate-3 text-n-slate-11 text-label-small rounded-full"
                >
                  {{
                    doc.scope === 'PERSONAL'
                      ? t('CRM.KNOWLEDGE_DOCS.RECYCLE.SCOPE_PERSONAL')
                      : t('CRM.KNOWLEDGE_DOCS.RECYCLE.SCOPE_COMPANY')
                  }}
                </span>
              </div>
              <div
                class="mt-1.5 flex flex-wrap gap-x-3 gap-y-1 text-xs text-n-slate-11"
              >
                <span>
                  {{ t('CRM.KNOWLEDGE_DOCS.RECYCLE.OWNER') }}:
                  {{ doc.owner_name || '—' }}
                </span>
                <span>
                  {{ t('CRM.KNOWLEDGE_DOCS.RECYCLE.DELETED_BY') }}:
                  {{ doc.discarded_by_name || '—' }}
                </span>
                <span class="tabular-nums">
                  {{ t('CRM.KNOWLEDGE_DOCS.RECYCLE.DELETED_AT') }}:
                  {{ fmtDateTime(doc.discarded_at) }}
                </span>
              </div>
              <div class="flex items-center gap-1.5 mt-2">
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
            </div>
          </div>

          <table class="hidden w-full text-sm md:table">
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
                  <span class="font-medium text-n-slate-12">{{
                    doc.name
                  }}</span>
                  <span
                    class="ml-2 px-1.5 py-0.5 bg-n-slate-3 text-n-slate-11 text-label-small rounded-full"
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
        </template>
      </div>

      <!-- 三级目录浏览器：面包屑 + 子文件夹网格 + 本层文档（搜索时平铺命中）-->
      <div v-else class="flex flex-col flex-1 overflow-hidden">
        <!-- 销售资料根目录已由页标题标识，进入子目录或搜索后再显示路径。 -->
        <div
          v-if="isGeneral || pathStack.length || isSearching"
          class="flex items-center gap-1.5 px-4 py-3 text-sm border-b sm:px-6 border-n-weak min-w-0"
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
            {{ rootLabel }}
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

          <!-- 当前板块负责人：全员可见，方便知道该板块归谁、该找谁 -->
          <div
            v-if="isGeneral && activeSectionManagerNames.length"
            class="flex items-center gap-1 ml-auto shrink-0 text-xs text-n-slate-11"
          >
            <span
              class="i-lucide-user-round-cog size-3.5 text-n-slate-10 shrink-0"
            />
            <span class="text-n-slate-10">负责人：</span>
            <span class="font-medium truncate text-n-slate-12 max-w-[16rem]">
              {{ activeSectionManagerNames.join('、') }}
            </span>
          </div>
        </div>

        <div
          class="relative flex-1 px-4 py-3 overflow-y-auto sm:px-6 sm:py-4"
          @dragover.prevent="onContentDragOver"
          @dragleave="onContentDragLeave"
          @drop.prevent="onContentDrop"
        >
          <!-- 超一次拉取上限提示：显式告知未全部加载，绝不静默吞文档 -->
          <div
            v-if="isTruncated"
            class="flex items-center gap-2 px-3 py-2 mb-3 text-xs border rounded-xl border-n-amber-6 bg-n-amber-3/40 text-n-amber-11"
          >
            <span class="i-lucide-triangle-alert size-4 shrink-0" />
            本板块文档较多（共 {{ totalCount }} 条），当前仅加载最新
            {{ records.length }} 条，其余请用右上角搜索定位。
          </div>

          <!-- 拖拽上传高亮遮罩 -->
          <div
            v-if="isDragging"
            class="absolute inset-3 z-20 flex flex-col items-center justify-center gap-2 border-2 border-dashed pointer-events-none rounded-2xl border-n-iris-8 bg-n-iris-3/70 backdrop-blur-sm"
          >
            <span class="i-lucide-upload-cloud size-8 text-n-iris-11" />
            <span class="text-sm font-medium text-n-iris-11">
              {{ t('CRM.KNOWLEDGE_DOCS.UPLOAD.DROP_HINT') }}
            </span>
          </div>
          <input
            ref="directFileInput"
            type="file"
            multiple
            class="hidden"
            @change="onDirectFiles"
          />
          <!-- 空态 -->
          <div
            v-if="
              isSearching
                ? !currentDocs.length
                : !sortedFolders.length &&
                  !currentDocs.length &&
                  !canAddFolderHere &&
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

          <!-- 文件夹区：顶部工具栏（上传文件 + 新建文件夹并排）；立体玻璃文件夹（原设计）-->
          <div
            v-if="
              !isSearching &&
              (sortedFolders.length || canAddFolderHere || canCreateDocsHere)
            "
          >
            <div
              v-if="canCreateDocsHere || canAddFolderHere"
              class="flex items-center justify-end gap-1.5 h-8 mb-2"
            >
              <button
                v-if="canAddFolderHere"
                type="button"
                class="inline-flex items-center gap-1 px-2 py-1 text-xs font-medium rounded-md text-n-slate-11 hover:bg-n-alpha-2"
                @click="createUnnamedFolder"
              >
                <span class="i-lucide-folder-plus size-3.5" />
                {{ t('CRM.KNOWLEDGE_DOCS.VIEW.ADD_FOLDER') }}
              </button>
              <button
                v-if="canCreateDocsHere"
                type="button"
                :disabled="directUploading"
                class="inline-flex items-center gap-1 px-2 py-1 disabled:opacity-60 text-label-small rounded-xl bg-wintouch-yellow text-wintouch-ink hover:enabled:bg-wintouch-yellow-hover focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-wintouch-ink/50 transition-colors duration-150"
                @click="triggerDirectUpload"
              >
                <span
                  :class="
                    directUploading
                      ? 'i-lucide-loader-2 animate-spin'
                      : 'i-lucide-upload'
                  "
                  class="size-3.5"
                />
                {{
                  directUploading
                    ? t('CRM.KNOWLEDGE_DOCS.UPLOAD.UPLOADING', {
                        done: directProgress.done,
                        total: directProgress.total,
                      })
                    : t('CRM.KNOWLEDGE_DOCS.UPLOAD.BTN')
                }}
              </button>
            </div>

            <div
              v-if="sortedFolders.length"
              class="grid grid-cols-3 gap-2.5 sm:grid-cols-6 xl:grid-cols-8"
            >
              <div
                v-for="folder in sortedFolders"
                :key="folderKeyOf(folder)"
                class="group/folder-style relative"
                @mouseenter="hoveredFolderId = folder.id"
                @mouseleave="hoveredFolderId = null"
              >
                <!-- 重命名内联输入 -->
                <input
                  v-if="editingId === folder.id"
                  :ref="focusRename"
                  v-model="editingName"
                  class="absolute z-10 left-3 right-3 top-1/2 -translate-y-1/2 h-8 px-2 text-sm border rounded-md border-n-iris-8 bg-n-solid-1 text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-8"
                  @keyup.enter="$event.target.blur()"
                  @blur="saveRename"
                  @click.stop
                />
                <!-- 单击直接进入（逐级下钻）-->
                <button
                  type="button"
                  class="relative block w-full text-left transition-transform cursor-pointer"
                  :class="hoveredFolderId === folder.id ? '-translate-y-1' : ''"
                  @click="enterFolder(folder)"
                >
                  <!-- iOS「文件」风立体文件夹：蓝亮前袋 + 粉/白/黄纸扇形探出 + 前袋写名 -->
                  <div v-if="(isGeneral || isMineView) && styleForFolder(folderStyleKey('category', folder.id)).image" class="flex flex-col items-center gap-2 p-2">
                    <CrmFolderArtwork :image="styleForFolder(folderStyleKey('category', folder.id)).image" :animated="styleForFolder(folderStyleKey('category', folder.id)).animated" class="aspect-square w-full rounded-xl" />
                    <div class="w-full min-w-0 text-center">
                      <div class="truncate text-label text-n-slate-12" :title="folder.name">{{ folder.name }}</div>
                      <div class="mt-1 truncate text-label-small text-n-slate-10">
                        {{ t('CRM.KNOWLEDGE_DOCS.VIEW.COUNT', { count: folder.docs.length }) }}
                        <template v-if="folder.childCount"> · {{ t('CRM.KNOWLEDGE_DOCS.VIEW.SUBFOLDERS', { count: folder.childCount }) }}</template>
                        <template v-if="folderBytes(folder)"> · {{ fmtSize(folderBytes(folder)) }}</template>
                      </div>
                    </div>
                  </div>
                  <div v-else class="relative w-full aspect-[8/7]">
                    <div
                      class="absolute left-[11%] right-[11%] top-[17%] bottom-[7%] rounded-[16px] bg-gradient-to-b from-[#5aa6ff] to-[#3f8bf7]"
                    />
                    <div
                      class="absolute left-[21%] top-[15%] h-[41%] w-[25%] origin-bottom-right -rotate-[10deg] rounded-[6px] bg-gradient-to-b from-[#ffd7e1] to-[#f8bacb] shadow-sm"
                    />
                    <div
                      class="absolute right-[21%] top-[15%] h-[41%] w-[25%] origin-bottom-left rotate-[10deg] rounded-[6px] bg-gradient-to-b from-[#ffe9a4] to-[#ffd977] shadow-sm"
                    />
                    <div
                      class="absolute left-1/2 top-[10%] h-[45%] w-[37%] -translate-x-1/2 overflow-hidden rounded-[6px] bg-white shadow-sm"
                    >
                      <div class="mt-[26%] mx-[15%] space-y-[3.5px]">
                        <div
                          v-for="i in 4"
                          :key="i"
                          class="h-[2px] rounded-full bg-n-slate-4"
                          :class="i === 4 ? 'w-1/2' : 'w-full'"
                        />
                      </div>
                    </div>
                    <div
                      class="absolute left-[11%] right-[11%] bottom-[7%] h-[47%] overflow-hidden rounded-[16px] rounded-t-[13px] bg-gradient-to-b from-[#63acff] to-[#4691fb] shadow-[0_10px_20px_-4px_rgba(64,120,230,0.45)]"
                    >
                      <div
                        class="absolute inset-x-0 top-0 h-1/2 bg-gradient-to-b from-white/25 to-transparent"
                      />
                    </div>
                    <div
                      class="absolute left-[16%] right-[13%] bottom-[12%] min-w-0"
                    >
                      <div
                        class="text-[12px] font-bold leading-tight truncate text-white drop-shadow-sm"
                      >
                        {{ folder.name }}
                      </div>
                      <div class="mt-0.5 text-[9px] truncate text-white/85">
                        {{
                          t('CRM.KNOWLEDGE_DOCS.VIEW.COUNT', {
                            count: folder.docs.length,
                          })
                        }}
                        <template v-if="folder.childCount">
                          ·
                          {{
                            t('CRM.KNOWLEDGE_DOCS.VIEW.SUBFOLDERS', {
                              count: folder.childCount,
                            })
                          }}
                        </template>
                        <template v-if="folderBytes(folder)">
                          · {{ fmtSize(folderBytes(folder)) }}
                        </template>
                      </div>
                    </div>
                  </div>
                </button>

                <button
                  v-if="isGeneral || isMineView"
                  type="button"
                  class="absolute left-0 top-0 z-20 flex size-7 items-center justify-center rounded-full border border-n-weak bg-n-solid-1 text-n-slate-11 opacity-100 shadow-sm transition-opacity duration-150 hover:text-n-iris-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-iris-8 [@media(hover:hover)]:opacity-0 [@media(hover:hover)]:group-hover/folder-style:opacity-100 [@media(hover:hover)]:group-focus-within/folder-style:opacity-100 motion-reduce:transition-none"
                  :title="t('CRM.KNOWLEDGE_DOCS.FOLDER_STYLE.FOLDER_TITLE', { name: folder.name })"
                  :aria-label="t('CRM.KNOWLEDGE_DOCS.FOLDER_STYLE.FOLDER_TITLE', { name: folder.name })"
                  @click.stop="folderStylePicker.open({ key: folderStyleKey('category', folder.id), name: folder.name })"
                >
                  <span class="i-lucide-palette size-3.5" aria-hidden="true" />
                </button>

                <!-- 悬停操作：重命名 / 删除（空且无子文件夹才可删）-->
                <div
                  v-show="
                    canManageBoard &&
                    editingId !== folder.id &&
                    hoveredFolderId === folder.id
                  "
                  class="absolute z-20 flex items-center gap-1 top-0 right-0"
                >
                  <button
                    type="button"
                    class="flex items-center justify-center border rounded-full shadow-md size-7 border-n-weak bg-n-solid-1 text-n-slate-12 hover:text-n-iris-11 hover:border-n-iris-8"
                    :title="t('CRM.KNOWLEDGE_DOCS.CATEGORY.RENAME')"
                    @click.stop="startRename(folder)"
                  >
                    <span class="i-lucide-pencil size-4" />
                  </button>
                  <button
                    v-if="!folder.docs.length && !folder.childCount"
                    type="button"
                    class="flex items-center justify-center border rounded-full shadow-md size-7 border-n-weak bg-n-solid-1 text-n-slate-12 hover:text-n-ruby-11 hover:border-n-ruby-8"
                    :title="t('CRM.KNOWLEDGE_DOCS.CATEGORY.DELETE')"
                    @click.stop="removeCategory(folder)"
                  >
                    <span class="i-lucide-trash-2 size-4" />
                  </button>
                </div>
              </div>
            </div>
          </div>

          <!-- 文件区：文件/文档卡片（原设计）；上传入口在顶部工具栏 -->
          <div
            v-if="currentDocs.length"
            :class="
              !isSearching && (sortedFolders.length || canAddFolderHere)
                ? 'mt-6'
                : ''
            "
          >
            <!-- 宫格：图标在上、名称与副行在下，文档与文件同一种形（同手机端文档页）。
                 多附件条目用文件夹图标、副行显示「N 项」；单文件按扩展名出类型图标、副行显示日期。 -->
            <div
              class="grid grid-cols-3 gap-x-3 gap-y-5 sm:grid-cols-4 lg:grid-cols-6 xl:grid-cols-8"
            >
              <div
                v-for="doc in currentDocs"
                :key="doc.id"
                class="relative"
                @mouseenter="hoveredDocId = doc.id"
                @mouseleave="hoveredDocId = null"
              >
                <button
                  type="button"
                  class="flex flex-col items-center w-full gap-1.5 px-1 py-2 text-center transition-colors rounded-xl hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-8"
                  :class="
                    selectedDoc && selectedDoc.id === doc.id
                      ? 'bg-n-alpha-2 ring-1 ring-n-blue-8'
                      : ''
                  "
                  @click="isFileDoc(doc) ? openPreview(doc) : openPanel(doc)"
                >
                  <!-- 多附件条目取第一个附件的类型出图标，右下角挂附件数角标 -->
                  <span class="relative size-[72px] shrink-0">
                    <span
                      v-if="docThumb(doc)"
                      class="grid size-full place-items-center"
                    >
                      <img
                        :src="docThumb(doc)"
                        :alt="doc.name"
                        loading="lazy"
                        class="object-cover rounded-lg shadow-sm size-[78%] ring-1 ring-n-slate-4 bg-n-alpha-1"
                        @error="thumbBroken[doc.id] = true"
                      />
                    </span>
                    <CrmFileIcon
                      v-else
                      class="size-full"
                      :filename="(doc.files || [])[0]?.filename || doc.name"
                    />
                    <span
                      v-if="(doc.files || []).length > 1"
                      class="absolute -bottom-0.5 right-1 inline-flex items-center justify-center min-w-5 h-5 px-1 text-[11px] font-semibold rounded-full ring-2 tabular-nums bg-n-slate-12 text-n-solid-1 ring-n-background"
                    >
                      {{ doc.files.length }}
                    </span>
                  </span>
                  <input
                    v-if="editingDocId === doc.id"
                    :ref="focusRename"
                    v-model="editingDocName"
                    class="w-full h-7 px-1.5 text-sm text-center border rounded border-n-iris-8 bg-n-solid-1 text-n-slate-12 focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-8"
                    @keyup.enter="$event.target.blur()"
                    @blur="saveRenameDoc"
                    @click.stop
                  />
                  <span
                    v-else
                    class="w-full text-sm font-medium leading-5 line-clamp-2 text-n-slate-12"
                  >
                    {{ doc.name }}
                  </span>
                  <span class="w-full text-xs truncate text-n-slate-10">
                    <template v-if="isSearching && doc.category">
                      {{ doc.category }}
                    </template>
                    <template v-else-if="(doc.files || []).length > 1">
                      {{ doc.files.length }} 项
                    </template>
                    <template v-else>{{ fmtDate(doc.updatedAt) }}</template>
                  </span>
                </button>
                <!-- 悬停：改名 / 删除 -->
                <div
                  v-show="
                    canManageDoc(doc) &&
                    editingDocId !== doc.id &&
                    hoveredDocId === doc.id
                  "
                  class="absolute z-20 flex items-center gap-1 top-0 right-0"
                >
                  <button
                    type="button"
                    class="flex items-center justify-center border rounded-full shadow-md size-7 border-n-weak bg-n-solid-1 text-n-slate-12 hover:text-n-iris-11 hover:border-n-iris-8"
                    :title="t('CRM.KNOWLEDGE_DOCS.CATEGORY.RENAME')"
                    @click.stop="startRenameDoc(doc)"
                  >
                    <span class="i-lucide-pencil size-4" />
                  </button>
                  <button
                    type="button"
                    class="flex items-center justify-center border rounded-full shadow-md size-7 border-n-weak bg-n-solid-1 text-n-slate-12 hover:text-n-ruby-11 hover:border-n-ruby-8"
                    :title="t('CRM.KNOWLEDGE_DOCS.CATEGORY.DELETE')"
                    @click.stop="removeDocDirect(doc)"
                  >
                    <span class="i-lucide-trash-2 size-4" />
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- 右侧详情侧边栏 -->
    <aside
      v-if="panelMode"
      class="fixed inset-0 z-40 flex flex-col overflow-hidden border-l md:static md:inset-auto md:z-auto md:w-[420px] md:flex-shrink-0 border-n-weak bg-n-solid-1"
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
                class="px-2 py-0.5 text-label-small rounded-full"
                :class="colorOf(selectedDoc.category)"
              >
                {{
                  selectedDoc.category || t('CRM.KNOWLEDGE_DOCS.UNCATEGORIZED')
                }}
              </span>
              <span
                class="px-2 py-0.5 bg-n-alpha-2 text-n-slate-11 text-label-small rounded-full"
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
                  :href="fileHref(file)"
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
                  v-model="editForm.categoryId"
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

    <!-- 在线预览浮层：视频/图片/PDF/音频直接看，其余提示下载 -->
    <Teleport to="body">
      <div
        v-if="previewDoc"
        class="fixed inset-0 z-[9999] flex items-center justify-center p-4 sm:p-8 bg-black/70 backdrop-blur-sm"
        @click="previewDoc = null"
      >
        <div
          class="relative flex flex-col w-full max-w-5xl max-h-[92vh] overflow-hidden shadow-2xl bg-n-solid-1 rounded-2xl"
          @click.stop
        >
          <div
            class="flex items-center gap-3 px-4 py-3 border-b border-n-weak shrink-0"
          >
            <span
              :class="fileMeta(previewDoc.name).icon"
              class="size-5 shrink-0 text-n-slate-11"
            />
            <span class="text-sm font-medium truncate text-n-slate-12">
              {{ previewDoc.name }}
            </span>
            <button
              type="button"
              class="inline-flex items-center gap-1 px-2.5 py-1 ml-auto text-xs font-medium rounded-md shrink-0 text-n-slate-11 hover:bg-n-alpha-2"
              @click="openDocFile(previewDoc)"
            >
              <span class="i-lucide-download size-3.5" />
              {{ t('CRM.KNOWLEDGE_DOCS.PREVIEW.DOWNLOAD') }}
            </button>
            <button
              type="button"
              class="flex items-center justify-center rounded-md size-7 shrink-0 text-n-slate-11 hover:bg-n-alpha-2"
              @click="previewDoc = null"
            >
              <span class="i-lucide-x size-4" />
            </button>
          </div>
          <div
            class="flex items-center justify-center flex-1 min-h-0 overflow-auto bg-black/5"
          >
            <video
              v-if="previewKind === 'video'"
              :src="previewUrl"
              controls
              autoplay
              class="max-h-[80vh] max-w-full"
            />
            <img
              v-else-if="previewKind === 'image'"
              :src="previewUrl"
              :alt="previewDoc.name"
              class="max-h-[80vh] max-w-full object-contain"
            />
            <iframe
              v-else-if="previewKind === 'pdf'"
              :src="previewPdfUrl"
              class="w-full h-[82vh] border-0"
            />
            <audio
              v-else-if="previewKind === 'audio'"
              :src="previewUrl"
              controls
              class="w-4/5"
            />
            <div
              v-else-if="previewKind === 'excel'"
              class="w-full h-[82vh] overflow-auto bg-n-solid-1 p-3"
            >
              <div
                v-if="previewTooLarge"
                class="flex flex-col items-center gap-3 py-16 text-center"
              >
                <span class="i-lucide-file-question size-10 text-n-slate-9" />
                <p class="text-sm text-n-slate-11">
                  {{ t('CRM.KNOWLEDGE_DOCS.PREVIEW.TOO_LARGE') }}
                </p>
                <button
                  type="button"
                  class="inline-flex items-center gap-1 px-3 py-1.5 text-label-small rounded-xl bg-wintouch-yellow text-wintouch-ink hover:enabled:bg-wintouch-yellow-hover focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-wintouch-ink/50 transition-colors duration-150"
                  @click="openDocFile(previewDoc)"
                >
                  <span class="i-lucide-download size-3.5" />
                  {{ t('CRM.KNOWLEDGE_DOCS.PREVIEW.DOWNLOAD') }}
                </button>
              </div>
              <div
                v-else-if="excelLoading"
                class="flex items-center justify-center h-full text-sm text-n-slate-11"
              >
                <span class="mr-2 i-lucide-loader-2 size-4 animate-spin" />
                {{ t('CRM.KNOWLEDGE_DOCS.PREVIEW.LOADING') }}
              </div>
              <div
                v-else-if="excelHtml"
                class="text-xs text-n-slate-12 [&_table]:border-collapse [&_td]:border [&_td]:border-n-weak [&_td]:px-2 [&_td]:py-1 [&_td]:whitespace-nowrap [&_th]:border [&_th]:border-n-weak [&_th]:px-2 [&_th]:py-1"
                v-html="excelHtml"
              />
              <div
                v-else
                class="flex flex-col items-center gap-3 py-16 text-center"
              >
                <span class="i-lucide-file-question size-10 text-n-slate-9" />
                <p class="text-sm text-n-slate-11">
                  {{ t('CRM.KNOWLEDGE_DOCS.PREVIEW.UNSUPPORTED') }}
                </p>
                <button
                  type="button"
                  class="inline-flex items-center gap-1 px-3 py-1.5 text-label-small rounded-xl bg-wintouch-yellow text-wintouch-ink hover:enabled:bg-wintouch-yellow-hover focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-wintouch-ink/50 transition-colors duration-150"
                  @click="openDocFile(previewDoc)"
                >
                  <span class="i-lucide-download size-3.5" />
                  {{ t('CRM.KNOWLEDGE_DOCS.PREVIEW.DOWNLOAD') }}
                </button>
              </div>
            </div>
            <div
              v-else-if="previewKind === 'word'"
              class="w-full h-[82vh] overflow-auto bg-n-solid-1 p-6"
            >
              <div
                v-if="previewTooLarge"
                class="flex flex-col items-center gap-3 py-16 text-center"
              >
                <span class="i-lucide-file-question size-10 text-n-slate-9" />
                <p class="text-sm text-n-slate-11">
                  {{ t('CRM.KNOWLEDGE_DOCS.PREVIEW.TOO_LARGE') }}
                </p>
                <button
                  type="button"
                  class="inline-flex items-center gap-1 px-3 py-1.5 text-label-small rounded-xl bg-wintouch-yellow text-wintouch-ink hover:enabled:bg-wintouch-yellow-hover focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-wintouch-ink/50 transition-colors duration-150"
                  @click="openDocFile(previewDoc)"
                >
                  <span class="i-lucide-download size-3.5" />
                  {{ t('CRM.KNOWLEDGE_DOCS.PREVIEW.DOWNLOAD') }}
                </button>
              </div>
              <div
                v-else-if="wordLoading"
                class="flex items-center justify-center h-full text-sm text-n-slate-11"
              >
                <span class="mr-2 i-lucide-loader-2 size-4 animate-spin" />
                {{ t('CRM.KNOWLEDGE_DOCS.PREVIEW.LOADING') }}
              </div>
              <div
                v-else-if="wordHtml"
                class="mx-auto prose-sm prose max-w-3xl text-n-slate-12 prose-td:border prose-td:border-n-weak prose-td:px-2 prose-th:border prose-th:border-n-weak prose-th:px-2"
                v-html="wordHtml"
              />
              <div
                v-else
                class="flex flex-col items-center gap-3 py-16 text-center"
              >
                <span class="i-lucide-file-question size-10 text-n-slate-9" />
                <p class="text-sm text-n-slate-11">
                  {{ t('CRM.KNOWLEDGE_DOCS.PREVIEW.UNSUPPORTED') }}
                </p>
                <button
                  type="button"
                  class="inline-flex items-center gap-1 px-3 py-1.5 text-label-small rounded-xl bg-wintouch-yellow text-wintouch-ink hover:enabled:bg-wintouch-yellow-hover focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-wintouch-ink/50 transition-colors duration-150"
                  @click="openDocFile(previewDoc)"
                >
                  <span class="i-lucide-download size-3.5" />
                  {{ t('CRM.KNOWLEDGE_DOCS.PREVIEW.DOWNLOAD') }}
                </button>
              </div>
            </div>
            <div
              v-else
              class="flex flex-col items-center gap-3 px-6 py-16 text-center"
            >
              <span class="i-lucide-file-question size-10 text-n-slate-9" />
              <p class="text-sm text-n-slate-11">
                {{ t('CRM.KNOWLEDGE_DOCS.PREVIEW.UNSUPPORTED') }}
              </p>
              <button
                type="button"
                class="inline-flex items-center gap-1 px-3 py-1.5 text-label-small rounded-xl bg-wintouch-yellow text-wintouch-ink hover:enabled:bg-wintouch-yellow-hover focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-wintouch-ink/50 transition-colors duration-150"
                @click="openDocFile(previewDoc)"
              >
                <span class="i-lucide-download size-3.5" />
                {{ t('CRM.KNOWLEDGE_DOCS.PREVIEW.DOWNLOAD') }}
              </button>
            </div>
          </div>
        </div>
      </div>
    </Teleport>

    <CrmFolderStylePicker v-if="isGeneral || isMineView" ref="folderStylePicker" />

    <CrmDocSectionManager
      :show="showSectionManager"
      @close="showSectionManager = false"
      @updated="onSectionsUpdated"
    />
  </div>
</template>
