<script setup>
/* global axios */
import { ref, computed, reactive, onMounted, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import camelcaseKeys from 'camelcase-keys';
import MesOrderStockEntriesDialog from 'dashboard/components-next/mes/MesOrderStockEntriesDialog.vue';
import MesProductPicker from 'dashboard/components-next/mes/MesProductPicker.vue';
import { useMesProductionOrdersStore } from 'dashboard/stores/mes/productionOrders';
import MesProductionOrderAPI from 'dashboard/api/mes/productionOrders';
import MesBomAPI from 'dashboard/api/mes/boms';
import { useMesRole } from 'dashboard/composables/useMesRole';
import { useOrderableColumns } from 'dashboard/composables/useOrderableColumns';
import { useCrmRole } from 'dashboard/composables/useCrmRole';
import {
  SPEC_TEMPLATES,
  blankSpec,
  specFieldsFor,
} from 'dashboard/routes/dashboard/mes/pages/orderSpecFields';

import Button from 'dashboard/components-next/button/Button.vue';
import {
  exportNodeToJpg,
  exportDataToExcel,
  printNode,
} from 'dashboard/helper/mesExport';
import MesOrderSpecForm from 'dashboard/components-next/mes/MesOrderSpecForm.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';
import { useRouteQueryReentry } from 'dashboard/composables/useRouteQueryReentry';

const ITEMS_PER_PAGE = 15;

const { accountId, accountScopedRoute } = useAccount();
const route = useRoute();
const router = useRouter();
const { mesCan } = useMesRole();
const { isAdmin, isCrmDeputyAdmin, isCrmTeamLead, isCrmSales, currentUser } =
  useCrmRole();
const currentUserId = useMapGetter('getCurrentUserID');
// 业务角色可建定制单（草稿→三级审批）；备货单/从销售订单转入仍仅 order 能力。
// 与后端 ProductionOrderPolicy#create? 同口径，后端 403 兜底。
const canCreateOrder = computed(
  () => mesCan('order') || currentUser.value?.can_access_crm !== false
);
// CRM 业务身份（业务员/主管/管理员）：「我的订单」「待我确认」tab 只对他们有内容；
// 纯 MES 操作岗（车间/仓管/PMC 等，无 CRM 角色）两个 tab 永远为空，不展示。
const isCrmMember = computed(() => currentUser.value?.can_access_crm !== false);
// 纯业务员（CRM 业务身份，非主管/团队负责人）：只看本人数据。对其隐藏「全部」页签
// 与「全部业务员」筛选下拉——名册对业务员是泄露，且选别人也被后端过滤为空。
// 管理员/副管理员/主管/团队负责人 及 非 CRM 操作岗（车间/仓管/采购/PMC）不受限，照旧全看。
const isPlainSales = computed(
  () => isCrmMember.value && isCrmSales.value && !isCrmTeamLead.value
);
const canSeeAllScope = computed(() => !isPlainSales.value);
// MES 员工（管理员/副管理员 或 有 mes_roles）：与后端 AccountUser#mes_staff? 同口径。
// 供应商/关联采购单含供应商与采购信息，销售端不可见（生态硬约束），仅 MES 员工可见。
const isMesStaff = computed(
  () =>
    isAdmin.value ||
    isCrmDeputyAdmin.value ||
    (currentUser.value?.mes_roles || []).length > 0
);
const store = useMesProductionOrdersStore();

// 8 阶段（与后端 Mes::ProductionOrder::STAGES 顺序一致）。
const STAGES = [
  { value: 'SALES_CONFIRMED', label: '待工程接单' },
  { value: 'BOM_READY', label: '工程/PMC 生产任务单' },
  { value: 'PURCHASING', label: '采购原料' },
  { value: 'MATERIAL_INBOUND', label: '原料入库' },
  { value: 'PICKING', label: '生产领料' },
  { value: 'PRODUCTION', label: '生产' },
  { value: 'FG_INBOUND', label: '成品入库' },
  { value: 'SHIPPED', label: '销售出库' },
];
const STATUS_LABELS = {
  IN_PROGRESS: '进行中',
  COMPLETED: '已完成',
  STOPPED: '已终止',
  CANCELLED: '已取消',
};
// 关联采购单状态（一单多采购单：主料/辅料各一张）。
const PO_STATUS_LABELS = {
  DRAFT: '草稿',
  SUBMITTED: '已提交',
  PARTIAL_RECEIVED: '部分到料',
  RECEIVED: '已到料',
  CANCELLED: '已作废',
};
const poStatusLabel = s => PO_STATUS_LABELS[s] || s;
// 齐套进度：未作废采购单中已到料齐（RECEIVED）的张数 / 总张数。全部到齐才推进到原料入库。
const poKitSummary = pos => {
  const active = (pos || []).filter(p => p.status !== 'CANCELLED');
  const received = active.filter(p => p.status === 'RECEIVED').length;
  return {
    received,
    total: active.length,
    complete: active.length > 0 && received === active.length,
  };
};
// 阶段芯片配色：8 个阶段各一色（原来统一 bg-n-iris-3，一眼看不出订单走到哪一步，
// 经典灰下更是整条 iris 被压成灰）。参照 CRM 的 PI 状态芯片做法：浅底 + 同色深字。
//
// 直接写色值、不用 --iris/--blue 这类 token：蓝 / beebot / 经典灰三套主题都重映射了 iris，
// 经典灰还把 blue 压成灰——用 token 的话同一个阶段在四套配色里会显示成不同颜色甚至全灰。
// 阶段色是流程语义、跟配色主题无关，所以与主题解耦，四套配色下完全一致。
// 色序按流程走：灰(待接) → 紫(设计) → 琥珀/橙(采购到料) → 蓝/靛(车间) → 青/绿(完工出货)。
const STAGE_CHIP = {
  SALES_CONFIRMED:
    'bg-[#eceef2] text-[#4f5665] dark:bg-[#2b2e35] dark:text-[#b6bac4]',
  BOM_READY:
    'bg-[#efe9fd] text-[#5f3fb8] dark:bg-[#312a4d] dark:text-[#c3b2f5]',
  PURCHASING:
    'bg-[#fdf0d5] text-[#8a5f00] dark:bg-[#3d3011] dark:text-[#f0c35a]',
  MATERIAL_INBOUND:
    'bg-[#ffe7d8] text-[#9a4a18] dark:bg-[#402618] dark:text-[#f0a878]',
  PICKING: 'bg-[#e0eeff] text-[#12508f] dark:bg-[#16304d] dark:text-[#84b8f0]',
  PRODUCTION:
    'bg-[#e5e7ff] text-[#4040c4] dark:bg-[#26284d] dark:text-[#a3a5f2]',
  FG_INBOUND:
    'bg-[#e5f2ec] text-[#2b7255] dark:bg-[#14332a] dark:text-[#6fc2a0]',
  SHIPPED: 'bg-[#e4f3e0] text-[#37702f] dark:bg-[#1c3318] dark:text-[#89c97e]',
};
const stageChip = value => STAGE_CHIP[value] || 'bg-n-slate-3 text-n-slate-11';

const stageIndex = value => STAGES.findIndex(s => s.value === value);
const stageLabel = value => STAGES[stageIndex(value)]?.label || value;
// 外购按单短版脊柱：时间线只显示 销售订单确定 → 采购 → 成品入库 → 出库。
const OUTSOURCE_STAGE_VALUES = [
  'SALES_CONFIRMED',
  'PURCHASING',
  'FG_INBOUND',
  'SHIPPED',
];

// 阶段进度点：列表里只看得到「当前在哪一环」，看不出这单走到几成了——
// 十几行扫下来分不清哪些刚起步、哪些快出货。这里给一排点，深=走过、黄=当前、灰=未到。
//
// 点数按**这张单自己的脊柱**算：外购单走短流程（销售订单确定→采购→成品入库→出库，
// 跳过 BOM/领料/报工/质检），写死 8 个点会让外购单永远显示「跳了 4 步」，看着像卡住。
const stageFlowOf = po =>
  po?.isOutsourced
    ? STAGES.filter(st => OUTSOURCE_STAGE_VALUES.includes(st.value))
    : STAGES;

// 当前阶段在本单脊柱里的位置（0 基）。找不到按 -1，全部显示为未到。
const stageIndexOf = po =>
  stageFlowOf(po).findIndex(st => st.value === po?.stage);

const stageDotClass = (po, idx) => {
  const cur = stageIndexOf(po);
  if (cur < 0) return 'bg-n-slate-5';
  if (idx < cur) return 'bg-n-iris-9';
  if (idx === cur) return 'bg-n-amber-9 ring-2 ring-n-amber-4';
  return 'bg-n-slate-5';
};
const stageProgressText = po => {
  const flow = stageFlowOf(po);
  const cur = stageIndexOf(po);
  return cur < 0 ? '' : `已走 ${cur + 1}/${flow.length}`;
};

// 列顺序可拖（和生产任务单列表同一套，按人记在本机）。
const COLUMN_DEFS = [
  {
    key: 'no',
    label: '工单号',
    tdClass: 'px-3 py-3 font-medium text-n-slate-12',
  },
  {
    key: 'model',
    label: '型号',
    tdClass: 'px-3 py-3 text-n-slate-11 max-w-[14rem]',
  },
  {
    key: 'qty',
    label: '数量',
    tdClass: 'px-3 py-3 text-n-slate-11 whitespace-nowrap',
  },
  {
    key: 'stage',
    label: '阶段',
    tdClass: 'px-3 py-3 align-top min-w-[16rem]',
  },
  { key: 'due', label: '交期', tdClass: 'px-3 py-3 text-xs whitespace-nowrap' },
  {
    key: 'sku',
    label: '商品编码',
    tdClass: 'px-3 py-3 text-n-slate-11 tabular-nums whitespace-nowrap',
  },
  // 对标金蝶生产任务单的那几列：规格、入库进度、领料与完工状态。
  {
    key: 'spec',
    label: '规格型号',
    tdClass: 'px-3 py-3 text-n-slate-11 max-w-[14rem] truncate',
  },
  {
    key: 'inboundQty',
    label: '已入库',
    tdClass:
      'px-3 py-3 text-right tabular-nums whitespace-nowrap text-n-slate-11',
  },
  {
    key: 'pendingQty',
    label: '未入库',
    tdClass:
      'px-3 py-3 text-right tabular-nums whitespace-nowrap text-n-slate-11',
  },
  {
    key: 'issueState',
    label: '领料状态',
    tdClass: 'px-3 py-3 whitespace-nowrap',
  },
  {
    key: 'doneState',
    label: '完工状态',
    tdClass: 'px-3 py-3 whitespace-nowrap',
  },
  {
    key: 'remark',
    label: '备注',
    tdClass: 'px-3 py-3 text-n-slate-11 max-w-[12rem]',
  },
  {
    key: 'salesOrder',
    label: '来源销售单',
    tdClass: 'px-3 py-3 text-n-slate-11 whitespace-nowrap',
  },
  {
    key: 'owner',
    label: '负责人',
    tdClass: 'px-3 py-3 text-n-slate-11 whitespace-nowrap',
  },
];
const {
  orderedColumns,
  visibleColumns,
  hiddenKeys,
  isHidden,
  toggleColumn,
  showAllColumns,
  isDragging,
  onColDragStart,
  onColDrop,
  resetOrder,
} = useOrderableColumns(COLUMN_DEFS, 'mes.orderCols.v1');

// 14 列撑得比屏幕宽，只能靠底下那根细横条拖——触控板还行，鼠标很难受。
// 与其想办法把横滑做顺手，不如让它不用横滑：把平时不看的列收起来，按人记在本机。
const showColumnPanel = ref(false);
const hiddenCols = computed(() => hiddenKeys.value.length);

// 未入库量：订单数量 − 已完工入库量（后端 fg_inbound_qty 只认已过账的成品入库单）。
const pendingQty = po => {
  const left = Number(po.qty || 0) - Number(po.fgInboundQty || 0);
  return left > 0 ? Number(left.toFixed(3)) : 0;
};
const pendingCls = po => (pendingQty(po) > 0 ? 'text-n-amber-11' : '');
// 领料状态只认已过账的领料单：草稿不算领过（和入库口径一致）。
const issueState = po =>
  po.issuedEntryCount > 0
    ? { label: `已领料 ${po.issuedEntryCount} 单`, cls: 'text-n-teal-11' }
    : { label: '未领料', cls: 'text-n-slate-10' };
// 完工状态按「已入库量 / 订单量」判，不看阶段——阶段是人推的，入库量是真发生的。
const doneState = po => {
  const done = Number(po.fgInboundQty || 0);
  if (done <= 0) return { label: '未入库', cls: 'text-n-slate-10' };
  return done >= Number(po.qty || 0)
    ? { label: '已完工', cls: 'text-n-teal-11' }
    : { label: '部分入库', cls: 'text-n-amber-11' };
};

const records = computed(() => store.getRecords);
const uiFlags = computed(() => store.getUIFlags);
const isFetching = computed(() => uiFlags.value.fetchingList);
const converting = computed(() => uiFlags.value.creatingItem);
const totalCount = computed(() => store.getMeta.count || 0);

const activeStage = ref('');
const activeStatus = ref('');
const activeOwner = ref('');
const searchQuery = ref(route.query.q ? String(route.query.q) : '');
const currentPage = ref(1);

const stageFilterOptions = [
  { value: '', label: '全部阶段' },
  ...STAGES.map(s => ({ value: s.value, label: s.label })),
];
const statusFilterOptions = [
  { value: '', label: '全部状态' },
  ...Object.entries(STATUS_LABELS).map(([value, label]) => ({ value, label })),
];
// 业务员（订单归属人）筛选：取账号成员。
const agents = useMapGetter('agents/getAgents');
const ownerFilterOptions = computed(() => [
  { value: '', label: '全部业务员' },
  ...(agents.value || []).map(a => ({ value: String(a.id), label: a.name })),
]);

// —— 详情面板选中项（提前声明：视图切换要清空它）——
const selected = ref(null);
// 外购单时间线用短版脊柱（依赖 selected，故定义在其后）。
const timelineStages = computed(() =>
  selected.value?.isOutsourced
    ? STAGES.filter(s => OUTSOURCE_STAGE_VALUES.includes(s.value))
    : STAGES
);
const timelineStageIndex = value =>
  timelineStages.value.findIndex(s => s.value === value);

// 视图：all 列表（再按 listScope 分档）/ inbox 待我确认（停在我这一级的审批单）。
const viewMode = ref('all');
// 列表分档：mine 我的订单 / stock 库存备货 / all 全部（可见范围内）。
const listScope = ref('all');
const fetchRecords = () => {
  if (viewMode.value === 'inbox') return store.fetchApprovalInbox();
  return store.get({
    page: currentPage.value,
    list_scope: listScope.value,
    stage: activeStage.value || undefined,
    status: activeStatus.value || undefined,
    owner_id: activeOwner.value || undefined,
    q: searchQuery.value.trim() || undefined,
  });
};
const setViewMode = m => {
  if (viewMode.value === m) return;
  viewMode.value = m;
  currentPage.value = 1;
  selected.value = null;
  fetchRecords();
};
// 列表分档 tab（我的订单/库存备货/全部）：切到列表视图并换档。
const setListScope = s => {
  if (viewMode.value === 'all' && listScope.value === s) return;
  viewMode.value = 'all';
  listScope.value = s;
  currentPage.value = 1;
  selected.value = null;
  fetchRecords();
};
const tabActive = (mode, scope) =>
  mode === 'inbox'
    ? viewMode.value === 'inbox'
    : viewMode.value === 'all' && listScope.value === scope;

let searchTimer = null;
const onSearchInput = () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => {
    currentPage.value = 1;
    fetchRecords();
  }, 300);
};

