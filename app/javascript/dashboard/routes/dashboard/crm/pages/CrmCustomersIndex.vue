<script setup>
/* global axios */
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCrmCustomersStore } from 'dashboard/stores/crm/customers';

import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import CrmCustomerCreateDialog from 'dashboard/components-next/CRM/CrmCustomerCreateDialog.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';

// 与后端 CustomersController::RESULTS_PER_PAGE 保持一致。
const ITEMS_PER_PAGE = 15;

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { accountId, accountScopedRoute } = useAccount();
const customersStore = useCrmCustomersStore();

const actingId = ref(null);

const createDialogRef = ref(null);
// 私海(private)/公海(public_pool) 由侧边栏入口经 ?filter= 驱动；默认私海。
const activeFilter = ref(route.query.filter || 'private');
const activeCustomerGroup = ref('');
const activeProductGroup = ref('');
const activeSourceChannel = ref('');
const currentPage = ref(1);
const sortKey = ref(''); // '' = 默认(更新时间倒序)；'deal_amount' = 累计成交额
const sortDir = ref('desc');
const searchQuery = ref('');
const teams = ref([]);
const selectedTeamId = ref('');
const selectedOwnerId = ref('');

const customers = computed(() => customersStore.getCustomers);
const uiFlags = computed(() => customersStore.getUIFlags);
const isFetching = computed(() => uiFlags.value.fetchingList);
const isCreating = computed(() => uiFlags.value.creatingItem);
const totalCount = computed(() => customersStore.getMeta.count || 0);

// 客户分组 / 产品分组下拉（空值 = 全部）；标签与建档/编辑弹窗保持一致。
const customerGroupOptions = [
  { value: '', label: t('CRM.CUSTOMERS.FILTERS.ALL_CUSTOMER_GROUP') },
  { value: 'KEY_ACCOUNT_WON', label: '成交重点客户' },
  { value: 'WON', label: '成交客户' },
  { value: 'SAMPLE_WON', label: '成交样品客户' },
  { value: 'NOT_WON', label: '未成交客户' },
  { value: 'SOCIAL_MEDIA', label: '社媒开发客户' },
];
const productGroupOptions = [
  { value: '', label: t('CRM.CUSTOMERS.FILTERS.ALL_PRODUCT_GROUP') },
  { value: 'TABLET', label: '平板电脑' },
  { value: 'COMMERCIAL_DISPLAY', label: '商显' },
  { value: 'INDUSTRIAL_CONTROL', label: '工控' },
];
// 客户来源下拉（空值 = 全部）；取值对齐 Crm::Customer::SOURCE_CHANNELS。
const sourceChannelOptions = [
  { value: '', label: t('CRM.CUSTOMERS.FILTERS.ALL_SOURCE_CHANNEL') },
  { value: 'ALIBABA', label: '阿里巴巴国际站' },
  { value: 'WEBSITE', label: '官网' },
  { value: 'EXHIBITION', label: '展会' },
  { value: 'REFERRAL', label: '转介绍' },
  { value: 'EMAIL', label: '邮件开发' },
  { value: 'OTHER', label: '其他' },
];

