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
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import CrmAgentAPI from 'dashboard/api/crm/crmAgents';
import SalesOrdersAPI from 'dashboard/api/crm/salesOrders';
import { isClassicTheme } from 'dashboard/components-next/CRM/charts/chartColors';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import MonthPicker from 'dashboard/components-next/monthpicker/MonthPicker.vue';
import CrmSalesOrderCreateDialog from 'dashboard/components-next/CRM/CrmSalesOrderCreateDialog.vue';

// 与后端 SalesOrdersController::RESULTS_PER_PAGE 保持一致。
const ITEMS_PER_PAGE = 15;

const { t } = useI18n();
const route = useRoute();
const { accountId } = useAccount();
const store = useCrmSalesOrdersStore();

const createDialogRef = ref(null);
const { isCrmSales, isCrmTeamLead } = useCrmRole();
// 删除：负责人本人可删自己的单；管理员/副管可删任意 + 用回收箱。
const currentUser = useMapGetter('getCurrentUser');
const isAdmin = computed(
  () =>
    currentUser.value?.role === 'administrator' ||
    currentUser.value?.crm_role === 'deputy_admin'
);
const canDeleteSelected = computed(
  () => isAdmin.value || selectedOrder.value?.ownerId === currentUser.value?.id
);
// 能看「本人以外」的订单：管理员/副管理员/部门主管，或 CRM 团队负责人（订单按 CRM 团队收口）。
const canViewTeam = computed(() => !isCrmSales.value || isCrmTeamLead.value);
// 纯业务员只看个人订单：无「全部」视图，默认落在「我的」（未关联客户视图保留）。
const normalizeFilter = value =>
  !canViewTeam.value && (!value || value === 'all') ? 'mine' : value || 'all';
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
// 自绘分页器（还原效果图页脚）：共 N 条 · 每页 15 条 + ‹ 页码 ›
const totalPages = computed(() =>
  Math.max(1, Math.ceil(totalCount.value / ITEMS_PER_PAGE))
);
// 页码窗口化：页多时首页 … 当前±1 … 末页，避免一长排按钮。
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

const crmBase = () => `/api/v1/accounts/${accountId.value}/crm`;

const isClassic = ref(isClassicTheme());
// 状态配色：仅经典灰用不褪色语义色(金/紫/绿/实心绿终态)；其它主题保持原始 blue/iris/teal（不同步）。
const STATUSES = computed(() => {
  const c = isClassic.value;
  return {
    PENDING_CONFIRMATION: {
      label: '待确认',
      class: 'bg-n-slate-3 text-n-slate-11',
    },
    IN_PRODUCTION: {
      label: '生产中',
      class: c ? 'bg-n-amber-3 text-n-amber-11' : 'bg-n-blue-3 text-n-blue-11',
    },
    PENDING_SHIPMENT: {
      label: '待出货',
      class: c ? 'bg-n-violet-3 text-n-violet-11' : 'bg-n-iris-3 text-n-iris-11',
    },
    SHIPPED: {
      label: '已出货',
      class: c ? 'bg-n-teal-3 text-n-teal-11' : 'bg-n-iris-3 text-n-iris-11',
    },
    COMPLETED: {
      label: '已完成',
      class: c ? 'bg-n-teal-9 text-white' : 'bg-n-teal-3 text-n-teal-11',
    },
    CANCELLED: { label: '已取消', class: 'bg-n-ruby-3 text-n-ruby-11' },
  };
});

// 视图 tab（我的/全部）带计数：计数取自列表 meta 的 mineCount/allCount。
const filterTabs = computed(() => {
  const meta = store.getMeta;
  return [
    ...(canViewTeam.value
      ? [
          {
            key: 'all',
            label: t('CRM.SALES_ORDERS.FILTERS.ALL'),
            count: meta.allCount,
          },
        ]
      : []),
    {
      key: 'mine',
      label: t('CRM.SALES_ORDERS.FILTERS.MINE'),
      count: meta.mineCount,
    },
  ];
});

// 状态筛选下拉，空值 = 全部状态；标签复用上面的 STATUSES 定义。
const statusFilterOptions = [
  { value: '', label: t('CRM.SALES_ORDERS.FILTERS.ALL_STATUS') },
  ...Object.entries(STATUSES.value).map(([value, { label }]) => ({
    value,
    label,
  })),
];

