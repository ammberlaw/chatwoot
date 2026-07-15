<script setup>
/* global axios */
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCrmSalesOrdersStore } from 'dashboard/stores/crm/salesOrders';
import { useCrmRole } from 'dashboard/composables/useCrmRole';
import { useMapGetter } from 'dashboard/composables/store';
import CrmMemberAPI from 'dashboard/api/crm/members';

import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import CrmSalesOrderCreateDialog from 'dashboard/components-next/CRM/CrmSalesOrderCreateDialog.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';

// 与后端 SalesOrdersController::RESULTS_PER_PAGE 保持一致。
const ITEMS_PER_PAGE = 15;

const { t } = useI18n();
const route = useRoute();
const { accountId } = useAccount();
const store = useCrmSalesOrdersStore();

const createDialogRef = ref(null);
const { isCrmSales, isCrmManager } = useCrmRole();
const currentUserForFilter = useMapGetter('getCurrentUser');
// 普通业务只看个人订单：无「全部」视图，默认落在「我的」（未关联客户视图保留）。
const normalizeFilter = value =>
  isCrmSales.value && (!value || value === 'all') ? 'mine' : value || 'all';
const activeFilter = ref(normalizeFilter(route.query.filter));
const activeStatus = ref('');
const currentPage = ref(1);
const searchQuery = ref('');
const activeOwnerId = ref('');
const activeMonth = ref('');
const agents = ref([]);

const records = computed(() => store.getRecords);
const uiFlags = computed(() => store.getUIFlags);
const isFetching = computed(() => uiFlags.value.fetchingList);
const isCreating = computed(() => uiFlags.value.creatingItem);
const totalCount = computed(() => store.getMeta.count || 0);

const crmBase = () => `/api/v1/accounts/${accountId.value}/crm`;

const STATUSES = {
  PENDING_CONFIRMATION: { label: '待确认', class: 'bg-n-slate-3 text-n-slate-11' },
  IN_PRODUCTION: { label: '生产中', class: 'bg-n-blue-3 text-n-blue-11' },
  PENDING_SHIPMENT: { label: '待出货', class: 'bg-n-iris-3 text-n-iris-11' },
  SHIPPED: { label: '已出货', class: 'bg-n-iris-3 text-n-iris-11' },
  COMPLETED: { label: '已完成', class: 'bg-n-teal-3 text-n-teal-11' },
  CANCELLED: { label: '已取消', class: 'bg-n-ruby-3 text-n-ruby-11' },
};

const filterTabs = computed(() => [
  ...(isCrmSales.value
    ? []
    : [{ key: 'all', label: t('CRM.SALES_ORDERS.FILTERS.ALL') }]),
  { key: 'mine', label: t('CRM.SALES_ORDERS.FILTERS.MINE') },
]);

// 状态筛选下拉，空值 = 全部状态；标签复用上面的 STATUSES 定义。
const statusFilterOptions = [
  { value: '', label: t('CRM.SALES_ORDERS.FILTERS.ALL_STATUS') },
  ...Object.entries(STATUSES).map(([value, { label }]) => ({ value, label })),
];