// —— 详情面板 ——
const selectRow = row => {
  selected.value = selected.value?.id === row.id ? null : row;
};

// 「查看」：看建单时填的**订单明细（定制规格表）**，只读弹窗（区别于右侧流程面板）。
const detailDialogRef = ref(null);
const detailContentRef = ref(null);
const viewingOrder = ref(null);
const viewTemplate = computed(() => {
  const o = viewingOrder.value;
  if (!o) return 'TABLET';
  return (
    o.spec?.template ||
    (SPEC_TEMPLATES[o.productLine] ? o.productLine : 'TABLET')
  );
});
const viewSpec = computed(() => ({
  ...blankSpec(viewTemplate.value),
  ...(viewingOrder.value?.spec || {}),
}));
const viewBaseFields = computed(() => {
  const o = viewingOrder.value || {};
  return [
    { label: '工单号', value: o.orderNo },
    { label: '成品', value: o.productName },
    { label: '数量', value: `${o.qty ?? ''} ${o.unit ?? ''}` },
    { label: 'PI 编号', value: o.piNo || '—' },
    { label: '商品编码', value: o.productSku || '—' },
    { label: '归属业务员', value: o.ownerName || '—' },
    {
      label: '交期',
      value: o.deliveryDate ? String(o.deliveryDate).slice(0, 10) : '—',
    },
  ];
});
const openDetail = row => {
  viewingOrder.value = row;
  detailDialogRef.value?.open();
  // 拉最新详情，补全转发目标(阶段负责人)与已知会留痕（列表行不带这些，避免 N+1）。
  MesProductionOrderAPI.show(row.id)
    .then(({ data }) => {
      if (viewingOrder.value?.id === row.id) {
        viewingOrder.value = camelcaseKeys(data, { deep: true });
      }
    })
    .catch(() => {});
};

// —— 业务转发/知会：把订单知会给某阶段负责人 + 附言，推站内通知并留痕 ——
const forwardDialogRef = ref(null);
const forwardBoardKey = ref('');
const forwardNote = ref('');
const forwardBusy = ref(false);
const forwardOptions = computed(() =>
  (viewingOrder.value?.forwardTargets || []).map(t => ({
    value: t.boardKey,
    label: t.recipientNames?.length
      ? `${t.label}（${t.recipientNames.join('、')}）`
      : `${t.label}（未配置负责人）`,
    disabled: !t.recipientNames?.length,
  }))
);
const openForward = () => {
  forwardBoardKey.value = '';
  forwardNote.value = '';
  forwardDialogRef.value?.open();
};
const submitForward = async () => {
  if (!forwardBoardKey.value) {
    useAlert('请选择要知会的阶段负责人');
    return;
  }
  forwardBusy.value = true;
  try {
    const { data } = await MesProductionOrderAPI.forward(
      viewingOrder.value.id,
      {
        board_key: forwardBoardKey.value,
        note: forwardNote.value,
      }
    );
    viewingOrder.value = camelcaseKeys(data, { deep: true });
    forwardDialogRef.value?.close();
    useAlert('已知会该阶段负责人');
  } catch (e) {
    useAlert(e?.response?.data?.error || '知会失败');
  } finally {
    forwardBusy.value = false;
  }
};
// 导出订单明细（Excel = 基本信息 + 规格键值；图片 = 明细区截图）。
const detailExportData = () => {
  const specRows = specFieldsFor(viewTemplate.value)
    .filter(f => !f.section)
    .map(f => {
      const v = viewSpec.value[f.key];
      return { label: f.label, value: Array.isArray(v) ? v.join('、') : v };
    })
    .filter(f => f.value !== undefined && f.value !== null && f.value !== '');
  return {
    title: viewingOrder.value?.orderNo
      ? `订单明细 ${viewingOrder.value.orderNo}`
      : '订单明细',
    fields: [...viewBaseFields.value, ...specRows],
  };
};
const exportDetailExcel = () => {
  const d = detailExportData();
  exportDataToExcel(d, d.title);
};
const exportDetailJpg = () =>
  exportNodeToJpg(detailContentRef.value, detailExportData().title);
const printDetail = () =>
  printNode(detailContentRef.value, detailExportData().title);
// 各阶段到达时间（stage → 日期字符串）。
const stageTime = stageValue => {
  const ev = (selected.value?.stageEvents || []).find(
    e => e.stage === stageValue
  );
  return ev?.enteredAt ? new Date(ev.enteredAt).toLocaleDateString() : '';
};

const DAY = 86400000;
const STALL_DAYS = 3; // 当前阶段滞留超此天数即预警
const DUE_SOON_DAYS = 3; // 距交期内此天数算临近

// 各阶段耗时：相邻事件时间差；当前(最后)阶段算「已 N 天」。
const stageDurationLabel = stageValue => {
  const evs = [...(selected.value?.stageEvents || [])].sort(
    (a, b) => new Date(a.enteredAt) - new Date(b.enteredAt)
  );
  const idx = evs.findIndex(e => e.stage === stageValue);
  if (idx === -1) return '';
  const start = new Date(evs[idx].enteredAt);
  const isCurrent = idx === evs.length - 1;
  const end = isCurrent ? Date.now() : new Date(evs[idx + 1].enteredAt);
  const days = Math.max(0, Math.round((end - start) / DAY));
  if (!isCurrent) return `耗时 ${days} 天`;
  if (selected.value?.stage === 'SHIPPED') return '';
  // 完工入库收齐后订单转「生产完成」：当前(成品入库)阶段显示已完成·待出库，不再「进行中」。
  if (selected.value?.status === 'COMPLETED') return '已完成 · 待出库';
  return `进行中 · 已 ${days} 天`;
};

// 某阶段的接单/转交流水。一个阶段两人接力时（工程先出 BOM 再转 PMC 投单），
// 订单上的 stageAckBy 只剩最后一个人，这里把每一步都列出来。
const stageAckLog = stageValue =>
  (selected.value?.stageAckEvents || [])
    .filter(e => e.stage === stageValue)
    .map(e =>
      e.kind === 'HANDOFF'
        ? `${e.actorName} 转给 ${e.toUserName}${e.note ? `：${e.note}` : ''}`
        : `${e.actorName} 接单`
    );

// 当前阶段滞留天数（未出货才算）。
const stallDays = po => {
  if (!po || po.stage === 'SHIPPED' || po.status === 'COMPLETED') return 0;
  const ev = (po.stageEvents || []).find(e => e.stage === po.stage);
  if (!ev?.enteredAt) return 0;
  return Math.round((Date.now() - new Date(ev.enteredAt)) / DAY);
};
const isStalled = po => stallDays(po) >= STALL_DAYS;

// 列表阶段列的「等谁」：当前阶段负责人（未配则空；建单/出货阶段无板块负责人）。
// 列表阶段列的接单态徽标（与详情面板同口径）：已接单 / 超时未接单 / 待接单。
const ackChip = po => {
  if (!po || po.stage === 'SHIPPED') return null;
  if (po.stageAckAt)
    return {
      text: po.stageAckByName ? `✓ ${po.stageAckByName} 已接单` : '✓ 已接单',
      cls: 'text-n-teal-11',
    };
  if (po.ackOverdue) return { text: '超时未接单', cls: 'text-n-ruby-11' };
  if (po.awaitingAck) return { text: '待接单', cls: 'text-n-amber-11' };
  return null;
};

// 交期状态：已出货不预警；逾期红 / 临近橙 / 正常灰。
const deliveryStatus = po => {
  if (!po?.deliveryDate || po.stage === 'SHIPPED') return null;
  const days = Math.round((new Date(po.deliveryDate) - Date.now()) / DAY);
  if (days < 0) return { level: 'overdue', label: `已逾期 ${-days} 天` };
  if (days <= DUE_SOON_DAYS)
    return { level: 'soon', label: `距交期 ${days} 天` };
  return { level: 'ok', label: `距交期 ${days} 天` };
};
const DUE_CLASS = {
  overdue: 'text-n-ruby-11',
  soon: 'text-n-amber-11',
  ok: 'text-n-slate-11',
};

// —— 转单弹窗 ——
const convertDialogRef = ref(null);
const salesOrders = ref([]);
const products = ref([]);
const convertForm = ref({
  crmSalesOrderId: '',
  crmProductId: '',
  productName: '',
  qty: '',
  unit: '',
});
const { isDirty: isConvertDirty, markPristine: markConvertPristine } =
  useDirtyGuard(() => convertForm.value);

// 转单选销售订单：用 ComboBox（可搜索订单号 / PI / 客户），不含占位项。
const salesOrderOptions = computed(() =>
  salesOrders.value.map(o => ({
    value: String(o.id),
    label: `${o.order_no}${o.customer_name ? ` · ${o.customer_name}` : ''}`,
    searchText: `${o.pi_no || ''} ${o.customer_name || ''}`,
  }))
);
const productOptions = computed(() =>
  products.value.map(p => ({ value: String(p.id), label: p.name }))
);
const convertInvalid = computed(
  () => !convertForm.value.crmSalesOrderId || !Number(convertForm.value.qty)
);

const fetchPickerData = async () => {
  try {
    const [soRes, prodRes] = await Promise.all([
      axios.get(`/api/v1/accounts/${accountId.value}/crm/sales_orders`, {
        params: { per_page: 100 },
      }),
      axios.get(`/api/v1/accounts/${accountId.value}/mes/products`),
    ]);
    salesOrders.value = soRes.data?.payload || [];
    products.value = prodRes.data?.payload || prodRes.data || [];
  } catch {
    salesOrders.value = [];
    products.value = [];
  }
};

const openConvert = () => {
  convertForm.value = {
    crmSalesOrderId: '',
    crmProductId: '',
    productName: '',
    qty: '',
    unit: '',
  };
  if (!salesOrders.value.length) fetchPickerData();
  markConvertPristine();
  convertDialogRef.value?.open();
};

// 选成品时带出成品名默认值。
watch(
  () => convertForm.value.crmProductId,
  id => {
    const p = products.value.find(x => String(x.id) === String(id));
    if (p && !convertForm.value.productName)
      convertForm.value.productName = p.name;
  }
);

const submitConvert = async () => {
  if (convertInvalid.value) return;
  const ok = await store.convert({ ...convertForm.value });
  if (ok) {
    useAlert(`已生成生产订单 ${ok.orderNo}`);
    convertDialogRef.value?.close();
    fetchRecords();
  }
};

// —— 定制生产订单：按产品线模板填规格（新建 / 编辑规格）——
const orderDialogRef = ref(null);
const editingOrderId = ref(null);
const viewOnlyOrder = ref(false);
const orderTemplate = ref('TABLET');
const templateOptions = Object.entries(SPEC_TEMPLATES).map(([value, t]) => ({
  value,
  label: t.label,
}));
const orderBase = reactive({
  piNo: '',
  crmProductId: '',
  productName: '',
  qty: '',
  unit: '台',
  deliveryDate: '',
});
const { isDirty, markPristine } = useDirtyGuard(() => orderBase);
const orderSpec = ref(blankSpec('TABLET'));
// 商品编码选填：业务建单可不填，工程做 BOM 时再补（在编辑订单里补录）。
const orderInvalid = computed(
  () => !orderBase.productName.trim() || !Number(orderBase.qty)
);