// 业务员下拉（空值 = 全部业务员），取自账号成员。
const ownerFilterOptions = computed(() => [
  { value: '', label: t('CRM.SALES_ORDERS.FILTERS.ALL_OWNER') },
  ...agents.value.map(a => ({ value: String(a.id), label: a.name })),
]);
// 业务员下拉只列 CRM 成员，按 CRM 团队口径收口（与订单可见范围一致）：
// 业务员=自己、团队负责人=本团队、管理员=全部 CRM 成员。
const fetchAgents = async () => {
  try {
    const { data } = await CrmAgentAPI.get(accountId.value, 'team');
    agents.value = data.payload || [];
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

// 明细副行文案：「规格 · 数量 × 单价」，符号放进 JS 避免模板裸字符串。
const itemMeta = li => {
  const qty = li.quantity != null ? li.quantity : '—';
  const price = li.unitPrice != null ? li.unitPrice : '—';
  const prefix = li.spec ? `${li.spec} · ` : '';
  return `${prefix}${qty} × ${price}`;
};
const itemAmount = li => (li.amount != null ? String(li.amount) : '—');

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
  const statusMeta = STATUSES.value[o.status];
  return [
    {
      title: '基本信息',
      rows: [
        { label: '名称', value: o.name },
        { label: 'PI号', value: o.piNo, copyable: true },
        { label: '订单号', value: o.orderNo, copyable: true },
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
        {
          label: '订单金额',
          value: fmtMoney(o.orderAmountMicros, o.orderCurrency),
        },
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
  name: '订单名称',
  pi_no: 'PI号',
  order_no: '订单号',
  line_items: '订单明细',
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

// 一键复制 PI号 / 订单号（详情面板字段行的复制按钮）。
const copyValue = async (label, value) => {
  if (!value) return;
  await copyTextToClipboard(String(value));
  useAlert(`已复制${label}`);
};

// 删除销售订单（删重复单）：软删进回收箱，管理员可恢复。负责人本人/管理员可删。
const deleteOrder = async () => {
  const order = selectedOrder.value;
  if (!order) return;
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      `确定删除销售订单「${order.name || order.orderNo}」？将移入回收箱，管理员可恢复。`
    )
  ) {
    return;
  }
  try {
    await store.delete(order.id);
    useAlert('已移入回收箱');
    closePanel();
  } catch (e) {
    useAlert(e?.response?.data?.error || '删除失败');
  }
};

// ── 回收箱（仅管理员/副管）：已删订单列表 + 恢复 ──
const binDialogRef = ref(null);
const binOrders = ref([]);
const binLoading = ref(false);
const openBin = async () => {
  binDialogRef.value?.open();
  binLoading.value = true;
  try {
    const { data } = await SalesOrdersAPI.deleted();
    binOrders.value = data.payload || [];
  } catch (e) {
    useAlert(e?.response?.data?.error || '加载回收箱失败');
  } finally {
    binLoading.value = false;
  }
};
const restoreOrder = async id => {
  try {
    await SalesOrdersAPI.restore(id);
    binOrders.value = binOrders.value.filter(o => o.id !== id);
    useAlert('已恢复');
    fetchRecords();
  } catch (e) {
    useAlert(e?.response?.data?.error || '恢复失败');
  }
};
const fmtBinAmount = o => {
  if (o.amount_micros == null) return '—';
  const v = Math.round(o.amount_micros / 1_000_000).toLocaleString();
  return `${o.currency || ''} ${v}`;
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

// 从客户详情跳来时带 ?focus=<id>，列表加载后自动打开该订单面板（仅一次）。
const focusOpened = ref(false);
watch(
  records,
  list => {
    if (focusOpened.value || !route.query.focus) return;
    const rec = list.find(r => String(r.id) === String(route.query.focus));
    if (rec) {
      selectOrder(rec);
      focusOpened.value = true;
    }
  },
  { immediate: true }
);
</script>

<template>
  <div
    class="flex w-full h-full overflow-hidden bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div class="flex flex-col flex-1 min-w-0 overflow-hidden">
      <!-- 标题 + 新建订单 -->
      <div
        class="flex items-center justify-between px-[26px] pt-[18px] pb-3.5 border-b border-n-weak"
      >
        <h1 class="text-[22px] font-bold tracking-[-0.01em] text-n-slate-12">
          {{ t('CRM.SALES_ORDERS.HEADER') }}
        </h1>
        <div class="flex items-center gap-2">
          <button
            v-if="isAdmin"
            type="button"
            title="回收箱"
            class="inline-flex items-center gap-1.5 h-[34px] px-3 text-[13px] font-medium rounded-[9px] border border-n-weak text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
            @click="openBin"
          >
            <span class="i-lucide-trash-2 size-4" />
            回收箱
          </button>
          <button
            type="button"
            class="inline-flex items-center gap-1.5 h-[34px] px-3.5 text-[13px] font-medium text-white rounded-[9px] bg-gradient-to-br from-n-iris-9 to-n-accent-grad shadow-lg shadow-n-iris-9/30 hover:brightness-105"
            @click="openCreateDialog"
          >
            <span class="i-lucide-plus size-4" />
            {{ t('CRM.SALES_ORDERS.NEW') }}
          </button>
        </div>
      </div>

      <!-- 筛选工具条 -->
      <div class="flex flex-wrap items-center gap-2.5 px-[26px] pt-3.5 pb-2.5">
        <div
          class="flex items-center flex-1 min-w-[200px] h-[38px] gap-2 px-3 text-[13px] border rounded-[10px] border-n-weak bg-n-solid-1/60 focus-within:ring-2 focus-within:ring-n-iris-9"
        >
          <span class="i-lucide-search size-4 shrink-0 text-n-slate-9" />
          <input
            v-model="searchQuery"
            type="text"
            :placeholder="t('CRM.SALES_ORDERS.SEARCH_PLACEHOLDER')"
            class="flex-1 h-full bg-transparent reset-base text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none"
            @input="onSearchInput"
          />
        </div>
        <MonthPicker
          v-model="activeMonth"
          trigger-class="h-[38px]"
          @change="onMonthChange"
        />
        <SelectCard
          :model-value="activeStatus"
          :options="statusFilterOptions"
          trigger-class="h-[38px]"
          @update:model-value="setStatus"
        />
        <SelectCard
          v-if="canViewTeam"
          :model-value="activeOwnerId"
          :options="ownerFilterOptions"
          trigger-class="h-[38px]"
          @update:model-value="setOwner"
        />
      </div>

      <!-- 视图下划线 tab -->
      <div
        v-if="filterTabs.length > 1"
        class="flex items-center gap-[22px] px-[26px] pt-0.5 border-b border-n-weak"
      >
        <button
          v-for="tab in filterTabs"
          :key="tab.key"
          type="button"
          class="relative flex items-center gap-[7px] py-2.5 text-[13.5px] transition-colors"
          :class="
            activeFilter === tab.key
              ? 'font-semibold text-n-iris-11'
              : 'text-n-slate-10 hover:text-n-slate-12'
          "
          @click="setFilter(tab.key)"
        >
          {{ tab.label }}
          <span
            v-if="tab.count != null"
            class="px-[7px] py-px text-[11px] rounded-full tabular-nums"
            :class="
              activeFilter === tab.key
                ? 'bg-n-iris-4 text-n-iris-11'
                : 'bg-n-slate-3 text-n-slate-11'
            "
          >
            {{ tab.count }}
          </span>
          <span
            v-if="activeFilter === tab.key"
            class="absolute inset-x-0 -bottom-px h-0.5 rounded-full bg-n-iris-9"
          />
        </button>
      </div>

      <div class="flex-1 px-3.5 py-1.5 overflow-auto">
        <div
          v-if="isFetching"
          class="flex items-center justify-center p-8 text-sm text-n-slate-11"
        >
          {{ t('CRM.SALES_ORDERS.LOADING') }}
        </div>
        <div
          v-else-if="!records.length"
          class="flex items-center justify-center p-8 text-sm text-n-slate-11"
        >
          {{ t('CRM.SALES_ORDERS.EMPTY') }}
        </div>
        <table v-else class="w-full text-[13px] border-collapse">
          <thead>
            <tr>
              <th
                class="px-3 py-2.5 text-left text-[11.5px] font-semibold text-n-slate-10 whitespace-nowrap"
              >
                {{ t('CRM.SALES_ORDERS.TABLE.NAME') }}
              </th>
              <th
                class="px-3 py-2.5 text-left text-[11.5px] font-semibold text-n-slate-10 whitespace-nowrap"
              >
                {{ t('CRM.SALES_ORDERS.TABLE.ORDER_NO') }}
              </th>
              <th
                class="px-3 py-2.5 text-left text-[11.5px] font-semibold text-n-slate-10 whitespace-nowrap"
              >
                {{ t('CRM.SALES_ORDERS.TABLE.CUSTOMER') }}
              </th>
              <th
                class="px-3 py-2.5 text-left text-[11.5px] font-semibold text-n-slate-10 whitespace-nowrap"
              >
                {{ t('CRM.SALES_ORDERS.TABLE.STATUS') }}
              </th>
              <th
                class="px-3 py-2.5 text-right text-[11.5px] font-semibold text-n-slate-10 whitespace-nowrap"
              >
                {{ t('CRM.SALES_ORDERS.TABLE.AMOUNT') }}
              </th>
              <th
                class="px-3 py-2.5 text-left text-[11.5px] font-semibold text-n-slate-10 whitespace-nowrap"
              >
                {{ t('CRM.SALES_ORDERS.TABLE.ORDER_DATE') }}
              </th>
              <th
                class="px-3 py-2.5 text-left text-[11.5px] font-semibold text-n-slate-10 whitespace-nowrap"
              >
                {{ t('CRM.SALES_ORDERS.TABLE.DELIVERY_DATE') }}
              </th>
              <th
                class="px-3 py-2.5 text-left text-[11.5px] font-semibold text-n-slate-10 whitespace-nowrap"
              >
                {{ t('CRM.SALES_ORDERS.TABLE.OWNER') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="record in records"
              :key="record.id"
              class="border-t cursor-pointer border-n-weak hover:bg-n-iris-9/[0.04]"
              :class="{ 'bg-n-iris-2': selectedOrder?.id === record.id }"
              @click="selectOrder(record)"
            >
              <td
                class="px-3 py-3 font-semibold text-n-slate-12 whitespace-nowrap"
              >
                {{ record.piNo || record.name }}
              </td>
              <td
                class="px-3 py-3 font-mono text-[12px] text-n-slate-10 whitespace-nowrap"
              >
                {{ record.orderNo }}
              </td>
              <td class="px-3 py-3 text-n-slate-12 whitespace-nowrap">
                {{ record.customerName || '—' }}
              </td>
              <td class="px-3 py-3 whitespace-nowrap">
                <span
                  class="inline-flex items-center gap-[5px] px-2.5 py-[3px] rounded-full text-[12px] font-medium"
                  :class="STATUSES[record.status]?.class"
                >
                  <span class="rounded-full size-1.5 bg-current opacity-90" />
                  {{ STATUSES[record.status]?.label || record.status }}
                </span>
              </td>
              <td
                class="px-3 py-3 font-semibold text-right tabular-nums text-n-slate-12 whitespace-nowrap"
              >
                {{ fmtMoney(record.orderAmountMicros, record.orderCurrency) }}
              </td>
              <td
                class="px-3 py-3 tabular-nums text-n-slate-10 whitespace-nowrap"
              >
                {{ fmtDate(record.orderDate) }}
              </td>
              <td
                class="px-3 py-3 tabular-nums text-n-slate-10 whitespace-nowrap"
              >
                {{ fmtDate(record.deliveryDate) }}
              </td>
              <td class="px-3 py-3 whitespace-nowrap">
                <div v-if="record.ownerName" class="flex flex-col gap-0.5">
                  <span class="inline-flex items-center gap-2 text-n-slate-11">
                    <Avatar
                      :name="record.ownerName"
                      :src="record.ownerAvatarUrl || ''"
                      :size="26"
                      rounded-full
                    />
                    {{ record.ownerName }}
                  </span>
                  <span
                    v-if="
                      record.handledByName &&
                      record.handledById !== record.ownerId
                    "
                    class="pl-[34px] text-[11px] text-n-slate-10"
                  >
                    经办：{{ record.handledByName }}
                  </span>
                </div>
                <span v-else class="text-n-slate-10">—</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- 页脚：共 N 条 · 每页 15 条 + 页码 -->
      <div
        v-if="totalCount"
        class="flex items-center justify-between px-[26px] py-3 border-t border-n-weak text-[12.5px] text-n-slate-10"
      >
        <span>
          {{
            t('CRM.SALES_ORDERS.FOOTER_COUNT', {
              total: totalCount,
              per: ITEMS_PER_PAGE,
            })
          }}
        </span>
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
        <Button
          v-if="canDeleteSelected"
          label="删除"
          icon="i-lucide-trash-2"
          size="sm"
          color="ruby"
          variant="faded"
          @click="deleteOrder"
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
                  <button
                    v-if="row.copyable && row.value"
                    v-tooltip.top="`复制${row.label}`"
                    class="shrink-0 p-1 rounded-md text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-1"
                    @click="copyValue(row.label, row.value)"
                  >
                    <span class="i-lucide-copy size-3.5" />
                  </button>
                  <span v-if="!row.tag && !row.value" class="text-n-slate-10"
                    >—</span
                  >
                </div>
              </div>
            </div>
          </div>

          <!-- 订单明细 -->
          <div
            v-if="selectedOrder.lineItems && selectedOrder.lineItems.length"
            class="px-5 py-4 border-b border-n-weak"
          >
            <div
              class="mb-3 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
            >
              {{ t('CRM.SALES_ORDERS.FORM.SECTION_ITEMS') }}
            </div>
            <div class="flex flex-col gap-2">
              <div
                v-for="(li, i) in selectedOrder.lineItems"
                :key="i"
                class="flex flex-col gap-0.5 pb-2 border-b border-dashed last:border-0 border-n-weak"
              >
                <div class="flex items-center justify-between gap-2 text-sm">
                  <span class="font-medium truncate text-n-slate-12">
                    {{ li.name }}
                  </span>
                  <span class="shrink-0 text-n-slate-11 tabular-nums">
                    {{ itemAmount(li) }}
                  </span>
                </div>
                <div class="text-xs text-n-slate-10">
                  {{ itemMeta(li) }}
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

    <!-- 回收箱（管理员/副管）：已删订单，可恢复 -->
    <Dialog
      ref="binDialogRef"
      title="订单回收箱"
      description="已删除的销售订单，管理员可恢复。"
      :show-cancel-button="false"
      :show-confirm-button="false"
      width="2xl"
    >
      <div class="max-h-[60vh] overflow-auto -mx-1">
        <div
          v-if="binLoading"
          class="py-10 text-sm text-center text-n-slate-10"
        >
          加载中…
        </div>
        <div
          v-else-if="!binOrders.length"
          class="py-10 text-sm text-center text-n-slate-10"
        >
          回收箱是空的
        </div>
        <table v-else class="w-full">
          <thead>
            <tr class="text-[11.5px] text-n-slate-10">
              <th class="px-2 py-2 font-medium text-left">订单</th>
              <th class="px-2 py-2 font-medium text-left">客户</th>
              <th class="px-2 py-2 font-medium text-right">金额</th>
              <th class="px-2 py-2 font-medium text-left">负责人</th>
              <th class="px-2 py-2 font-medium text-left">删除</th>
              <th class="px-2 py-2" />
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="o in binOrders"
              :key="o.id"
              class="border-t border-n-weak text-[13px]"
            >
              <td class="px-2 py-2.5">
                <div class="font-medium text-n-slate-12">{{ o.name }}</div>
                <div class="text-[11px] text-n-slate-10">{{ o.order_no }}</div>
              </td>
              <td class="px-2 py-2.5 text-n-slate-11">
                {{ o.customer_name || '—' }}
              </td>
              <td
                class="px-2 py-2.5 font-semibold text-right tabular-nums text-n-slate-12"
              >
                {{ fmtBinAmount(o) }}
              </td>
              <td class="px-2 py-2.5 text-n-slate-11">
                {{ o.owner_name || '—' }}
              </td>
              <td class="px-2 py-2.5 text-[11px] text-n-slate-10">
                {{ o.deleted_by_name || '—' }}
              </td>
              <td class="px-2 py-2.5 text-right">
                <button
                  type="button"
                  class="inline-flex items-center gap-1 h-7 px-2.5 text-[12px] font-medium rounded-md border border-n-weak text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
                  @click="restoreOrder(o.id)"
                >
                  <span class="i-lucide-rotate-ccw size-3.5" />
                  恢复
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </Dialog>
  </div>
</template>
