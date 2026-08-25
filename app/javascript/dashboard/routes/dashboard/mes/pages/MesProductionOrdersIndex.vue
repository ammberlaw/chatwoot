<script setup>
/* global axios */
import { ref, computed, reactive, onMounted, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import camelcaseKeys from 'camelcase-keys';
import MesProductPicker from 'dashboard/components-next/mes/MesProductPicker.vue';
import { useMesProductionOrdersStore } from 'dashboard/stores/mes/productionOrders';
import { useMesBomsStore } from 'dashboard/stores/mes/boms';
import MesBomAPI from 'dashboard/api/mes/boms';
import { useMesRole } from 'dashboard/composables/useMesRole';
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
  { value: 'BOM_READY', label: '工程/PMC BOM' },
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
const stageIndex = value => STAGES.findIndex(s => s.value === value);
const stageLabel = value => STAGES[stageIndex(value)]?.label || value;
// 外购按单短版脊柱：时间线只显示 销售订单确定 → 采购 → 成品入库 → 出库。
const OUTSOURCE_STAGE_VALUES = [
  'SALES_CONFIRMED',
  'PURCHASING',
  'FG_INBOUND',
  'SHIPPED',
];

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

// 视图：all 列表（再按 listScope 分档）/ inbox 待我确认（停在我这一级的审批单 + 待我二次确认 BOM 的单）。
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
    { label: '产品编码', value: o.productCode || '—' },
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
  return selected.value?.stage === 'SHIPPED' ? '' : `进行中 · 已 ${days} 天`;
};

// 当前阶段滞留天数（未出货才算）。
const stallDays = po => {
  if (!po || po.stage === 'SHIPPED') return 0;
  const ev = (po.stageEvents || []).find(e => e.stage === po.stage);
  if (!ev?.enteredAt) return 0;
  return Math.round((Date.now() - new Date(ev.enteredAt)) / DAY);
};
const isStalled = po => stallDays(po) >= STALL_DAYS;

// 列表阶段列的「等谁」：当前阶段负责人（未配则空；建单/出货阶段无板块负责人）。
const stageWaitingText = po =>
  (po?.stageOwnerNames || []).length
    ? `等：${po.stageOwnerNames.join('、')}`
    : '';