// 编辑订单：商品编码选择器（关联产品档案，API 搜索）。用独立 state，与转单/外协的
// products 隔离互不干扰。产品档案数千条，输入即带 q 查后端、不本地全量加载。
const orderProducts = ref([]);
const selectedOrderProductLabel = ref('');
const orderProductLabel = p => {
  const base = p.sku ? `${p.sku} · ${p.name}` : p.name;
  return p.specification ? `${base} · ${p.specification}` : base;
};
const orderProductOptions = computed(() =>
  orderProducts.value.map(p => ({
    value: String(p.id),
    label: orderProductLabel(p),
    searchText: `${p.name} ${p.specification || ''}`,
  }))
);
const loadOrderProducts = async (q = '') => {
  try {
    const res = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/products`,
      { params: { q: q || undefined, per_page: 30 } }
    );
    orderProducts.value = res.data?.payload || res.data || [];
  } catch {
    orderProducts.value = [];
  }
};
let orderProductTimer = null;
const onOrderProductSearch = q => {
  clearTimeout(orderProductTimer);
  orderProductTimer = setTimeout(() => loadOrderProducts(q), 250);
};
const onOrderProductOpen = () => {
  if (!orderProducts.value.length) loadOrderProducts();
};
watch(
  () => orderBase.crmProductId,
  id => {
    const p = orderProducts.value.find(x => String(x.id) === String(id));
    if (p) {
      selectedOrderProductLabel.value = orderProductLabel(p);
      if (!orderBase.productName.trim()) orderBase.productName = p.name;
    }
  }
);
const setTemplate = t => {
  orderTemplate.value = t;
  orderSpec.value = blankSpec(t); // 换模板重置规格
};
const orderDialogTitle = computed(() => {
  if (viewOnlyOrder.value) return '查看生产订单';
  return editingOrderId.value ? '编辑生产订单' : '新建生产订单';
});
// 新建走整页建档页；本弹框仅用于编辑规格。
const openNewOrder = () =>
  router.push(accountScopedRoute('mes_production_order_intake_index'));
// viewOnly：非制单人且无 order 能力的人走「查看订单」，同一弹窗只读呈现（禁用录入、藏确认键）。
const openEditSpec = (order, { viewOnly = false } = {}) => {
  viewOnlyOrder.value = viewOnly;
  editingOrderId.value = order.id;
  orderTemplate.value =
    order.spec?.template ||
    (SPEC_TEMPLATES[order.productLine] ? order.productLine : 'TABLET');
  Object.assign(orderBase, {
    piNo: order.piNo || '',
    crmProductId: order.crmProductId ? String(order.crmProductId) : '',
    productName: order.productName || '',
    qty: String(order.qty ?? ''),
    unit: order.unit || '台',
    deliveryDate: order.deliveryDate
      ? String(order.deliveryDate).slice(0, 10)
      : '',
  });
  // 已关联产品名先兜底显示（下拉未加载时也有标签）；点开搜索改选后转 sku·名称。
  selectedOrderProductLabel.value = order.crmProductId
    ? order.productName || ''
    : '';
  orderProducts.value = [];
  orderSpec.value = {
    ...blankSpec(orderTemplate.value),
    ...(order.spec || {}),
    template: orderTemplate.value,
  };
  markPristine();
  orderDialogRef.value?.open();
};
const submitOrder = async () => {
  if (orderInvalid.value) return;
  const payload = {
    piNo: orderBase.piNo.trim() || undefined,
    // 清空要显式送 null：undefined 会被 JSON 序列化丢掉，后端收不到这个键就保留原值，
    // 表现为「清掉了、退出再进又回来」。crm_product_id 是选填(belongs_to optional)。
    crmProductId: orderBase.crmProductId
      ? Number(orderBase.crmProductId)
      : null,
    productName: orderBase.productName.trim(),
    qty: Number(orderBase.qty),
    unit: orderBase.unit,
    deliveryDate: orderBase.deliveryDate || undefined,
    productLine: orderTemplate.value,
    spec: orderSpec.value,
  };
  const ok = editingOrderId.value
    ? await store.update({ id: editingOrderId.value, ...payload })
    : await store.create(payload);
  if (ok) {
    useAlert(editingOrderId.value ? '订单已更新' : `已建单 ${ok.orderNo}`);
    if (editingOrderId.value) selected.value = ok;
    orderDialogRef.value?.close();
    fetchRecords();
  }
};

// —— 产品图片 / 附件上传 ——
const uploading = ref(false);
const onUpload = async (event, kind) => {
  const list = Array.from(event.target.files || []);
  event.target.value = '';
  if (!list.length) return;
  if (!selected.value) {
    useAlert('请先选中一张订单再上传');
    return;
  }
  const fd = new FormData();
  list.forEach(f => fd.append('files[]', f));
  uploading.value = true;
  try {
    const ok = await store.attachFiles({
      id: selected.value.id,
      formData: fd,
      kind,
    });
    if (ok) {
      selected.value = ok;
      useAlert(kind === 'images' ? '图片已上传' : '附件已上传');
    }
  } catch (e) {
    // eslint-disable-next-line no-console
    console.error('[MES upload] failed', e);
    useAlert(
      `上传失败：${e?.response?.data?.error || e?.message || '未知错误'}`
    );
  } finally {
    uploading.value = false;
  }
};
const removeAttachment = async (attachmentId, kind) => {
  const ok = await store.detachFile({
    id: selected.value.id,
    attachmentId,
    kind,
  });
  if (ok) selected.value = ok;
};

// 详情里要能看到工程做的用料清单：订单详情选中且已挂 BOM 时，按 bomId 拉 BOM 明细。
const CATEGORY_LABELS = { MACHINE: '整机物料', PACKAGING: '包装物料' };
const categoryLabel = c => CATEGORY_LABELS[c] || '整机物料';
const bomDetail = ref(null);
const bomViewDialogRef = ref(null);
const loadBomDetail = async id => {
  bomDetail.value = null;
  if (!id) return;
  try {
    const { data } = await MesBomAPI.show(id);
    bomDetail.value = camelcaseKeys(data, { deep: true });
  } catch {
    bomDetail.value = null;
  }
};
watch(() => selected.value?.bomId, loadBomDetail, { immediate: true });
const openBomView = () => bomViewDialogRef.value?.open();

// BOM 变更史展示：把 diff 数组拼成一行文案 + 时间格式化。
const revDiffText = (diff = []) =>
  diff
    .map(c => {
      const name = c.materialName || c.materialNo || '物料';
      if (c.kind === 'added') return `+${name} ${c.toQty}${c.unit || ''}`;
      if (c.kind === 'removed') return `-${name}`;
      return `${name} ${c.fromQty}→${c.toQty}${c.unit || ''}`;
    })
    .join('；');
const fmtRevTime = iso => {
  if (!iso) return '';
  const d = new Date(iso);
  const p = n => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
};

// 自产：不在订单页手动挂 BOM，而是跳到「工程 BOM」板块新建 BOM 并预关联本订单，
// 「保存并下发」即自动挂到本单（进 BOM_READY、通知业务员确认），无需回订单页操作。
const goCreateBomForOrder = () => {
  if (!selected.value) return;
  const o = selected.value;
  // 带上订单展示字段，BOM 弹窗即使可挂列表没有本单（状态/分页）也能注入并预选。
  router.push(
    accountScopedRoute(
      'mes_boms_index',
      {},
      {
        new_for_order: o.id,
        nfo_no: o.orderNo,
        nfo_product: o.productName,
        nfo_qty: o.qty,
        nfo_owner: o.ownerName || '',
      }
    )
  );
};

// —— 标记外购（工程判定为外购成品，跳过 BOM 直接进采购）——
const outsourceDialogRef = ref(null);
const suppliers = ref([]);
const outsourceForm = ref({
  crmProductId: '',
  supplierId: '',
  productName: '',
});
const supplierOptions = computed(() =>
  suppliers.value.map(s => ({ value: String(s.id), label: s.name }))
);
const outsourceInvalid = computed(
  () => !outsourceForm.value.crmProductId || !outsourceForm.value.supplierId
);
const openMarkOutsourced = async () => {
  outsourceForm.value = {
    crmProductId: selected.value?.crmProductId
      ? String(selected.value.crmProductId)
      : '',
    supplierId: '',
    productName: selected.value?.productName || '',
  };
  if (!suppliers.value.length) {
    try {
      const { data } = await axios.get(
        `/api/v1/accounts/${accountId.value}/mes/suppliers`,
        { params: { active: 'true', per_page: 500 } }
      );
      suppliers.value = data?.payload || data || [];
    } catch {
      suppliers.value = [];
    }
  }
  outsourceDialogRef.value?.open();
};
const submitMarkOutsourced = async () => {
  if (outsourceInvalid.value || !selected.value) return;
  const p = products.value.find(
    x => String(x.id) === outsourceForm.value.crmProductId
  );
  const ok = await store.markOutsourced({
    id: selected.value.id,
    crmProductId: Number(outsourceForm.value.crmProductId),
    mesSupplierId: Number(outsourceForm.value.supplierId),
    productName: p?.name || outsourceForm.value.productName || undefined,
  });
  if (ok) {
    useAlert('已标记外购，进入采购阶段');
    selected.value = ok;
    outsourceDialogRef.value?.close();
    fetchRecords();
  }
};

// —— 关联已有 BOM（复用现成 BOM 直接挂到本单，不用重建；挂好即可下发采购）——
const linkBomDialogRef = ref(null);
const linkBomList = ref([]); // 直连 MesBomAPI，snake_case
const linkBomId = ref('');
const linkBomAllProducts = ref(false); // 默认只列本单产品的生产任务单，可切全部
const linkBomBusy = ref(false);
const linkBomOptions = computed(() =>
  linkBomList.value.map(b => ({
    value: String(b.id),
    // 带上机型和产成品代码：光看 BOM 号和产品名分不出 K705 还是 A80，挂错了要退回重挂。
    label: `${b.bom_no} · ${[b.model, b.product_code].filter(Boolean).join(' ') || b.product_name || '—'} × ${b.base_qty || 1}${b.unit || ''}${b.status === 'DRAFT' ? '（草稿）' : ''}`,
  }))
);
const loadLinkBoms = async () => {
  try {
    const params = { per_page: 200 };
    if (!linkBomAllProducts.value && selected.value?.crmProductId) {
      params.crm_product_id = selected.value.crmProductId;
    }
    const { data } = await MesBomAPI.get(params);
    linkBomList.value = data?.payload || data || [];
  } catch {
    linkBomList.value = [];
  }
};
const openLinkBom = async () => {
  linkBomId.value = '';
  linkBomAllProducts.value = false;
  await loadLinkBoms();
  linkBomDialogRef.value?.open();
};
const toggleLinkBomScope = async () => {
  linkBomAllProducts.value = !linkBomAllProducts.value;
  linkBomId.value = '';
  await loadLinkBoms();
};
const submitLinkBom = async () => {
  if (!linkBomId.value || !selected.value || linkBomBusy.value) return;
  // 勾了「显示全部产品的 BOM」就能挂上别的产品的 BOM，挂错了要退回重来，
  // 所以编码对不上时先拦一道——只提醒不禁止（同款产品编码不一致的历史单仍要能挂）。
  const picked = linkBomList.value.find(
    b => String(b.id) === String(linkBomId.value)
  );
  const orderCode = (selected.value.productCode || '').trim();
  const bomCode = (picked?.product_code || '').trim();
  if (
    orderCode &&
    bomCode &&
    orderCode !== bomCode &&
    !window.confirm(
      `这张生产任务单的商品编码是 ${bomCode}，本单是 ${orderCode}，两者对不上。\n确定还是要关联吗？`
    )
  )
    return;
  linkBomBusy.value = true;
  try {
    const ok = await store.attachBom({
      id: selected.value.id,
      bomId: Number(linkBomId.value),
    });
    if (ok) {
      useAlert('已关联生产任务单，可下发采购');
      selected.value = ok;
      linkBomDialogRef.value?.close();
      fetchRecords();
    }
  } finally {
    linkBomBusy.value = false;
  }
};

// 解除 BOM 关联：挂错了就退回「待工程接单」重挂。后端会拦已开出下游单据的订单。
const detachBom = async () => {
  if (!selected.value) return;
  if (
    !window.confirm(
      `确定解除「${selected.value.orderNo}」与生产任务单 ${selected.value.bomNo} 的关联？\n订单会退回「待工程接单」，需要重新挂生产任务单。`
    )
  )
    return;
  const ok = await store.detachBom(selected.value.id);
  if (ok) {
    useAlert('已解除生产任务单关联，订单退回待工程接单');
    selected.value = ok;
    fetchRecords();
  }
};

// 采购原料退回工程/PMC BOM：下发早了或 BOM 要改时用。
const revertToBomReady = async () => {
  if (!selected.value) return;
  if (
    !window.confirm(
      `确定把「${selected.value.orderNo}」退回「工程/PMC 生产任务单」阶段？\n采购那边会看不到这张单，直到重新下发。`
    )
  )
    return;
  const ok = await store.revertToBomReady(selected.value.id);
  if (ok) {
    useAlert('已退回工程/PMC 生产任务单阶段');
    selected.value = ok;
    fetchRecords();
  }
};

// 工程/PMC 制单后一键下发到采购阶段。
const releasePurchasing = async () => {
  if (!selected.value) return;
  const ok = await store.releasePurchasing(selected.value.id);
  if (ok) {
    useAlert('已下发到采购阶段');
    selected.value = ok;
    fetchRecords();
  }
};

// 无需采购（库存直接领用）：料现成在库里、不用买，跳过采购直接进「原料入库」，
// 领料页才选得到这张单。只推阶段、不动库存——料本来就在库里，领料时正常扣。
const skipPurchaseDialogRef = ref(null);
const skipPurchaseReason = ref('');
const openSkipPurchasing = () => {
  skipPurchaseReason.value = '';
  skipPurchaseDialogRef.value?.open();
};
const submitSkipPurchasing = async () => {
  if (!selected.value) return;
  const ok = await store.skipPurchasing(
    selected.value.id,
    skipPurchaseReason.value.trim()
  );
  if (ok) {
    skipPurchaseDialogRef.value?.close();
    useAlert('已标记无需采购，可以去领料了');
    selected.value = ok;
    fetchRecords();
  }
};

// —— 审批链（取代发布）：草稿→部门主管→总经理 ——
const APPROVAL_LABELS = {
  DRAFT: '草稿',
  SUBMITTED: '待部门主管审批',
  MANAGER_APPROVED: '待总经理',
  APPROVED: '已通过·生效',
  REJECTED: '已驳回',
};
const approvalComment = ref('');

const isOwner = computed(() => selected.value?.ownerId === currentUserId.value);
// 编辑规格/图片/附件：order 能力全量；业务角色可改**本人订单（含已下发）**——
// 已下发改动由后端通知下一个流程负责人（后端 ensure_editable! 同口径）。
const canEditSelected = computed(
  () => mesCan('order') || (canCreateOrder.value && isOwner.value)
);
// 列表行级「编辑」：与 canEditSelected 同口径（order 能力 / 本人订单），
// 且订单须有定制规格表（编辑弹窗基于规格模板，外购单无规格不走此入口）。
const canEditRow = po =>
  !!po.spec?.template &&
  (mesCan('order') ||
    (canCreateOrder.value && po.ownerId === currentUserId.value));
// 删除：管理员删任意；归属业务仅删**本人草稿**（已下发进入生产流程不可删，后端 ensure_deletable! 同口径）。
const canDeleteRow = po =>
  isAdmin.value ||
  isCrmDeputyAdmin.value ||
  (canCreateOrder.value && po.ownerId === currentUserId.value && po.isDraft);
// 当前页查看该订单的原料入库单，保留列表及详情状态。
const stockEntriesDialog = ref(null);
const goStockEntries = po => stockEntriesDialog.value.open(po);

// 点阶段负责人名字 → 跳团队协同并直接打开与该负责人的私聊。
const goStageOwnerChat = ownerId => {
  if (!ownerId) return;
  router.push(accountScopedRoute('crm_team_chat_index', {}, { peer: ownerId }));
};

// 单号复制：工单号/来源销售单常要贴到 PI、聊天、Excel 里，手工选中容易漏字符。
const copyNo = async no => {
  if (!no) return;
  await copyTextToClipboard(String(no));
  useAlert(`已复制 ${no}`);
};

// 来源销售单 → 跳 CRM 销售订单页并自动展开该单（focus 是那页现成的入参）。
const goCrmSalesOrder = id =>
  router.push(accountScopedRoute('crm_sales_orders_index', {}, { focus: id }));

// 删除草稿订单（归属业务删本人草稿 / 管理员删任意）。
const deleteOrder = async po => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`确定删除草稿订单「${po.orderNo}」？`)) return;
  const ok = await store.delete(po.id);
  if (ok) {
    useAlert('草稿订单已删除');
    if (selected.value?.id === po.id) selected.value = null;
    fetchRecords();
  }
};
const canApprove = computed(() => {
  const po = selected.value;
  if (!po) return false;
  if (!['SUBMITTED', 'MANAGER_APPROVED'].includes(po.approvalStatus))
    return false;
  return (
    isAdmin.value ||
    isCrmDeputyAdmin.value ||
    po.currentApproverId === currentUserId.value
  );
});

// ── 审批卡 / 接单卡的状态计算 ──
// 三种状态的分支写在模板里会糊成一团，统一在这里算好，模板只管画。

// 右上角状态徽标
const approvalBadge = computed(() => {
  const s = selected.value?.approvalStatus;
  if (s === 'APPROVED')
    return {
      text: '已生效',
      icon: 'i-lucide-check',
      cls: 'bg-n-teal-3 text-n-teal-11',
    };
  if (s === 'REJECTED')
    return {
      text: '已驳回',
      icon: 'i-lucide-x',
      cls: 'bg-n-ruby-3 text-n-ruby-11',
    };
  if (s === 'SUBMITTED')
    return {
      text: '待部门主管审批',
      icon: 'i-lucide-clock',
      cls: 'bg-n-amber-3 text-n-amber-11',
    };
  if (s === 'MANAGER_APPROVED')
    return {
      text: '待总经理审批',
      icon: 'i-lucide-clock',
      cls: 'bg-n-amber-3 text-n-amber-11',
    };
  return {
    text: '草稿',
    icon: 'i-lucide-file-pen-line',
    cls: 'bg-n-slate-4 text-n-slate-11',
  };
});

// 审批时间线。驳回发生在哪一级，就把那一级标红：主管驳回时 gmActedAt 为空，据此区分。
const approvalSteps = computed(() => {
  const po = selected.value;
  if (!po || po.approvalStatus === 'DRAFT') return [];
  const rejected = po.approvalStatus === 'REJECTED';
  const out = [];
  if (po.submittedAt) {
    out.push({
      key: 'submitted',
      title: '提交',
      who: po.ownerName,
      at: po.submittedAt,
      state: 'submit',
    });
  }
  if (po.managerActedAt) {
    const denied = rejected && !po.gmActedAt;
    out.push({
      key: 'manager',
      title: denied ? '部门主管驳回' : '部门主管通过',
      who: po.managerName,
      at: po.managerActedAt,
      state: denied ? 'reject' : 'done',
      comment: po.managerComment,
    });
  } else if (po.approvalStatus === 'SUBMITTED') {
    out.push({
      key: 'manager',
      title: '部门主管审批',
      who: po.managerName || '未解析到主管，将转总经理',
      state: 'wait',
    });
  }
  if (po.gmActedAt) {
    out.push({
      key: 'gm',
      title: rejected ? '总经理驳回' : '总经理通过',
      who: po.gmName,
      at: po.gmActedAt,
      state: rejected ? 'reject' : 'done',
      comment: po.gmComment,
    });
  } else if (po.approvalStatus === 'MANAGER_APPROVED') {
    out.push({
      key: 'gm',
      title: '总经理审批',
      who: po.gmName || '未指定总经理',
      state: 'wait',
    });
  }
  return out;
});

const STEP_DOT = {
  submit: { cls: 'bg-n-iris-9 text-white', icon: 'i-lucide-arrow-up' },
  done: { cls: 'bg-n-teal-9 text-white', icon: 'i-lucide-check' },
  reject: { cls: 'bg-n-ruby-9 text-white', icon: 'i-lucide-x' },
  wait: { cls: 'border border-dashed border-n-iris-7', icon: '' },
};
const stepDot = state => STEP_DOT[state] || STEP_DOT.wait;

// 接单卡徽标
const ackBadge = computed(() => {
  const po = selected.value;
  if (!po) return null;
  if (po.stageAckAt)
    return {
      text: '已接单',
      icon: 'i-lucide-check',
      cls: 'bg-n-teal-3 text-n-teal-11',
    };
  if (po.ackOverdue)
    return {
      text: '超时未接单',
      icon: 'i-lucide-alert-circle',
      cls: 'bg-n-ruby-3 text-n-ruby-11',
    };
  if (po.awaitingAck)
    return {
      text: '待接单',
      icon: 'i-lucide-clock',
      cls: 'bg-n-amber-3 text-n-amber-11',
    };
  return null;
});

// 截止倒计时：没超时说「还剩」，超时说「已超时」。不足一小时按分钟显示。
const ackCountdown = computed(() => {
  const po = selected.value;
  if (!po?.ackDeadline || po.stageAckAt) return null;
  const diff = new Date(po.ackDeadline).getTime() - Date.now();
  const mins = Math.round(Math.abs(diff) / 60000);
  const txt = mins >= 60 ? `${Math.floor(mins / 60)} 小时` : `${mins} 分钟`;
  return diff >= 0
    ? { text: `还剩 ${txt}`, cls: 'text-n-amber-11' }
    : { text: `已超时 ${txt}`, cls: 'text-n-ruby-11' };
});

// 卡片里的时间用短格式（9/21 09:55），完整时间在别处已有。
const fmtShort = d =>
  d
    ? new Date(d).toLocaleString(undefined, {
        month: 'numeric',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
        hour12: false,
      })
    : '';

const submitApproval = async () => {
  if (!selected.value) return;
  const ok = await store.submitApproval(selected.value.id);
  if (ok) {
    useAlert('已提交审批');
    selected.value = ok;
    fetchRecords();
  }
};
const approveOrder = async () => {
  if (!selected.value) return;
  const ok = await store.approve({
    id: selected.value.id,
    comment: approvalComment.value.trim() || undefined,
  });
  if (ok) {
    useAlert('已通过');
    selected.value = ok;
    approvalComment.value = '';
    fetchRecords();
  }
};
// 列表行审批徽标配色。
const rowApprovalClass = status => {
  if (status === 'REJECTED') return 'bg-n-ruby-3 text-n-ruby-11';
  if (status === 'DRAFT') return 'bg-n-slate-4 text-n-slate-11';
  return 'bg-n-amber-3 text-n-amber-11'; // 待部门主管 / 待总经理
};

const denyDialogRef = ref(null);
const denyReason = ref('');
const openDeny = () => {
  denyReason.value = '';
  denyDialogRef.value?.open();
};
const confirmDeny = async () => {
  if (!selected.value || !denyReason.value.trim()) return;
  const ok = await store.deny({
    id: selected.value.id,
    reason: denyReason.value.trim(),
  });
  if (ok) {
    useAlert('已驳回');
    selected.value = ok;
    denyDialogRef.value?.close();
    fetchRecords();
  }
};

// —— 接单确认（P1）——
// 只有本阶段负责人本人能接单/拒收；管理员/副管理员一律不显示——他们不干这活，
// 按钮挂在那只会让人以为自己该接（即便被配成了板块负责人也不显示）。
const canHandleStage = computed(() => {
  const po = selected.value;
  if (!po || po.stage === 'SHIPPED' || po.status !== 'IN_PROGRESS')
    return false;
  if (isAdmin.value || isCrmDeputyAdmin.value) return false;
  return (po.stageOwnerIds || []).includes(currentUserId.value);
});

// 接单之后下一步该建什么单——系统知道，就别让人自己去侧栏找。
// 阶段 → { 下一张单的名字, 落到哪个建档页 }；没有对应建单动作的阶段不弹。
const NEXT_DOC = {
  SALES_CONFIRMED: { label: '生产任务单', kind: 'bom' },
  PURCHASING: { label: '采购单', kind: 'purchase' },
  MATERIAL_INBOUND: { label: '入库单', route: 'mes_stock_entries_index' },
  PICKING: { label: '领料单', route: 'mes_material_issues_index' },
  PRODUCTION: { label: '报工单', route: 'mes_production_records_index' },
  FG_INBOUND: { label: '成品入库单', route: 'mes_fg_inbound_index' },
};
const nextDoc = computed(() => NEXT_DOC[selected.value?.stage] || null);
const nextDocDialogRef = ref(null);
const goNextDoc = () => {
  const d = nextDoc.value;
  const po = selected.value;
  if (!d || !po) return;
  nextDocDialogRef.value?.close();
  if (d.kind === 'bom') {
    goCreateBomForOrder();
    return;
  }
  if (d.kind === 'purchase') {
    router.push(
      accountScopedRoute(
        'mes_purchase_order_intake_index',
        {},
        { production_order_id: po.id }
      )
    );
    return;
  }
  router.push(accountScopedRoute(d.route, {}, { q: po.orderNo }));
};

const acknowledge = async () => {
  if (!selected.value) return;
  const ok = await store.acknowledge(selected.value.id);
  if (ok) {
    useAlert('已接单');
    selected.value = ok;
    // 接完单顺手把下一步递到手上，不用自己去侧栏找该建哪张单。
    if (nextDoc.value) nextDocDialogRef.value?.open();
  }
};

// 转给同阶段另一位负责人（工程出/改完 BOM 转 PMC 投单；PMC 接了才发现要改料也能转回）。
// 转出后本人不再是接单人，接收人那边重新出现「待我接单」。
const handoffDialogRef = ref(null);
const handoffToId = ref('');
const handoffNote = ref('');

// 可转交对象 = 本阶段负责人里除自己以外的人。
const handoffCandidates = computed(() =>
  (selected.value?.stageOwners || []).filter(o => o.id !== currentUserId.value)
);

const openHandoff = () => {
  handoffToId.value = String(handoffCandidates.value[0]?.id || '');
  handoffNote.value = '';
  handoffDialogRef.value?.open();
};

const confirmHandoff = async () => {
  if (!selected.value || !handoffToId.value) return;
  const ok = await store.handoff(selected.value.id, {
    to_user_id: Number(handoffToId.value),
    note: handoffNote.value,
  });
  if (ok) {
    useAlert('已转交，对方会收到待接单提醒');
    selected.value = ok;
    handoffDialogRef.value?.close();
  }
};

const rejectDialogRef = ref(null);
const rejectReason = ref('');
const openReject = () => {
  rejectReason.value = '';
  rejectDialogRef.value?.open();
};
const confirmReject = async () => {
  if (!selected.value || !rejectReason.value.trim()) return;
  const ok = await store.reject({
    id: selected.value.id,
    reason: rejectReason.value.trim(),
  });
  if (ok) {
    useAlert('已退回上一阶段');
    selected.value = ok;
    rejectDialogRef.value?.close();
    fetchRecords();
  }
};

// 商品编码统一取自关联产品档案(crm_product 的 sku)，在「编辑订单」里选商品编码设置；
// 原「产品编码」自由文本(product_code，无人使用)已下线，不再单独维护。

const rootStore = useStore();
// 按 query 定位：切到对应视图、按单号搜索并打开详情面板。
// 首次进入由 onMounted 调用；从站内通知带着新单号再次进来时由 useRouteQueryReentry 调用——
// 本页在 keep-alive 里缓存着，不补这一道的话 onMounted 不会再跑，参数全不生效。
const applyRouteQuery = async query => {
  // 列表视图的值是 'all'，不是 'list'——写错成 'list' 会落到一个谁都不认的状态：
  // 四个页签一个都不高亮（进页面看不出当前在看哪一栏），得点一下才回到 'all'。
  viewMode.value = query.view === 'approval' ? 'inbox' : 'all';
  const q = query.q ? String(query.q) : '';
  searchQuery.value = q;
  currentPage.value = 1;
  await fetchRecords();
  selected.value = q
    ? records.value.find(r => r.orderNo === q) || null
    : selected.value;
};

onMounted(async () => {
  // 纯业务员没有「全部」页签，默认落到「我的订单」，避免默认档无对应高亮页签。
  if (isPlainSales.value && listScope.value === 'all') listScope.value = 'mine';
  if (!agents.value?.length) rootStore.dispatch('agents/get');
  await applyRouteQuery(route.query);
});

useRouteQueryReentry(applyRouteQuery);
// 改筛选回到第 1 页再拉。
watch([activeStage, activeStatus, activeOwner], () => {
  currentPage.value = 1;
  fetchRecords();
});
watch(currentPage, fetchRecords);
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <!-- 头部 -->
    <div
      class="flex flex-wrap items-center justify-between gap-3 px-4 py-3 sm:px-6 sm:py-4"
    >
      <h1 class="text-xl font-semibold text-n-slate-12">生产订单</h1>

    </div>

    <!-- 视图切换：我的订单 / 库存备货 / 全部 / 待我确认（前后两个仅 CRM 业务身份显示）。
         data-tabbar="page" + aria-selected 是全站页面级 Tab 的统一标记（灰槽 + 深色选中块），
         样式在 _next-colors.scss 里，这里不要再写边框/底色，写了会跟它打架。 -->
    <div class="flex flex-wrap items-center justify-between gap-3 px-4 pb-2 sm:px-6">
      <div data-tabbar="page" class="shrink-0">
        <button
          v-if="isCrmMember"
          :aria-selected="tabActive('all', 'mine')"
          @click="setListScope('mine')"
        >
          我的订单
        </button>
        <!-- 库存备货：PMC（建备货单）与业务身份（卖共享库存）可见；采购/车间/仓库隐藏 -->
        <button
          v-if="isCrmMember || mesCan('order')"
          :aria-selected="tabActive('all', 'stock')"
          @click="setListScope('stock')"
        >
          库存备货
        </button>
        <button
          v-if="canSeeAllScope"
          :aria-selected="tabActive('all', 'all')"
          @click="setListScope('all')"
        >
          全部
        </button>
        <button
          v-if="isCrmMember"
          :aria-selected="tabActive('inbox')"
          @click="setViewMode('inbox')"
        >
          待我确认
        </button>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <!-- 列顺序是本机记忆，拖乱了要有路回来 -->
        <Button
          label="恢复默认列序"
          variant="ghost"
          color="slate"
          size="sm"
          @click="resetOrder"
        />
        <!-- 收起用不到的列：列少了就不用横着拖滚动条 -->
        <div class="relative">
          <Button
            :label="hiddenCols ? `列（收起 ${hiddenCols}）` : '列'"
            variant="outline"
            color="slate"
            size="sm"
            class="btn-ink"
            icon="i-lucide-columns-3"
            @click="showColumnPanel = !showColumnPanel"
          />
          <!-- 透明兜底层：点面板外面收起来，省掉一个全局 click 监听 -->
          <div
            v-if="showColumnPanel"
            class="fixed inset-0 z-10"
            @click="showColumnPanel = false"
          />
          <div
            v-if="showColumnPanel"
            class="absolute right-0 z-20 flex flex-col gap-1 p-2 mt-1 border shadow-lg top-full w-52 rounded-xl border-n-weak bg-n-solid-1"
          >
            <label
              v-for="col in orderedColumns"
              :key="`vis-${col.key}`"
              class="flex items-center gap-2 px-2 py-1 rounded cursor-pointer text-label-small hover:bg-n-alpha-1"
            >
              <input
                type="checkbox"
                :checked="!isHidden(col.key)"
                @change="toggleColumn(col.key)"
              />
              {{ col.label }}
            </label>
            <button
              class="px-2 py-1 mt-1 text-left border-t text-label-small text-n-slate-11 border-n-weak hover:text-n-slate-12"
              @click="showAllColumns"
            >
              全部显示
            </button>
          </div>
        </div>
        <Button
          v-if="mesCan('order')"
          label="从销售订单转入"
          variant="outline"
          color="slate"
          size="sm"
          class="btn-ink"
          @click="openConvert"
        />
        <Button
          v-if="canCreateOrder"
          label="新建生产订单"
          color="iris"
          size="sm"
          @click="openNewOrder"
        />
      </div>
    </div>

    <!-- 筛选 -->
    <div
      v-show="viewMode === 'all'"
      class="flex flex-wrap items-center gap-3 px-4 pb-3 sm:px-6"
    >
      <SelectCard
        :model-value="activeStage"
        :options="stageFilterOptions"
        @update:model-value="v => (activeStage = v)"
      />
      <SelectCard
        :model-value="activeStatus"
        :options="statusFilterOptions"
        @update:model-value="v => (activeStatus = v)"
      />
      <SelectCard
        v-if="canSeeAllScope"
        :model-value="activeOwner"
        :options="ownerFilterOptions"
        @update:model-value="v => (activeOwner = v)"
      />
      <!-- reset-base：不加的话全局 $form-input-selector 会给它套上 field-base 的
           w-full + mb-4，搜索框撑满整行、被挤到筛选下面去（用户反馈「怎么搞了这么多行」）。
           高度跟 SelectCard 对齐用 h-9。 -->
      <input
        v-model="searchQuery"
        type="text"
        placeholder="搜索 工单号 / 成品名 / 商品编码…"
        class="reset-base h-9 px-3 text-sm rounded-lg outline-none w-60 border border-n-weak bg-n-solid-1 text-n-slate-12"
        @input="onSearchInput"
      />
    </div>

    <div
      class="flex flex-col md:flex-row flex-1 min-h-0 gap-4 px-4 pb-4 sm:px-6 sm:pb-6"
    >
      <!-- 列表 -->
      <div class="flex-1 min-w-0 overflow-auto">
        <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
          加载中…
        </div>
        <template v-else>
          <!-- 手机卡片列表（<768px） -->
          <div class="flex flex-col gap-2 md:hidden">
            <div
              v-for="po in records"
              :key="po.id"
              class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl active:bg-n-alpha-1"
              :class="{
                'bg-n-alpha-2 !border-n-iris-9':
                  selected && selected.id === po.id,
              }"
              @click="selectRow(po)"
            >
              <div class="flex items-center gap-2">
                <span class="font-medium text-n-slate-12 truncate">
                  {{ po.orderNo }}
                </span>
                <span
                  class="shrink-0 px-2 py-0.5 text-xs rounded-full"
                  :class="stageChip(po.stage)"
                >
                  {{ stageLabel(po.stage) }}
                </span>
                <span
                  v-if="isStalled(po)"
                  v-tooltip.top="`本阶段已滞留 ${stallDays(po)} 天`"
                  class="shrink-0 text-xs cursor-help text-n-ruby-11"
                >
                  ⚠
                </span>
                <span class="flex-1" />
                <div class="flex items-center gap-1 shrink-0" @click.stop>
                  <Button
                    v-if="canEditRow(po)"
                    label="编辑"
                    variant="ghost"
                    color="iris"
                    size="sm"
                    @click="openEditSpec(po)"
                  />
                  <Button
                    label="查看"
                    variant="ghost"
                    size="sm"
                    @click="openDetail(po)"
                  />
                  <Button
                    v-if="canDeleteRow(po)"
                    label="删除"
                    variant="ghost"
                    color="ruby"
                    size="sm"
                    @click="deleteOrder(po)"
                  />
                </div>
              </div>
              <div
                class="flex flex-wrap items-center gap-x-2 gap-y-0.5 mt-1 text-xs"
              >
                <span
                  v-if="po.orderKind === 'STOCK'"
                  class="px-1.5 py-0.5 rounded-full whitespace-nowrap shrink-0 bg-n-teal-3 text-n-teal-11"
                >
                  外贸库存备货
                </span>
                <span
                  v-if="po.isOutsourced"
                  class="px-1.5 py-0.5 rounded-full whitespace-nowrap shrink-0 bg-n-amber-3 text-n-amber-11"
                >
                  外购
                </span>
                <span
                  v-if="po.approvalStatus && po.approvalStatus !== 'APPROVED'"
                  class="px-1.5 py-0.5 rounded-full"
                  :class="rowApprovalClass(po.approvalStatus)"
                >
                  {{ APPROVAL_LABELS[po.approvalStatus] }}
                </span>
              </div>
              <div class="mt-1 text-xs text-n-slate-11 truncate">
                {{ po.productName }}
              </div>
              <div
                class="flex flex-wrap gap-x-3 gap-y-0.5 mt-1 text-xs text-n-slate-11"
              >
                <span
                  >数量：{{ po.producedQty }} / {{ po.qty }} {{ po.unit }}</span
                >
                <span v-if="po.piNo">PI {{ po.piNo }}</span>
                <span v-if="po.productSku" class="text-n-iris-11">
                  商品编码 {{ po.productSku }}
                </span>
              </div>
              <div
                class="flex flex-wrap gap-x-3 gap-y-0.5 mt-1 text-xs text-n-slate-11"
              >
                <span
                  v-if="deliveryStatus(po)"
                  :class="DUE_CLASS[deliveryStatus(po).level]"
                >
                  交期：{{ deliveryStatus(po).label }}
                </span>
                <span v-if="po.remark">备注：{{ po.remark }}</span>
                <span v-if="po.salesOrderNo">来源：{{ po.salesOrderNo }}</span>
                <span>负责人：{{ po.ownerName || '—' }}</span>
              </div>
              <div
                v-if="ackChip(po)"
                class="mt-1 text-[11px] leading-tight text-n-slate-10"
              >
                <span>
                  <span :class="ackChip(po).cls">{{ ackChip(po).text }}</span>
                  <span v-if="stallDays(po) > 0">
                    · 停留 {{ stallDays(po) }} 天</span
                  >
                </span>
              </div>
            </div>
            <div
              v-if="!records.length"
              class="px-3 py-10 text-center text-n-slate-11"
            >
              还没有生产订单。点右上角「从销售订单转入」开始。
            </div>
          </div>

          <!-- 列多：给表格设最小宽度，窄屏时外层 overflow-auto 自动横向滑动，列各自保持自然宽不再挤压换行。
               收起过列就不再压这个最小宽——否则列都收完了表格还是 1240px 宽，照样要横着拖。 -->
          <table
            class="hidden md:table w-full text-sm"
            :class="hiddenCols ? '' : 'md:min-w-[1240px]'"
          >
            <thead>
              <tr
                class="text-left text-n-slate-11 border-b border-n-weak whitespace-nowrap"
              >
                <!-- 拖列头即可改顺序，按人记在本机 -->
                <th
                  v-for="col in visibleColumns"
                  :key="col.key"
                  draggable="true"
                  class="px-3 py-3 font-medium transition-colors cursor-move select-none"
                  :class="isDragging(col.key) ? 'opacity-40' : ''"
                  title="拖动可调整列顺序"
                  @dragstart="onColDragStart(col.key)"
                  @dragover.prevent
                  @drop="onColDrop(col.key)"
                >
                  {{ col.label }}
                </th>
                <th class="px-3 py-3" />
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="po in records"
                :key="po.id"
                class="border-b cursor-pointer group/row border-n-weak [&:hover>td]:bg-n-alpha-1 [&>td:first-child]:rounded-l-lg [&>td:last-child]:rounded-r-lg"
                :class="
                  selected && selected.id === po.id
                    ? '[&>td]:!bg-n-alpha-2 [&>td:first-child]:shadow-[inset_3px_0_0_0_rgb(var(--iris-9))]'
                    : ''
                "
                @click="selectRow(po)"
              >
                <!-- 中间列按 visibleColumns 渲染（收起的列不出现），顺序随表头拖拽实时变化 -->
                <td
                  v-for="col in visibleColumns"
                  :key="col.key"
                  :class="col.tdClass"
                >
                  <template v-if="col.key === 'no'">
                    <span
                      class="inline-flex items-center gap-1 whitespace-nowrap"
                    >
                      <span>{{ po.orderNo }}</span>
                      <button
                        v-if="po.orderNo"
                        v-tooltip.top="'复制工单号'"
                        type="button"
                        class="transition-opacity opacity-0 i-lucide-copy size-3.5 shrink-0 text-n-slate-10 hover:text-n-iris-11 group-hover/row:opacity-100"
                        @click.stop="copyNo(po.orderNo)"
                      />
                    </span>
                    <span
                      v-if="po.orderKind === 'STOCK'"
                      class="inline-block ml-1 px-1.5 py-0.5 text-xs rounded-full whitespace-nowrap bg-n-teal-3 text-n-teal-11"
                      title="外贸库存备货订单：全业务共享库存"
                    >
                      外贸库存备货
                    </span>
                    <span
                      v-if="po.isOutsourced"
                      class="inline-block ml-1 px-1.5 py-0.5 text-xs rounded-full whitespace-nowrap bg-n-amber-3 text-n-amber-11"
                      title="外购成品：工程判定外购，跳过生产，采购按单买"
                    >
                      外购
                    </span>
                    <span
                      v-if="
                        po.approvalStatus && po.approvalStatus !== 'APPROVED'
                      "
                      class="inline-block ml-1 px-1.5 py-0.5 text-xs rounded-full whitespace-nowrap"
                      :class="rowApprovalClass(po.approvalStatus)"
                    >
                      {{ APPROVAL_LABELS[po.approvalStatus] }}
                    </span>
                    <span
                      v-if="po.piNo"
                      class="block text-xs font-normal text-n-slate-10"
                    >
                      PI {{ po.piNo }}
                    </span>
                    <span
                      v-if="po.productSku"
                      class="block text-xs font-normal text-n-iris-11"
                    >
                      商品编码 {{ po.productSku }}
                    </span>
                  </template>
                  <template v-if="col.key === 'model'">
                    <span class="block truncate" :title="po.productName || ''">
                      {{ po.productName }}
                    </span>
                  </template>
                  <template v-if="col.key === 'qty'">
                    {{ po.producedQty }} / {{ po.qty }} {{ po.unit }}
                  </template>
                  <template v-if="col.key === 'stage'">
                    <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
                      <span
                        class="inline-flex items-center px-2 py-0.5 text-xs rounded-full"
                        :class="stageChip(po.stage)"
                      >
                        {{ stageLabel(po.stage) }}
                      </span>
                      <span
                        v-if="isStalled(po)"
                        v-tooltip.top="`本阶段已滞留 ${stallDays(po)} 天`"
                        class="ml-1 text-xs cursor-help text-n-ruby-11"
                      >
                        ⚠
                      </span>
                      <!-- 阶段进度：一排点＋已走几步，跟药丸同一行。
                           外购单点数更少（短流程），不是「跳了几步」。 -->
                      <span class="flex items-center gap-1">
                        <template
                          v-for="(st, si) in stageFlowOf(po)"
                          :key="st.value"
                        >
                          <span
                            v-if="si"
                            class="w-2 h-px shrink-0"
                            :class="
                              si <= stageIndexOf(po)
                                ? 'bg-n-iris-9'
                                : 'bg-n-slate-5'
                            "
                          />
                          <span
                            v-tooltip.top="st.label"
                            class="rounded-full cursor-help size-2 shrink-0"
                            :class="stageDotClass(po, si)"
                          />
                        </template>
                        <span
                          class="ml-1 text-[11px] tabular-nums whitespace-nowrap shrink-0 text-n-slate-10"
                        >
                          {{ stageProgressText(po) }}
                        </span>
                      </span>
                    </div>
                    <!-- 卡在谁那·卡了多久·接单态：不点开也一眼看清 -->
                    <div
                      class="mt-0.5 text-[11px] leading-tight text-n-slate-10"
                    >
                      <span v-if="ackChip(po)">
                        <span :class="ackChip(po).cls">{{
                          ackChip(po).text
                        }}</span>
                        <span v-if="stallDays(po) > 0">
                          · 停留 {{ stallDays(po) }} 天</span
                        >
                      </span>
                    </div>
                  </template>
                  <template v-if="col.key === 'due'">
                    <span
                      v-if="deliveryStatus(po)"
                      :class="DUE_CLASS[deliveryStatus(po).level]"
                    >
                      {{ deliveryStatus(po).label }}
                    </span>
                    <span v-else class="text-n-slate-10">—</span>
                  </template>
                  <template v-if="col.key === 'sku'">
                    {{ po.productSku || '—' }}
                  </template>
                  <template v-if="col.key === 'spec'">
                    <span
                      class="block truncate"
                      :title="po.specification || ''"
                    >
                      {{ po.specification || '—' }}
                    </span>
                  </template>
                  <template v-if="col.key === 'inboundQty'">
                    {{ po.fgInboundQty || 0 }}
                  </template>
                  <template v-if="col.key === 'pendingQty'">
                    <span :class="pendingCls(po)">{{ pendingQty(po) }}</span>
                  </template>
                  <template v-if="col.key === 'issueState'">
                    <span :class="issueState(po).cls">
                      {{ issueState(po).label }}
                    </span>
                  </template>
                  <template v-if="col.key === 'doneState'">
                    <span :class="doneState(po).cls">
                      {{ doneState(po).label }}
                    </span>
                  </template>
                  <template v-if="col.key === 'remark'">
                    <span class="block truncate" :title="po.remark || ''">
                      {{ po.remark || '—' }}
                    </span>
                  </template>
                  <template v-if="col.key === 'salesOrder'">
                    <!-- 挂了 CRM 销售订单就能点进去看原单（走该页现成的 ?focus=<id> 定位） -->
                    <span
                      class="inline-flex items-center gap-1 whitespace-nowrap"
                    >
                      <button
                        v-if="po.crmSalesOrderId && po.salesOrderNo"
                        type="button"
                        class="underline text-n-iris-11 underline-offset-2 hover:text-n-iris-12"
                        @click.stop="goCrmSalesOrder(po.crmSalesOrderId)"
                      >
                        {{ po.salesOrderNo }}
                      </button>
                      <span v-else>{{ po.salesOrderNo || '—' }}</span>
                      <button
                        v-if="po.salesOrderNo"
                        v-tooltip.top="'复制销售单号'"
                        type="button"
                        class="transition-opacity opacity-0 i-lucide-copy size-3.5 shrink-0 text-n-slate-10 hover:text-n-iris-11 group-hover/row:opacity-100"
                        @click.stop="copyNo(po.salesOrderNo)"
                      />
                    </span>
                  </template>
                  <template v-if="col.key === 'owner'">
                    {{ po.ownerName || '—' }}
                  </template>
                </td>
                <td class="px-3 py-3 text-right" @click.stop>
                  <div class="flex items-center justify-end gap-1">
                    <Button
                      v-if="canEditRow(po)"
                      label="编辑"
                      variant="ghost"
                      color="iris"
                      size="sm"
                      @click="openEditSpec(po)"
                    />
                    <Button
                      label="查看"
                      variant="ghost"
                      size="sm"
                      @click="openDetail(po)"
                    />
                  </div>
                </td>
              </tr>
              <tr v-if="!records.length">
                <td colspan="10" class="px-3 py-10 text-center text-n-slate-11">
                  还没有生产订单。点右上角「从销售订单转入」开始。
                </td>
              </tr>
            </tbody>
          </table>
        </template>

        <PaginationFooter
          v-if="totalCount > ITEMS_PER_PAGE"
          :current-page="currentPage"
          :total-items="totalCount"
          :items-per-page="ITEMS_PER_PAGE"
          class="!bg-transparent before:!hidden"
          @update:current-page="currentPage = $event"
        />
      </div>

      <!-- 详情：8 阶段进度条（流程视图；订单明细看「查看」弹窗） -->
      <div
        v-if="selected"
        class="flex flex-col p-5 overflow-auto w-full md:w-80 shrink-0 rounded-xl bg-n-alpha-black1 border border-n-weak [.theme-classic-black_&]:!bg-white [.theme-classic-black_&]:rounded-3xl [.theme-classic-black_&]:!border-[#e8eaed] [.theme-classic-black_&]:md:w-96 [.theme-classic-black_&]:p-6"
      >
        <div class="flex items-center gap-2 mb-1 [.theme-classic-black_&]:mb-3">
          <span class="font-semibold truncate text-n-slate-12 [.theme-classic-black_&]:text-heading-1">{{
            selected.orderNo
          }}</span>
          <span class="ml-auto text-xs shrink-0 text-n-slate-11">
            {{ STATUS_LABELS[selected.status] }}
          </span>
          <!-- 关闭：面板原来只能靠再点一次列表行关掉，从站内通知跳进来的人根本没点过行，
               等于进来就出不去。 -->
          <Button
            icon="i-lucide-x"
            variant="ghost"
            color="slate"
            size="xs"
            aria-label="关闭"
            class="-mr-1 shrink-0"
            @click="selected = null"
          />
        </div>
        <div class="mb-1 text-sm text-n-slate-11">
          {{ selected.productName }} · {{ selected.producedQty }}/{{
            selected.qty
          }}
          {{ selected.unit }}
        </div>
        <div v-if="selected.piNo" class="mb-1 text-xs text-n-slate-11">
          PI：{{ selected.piNo }}
        </div>

        <!-- 商品编码：取自关联产品档案(sku)，在「编辑」里选商品编码设置 -->
        <div class="mb-4 text-xs text-n-slate-11">
          商品编码：{{
            selected.productSku || '未编码（在「编辑」里选商品编码）'
          }}
        </div>

        <!-- 审批链（取代发布）：草稿→部门主管→总经理，全部通过才生效 -->
        <div
          class="p-4 mb-4 border shadow-sm rounded-2xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl [.theme-classic-black_&]:!bg-[#f8f9fa] [.theme-classic-black_&]:!border-[#eeeff1] [.theme-classic-black_&]:!shadow-none [.theme-classic-black_&]:p-5"
        >
          <div class="flex items-center justify-between gap-2 mb-3">
            <span class="text-sm font-semibold text-n-slate-12">审批</span>
            <div class="flex items-center gap-2">
              <Button
                v-if="
                  isOwner &&
                  ['DRAFT', 'REJECTED'].includes(selected.approvalStatus)
                "
                :label="
                  selected.approvalStatus === 'REJECTED'
                    ? '重新提交'
                    : '提交审批'
                "
                color="iris"
                size="xs"
                :is-loading="uiFlags.updatingItem"
                @click="submitApproval"
              />
              <span
                class="inline-flex gap-1 items-center px-2 py-1 text-xs font-medium rounded-full shrink-0"
                :class="approvalBadge.cls"
              >
                <span :class="approvalBadge.icon" class="size-3" />
                {{ approvalBadge.text }}
              </span>
            </div>
          </div>

          <!-- 审批人可通过/驳回 -->
          <div v-if="canApprove" class="flex flex-col gap-2 mb-3">
            <textarea
              v-model="approvalComment"
              rows="2"
              placeholder="审批意见（选填）"
              class="px-2 py-1.5 text-xs rounded-lg border outline-none resize-y border-n-weak bg-n-alpha-black1 text-n-slate-12"
            />
            <div class="flex gap-2">
              <Button
                label="通过"
                color="iris"
                size="xs"
                :is-loading="uiFlags.updatingItem"
                @click="approveOrder"
              />
              <Button
                label="驳回"
                color="ruby"
                variant="outline"
                size="xs"
                @click="openDeny"
              />
            </div>
          </div>

          <!-- 审批留痕时间线 -->
          <div v-if="approvalSteps.length" class="flex flex-col">
            <div
              v-for="(step, i) in approvalSteps"
              :key="step.key"
              class="flex gap-3 [.theme-classic-black_&]:gap-4"
            >
              <div class="flex flex-col items-center shrink-0">
                <span
                  class="grid rounded-full place-items-center size-6 shrink-0 [.theme-classic-black_&]:size-7 [.theme-classic-black_&]:!bg-[#e5eddf] [.theme-classic-black_&]:!text-[#617754]"
                  :class="stepDot(step.state).cls"
                >
                  <span
                    v-if="stepDot(step.state).icon"
                    :class="stepDot(step.state).icon"
                    class="size-3.5"
                  />
                </span>
                <span
                  v-if="i < approvalSteps.length - 1"
                  class="flex-1 w-px min-h-4 bg-n-iris-5 [.theme-classic-black_&]:!bg-[#dce2d7]"
                />
              </div>
              <div class="flex-1 min-w-0 pb-3 [.theme-classic-black_&]:pb-5">
                <div class="flex gap-2 justify-between items-start">
                  <span
                    class="text-sm font-medium"
                    :class="
                      step.state === 'wait'
                        ? 'text-n-slate-10'
                        : 'text-n-slate-12'
                    "
                  >
                    {{ step.title }}
                  </span>
                  <span class="text-xs shrink-0 text-n-slate-10">
                    {{ step.at ? fmtShort(step.at) : '等待中' }}
                  </span>
                </div>
                <div class="text-xs text-n-slate-11">{{ step.who }}</div>
                <div
                  v-if="step.comment"
                  class="px-3 py-2 mt-2 text-xs rounded-lg bg-n-alpha-black1 text-n-slate-11"
                >
                  {{ step.comment }}
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- 接单确认（P1）：当前阶段负责人 + 接单状态 + 接单/拒收。
             建单生效后归工程/PMC 接单出生产任务单；SHIPPED 为终点无需接单。 -->
        <div
          v-if="
            selected.stage !== 'SHIPPED' && selected.status === 'IN_PROGRESS'
          "
          class="p-4 mb-4 border shadow-sm rounded-2xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl [.theme-classic-black_&]:!bg-[#f8f9fa] [.theme-classic-black_&]:!border-[#eeeff1] [.theme-classic-black_&]:!shadow-none [.theme-classic-black_&]:p-5"
        >
          <div class="flex items-center justify-between gap-2 mb-3">
            <span class="text-sm font-semibold text-n-slate-12">
              本阶段负责人
            </span>
            <span
              v-if="ackBadge"
              class="inline-flex gap-1 items-center px-2 py-1 text-xs font-medium rounded-full shrink-0"
              :class="ackBadge.cls"
            >
              <span :class="ackBadge.icon" class="size-3" />
              {{ ackBadge.text }}
            </span>
          </div>

          <div class="flex flex-wrap gap-2">
            <button
              v-for="o in selected.stageOwners || []"
              :key="o.id"
              type="button"
              class="inline-flex gap-2 items-center py-1 pr-3 pl-1 rounded-full bg-n-iris-3 hover:bg-n-iris-4"
              title="点击私聊该负责人"
              @click="goStageOwnerChat(o.id)"
            >
              <span
                class="grid text-xs text-white rounded-full place-items-center size-6 bg-n-iris-9"
              >
                {{ (o.name || '?').slice(0, 1) }}
              </span>
              <span class="text-sm text-n-iris-12">{{
                o.label || o.name
              }}</span>
              <span class="i-lucide-message-circle size-3.5 text-n-iris-11" />
            </button>
            <span
              v-if="!(selected.stageOwners || []).length"
              class="text-xs text-n-amber-11"
            >
              未设置负责人
            </span>
          </div>

          <div class="mt-3 text-xs text-n-slate-11">
            <template v-if="selected.stageAckAt">
              接单于 {{ fmtShort(selected.stageAckAt) }}
              <template v-if="selected.stageAckByName">
                · {{ selected.stageAckByName }}
              </template>
            </template>
            <template v-else-if="selected.ackDeadline">
              截止 {{ fmtShort(selected.ackDeadline) }}
              <span v-if="ackCountdown" :class="ackCountdown.cls">
                · {{ ackCountdown.text }}
              </span>
            </template>
          </div>

          <div v-if="canHandleStage" class="flex gap-2 mt-3">
            <Button
              v-if="selected.awaitingAck"
              label="接单"
              color="teal"
              size="sm"
              :is-loading="uiFlags.updatingItem"
              @click="acknowledge"
            />
            <Button
              v-if="handoffCandidates.length"
              label="转交"
              variant="outline"
              size="sm"
              :is-loading="uiFlags.updatingItem"
              @click="openHandoff"
            />
            <Button
              v-if="selected.stage !== 'SALES_CONFIRMED'"
              label="拒收打回"
              variant="outline"
              color="ruby"
              size="sm"
              @click="openReject"
            />
            <!-- 库里有料、不用买的单：卡在「采购原料」就领不了料（领料只对已入库的单开单）。
                 放在通用操作区——没挂生产任务单的单同样可能不用采购，不能塞进 bomNo 块里。 -->
            <Button
              v-if="
                selected.stage === 'PURCHASING' &&
                (mesCan('purchase') || mesCan('order'))
              "
              label="无需采购 · 用库存料"
              variant="outline"
              color="slate"
              size="sm"
              :is-loading="uiFlags.updatingItem"
              @click="openSkipPurchasing"
            />
          </div>
        </div>

        <div class="flex flex-col gap-0">
          <div
            v-for="(s, i) in timelineStages"
            :key="s.value"
            class="flex items-start gap-3"
          >
            <div class="flex flex-col items-center">
              <span
                class="flex items-center justify-center w-6 h-6 text-xs rounded-full shrink-0"
                :class="
                  i <= timelineStageIndex(selected.stage)
                    ? 'bg-n-iris-9 text-white'
                    : 'bg-n-slate-4 text-n-slate-11'
                "
              >
                {{ i + 1 }}
              </span>
              <span
                v-if="i < timelineStages.length - 1"
                class="w-px h-8"
                :class="
                  i < timelineStageIndex(selected.stage)
                    ? 'bg-n-iris-9'
                    : 'bg-n-slate-4'
                "
              />
            </div>
            <div class="pt-0.5 pb-2">
              <span
                class="text-sm"
                :class="
                  i === timelineStageIndex(selected.stage)
                    ? 'font-semibold text-n-slate-12'
                    : 'text-n-slate-11'
                "
              >
                {{ s.label }}
              </span>
              <button
                v-if="s.value === 'MATERIAL_INBOUND'"
                type="button"
                class="ml-2 text-xs text-n-iris-11 hover:underline"
                @click="goStockEntries(selected)"
              >
                查看入库单
              </button>
              <div
                v-for="(line, li) in stageAckLog(s.value)"
                :key="`ack-${s.value}-${li}`"
                class="text-xs text-n-slate-11"
              >
                · {{ line }}
              </div>
              <div v-if="stageTime(s.value)" class="text-xs text-n-slate-10">
                {{ stageTime(s.value) }} 到达
                <span
                  v-if="stageDurationLabel(s.value)"
                  :class="
                    i === timelineStageIndex(selected.stage) &&
                    isStalled(selected)
                      ? 'text-n-amber-11'
                      : 'text-n-slate-10'
                  "
                >
                  · {{ stageDurationLabel(s.value) }}
                </span>
              </div>
            </div>
          </div>
        </div>

        <div class="pt-4 mt-4 border-t border-n-weak">
          <template v-if="selected.bomNo">
            <div class="text-xs text-n-slate-11">
              工程/PMC 生产任务单：{{ selected.bomNo }}
            </div>
            <!-- 挂好 BOM 后下一步就是工程/PMC「下发到采购」
                 （原先中间有一道「业务二次确认生产任务单」的闸，已取消）。 -->
            <div
              v-if="selected.stage === 'BOM_READY'"
              class="p-3 mt-2 text-xs rounded-lg text-n-slate-11 bg-n-alpha-1"
            >
              生产任务单已挂好，等工程/PMC 核对后点「下发到采购」。
            </div>
            <!-- 查看工程做的用料清单（弹窗看完整明细） -->
            <Button
              v-if="
                bomDetail && bomDetail.bomItems && bomDetail.bomItems.length
              "
              :label="`查看生产任务单明细（${bomDetail.bomItems.length} 项）`"
              variant="outline"
              color="slate"
              size="sm"
              class="w-full mt-2"
              @click="openBomView"
            />
            <!-- 下发采购（原先此处有一道「业务二次确认 BOM」的闸，已取消）-->
            <Button
              v-if="
                selected.stage === 'BOM_READY' &&
                (mesCan('bom') || mesCan('order'))
              "
              label="下发到采购"
              color="iris"
              size="sm"
              class="w-full mt-2"
              :is-loading="uiFlags.updatingItem"
              @click="releasePurchasing"
            />
            <!-- 纠错口：BOM 挂错了解绑重挂 / 采购下发早了退回来改 BOM。
                 已开出请购、采购、出入库、报工单据的，后端会拦住并说明先作废哪些。 -->
            <Button
              v-if="
                selected.stage === 'BOM_READY' &&
                (mesCan('bom') || mesCan('order'))
              "
              label="解除生产任务单关联"
              variant="outline"
              color="ruby"
              size="sm"
              class="w-full mt-2"
              :is-loading="uiFlags.updatingItem"
              @click="detachBom"
            />
            <Button
              v-if="
                selected.stage === 'PURCHASING' &&
                !selected.isOutsourced &&
                (mesCan('bom') || mesCan('order'))
              "
              label="退回工程/PMC 生产任务单"
              variant="outline"
              color="ruby"
              size="sm"
              class="w-full mt-2"
              :is-loading="uiFlags.updatingItem"
              @click="revertToBomReady"
            />
            <!-- BOM 变更史：工程改动已下发 BOM 的用料留痕（谁/何时/改了什么）-->
            <div
              v-if="(selected.bomRevisions || []).length"
              class="p-2 mt-2 border rounded-lg border-n-amber-6 bg-n-amber-2"
            >
              <div class="mb-1 text-xs font-semibold text-n-amber-11">
                生产任务单变更记录（{{ selected.bomRevisions.length }} 次）
              </div>
              <ul class="flex flex-col gap-1.5">
                <li
                  v-for="rev in selected.bomRevisions"
                  :key="rev.revNo"
                  class="text-xs"
                >
                  <div class="flex items-center gap-1.5 text-n-slate-11">
                    <span class="font-semibold text-n-slate-12">
                      v{{ rev.revNo }}
                    </span>
                    <span>{{ rev.changedByName || '—' }}</span>
                    <span>{{ fmtRevTime(rev.createdAt) }}</span>
                  </div>
                  <div class="text-n-slate-12">{{ revDiffText(rev.diff) }}</div>
                  <div v-if="rev.reason" class="text-n-slate-10">
                    原因：{{ rev.reason }}
                  </div>
                </li>
              </ul>
            </div>
          </template>
          <!-- 工程判定：自产去建生产任务单并关联本单（自动挂），外购走标记外购 -->
          <div
            v-else-if="
              selected.stage === 'SALES_CONFIRMED' &&
              (mesCan('order') || mesCan('bom'))
            "
            class="flex flex-col gap-2"
          >
            <Button
              label="去建生产任务单（自产）"
              color="iris"
              size="sm"
              class="w-full"
              @click="goCreateBomForOrder"
            />
            <Button
              label="关联已有生产任务单"
              variant="faded"
              color="iris"
              size="sm"
              class="w-full"
              @click="openLinkBom"
            />
            <Button
              label="标记外购（跳过生产）"
              variant="outline"
              color="slate"
              size="sm"
              class="w-full"
              @click="openMarkOutsourced"
            />
          </div>
        </div>

        <!-- 外购标识 -->
        <div
          v-if="selected.isOutsourced"
          class="pt-3 mt-3 border-t border-n-weak"
        >
          <div class="flex items-center gap-2 text-xs">
            <span
              class="px-1.5 py-0.5 rounded-full bg-n-amber-3 text-n-amber-11"
            >
              外购成品
            </span>
            <span v-if="isMesStaff" class="text-n-slate-11">
              供应商：{{ selected.outsourceSupplierName || '—' }}
            </span>
          </div>
        </div>

        <!-- 关联采购单（一单多采购单：主料/辅料各一张，不同采购员）——销售端不可见（生态硬约束） -->
        <div
          v-if="isMesStaff && (selected.purchaseOrders || []).length"
          class="pt-3 mt-3 border-t border-n-weak"
        >
          <div class="flex items-center justify-between mb-2">
            <span class="text-xs font-medium text-n-slate-11">
              关联采购单（{{ selected.purchaseOrders.length }}）
            </span>
            <span
              class="px-1.5 py-0.5 text-xs rounded-full shrink-0"
              :class="
                poKitSummary(selected.purchaseOrders).complete
                  ? 'bg-n-teal-3 text-n-teal-11'
                  : 'bg-n-amber-3 text-n-amber-11'
              "
            >
              {{
                poKitSummary(selected.purchaseOrders).complete
                  ? '已齐套'
                  : `待齐套 ${poKitSummary(selected.purchaseOrders).received}/${poKitSummary(selected.purchaseOrders).total}`
              }}
            </span>
          </div>
          <ul class="flex flex-col gap-1.5">
            <li
              v-for="po in selected.purchaseOrders"
              :key="po.id"
              class="flex items-center justify-between text-xs"
            >
              <span class="text-n-slate-12">
                {{ po.po_no }}
                <span class="text-n-slate-10">
                  · {{ po.owner_name || '—' }} · {{ po.item_count }} 项
                </span>
              </span>
              <span
                class="px-1.5 py-0.5 rounded-full shrink-0"
                :class="
                  po.status === 'RECEIVED'
                    ? 'bg-n-teal-3 text-n-teal-11'
                    : po.status === 'CANCELLED'
                      ? 'bg-n-slate-4 text-n-slate-10'
                      : 'bg-n-amber-3 text-n-amber-11'
                "
              >
                {{ poStatusLabel(po.status) }}
              </span>
            </li>
          </ul>
        </div>

        <!-- 定制规格（生产订单单据内容） -->
        <div
          v-if="selected.spec && selected.spec.template"
          class="pt-3 mt-3 border-t border-n-weak"
        >
          <div class="flex items-center justify-between mb-2">
            <span class="text-xs font-medium text-n-slate-11">
              定制规格 ·
              {{ (SPEC_TEMPLATES[selected.spec.template] || {}).label }}
            </span>
            <!-- 「查看订单」人人可见（只读整单）；「编辑订单」只给能改的人（制单人 / order 能力）。 -->
            <div class="flex items-center gap-1">
              <Button
                label="查看订单"
                variant="ghost"
                size="xs"
                @click="openEditSpec(selected, { viewOnly: true })"
              />
              <Button
                v-if="canEditSelected"
                label="编辑订单"
                variant="ghost"
                size="xs"
                @click="openEditSpec(selected)"
              />
            </div>
          </div>
          <MesOrderSpecForm
            :template="selected.spec.template"
            :spec="selected.spec"
            readonly
          />
        </div>

        <div
          v-if="selected.deliveryDate"
          class="flex items-center justify-between pt-3 mt-3 text-xs border-t text-n-slate-11 border-n-weak"
        >
          <span
            >交期：{{
              new Date(selected.deliveryDate).toLocaleDateString()
            }}</span
          >
          <span
            v-if="deliveryStatus(selected)"
            class="font-medium"
            :class="DUE_CLASS[deliveryStatus(selected).level]"
          >
            {{ deliveryStatus(selected).label }}
          </span>
        </div>

        <!-- 产品图片 -->
        <div class="pt-3 mt-3 border-t border-n-weak">
          <div class="flex items-center justify-between mb-2">
            <span class="text-xs font-medium text-n-slate-11">产品图片</span>
            <label
              v-if="canEditSelected"
              class="text-xs cursor-pointer text-n-iris-11 hover:underline"
            >
              上传图片
              <input
                type="file"
                accept="image/*"
                multiple
                class="hidden"
                :disabled="uploading"
                @change="e => onUpload(e, 'images')"
              />
            </label>
          </div>
          <div
            v-if="(selected.images || []).length"
            class="grid grid-cols-3 gap-2"
          >
            <div
              v-for="img in selected.images"
              :key="img.id"
              class="relative group"
            >
              <a :href="img.url" target="_blank" rel="noopener">
                <img
                  :src="img.url"
                  :alt="img.filename"
                  class="object-cover w-full h-20 rounded-lg border border-n-weak"
                />
              </a>
              <button
                v-if="canEditSelected"
                type="button"
                class="absolute top-1 right-1 items-center justify-center hidden w-5 h-5 text-xs text-white rounded-full bg-n-slate-12/70 group-hover:flex"
                @click="removeAttachment(img.id, 'images')"
              >
                ✕
              </button>
            </div>
          </div>
          <p v-else class="text-xs text-n-slate-10">暂无产品图片</p>
        </div>

        <!-- 附件 -->
        <div class="pt-3 mt-3 border-t border-n-weak">
          <div class="flex items-center justify-between mb-2">
            <span class="text-xs font-medium text-n-slate-11">附件</span>
            <label
              v-if="canEditSelected"
              class="text-xs cursor-pointer text-n-iris-11 hover:underline"
            >
              上传附件
              <input
                type="file"
                multiple
                class="hidden"
                :disabled="uploading"
                @change="e => onUpload(e, 'files')"
              />
            </label>
          </div>
          <ul v-if="(selected.files || []).length" class="flex flex-col gap-1">
            <li
              v-for="file in selected.files"
              :key="file.id"
              class="flex items-center justify-between text-xs group"
            >
              <a
                :href="file.url"
                target="_blank"
                rel="noopener"
                class="truncate text-n-iris-11 hover:underline"
              >
                {{ file.filename }}
              </a>
              <button
                v-if="canEditSelected"
                type="button"
                class="hidden ml-2 text-n-slate-10 hover:text-n-ruby-11 group-hover:block"
                @click="removeAttachment(file.id, 'files')"
              >
                ✕
              </button>
            </li>
          </ul>
          <p v-else class="text-xs text-n-slate-10">暂无附件</p>
        </div>
      </div>
    </div>

    <!-- 新建 / 编辑定制生产订单 -->
    <Dialog
      ref="orderDialogRef"
      :dismissible="false"
      width="2xl"
      overflow-y-auto
      confirm-button-color="iris"
      :title="orderDialogTitle"
      :is-loading="converting"
      :show-confirm-button="!viewOnlyOrder"
      :cancel-button-label="viewOnlyOrder ? '关闭' : undefined"
      :disable-confirm-button="orderInvalid"
      :dirty="isDirty"
      dirty-save-label="保存"
      @confirm="submitOrder"
      @close="markPristine"
      @save="submitOrder"
    >
      <div class="flex flex-col gap-4">
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">产品线 / 模板</label>
          <SelectCard
            size="form"
            :model-value="orderTemplate"
            :options="templateOptions"
            :disabled="!!editingOrderId"
            @update:model-value="setTemplate"
          />
        </div>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div class="flex flex-col sm:col-span-2 gap-1">
            <label class="text-heading-3 text-n-slate-12">PI 编号</label>
            <Input
              v-model="orderBase.piNo"
              :disabled="viewOnlyOrder"
              placeholder="形式发票号"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              成品名称&型号 <span class="text-n-ruby-11">*</span>
            </label>
            <Input v-model="orderBase.productName" :disabled="viewOnlyOrder" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              商品编码
              <span class="text-n-slate-10"
                >（选填，工程做生产任务单时补）</span
              >
            </label>
            <ComboBox
              v-model="orderBase.crmProductId"
              :options="orderProductOptions"
              use-api-results
              clearable
              :disabled="viewOnlyOrder"
              :display-label="selectedOrderProductLabel"
              placeholder="选择商品编码（选填，可留空）"
              search-placeholder="搜编码 / 名称"
              empty-state="无匹配商品"
              @open="onOrderProductOpen"
              @search="onOrderProductSearch"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              数量 <span class="text-n-ruby-11">*</span>
            </label>
            <Input
              v-model="orderBase.qty"
              type="number"
              :disabled="viewOnlyOrder"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">单位</label>
            <Input
              v-model="orderBase.unit"
              :disabled="viewOnlyOrder"
              placeholder="台 / 片 / pcs"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">期望交期</label>
            <!-- DatePicker 没有 disabled，只读时用容器锁交互（其余控件走各自的 disabled）。 -->
            <div :class="viewOnlyOrder ? 'pointer-events-none opacity-60' : ''">
              <DatePicker v-model="orderBase.deliveryDate" block />
            </div>
          </div>
        </div>

        <div class="pt-2 border-t border-n-weak">
          <MesOrderSpecForm
            v-model:spec="orderSpec"
            :template="orderTemplate"
            :readonly="viewOnlyOrder"
          />
        </div>
      </div>
    </Dialog>

    <!-- 转单弹窗 -->
    <Dialog
      ref="convertDialogRef"
      :dismissible="false"
      width="lg"
      confirm-button-color="iris"
      title="从销售订单转生产订单"
      description="选择销售订单与成品，生成生产订单；来源订单将自动进入「生产中」。"
      :is-loading="converting"
      :disable-confirm-button="convertInvalid"
      :dirty="isConvertDirty"
      dirty-save-label="保存"
      @confirm="submitConvert"
      @close="markConvertPristine"
      @save="submitConvert"
    >
      <div class="flex flex-col gap-4">
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">
            销售订单 <span class="text-n-ruby-11">*</span>
          </label>
          <ComboBox
            v-model="convertForm.crmSalesOrderId"
            :options="salesOrderOptions"
            placeholder="选择销售订单…"
            search-placeholder="搜索订单号 / PI / 客户…"
            empty-state="无匹配的销售订单"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">成品</label>
          <ComboBox
            v-model="convertForm.crmProductId"
            :options="productOptions"
            placeholder="选择成品（可选）"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">
            成品名称&型号 <span class="text-n-ruby-11">*</span>
          </label>
          <Input
            v-model="convertForm.productName"
            placeholder="未选成品时手填"
          />
        </div>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              生产数量 <span class="text-n-ruby-11">*</span>
            </label>
            <Input v-model="convertForm.qty" type="number" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">单位</label>
            <Input v-model="convertForm.unit" placeholder="台 / 片 / pcs" />
          </div>
        </div>
      </div>
    </Dialog>

    <!-- 查看 BOM 完整用料明细弹窗 -->
    <Dialog
      ref="bomViewDialogRef"
      :dismissible="false"
      width="5xl"
      :title="`工程/PMC 生产任务单明细${bomDetail?.bomNo ? ` · ${bomDetail.bomNo}` : ''}`"
      :show-confirm-button="false"
      cancel-button-label="关闭"
    >
      <div v-if="bomDetail" class="flex flex-col gap-3">
        <div class="flex flex-wrap gap-x-6 gap-y-1 text-sm text-n-slate-11">
          <span v-if="bomDetail.productName">
            产品：<span class="text-n-slate-12">{{
              bomDetail.productName
            }}</span>
          </span>
          <span v-if="bomDetail.baseQty">
            基准产量：<span class="text-n-slate-12">
              {{ bomDetail.baseQty }} {{ bomDetail.unit }}
            </span>
          </span>
          <span>
            用料项：<span class="text-n-slate-12">
              {{ bomDetail.bomItems ? bomDetail.bomItems.length : 0 }}
            </span>
          </span>
        </div>
        <div class="overflow-auto border rounded-lg border-n-weak max-h-[60vh]">
          <table class="w-full text-sm">
            <thead class="sticky top-0 bg-n-solid-2">
              <tr class="text-left text-n-slate-11">
                <th class="px-3 py-2 font-medium">#</th>
                <th class="px-3 py-2 font-medium whitespace-nowrap">
                  物料名称
                </th>
                <th class="px-3 py-2 font-medium whitespace-nowrap">料号</th>
                <th class="px-3 py-2 font-medium">规格</th>
                <th class="px-3 py-2 font-medium text-right whitespace-nowrap">
                  用量
                </th>
                <th class="px-3 py-2 font-medium whitespace-nowrap">类别</th>
                <th class="px-3 py-2 font-medium whitespace-nowrap">备注</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(it, idx) in bomDetail.bomItems"
                :key="it.id"
                class="border-t border-n-weak/60 text-n-slate-12"
              >
                <td class="px-3 py-2 text-n-slate-10">{{ idx + 1 }}</td>
                <td class="px-3 py-2 min-w-[11rem]">{{ it.materialName }}</td>
                <td class="px-3 py-2 whitespace-nowrap text-n-slate-11">
                  {{ it.materialNo || '—' }}
                </td>
                <td class="px-3 py-2 text-n-slate-11">
                  {{ it.specification || '—' }}
                </td>
                <td class="px-3 py-2 text-right whitespace-nowrap">
                  {{ it.qty }} {{ it.unit }}
                </td>
                <td class="px-3 py-2 whitespace-nowrap text-n-slate-11">
                  {{ categoryLabel(it.category) }}
                </td>
                <td class="px-3 py-2 text-n-slate-11">
                  {{ it.remark || '—' }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </Dialog>

    <!-- 标记外购弹窗（工程判定外购成品：选产品+供应商，跳过 BOM 直接进采购） -->
    <!-- 无需采购：料现成在库里，跳过采购直接进「原料入库」好让领料开单 -->
    <Dialog
      ref="skipPurchaseDialogRef"
      :dismissible="false"
      confirm-button-color="iris"
      confirm-button-label="确认无需采购"
      title="无需采购 · 用库存料"
      :description="
        selected
          ? `「${selected.orderNo}」的料从现有库存出，不走采购。确认后订单直接进入「原料入库」阶段，领料页就能选到它——不会产生任何库存变动，料在领料时正常扣减。`
          : ''
      "
      :is-loading="uiFlags.updatingItem"
      @confirm="submitSkipPurchasing"
    >
      <div class="flex flex-col gap-1">
        <label class="text-heading-3 text-n-slate-12">原因（选填）</label>
        <Input
          v-model="skipPurchaseReason"
          placeholder="如：库存充足，无需采购"
        />
        <p class="mt-1 text-label-small text-n-slate-10">
          会记在订单的阶段轨迹里，以后查得到这张单为什么没有采购记录。
        </p>
      </div>
    </Dialog>

    <Dialog
      ref="outsourceDialogRef"
      :dismissible="false"
      width="3xl"
      confirm-button-color="iris"
      title="标记外购成品"
      description="外购成品不走生产：选定产品与供应商后，订单直接进入采购阶段，由采购按单下采购单。跳过生产任务单/领料/报工/质检。"
      :is-loading="uiFlags.updatingItem"
      :disable-confirm-button="outsourceInvalid"
      @confirm="submitMarkOutsourced"
    >
      <div class="flex flex-col gap-4">
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">
            外购成品 <span class="text-n-ruby-11">*</span>
          </label>
          <MesProductPicker
            :account-id="accountId"
            :model-value="outsourceForm.crmProductId"
            :display-text="outsourceForm.productName"
            placeholder="搜索并选择外购成品（编码/名称/规格）"
            @update:model-value="v => (outsourceForm.crmProductId = v)"
            @select="p => (outsourceForm.productName = p.name)"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">
            供应商 <span class="text-n-ruby-11">*</span>
          </label>
          <ComboBox
            :model-value="outsourceForm.supplierId"
            :options="supplierOptions"
            placeholder="选择供应商"
            search-placeholder="搜索供应商"
            @update:model-value="v => (outsourceForm.supplierId = v)"
          />
        </div>
      </div>
    </Dialog>

    <!-- 关联已有 BOM 弹窗（复用现成 BOM 直接挂到本单，挂好即可下发采购） -->
    <Dialog
      ref="linkBomDialogRef"
      :dismissible="false"
      width="3xl"
      confirm-button-color="iris"
      title="关联已有生产任务单"
      description="把一张已存在的生产任务单直接关联到本订单，挂好后由工程/PMC 下发采购，无需重新建生产任务单。"
      :is-loading="uiFlags.updatingItem"
      :disable-confirm-button="!linkBomId"
      @confirm="submitLinkBom"
    >
      <div class="flex flex-col gap-1">
        <div class="flex items-center justify-between">
          <label class="text-heading-3 text-n-slate-12">
            选择生产任务单 <span class="text-n-ruby-11">*</span>
          </label>
          <label
            class="flex items-center gap-1.5 text-heading-3 text-n-slate-12"
          >
            <input
              type="checkbox"
              class="accent-n-iris-9"
              :checked="linkBomAllProducts"
              @change="toggleLinkBomScope"
            />
            显示全部产品的生产任务单
          </label>
        </div>
        <ComboBox
          :model-value="linkBomId"
          :options="linkBomOptions"
          placeholder="选择要关联的生产任务单"
          search-placeholder="搜索生产任务单号 / 产品"
          @update:model-value="v => (linkBomId = v)"
        />
        <p v-if="!linkBomOptions.length" class="text-xs text-n-slate-10">
          {{
            linkBomAllProducts
              ? '还没有任何生产任务单，请先去「工程生产任务单」新建。'
              : '本产品还没有生产任务单，可勾选上方「显示全部产品的生产任务单」，或去新建。'
          }}
        </p>
      </div>
    </Dialog>

    <!-- 接单之后：把下一步要建的单直接递到手上 -->
    <Dialog
      ref="nextDocDialogRef"
      :title="`已接单：${selected?.orderNo || ''}`"
      :description="
        nextDoc ? `下一步是给这张订单建${nextDoc.label}，现在就去？` : ''
      "
      :confirm-button-label="nextDoc ? `去建${nextDoc.label}` : '好'"
      cancel-button-label="稍后"
      @confirm="goNextDoc"
    />

    <Dialog
      ref="handoffDialogRef"
      :dismissible="false"
      title="转给本阶段另一位负责人"
      description="转出后你不再是接单人，对方会收到「待你接单」提醒。阶段不变，超时计时也不重置。"
      :is-loading="uiFlags.updatingItem"
      :disable-confirm-button="!handoffToId"
      @confirm="confirmHandoff"
    >
      <div class="flex flex-col gap-3">
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">
            转给谁 <span class="text-n-ruby-11">*</span>
          </label>
          <SelectCard
            v-model="handoffToId"
            :options="
              handoffCandidates.map(o => ({
                value: String(o.id),
                label: o.name,
              }))
            "
            block
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">说明（选填）</label>
          <Input v-model="handoffNote" />
        </div>
      </div>
    </Dialog>

    <Dialog
      ref="rejectDialogRef"
      :dismissible="false"
      confirm-button-color="ruby"
      title="拒收打回上一阶段"
      description="退回后责任明确回上游，上一阶段重新计时、需重新接单。"
      :is-loading="uiFlags.updatingItem"
      :disable-confirm-button="!rejectReason.trim()"
      @confirm="confirmReject"
    >
      <div class="flex flex-col gap-1">
        <label class="text-heading-3 text-n-slate-12">
          退回原因 <span class="text-n-ruby-11">*</span>
        </label>
        <Input v-model="rejectReason" />
      </div>
    </Dialog>

    <!-- 审批驳回：退回业务员，可改后重提 -->
    <Dialog
      ref="denyDialogRef"
      :dismissible="false"
      confirm-button-color="ruby"
      title="驳回生产订单"
      description="驳回后退回创建人，可修改后重新提交，重走审批流程。"
      :is-loading="uiFlags.updatingItem"
      :disable-confirm-button="!denyReason.trim()"
      @confirm="confirmDeny"
    >
      <div class="flex flex-col gap-1">
        <label class="text-heading-3 text-n-slate-12">
          驳回原因 <span class="text-n-ruby-11">*</span>
        </label>
        <Input v-model="denyReason" />
      </div>
    </Dialog>

    <MesOrderStockEntriesDialog ref="stockEntriesDialog" />

    <!-- 订单明细：建单时填的规格表（只读）+ 导出 -->
    <Dialog
      ref="detailDialogRef"
      :dismissible="false"
      width="3xl"
      overflow-y-auto
      :show-confirm-button="false"
      cancel-button-label="关闭"
      :title="viewingOrder ? `订单明细 ${viewingOrder.orderNo}` : '订单明细'"
    >
      <div v-if="viewingOrder" class="flex flex-col gap-4 text-sm">
        <div class="flex justify-end gap-2">
          <Button
            label="转发/知会"
            icon="i-lucide-send"
            variant="outline"
            color="iris"
            size="sm"
            @click="openForward"
          />
          <Button
            label="导出 Excel"
            variant="outline"
            color="slate"
            size="sm"
            @click="exportDetailExcel"
          />
          <Button
            label="导出图片"
            variant="outline"
            color="slate"
            size="sm"
            @click="exportDetailJpg"
          />
          <Button
            label="打印"
            variant="outline"
            color="slate"
            size="sm"
            @click="printDetail"
          />
        </div>
        <div
          ref="detailContentRef"
          class="flex flex-col gap-4 p-4 bg-white rounded-lg"
        >
          <div class="grid grid-cols-2 sm:grid-cols-3 gap-x-4 gap-y-3">
            <div
              v-for="f in viewBaseFields"
              :key="f.label"
              class="flex flex-col"
            >
              <span class="text-xs text-n-slate-10">{{ f.label }}</span>
              <span class="text-n-slate-12">{{ f.value }}</span>
            </div>
          </div>

          <div class="pt-2 border-t border-n-weak">
            <div
              class="mb-2 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
            >
              定制规格
            </div>
            <MesOrderSpecForm
              :template="viewTemplate"
              :spec="viewSpec"
              readonly
            />
          </div>

          <!-- 材料明细（该单 BOM 用料，对标金蝶「材料明细」）-->
          <div
            v-if="viewingOrder.bomItems && viewingOrder.bomItems.length"
            class="pt-2 border-t border-n-weak"
          >
            <div
              class="mb-2 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
            >
              材料明细（{{ viewingOrder.bomItems.length }} 项）
            </div>
            <div class="overflow-x-auto">
              <table class="w-full text-sm md:min-w-[560px]">
                <thead>
                  <tr class="text-left text-n-slate-10 whitespace-nowrap">
                    <th class="py-1.5 pr-3 font-medium w-10">#</th>
                    <th class="py-1.5 pr-3 font-medium">物料编码</th>
                    <th class="py-1.5 pr-3 font-medium">物料名称</th>
                    <th class="py-1.5 pr-3 font-medium">规格型号</th>
                    <th class="py-1.5 pr-3 font-medium">辅助属性</th>
                    <th class="py-1.5 pr-3 font-medium">单位</th>
                    <th class="py-1.5 pr-3 font-medium text-right">用量</th>
                    <th class="py-1.5 pr-3 font-medium">备注</th>
                    <th class="py-1.5 pr-3 font-medium">生产备注</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    v-for="(bi, idx) in viewingOrder.bomItems"
                    :key="idx"
                    class="border-t border-n-weak/60"
                  >
                    <td class="py-1.5 pr-3 tabular-nums text-n-slate-10">
                      {{ idx + 1 }}
                    </td>
                    <td class="py-1.5 pr-3 whitespace-nowrap text-n-slate-11">
                      {{ bi.materialNo || '—' }}
                    </td>
                    <td class="py-1.5 pr-3 text-n-slate-12">
                      {{ bi.materialName }}
                    </td>
                    <td class="py-1.5 pr-3 text-n-slate-11">
                      {{ bi.specification || '—' }}
                    </td>
                    <td class="py-1.5 pr-3 text-n-slate-11">
                      {{ bi.auxAttributeName || '—' }}
                    </td>
                    <td class="py-1.5 pr-3 whitespace-nowrap text-n-slate-11">
                      {{ bi.unit || '—' }}
                    </td>
                    <td
                      class="py-1.5 pr-3 text-right whitespace-nowrap text-n-slate-12"
                    >
                      {{ bi.qty }}
                    </td>
                    <!-- 本行没写备注就显产品档案上的工艺要求，车间照这个做 -->
                    <td class="py-1.5 pr-3 text-n-slate-11">
                      <span v-if="bi.remark">{{ bi.remark }}</span>
                      <span
                        v-else-if="bi.productRemark"
                        class="text-n-slate-10"
                        :title="`产品档案备注：${bi.productRemark}`"
                      >
                        {{ bi.productRemark }}
                      </span>
                      <span v-else>—</span>
                    </td>
                    <td class="py-1.5 pr-3 text-n-slate-11">
                      {{ bi.productionNote || '—' }}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          <div
            v-if="viewingOrder.images && viewingOrder.images.length"
            class="pt-2 border-t border-n-weak"
          >
            <div
              class="mb-2 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
            >
              产品图片
            </div>
            <div class="flex flex-wrap gap-2">
              <img
                v-for="img in viewingOrder.images"
                :key="img.id"
                :src="img.url"
                class="object-cover w-20 h-20 border rounded border-n-weak"
              />
            </div>
          </div>

          <div
            v-if="viewingOrder.files && viewingOrder.files.length"
            class="pt-2 border-t border-n-weak"
          >
            <div
              class="mb-2 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
            >
              附件
            </div>
            <ul class="flex flex-col gap-1">
              <li v-for="af in viewingOrder.files" :key="af.id">
                <a
                  :href="af.url"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-n-iris-11 hover:underline"
                >
                  {{ af.filename }}
                </a>
              </li>
            </ul>
          </div>
        </div>

        <!-- 知会记录（留痕）：谁在何时把订单知会给了哪个阶段负责人 + 附言 -->
        <div
          v-if="viewingOrder.orderForwards && viewingOrder.orderForwards.length"
          class="pt-2 border-t border-n-weak"
        >
          <div
            class="mb-2 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
          >
            知会记录
          </div>
          <ul class="flex flex-col gap-2">
            <li
              v-for="fwd in viewingOrder.orderForwards"
              :key="fwd.id"
              class="px-3 py-2 rounded-lg bg-n-alpha-1"
            >
              <div class="flex flex-wrap items-center gap-x-2 gap-y-0.5">
                <span class="font-medium text-n-slate-12">{{
                  fwd.senderName || '业务'
                }}</span>
                <span class="text-xs text-n-slate-10">知会</span>
                <span class="text-xs text-n-iris-11">{{ fwd.stageLabel }}</span>
                <span class="text-xs text-n-slate-11">{{
                  fwd.recipientNames ? `· ${fwd.recipientNames}` : ''
                }}</span>
                <span class="ml-auto text-xs text-n-slate-10">{{
                  new Date(fwd.createdAt).toLocaleString()
                }}</span>
              </div>
              <p v-if="fwd.note" class="mt-1 text-n-slate-12">{{ fwd.note }}</p>
            </li>
          </ul>
        </div>
      </div>
    </Dialog>

    <!-- 转发/知会：选阶段负责人 + 附言，推站内通知并在订单上留痕 -->
    <Dialog
      ref="forwardDialogRef"
      title="转发 / 知会阶段负责人"
      confirm-button-label="发送知会"
      confirm-button-color="iris"
      :is-loading="forwardBusy"
      :disable-confirm-button="!forwardBoardKey"
      @confirm="submitForward"
    >
      <div class="flex flex-col gap-4">
        <div class="flex flex-col gap-1.5">
          <label class="text-heading-3 text-n-slate-12">知会给</label>
          <SelectCard
            v-model="forwardBoardKey"
            :options="forwardOptions"
            placeholder="选择阶段负责人"
            block
          />
        </div>
        <div class="flex flex-col gap-1.5">
          <label class="text-heading-3 text-n-slate-12">附言（选填）</label>
          <textarea
            v-model="forwardNote"
            rows="3"
            class="px-3 py-2 text-sm border rounded-lg outline-none resize-y border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="想让对方注意的事项"
          />
        </div>
        <p class="text-xs text-n-slate-10">
          对方会收到站内通知并可跳到本订单；本次知会会记录在订单「知会记录」里。
        </p>
      </div>
    </Dialog>
  </div>
</template>