const fetchCustomers = () => {
  const filter = activeFilter.value === 'all' ? undefined : activeFilter.value;
  return customersStore.get({
    page: currentPage.value,
    filter,
    customer_group: activeCustomerGroup.value || undefined,
    product_group: activeProductGroup.value || undefined,
    source_channel: activeSourceChannel.value || undefined,
    q: searchQuery.value.trim() || undefined,
    team_id: selectedTeamId.value || undefined,
    account_owner_id: selectedOwnerId.value || undefined,
    sort: sortKey.value || undefined,
    direction: sortKey.value ? sortDir.value : undefined,
  });
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
  { value: '', label: '全部团队' },
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

const onPageChange = page => {
  currentPage.value = page;
  fetchCustomers();
};

// 新建统一走「客户建档」引导页(带查重 + 自动归私海)；弹窗只用于编辑。
const goToIntake = () =>
  router.push(accountScopedRoute('crm_customer_intake_index'));
const openEditDialog = record => createDialogRef.value?.open(record);

// 右侧详情面板：点行选中展开，编辑仍走弹窗。
const selectedCustomer = ref(null);
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
  newNote.value = '';
};
const closePanel = () => {
  selectedCustomer.value = null;
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

// 软色胶囊：浅底 + 同色文字，仿 Twenty 标签观感。
// 用字面量类名(Tailwind 只编译源码里出现的完整类名，动态拼接会被漏掉)。
const PILL = {
  teal: 'bg-n-teal-3 text-n-teal-11',
  blue: 'bg-n-blue-3 text-n-blue-11',
  amber: 'bg-n-amber-3 text-n-amber-11',
  ruby: 'bg-n-ruby-3 text-n-ruby-11',
  iris: 'bg-n-iris-3 text-n-iris-11',
  slate: 'bg-n-slate-4 text-n-slate-11',
};
const AVATAR = {
  blue: 'bg-n-blue-9 text-white',
  teal: 'bg-n-teal-9 text-white',
  iris: 'bg-n-iris-9 text-white',
  amber: 'bg-n-amber-9 text-white',
  ruby: 'bg-n-ruby-9 text-white',
};
const pillCls = color => PILL[color] || PILL.slate;

const GRADE_META = {
  COMPLETE: { label: '完善', color: 'teal' },
  GOOD: { label: '良好', color: 'blue' },
  FAIR: { label: '一般', color: 'amber' },
  POOR: { label: '待完善', color: 'ruby' },
};
const STATUS_META = {
  PROSPECT: { label: '潜在客户', color: 'slate' },
  FOLLOWING: { label: '跟进中', color: 'blue' },
  WON: { label: '成交客户', color: 'teal' },
  DORMANT: { label: '沉默客户', color: 'amber' },
  LOST: { label: '流失客户', color: 'ruby' },
};
const SOURCE_META = {
  ALIBABA: { label: '阿里巴巴国际站', color: 'amber' },
  WEBSITE: { label: '官网', color: 'blue' },
  EXHIBITION: { label: '展会', color: 'teal' },
  REFERRAL: { label: '转介绍', color: 'iris' },
  EMAIL: { label: '邮件开发', color: 'amber' },
  SOCIAL_MEDIA: { label: '社媒开发', color: 'ruby' },
  OTHER: { label: '其他', color: 'slate' },
};
const LEVEL_COLOR = { A: 'teal', B: 'blue', C: 'amber', D: 'slate' };
const REGION_META = {
  NORTH_AMERICA: { label: '北美', color: 'blue' },
  EUROPE: { label: '欧洲', color: 'iris' },
  SOUTH_AMERICA: { label: '南美', color: 'teal' },
  MIDDLE_EAST: { label: '中东', color: 'amber' },
  SOUTHEAST_ASIA: { label: '东南亚', color: 'ruby' },
  AFRICA: { label: '非洲', color: 'slate' },
  OTHER: { label: '其他', color: 'slate' },
};
// 国家 → 国旗+中文名（覆盖常用外贸目的国）
const COUNTRY_MAP = {
  USA: '🇺🇸 美国',
  GERMANY: '🇩🇪 德国',
  UK: '🇬🇧 英国',
  FRANCE: '🇫🇷 法国',
  ITALY: '🇮🇹 意大利',
  SPAIN: '🇪🇸 西班牙',
  CANADA: '🇨🇦 加拿大',
  AUSTRALIA: '🇦🇺 澳大利亚',
  JAPAN: '🇯🇵 日本',
  SOUTH_KOREA: '🇰🇷 韩国',
  INDIA: '🇮🇳 印度',
  RUSSIA: '🇷🇺 俄罗斯',
  BRAZIL: '🇧🇷 巴西',
  MEXICO: '🇲🇽 墨西哥',
  NETHERLANDS: '🇳🇱 荷兰',
  BELGIUM: '🇧🇪 比利时',
  UAE: '🇦🇪 阿联酋',
  SAUDI_ARABIA: '🇸🇦 沙特',
  SINGAPORE: '🇸🇬 新加坡',
  MALAYSIA: '🇲🇾 马来西亚',
  THAILAND: '🇹🇭 泰国',
  VIETNAM: '🇻🇳 越南',
  INDONESIA: '🇮🇩 印尼',
  PHILIPPINES: '🇵🇭 菲律宾',
  TURKEY: '🇹🇷 土耳其',
  SOUTH_AFRICA: '🇿🇦 南非',
  EGYPT: '🇪🇬 埃及',
  NIGERIA: '🇳🇬 尼日利亚',
  POLAND: '🇵🇱 波兰',
  SWEDEN: '🇸🇪 瑞典',
  TAIWAN: '🇹🇼 台湾',
  HONG_KONG: '🇭🇰 香港',
  PAKISTAN: '🇵🇰 巴基斯坦',
  BANGLADESH: '🇧🇩 孟加拉',
  OTHER: '🌍 其他',
};

const gradeMeta = c => GRADE_META[c.completenessGrade] || null;
const statusMeta = c => STATUS_META[c.customerStatus] || null;
const sourceMeta = c => SOURCE_META[c.sourceChannel] || null;
const regionMeta = c => REGION_META[c.tradeRegion] || null;
const levelColor = level => LEVEL_COLOR[level] || 'slate';
const countryLabel = country => COUNTRY_MAP[country] || country || '—';

// 公司首字母头像色：按名称哈希取一个稳定色
const AVATAR_COLORS = ['blue', 'teal', 'iris', 'amber', 'ruby'];
const avatarCls = name => {
  const key = (name || '?').charCodeAt(0) || 0;
  return AVATAR[AVATAR_COLORS[key % AVATAR_COLORS.length]];
};
const initial = name => (name || '?').trim().charAt(0).toUpperCase();

const money = micros =>
  micros ? `¥${Math.round(micros / 1_000_000).toLocaleString()}` : '¥0';

const formatDate = value => (value ? new Date(value).toLocaleDateString() : '');

const CUSTOMER_GROUP_LABELS = {
  KEY_ACCOUNT_WON: '成交重点客户',
  WON: '成交客户',
  SAMPLE_WON: '成交样品客户',
  NOT_WON: '未成交客户',
  SOCIAL_MEDIA: '社媒开发客户',
};
const PRODUCT_GROUP_LABELS = {
  TABLET: '平板电脑',
  COMMERCIAL_DISPLAY: '商显',
  INDUSTRIAL_CONTROL: '工控',
};

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
          label: '负责人',
          value: c.isInPublicPool ? '🌊 公海' : c.accountOwnerName || '未分配',
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
        { label: '客户分组', value: CUSTOMER_GROUP_LABELS[c.customerGroup] },
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
    {
      title: '备注',
      rows: [{ label: '备注', value: c.customerRemark, full: true }],
    },
  ];
});