// 业务员下拉（空值 = 全部业务员），取自账号成员。
const ownerFilterOptions = computed(() => [
  { value: '', label: t('CRM.SALES_ORDERS.FILTERS.ALL_OWNER') },
  ...agents.value.map(a => ({ value: String(a.id), label: a.name })),
]);
// 部门主管：业务员下拉只列自己团队（本人 + 下属，成员接口已按辖区收口）；管理员列全账号成员。
const fetchAgents = async () => {
  try {
    if (isCrmManager.value) {
      const { data } = await CrmMemberAPI.get();
      const me = currentUserForFilter.value || {};
      agents.value = [
        { id: me.id, name: `${me.name}（我）` },
        ...(data.payload || [])
          .filter(m => m.user_id !== me.id)
          .map(m => ({ id: m.user_id, name: m.name })),
      ];
      return;
    }
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/agents`
    );
    agents.value = data || [];
  } catch {
    agents.value = [];
  }
};

const fetchRecords = () => {
  const filter = activeFilter.value === 'all' ? undefined : activeFilter.value;
  store.get({
    page: currentPage.value,
    filter,
    status: activeStatus.value || undefined,
    owner_id: activeOwnerId.value || undefined,
    month: activeMonth.value || undefined,
    q: searchQuery.value.trim() || undefined,
  });
};

const setFilter = key => {
  activeFilter.value = key;
  currentPage.value = 1;
  fetchRecords();
};

// 订单号 / 客户 / 名称搜索（300ms 防抖）
let searchTimer = null;
const onSearchInput = () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => {
    currentPage.value = 1;
    fetchRecords();
  }, 300);
};

const onPageChange = page => {
  currentPage.value = page;
  fetchRecords();
};

const setStatus = value => {
  activeStatus.value = value;
  currentPage.value = 1;
  fetchRecords();
};

const setOwner = value => {
  activeOwnerId.value = value;
  currentPage.value = 1;
  fetchRecords();
};

const onMonthChange = () => {
  currentPage.value = 1;
  fetchRecords();
};

const openCreateDialog = () => createDialogRef.value?.open();
const openEditDialog = record => createDialogRef.value?.open(record);

const createRecord = async payload => {
  try {
    await store.create(payload);
    createDialogRef.value?.onSuccess();
    useAlert(t('CRM.SALES_ORDERS.CREATE.SUCCESS'));
  } catch {
    useAlert(t('CRM.SALES_ORDERS.CREATE.ERROR'));
  }
};

const updateRecord = async payload => {
  try {
    const updated = await store.update(payload);
    createDialogRef.value?.onSuccess();
    if (updated && selectedOrder.value?.id === updated.id) {
      selectedOrder.value = updated;
      panelAudits.value = [];
    }
    useAlert(t('CRM.SALES_ORDERS.EDIT.SUCCESS'));
  } catch {
    useAlert(t('CRM.SALES_ORDERS.EDIT.ERROR'));
  }
};

const CURRENCY_SYMBOL = { CNY: '¥', USD: '$', EUR: '€' };
const fmtMoney = (micros, currency) =>
  micros == null
    ? '—'
    : `${CURRENCY_SYMBOL[currency] || ''}${Math.round(micros / 1_000_000).toLocaleString()}`;
const fmtDate = value => (value ? new Date(value).toLocaleDateString() : '—');
const fmtDateTime = v => (v ? new Date(v).toLocaleString() : '');

const AVATAR = [
  'bg-n-blue-9',
  'bg-n-teal-9',
  'bg-n-iris-9',
  'bg-n-iris-9',
  'bg-n-ruby-9',
];
const avatarCls = name =>
  AVATAR[((name || '?').charCodeAt(0) || 0) % AVATAR.length];
const initial = name => (name || '?').trim().charAt(0).toUpperCase();

// ── 右侧订单详情面板（点行展开；编辑仍走弹窗）──
const PANEL_TABS = [
  { key: 'fields', label: '详情', icon: 'i-lucide-house' },
  { key: 'timeline', label: '操作历史', icon: 'i-lucide-history' },
];
const selectedOrder = ref(null);
const activeTab = ref('fields');
const panelAudits = ref([]);
const tabLoading = ref(false);

const detailSections = computed(() => {
  const o = selectedOrder.value;
  if (!o) return [];
  const statusMeta = STATUSES[o.status];
  return [
    {
      title: '基本信息',
      rows: [
        { label: 'PI号', value: o.name },
        { label: '订单号', value: o.orderNo },
        {
          label: '状态',
          tag: statusMeta
            ? { text: statusMeta.label, cls: statusMeta.class }
            : null,
        },
        { label: '负责人', value: o.ownerName },
        { label: '下单日期', value: o.orderDate ? fmtDate(o.orderDate) : null },
        {
          label: '交期',
          value: o.deliveryDate ? fmtDate(o.deliveryDate) : null,
        },
      ],
    },
    {
      title: '金额',
      rows: [
        { label: '订单金额', value: fmtMoney(o.orderAmountMicros, o.orderCurrency) },
        { label: '币种', value: o.orderCurrency },
        {
          label: '汇率',
          value: o.exchangeRate != null ? String(o.exchangeRate) : null,
        },
      ],
    },
    {
      title: '关联',
      rows: [{ label: '客户', value: o.customerName }],
    },
    {
      title: '备注',
      rows: [{ label: '备注', value: o.remark, full: true }],
    },
  ];
});

const AUDIT_LABELS = {
  name: 'PI号',
  order_no: '订单号',
  status: '状态',
  order_date: '下单日期',
  delivery_date: '交期',
  order_amount_micros: '订单金额',
  order_currency: '币种',
  exchange_rate: '汇率',
  crm_customer_id: '关联客户',
  crm_opportunity_id: '关联商机',
  crm_quote_id: '关联报价',
  crm_team_id: '团队',
  owner_id: '负责人',
  remark: '备注',
  cost_amount_micros: '成本',
  profit_amount_micros: '利润',
  profit_rate: '利润率',
};
const auditMessage = a => {
  const who = a.user_name;
  if (a.action === 'create') return `${who} 创建了订单`;
  const fields = (a.changed_fields || [])
    .filter(f => AUDIT_LABELS[f])
    .map(f => AUDIT_LABELS[f]);
  return fields.length
    ? `${who} 编辑了 ${fields.join('、')}`
    : `${who} 更新了订单`;
};

const fetchAudits = async () => {
  const { data } = await axios.get(
    `${crmBase()}/sales_orders/${selectedOrder.value.id}/audits`
  );
  panelAudits.value = data.payload || [];
};
const setTab = async key => {
  activeTab.value = key;
  if (!selectedOrder.value) return;
  if (key === 'timeline') {
    tabLoading.value = true;
    try {
      await fetchAudits();
    } catch {
      panelAudits.value = [];
    } finally {
      tabLoading.value = false;
    }
  }
};

const selectOrder = record => {
  selectedOrder.value = record;
  activeTab.value = 'fields';
  panelAudits.value = [];
};
const closePanel = () => {
  selectedOrder.value = null;
};

onMounted(() => {
  fetchRecords();
  fetchAgents();
});
watch(
  () => route.query.filter,
  value => {
    activeFilter.value = normalizeFilter(value);
    currentPage.value = 1;
    closePanel();
    fetchRecords();
  }
);
</script>

<template>
  <div class="flex w-full h-full overflow-hidden bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5">
    <div class="flex flex-col flex-1 min-w-0 overflow-hidden">
      <div
        class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak"
      >
        <h1 class="text-2xl font-semibold tracking-tight text-n-slate-12">
          {{ t('CRM.SALES_ORDERS.HEADER') }}
        </h1>
        <Button
          :label="t('CRM.SALES_ORDERS.NEW')"
          icon="i-lucide-plus"
          color="iris"
          @click="openCreateDialog"
        />
      </div>

      <div
        class="flex flex-wrap items-center gap-2 px-6 py-3 border-b border-n-weak"
      >
        <Button
          v-for="tab in filterTabs"
          :key="tab.key"
          :label="tab.label"
          size="sm"
          :variant="activeFilter === tab.key ? 'solid' : 'faded'"
          :color="activeFilter === tab.key ? 'iris' : 'slate'"
          @click="setFilter(tab.key)"
        />
        <div class="w-px h-6 mx-1 bg-n-weak" />
        <input
          v-model="searchQuery"
          type="text"
          :placeholder="t('CRM.SALES_ORDERS.SEARCH_PLACEHOLDER')"
          class="reset-base h-9 px-3 text-sm border rounded-lg w-44 border-n-weak bg-n-solid-1 text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-9"
          @input="onSearchInput"
        />
        <input
          v-model="activeMonth"
          type="month"
          :aria-label="t('CRM.SALES_ORDERS.FILTERS.MONTH')"
          class="reset-base h-9 px-3 text-sm border rounded-lg w-36 border-n-weak bg-n-solid-1 text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-9"
          @change="onMonthChange"
        />
        <Select
          v-if="!isCrmSales"
          :model-value="activeOwnerId"
          :options="ownerFilterOptions"
          @update:model-value="setOwner"
        />
        <Select
          :model-value="activeStatus"
          :options="statusFilterOptions"
          @update:model-value="setStatus"
        />
      </div>

      <div class="flex-1 px-6 py-4 overflow-auto">
        <div
          v-if="isFetching"
          class="flex items-center justify-center p-8 text-base text-n-slate-11"
        >
          {{ t('CRM.SALES_ORDERS.LOADING') }}
        </div>
        <div
          v-else-if="!records.length"
          class="flex items-center justify-center p-8 text-base text-n-slate-11"
        >
          {{ t('CRM.SALES_ORDERS.EMPTY') }}
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
                    {{ t('CRM.SALES_ORDERS.TABLE.NAME') }}
                  </th>
                  <th class="px-4 py-3 font-medium whitespace-nowrap">
                    {{ t('CRM.SALES_ORDERS.TABLE.ORDER_NO') }}
                  </th>
                  <th class="px-4 py-3 font-medium whitespace-nowrap">
                    {{ t('CRM.SALES_ORDERS.TABLE.CUSTOMER') }}
                  </th>
                  <th class="px-4 py-3 font-medium whitespace-nowrap">
                    {{ t('CRM.SALES_ORDERS.TABLE.STATUS') }}
                  </th>
                  <th
                    class="px-4 py-3 font-medium text-right whitespace-nowrap"
                  >
                    {{ t('CRM.SALES_ORDERS.TABLE.AMOUNT') }}
                  </th>
                  <th class="px-4 py-3 font-medium whitespace-nowrap">
                    {{ t('CRM.SALES_ORDERS.TABLE.ORDER_DATE') }}
                  </th>
                  <th class="px-4 py-3 font-medium whitespace-nowrap">
                    {{ t('CRM.SALES_ORDERS.TABLE.DELIVERY_DATE') }}
                  </th>
                  <th class="px-4 py-3 font-medium whitespace-nowrap">
                    {{ t('CRM.SALES_ORDERS.TABLE.OWNER') }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="record in records"
                  :key="record.id"
                  class="border-b cursor-pointer border-n-weak hover:bg-n-alpha-1"
                  :class="{
                    'bg-n-iris-2': selectedOrder?.id === record.id,
                  }"
                  @click="selectOrder(record)"
                >
                  <td
                    class="px-4 py-3 font-medium text-n-slate-12 whitespace-nowrap"
                  >
                    {{ record.name }}
                  </td>
                  <td class="px-4 py-3 text-n-slate-11 whitespace-nowrap">
                    {{ record.orderNo }}
                  </td>
                  <td class="px-4 py-3 text-n-slate-11 whitespace-nowrap">
                    {{ record.customerName || '—' }}
                  </td>
                  <td class="px-4 py-3 whitespace-nowrap">
                    <span
                      class="px-2 py-0.5 rounded-md text-xs font-medium"
                      :class="STATUSES[record.status]?.class"
                    >
                      {{ STATUSES[record.status]?.label || record.status }}
                    </span>
                  </td>
                  <td
                    class="px-4 py-3 font-semibold text-right tabular-nums text-n-slate-12 whitespace-nowrap"
                  >
                    {{ fmtMoney(record.orderAmountMicros, record.orderCurrency) }}
                  </td>
                  <td class="px-4 py-3 text-n-slate-11 whitespace-nowrap">
                    {{ fmtDate(record.orderDate) }}
                  </td>
                  <td class="px-4 py-3 text-n-slate-11 whitespace-nowrap">
                    {{ fmtDate(record.deliveryDate) }}
                  </td>
                  <td class="px-4 py-3 whitespace-nowrap">
                    <span
                      v-if="record.ownerName"
                      class="inline-flex items-center gap-1.5 text-n-slate-11"
                    >
                      <span
                        class="flex items-center justify-center w-5 h-5 text-xs font-semibold text-white rounded"
                        :class="avatarCls(record.ownerName)"
                      >
                        {{ initial(record.ownerName) }}
                      </span>
                      {{ record.ownerName }}
                    </span>
                    <span v-else class="text-n-slate-10">—</span>
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

    <!-- 右侧订单详情面板 -->
    <aside
      v-if="selectedOrder"
      class="flex flex-col w-[400px] flex-shrink-0 overflow-hidden border-l border-n-weak bg-n-solid-1"
    >
      <div class="flex items-center gap-3 px-5 py-4 border-b border-n-weak">
        <div class="flex-1 min-w-0">
          <div class="font-semibold truncate text-n-slate-12">
            {{ selectedOrder.name }}
          </div>
          <div class="text-xs text-n-slate-10">
            {{ selectedOrder.orderNo }}
          </div>
        </div>
        <Button
          :label="t('CRM.SALES_ORDERS.EDIT.TITLE')"
          icon="i-lucide-pencil"
          size="sm"
          color="slate"
          variant="faded"
          @click="openEditDialog(selectedOrder)"
        />
        <button
          class="p-1 rounded-md text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-1"
          @click="closePanel"
        >
          <span class="i-lucide-x size-5" />
        </button>
      </div>

      <!-- 标签栏 -->
      <div class="flex px-2 border-b border-n-weak">
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
        <!-- 详情：字段 -->
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
                <span class="w-16 shrink-0 text-n-slate-10">
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

          <!-- 附件 -->
          <div class="px-5 py-4">
            <div
              class="mb-3 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
            >
              {{ t('CRM.SALES_ORDERS.ATTACH.TITLE') }}
            </div>
            <div
              v-if="!selectedOrder.files || !selectedOrder.files.length"
              class="text-sm text-n-slate-10"
            >
              —
            </div>
            <a
              v-for="file in selectedOrder.files"
              :key="file.id"
              :href="file.url"
              target="_blank"
              rel="noopener noreferrer"
              class="flex items-center gap-2 px-3 py-2 mb-1.5 text-sm border rounded-lg border-n-weak text-n-blue-11 hover:underline"
            >
              <span class="i-lucide-file size-4 shrink-0" />
              <span class="truncate">{{ file.filename }}</span>
            </a>
          </div>
        </template>

        <div
          v-else-if="tabLoading"
          class="py-10 text-sm text-center text-n-slate-10"
        >
          加载中…
        </div>

        <!-- 操作历史 -->
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
                class="z-10 mt-1 border-2 rounded-full size-2.5 shrink-0 border-n-iris-9 bg-n-solid-1"
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
      </div>
    </aside>

    <CrmSalesOrderCreateDialog
      ref="createDialogRef"
      :is-loading="isCreating"
      @create="createRecord"
      @update="updateRecord"
      @refresh="fetchRecords"
    />
  </div>
</template>
