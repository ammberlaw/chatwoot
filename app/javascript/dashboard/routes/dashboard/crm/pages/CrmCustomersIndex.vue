<script setup>
/* global axios */
import { ref, computed, onMounted, onBeforeUnmount, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCrmCustomersStore } from 'dashboard/stores/crm/customers';
import { useCrmRole } from 'dashboard/composables/useCrmRole';
import { useMapGetter } from 'dashboard/composables/store';
import { useCrmComposeStore } from 'dashboard/stores/crm/compose';
import CrmAgentAPI from 'dashboard/api/crm/crmAgents';

import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import CrmCustomerCreateDialog from 'dashboard/components-next/CRM/CrmCustomerCreateDialog.vue';
import CrmCustomerImportDialog from 'dashboard/components-next/CRM/CrmCustomerImportDialog.vue';
import { COUNTRY_LABELS } from 'dashboard/routes/dashboard/crm/constants/countries';
import { COUNTRY_TZ } from 'dashboard/routes/dashboard/crm/helper/scheduleTimezone';
import { useCrmOptions } from 'dashboard/composables/useCrmOptions';
import { isClassicTheme } from 'dashboard/components-next/CRM/charts/chartColors';
import CustomerAPI from 'dashboard/api/crm/customers';

// 经典灰专属：资料完善度进度条改金黄；其它主题保持原样。切主题需刷新。
const isClassic = ref(isClassicTheme());

// 特别关注（每人各标）：乐观切换爱心 → 调收藏/取消接口，失败回滚。
const toggleFavorite = async customer => {
  const next = !customer.favorited;
  customer.favorited = next;
  try {
    if (next) await CustomerAPI.favorite(customer.id);
    else await CustomerAPI.unfavorite(customer.id);
  } catch (e) {
    customer.favorited = !next;
    useAlert(e?.response?.data?.error || '操作失败');
  }
};

// 每页条数（默认 15，与后端 RESULTS_PER_PAGE 一致；后端上限 200）。
const PAGE_SIZE_OPTIONS = [15, 30, 50, 100];
const pageSizeOptions = PAGE_SIZE_OPTIONS.map(s => ({ value: s, label: String(s) }));
const pageSize = ref(15);

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { accountId, accountScopedRoute } = useAccount();
const { isCrmSales, isCrmManager, isAdmin, isCrmDeputyAdmin } = useCrmRole();
const currentUserForFilter = useMapGetter('getCurrentUser');
const customersStore = useCrmCustomersStore();

const actingId = ref(null);

const createDialogRef = ref(null);

// 批量导入：仅管理员/副管理员/主管可见；导入完成后刷新列表。
const importDialogRef = ref(null);
const canImport = computed(
  () => isAdmin.value || isCrmDeputyAdmin.value || isCrmManager.value
);
const importMemberOptions = computed(() =>
  allAgentsForAssign.value.map(a => ({ value: String(a.id), label: a.name }))
);
// 私海(private)/公海(public_pool) 由侧边栏入口经 ?filter= 驱动；默认私海。
const activeFilter = ref(route.query.filter || 'private');
const activeCustomerGroup = ref('');
const activeProductGroup = ref('');
const activeSourceChannel = ref('');
// 只看特别关注（每人各标）。
const favoritesOnly = ref(false);
const toggleFavoritesOnly = () => {
  favoritesOnly.value = !favoritesOnly.value;
  currentPage.value = 1;
  fetchCustomers();
};
const activeStatus = ref('');
const activeLevel = ref('');
const currentPage = ref(1);
const sortKey = ref(''); // '' = 默认(更新时间倒序)；'deal_amount' = 累计成交额
const sortDir = ref('desc');
// 支持 ?q= 深链（客户查重页跳转定位用）
const searchQuery = ref(route.query.q || '');
const teams = ref([]);
const selectedTeamId = ref('');
const selectedOwnerId = ref('');

const customers = computed(() => customersStore.getCustomers);
const uiFlags = computed(() => customersStore.getUIFlags);
const isFetching = computed(() => uiFlags.value.fetchingList);
const isCreating = computed(() => uiFlags.value.creatingItem);
const totalCount = computed(() => customersStore.getMeta.count || 0);
// 自绘页脚分页（还原效果图）：页多时窗口化（首页 … 当前±1 … 末页）。
const totalPages = computed(() =>
  Math.max(1, Math.ceil(totalCount.value / pageSize.value))
);
const pageList = computed(() => {
  const total = totalPages.value;
  const cur = currentPage.value;
  if (total <= 7) return Array.from({ length: total }, (_, i) => i + 1);
  const wanted = [1, total, cur, cur - 1, cur + 1].filter(
    p => p >= 1 && p <= total
  );
  const sorted = [...new Set(wanted)].sort((a, b) => a - b);
  const result = [];
  let prev = 0;
  sorted.forEach(p => {
    if (p - prev > 1) result.push('…');
    result.push(p);
    prev = p;
  });
  return result;
});

// 客户分组 / 客户来源：从「客户设置」动态读取（含二级），全站下拉与标签共享缓存。
const { ensureLoaded, groupOptions, sourceOptions, groupLabel, sourceLabel } =
  useCrmOptions();

// 客户分组下拉（空值 = 全部）
const customerGroupOptions = computed(() => [
  { value: '', label: t('CRM.CUSTOMERS.FILTERS.ALL_CUSTOMER_GROUP') },
  ...groupOptions.value,
]);
const productGroupOptions = [
  { value: '', label: t('CRM.CUSTOMERS.FILTERS.ALL_PRODUCT_GROUP') },
  { value: 'TABLET', label: '平板电脑' },
  { value: 'COMMERCIAL_DISPLAY', label: '商显工控' },
];
// 客户来源下拉（空值 = 全部）
const sourceChannelOptions = computed(() => [
  { value: '', label: t('CRM.CUSTOMERS.FILTERS.ALL_SOURCE_CHANNEL') },
  ...sourceOptions.value,
]);
// 客户状态 / 客户等级下拉（空值 = 全部）；状态标签取 STATUS_META（getter 惰性，无 TDZ）。
const statusFilterOptions = computed(() => [
  { value: '', label: '状态 全部' },
  ...Object.entries(STATUS_META).map(([value, m]) => ({
    value,
    label: m.label,
  })),
]);
const levelFilterOptions = [
  { value: '', label: '等级 全部' },
  ...['A', 'B', 'C', 'D'].map(v => ({ value: v, label: `${v} 级` })),
];

// 部门主管：不筛团队，直接筛自己团队的业务员（本人 + 下属，成员接口已按辖区收口）。
const teamMembers = ref([]);
const fetchTeamMembers = async () => {
  try {
    const { data } = await CrmAgentAPI.get(accountId.value, 'team');
    teamMembers.value = data.payload || [];
  } catch {
    teamMembers.value = [];
  }
};
const managerOwnerOptions = computed(() => {
  const me = currentUserForFilter.value || {};
  const rows = teamMembers.value.filter(m => m.user_id !== me.id);
  return [
    { value: '', label: '全部业务员' },
    { value: String(me.id), label: `${me.name}（我）` },
    ...rows.map(m => ({ value: String(m.user_id), label: m.name })),
  ];
});

// 部门主管私海双视图：我的客户(mine) / 团队客户(private 全辖区)
const managerView = ref('team');
const isManagerTeamView = computed(
  () =>
    isCrmManager.value &&
    activeFilter.value === 'private' &&
    managerView.value === 'team'
);

// 列表与概览卡共用的筛选口径（视图/分组/来源/状态/等级/搜索/团队/业务员）。
const currentFilterParams = () => {
  let filter = activeFilter.value === 'all' ? undefined : activeFilter.value;
  if (
    isCrmManager.value &&
    filter === 'private' &&
    managerView.value === 'mine'
  ) {
    filter = 'mine';
  }
  return {
    filter,
    customer_group: activeCustomerGroup.value || undefined,
    product_group: activeProductGroup.value || undefined,
    source_channel: activeSourceChannel.value || undefined,
    favorited_only: favoritesOnly.value ? 1 : undefined,
    status: activeStatus.value || undefined,
    customer_level: activeLevel.value || undefined,
    q: searchQuery.value.trim() || undefined,
    team_id: selectedTeamId.value || undefined,
    account_owner_id: selectedOwnerId.value || undefined,
  };
};

// 顶部概览卡：我的客户 / 本月新增 / 在谈商机 / 有成交订单（随筛选联动）。
const stats = ref({
  customers: 0,
  newThisMonth: 0,
  openOpportunities: 0,
  withOrders: 0,
});
const fetchStats = async () => {
  try {
    const { data } = await CustomerAPI.stats(currentFilterParams());
    stats.value = {
      customers: data.customers || 0,
      newThisMonth: data.new_this_month || 0,
      openOpportunities: data.open_opportunities || 0,
      withOrders: data.with_orders || 0,
    };
  } catch (e) {
    // 概览卡取数失败不阻塞列表
  }
};

// 概览卡展示配置（值来自 stats，配色随主题令牌）。
const statCards = computed(() => [
  {
    key: 'customers',
    label: isManagerTeamView.value ? '团队客户' : '我的客户',
    value: stats.value.customers,
    icon: 'i-lucide-users',
    tile: 'bg-n-amber-3 text-n-amber-11',
  },
  {
    key: 'new',
    label: '本月新增',
    value: stats.value.newThisMonth,
    icon: 'i-lucide-user-plus',
    tile: 'bg-n-slate-4 text-n-slate-12',
  },
  {
    key: 'opps',
    label: '在谈商机',
    value: stats.value.openOpportunities,
    icon: 'i-lucide-target',
    tile: 'bg-n-blue-3 text-n-blue-11',
  },
  {
    key: 'orders',
    label: '有成交订单',
    value: stats.value.withOrders,
    icon: 'i-lucide-package',
    tile: 'bg-n-teal-3 text-n-teal-11',
  },
]);

const fetchCustomers = () => {
  fetchStats();
  return customersStore.get({
    page: currentPage.value,
    per_page: pageSize.value,
    ...currentFilterParams(),
    sort: sortKey.value || undefined,
    direction: sortKey.value ? sortDir.value : undefined,
  });
};

// —— 勾选批量转移（主管团队视图）——
const selectedIds = ref([]);