// 列表阶段列的接单态徽标（与详情面板同口径）：已接单 / 超时未接单 / 待接单。
const ackChip = po => {
  if (!po || po.stage === 'SHIPPED') return null;
  if (po.stageAckAt) return { text: '✓ 已接单', cls: 'text-n-teal-11' };
  if (po.ackOverdue) return { text: '🔴 超时未接单', cls: 'text-n-ruby-11' };
  if (po.awaitingAck) return { text: '⏳ 待接单', cls: 'text-n-amber-11' };
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
const orderSpec = ref(blankSpec('TABLET'));
const orderInvalid = computed(
  () =>
    !orderBase.crmProductId ||
    !orderBase.productName.trim() ||
    !Number(orderBase.qty)
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
// 新建走整页建档页；本弹框仅用于编辑规格。
const openNewOrder = () =>
  router.push(accountScopedRoute('mes_production_order_intake_index'));
const openEditSpec = order => {
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
  orderDialogRef.value?.open();
};
const submitOrder = async () => {
  if (orderInvalid.value) return;
  const payload = {
    piNo: orderBase.piNo.trim() || undefined,
    crmProductId: orderBase.crmProductId
      ? Number(orderBase.crmProductId)
      : undefined,
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

// —— 挂 BOM（阶段 2 触点）——
const bomsStore = useMesBomsStore();

// 业务二次确认前要能看到工程做的用料清单：订单详情选中且已挂 BOM 时，按 bomId 拉 BOM 明细。
const CATEGORY_LABELS = { MACHINE: '整机生产物料', PACKAGING: '包装物料' };
const categoryLabel = c => CATEGORY_LABELS[c] || '整机生产物料';
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

const bomDialogRef = ref(null);
const bomForm = ref({ bomId: '', deliveryDate: '' });
const attaching = computed(
  () => bomsStore.getUIFlags.updatingItem || uiFlags.value.updatingItem
);
const bomOptions = computed(() => [
  { value: '', label: '选择 BOM…' },
  // 只列已下发的 BOM，草稿不可挂。
  ...(bomsStore.getRecords || [])
    .filter(b => b.status === 'RELEASED')
    .map(b => ({
      value: String(b.id),
      label: `${b.bomNo}${b.productName ? ` · ${b.productName}` : ''}`,
    })),
]);
const openAttachBom = () => {
  // 期望交期预填订单现有交期，工程/PMC 可在此确认或调整。
  bomForm.value = {
    bomId: '',
    deliveryDate: selected.value?.deliveryDate
      ? String(selected.value.deliveryDate).slice(0, 10)
      : '',
  };
  if (!bomsStore.getRecords?.length) bomsStore.get();
  bomDialogRef.value?.open();
};
const submitAttachBom = async () => {
  if (!bomForm.value.bomId || !selected.value) return;
  const ok = await store.attachBom({
    id: selected.value.id,
    bomId: Number(bomForm.value.bomId),
    deliveryDate: bomForm.value.deliveryDate || undefined,
  });
  if (ok) {
    useAlert('已挂 BOM，进入「工程/PMC BOM」阶段');
    selected.value = ok;
    bomDialogRef.value?.close();
    fetchRecords();
  }
};

// 业务二次确认 BOM（BOM_READY 段内的闸，确认后方可下发采购）。
const confirmBom = async () => {
  if (!selected.value) return;
  const ok = await store.confirmBom(selected.value.id);
  if (ok) {
    useAlert('BOM 已二次确认，可下发采购');
    selected.value = ok;
    fetchRecords();
  }
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

// —— 审批链（取代发布）：草稿→部门主管→总经理 ——
const APPROVAL_LABELS = {
  DRAFT: '草稿',
  SUBMITTED: '待部门主管',
  MANAGER_APPROVED: '待总经理',
  APPROVED: '已通过·生效',
  REJECTED: '已驳回',
};
const approvalComment = ref('');

const isOwner = computed(() => selected.value?.ownerId === currentUserId.value);
// 编辑规格/图片/附件：order 能力全量；业务角色仅本人草稿（后端 ensure_own_draft! 同口径）。
const canEditSelected = computed(
  () =>
    mesCan('order') ||
    (canCreateOrder.value && isOwner.value && selected.value?.isDraft)
);
// 列表行级「编辑」：与 canEditSelected 同口径（order 能力 / 本人草稿），
// 且订单须有定制规格表（编辑弹窗基于规格模板，外购单无规格不走此入口）。
const canEditRow = po =>
  !!po.spec?.template &&
  (mesCan('order') ||
    (canCreateOrder.value && po.ownerId === currentUserId.value && po.isDraft));
// 业务二次确认 BOM：BOM_READY 段、已挂 BOM 且未确认，创建人（业务员）或管理员可确认。
const canConfirmBom = computed(() => {
  const po = selected.value;
  if (!po) return false;
  return (
    po.stage === 'BOM_READY' &&
    po.bomNo &&
    !po.bomConfirmedAt &&
    (isOwner.value || isAdmin.value || isCrmDeputyAdmin.value)
  );
});
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
const approvalBoxClass = computed(() => {
  const s = selected.value?.approvalStatus;
  if (s === 'APPROVED') return 'bg-n-teal-2 border-n-teal-6';
  if (s === 'REJECTED') return 'bg-n-ruby-2 border-n-ruby-6';
  if (s === 'DRAFT') return 'bg-n-slate-3 border-n-weak';
  return 'bg-n-amber-2 border-n-amber-6';
});
const approvalTextClass = computed(() => {
  const s = selected.value?.approvalStatus;
  if (s === 'APPROVED') return 'text-n-teal-11';
  if (s === 'REJECTED') return 'text-n-ruby-11';
  if (s === 'DRAFT') return 'text-n-slate-11';
  return 'text-n-amber-11';
});

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
// 只有本阶段负责人本人或管理员能接单/拒收。
const canHandleStage = computed(() => {
  const po = selected.value;
  if (!po || po.stage === 'SHIPPED' || po.status !== 'IN_PROGRESS')
    return false;
  return (
    isAdmin.value ||
    isCrmDeputyAdmin.value ||
    (po.stageOwnerIds || []).includes(currentUserId.value)
  );
});
const fmtDateTime = d =>
  d ? new Date(d).toLocaleString(undefined, { hour12: false }) : '';

const acknowledge = async () => {
  if (!selected.value) return;
  const ok = await store.acknowledge(selected.value.id);
  if (ok) {
    useAlert('已接单');
    selected.value = ok;
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

// —— 产品编码（工程/PMC 编写，唯一，供 ERP 共享）——
const canEditProductCode = computed(() => mesCan('bom'));
const productCodeInput = ref('');
const productCodeError = ref('');
watch(
  selected,
  po => {
    productCodeInput.value = po?.productCode || '';
    productCodeError.value = '';
  },
  { immediate: true }
);
const saveProductCode = async () => {
  if (!selected.value) return;
  productCodeError.value = '';
  try {
    const ok = await store.setProductCode({
      id: selected.value.id,
      productCode: productCodeInput.value.trim(),
    });
    if (ok) {
      useAlert('产品编码已保存');
      selected.value = ok;
      fetchRecords();
    }
  } catch (e) {
    productCodeError.value = e?.response?.data?.error || '保存失败';
  }
};

const rootStore = useStore();
onMounted(async () => {
  // 纯业务员没有「全部」页签，默认落到「我的订单」，避免默认档无对应高亮页签。
  if (isPlainSales.value && listScope.value === 'all') listScope.value = 'mine';
  // 从看板「待我审批」跳转：进「待我审批」视图。
  if (route.query.view === 'approval') viewMode.value = 'inbox';
  if (!agents.value?.length) rootStore.dispatch('agents/get');
  await fetchRecords();
  // 从看板交期预警/待我审批跳转过来：按订单号自动打开详情面板。
  const q = route.query.q ? String(route.query.q) : '';
  if (q) {
    const match = records.value.find(r => r.orderNo === q);
    if (match) selected.value = match;
  }
});
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
      <div class="flex flex-wrap gap-2">
        <Button
          v-if="canCreateOrder"
          label="新建生产订单"
          color="iris"
          size="sm"
          @click="openNewOrder"
        />
        <Button
          v-if="mesCan('order')"
          label="从销售订单转入"
          variant="outline"
          color="slate"
          size="sm"
          @click="openConvert"
        />
      </div>
    </div>

    <!-- 视图切换：我的订单 / 库存备货 / 全部 / 待我确认（前后两个仅 CRM 业务身份显示） -->
    <div class="flex flex-wrap items-center gap-2 px-4 pb-2 sm:px-6">
      <button
        v-if="isCrmMember"
        class="px-3 py-1.5 text-sm rounded-lg border"
        :class="
          tabActive('all', 'mine')
            ? 'border-n-iris-8 bg-n-iris-3 text-n-iris-12'
            : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
        "
        @click="setListScope('mine')"
      >
        我的订单
      </button>
      <!-- 库存备货：PMC（建备货单）与业务身份（卖共享库存）可见；采购/车间/仓库隐藏 -->
      <button
        v-if="isCrmMember || mesCan('order')"
        class="px-3 py-1.5 text-sm rounded-lg border"
        :class="
          tabActive('all', 'stock')
            ? 'border-n-iris-8 bg-n-iris-3 text-n-iris-12'
            : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
        "
        @click="setListScope('stock')"
      >
        库存备货
      </button>
      <button
        v-if="canSeeAllScope"
        class="px-3 py-1.5 text-sm rounded-lg border"
        :class="
          tabActive('all', 'all')
            ? 'border-n-iris-8 bg-n-iris-3 text-n-iris-12'
            : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
        "
        @click="setListScope('all')"
      >
        全部
      </button>
      <button
        v-if="isCrmMember"
        class="px-3 py-1.5 text-sm rounded-lg border"
        :class="
          tabActive('inbox')
            ? 'border-n-iris-8 bg-n-iris-3 text-n-iris-12'
            : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
        "
        @click="setViewMode('inbox')"
      >
        待我确认
      </button>
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
      <input
        v-model="searchQuery"
        type="text"
        placeholder="搜索 工单号 / 成品名…"
        class="h-9 px-3 text-sm rounded-lg outline-none w-full sm:w-44 border border-n-weak bg-n-solid-1 text-n-slate-12"
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
              :class="{ 'bg-n-alpha-1': selected && selected.id === po.id }"
              @click="selectRow(po)"
            >
              <div class="flex items-center gap-2">
                <span class="font-medium text-n-slate-12 truncate">
                  {{ po.orderNo }}
                </span>
                <span
                  class="shrink-0 px-2 py-0.5 text-xs rounded-full bg-n-iris-3 text-n-iris-11"
                >
                  {{ stageLabel(po.stage) }}
                </span>
                <span
                  v-if="isStalled(po)"
                  class="shrink-0 text-xs text-n-amber-11"
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
                </div>
              </div>
              <div
                class="flex flex-wrap items-center gap-x-2 gap-y-0.5 mt-1 text-xs"
              >
                <span
                  v-if="po.orderKind === 'STOCK'"
                  class="px-1.5 py-0.5 rounded-full bg-n-teal-3 text-n-teal-11"
                >
                  外贸库存备货
                </span>
                <span
                  v-if="po.isOutsourced"
                  class="px-1.5 py-0.5 rounded-full bg-n-amber-3 text-n-amber-11"
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
                <span>数量：{{ po.producedQty }} / {{ po.qty }} {{ po.unit }}</span>
                <span v-if="po.piNo">PI {{ po.piNo }}</span>
                <span v-if="po.productCode" class="text-n-iris-11">
                  编码 {{ po.productCode }}
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
                <span v-if="po.salesOrderNo">来源：{{ po.salesOrderNo }}</span>
                <span>负责人：{{ po.ownerName || '—' }}</span>
              </div>
              <div
                v-if="stageWaitingText(po) || ackChip(po)"
                class="mt-1 text-[11px] leading-tight text-n-slate-10"
              >
                <span v-if="stageWaitingText(po)" class="block truncate">
                  {{ stageWaitingText(po) }}
                </span>
                <span v-if="ackChip(po)">
                  <span :class="ackChip(po).cls">{{ ackChip(po).text }}</span>
                  <span v-if="stallDays(po) > 0">
                    · 停留 {{ stallDays(po) }} 天</span>
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

          <table class="hidden md:table w-full text-sm">
            <thead>
              <tr class="text-left text-n-slate-11 border-b border-n-weak">
                <th class="px-3 py-3 font-medium">工单号</th>
                <th class="px-3 py-3 font-medium">成品</th>
                <th class="px-3 py-3 font-medium">数量</th>
                <th class="px-3 py-3 font-medium">阶段</th>
                <th class="px-3 py-3 font-medium">交期</th>
                <th class="px-3 py-3 font-medium">来源销售单</th>
                <th class="px-3 py-3 font-medium">负责人</th>
                <th class="px-3 py-3" />
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="po in records"
                :key="po.id"
                class="border-b cursor-pointer border-n-weak hover:bg-n-alpha-1"
                :class="{ 'bg-n-alpha-1': selected && selected.id === po.id }"
                @click="selectRow(po)"
              >
                <td class="px-3 py-3 font-medium text-n-slate-12">
                  {{ po.orderNo }}
                  <span
                    v-if="po.orderKind === 'STOCK'"
                    class="ml-1 px-1.5 py-0.5 text-xs rounded-full bg-n-teal-3 text-n-teal-11"
                    title="外贸库存备货订单：全业务共享库存"
                  >
                    外贸库存备货
                  </span>
                  <span
                    v-if="po.isOutsourced"
                    class="ml-1 px-1.5 py-0.5 text-xs rounded-full bg-n-amber-3 text-n-amber-11"
                    title="外购成品：工程判定外购，跳过生产，采购按单买"
                  >
                    外购
                  </span>
                  <span
                    v-if="po.approvalStatus && po.approvalStatus !== 'APPROVED'"
                    class="ml-1 px-1.5 py-0.5 text-xs rounded-full"
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
                    v-if="po.productCode"
                    class="block text-xs font-normal text-n-iris-11"
                  >
                    编码 {{ po.productCode }}
                  </span>
                </td>
                <td class="px-3 py-3 text-n-slate-11">{{ po.productName }}</td>
                <td class="px-3 py-3 text-n-slate-11">
                  {{ po.producedQty }} / {{ po.qty }} {{ po.unit }}
                </td>
                <td class="px-3 py-3 align-top">
                  <div class="flex items-center">
                    <span
                      class="inline-flex items-center px-2 py-0.5 text-xs rounded-full bg-n-iris-3 text-n-iris-11"
                    >
                      {{ stageLabel(po.stage) }}
                    </span>
                    <span
                      v-if="isStalled(po)"
                      v-tooltip.top="`本阶段已滞留 ${stallDays(po)} 天`"
                      class="ml-1 text-xs text-n-amber-11"
                    >
                      ⚠
                    </span>
                  </div>
                  <!-- 卡在谁那·卡了多久·接单态：不点开也一眼看清 -->
                  <div class="mt-1 text-[11px] leading-tight text-n-slate-10">
                    <span v-if="stageWaitingText(po)" class="block truncate">
                      {{ stageWaitingText(po) }}
                    </span>
                    <span v-if="ackChip(po)">
                      <span :class="ackChip(po).cls">{{
                        ackChip(po).text
                      }}</span>
                      <span v-if="stallDays(po) > 0">
                        · 停留 {{ stallDays(po) }} 天</span>
                    </span>
                  </div>
                </td>
                <td class="px-3 py-3 text-xs">
                  <span
                    v-if="deliveryStatus(po)"
                    :class="DUE_CLASS[deliveryStatus(po).level]"
                  >
                    {{ deliveryStatus(po).label }}
                  </span>
                  <span v-else class="text-n-slate-10">—</span>
                </td>
                <td class="px-3 py-3 text-n-slate-11">
                  {{ po.salesOrderNo || '—' }}
                </td>
                <td class="px-3 py-3 text-n-slate-11">
                  {{ po.ownerName || '—' }}
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
                <td colspan="8" class="px-3 py-10 text-center text-n-slate-11">
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
        class="flex flex-col p-5 overflow-auto w-full md:w-80 shrink-0 rounded-xl bg-n-alpha-black1 border border-n-weak"
      >
        <div class="flex items-center justify-between mb-1">
          <span class="font-semibold text-n-slate-12">{{
            selected.orderNo
          }}</span>
          <span class="text-xs text-n-slate-11">
            {{ STATUS_LABELS[selected.status] }}
          </span>
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

        <!-- 产品编码：工程/PMC 编写（唯一，供 ERP 共享） -->
        <div class="mb-4">
          <div v-if="canEditProductCode" class="flex flex-col gap-1">
            <label class="text-xs text-n-slate-11">
              产品编码
              <span class="text-n-slate-10">（工程/PMC 编，唯一）</span>
            </label>
            <div class="flex items-center gap-2">
              <Input
                v-model="productCodeInput"
                placeholder="如：C.BB.215.003"
                class="flex-1"
              />
              <Button
                label="保存"
                size="xs"
                color="iris"
                :is-loading="uiFlags.updatingItem"
                :disabled="
                  productCodeInput.trim() === (selected.productCode || '')
                "
                @click="saveProductCode"
              />
            </div>
            <span v-if="productCodeError" class="text-xs text-n-ruby-11">
              {{ productCodeError }}
            </span>
          </div>
          <div v-else class="text-xs text-n-slate-11">
            产品编码：{{ selected.productCode || '未编码' }}
          </div>
        </div>

        <!-- 审批链（取代发布）：草稿→部门主管→总经理，全部通过才生效 -->
        <div
          class="flex flex-col gap-2 p-3 mb-4 rounded-lg border"
          :class="approvalBoxClass"
        >
          <div class="flex items-center justify-between">
            <span class="text-xs font-medium" :class="approvalTextClass">
              审批 · {{ APPROVAL_LABELS[selected.approvalStatus] }}
            </span>
            <!-- 归属人：草稿/被驳回可提交 -->
            <Button
              v-if="
                isOwner &&
                ['DRAFT', 'REJECTED'].includes(selected.approvalStatus)
              "
              :label="
                selected.approvalStatus === 'REJECTED' ? '重新提交' : '提交审批'
              "
              color="iris"
              size="xs"
              :is-loading="uiFlags.updatingItem"
              @click="submitApproval"
            />
          </div>

          <!-- 审批人可通过/驳回 -->
          <div v-if="canApprove" class="flex flex-col gap-2">
            <textarea
              v-model="approvalComment"
              rows="2"
              placeholder="审批意见（选填）"
              class="px-2 py-1.5 text-xs border rounded-lg outline-none resize-y border-n-weak bg-n-alpha-black1 text-n-slate-12"
            />
            <div class="flex gap-2">
              <Button
                label="通过"
                color="teal"
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

          <!-- 审批留痕：提交/主管/总经理 -->
          <div class="flex flex-col gap-1 text-xs text-n-slate-11">
            <div v-if="selected.submittedAt">
              📤 提交 · {{ selected.ownerName }} ·
              {{ fmtDateTime(selected.submittedAt) }}
            </div>
            <div v-if="selected.managerActedAt">
              <span
                :class="
                  selected.approvalStatus === 'REJECTED'
                    ? 'text-n-ruby-11'
                    : 'text-n-teal-11'
                "
              >
                {{
                  selected.approvalStatus === 'REJECTED'
                    ? '⛔ 主管驳回'
                    : '✅ 主管通过'
                }}
              </span>
              · {{ selected.managerName }} ·
              {{ fmtDateTime(selected.managerActedAt) }}
              <span v-if="selected.managerComment">
                · {{ selected.managerComment }}</span
              >
            </div>
            <div v-else-if="selected.approvalStatus === 'SUBMITTED'">
              ⏳ 待部门主管审批 ·
              {{ selected.managerName || '未解析到主管，将转总经理' }}
            </div>
            <div v-if="selected.gmActedAt">
              <span
                :class="
                  selected.approvalStatus === 'REJECTED'
                    ? 'text-n-ruby-11'
                    : 'text-n-teal-11'
                "
              >
                {{
                  selected.approvalStatus === 'REJECTED'
                    ? '⛔ 总经理驳回'
                    : '✅ 总经理通过（生效）'
                }}
              </span>
              · {{ selected.gmName }} · {{ fmtDateTime(selected.gmActedAt) }}
              <span v-if="selected.gmComment"> · {{ selected.gmComment }}</span>
            </div>
            <div v-else-if="selected.approvalStatus === 'MANAGER_APPROVED'">
              ⏳ 待总经理审批 · {{ selected.gmName || '未指定总经理' }}
            </div>
          </div>
        </div>

        <!-- 接单确认（P1）：当前阶段负责人 + 接单状态 + 接单/拒收。
             建单生效后归工程/PMC 接单出 BOM；SHIPPED 为终点无需接单。 -->
        <div
          v-if="
            selected.stage !== 'SHIPPED' && selected.status === 'IN_PROGRESS'
          "
          class="flex flex-col gap-2 p-3 mb-4 rounded-lg bg-n-alpha-black1 border border-n-weak"
        >
          <div class="flex flex-wrap items-center gap-1.5 text-xs">
            <span class="text-n-slate-11">本阶段负责人</span>
            <template v-if="(selected.stageOwnerNames || []).length">
              <span
                v-for="n in selected.stageOwnerNames"
                :key="n"
                class="px-1.5 py-0.5 rounded-full bg-n-iris-3 text-n-iris-12"
              >
                {{ n }}
              </span>
            </template>
            <span v-else class="text-n-amber-11">未设置负责人</span>
          </div>
          <div class="text-xs">
            <span v-if="selected.stageAckAt" class="text-n-teal-11">
              ✅ 已接单 · {{ selected.stageAckByName }}
            </span>
            <span v-else-if="selected.ackOverdue" class="text-n-ruby-11">
              🔴 超时未接单（截止 {{ fmtDateTime(selected.ackDeadline) }}）
            </span>
            <span v-else-if="selected.awaitingAck" class="text-n-amber-11">
              ⏳ 待接单 · 截止 {{ fmtDateTime(selected.ackDeadline) }}
            </span>
          </div>
          <div v-if="canHandleStage" class="flex gap-2">
            <Button
              v-if="selected.awaitingAck"
              label="接单"
              color="teal"
              size="sm"
              :is-loading="uiFlags.updatingItem"
              @click="acknowledge"
            />
            <Button
              v-if="selected.stage !== 'SALES_CONFIRMED'"
              label="拒收打回"
              variant="outline"
              color="ruby"
              size="sm"
              @click="openReject"
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
              工程/PMC BOM：{{ selected.bomNo }}
            </div>
            <!-- 两步流程指引：谁做、到哪步了，避免「业务确认后到底谁下发采购」的误解 -->
            <div
              v-if="selected.stage === 'BOM_READY'"
              class="flex flex-col gap-2 p-3 mt-2 text-xs rounded-lg bg-n-alpha-1"
            >
              <div class="flex items-start gap-2">
                <span
                  class="flex items-center justify-center w-4 h-4 text-white rounded-full shrink-0 text-[10px]"
                  :class="
                    selected.bomConfirmedAt ? 'bg-n-teal-9' : 'bg-n-amber-9'
                  "
                >
                  {{ selected.bomConfirmedAt ? '✓' : '1' }}
                </span>
                <div class="flex flex-col">
                  <span class="font-medium text-n-slate-12">
                    业务核对确认用料
                  </span>
                  <span
                    :class="
                      selected.bomConfirmedAt
                        ? 'text-n-teal-11'
                        : 'text-n-amber-11'
                    "
                  >
                    {{
                      selected.bomConfirmedAt
                        ? `已确认${
                            selected.bomConfirmedByName
                              ? `（${selected.bomConfirmedByName}）`
                              : ''
                          }`
                        : '待业务确认（点下方「业务确认BOM」）'
                    }}
                  </span>
                </div>
              </div>
              <div class="flex items-start gap-2">
                <span
                  class="flex items-center justify-center w-4 h-4 rounded-full shrink-0 text-[10px]"
                  :class="
                    selected.bomConfirmedAt
                      ? 'bg-n-iris-9 text-white'
                      : 'bg-n-slate-4 text-n-slate-10'
                  "
                >
                  2
                </span>
                <div class="flex flex-col">
                  <span
                    class="font-medium"
                    :class="
                      selected.bomConfirmedAt
                        ? 'text-n-slate-12'
                        : 'text-n-slate-10'
                    "
                  >
                    工程/PMC 下发采购
                  </span>
                  <span class="text-n-slate-10">
                    {{
                      selected.bomConfirmedAt
                        ? '业务已确认，由工程/PMC 下发采购'
                        : '待业务确认后，由工程/PMC 下发（非业务操作）'
                    }}
                  </span>
                </div>
              </div>
            </div>
            <!-- 查看工程做的用料清单（弹窗看完整明细） -->
            <Button
              v-if="
                bomDetail && bomDetail.bomItems && bomDetail.bomItems.length
              "
              :label="`查看 BOM 明细（${bomDetail.bomItems.length} 项）`"
              variant="outline"
              color="slate"
              size="sm"
              class="w-full mt-2"
              @click="openBomView"
            />
            <!-- 业务确认 BOM 按钮 -->
            <Button
              v-if="canConfirmBom"
              label="业务确认BOM"
              color="amber"
              size="sm"
              class="w-full mt-2"
              :is-loading="uiFlags.updatingItem"
              @click="confirmBom"
            />
            <!-- 下发采购：需业务确认后才可点 -->
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
              :disabled="!selected.bomConfirmedAt"
              @click="releasePurchasing"
            />
          </template>
          <!-- 工程判定：自产走挂 BOM，外购走标记外购（二选一，都在建单阶段） -->
          <div
            v-else-if="
              selected.stage === 'SALES_CONFIRMED' &&
              (mesCan('order') || mesCan('bom'))
            "
            class="flex flex-col gap-2"
          >
            <Button
              label="挂工程/PMC BOM（自产）"
              color="iris"
              size="sm"
              class="w-full"
              @click="openAttachBom"
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
            <Button
              v-if="canEditSelected"
              label="编辑订单"
              variant="ghost"
              size="xs"
              @click="openEditSpec(selected)"
            />
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
      width="2xl"
      overflow-y-auto
      confirm-button-color="iris"
      :title="editingOrderId ? '编辑生产订单' : '新建生产订单'"
      :is-loading="converting"
      :disable-confirm-button="orderInvalid"
      @confirm="submitOrder"
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
              placeholder="形式发票号，如 PI-2026-0788"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              成品名称&型号 <span class="text-n-ruby-11">*</span>
            </label>
            <Input
              v-model="orderBase.productName"
              placeholder="如：商显一体机 43寸"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              商品编码 <span class="text-n-ruby-11">*</span>
            </label>
            <ComboBox
              v-model="orderBase.crmProductId"
              :options="orderProductOptions"
              use-api-results
              :display-label="selectedOrderProductLabel"
              placeholder="选择商品编码（关联产品档案）"
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
            <Input v-model="orderBase.qty" type="number" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">单位</label>
            <Input v-model="orderBase.unit" placeholder="台 / 片 / pcs" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">期望交期</label>
            <DatePicker v-model="orderBase.deliveryDate" block />
          </div>
        </div>

        <div class="pt-2 border-t border-n-weak">
          <MesOrderSpecForm
            v-model:spec="orderSpec"
            :template="orderTemplate"
          />
        </div>
      </div>
    </Dialog>

    <!-- 转单弹窗 -->
    <Dialog
      ref="convertDialogRef"
      width="lg"
      confirm-button-color="iris"
      title="从销售订单转生产订单"
      description="选择销售订单与成品，生成生产订单；来源订单将自动进入「生产中」。"
      :is-loading="converting"
      :disable-confirm-button="convertInvalid"
      @confirm="submitConvert"
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

    <!-- 挂 BOM 弹窗 -->
    <Dialog
      ref="bomDialogRef"
      width="lg"
      confirm-button-color="iris"
      title="挂工程/PMC BOM"
      description="选择该成品的已下发 BOM，填期望交期，生产订单进入「工程/PMC BOM」阶段。"
      :is-loading="attaching"
      :disable-confirm-button="!bomForm.bomId"
      @confirm="submitAttachBom"
    >
      <div class="flex flex-col gap-4">
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">
            BOM <span class="text-n-ruby-11">*</span>
          </label>
          <SelectCard
            size="form"
            :model-value="bomForm.bomId"
            :options="bomOptions"
            @update:model-value="v => (bomForm.bomId = v)"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">期望交期</label>
          <DatePicker v-model="bomForm.deliveryDate" block />
        </div>
      </div>
    </Dialog>

    <!-- 查看 BOM 完整用料明细弹窗（业务二次确认前核对） -->
    <Dialog
      ref="bomViewDialogRef"
      width="xl"
      :title="`工程/PMC BOM 明细${bomDetail?.bomNo ? ` · ${bomDetail.bomNo}` : ''}`"
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
                <th class="px-3 py-2 font-medium">物料名称</th>
                <th class="px-3 py-2 font-medium">料号</th>
                <th class="px-3 py-2 font-medium">规格</th>
                <th class="px-3 py-2 font-medium text-right">用量</th>
                <th class="px-3 py-2 font-medium">类别</th>
                <th class="px-3 py-2 font-medium">备注</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(it, idx) in bomDetail.bomItems"
                :key="it.id"
                class="border-t border-n-weak/60 text-n-slate-12"
              >
                <td class="px-3 py-2 text-n-slate-10">{{ idx + 1 }}</td>
                <td class="px-3 py-2">{{ it.materialName }}</td>
                <td class="px-3 py-2 text-n-slate-11">
                  {{ it.materialNo || '—' }}
                </td>
                <td class="px-3 py-2 text-n-slate-11">
                  {{ it.specification || '—' }}
                </td>
                <td class="px-3 py-2 text-right whitespace-nowrap">
                  {{ it.qty }} {{ it.unit }}
                </td>
                <td class="px-3 py-2 text-n-slate-11">
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
    <Dialog
      ref="outsourceDialogRef"
      width="3xl"
      confirm-button-color="iris"
      title="标记外购成品"
      description="外购成品不走生产：选定产品与供应商后，订单直接进入采购阶段，由采购按单下采购单。跳过 BOM/领料/报工/质检。"
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

    <Dialog
      ref="rejectDialogRef"
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
        <Input
          v-model="rejectReason"
          placeholder="如：BOM 漏了主板 / 来料规格不对"
        />
      </div>
    </Dialog>

    <!-- 审批驳回：退回业务员，可改后重提 -->
    <Dialog
      ref="denyDialogRef"
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
        <Input
          v-model="denyReason"
          placeholder="如：PI 与数量不符 / 交期不可行"
        />
      </div>
    </Dialog>

    <!-- 订单明细：建单时填的规格表（只读）+ 导出 -->
    <Dialog
      ref="detailDialogRef"
      width="3xl"
      overflow-y-auto
      :show-confirm-button="false"
      cancel-button-label="关闭"
      :title="viewingOrder ? `订单明细 ${viewingOrder.orderNo}` : '订单明细'"
    >
      <div v-if="viewingOrder" class="flex flex-col gap-4 text-sm">
        <div class="flex justify-end gap-2">
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
      </div>
    </Dialog>
  </div>
</template>