onMounted(() => {
  fetchTeams();
  fetchCustomers();
});
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
  <div class="flex w-full h-full overflow-hidden bg-n-background">
    <div class="flex flex-col flex-1 min-w-0 overflow-hidden">
      <div
        class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak"
      >
        <h1 class="text-2xl font-semibold tracking-tight text-n-slate-12">
          {{ t('CRM.CUSTOMERS.HEADER') }}
        </h1>
        <Button
          :label="t('CRM.CUSTOMERS.NEW')"
          icon="i-lucide-plus"
          color="amber"
          @click="goToIntake"
        />
      </div>

      <div
        class="flex flex-wrap items-center gap-2 px-6 py-3 border-b border-n-weak"
      >
        <div class="flex flex-wrap items-center gap-2">
          <input
            v-model="searchQuery"
            type="text"
            placeholder="搜索客户名…"
            class="h-9 px-3 text-sm border rounded-lg w-44 border-n-weak bg-n-solid-1 text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-amber-9"
            @input="onSearchInput"
          />
          <Select
            :model-value="selectedTeamId"
            :options="teamOptions"
            @update:model-value="setTeam"
          />
          <Select
            v-if="selectedTeamId"
            :model-value="selectedOwnerId"
            :options="ownerOptions"
            @update:model-value="setOwner"
          />
          <Select
            :model-value="activeCustomerGroup"
            :options="customerGroupOptions"
            @update:model-value="setCustomerGroup"
          />
          <Select
            :model-value="activeProductGroup"
            :options="productGroupOptions"
            @update:model-value="setProductGroup"
          />
          <Select
            :model-value="activeSourceChannel"
            :options="sourceChannelOptions"
            @update:model-value="setSourceChannel"
          />
        </div>
      </div>

      <div class="flex-1 px-6 py-4 overflow-auto">
        <div
          v-if="isFetching"
          class="flex items-center justify-center p-8 text-base text-n-slate-11"
        >
          {{ t('CRM.CUSTOMERS.LOADING') }}
        </div>
        <div
          v-else-if="!customers.length"
          class="flex items-center justify-center p-8 text-base text-n-slate-11"
        >
          {{ t('CRM.CUSTOMERS.EMPTY') }}
        </div>
        <div
          v-else
          class="overflow-hidden border shadow-sm rounded-2xl border-n-weak bg-n-solid-1"
        >
          <div class="overflow-x-auto">
            <table class="w-full text-sm text-left border-collapse">
              <thead class="bg-n-alpha-1 text-n-slate-11">
                <tr class="border-b border-n-weak">
                  <th class="px-4 py-3 font-medium whitespace-nowrap">
                    {{ t('CRM.CUSTOMERS.TABLE.NAME') }}
                  </th>
                  <th class="px-4 py-3 font-medium whitespace-nowrap">
                    {{ t('CRM.CUSTOMERS.TABLE.GRADE') }}
                  </th>
                  <th
                    class="px-4 py-3 font-medium text-right whitespace-nowrap"
                  >
                    <button
                      class="inline-flex items-center gap-1 ml-auto transition-colors hover:text-n-slate-12"
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
                    class="px-4 py-3 font-medium text-right whitespace-nowrap"
                  >
                    {{ t('CRM.CUSTOMERS.TABLE.DEAL_COUNT') }}
                  </th>
                  <th class="px-4 py-3 font-medium whitespace-nowrap">
                    {{ t('CRM.CUSTOMERS.TABLE.STATUS') }}
                  </th>
                  <th class="px-4 py-3 font-medium whitespace-nowrap">
                    {{ t('CRM.CUSTOMERS.TABLE.LEVEL') }}
                  </th>
                  <th class="px-4 py-3 font-medium whitespace-nowrap">
                    {{ t('CRM.CUSTOMERS.TABLE.SOURCE') }}
                  </th>
                  <th class="px-4 py-3 font-medium whitespace-nowrap">
                    {{ t('CRM.CUSTOMERS.TABLE.COUNTRY') }}
                  </th>
                  <th class="px-4 py-3 font-medium whitespace-nowrap">
                    {{ t('CRM.CUSTOMERS.TABLE.REGION') }}
                  </th>
                  <th class="px-4 py-3 font-medium whitespace-nowrap">
                    {{ t('CRM.CUSTOMERS.TABLE.OWNER') }}
                  </th>
                  <th
                    class="px-4 py-3 font-medium text-right whitespace-nowrap"
                  >
                    {{ t('CRM.CUSTOMERS.TABLE.ACTION') }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="customer in customers"
                  :key="customer.id"
                  class="border-b cursor-pointer border-n-weak hover:bg-n-alpha-1"
                  :class="{
                    'bg-n-amber-2': selectedCustomer?.id === customer.id,
                  }"
                  @click="selectCustomer(customer)"
                >
                  <td class="px-4 py-3">
                    <div class="flex items-center gap-2 whitespace-nowrap">
                      <span
                        class="flex items-center justify-center flex-shrink-0 text-xs font-semibold rounded-lg w-6 h-6"
                        :class="avatarCls(customer.name)"
                      >
                        {{ initial(customer.name) }}
                      </span>
                      <span class="text-n-slate-12">{{ customer.name }}</span>
                    </div>
                  </td>
                  <td class="px-4 py-3">
                    <span
                      v-if="gradeMeta(customer)"
                      class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-xs whitespace-nowrap"
                      :class="pillCls(gradeMeta(customer).color)"
                    >
                      {{ gradeMeta(customer).label }}
                      <span class="opacity-70">{{
                        customer.infoCompletenessScore
                      }}</span>
                    </span>
                    <span v-else class="text-n-slate-10">—</span>
                  </td>
                  <td
                    class="px-4 py-3 text-right text-n-slate-11 whitespace-nowrap"
                  >
                    {{ money(customer.dealTotalAmountMicros) }}
                  </td>
                  <td class="px-4 py-3 text-right text-n-slate-11">
                    {{ customer.dealOrderCount || 0 }}
                  </td>
                  <td class="px-4 py-3">
                    <span
                      v-if="statusMeta(customer)"
                      class="inline-flex px-2 py-0.5 rounded-md text-xs whitespace-nowrap"
                      :class="pillCls(statusMeta(customer).color)"
                    >
                      {{ statusMeta(customer).label }}
                    </span>
                    <span v-else class="text-n-slate-10">—</span>
                  </td>
                  <td class="px-4 py-3">
                    <span
                      v-if="customer.customerLevel"
                      class="inline-flex items-center justify-center w-5 h-5 rounded text-xs font-medium"
                      :class="pillCls(levelColor(customer.customerLevel))"
                    >
                      {{ customer.customerLevel }}
                    </span>
                    <span v-else class="text-n-slate-10">—</span>
                  </td>
                  <td class="px-4 py-3">
                    <span
                      v-if="sourceMeta(customer)"
                      class="inline-flex px-2 py-0.5 rounded-md text-xs whitespace-nowrap"
                      :class="pillCls(sourceMeta(customer).color)"
                    >
                      {{ sourceMeta(customer).label }}
                    </span>
                    <span v-else class="text-n-slate-10">—</span>
                  </td>
                  <td class="px-4 py-3 text-n-slate-11 whitespace-nowrap">
                    {{ countryLabel(customer.tradeCountry) }}
                  </td>
                  <td class="px-4 py-3">
                    <span
                      v-if="regionMeta(customer)"
                      class="inline-flex px-2 py-0.5 rounded-md text-xs whitespace-nowrap"
                      :class="pillCls(regionMeta(customer).color)"
                    >
                      {{ regionMeta(customer).label }}
                    </span>
                    <span v-else class="text-n-slate-10">—</span>
                  </td>
                  <td class="px-4 py-3 whitespace-nowrap text-n-slate-11">
                    <span v-if="customer.isInPublicPool" class="text-n-blue-11">
                      🌊 公海
                    </span>
                    <span v-else-if="customer.accountOwnerName">
                      {{ customer.accountOwnerName }}
                    </span>
                    <span v-else class="text-n-slate-10">未分配</span>
                  </td>
                  <td class="px-4 py-3 text-right" @click.stop>
                    <Button
                      v-if="customer.isInPublicPool"
                      :label="t('CRM.CUSTOMERS.POOL.CLAIM')"
                      size="sm"
                      color="amber"
                      :is-loading="actingId === customer.id"
                      @click="claimCustomer(customer)"
                    />
                    <Button
                      v-else
                      :label="t('CRM.CUSTOMERS.POOL.RELEASE')"
                      size="sm"
                      variant="faded"
                      color="slate"
                      :is-loading="actingId === customer.id"
                      @click="releaseCustomer(customer)"
                    />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <PaginationFooter
        v-if="totalCount > ITEMS_PER_PAGE"
        :current-page="currentPage"
        :total-items="totalCount"
        :items-per-page="ITEMS_PER_PAGE"
        class="flex-shrink-0"
        @update:current-page="onPageChange"
      />
    </div>

    <!-- 右侧客户详情面板 -->
    <aside
      v-if="selectedCustomer"
      class="flex flex-col w-[400px] flex-shrink-0 overflow-hidden border-l border-n-weak bg-n-solid-1"
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
              ? 'border-n-amber-9 text-n-slate-12 font-medium'
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
            <Button label="添加" color="amber" size="sm" @click="addNote" />
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
          color="amber"
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
  </div>
</template>