const setManagerView = view => {
  managerView.value = view;
  selectedIds.value = [];
  currentPage.value = 1;
  fetchCustomers();
};
const reassignTargetId = ref('');
const reassigning = ref(false);
const toggleSelect = id => {
  selectedIds.value = selectedIds.value.includes(id)
    ? selectedIds.value.filter(x => x !== id)
    : [...selectedIds.value, id];
};
const allSelected = computed(
  () =>
    customers.value.length > 0 &&
    customers.value.every(c => selectedIds.value.includes(c.id))
);
const toggleSelectAll = () => {
  selectedIds.value = allSelected.value ? [] : customers.value.map(c => c.id);
};
const reassignTargetOptions = computed(() => [
  { value: '', label: '分配给…' },
  ...managerOwnerOptions.value.filter(o => o.value),
]);

// 任何 CRM 角色都可勾选分配自己的私海客户；主管团队视图还可分配团队成员的客户；
// 超管/管理员可跨全辖区批量转移私海客户（含商机/订单/报价/邮件级联）。
const canSelectRows = computed(
  () =>
    activeFilter.value === 'private' &&
    (isCrmSales.value ||
      isCrmManager.value ||
      isAdmin.value ||
      isCrmDeputyAdmin.value)
);

// 分配目标：团队视图限本团队；「我的客户」/业务员视图可分配给任意成员。
const allAgentsForAssign = ref([]);
const fetchAllAgentsForAssign = async () => {
  try {
    // 分配/转移目标：可指派给任意 CRM 成员（scope=all，不按可见范围收），但只列 CRM 成员。
    const { data } = await CrmAgentAPI.get(accountId.value, 'all');
    allAgentsForAssign.value = data.payload || [];
  } catch {
    allAgentsForAssign.value = [];
  }
};
const assignTargetOptions = computed(() => {
  if (isManagerTeamView.value) return reassignTargetOptions.value;
  const me = currentUserForFilter.value || {};
  return [
    { value: '', label: '分配给…' },
    ...allAgentsForAssign.value
      .filter(a => a.id !== me.id)
      .map(a => ({ value: String(a.id), label: a.name })),
  ];
});
const reassignSelected = async () => {
  if (!reassignTargetId.value || !selectedIds.value.length) return;
  reassigning.value = true;
  try {
    await axios.post(
      `/api/v1/accounts/${accountId.value}/crm/customers/reassign`,
      { ids: selectedIds.value, owner_id: Number(reassignTargetId.value) }
    );
    useAlert(`已分配 ${selectedIds.value.length} 个客户`);
    selectedIds.value = [];
    reassignTargetId.value = '';
    fetchCustomers();
  } catch (e) {
    useAlert(e?.response?.data?.error || '分配失败');
  } finally {
    reassigning.value = false;
  }
};

// 客户名搜索（300ms 防抖）
let searchTimer = null;
const onSearchInput = () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => {
    currentPage.value = 1;
    fetchCustomers();
  }, 300);
};

// admin 团队 → 业务员逐级筛选
const teamOptions = computed(() => [
  { value: '', label: '团队 全部' },
  ...teams.value.map(tm => ({ value: String(tm.id), label: tm.name })),
]);
const ownerOptions = computed(() => {
  const team = teams.value.find(tm => String(tm.id) === selectedTeamId.value);
  return [
    { value: '', label: '全部业务员' },
    ...(team?.members || []).map(m => ({ value: String(m.id), label: m.name })),
  ];
});
const fetchTeams = async () => {
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/crm/teams`
    );
    teams.value = data.payload || [];
  } catch {
    teams.value = [];
  }
};
const setTeam = val => {
  selectedTeamId.value = val;
  selectedOwnerId.value = '';
  currentPage.value = 1;
  fetchCustomers();
};
const setOwner = val => {
  selectedOwnerId.value = val;
  currentPage.value = 1;
  fetchCustomers();
};

// 表头点击排序：同列 desc → asc → 取消；换列从 desc 起。
const toggleSort = key => {
  if (sortKey.value !== key) {
    sortKey.value = key;
    sortDir.value = 'desc';
  } else if (sortDir.value === 'desc') {
    sortDir.value = 'asc';
  } else {
    sortKey.value = '';
    sortDir.value = 'desc';
  }
  currentPage.value = 1;
  fetchCustomers();
};
const sortIcon = key => {
  if (sortKey.value !== key) return 'i-lucide-chevrons-up-down opacity-40';
  return sortDir.value === 'asc' ? 'i-lucide-arrow-up' : 'i-lucide-arrow-down';
};

const setCustomerGroup = value => {
  activeCustomerGroup.value = value;
  currentPage.value = 1;
  fetchCustomers();
};

const setProductGroup = value => {
  activeProductGroup.value = value;
  currentPage.value = 1;
  fetchCustomers();
};

const setSourceChannel = value => {
  activeSourceChannel.value = value;
  currentPage.value = 1;
  fetchCustomers();
};

const setStatus = value => {
  activeStatus.value = value;
  currentPage.value = 1;
  fetchCustomers();
};

const setLevel = value => {
  activeLevel.value = value;
  currentPage.value = 1;
  fetchCustomers();
};

const onPageChange = page => {
  currentPage.value = page;
  fetchCustomers();
};

// 切每页条数：回到第 1 页重新取数。
const setPageSize = size => {
  pageSize.value = Number(size);
  currentPage.value = 1;
  fetchCustomers();
};

// 新建统一走「客户建档」引导页(带查重 + 自动归私海)；弹窗只用于编辑。
const goToIntake = () =>
  router.push(accountScopedRoute('crm_customer_intake_index'));
const openEditDialog = record => createDialogRef.value?.open(record);

// 右侧详情面板：点行选中展开，编辑仍走弹窗。
const selectedCustomer = ref(null);

// 面板内「下次跟进 + 加入日程」——不用点进详情页。
const nextDate = ref('');
const nextTime = ref('09:00');
const addToSchedule = ref(true);
const savingNext = ref(false);
const pad2 = n => String(n).padStart(2, '0');
const timeOptions = (() => {
  const out = [];
  for (let h = 0; h < 24; h += 1) {
    ['00', '30'].forEach(mm =>
      out.push({ value: `${pad2(h)}:${mm}`, label: `${pad2(h)}:${mm}` })
    );
  }
  return out;
})();
watch(selectedCustomer, c => {
  if (c?.next_follow_up_at) {
    nextDate.value = c.next_follow_up_at.slice(0, 10);
    nextTime.value = c.next_follow_up_at.slice(11, 16) || '09:00';
  } else {
    nextDate.value = '';
    nextTime.value = '09:00';
  }
});
const saveNextFollowUp = async () => {
  if (!selectedCustomer.value || !nextDate.value) {
    useAlert('请选择下次跟进日期');
    return;
  }
  const startAt = `${nextDate.value}T${nextTime.value}:00`;
  savingNext.value = true;
  try {
    await axios.post(
      `${crmBase()}/customers/${selectedCustomer.value.id}/schedule_follow_up`,
      { next_follow_up_at: startAt, add_to_schedule: addToSchedule.value }
    );
    selectedCustomer.value.next_follow_up_at = startAt;
    useAlert(addToSchedule.value ? '下次跟进已保存并加入日程' : '下次跟进已保存');
  } catch {
    useAlert('保存失败');
  } finally {
    savingNext.value = false;
  }
};
const PANEL_TABS = [
  { key: 'fields', label: '主页', icon: 'i-lucide-house' },
  { key: 'timeline', label: '操作历史', icon: 'i-lucide-history' },
  { key: 'notes', label: '备注', icon: 'i-lucide-file-text' },
  { key: 'files', label: '文件', icon: 'i-lucide-paperclip' },
  { key: 'emails', label: '电子邮件', icon: 'i-lucide-mail' },
];
const activeTab = ref('fields');
const panelNotes = ref([]);
const panelEmails = ref([]);
const panelAudits = ref([]);
const panelContacts = ref([]);

// 审计字段 → 中文标签（用于「操作历史」文案）
const AUDIT_LABELS = {
  name: '公司名',
  customer_code: '客户编码',
  website: '官网',
  customer_status: '客户状态',
  customer_level: '客户级别',
  customer_group: '客户分组',
  product_group: '产品分组',
  source_channel: '客户来源',
  trade_country: '国家地区',
  trade_region: '贸易区域',
  primary_contact_name: '主要联系人',
  contact_job_title: '职位',
  contact_email: '联系邮箱',
  contact_phone: '联系电话',
  whats_app: 'WhatsApp',
  wechat: '微信',
  linkedin: 'LinkedIn',
  address: '地址',
  contact_preference: '联系偏好',
  customer_remark: '备注',
};
const auditMessage = a => {
  const who = a.user_name;
  if (a.action === 'create') return `${who} 创建了客户`;
  if (a.action === 'destroy') return `${who} 删除了客户`;
  const fields = (a.changed_fields || []).filter(
    f => f !== 'account_owner_id' && f !== 'is_in_public_pool'
  );
  const parts = [];
  if ((a.changed_fields || []).includes('account_owner_id'))
    parts.push('重新分配了客户');
  if ((a.changed_fields || []).includes('is_in_public_pool'))
    parts.push('变更了公海/私海归属');
  if (fields.length)
    parts.push(
      `编辑了客户信息 ${fields.map(f => AUDIT_LABELS[f] || f).join('、')}`
    );
  return `${who} ${parts.join('，') || '更新了客户'}`;
};
const newNote = ref('');
const tabLoading = ref(false);

const crmBase = () => `/api/v1/accounts/${accountId.value}/crm`;

const fetchNotes = async () => {
  const { data } = await axios.get(`${crmBase()}/follow_up_notes`, {
    params: { customer_id: selectedCustomer.value.id },
  });
  panelNotes.value = data.payload || [];
};
const fetchEmails = async () => {
  const { data } = await axios.get(`${crmBase()}/emails`, {
    params: { customer_id: selectedCustomer.value.id },
  });
  panelEmails.value = data.payload || [];
};
const fetchAudits = async () => {
  const { data } = await axios.get(
    `${crmBase()}/customers/${selectedCustomer.value.id}/audits`
  );
  panelAudits.value = data.payload || [];
};
const fetchContacts = async () => {
  const { data } = await axios.get(`${crmBase()}/contacts`, {
    params: { customer_id: selectedCustomer.value.id },
  });
  panelContacts.value = data.payload || [];
};

const setTab = async key => {
  activeTab.value = key;
  if (!selectedCustomer.value) return;
  tabLoading.value = true;
  try {
    if (key === 'notes') await fetchNotes();
    else if (key === 'emails') await fetchEmails();
    else if (key === 'timeline') await fetchAudits();
  } catch {
    /* 忽略：面板内容加载失败留空 */
  } finally {
    tabLoading.value = false;
  }
};

const selectCustomer = customer => {
  selectedCustomer.value = customer;
  activeTab.value = 'fields';
  panelNotes.value = [];
  panelEmails.value = [];
  panelAudits.value = [];
  panelContacts.value = [];
  newNote.value = '';
  // 字段是默认 tab，其他联系人随详情直接展示，故进面板即拉取。
  fetchContacts().catch(() => {
    panelContacts.value = [];
  });
};
const closePanel = () => {
  selectedCustomer.value = null;
};
// 跳转到客户全页详情。
const openDetailPage = () => {
  if (!selectedCustomer.value) return;
  router.push({
    name: 'crm_customer_detail_index',
    params: { accountId: accountId.value, id: selectedCustomer.value.id },
  });
};

const addNote = async () => {
  const title = newNote.value.trim();
  if (!title || !selectedCustomer.value) return;
  await axios.post(`${crmBase()}/follow_up_notes`, {
    note: { title, crm_customer_id: selectedCustomer.value.id },
  });
  newNote.value = '';
  fetchNotes();
};
// 文件上传/删除后重取列表并重新定位选中客户（保证 files 为最新 camelCase）。
const resyncSelected = async () => {
  const id = selectedCustomer.value?.id;
  await fetchCustomers();
  const found = customers.value.find(c => c.id === id);
  if (found) selectedCustomer.value = found;
};
const uploadFiles = async event => {
  const files = Array.from(event.target.files || []);
  event.target.value = '';
  if (!files.length || !selectedCustomer.value) return;
  const fd = new FormData();
  files.forEach(f => fd.append('files[]', f));
  tabLoading.value = true;
  try {
    await axios.post(
      `${crmBase()}/customers/${selectedCustomer.value.id}/attach`,
      fd,
      { headers: { 'Content-Type': 'multipart/form-data' } }
    );
    await resyncSelected();
  } finally {
    tabLoading.value = false;
  }
};
const removeFile = async fileId => {
  await axios.delete(
    `${crmBase()}/customers/${selectedCustomer.value.id}/attach/${fileId}`
  );
  resyncSelected();
};

const fmtDateTime = v => (v ? new Date(v).toLocaleString() : '');
const fmtBytes = n => {
  if (!n) return '';
  if (n < 1024) return `${n} B`;
  if (n < 1_048_576) return `${(n / 1024).toFixed(0)} KB`;
  return `${(n / 1_048_576).toFixed(1)} MB`;
};

const editSelected = () =>
  selectedCustomer.value && openEditDialog(selectedCustomer.value);

const updateCustomer = async customer => {
  try {
    await customersStore.update(customer);
    createDialogRef.value?.onSuccess();
    useAlert(t('CRM.CUSTOMERS.EDIT.SUCCESS'));
    const updated = customers.value.find(x => x.id === customer.id);
    if (updated) selectedCustomer.value = updated;
  } catch {
    useAlert(t('CRM.CUSTOMERS.EDIT.ERROR'));
  }
};

// ── 行内单元格：悬停复制 + 铅笔就地编辑（公司名称/主要联系人/邮箱）──
const vFocus = { mounted: el => el.focus() };
const editingCell = ref(null); // { id, field }
const editingValue = ref('');
const savingCell = ref(false);

const isEditingCell = (customer, field) =>
  editingCell.value?.id === customer.id && editingCell.value?.field === field;

const startCellEdit = (customer, field) => {
  editingCell.value = { id: customer.id, field };
  editingValue.value = customer[field] || '';
};
const cancelCellEdit = () => {
  editingCell.value = null;
  editingValue.value = '';
};

const saveCellEdit = async customer => {
  const cell = editingCell.value;
  if (!cell || savingCell.value) return;
  const { field } = cell;
  const next = editingValue.value.trim();
  if (next === (customer[field] || '')) {
    cancelCellEdit();
    return;
  }
  savingCell.value = true;
  try {
    const updated = await customersStore.update({
      id: customer.id,
      [field]: next,
    });
    if (selectedCustomer.value?.id === customer.id)
      selectedCustomer.value = updated;
    useAlert('已保存');
  } catch {
    useAlert('保存失败');
  } finally {
    savingCell.value = false;
    // 保存期间若已切到别的格子就别清空，避免误关新编辑
    if (isEditingCell(customer, field)) cancelCellEdit();
  }
};

// HTTP 环境（生产 IP 直连无 HTTPS）没有 navigator.clipboard，退回 execCommand 复制。
const copyCell = async value => {
  const text = String(value ?? '').trim();
  if (!text) return;
  try {
    if (navigator.clipboard) {
      await navigator.clipboard.writeText(text);
    } else {
      const holder = document.createElement('textarea');
      holder.value = text;
      holder.setAttribute('readonly', '');
      holder.style.position = 'fixed';
      holder.style.opacity = '0';
      document.body.appendChild(holder);
      holder.select();
      const ok = document.execCommand('copy');
      holder.remove();
      if (!ok) throw new Error('copy unsupported');
    }
    useAlert('已复制');
  } catch {
    useAlert('复制失败');
  }
};

const crmApi = () => `/api/v1/accounts/${accountId.value}/crm/customers`;

// 认领：公海客户归我私海；转公海：私海客户放回公海。行按钮，阻止冒泡避免触发编辑。
const claimCustomer = async customer => {
  actingId.value = customer.id;
  try {
    await axios.post(`${crmApi()}/${customer.id}/claim`);
    useAlert(t('CRM.CUSTOMERS.POOL.CLAIM_SUCCESS'));
    if (selectedCustomer.value?.id === customer.id) closePanel();
    fetchCustomers();
  } catch (e) {
    useAlert(e.response?.data?.message || t('CRM.CUSTOMERS.POOL.CLAIM_ERROR'));
  } finally {
    actingId.value = null;
  }
};

const releaseCustomer = async customer => {
  const { name } = customer;
  // eslint-disable-next-line no-alert
  const ok = window.confirm(t('CRM.CUSTOMERS.POOL.RELEASE_CONFIRM', { name }));
  if (!ok) return;
  actingId.value = customer.id;
  try {
    await axios.post(`${crmApi()}/${customer.id}/release`);
    useAlert(t('CRM.CUSTOMERS.POOL.RELEASE_SUCCESS'));
    if (selectedCustomer.value?.id === customer.id) closePanel();
    fetchCustomers();
  } catch (e) {
    useAlert(
      e.response?.data?.message || t('CRM.CUSTOMERS.POOL.RELEASE_ERROR')
    );
  } finally {
    actingId.value = null;
  }
};

// —— 行操作菜单 ——
const composeStore = useCrmComposeStore();
const openMenuId = ref(null);

// 时区列：按客户国家取当地当前时间 + UTC 偏移（如 08:42 UTC+0），每分钟刷新。
const now = ref(new Date());
let clockTimer = null;
const customerTime = customer => {
  const tz = COUNTRY_TZ[customer.tradeCountry];
  if (!tz) return '';
  try {
    const time = new Intl.DateTimeFormat('en-GB', {
      timeZone: tz,
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    }).format(now.value);
    const off =
      new Intl.DateTimeFormat('en-US', {
        timeZone: tz,
        timeZoneName: 'shortOffset',
      })
        .formatToParts(now.value)
        .find(p => p.type === 'timeZoneName')?.value || 'GMT';
    const utc = off === 'GMT' ? 'UTC+0' : off.replace('GMT', 'UTC');
    return `${time} ${utc}`;
  } catch {
    return '';
  }
};
// 行操作菜单 Teleport 到 body（避开表格横向滚动容器裁剪），按按钮位置定位。
const menuAnchor = ref({ top: 0, left: 0 });
const menuCustomer = computed(
  () => customers.value.find(c => c.id === openMenuId.value) || null
);
const toggleRowMenu = (id, event) => {
  if (openMenuId.value === id) {
    openMenuId.value = null;
    return;
  }
  const r = event.currentTarget.getBoundingClientRect();
  menuAnchor.value = { top: r.bottom + 4, left: r.right - 148 };
  openMenuId.value = id;
};

// 写邮件：常驻写信窗，带客户预填（自动带出联系人/收件人）。
const writeEmail = customer => {
  openMenuId.value = null;
  composeStore.open({
    customer: {
      id: customer.id,
      name: customer.name,
      tradeCountry: customer.tradeCountry,
    },
    // 点客户邮箱写信时，直接把该邮箱预填为收件人。
    toAddress: customer.contactEmail || undefined,
  });
};

// 客户往来邮件里直接回复：带出对方地址 + 原邮件引用，复用写信窗。
const replyPanelEmail = e => {
  const isSent = e.folder === 'SENT';
  const to = isSent ? e.to_address : e.from_address;
  const quote = `\n\n------ 原邮件 ------\n发件人：${e.from_address || '—'}\n时间：${fmtDateTime(
    e.email_date || e.created_at
  )}\n主题：${e.subject || '(无主题)'}\n\n${e.body || ''}`;
  composeStore.open({
    toAddress: to || '',
    subject: e.subject?.startsWith('Re:')
      ? e.subject
      : `Re: ${e.subject || ''}`,
    body: quote,
    crmCustomerId: e.crm_customer_id || selectedCustomer.value?.id || null,
    contactId: e.contact_id || null,
    focusReplyTop: true,
  });
};

// 群发单显：勾选多个客户 → 打开写信窗群发（每人各收一封独立邮件，互不可见）。
const bulkSendSelected = () => {
  const recipients = customers.value
    .filter(c => selectedIds.value.includes(c.id))
    .map(c => ({
      email: c.contactEmail,
      crmCustomerId: c.id,
      contactId: c.contactId || null,
      name: c.name,
    }))
    .filter(r => r.email);
  if (!recipients.length) {
    useAlert('勾选的客户都没有邮箱，无法群发');
    return;
  }
  composeStore.open({ bulkRecipients: recipients });
};

// 目标客户（分组/转移/共享 弹窗共用）
const rowTarget = ref(null);
const moveGroupDialogRef = ref(null);
const transferDialogRef = ref(null);
const shareDialogRef = ref(null);
const moveGroupValue = ref('');
const transferValue = ref('');
const shareUserIds = ref([]);

const moveGroupOptions = computed(() => [
  { value: '', label: '不分组' },
  ...groupOptions.value,
]);
const openMoveGroup = customer => {
  openMenuId.value = null;
  rowTarget.value = customer;
  moveGroupValue.value = customer.customerGroup || '';
  moveGroupDialogRef.value?.open();
};
const saveMoveGroup = async () => {
  try {
    await axios.patch(`${crmApi()}/${rowTarget.value.id}`, {
      customer: { customer_group: moveGroupValue.value || null },
    });
    useAlert('已移动分组');
    fetchCustomers();
  } catch {
    useAlert('操作失败');
  }
};

const ensureAgents = async () => {
  if (!allAgentsForAssign.value.length) await fetchAllAgentsForAssign();
};
const transferOptions = computed(() => [
  { value: '', label: '选择业务员…' },
  ...allAgentsForAssign.value
    .filter(a => a.id !== rowTarget.value?.accountOwnerId)
    .map(a => ({ value: String(a.id), label: a.name })),
]);
// 级联项：转移客户时是否把商机/订单/邮件一并转给新负责人（默认全带）。
const transferCascade = ref({
  opportunities: true,
  orders: true,
  emails: true,
});
const transferTitle = computed(() =>
  rowTarget.value ? `将【${rowTarget.value.name}】转移给` : '转移给'
);
const openTransfer = async customer => {
  openMenuId.value = null;
  rowTarget.value = customer;
  transferValue.value = '';
  transferCascade.value = { opportunities: true, orders: true, emails: true };
  await ensureAgents();
  transferDialogRef.value?.open();
};
const saveTransfer = async () => {
  if (!transferValue.value) return;
  try {
    await axios.post(`${crmApi()}/reassign`, {
      ids: [rowTarget.value.id],
      owner_id: Number(transferValue.value),
      cascade: transferCascade.value,
    });
    useAlert('已转移');
    fetchCustomers();
  } catch (e) {
    useAlert(e.response?.data?.error || '转移失败');
  }
};

// 共享候选：除负责人本人外的全部 CRM 成员。
const shareCandidates = computed(() =>
  allAgentsForAssign.value.filter(a => a.id !== rowTarget.value?.accountOwnerId)
);
const openShare = async customer => {
  openMenuId.value = null;
  rowTarget.value = customer;
  shareUserIds.value = [...(customer.sharedUserIds || [])];
  await ensureAgents();
  shareDialogRef.value?.open();
};
const toggleShareUser = id => {
  const i = shareUserIds.value.indexOf(id);
  if (i >= 0) shareUserIds.value.splice(i, 1);
  else shareUserIds.value.push(id);
};
const saveShare = async () => {
  try {
    await axios.post(`${crmApi()}/${rowTarget.value.id}/share`, {
      user_ids: shareUserIds.value,
    });
    useAlert('已更新共享');
    fetchCustomers();
  } catch (e) {
    useAlert(e.response?.data?.error || '共享失败');
  }
};

// 软色胶囊：浅底 + 同色文字，仿 Twenty 标签观感。
// 用字面量类名(Tailwind 只编译源码里出现的完整类名，动态拼接会被漏掉)。
const PILL = {
  teal: 'bg-n-teal-3 text-n-teal-11',
  blue: 'bg-n-blue-3 text-n-blue-11',
  amber: 'bg-n-iris-3 text-n-iris-11',
  gold: 'bg-n-amber-3 text-n-amber-11',
  violet: 'bg-n-violet-3 text-n-violet-11',
  ruby: 'bg-n-ruby-3 text-n-ruby-11',
  iris: 'bg-n-iris-3 text-n-iris-11',
  slate: 'bg-n-slate-4 text-n-slate-11',
};
// 仅经典灰：blue/iris 在经典灰下塌成灰，重映射到不褪色的 gold/violet；其它主题保持原色。
const CLASSIC_PILL_REMAP = { blue: 'gold', iris: 'violet' };
const AVATAR = {
  blue: 'bg-n-blue-9 text-white',
  teal: 'bg-n-teal-9 text-white',
  iris: 'bg-n-iris-9 text-white',
  amber: 'bg-n-iris-9 text-white',
  ruby: 'bg-n-ruby-9 text-white',
};
const pillCls = color =>
  PILL[(isClassic.value && CLASSIC_PILL_REMAP[color]) || color] || PILL.slate;

const GRADE_META = {
  COMPLETE: { label: '完善', color: 'teal' },
  GOOD: { label: '良好', color: 'blue' },
  FAIR: { label: '一般', color: 'iris' },
  POOR: { label: '待完善', color: 'ruby' },
};
const STATUS_META = {
  PROSPECT: { label: '潜在客户', color: 'slate' },
  FOLLOWING: { label: '跟进中', color: 'blue' },
  WON: { label: '成交客户', color: 'teal' },
  DORMANT: { label: '沉默客户', color: 'iris' },
  LOST: { label: '流失客户', color: 'ruby' },
};
// 来源来自「客户设置」，无固定色；按 code 哈希稳定取一个色，保持彩色胶囊观感。
const SOURCE_COLORS = ['iris', 'blue', 'teal', 'ruby', 'amber', 'slate'];
const sourceColor = code => {
  const s = String(code || '');
  let h = 0;
  for (let i = 0; i < s.length; i += 1) {
    h = (h + s.charCodeAt(i)) % SOURCE_COLORS.length;
  }
  return SOURCE_COLORS[h];
};
const LEVEL_COLOR = { A: 'teal', B: 'blue', C: 'iris', D: 'slate' };
const REGION_META = {
  NORTH_AMERICA: { label: '北美', color: 'blue' },
  EUROPE: { label: '欧洲', color: 'iris' },
  SOUTH_AMERICA: { label: '南美', color: 'teal' },
  MIDDLE_EAST: { label: '中东', color: 'iris' },
  SOUTHEAST_ASIA: { label: '东南亚', color: 'ruby' },
  AFRICA: { label: '非洲', color: 'slate' },
  OTHER: { label: '其他', color: 'slate' },
};
// 国家码 → 国旗+中文名（单一事实源见 constants/countries）
const COUNTRY_MAP = COUNTRY_LABELS;

const gradeMeta = c => GRADE_META[c.completenessGrade] || null;
const statusMeta = c => STATUS_META[c.customerStatus] || null;
const sourceMeta = c =>
  c.sourceChannel
    ? {
        label: sourceLabel(c.sourceChannel),
        color: sourceColor(c.sourceChannel),
      }
    : null;
const regionMeta = c => REGION_META[c.tradeRegion] || null;
const levelColor = level => LEVEL_COLOR[level] || 'slate';
const countryLabel = country => COUNTRY_MAP[country] || country || '—';

// 公司首字母头像色：按名称哈希取一个稳定色
const AVATAR_COLORS = ['blue', 'teal', 'iris', 'iris', 'ruby'];
const avatarCls = name => {
  const key = (name || '?').charCodeAt(0) || 0;
  return AVATAR[AVATAR_COLORS[key % AVATAR_COLORS.length]];
};
const initial = name => (name || '?').trim().charAt(0).toUpperCase();

// 负责人显示名：公海显示原跟进人，其余显示负责人（无则空）。
const ownerDisplayName = c =>
  c.isInPublicPool ? c.previousOwnerName : c.accountOwnerName;

const money = micros =>
  micros ? `¥${Math.round(micros / 1_000_000).toLocaleString()}` : '¥0';

const formatDate = value => (value ? new Date(value).toLocaleDateString() : '');

const PRODUCT_GROUP_LABELS = {
  TABLET: '平板电脑',
  COMMERCIAL_DISPLAY: '商显工控',
  // 兼容历史数据：迁移前的「工控」值仍显示为商显工控
  INDUSTRIAL_CONTROL: '商显工控',
};

// 详情面板展示的其他联系人：排除主联系人（已在「联系方式」呈现）。
const otherContacts = computed(() =>
  panelContacts.value.filter(ct => !ct.is_primary_contact)
);

// 右侧详情面板：分组字段数据（value 纯文本 / tag 彩色胶囊 / link 可点）
const detailSections = computed(() => {
  const c = selectedCustomer.value;
  if (!c) return [];
  const tag = meta =>
    meta ? { text: meta.label, cls: pillCls(meta.color) } : null;
  return [
    {
      title: '基本信息',
      rows: [
        { label: '客户编码', value: c.customerCode },
        { label: '官网', value: c.website, link: true },
        {
          label: c.isInPublicPool ? '原跟进人' : '负责人',
          value: c.isInPublicPool
            ? c.previousOwnerName || '—'
            : c.accountOwnerName || '未分配',
        },
        { label: '客户状态', tag: tag(statusMeta(c)) },
        {
          label: '客户级别',
          tag: c.customerLevel
            ? {
                text: c.customerLevel,
                cls: pillCls(levelColor(c.customerLevel)),
              }
            : null,
        },
        {
          label: '完善度',
          tag: tag(gradeMeta(c)),
          value:
            c.infoCompletenessScore != null
              ? `${c.infoCompletenessScore} 分`
              : null,
        },
      ],
    },
    {
      title: '商务',
      rows: [
        {
          label: '国家地区',
          value: c.tradeCountry ? countryLabel(c.tradeCountry) : null,
        },
        { label: '贸易区域', tag: tag(regionMeta(c)) },
        { label: '客户分组', value: groupLabel(c.customerGroup) },
        { label: '产品分组', value: PRODUCT_GROUP_LABELS[c.productGroup] },
        { label: '客户来源', tag: tag(sourceMeta(c)) },
        { label: '累计成交额', value: money(c.dealTotalAmountMicros) },
        {
          label: '成交订单数',
          value: c.dealOrderCount != null ? String(c.dealOrderCount) : null,
        },
        { label: '首次成交', value: formatDate(c.firstDealAt) || null },
        { label: '最近成交', value: formatDate(c.lastDealAt) || null },
      ],
    },
    {
      title: '联系方式',
      rows: [
        { label: '主要联系人', value: c.primaryContactName },
        { label: '职位', value: c.contactJobTitle },
        { label: '联系邮箱', value: c.contactEmail },
        { label: '联系电话', value: c.contactPhone },
        { label: 'WhatsApp', value: c.whatsApp },
        { label: '微信', value: c.wechat },
        { label: 'LinkedIn', value: c.linkedin, link: true },
        { label: '地址', value: c.address },
        { label: '联系偏好', value: c.contactPreference },
      ],
    },
    ...(otherContacts.value.length
      ? [
          {
            title: '其他联系人',
            rows: otherContacts.value.map(ct => ({
              label: ct.name || '联系人',
              value: [ct.job_title, ct.email].filter(Boolean).join(' · '),
            })),
          },
        ]
      : []),
    {
      title: '备注',
      rows: [{ label: '备注', value: c.customerRemark, full: true }],
    },
  ];
});

onMounted(() => {
  if (isCrmManager.value) fetchTeamMembers();
  else fetchTeams();
  if (
    isCrmSales.value ||
    isCrmManager.value ||
    isAdmin.value ||
    isCrmDeputyAdmin.value
  ) {
    fetchAllAgentsForAssign();
  }
  ensureLoaded();
  fetchCustomers();
  clockTimer = setInterval(() => {
    now.value = new Date();
  }, 60000);
});
onBeforeUnmount(() => clearInterval(clockTimer));
watch(
  () => route.query.filter,
  value => {
    activeFilter.value = value || 'private';
    currentPage.value = 1;
    fetchCustomers();
  }
);
</script>

<template>
  <div class="flex w-full h-full overflow-hidden font-sans">
    <div
      class="flex flex-col flex-1 min-w-0 overflow-hidden gap-3.5 px-5 py-4"
    >
      <div class="flex items-center justify-between flex-shrink-0">
        <div>
          <h1 class="text-[22px] font-bold tracking-[-0.01em] text-n-slate-12">
            {{
              activeFilter === 'churn_risk'
                ? '流失预警'
                : t('CRM.CUSTOMERS.HEADER')
            }}
          </h1>
          <!-- eslint-disable-next-line @intlify/vue-i18n/no-raw-text -->
          <p
            v-if="activeFilter === 'churn_risk'"
            class="mt-0.5 text-xs text-n-slate-10"
          >
            成交客户超过 30
            天没有跟进、邮件或订单，按最久未互动排序——跟进后自动移出
          </p>
        </div>
        <div class="flex items-center gap-2">
          <Button
            v-if="canImport"
            label="导入"
            icon="i-lucide-upload"
            variant="faded"
            color="slate"
            @click="importDialogRef?.open()"
          />
          <button
            type="button"
            class="inline-flex items-center gap-1.5 h-[34px] px-3.5 text-[13px] font-medium text-white rounded-[9px] bg-gradient-to-br from-n-iris-9 to-n-accent-grad shadow-lg shadow-n-iris-9/30 hover:brightness-105"
            @click="goToIntake"
          >
            <span class="i-lucide-plus size-4" />
            {{ t('CRM.CUSTOMERS.NEW') }}
          </button>
        </div>
      </div>

      <!-- 概览卡区（第 1 框）：随筛选联动 -->
      <div
        v-if="activeFilter !== 'churn_risk'"
        class="grid grid-cols-2 lg:grid-cols-4 gap-3.5 flex-shrink-0"
      >
        <div
          v-for="card in statCards"
          :key="card.key"
          class="flex items-center gap-3.5 p-4 rounded-2xl border border-n-weak bg-white shadow-sm shadow-n-slate-4/40"
        >
          <div
            class="grid place-items-center flex-none rounded-xl size-11"
            :class="card.tile"
          >
            <span :class="[card.icon, 'size-5']" />
          </div>
          <div class="min-w-0">
            <div
              class="text-2xl font-bold tracking-[-0.02em] text-n-slate-12 tabular-nums"
            >
              {{ card.value }}
            </div>
            <div class="mt-0.5 text-xs text-n-slate-11">{{ card.label }}</div>
          </div>
        </div>
      </div>

      <!-- 筛选区（第 2 框） -->
      <div
        class="flex flex-col gap-2.5 flex-shrink-0 px-4 py-3.5 rounded-2xl border border-n-weak bg-white shadow-sm shadow-n-slate-4/30"
      >
        <!-- 第 1 行：视图切换 + 搜索 + 只看关注 + 批量操作 -->
        <div class="flex flex-wrap items-center gap-2">
          <!-- 部门主管：我的客户 / 团队客户 双视图 -->
          <div
            v-if="isCrmManager && activeFilter === 'private'"
            class="flex items-center gap-0.5 p-[3px] rounded-[10px] bg-n-slate-3"
          >
            <button
              v-for="tab in [
                { key: 'mine', label: '我的客户' },
                { key: 'team', label: '团队客户' },
              ]"
              :key="tab.key"
              type="button"
              class="px-3 py-1.5 text-[13px] rounded-lg transition-colors"
              :class="
                managerView === tab.key
                  ? 'bg-n-iris-9 text-white font-semibold shadow-sm shadow-n-iris-9/30'
                  : 'text-n-slate-11 hover:text-n-slate-12'
              "
              @click="setManagerView(tab.key)"
            >
              {{ tab.label }}
            </button>
          </div>
          <div
            class="flex items-center gap-2 px-3 h-[38px] w-60 text-[13px] border rounded-[10px] border-n-weak bg-n-solid-1/60 focus-within:ring-2 focus-within:ring-n-iris-9"
          >
            <span class="i-lucide-search size-4 shrink-0 text-n-slate-9" />
            <input
              v-model="searchQuery"
              type="text"
              placeholder="搜索客户名…"
              class="flex-1 h-full bg-transparent reset-base text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none"
              @input="onSearchInput"
            />
          </div>
          <!-- 只看特别关注（每人各标） -->
          <button
            type="button"
            class="flex items-center gap-1.5 px-3 h-[38px] text-[13px] font-medium border rounded-[10px] shrink-0 transition-colors"
            :class="
              favoritesOnly
                ? 'border-[#ffb3b5] bg-[#fff2f2] text-[#ff5a5f]'
                : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-2'
            "
            @click="toggleFavoritesOnly"
          >
            <span
              class="size-4"
              :class="favoritesOnly ? 'i-ri-heart-fill' : 'i-ri-heart-line'"
            />
            只看关注
          </button>
          <!-- 勾选分配：选中客户连同商机/订单/报价/邮件分配给新业务员 -->
          <template v-if="canSelectRows && selectedIds.length">
            <span class="text-sm text-n-slate-11">
              已选 {{ selectedIds.length }} 个
            </span>
            <SelectCard
              :model-value="reassignTargetId"
              :options="assignTargetOptions"
              placeholder="选择业务员"
              @update:model-value="v => (reassignTargetId = v)"
            />
            <Button
              v-tooltip.top="
                '分配后，该客户的商机、订单、报价及往来邮件将一并转入新负责人名下'
              "
              label="分配"
              color="iris"
              size="sm"
              :disabled="!reassignTargetId || reassigning"
              @click="reassignSelected"
            />
            <Button
              v-tooltip.top="
                '给勾选客户群发同一封邮件，每人各收到一封独立邮件、互相不可见'
              "
              label="群发邮件"
              icon="i-lucide-mail"
              color="teal"
              size="sm"
              @click="bulkSendSelected"
            />
          </template>
        </div>

        <!-- 第 2 行：筛选下拉 -->
        <div
          class="flex flex-wrap items-center gap-2 pt-2.5 border-t border-n-weak"
        >
          <span class="text-[11.5px] font-semibold tracking-wide text-n-slate-10">
            筛选
          </span>
          <!-- 公海全公司共享，不提供团队/业务员筛选 -->
          <SelectCard
            v-if="
              !isCrmSales && !isCrmManager && activeFilter !== 'public_pool'
            "
            :model-value="selectedTeamId"
            :options="teamOptions"
            trigger-class="!text-[13px]"
            @update:model-value="setTeam"
          />
          <SelectCard
            v-if="
              !isCrmSales &&
              !isCrmManager &&
              activeFilter !== 'public_pool' &&
              selectedTeamId
            "
            :model-value="selectedOwnerId"
            :options="ownerOptions"
            trigger-class="!text-[13px]"
            @update:model-value="setOwner"
          />
          <!-- 部门主管：团队客户视图下按自己团队的业务员筛选 -->
          <SelectCard
            v-if="isManagerTeamView"
            :model-value="selectedOwnerId"
            :options="managerOwnerOptions"
            trigger-class="!text-[13px]"
            @update:model-value="setOwner"
          />
          <SelectCard
            :model-value="activeStatus"
            :options="statusFilterOptions"
            trigger-class="!text-[13px]"
            @update:model-value="setStatus"
          />
          <SelectCard
            :model-value="activeLevel"
            :options="levelFilterOptions"
            trigger-class="!text-[13px]"
            @update:model-value="setLevel"
          />
          <SelectCard
            :model-value="activeSourceChannel"
            :options="sourceChannelOptions"
            trigger-class="!text-[13px]"
            @update:model-value="setSourceChannel"
          />
          <SelectCard
            :model-value="activeCustomerGroup"
            :options="customerGroupOptions"
            trigger-class="!text-[13px]"
            @update:model-value="setCustomerGroup"
          />
          <SelectCard
            :model-value="activeProductGroup"
            :options="productGroupOptions"
            trigger-class="!text-[13px]"
            @update:model-value="setProductGroup"
          />
        </div>
      </div>

      <!-- 表格区（第 3 框）：内含滚动表格 + 分页页脚 -->
      <div
        class="flex flex-col flex-1 min-h-0 overflow-hidden rounded-2xl border border-n-weak bg-white shadow-sm shadow-n-slate-4/30"
      >
        <div class="flex-1 min-h-0 px-3.5 py-1 overflow-auto">
          <div
            v-if="isFetching"
            class="flex items-center justify-center p-8 text-sm text-n-slate-11"
          >
            {{ t('CRM.CUSTOMERS.LOADING') }}
        </div>
        <div
          v-else-if="!customers.length"
          class="flex items-center justify-center p-8 text-sm text-n-slate-11"
        >
          {{ t('CRM.CUSTOMERS.EMPTY') }}
        </div>
        <div v-else class="overflow-x-auto">
          <div class="overflow-x-auto">
            <table
              class="w-full text-[13px] text-left border-separate border-spacing-0"
            >
              <thead class="text-n-slate-10">
                <tr class="[&>th]:border-b [&>th]:border-n-weak">
                  <th
                    v-if="canSelectRows"
                    class="sticky left-0 z-20 w-11 px-3 py-2.5 bg-white"
                  >
                    <input
                      type="checkbox"
                      class="accent-n-iris-9"
                      :checked="allSelected"
                      @change="toggleSelectAll"
                    />
                  </th>
                  <th
                    class="sticky z-20 px-3 py-2.5 text-[13px] font-semibold whitespace-nowrap bg-white shadow-[6px_0_8px_-6px_rgba(80,70,229,0.15)]"
                    :class="canSelectRows ? 'left-11' : 'left-0'"
                  >
                    {{ t('CRM.CUSTOMERS.TABLE.NAME') }}
                  </th>
                  <th
                    class="px-3 py-2.5 text-[13px] font-semibold whitespace-nowrap"
                  >
                    {{ t('CRM.CUSTOMERS.TABLE.COUNTRY') }}
                  </th>
                  <th
                    class="px-3 py-2.5 text-[13px] font-semibold whitespace-nowrap"
                  >
                    时区
                  </th>
                  <th
                    class="px-3 py-2.5 text-[13px] font-semibold whitespace-nowrap"
                  >
                    主要联系人
                  </th>
                  <th
                    class="px-3 py-2.5 text-[13px] font-semibold whitespace-nowrap"
                  >
                    邮箱
                  </th>
                  <th
                    class="px-3 py-2.5 text-[13px] font-semibold whitespace-nowrap"
                  >
                    <button
                      class="inline-flex items-center gap-1 text-[13px] transition-colors hover:text-n-slate-12"
                      :class="
                        sortKey === 'completeness' ? 'text-n-slate-12' : ''
                      "
                      @click="toggleSort('completeness')"
                    >
                      {{ t('CRM.CUSTOMERS.TABLE.GRADE') }}
                      <span
                        class="size-3.5"
                        :class="sortIcon('completeness')"
                      />
                    </button>
                  </th>
                  <th
                    class="px-3 py-2.5 text-[13px] font-semibold text-right whitespace-nowrap"
                  >
                    <button
                      class="inline-flex items-center gap-1 ml-auto text-[13px] transition-colors hover:text-n-slate-12"
                      :class="
                        sortKey === 'deal_amount' ? 'text-n-slate-12' : ''
                      "
                      @click="toggleSort('deal_amount')"
                    >
                      {{ t('CRM.CUSTOMERS.TABLE.DEAL_AMOUNT') }}
                      <span class="size-3.5" :class="sortIcon('deal_amount')" />
                    </button>
                  </th>
                  <th
                    class="px-3 py-2.5 text-[13px] font-semibold text-right whitespace-nowrap"
                  >
                    <button
                      class="inline-flex items-center gap-1 ml-auto text-[13px] transition-colors hover:text-n-slate-12"
                      :class="sortKey === 'deal_count' ? 'text-n-slate-12' : ''"
                      @click="toggleSort('deal_count')"
                    >
                      {{ t('CRM.CUSTOMERS.TABLE.DEAL_COUNT') }}
                      <span class="size-3.5" :class="sortIcon('deal_count')" />
                    </button>
                  </th>
                  <th
                    class="px-3 py-2.5 text-[13px] font-semibold whitespace-nowrap"
                  >
                    {{ t('CRM.CUSTOMERS.TABLE.STATUS') }}
                  </th>
                  <th
                    class="px-3 py-2.5 text-[13px] font-semibold whitespace-nowrap"
                  >
                    {{ t('CRM.CUSTOMERS.TABLE.LEVEL') }}
                  </th>
                  <th
                    class="px-3 py-2.5 text-[13px] font-semibold whitespace-nowrap"
                  >
                    {{ t('CRM.CUSTOMERS.TABLE.SOURCE') }}
                  </th>
                  <th
                    class="px-3 py-2.5 text-[13px] font-semibold whitespace-nowrap"
                  >
                    {{ t('CRM.CUSTOMERS.TABLE.REGION') }}
                  </th>
                  <th
                    class="px-3 py-2.5 text-[13px] font-semibold whitespace-nowrap"
                  >
                    {{
                      activeFilter === 'public_pool'
                        ? '原跟进人'
                        : t('CRM.CUSTOMERS.TABLE.OWNER')
                    }}
                  </th>
                  <th
                    class="px-3 py-2.5 text-[13px] font-semibold text-right whitespace-nowrap"
                  >
                    {{ t('CRM.CUSTOMERS.TABLE.ACTION') }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="customer in customers"
                  :key="customer.id"
                  class="cursor-pointer [&>td]:border-b [&>td]:border-n-weak hover:bg-n-iris-9/[0.04]"
                  :class="{
                    'bg-n-iris-2': selectedCustomer?.id === customer.id,
                  }"
                  @click="selectCustomer(customer)"
                >
                  <td
                    v-if="canSelectRows"
                    class="sticky left-0 z-10 w-11 px-3 py-2.5 bg-white"
                    @click.stop
                  >
                    <input
                      type="checkbox"
                      class="accent-n-iris-9"
                      :checked="selectedIds.includes(customer.id)"
                      @change="toggleSelect(customer.id)"
                    />
                  </td>
                  <td
                    class="sticky z-10 px-3 py-2.5 min-w-[180px] bg-white shadow-[6px_0_8px_-6px_rgba(80,70,229,0.15)]"
                    :class="canSelectRows ? 'left-11' : 'left-0'"
                  >
                    <div class="flex items-center gap-2.5 min-w-0 group">
                      <span
                        class="grid flex-none text-xs font-bold rounded-lg size-7 place-items-center bg-n-slate-4 text-n-slate-11"
                      >
                        {{ initial(customer.name) }}
                      </span>
                      <input
                        v-if="isEditingCell(customer, 'name')"
                        v-model="editingValue"
                        v-focus
                        class="w-full min-w-0 px-1.5 py-0.5 text-sm border rounded bg-n-solid-1 border-n-iris-8 text-n-slate-12 focus:outline-none"
                        @click.stop
                        @keyup.enter="saveCellEdit(customer)"
                        @keyup.esc="cancelCellEdit"
                        @blur="saveCellEdit(customer)"
                      />
                      <template v-else>
                        <span class="font-semibold truncate text-n-slate-12">
                          {{ customer.name }}
                        </span>
                        <button
                          type="button"
                          :title="
                            customer.favorited ? '取消特别关注' : '特别关注'
                          "
                          class="flex-shrink-0 transition"
                          :class="
                            customer.favorited
                              ? 'text-[#ff5a5f]'
                              : 'text-n-slate-8 opacity-0 group-hover:opacity-100 hover:text-[#ff8a8d]'
                          "
                          @click.stop="toggleFavorite(customer)"
                        >
                          <span
                            class="size-4"
                            :class="
                              customer.favorited
                                ? 'i-ri-heart-fill'
                                : 'i-ri-heart-line'
                            "
                          />
                        </button>
                        <span
                          class="flex items-center flex-shrink-0 gap-0.5 transition-opacity opacity-0 group-hover:opacity-100"
                          @click.stop
                        >
                          <button
                            type="button"
                            title="复制"
                            class="p-1 rounded text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2"
                            @click.stop="copyCell(customer.name)"
                          >
                            <span class="i-lucide-copy size-3.5" />
                          </button>
                          <button
                            type="button"
                            title="编辑"
                            class="p-1 rounded text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2"
                            @click.stop="startCellEdit(customer, 'name')"
                          >
                            <span class="i-lucide-pencil size-3.5" />
                          </button>
                        </span>
                      </template>
                    </div>
                  </td>
                  <td class="px-3 py-2.5 whitespace-nowrap text-n-slate-11">
                    {{ countryLabel(customer.tradeCountry) }}
                  </td>
                  <td
                    class="px-3 py-2.5 whitespace-nowrap text-n-slate-11 tabular-nums"
                  >
                    {{ customerTime(customer) || '—' }}
                  </td>
                  <td class="px-3 py-2.5 whitespace-nowrap text-n-slate-11">
                    <div class="flex items-center min-w-0 gap-1 group">
                      <input
                        v-if="isEditingCell(customer, 'primaryContactName')"
                        v-model="editingValue"
                        v-focus
                        class="w-full min-w-0 px-1.5 py-0.5 text-sm border rounded bg-n-solid-1 border-n-iris-8 text-n-slate-12 focus:outline-none"
                        @click.stop
                        @keyup.enter="saveCellEdit(customer)"
                        @keyup.esc="cancelCellEdit"
                        @blur="saveCellEdit(customer)"
                      />
                      <template v-else>
                        <span class="truncate">
                          {{ customer.primaryContactName || '—' }}
                        </span>
                        <span
                          class="flex items-center flex-shrink-0 gap-0.5 transition-opacity opacity-0 group-hover:opacity-100"
                          @click.stop
                        >
                          <button
                            v-if="customer.primaryContactName"
                            type="button"
                            title="复制"
                            class="p-1 rounded text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2"
                            @click.stop="copyCell(customer.primaryContactName)"
                          >
                            <span class="i-lucide-copy size-3.5" />
                          </button>
                          <button
                            type="button"
                            title="编辑"
                            class="p-1 rounded text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2"
                            @click.stop="
                              startCellEdit(customer, 'primaryContactName')
                            "
                          >
                            <span class="i-lucide-pencil size-3.5" />
                          </button>
                        </span>
                      </template>
                    </div>
                  </td>
                  <td class="px-3 py-2.5 whitespace-nowrap text-n-slate-11">
                    <div class="flex items-center min-w-0 gap-1 group">
                      <input
                        v-if="isEditingCell(customer, 'contactEmail')"
                        v-model="editingValue"
                        v-focus
                        type="email"
                        class="w-full min-w-0 px-1.5 py-0.5 text-sm border rounded bg-n-solid-1 border-n-iris-8 text-n-slate-12 focus:outline-none"
                        @click.stop
                        @keyup.enter="saveCellEdit(customer)"
                        @keyup.esc="cancelCellEdit"
                        @blur="saveCellEdit(customer)"
                      />
                      <template v-else>
                        <button
                          v-if="customer.contactEmail"
                          type="button"
                          title="点击写邮件"
                          class="truncate text-left transition-colors hover:text-n-iris-11 hover:underline"
                          @click.stop="writeEmail(customer)"
                        >
                          {{ customer.contactEmail }}
                        </button>
                        <span v-else class="truncate">—</span>
                        <span
                          class="flex items-center flex-shrink-0 gap-0.5 transition-opacity opacity-0 group-hover:opacity-100"
                          @click.stop
                        >
                          <button
                            v-if="customer.contactEmail"
                            type="button"
                            title="复制"
                            class="p-1 rounded text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2"
                            @click.stop="copyCell(customer.contactEmail)"
                          >
                            <span class="i-lucide-copy size-3.5" />
                          </button>
                          <button
                            type="button"
                            title="编辑"
                            class="p-1 rounded text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2"
                            @click.stop="
                              startCellEdit(customer, 'contactEmail')
                            "
                          >
                            <span class="i-lucide-pencil size-3.5" />
                          </button>
                        </span>
                      </template>
                    </div>
                  </td>
                  <td class="px-3 py-2.5">
                    <div
                      v-if="gradeMeta(customer)"
                      class="flex items-center gap-2"
                    >
                      <div
                        class="w-11 h-[5px] rounded-full bg-n-slate-4 overflow-hidden"
                      >
                        <div
                          class="h-full rounded-full"
                          :class="
                            isClassic
                              ? 'bg-[#f5c451]'
                              : 'bg-gradient-to-r from-n-iris-9 to-n-accent-grad'
                          "
                          :style="{
                            width:
                              Math.min(
                                100,
                                Math.max(0, customer.infoCompletenessScore || 0)
                              ) + '%',
                          }"
                        />
                      </div>
                      <span class="text-[11px] text-n-slate-10 tabular-nums">
                        {{ customer.infoCompletenessScore }}
                      </span>
                    </div>
                    <span v-else class="text-n-slate-10">—</span>
                  </td>
                  <td
                    class="px-3 py-2.5 font-semibold text-right tabular-nums text-n-slate-12 whitespace-nowrap"
                  >
                    {{ money(customer.dealTotalAmountMicros) }}
                  </td>
                  <td
                    class="px-3 py-2.5 text-right tabular-nums text-n-slate-11"
                  >
                    {{ customer.dealOrderCount || 0 }}
                  </td>
                  <td class="px-3 py-2.5">
                    <span
                      v-if="statusMeta(customer)"
                      class="inline-flex items-center px-2.5 py-[3px] rounded-full text-[11.5px] font-bold whitespace-nowrap"
                      :class="pillCls(statusMeta(customer).color)"
                    >
                      {{ statusMeta(customer).label }}
                    </span>
                    <span v-else class="text-n-slate-10">—</span>
                  </td>
                  <td class="px-3 py-2.5">
                    <span
                      v-if="customer.customerLevel"
                      class="inline-flex items-center justify-center rounded-md size-[22px] text-xs font-bold"
                      :class="pillCls(levelColor(customer.customerLevel))"
                    >
                      {{ customer.customerLevel }}
                    </span>
                    <span v-else class="text-n-slate-10">—</span>
                  </td>
                  <td class="px-3 py-2.5">
                    <span
                      v-if="sourceMeta(customer)"
                      class="inline-flex px-2.5 py-[3px] rounded-full text-[11px] font-bold whitespace-nowrap"
                      :class="pillCls(sourceMeta(customer).color)"
                    >
                      {{ sourceMeta(customer).label }}
                    </span>
                    <span v-else class="text-n-slate-10">—</span>
                  </td>
                  <td class="px-3 py-2.5 whitespace-nowrap text-n-slate-11">
                    <span v-if="regionMeta(customer)">
                      {{ regionMeta(customer).label }}
                    </span>
                    <span v-else class="text-n-slate-10">—</span>
                  </td>
                  <td class="px-3 py-2.5 whitespace-nowrap text-n-slate-11">
                    <div
                      v-if="ownerDisplayName(customer)"
                      class="flex items-center gap-2"
                    >
                      <span
                        class="grid flex-none text-[11px] font-bold rounded-md size-6 place-items-center bg-n-slate-4 text-n-slate-11"
                      >
                        {{ initial(ownerDisplayName(customer)) }}
                      </span>
                      <span class="truncate">
                        {{ ownerDisplayName(customer) }}
                      </span>
                    </div>
                    <span v-else class="text-n-slate-10">
                      <!-- eslint-disable-next-line @intlify/vue-i18n/no-raw-text -->
                      {{ customer.isInPublicPool ? '—' : '未分配' }}
                    </span>
                  </td>
                  <td class="px-3 py-2.5 text-right" @click.stop>
                    <Button
                      v-if="customer.isInPublicPool"
                      :label="t('CRM.CUSTOMERS.POOL.CLAIM')"
                      size="sm"
                      color="iris"
                      :is-loading="actingId === customer.id"
                      @click="claimCustomer(customer)"
                    />
                    <button
                      v-else
                      class="inline-flex items-center justify-center rounded size-7 text-n-slate-11 hover:bg-n-alpha-2"
                      @click="toggleRowMenu(customer.id, $event)"
                    >
                      <span class="i-lucide-ellipsis-vertical size-4" />
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <div
        v-if="totalCount > 0"
        class="flex items-center justify-between flex-shrink-0 px-4 py-3 border-t border-n-weak text-[12.5px] text-n-slate-10"
      >
        <div class="flex items-center gap-3 shrink-0 whitespace-nowrap">
          <!-- eslint-disable-next-line @intlify/vue-i18n/no-raw-text -->
          <span>共 {{ totalCount }} 条</span>
          <div class="flex items-center gap-1.5">
            <!-- eslint-disable-next-line @intlify/vue-i18n/no-raw-text -->
            <span>每页</span>
            <SelectCard
              :model-value="pageSize"
              :options="pageSizeOptions"
              align="right"
              trigger-class="!h-[26px] !text-[12.5px] !pl-2.5 !pr-1.5 !gap-1"
              @update:model-value="setPageSize"
            />
            <!-- eslint-disable-next-line @intlify/vue-i18n/no-raw-text -->
            <span>条</span>
          </div>
        </div>
        <div v-if="totalPages > 1" class="flex items-center gap-1">
          <button
            type="button"
            class="flex items-center justify-center min-w-[28px] h-7 px-1.5 border rounded-lg border-n-weak bg-n-solid-1/60 text-n-slate-11 disabled:opacity-40"
            :disabled="currentPage === 1"
            @click="onPageChange(currentPage - 1)"
          >
            <span class="i-lucide-chevron-left size-4" />
          </button>
          <template v-for="(p, i) in pageList" :key="i">
            <span
              v-if="p === '…'"
              class="flex items-center justify-center min-w-[28px] h-7 text-n-slate-9"
            >
              {{ p }}
            </span>
            <button
              v-else
              type="button"
              class="flex items-center justify-center min-w-[28px] h-7 px-2 rounded-lg tabular-nums"
              :class="
                p === currentPage
                  ? 'bg-n-iris-9 text-white font-semibold'
                  : 'text-n-slate-11 hover:bg-n-alpha-2'
              "
              @click="onPageChange(p)"
            >
              {{ p }}
            </button>
          </template>
          <button
            type="button"
            class="flex items-center justify-center min-w-[28px] h-7 px-1.5 border rounded-lg border-n-weak bg-n-solid-1/60 text-n-slate-11 disabled:opacity-40"
            :disabled="currentPage === totalPages"
            @click="onPageChange(currentPage + 1)"
          >
            <span class="i-lucide-chevron-right size-4" />
          </button>
        </div>
      </div>
      </div>
    </div>

    <!-- 右侧客户详情面板 -->
    <aside
      v-if="selectedCustomer"
      class="flex flex-col w-[400px] flex-shrink-0 overflow-hidden my-3 mr-3 rounded-3xl border border-white/50 bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 shadow-lg shadow-n-iris-9/5"
    >
      <div class="flex items-center gap-3 px-5 py-4 border-b border-n-weak">
        <span
          class="flex items-center justify-center flex-shrink-0 font-semibold rounded-lg size-9"
          :class="avatarCls(selectedCustomer.name)"
        >
          {{ initial(selectedCustomer.name) }}
        </span>
        <div class="flex-1 min-w-0">
          <div class="font-semibold truncate text-n-slate-12">
            {{ selectedCustomer.name }}
          </div>
          <div
            v-if="selectedCustomer.createdAt"
            class="text-xs text-n-slate-10"
          >
            创建于 {{ formatDate(selectedCustomer.createdAt) }}
          </div>
        </div>
        <button
          class="px-2.5 py-1 mr-1 text-xs rounded-md text-n-iris-11 hover:bg-n-iris-2"
          @click="openDetailPage"
        >
          查看详情
        </button>
        <button
          class="p-1 rounded-md text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-1"
          @click="closePanel"
        >
          <span class="i-lucide-x size-5" />
        </button>
      </div>

      <!-- 标签栏 -->
      <div class="flex px-2 overflow-x-auto border-b border-n-weak">
        <button
          v-for="tab in PANEL_TABS"
          :key="tab.key"
          class="flex items-center gap-1.5 px-2.5 py-2.5 text-sm border-b-2 whitespace-nowrap transition-colors"
          :class="
            activeTab === tab.key
              ? 'border-n-iris-9 text-n-slate-12 font-medium'
              : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
          "
          @click="setTab(tab.key)"
        >
          <span class="size-4" :class="tab.icon" />
          {{ tab.label }}
        </button>
      </div>

      <div class="flex-1 overflow-y-auto">
        <!-- 主页：字段 -->
        <template v-if="activeTab === 'fields'">
          <!-- 下次跟进 + 加入日程（置顶，免点详情/免下拉） -->
          <div class="px-5 py-4 border-b border-n-weak">
            <div
              class="mb-3 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
            >
              下次跟进
            </div>
            <div class="flex flex-wrap items-center gap-2">
              <div class="w-36">
                <DatePicker v-model="nextDate" block :clearable="false" />
              </div>
              <div class="w-24">
                <SelectCard v-model="nextTime" :options="timeOptions" block />
              </div>
            </div>
            <label
              class="flex items-center gap-1.5 mt-3 text-sm text-n-slate-11"
            >
              <input
                v-model="addToSchedule"
                type="checkbox"
                class="accent-n-iris-9"
              />
              加入我的日程
            </label>
            <button
              class="w-full py-2 mt-3 text-sm font-semibold text-white rounded-lg bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-60"
              :disabled="savingNext"
              @click="saveNextFollowUp"
            >
              {{ savingNext ? '保存中…' : '保存下次跟进' }}
            </button>
          </div>
          <div
            v-for="section in detailSections"
            :key="section.title"
            class="px-5 py-4 border-b border-n-weak"
          >
            <div
              class="mb-3 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
            >
              {{ section.title }}
            </div>
            <div class="flex flex-col gap-3">
              <div
                v-for="row in section.rows"
                :key="row.label"
                class="flex items-start gap-3 text-sm"
              >
                <span class="w-20 shrink-0 text-n-slate-10">
                  {{ row.label }}
                </span>
                <div class="flex flex-wrap items-center flex-1 min-w-0 gap-2">
                  <span
                    v-if="row.tag"
                    class="inline-flex px-2 py-0.5 text-xs rounded-md"
                    :class="row.tag.cls"
                  >
                    {{ row.tag.text }}
                  </span>
                  <a
                    v-if="row.link && row.value"
                    :href="row.value"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="break-all text-n-blue-11 hover:underline"
                  >
                    {{ row.value }}
                  </a>
                  <span
                    v-else-if="row.value"
                    class="text-n-slate-12"
                    :class="
                      row.full ? 'whitespace-pre-wrap break-words' : 'break-all'
                    "
                  >
                    {{ row.value }}
                  </span>
                  <span v-else-if="!row.tag" class="text-n-slate-10">—</span>
                </div>
              </div>
            </div>
          </div>
        </template>

        <div
          v-else-if="tabLoading"
          class="py-10 text-sm text-center text-n-slate-10"
        >
          加载中…
        </div>

        <!-- 操作历史（审计日志） -->
        <div v-else-if="activeTab === 'timeline'" class="p-5">
          <div
            v-if="!panelAudits.length"
            class="py-6 text-sm text-center text-n-slate-10"
          >
            暂无操作记录
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
                  {{ auditMessage(a) }}
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- 备注 -->
        <div v-else-if="activeTab === 'notes'" class="flex flex-col gap-3 p-5">
          <div class="flex gap-2">
            <input
              v-model="newNote"
              placeholder="添加备注…"
              class="flex-1 h-9 px-2 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
              @keyup.enter="addNote"
            />
            <Button label="添加" color="iris" size="sm" @click="addNote" />
          </div>
          <div
            v-if="!panelNotes.length"
            class="py-6 text-sm text-center text-n-slate-10"
          >
            暂无备注
          </div>
          <div v-else class="flex flex-col gap-2">
            <div
              v-for="n in panelNotes"
              :key="n.id"
              class="p-3 border rounded-lg border-n-weak"
            >
              <div class="text-sm font-medium text-n-slate-12">
                {{ n.title }}
              </div>
              <div
                v-if="n.body"
                class="mt-1 text-xs whitespace-pre-wrap text-n-slate-11"
              >
                {{ n.body }}
              </div>
              <div class="mt-1 text-xs text-n-slate-10">
                {{ fmtDateTime(n.created_at) }}
              </div>
            </div>
          </div>
        </div>

        <!-- 文件 -->
        <div v-else-if="activeTab === 'files'" class="flex flex-col gap-3 p-5">
          <label
            class="flex items-center justify-center gap-2 py-2 text-sm border border-dashed rounded-lg cursor-pointer border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
          >
            <span class="i-lucide-upload size-4" /> 上传文件
            <input type="file" multiple class="hidden" @change="uploadFiles" />
          </label>
          <div
            v-if="!(selectedCustomer.files && selectedCustomer.files.length)"
            class="py-6 text-sm text-center text-n-slate-10"
          >
            暂无文件
          </div>
          <div v-else class="flex flex-col gap-2">
            <div
              v-for="f in selectedCustomer.files"
              :key="f.id"
              class="flex items-center gap-2 p-2.5 border rounded-lg border-n-weak"
            >
              <span class="i-lucide-file size-4 text-n-slate-10 shrink-0" />
              <a
                :href="f.url"
                target="_blank"
                rel="noopener noreferrer"
                class="flex-1 text-sm truncate text-n-blue-11 hover:underline"
              >
                {{ f.filename }}
              </a>
              <span class="text-xs text-n-slate-10">
                {{ fmtBytes(f.byteSize) }}
              </span>
              <button
                class="text-n-slate-10 hover:text-n-ruby-11"
                @click="removeFile(f.id)"
              >
                <span class="i-lucide-x size-4" />
              </button>
            </div>
          </div>
        </div>

        <!-- 电子邮件 -->
        <div v-else-if="activeTab === 'emails'" class="p-5">
          <div
            v-if="!panelEmails.length"
            class="py-6 text-sm text-center text-n-slate-10"
          >
            暂无往来邮件
          </div>
          <div v-else class="flex flex-col gap-2">
            <div
              v-for="e in panelEmails"
              :key="e.id"
              class="p-3 border rounded-lg border-n-weak"
            >
              <div class="flex items-center gap-2">
                <span
                  class="px-1.5 py-0.5 text-xs rounded-md"
                  :class="
                    e.folder === 'SENT'
                      ? 'bg-n-teal-3 text-n-teal-11'
                      : 'bg-n-blue-3 text-n-blue-11'
                  "
                >
                  {{ e.folder === 'SENT' ? '发件' : '收件' }}
                </span>
                <span class="ml-auto text-xs text-n-slate-10">
                  {{ fmtDateTime(e.email_date || e.created_at) }}
                </span>
                <button
                  class="flex items-center gap-1 px-2 py-0.5 text-xs font-medium rounded-md text-n-iris-11 bg-n-iris-3 hover:bg-n-iris-4 transition-colors"
                  title="回复"
                  @click.stop="replyPanelEmail(e)"
                >
                  <span class="i-lucide-reply size-3.5" />
                  回复
                </button>
              </div>
              <div class="mt-1 text-sm font-medium truncate text-n-slate-12">
                {{ e.subject || '(无主题)' }}
              </div>
              <div class="text-xs truncate text-n-slate-10">
                {{ e.from_address }} → {{ e.to_address }}
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="flex gap-2 px-5 py-4 border-t border-n-weak">
        <Button
          label="编辑"
          icon="i-lucide-pencil"
          color="iris"
          class="flex-1"
          @click="editSelected"
        />
        <Button
          v-if="selectedCustomer.isInPublicPool"
          :label="t('CRM.CUSTOMERS.POOL.CLAIM')"
          variant="faded"
          color="slate"
          :is-loading="actingId === selectedCustomer.id"
          @click="claimCustomer(selectedCustomer)"
        />
        <Button
          v-else
          :label="t('CRM.CUSTOMERS.POOL.RELEASE')"
          variant="faded"
          color="slate"
          :is-loading="actingId === selectedCustomer.id"
          @click="releaseCustomer(selectedCustomer)"
        />
      </div>
    </aside>

    <CrmCustomerCreateDialog
      ref="createDialogRef"
      :is-loading="isCreating"
      @update="updateCustomer"
      @refresh="fetchCustomers"
    />

    <CrmCustomerImportDialog
      v-if="canImport"
      ref="importDialogRef"
      :member-options="importMemberOptions"
      @imported="fetchCustomers"
    />

    <!-- 行操作菜单（Teleport 到 body，避开表格滚动容器裁剪） -->
    <Teleport to="body">
      <template v-if="menuCustomer">
        <div class="fixed inset-0 z-[60]" @click="openMenuId = null" />
        <div
          class="fixed z-[61] py-1 border rounded-lg shadow-lg w-[148px] border-n-weak bg-n-solid-1"
          :style="{ top: menuAnchor.top + 'px', left: menuAnchor.left + 'px' }"
        >
          <button
            class="w-full px-3 py-2.5 text-sm text-left text-n-slate-12 hover:bg-n-alpha-1"
            @click="writeEmail(menuCustomer)"
          >
            写邮件
          </button>
          <button
            class="w-full px-3 py-2.5 text-sm text-left text-n-slate-12 hover:bg-n-alpha-1"
            @click="openMoveGroup(menuCustomer)"
          >
            移动至分组
          </button>
          <button
            class="w-full px-3 py-2.5 text-sm text-left text-n-slate-12 hover:bg-n-alpha-1"
            @click="openTransfer(menuCustomer)"
          >
            转移给
          </button>
          <button
            class="w-full px-3 py-2.5 text-sm text-left text-n-slate-12 hover:bg-n-alpha-1"
            @click="openShare(menuCustomer)"
          >
            共享客户
          </button>
          <div class="my-1 border-t border-n-weak" />
          <button
            class="w-full px-3 py-2.5 text-sm text-left text-n-ruby-11 hover:bg-n-alpha-1"
            @click="
              releaseCustomer(menuCustomer);
              openMenuId = null;
            "
          >
            移入公海
          </button>
        </div>
      </template>
    </Teleport>

    <!-- 移动至分组 -->
    <Dialog
      ref="moveGroupDialogRef"
      title="移动至分组"
      confirm-button-color="iris"
      @confirm="saveMoveGroup"
    >
      <div class="flex flex-col gap-1.5">
        <label class="text-heading-3 text-n-slate-12">选择分组</label>
        <Select v-model="moveGroupValue" :options="moveGroupOptions" />
      </div>
    </Dialog>

    <!-- 转移给 -->
    <Dialog
      ref="transferDialogRef"
      :title="transferTitle"
      confirm-button-color="iris"
      :disable-confirm-button="!transferValue"
      @confirm="saveTransfer"
    >
      <div class="flex flex-col gap-4">
        <div
          class="flex items-start gap-2 px-3 py-2 text-xs rounded-lg bg-n-blue-2 text-n-blue-11"
        >
          <span class="i-lucide-info size-3.5 shrink-0 mt-0.5" />
          转移客户后，新负责人将可见该客户的全部详细资料。
        </div>
        <div class="flex flex-col gap-1.5">
          <label class="text-heading-3 text-n-slate-12">转移给</label>
          <Select
            v-model="transferValue"
            :options="transferOptions"
            placeholder="请选择"
          />
        </div>
        <div class="flex flex-col gap-2">
          <label
            class="flex items-center gap-2.5 cursor-pointer text-sm text-n-slate-12"
          >
            <input
              type="checkbox"
              class="accent-n-iris-9"
              :checked="transferCascade.opportunities"
              @change="
                transferCascade.opportunities = !transferCascade.opportunities
              "
            />
            一并转移客户商机
          </label>
          <label
            class="flex items-center gap-2.5 cursor-pointer text-sm text-n-slate-12"
          >
            <input
              type="checkbox"
              class="accent-n-iris-9"
              :checked="transferCascade.orders"
              @change="transferCascade.orders = !transferCascade.orders"
            />
            一并转移客户订单（含报价）
          </label>
          <label
            class="flex items-center gap-2.5 cursor-pointer text-sm text-n-slate-12"
          >
            <input
              type="checkbox"
              class="accent-n-iris-9"
              :checked="transferCascade.emails"
              @change="transferCascade.emails = !transferCascade.emails"
            />
            一并转移客户邮件
          </label>
        </div>
      </div>
    </Dialog>

    <!-- 共享客户 -->
    <Dialog
      ref="shareDialogRef"
      title="共享客户"
      confirm-button-color="iris"
      @confirm="saveShare"
    >
      <div class="flex flex-col gap-3">
        <p class="text-xs text-n-slate-10">
          被共享的成员可查看该客户（不改变归属）。
        </p>
        <div
          class="flex flex-col gap-1 p-2 overflow-y-auto border rounded-lg max-h-64 border-n-weak"
        >
          <label
            v-for="m in shareCandidates"
            :key="m.id"
            class="flex items-center gap-2.5 px-2 py-1.5 rounded-md cursor-pointer hover:bg-n-alpha-1"
          >
            <input
              type="checkbox"
              class="accent-n-iris-9"
              :checked="shareUserIds.includes(m.id)"
              @change="toggleShareUser(m.id)"
            />
            <span class="text-sm text-n-slate-12">{{ m.name }}</span>
          </label>
          <p
            v-if="!shareCandidates.length"
            class="px-2 py-4 text-sm text-center text-n-slate-10"
          >
            暂无可共享成员
          </p>
        </div>
      </div>
    </Dialog>
  </div>
</template>
