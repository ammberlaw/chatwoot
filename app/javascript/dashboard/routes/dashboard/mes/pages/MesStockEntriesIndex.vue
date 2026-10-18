<script setup>
/* global axios */
import { ref, computed, reactive, onMounted, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesStockEntriesStore } from 'dashboard/stores/mes/stockEntries';
import { fmtMoney } from 'dashboard/helper/erpMoney';
import MesStockEntryAPI from 'dashboard/api/mes/stockEntries';
import MesImageLightbox from 'dashboard/components-next/mes/MesImageLightbox.vue';
import { useMesWarehousesStore } from 'dashboard/stores/mes/warehouses';

import Button from 'dashboard/components-next/button/Button.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import MesBoardOwnerBar from 'dashboard/components-next/mes/MesBoardOwnerBar.vue';
import { useMesRole } from 'dashboard/composables/useMesRole';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import MesViewDialog from 'dashboard/components-next/mes/MesViewDialog.vue';
import MesStockEntryPrintSheet from 'dashboard/components-next/mes/MesStockEntryPrintSheet.vue';
import { useListDensity } from 'dashboard/composables/useListDensity';
import { printElement } from 'dashboard/helper/printHelper';
import MesReturnControls from 'dashboard/components-next/mes/MesReturnControls.vue';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';
import { useRouteQueryReentry } from 'dashboard/composables/useRouteQueryReentry';
import MesStatusPill from 'dashboard/components-next/mes/MesStatusPill.vue';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
import ColResizeHandle from 'dashboard/components-next/table/ColResizeHandle.vue';
import MesColumnFilter from 'dashboard/components-next/mes/MesColumnFilter.vue';
import { useOrderableColumns } from 'dashboard/composables/useOrderableColumns';
const { accountId, accountScopedRoute } = useAccount();
const route = useRoute();
const store = useMesStockEntriesStore();
const { mesCan } = useMesRole();
// 行高：宽松/紧凑一键切，记在本机（反馈：间距太长想自己拉短）
const { compact, toggleDensity } = useListDensity();

// 从生产订单「查看入库单」跳转带来的按订单筛选（只看该订单的原料入库单）。
const filterOrderId = ref(route.query.production_order_id || '');
const filterOrderNo = ref(route.query.order_no || '');
// 库存单一表多用：本板块=原料入库，只取 MATERIAL_RECEIPT（生产领料/成品入库各有独立板块）。
// 后端每页 15 条。不传 page 就永远只有最新 15 张，第 16 张往后谁都点不到
// （生产上 44 张入库单，29 张看不见）。
const ITEMS_PER_PAGE = 15;
const currentPage = ref(1);
const totalCount = computed(() => store.getMeta?.count || 0);
// 表头列筛选（对标金蝶的漏斗）。条件发后端算：列表分页，前端只过滤本页的话
// 第 2 页往后的命中全看不见。
const colFilters = reactive({
  col_no: '',
  col_po: '',
  col_supplier: '',
  col_code: '',
  col_name: '',
  col_spec: '',
  col_owner: '',
  posted: { from: '', to: '' },
});
// 列 key → 筛什么。两个视图共用这张表（同名列筛的是同一件事）。
const FILTERABLE = {
  entryNo: { type: 'text', key: 'col_no', placeholder: '入库单号' },
  poNo: { type: 'text', key: 'col_po', placeholder: '采购单号' },
  sourceNo: { type: 'text', key: 'col_po', placeholder: '采购单号' },
  supplier: { type: 'text', key: 'col_supplier', placeholder: '供应商' },
  suppliers: { type: 'text', key: 'col_supplier', placeholder: '供应商' },
  code: { type: 'text', key: 'col_code', placeholder: '物料编码' },
  name: { type: 'text', key: 'col_name', placeholder: '物料/成品名' },
  spec: { type: 'text', key: 'col_spec', placeholder: '规格型号' },
  owner: { type: 'text', key: 'col_owner', placeholder: '归属人' },
  posted: { type: 'date', key: 'posted' },
};
// 外购成品收货说明：挂在标题旁那颗 ⓘ 上（纯文本，tooltip 不吃 HTML）。
const OUTSOURCE_HINT =
  '外购成品到货也在这里收货：新建入库单 → 选对应采购单（含「成品(外购)」行）→ ' +
  '系统自动把入库仓切为成品仓 → 过账后即成成品库存，可直接销售出库，无需再开成品入库单。';

const filterOf = col => FILTERABLE[col.key];
const activeFilterCount = computed(
  () =>
    Object.entries(colFilters).filter(([k, v]) =>
      k === 'posted' ? v.from || v.to : v
    ).length
);
// 一个框搜多处：入库单号 / 采购单号 / 对内备注 / 供应商 / 物料编码 / 品名 / 归属人。
// 走后端（见 StockEntriesController::SEARCH_SQL）——列表每页 15 条，前端过滤只筛得到本页。
const search = ref('');
const activeColFilterParams = () => ({
  q: search.value.trim() || undefined,
  col_no: colFilters.col_no || undefined,
  col_po: colFilters.col_po || undefined,
  col_supplier: colFilters.col_supplier || undefined,
  col_code: colFilters.col_code || undefined,
  col_name: colFilters.col_name || undefined,
  col_spec: colFilters.col_spec || undefined,
  col_owner: colFilters.col_owner || undefined,
  posted_from: colFilters.posted.from || undefined,
  posted_to: colFilters.posted.to || undefined,
});

const fetchList = () =>
  store.get({
    purpose: 'MATERIAL_RECEIPT',
    page: currentPage.value,
    ...(filterOrderId.value
      ? { production_order_id: filterOrderId.value }
      : {}),
    ...activeColFilterParams(),
  });
watch(currentPage, fetchList);
// 换筛选要回第 1 页：在第 3 页筛一个只有 2 条结果的条件会看到空列表。
const resetToFirstPage = () => {
  if (currentPage.value === 1) fetchList();
  else currentPage.value = 1;
};
// 300ms 防抖：边打字边请求会把后端打满，也会让结果跳来跳去。
let searchTimer = null;
watch(search, () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(resetToFirstPage, 300);
});

const clearOrderFilter = () => {
  filterOrderId.value = '';
  filterOrderNo.value = '';
  resetToFirstPage();
};
const warehousesStore = useMesWarehousesStore();

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const saving = computed(() => store.getUIFlags.creatingItem);
const posting = computed(() => store.getUIFlags.updatingItem);

const day = d => (d ? new Date(d).toLocaleDateString() : '—');
// 单价/金额是微元；没有值（无权或对不上采购行）留「—」，不要写成 0。
const money = micros => (micros ? fmtMoney(micros) : '—');

// S3 主用原料入库；其余 purpose 留给后续切片。
const PURPOSE_LABELS = {
  MATERIAL_RECEIPT: '原料入库',
  MATERIAL_ISSUE: '生产领料',
  MATERIAL_RETURN: '退料',
  MANUFACTURE: '成品入库',
  SCRAP: '清尾报废',
};
const IN_PURPOSES = ['MATERIAL_RECEIPT', 'MATERIAL_RETURN', 'MANUFACTURE'];
const purposeLabel = p => PURPOSE_LABELS[p] || p;
const STATUS_LABELS = { DRAFT: '草稿', POSTED: '已过账', CANCELLED: '已取消' };
// 财务审核：审核通过才能过账（过账要刷库存、起应付，闸设在过账前）。
const APPROVAL_LABELS = {
  PENDING: '待审核',
  APPROVED: '已通过',
  REJECTED: '已驳回',
};
// 审核人自己配（同采购审批人那套，存 Mes::BoardOwner）。不配就回落到财务/管理员。
const APPROVER_BOARD = [
  {
    key: 'mes_stock_approver',
    label: '入库审核人',
    single: true,
    hint: '原料入库单由他审核，审核通过才能过账。不设则由财务和管理员审核。',
  },
];

// 只读查看
const whName = id =>
  (warehousesStore.getRecords || []).find(w => w.id === id)?.name || '—';

// 列表两种看法：「按单」一行一张入库单，「按明细」一行一条料（对标金蝶采购入库单列表）。
// 反馈原话：「原料入库界面需要看到供应商和物料编码、明细、规格型号、单价、金额」——
// 这些都是行上的东西，单据级那一行摆不下。
const viewMode = ref('order'); // order | item
const VIEW_MODES = [
  { key: 'order', label: '按单' },
  { key: 'item', label: '按明细' },
];

const onColFilterChange = () => resetToFirstPage();
const clearColFilters = () => {
  Object.keys(colFilters).forEach(k => {
    colFilters[k] = k === 'posted' ? { from: '', to: '' } : '';
  });
  onColFilterChange();
};

// 按单视图的列（可拖序、可收起、可拉宽，按人记在本机）。操作列固定在最后，不参与。
const ORDER_COLUMN_DEFS = [
  {
    key: 'entryNo',
    label: '单号',
    tdClass: 'px-3 py-3 font-medium text-n-slate-12',
  },
  { key: 'purpose', label: '类型', tdClass: 'px-3 py-3 text-n-slate-11' },
  { key: 'poNo', label: '采购单', tdClass: 'px-3 py-3 text-n-slate-11' },
  // 供应商挂在来源采购单的行上，一张单可能好几家，全列出来。
  { key: 'suppliers', label: '供应商', tdClass: 'px-3 py-3 text-n-slate-11' },
  { key: 'qty', label: '入库量', tdClass: 'px-3 py-3 text-n-slate-11' },
  { key: 'owner', label: '归属人', tdClass: 'px-3 py-3 text-n-slate-11' },
  { key: 'checked', label: '核对', tdClass: 'px-3 py-3 text-n-slate-11' },
  { key: 'approval', label: '审核', tdClass: 'px-3 py-3 text-n-slate-11' },
  { key: 'status', label: '状态', tdClass: 'px-3 py-3' },
  // 列名用仓管的说法：过账＝库存真正变动的那一刻，就是货入库的时间。
  // 叫「过账时间」是财务口径，采购在列表里找「入库时间」找不到（问题点 A1：
  // 「这里要加一个入库时间，因为审核和入库不一定是同一天」——其实就是这一列）。
  { key: 'posted', label: '入库时间', tdClass: 'px-3 py-3 text-n-slate-11' },
  {
    key: 'internalRemark',
    label: '对内备注',
    tdClass: 'px-3 py-3 text-n-slate-11 max-w-[16rem] truncate',
  },
];
const {
  orderedColumns: orderCols,
  visibleColumns: visibleOrderCols,
  hiddenKeys: hiddenOrderColKeys,
  isHidden: isOrderColHidden,
  toggleColumn: toggleOrderCol,
  showAllColumns: showAllOrderCols,
  isDragging: isOrderColDragging,
  onColDragStart: onOrderColDragStart,
  onColDrop: onOrderColDrop,
  resetOrder: resetOrderCols,
  colStyle: orderColStyle,
  isResizing: isOrderColResizing,
  startResize: startOrderColResize,
  autoFitColumn: autoFitOrderCol,
} = useOrderableColumns(ORDER_COLUMN_DEFS, 'mes.seListCols.v1');

// 明细视图的列。两套各记各的（本机键不同），互不干扰。
const ITEM_COLUMN_DEFS = [
  {
    key: 'entryNo',
    label: '入库单号',
    tdClass: 'px-3 py-2 font-medium text-n-slate-12',
  },
  // 源单单号＝这家供应商那张子单（PU-…-01），仓库核对认的就是它。
  { key: 'sourceNo', label: '源单单号', tdClass: 'px-3 py-2 text-n-slate-11' },
  { key: 'supplier', label: '供应商', tdClass: 'px-3 py-2 text-n-slate-11' },
  { key: 'code', label: '物料编码', tdClass: 'px-3 py-2 text-n-slate-11' },
  { key: 'name', label: '物料名称', tdClass: 'px-3 py-2 text-n-slate-12' },
  {
    key: 'spec',
    label: '规格型号',
    tdClass: 'px-3 py-2 text-n-slate-11 max-w-[18rem] truncate',
  },
  { key: 'warehouse', label: '收料仓库', tdClass: 'px-3 py-2 text-n-slate-11' },
  { key: 'unit', label: '单位', tdClass: 'px-3 py-2 text-n-slate-11' },
  {
    key: 'qty',
    label: '应收',
    thClass: 'text-right',
    tdClass: 'px-3 py-2 text-right tabular-nums text-n-slate-11',
  },
  {
    key: 'receivedQty',
    label: '实收',
    thClass: 'text-right',
    tdClass: 'px-3 py-2 text-right tabular-nums text-n-slate-12',
  },
  {
    key: 'unitPrice',
    label: '单价',
    thClass: 'text-right',
    tdClass: 'px-3 py-2 text-right tabular-nums text-n-slate-11',
  },
  {
    key: 'amount',
    label: '金额',
    thClass: 'text-right',
    tdClass: 'px-3 py-2 text-right tabular-nums text-n-slate-12',
  },
  { key: 'status', label: '状态', tdClass: 'px-3 py-2' },
  {
    key: 'remark',
    label: '备注',
    tdClass: 'px-3 py-2 text-n-slate-11 max-w-[16rem] truncate',
  },
];
const {
  orderedColumns: itemCols,
  visibleColumns: visibleItemCols,
  hiddenKeys: hiddenItemColKeys,
  isHidden: isItemColHidden,
  toggleColumn: toggleItemCol,
  showAllColumns: showAllItemCols,
  isDragging: isItemColDragging,
  onColDragStart: onItemColDragStart,
  onColDrop: onItemColDrop,
  resetOrder: resetItemCols,
  colStyle: itemColStyle,
  isResizing: isItemColResizing,
  startResize: startItemColResize,
  autoFitColumn: autoFitItemCol,
} = useOrderableColumns(ITEM_COLUMN_DEFS, 'mes.seItemCols.v1');

// 把当页入库单摊平成「一行一条料」。只摊当页、不额外请求——列表本来就带明细。
const itemRows = computed(() =>
  records.value.flatMap(e =>
    (e.stockEntryItems || []).map(it => ({
      key: `${e.id}-${it.id}`,
      entry: e,
      entryNo: e.entryNo,
      sourceNo: it.sourcePoNo || e.purchaseOrderNo || '—',
      supplier: it.supplierName || '—',
      code: it.materialNo || '—',
      name: it.materialName || it.productName || '—',
      spec: it.specification || '—',
      warehouse: whName(it.warehouseId || e.toWarehouseId),
      unit: it.unit || '—',
      qty: it.qty,
      receivedQty: it.receivedQty ?? it.qty,
      unitPrice: money(it.unitPriceMicros),
      amount: money(it.amountMicros),
      status: e.status,
      remark: it.remark || '—',
    }))
  )
);

// 「列」面板与「恢复默认列序」必须跟着当前视图走：两套列完全不同，
// 恒指向按单那套的话，切到明细后勾的是看不见的那张表的列（点了没反应）。
const showColumnPanel = ref(false);
const isItemView = computed(() => viewMode.value === 'item');
const activeCols = computed(() =>
  isItemView.value ? itemCols.value : orderCols.value
);
const activeIsHidden = key =>
  isItemView.value ? isItemColHidden(key) : isOrderColHidden(key);
const activeToggleCol = key =>
  isItemView.value ? toggleItemCol(key) : toggleOrderCol(key);
const activeShowAllCols = () =>
  isItemView.value ? showAllItemCols() : showAllOrderCols();
const activeResetCols = () =>
  isItemView.value ? resetItemCols() : resetOrderCols();
const hiddenCols = computed(
  () =>
    (isItemView.value ? hiddenItemColKeys.value : hiddenOrderColKeys.value)
      .length
);
const viewDialogRef = ref(null);
const viewing = ref(null);
const openView = e => {
  viewing.value = e;
  viewDialogRef.value?.open();
};
// 「这张工单到货明细」：一张工单的料摊成十几张入库单，光看单张看不出整单齐不齐，
// 跳到销售订单详情里那块全量明细去（用户 10.16 反馈的查找麻烦，根子在这）。
const router = useRouter();
const goOrderArrivals = () => {
  const no = viewing.value?.productionOrderNo;
  if (!no) return;
  router.push(accountScopedRoute('mes_production_orders_index', {}, { q: no }));
};

const viewFields = computed(() => {
  const e = viewing.value || {};
  return [
    { label: '单号', value: e.entryNo },
    { label: '类型', value: purposeLabel(e.purpose) },
    { label: '采购单', value: e.purchaseOrderNo },
    // 供应商与对内备注原本只在采购单上，核料时要另开一张单比着看（反馈点名要补）。
    { label: '供应商', value: (e.supplierNames || []).join('、') },
    { label: '销售订单', value: e.productionOrderNo },
    { label: '归属人', value: e.productionOrderOwnerName },
    { label: '入库仓', value: whName(e.toWarehouseId) },
    { label: '状态', value: STATUS_LABELS[e.status] || e.status },
    { label: '入库时间', value: day(e.postedAt) },
    {
      label: '审核',
      value: e.needsApproval
        ? `${APPROVAL_LABELS[e.approvalStatus] || e.approvalStatus}${
            e.approvedByName ? ` · ${e.approvedByName}` : ''
          }${e.rejectReason ? `（${e.rejectReason}）` : ''}`
        : '无需审核',
    },
    {
      label: '核对',
      value: e.isChecked ? `已核对 · ${e.checkedByName || ''}` : '未核对',
    },
    { label: '收货人', value: e.receivedByName },
    { label: '制单人', value: e.ownerName },
    { label: '备注', value: e.remark },
    { label: '对内备注', value: e.internalRemark },
  ];
});
// 单价/金额只给看得见成本的岗位（采购/财务/管理员/采购审批人）——
// 入库单仓管看得最多，不能顺手把成本漏出去。后端不下发时这两列直接不出。
// 打印用的票面数据（1:1 对标旧系统那张采购入库单）。
// 源单单号＝来源采购单号；仓库按行的入库仓，没有就落到单据的入库仓。
const printSheetRef = ref(null);
const printRows = computed(() =>
  (viewing.value?.stockEntryItems || []).map(it => ({
    sourceNo: it.sourcePoNo || viewing.value?.purchaseOrderNo,
    materialNo: it.materialNo,
    name: it.materialName || it.productName,
    spec: it.specification,
    warehouse: whName(it.warehouseId || viewing.value?.toWarehouseId),
    unit: it.unit,
    qty: it.qty,
    receivedQty: it.receivedQty ?? it.qty,
    remark: it.remark,
  }))
);
const printSupplier = computed(() =>
  (viewing.value?.supplierNames || []).join('、')
);
// 套打在 9.5×5.5 英寸三联复写纸上（针式打印机），所以纸张写死、也不加 Wintouch 字标——
// 加了会把版心顶下去，套打直接压到预印格线上。
// 纸张只给尺寸、不写方向：横/纵由打印对话框里自己选（她那边每次打印手动选）。
// 另外 `size: 9.5in 5.5in landscape` 本来就不是合法写法——CSS 要么给两个长度、
// 要么给纸名+方向关键字，混着写浏览器会忽略方向，对话框里照样显示「纵向」。
const TRIPLICATE_PAGE = '@page{size:9.5in 5.5in;margin:8mm}';
const printEntry = () =>
  printElement(
    printSheetRef.value?.$el || printSheetRef.value,
    `采购入库单 ${viewing.value?.entryNo || ''}`,
    { page: TRIPLICATE_PAGE, brandHeader: false }
  );

const VIEW_ITEM_COLS = computed(() => [
  { label: '物料/产品', key: 'name' },
  { label: '编码', key: 'materialNo' },
  { label: '规格型号', key: 'specification', wrap: true },
  { label: '供应商', key: 'supplierName', wrap: true },
  { label: '应收', key: 'qty', align: 'right' },
  { label: '实收', key: 'receivedQty', align: 'right' },
  { label: '单位', key: 'unit' },
  ...(viewing.value?.canViewAmount
    ? [
        { label: '单价', key: 'unitPrice', align: 'right' },
        { label: '金额', key: 'amount', align: 'right' },
      ]
    : []),
  { label: '备注', key: 'remark', wrap: true },
  // 附图跟着自己那一行走（同采购单），点开在页内放大；不进 Excel 导出。
  { label: '附图（仅内部）', key: 'images', type: 'images' },
]);
const viewItems = computed(() =>
  (viewing.value?.stockEntryItems || []).map(it => ({
    name: it.materialName || it.productName,
    materialNo: it.materialNo,
    specification: it.specification,
    supplierName: it.supplierName,
    qty: it.qty,
    receivedQty: it.receivedQty ?? it.qty,
    unit: it.unit,
    unitPrice: money(it.unitPriceMicros),
    amount: money(it.amountMicros),
    remark: it.remark,
    images: it.images || [],
  }))
);

// 列表「入库量」摘要：项数 · 实收合计（一单多料时汇总）。
const entryQtySummary = e => {
  const items = e.stockEntryItems || [];
  if (!items.length) return '—';
  const total = items.reduce(
    (s, it) => s + Number(it.receivedQty ?? it.qty ?? 0),
    0
  );
  return `${items.length}项·${total}`;
};

const warehouseOptions = computed(() =>
  (warehousesStore.getRecords || []).map(w => ({
    value: String(w.id),
    label: w.name,
  }))
);
// 收货行类型：物料（生产用料）/ 成品（外购贸易品到货，入成品库）。
const ITEM_TYPE_OPTIONS = [
  { value: 'MATERIAL', label: '物料' },
  { value: 'PRODUCT', label: '成品(外购)' },
];
const productOptions = ref([]);
const mergeProductOptions = list => {
  const seen = new Set(productOptions.value.map(o => o.value));
  list.forEach(o => {
    if (!seen.has(o.value)) {
      productOptions.value.push(o);
      seen.add(o.value);
    }
  });
};
const loadProducts = async (q = '') => {
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/products`,
      // 产品档案近 5000 条,靠 q 搜索收窄;per_page 取后端上限 100,
      // 否则命中多于 15 条时后面的直接看不到。
      { params: { filter: 'active', q, per_page: 100 } }
    );
    mergeProductOptions(
      (data?.payload || []).map(p => ({
        value: String(p.id),
        label: `${p.name}${p.sku ? `（${p.sku}）` : ''}`,
        unit: p.unit || '',
      }))
    );
  } catch {
    // 忽略：搜索失败保留现有选项
  }
};
const productUnit = id =>
  productOptions.value.find(o => o.value === String(id))?.unit || '';
const finishedWarehouseId = () =>
  (warehousesStore.getRecords || []).find(w => w.kind === 'FINISHED')?.id;

const purchaseOrders = ref([]);
// 供应商名：后端给的是 supplier_names（**数组**，一张采购单常含好几家供应商）。
// 原来这里读的是单数 supplier_name，永远 undefined——于是下拉里既不显示供应商，
// 搜供应商名也永远「没有匹配的采购单」（10.17 反馈 A2，仓管按供应商找单）。
const supplierLabel = po => {
  const names = po.supplier_names || [];
  if (!names.length) return '';

  return names.length > 1 ? `${names[0]} 等 ${names.length} 家` : names[0];
};

const purchaseOrderOptions = computed(() => [
  { value: '', label: '不关联采购单' },
  ...purchaseOrders.value.map(p => ({
    value: String(p.id),
    label: `${p.po_no}${supplierLabel(p) ? ` · ${supplierLabel(p)}` : ''}`,
    // 搜索要能命中**每一家**供应商，不只是标签上显示的那家
    searchText: [...(p.supplier_names || []), p.production_order_no]
      .filter(Boolean)
      .join(' '),
  })),
]);

const dialogRef = ref(null);
const form = reactive({
  purpose: 'MATERIAL_RECEIPT',
  warehouseId: '',
  purchaseOrderId: '',
  // 追加的采购单：同一家供应商同一天送来好几张单的料，一张入库单一次收完
  // （10.17 反馈 A2「有一张单多个采购单的要一起入」）
  extraPurchaseOrderIds: [],
  productionOrderId: '',
  isChecked: false,
  rows: [], // { itemType, mesMaterialId, qty, receivedQty }
});
const { isDirty, markPristine } = useDirtyGuard(() => form);
// 物料/成品统一从产品档案(crm_products)选（mes_materials 已弃用），故都校验 crmProductId。
const rowIncomplete = r => !Number(r.qty) || !r.crmProductId;

const invalid = computed(
  () => !form.warehouseId || !form.rows.length || form.rows.some(rowIncomplete)
);

const addRow = () =>
  form.rows.push({
    itemType: 'MATERIAL',
    crmProductId: '',
    qty: '1',
    receivedQty: '',
    remark: '',
  });
const removeRow = i => form.rows.splice(i, 1);

// 选中的那张采购单：对内备注和供应商都从它身上取，核料时不用另开一张单比着看。
const selectedPO = computed(() =>
  purchaseOrders.value.find(p => String(p.id) === String(form.purchaseOrderId))
);

// 这张采购单上还没收完的行。已经入库完的不该再跳出来——
// 分批到货时一点预填就把收过的料又铺一遍，仓管得自己一行行删（用户点名）。
const outstandingItems = po =>
  (po?.purchase_items || []).filter(
    it => Number(it.qty || 0) - Number(it.received_qty || 0) > 0
  );

// 一张采购单常含好几家供应商，货是一家一家送到的。按供应商分别预填＝一家一张入库单，
// 入库单的收货明细和供应商才对得上，财务才能对账（用户点名）。
const prefillSupplierId = ref('');
const prefillSupplierOptions = computed(() => {
  const groups = new Map();
  outstandingItems(selectedPO.value).forEach(it => {
    const key = it.mes_supplier_id ? String(it.mes_supplier_id) : '';
    if (!groups.has(key)) {
      groups.set(key, { name: it.supplier_name || '未指定供应商', n: 0 });
    }
    groups.get(key).n += 1;
  });
  const rows = [...groups.entries()].map(([value, g]) => ({
    value,
    label: `${g.name}（${g.n} 行待收）`,
  }));
  // 只有一家就不用再选；多家时默认不选，逼着先挑一家，免得又铺成一张大杂烩单。
  return rows.length > 1
    ? [
        { value: '', label: '全部供应商（不建议，一张单混多家没法对账）' },
        ...rows,
      ]
    : rows;
});

// 追加采购单的候选：排掉主单和已追加的
const extraPOOptions = computed(() => [
  { value: '', label: '选一张追加…' },
  ...purchaseOrders.value
    .filter(
      p =>
        String(p.id) !== String(form.purchaseOrderId) &&
        !form.extraPurchaseOrderIds.includes(String(p.id))
    )
    .map(p => ({
      value: String(p.id),
      label: `${p.po_no}${supplierLabel(p) ? ` · ${supplierLabel(p)}` : ''}`,
      searchText: [...(p.supplier_names || []), p.production_order_no]
        .filter(Boolean)
        .join(' '),
    })),
]);
const addExtraPO = v => {
  if (v) form.extraPurchaseOrderIds.push(String(v));
};
const removeExtraPO = id => {
  form.extraPurchaseOrderIds = form.extraPurchaseOrderIds.filter(
    x => String(x) !== String(id)
  );
};
const poNoOf = id =>
  purchaseOrders.value.find(p => String(p.id) === String(id))?.po_no || id;

// 本单关联的全部采购单（主单 + 追加的）
const linkedPOs = computed(() =>
  [form.purchaseOrderId, ...form.extraPurchaseOrderIds]
    .filter(Boolean)
    .map(id => purchaseOrders.value.find(p => String(p.id) === String(id)))
    .filter(Boolean)
);

// 选采购单 → 按其明细预填收货行，实收默认等于未收数量。
// 挂了几张单就把几张的未收行一起铺出来——同一家供应商同一天送几张单的料，
// 仓管一次收完，不用开三张入库单（10.17 反馈 A2）。
const prefillFromPO = async () => {
  if (!form.purchaseOrderId) return;
  const pos = linkedPOs.value;
  const po = pos[0];
  let items = pos.flatMap(outstandingItems);
  if (prefillSupplierId.value) {
    items = items.filter(
      it => String(it.mes_supplier_id || '') === prefillSupplierId.value
    );
  }
  if (!items.length) {
    useAlert('这张采购单上没有还没收完的料了');
    return;
  }
  if (items.length) {
    form.productionOrderId = po.production_order_id
      ? String(po.production_order_id)
      : '';
    form.rows = items.map(it => ({
      itemType: it.item_type || 'MATERIAL',
      crmProductId: it.crm_product_id ? String(it.crm_product_id) : '',
      qty: String(it.qty),
      // 实收默认＝还没收的那部分（分批到货时不会把收过的再算一遍）。
      receivedQty: String(Number(it.qty || 0) - Number(it.received_qty || 0)),
      remark: '',
      // 只读，不提交：一张采购单可能好几家供应商，收货时得知道这一行的货是谁送来的
      // （反馈原话：「这里入库需要看到供应商名称」）。
      supplierName: it.supplier_name || '',
    }));
    // 物料/成品都从产品档案选，把所有行的产品并入下拉，保证行内直接显示、可改。
    mergeProductOptions(
      items
        .filter(it => it.crm_product_id)
        .map(it => ({
          value: String(it.crm_product_id),
          label: `${it.product_name || ''}${it.product_sku ? `（${it.product_sku}）` : ''}`,
          unit: it.unit || '',
        }))
    );
    // 有外购成品则默认入成品库。
    if (items.some(it => it.item_type === 'PRODUCT')) {
      const fin = finishedWarehouseId();
      if (fin) form.warehouseId = String(fin);
    }
  }
};

const openCreate = () => {
  const raw = (warehousesStore.getRecords || []).find(w => w.kind === 'RAW');
  Object.assign(form, {
    purpose: 'MATERIAL_RECEIPT',
    warehouseId: raw ? String(raw.id) : '',
    purchaseOrderId: '',
    extraPurchaseOrderIds: [],
    productionOrderId: '',
    isChecked: false,
    rows: [
      {
        itemType: 'MATERIAL',
        crmProductId: '',
        qty: '1',
        receivedQty: '',
        remark: '',
        images: [], // 行内附图（只对内）：收货时拍的实物照/破损照
      },
    ],
  });
  markPristine();
  dialogRef.value?.open();
};

// —— 明细行内部附图 ——
// 收货时对着这颗料拍的实物照/破损照，只给公司内部看。选了就先上传拿 signed_id，
// 随明细一起提交（后端 images= 整组替换）。
const stagingRow = ref(null);
// 点缩略图在页内放大，不另开浏览器标签页
const lightboxRef = ref(null);
const pickRowImages = async (event, row, index) => {
  const list = Array.from(event.target.files || []);
  event.target.value = '';
  if (!list.length) return;

  stagingRow.value = index;
  try {
    const staged = await Promise.all(
      list.map(file => {
        const fd = new FormData();
        fd.append('file', file);
        return MesStockEntryAPI.stageBlob(fd).then(({ data }) => ({
          name: data.filename,
          signedId: data.signed_id,
          url: URL.createObjectURL(file),
        }));
      })
    );
    row.images = [...(row.images || []), ...staged];
  } catch (e) {
    useAlert(
      `上传失败：${e?.response?.data?.error || e?.message || '未知错误'}`
    );
  } finally {
    stagingRow.value = null;
  }
};
const removeRowImage = (row, i) => row.images.splice(i, 1);

const submit = async () => {
  if (invalid.value) return;
  const inbound = IN_PURPOSES.includes(form.purpose);
  const payload = {
    purpose: form.purpose,
    purchaseOrderId: form.purchaseOrderId || null,
    extraPurchaseOrderIds: form.extraPurchaseOrderIds.map(Number),
    productionOrderId: form.productionOrderId || null,
    toWarehouseId: inbound ? Number(form.warehouseId) : null,
    fromWarehouseId: inbound ? null : Number(form.warehouseId),
    isChecked: form.isChecked,
    stockEntryItemsAttributes: form.rows.map(r => ({
      itemType: r.itemType,
      mesMaterialId: null,
      crmProductId: Number(r.crmProductId),
      unit: productUnit(r.crmProductId) || undefined,
      qty: Number(r.qty),
      receivedQty: Number(r.receivedQty) || Number(r.qty),
      warehouseId: Number(form.warehouseId),
      remark: r.remark || '',
      // 整组替换：给这一行当前应有的完整列表（同采购明细）
      images: (r.images || []).map(img => img.signedId),
    })),
  };
  const ok = await store.create(payload);
  if (ok) {
    useAlert(`已建 ${ok.entryNo}，待过账`);
    dialogRef.value?.close();
  }
};

// 财务审核。通过即可过账；驳回必须写原因——仓管要照着原因改单。
const approveEntry = async entry => {
  const ok = await store.approve(entry.id);
  if (ok) useAlert(`${entry.entryNo} 已审核通过，可以过账了`);
};
// 驳回走正经弹窗（同退回上一环节那套），不用浏览器原生 prompt。
const rejectDialogRef = ref(null);
const rejecting = ref(null);
const rejectReason = ref('');
const openReject = entry => {
  rejecting.value = entry;
  rejectReason.value = '';
  rejectDialogRef.value?.open();
};
const submitReject = async () => {
  if (!rejecting.value || !rejectReason.value.trim()) return;
  const ok = await store.reject(rejecting.value.id, rejectReason.value.trim());
  if (ok) {
    useAlert(`${rejecting.value.entryNo} 已驳回`);
    rejectDialogRef.value?.close();
  }
};

const postEntry = async entry => {
  const ok = await store.post(entry.id);
  if (!ok) return;
  useAlert(`${ok.entryNo} 已过账，库存已更新`);
  // 应付没同步要单独说——只看到「已过账」，财务那边却少一笔欠款。
  if (ok.erpPayableWarning) useAlert(ok.erpPayableWarning);
};

// 删单：草稿直接删；已过账走「作废」冲销（退回库存，保留单据可追溯）。
// 仓管可删别人建的草稿——重复单往往是仓管清点时才发现的，只许制单人删就成了死锁。
const removeEntry = async e => {
  const posted = e.status === 'POSTED';
  const text = posted
    ? `确定作废入库单 ${e.entryNo}？已入库的数量会从结存冲回。`
    : `确定删除入库单 ${e.entryNo}？删除后不可恢复。`;
  // eslint-disable-next-line no-alert
  if (!window.confirm(text)) return;
  try {
    const ok = posted ? await store.cancel(e.id) : await store.delete(e.id);
    if (ok) useAlert(posted ? '已作废' : '已删除');
  } catch (error) {
    useAlert(error.message || (posted ? '作废失败' : '删除失败'));
  }
};

onMounted(async () => {
  fetchList();
  warehousesStore.get();
  loadProducts('');
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/purchase_orders`,
      // 同上:采购单下拉要能选到全部,不能只给最新 15 张。
      { params: { per_page: 500 } }
    );
    purchaseOrders.value = data?.payload || [];
  } catch {
    purchaseOrders.value = [];
  }
});

// 从生产订单详情「查看入库单」再次进来：本页在 keep-alive 里缓存着，
// onMounted 不会再跑，不补这一道筛选条件就还是上一张订单的。
useRouteQueryReentry(query => {
  filterOrderId.value = query.production_order_id || '';
  filterOrderNo.value = query.order_no || '';
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div
      class="flex items-center justify-between px-4 py-3 sm:px-6 sm:py-4 [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:sm:!px-8"
    >
      <div class="flex items-center gap-1.5">
        <h1
          class="text-xl font-semibold text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8"
        >
          原料入库
        </h1>
        <!-- 外购成品收货说明原来是页头下一整条横幅，占掉一行、天天看见但只在第一次有用，
             收进标题旁这颗 ⓘ 里（用户原话「这个感叹号可以放在原料入库四个字鼠标悬停跳出」）。 -->
        <span
          v-tooltip="OUTSOURCE_HINT"
          class="shrink-0 cursor-help i-lucide-info size-4 text-n-slate-10 hover:text-n-slate-11"
        />
      </div>
      <div class="flex items-center gap-2">
        <button
          v-if="activeFilterCount"
          type="button"
          class="inline-flex items-center h-8 px-1 text-xs text-n-slate-11 hover:text-n-slate-12"
          @click="clearColFilters"
        >
          清空筛选（{{ activeFilterCount }}）
        </button>
        <button
          type="button"
          class="inline-flex items-center h-8 px-1 text-xs text-n-slate-11 hover:text-n-slate-12"
          @click="activeResetCols"
        >
          恢复默认列序
        </button>
        <!-- 按单 / 按明细：核对物料时要的是明细那一屏（对标金蝶）。
             走全站页面级 Tab 的统一标记；并排在工具栏里得压到同样 32px 高，
             全局 [data-tabbar] 规则特指度比 my-0 高，所以要带 !。 -->
        <div data-tabbar="page" class="!my-0 [&>button]:!h-[26px]">
          <button
            v-for="m in VIEW_MODES"
            :key="m.key"
            :aria-selected="viewMode === m.key"
            @click="viewMode = m.key"
          >
            {{ m.label }}
          </button>
        </div>
        <!-- 收起用不到的列：列少了就不用横着拖滚动条（同采购单） -->
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
              v-for="col in activeCols"
              :key="`vis-${col.key}`"
              class="flex items-center gap-2 px-2 py-1 rounded cursor-pointer text-label-small hover:bg-n-alpha-1"
            >
              <input
                type="checkbox"
                :checked="!activeIsHidden(col.key)"
                @change="activeToggleCol(col.key)"
              />
              {{ col.label }}
            </label>
            <button
              class="px-2 py-1 mt-1 text-left border-t text-label-small text-n-slate-11 border-n-weak hover:text-n-slate-12"
              @click="activeShowAllCols"
            >
              全部显示
            </button>
          </div>
        </div>
        <Button
          :label="compact ? '宽松行高' : '紧凑行高'"
          variant="ghost"
          color="slate"
          size="sm"
          @click="toggleDensity"
        />
        <Button
          v-if="mesCan('stock')"
          label="新建入库单"
          color="iris"
          size="sm"
          @click="openCreate"
        />
      </div>
    </div>

    <MesBoardOwnerBar
      board-key="mes_stock_entries_index"
      :extra-boards="APPROVER_BOARD"
    />

    <!-- 搜索：单号 / 采购单 / 对内备注 / 供应商 / 物料编码 / 品名 / 归属人（走后端，不只筛本页）。
         原生 input 要带 reset-base 和显式 h-9，否则被全局 SCSS 强制成 field-base h-10、比旁边控件高一截。 -->
    <div
      class="flex items-center gap-2 px-4 pt-1 pb-2 sm:px-6 [.theme-classic_&]:sm:!px-8"
    >
      <input
        v-model="search"
        type="text"
        placeholder="搜索单号 / 采购单 / 对内备注 / 供应商 / 物料编码"
        class="w-96 h-9 px-3 mb-0 text-sm rounded-lg reset-base outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-9 hover:outline-n-brand focus:outline-n-brand"
      />
      <button
        v-if="search"
        type="button"
        class="inline-flex items-center h-9 px-2 text-xs shrink-0 text-n-slate-11 hover:text-n-slate-12"
        @click="search = ''"
      >
        清空
      </button>
      <span v-if="search" class="text-xs text-n-slate-11">
        命中 {{ totalCount }} 张
      </span>
    </div>

    <!-- 从生产订单跳来的按订单筛选提示 -->
    <div
      v-if="filterOrderId"
      class="flex items-center gap-2 px-4 mb-1 sm:px-6 [.theme-classic_&]:sm:!px-8"
    >
      <span
        class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-full bg-n-iris-3 text-n-iris-11"
      >
        仅显示生产订单 {{ filterOrderNo || filterOrderId }} 的入库单
        <button
          type="button"
          class="i-lucide-x size-3.5 hover:text-n-iris-12"
          @click="clearOrderFilter"
        />
      </span>
    </div>

    <HScrollButtons />
    <div
      class="flex-1 min-h-0 px-4 pb-4 overflow-auto sm:px-6 sm:pb-6 [.theme-classic_&]:sm:!px-8"
    >
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <template v-else>
        <div class="flex flex-col gap-2 md:hidden">
          <div
            v-for="e in records"
            :key="e.id"
            class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl active:bg-n-alpha-1"
            @click="openView(e)"
          >
            <div class="flex items-center gap-2">
              <span class="font-medium truncate text-n-slate-12">
                {{ e.entryNo }}
              </span>
              <MesStatusPill
                class="shrink-0"
                :label="STATUS_LABELS[e.status]"
              />
              <span class="flex-1" />
              <Button
                v-if="e.status === 'DRAFT' && mesCan('stock')"
                label="过账"
                color="iris"
                size="sm"
                :is-loading="posting"
                @click.stop="postEntry(e)"
              />
            </div>
            <div class="flex flex-wrap gap-3 mt-2 text-xs text-n-slate-11">
              <span>类型：{{ purposeLabel(e.purpose) }}</span>
              <span>采购单：{{ e.purchaseOrderNo || '—' }}</span>
              <span>入库量：{{ entryQtySummary(e) }}</span>
            </div>
            <div class="flex flex-wrap gap-3 mt-1 text-xs text-n-slate-11">
              <span>归属人：{{ e.productionOrderOwnerName || '—' }}</span>
              <span>核对：{{ e.isChecked ? '已核对' : '—' }}</span>
            </div>
            <div class="flex flex-wrap gap-3 mt-1 text-xs text-n-slate-11">
              <span>入库时间：{{ day(e.postedAt) }}</span>
            </div>
            <div class="mt-2" @click.stop>
              <MesReturnControls
                :record="e"
                :store="store"
                :can-manage="mesCan('stock')"
              />
            </div>
          </div>
          <div v-if="!records.length" class="py-10 text-center text-n-slate-11">
            还没有入库单。
          </div>
        </div>
        <!-- 按单：一行一张入库单。列可拖序、可收起、可拉宽，表头带列筛选。 -->
        <table
          v-if="!isItemView"
          class="hidden w-full text-sm whitespace-nowrap md:table"
        >
          <thead>
            <tr
              class="text-left text-n-slate-11 [&>th]:sticky [&>th]:top-0 [&>th]:z-10 [&>th]:bg-n-solid-1 [&>th]:border-b [&>th]:border-n-weak"
            >
              <th
                v-for="col in visibleOrderCols"
                :key="col.key"
                draggable="true"
                class="relative px-3 py-3 font-medium transition-colors cursor-move select-none whitespace-nowrap"
                :class="[
                  col.thClass,
                  isOrderColDragging(col.key) ? 'opacity-40' : '',
                ]"
                :style="orderColStyle(col.key)"
                title="拖动可调整列顺序"
                @dragstart="onOrderColDragStart(col.key)"
                @dragover.prevent
                @drop="onOrderColDrop(col.key)"
              >
                <ColResizeHandle
                  :column-key="col.key"
                  :active="isOrderColResizing(col.key)"
                  @resize-start="(e, th) => startOrderColResize(col.key, e, th)"
                  @auto-fit="autoFitOrderCol"
                />
                <span class="inline-flex items-center gap-1">
                  {{ col.label }}
                  <MesColumnFilter
                    v-if="filterOf(col)"
                    v-model="colFilters[filterOf(col).key]"
                    :type="filterOf(col).type"
                    :placeholder="filterOf(col).placeholder || '输入关键字'"
                    @change="onColFilterChange"
                  />
                </span>
              </th>
              <th
                class="px-3 py-3 sticky right-0 z-10 bg-n-solid-1 border-l border-n-weak after:absolute after:inset-y-0 after:left-full after:w-8 after:bg-n-solid-1 after:content-['']"
              />
            </tr>
          </thead>
          <tbody>
            <tr v-for="e in records" :key="e.id" class="border-b border-n-weak">
              <td
                v-for="col in visibleOrderCols"
                :key="col.key"
                :class="[
                  col.tdClass,
                  orderColStyle(col.key).width && 'truncate',
                ]"
                :style="orderColStyle(col.key)"
              >
                <template v-if="col.key === 'entryNo'">
                  {{ e.entryNo }}
                </template>
                <template v-else-if="col.key === 'purpose'">
                  {{ purposeLabel(e.purpose) }}
                </template>
                <template v-else-if="col.key === 'poNo'">
                  {{ e.purchaseOrderNo || '—' }}
                </template>
                <template v-else-if="col.key === 'suppliers'">
                  {{ (e.supplierNames || []).join('、') || '—' }}
                </template>
                <template v-else-if="col.key === 'qty'">
                  {{ entryQtySummary(e) }}
                </template>
                <template v-else-if="col.key === 'owner'">
                  {{ e.productionOrderOwnerName || '—' }}
                </template>
                <template v-else-if="col.key === 'checked'">
                  {{ e.isChecked ? '已核对' : '—' }}
                </template>
                <template v-else-if="col.key === 'approval'">
                  <span v-if="!e.needsApproval">—</span>
                  <MesStatusPill
                    v-else
                    v-tooltip="
                      e.approvalStatus === 'REJECTED' ? e.rejectReason : ''
                    "
                    :label="APPROVAL_LABELS[e.approvalStatus]"
                  />
                </template>
                <template v-else-if="col.key === 'status'">
                  <MesStatusPill :label="STATUS_LABELS[e.status]" />
                </template>
                <template v-else-if="col.key === 'posted'">
                  {{ day(e.postedAt) }}
                </template>
                <template v-else-if="col.key === 'internalRemark'">
                  {{ e.internalRemark || '—' }}
                </template>
              </td>
              <td
                class="px-3 py-3 text-right sticky right-0 z-10 bg-n-solid-1 border-l border-n-weak after:absolute after:inset-y-0 after:left-full after:w-8 after:bg-n-solid-1 after:content-['']"
              >
                <div class="flex justify-end gap-1">
                  <Button
                    label="查看"
                    variant="ghost"
                    size="sm"
                    @click="openView(e)"
                  />
                  <Button
                    v-if="e.canApprove && e.approvalStatus !== 'APPROVED'"
                    label="审核通过"
                    color="iris"
                    variant="faded"
                    size="sm"
                    :is-loading="posting"
                    @click="approveEntry(e)"
                  />
                  <Button
                    v-if="e.canApprove && e.approvalStatus === 'PENDING'"
                    label="驳回"
                    color="ruby"
                    variant="ghost"
                    size="sm"
                    :is-loading="posting"
                    @click="openReject(e)"
                  />
                  <Button
                    v-if="e.status === 'DRAFT' && mesCan('stock')"
                    v-tooltip="
                      e.needsApproval && e.approvalStatus !== 'APPROVED'
                        ? '财务审核通过后才能过账'
                        : ''
                    "
                    label="过账"
                    color="iris"
                    size="sm"
                    :disabled="
                      e.needsApproval && e.approvalStatus !== 'APPROVED'
                    "
                    :is-loading="posting"
                    @click="postEntry(e)"
                  />
                  <Button
                    v-if="mesCan('stock') && e.status !== 'CANCELLED'"
                    :label="e.status === 'POSTED' ? '作废' : '删单'"
                    color="ruby"
                    variant="ghost"
                    size="sm"
                    :is-loading="posting"
                    @click="removeEntry(e)"
                  />
                  <MesReturnControls
                    :record="e"
                    :store="store"
                    :can-manage="mesCan('stock')"
                  />
                </div>
              </td>
            </tr>
            <tr v-if="!records.length">
              <td
                :colspan="visibleOrderCols.length + 1"
                class="px-3 py-10 text-center text-n-slate-11"
              >
                还没有入库单。
              </td>
            </tr>
          </tbody>
        </table>

        <!-- 按明细：一行一条料（对标金蝶采购入库单列表）。点「查看」仍回到整张单。 -->
        <table v-else class="hidden w-full text-sm whitespace-nowrap md:table">
          <thead>
            <tr
              class="text-left text-n-slate-11 [&>th]:sticky [&>th]:top-0 [&>th]:z-10 [&>th]:bg-n-solid-1 [&>th]:border-b [&>th]:border-n-weak"
            >
              <th
                v-for="col in visibleItemCols"
                :key="col.key"
                draggable="true"
                class="relative px-3 py-2 font-medium transition-colors cursor-move select-none whitespace-nowrap"
                :class="[
                  col.thClass,
                  isItemColDragging(col.key) ? 'opacity-40' : '',
                ]"
                :style="itemColStyle(col.key)"
                title="拖动可调整列顺序"
                @dragstart="onItemColDragStart(col.key)"
                @dragover.prevent
                @drop="onItemColDrop(col.key)"
              >
                <ColResizeHandle
                  :column-key="col.key"
                  :active="isItemColResizing(col.key)"
                  @resize-start="(e, th) => startItemColResize(col.key, e, th)"
                  @auto-fit="autoFitItemCol"
                />
                <span class="inline-flex items-center gap-1">
                  {{ col.label }}
                  <MesColumnFilter
                    v-if="filterOf(col)"
                    v-model="colFilters[filterOf(col).key]"
                    :type="filterOf(col).type"
                    :placeholder="filterOf(col).placeholder || '输入关键字'"
                    @change="onColFilterChange"
                  />
                </span>
              </th>
              <th
                class="px-3 py-2 sticky right-0 z-10 bg-n-solid-1 border-l border-n-weak after:absolute after:inset-y-0 after:left-full after:w-8 after:bg-n-solid-1 after:content-['']"
              />
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in itemRows"
              :key="row.key"
              class="border-b border-n-weak"
            >
              <td
                v-for="col in visibleItemCols"
                :key="col.key"
                :class="[
                  col.tdClass,
                  itemColStyle(col.key).width && 'truncate',
                ]"
                :style="itemColStyle(col.key)"
              >
                <template v-if="col.key === 'status'">
                  <MesStatusPill :label="STATUS_LABELS[row.status]" />
                </template>
                <template v-else>{{ row[col.key] }}</template>
              </td>
              <td
                class="px-3 py-2 text-right sticky right-0 z-10 bg-n-solid-1 border-l border-n-weak after:absolute after:inset-y-0 after:left-full after:w-8 after:bg-n-solid-1 after:content-['']"
              >
                <Button
                  label="查看"
                  variant="ghost"
                  size="sm"
                  @click="openView(row.entry)"
                />
              </td>
            </tr>
            <tr v-if="!itemRows.length">
              <td
                :colspan="visibleItemCols.length + 1"
                class="px-3 py-10 text-center text-n-slate-11"
              >
                还没有入库明细。
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

    <Dialog
      ref="dialogRef"
      :dismissible="false"
      width="7xl"
      overflow-y-auto
      confirm-button-color="iris"
      title="新建原料入库单"
      description="原料/外购成品到货收货：可从采购单预填明细（含外购成品，自动入成品仓），核对实收数量后保存，再「过账」刷新库存。"
      :is-loading="saving"
      :disable-confirm-button="invalid"
      :dirty="isDirty"
      dirty-save-label="保存"
      @confirm="submit"
      @close="markPristine"
      @save="submit"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">入库仓库</label>
            <SelectCard
              size="form"
              :model-value="form.warehouseId"
              :options="warehouseOptions"
              @update:model-value="v => (form.warehouseId = v)"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">关联采购单</label>
            <ComboBox
              :model-value="form.purchaseOrderId"
              :options="purchaseOrderOptions"
              placeholder="不关联采购单"
              search-placeholder="搜采购单号 / 供应商"
              empty-state="没有匹配的采购单"
              @update:model-value="v => (form.purchaseOrderId = v)"
            />
            <!-- 采购单的对内备注：核对入库时要看的就是这句（反馈点名要显示出来）。 -->
            <div
              v-if="selectedPO?.internal_remark"
              class="flex items-start gap-1.5 px-2 py-1.5 mt-1 text-xs rounded-lg text-n-iris-12 bg-n-iris-3/70"
            >
              <span
                class="mt-0.5 shrink-0 i-lucide-sticky-note size-3.5 text-n-iris-11"
              />
              <span class="leading-relaxed">
                采购单对内备注：{{ selectedPO.internal_remark }}
              </span>
            </div>
            <!-- 追加采购单：同一家供应商同一天送来好几张单的料，一次收完
                 （10.17 反馈 A2「有一张单多个采购单的要一起入」）。
                 预填会把挂上的几张单的未收行一起铺出来。 -->
            <div v-if="form.purchaseOrderId" class="flex flex-col gap-1 mt-2">
              <span class="text-xs text-n-slate-11">
                追加采购单（选填，几张单的货一起收）
              </span>
              <SelectCard
                block
                size="form"
                model-value=""
                :options="extraPOOptions"
                @update:model-value="addExtraPO"
              />
              <div
                v-if="form.extraPurchaseOrderIds.length"
                class="flex flex-wrap gap-1.5 mt-1"
              >
                <span
                  v-for="id in form.extraPurchaseOrderIds"
                  :key="`xpo-${id}`"
                  class="inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded-full bg-n-alpha-2 text-n-slate-12"
                >
                  {{ poNoOf(id) }}
                  <button
                    type="button"
                    class="text-n-slate-10 hover:text-n-ruby-11"
                    @click="removeExtraPO(id)"
                  >
                    ✕
                  </button>
                </span>
              </div>
            </div>

            <!-- 一家供应商一张入库单：先挑是哪家送来的货，再预填那几行。 -->
            <div
              v-if="form.purchaseOrderId"
              class="flex flex-wrap items-center gap-2 mt-1"
            >
              <SelectCard
                v-if="prefillSupplierOptions.length > 1"
                v-model="prefillSupplierId"
                :options="prefillSupplierOptions"
                placeholder="这批货是哪家送来的"
                trigger-class="w-72"
              />
              <Button
                label="按此采购单预填收货明细"
                type="button"
                color="iris"
                size="sm"
                icon="i-lucide-list-plus"
                class="po-prefill-btn"
                @click="prefillFromPO"
              />
            </div>
          </div>
        </div>

        <label
          class="inline-flex items-center gap-2 cursor-pointer text-heading-3 text-n-slate-12"
        >
          <input v-model="form.isChecked" type="checkbox" class="size-4" />
          已核对物料齐整度
        </label>

        <div class="flex items-center justify-between">
          <span class="text-heading-2 text-n-slate-12">
            收货明细 <span class="text-n-ruby-11">*</span>
          </span>
          <Button
            label="+ 加一行"
            type="button"
            variant="ghost"
            size="sm"
            @click="addRow"
          />
        </div>
        <div class="grid grid-cols-12 gap-2 text-xs text-n-slate-10">
          <span class="col-span-2">类型</span>
          <span class="col-span-3">物料/成品</span>
          <span class="col-span-2">供应商</span>
          <span class="col-span-1">应收</span>
          <span class="col-span-1">实收</span>
          <span class="col-span-1">备注</span>
          <span class="col-span-2 text-right">附图 / 删行</span>
        </div>
        <div class="flex flex-col gap-2">
          <div
            v-for="(row, i) in form.rows"
            :key="i"
            class="grid items-center grid-cols-12 gap-2"
          >
            <div class="col-span-2">
              <SelectCard
                size="form"
                :model-value="row.itemType"
                :options="ITEM_TYPE_OPTIONS"
                @update:model-value="v => (row.itemType = v)"
              />
            </div>
            <div class="col-span-3">
              <ComboBox
                v-model="row.crmProductId"
                :options="productOptions"
                use-api-results
                :placeholder="
                  row.itemType === 'PRODUCT' ? '选择外购成品' : '选择物料'
                "
                @search="loadProducts"
              />
            </div>
            <!-- 供应商只读：跟着预填的采购行走，不参与提交（入库单不改采购归属）。 -->
            <div class="col-span-2 text-xs truncate text-n-slate-11">
              {{ row.supplierName || '—' }}
            </div>
            <Input v-model="row.qty" type="number" class="col-span-1" />
            <Input
              v-model="row.receivedQty"
              type="number"
              placeholder="同应收"
              class="col-span-1"
            />
            <Input
              v-model="row.remark"
              placeholder="收货单据号"
              class="col-span-1"
            />
            <!-- 行内附图（只对内）：缩略图 + 加图按钮一起靠右，不另起一排。
                 收货时拍的实物照/破损照，对着这颗料存。 -->
            <div
              class="flex flex-wrap items-center justify-end col-span-2 gap-1"
            >
              <div
                v-for="(img, k) in row.images"
                :key="img.signedId"
                class="relative size-9 shrink-0 group"
              >
                <button
                  type="button"
                  :title="img.name"
                  @click="lightboxRef?.open(row.images, k)"
                >
                  <img
                    :src="img.url"
                    :alt="img.name"
                    class="object-contain border rounded size-9 border-n-weak bg-n-alpha-1 hover:opacity-80"
                  />
                </button>
                <button
                  type="button"
                  class="absolute items-center justify-center hidden text-white rounded-full size-4 -top-1 -right-1 bg-n-slate-12/80 group-hover:flex"
                  title="移除这张图"
                  @click="removeRowImage(row, k)"
                >
                  <span class="i-lucide-x size-2.5" />
                </button>
              </div>
              <span v-if="stagingRow === i" class="text-xs text-n-amber-11">
                传中…
              </span>
              <label
                class="inline-flex items-center justify-center border border-dashed rounded cursor-pointer size-9 shrink-0 border-n-weak text-n-slate-10 hover:text-n-slate-12 hover:border-n-slate-8"
                title="加附图（只公司内部看）"
              >
                <span class="i-lucide-image-plus size-4" />
                <input
                  type="file"
                  accept="image/*"
                  multiple
                  class="hidden"
                  @change="e => pickRowImages(e, row, i)"
                />
              </label>
              <button
                type="button"
                class="shrink-0 text-n-slate-10 hover:text-n-ruby-11"
                title="删掉这一行"
                @click="removeRow(i)"
              >
                ✕
              </button>
            </div>
          </div>
        </div>
      </div>
    </Dialog>

    <Dialog
      ref="rejectDialogRef"
      :dismissible="false"
      confirm-button-color="ruby"
      title="驳回这张入库单"
      description="驳回后仓管照着原因改单，改完自动回到「待审核」等你重新审。"
      confirm-button-label="驳回"
      :is-loading="posting"
      :disable-confirm-button="!rejectReason.trim()"
      @confirm="submitReject"
    >
      <div class="flex flex-col gap-1">
        <label class="text-heading-3 text-n-slate-12">
          驳回原因 <span class="text-n-ruby-11">*</span>
        </label>
        <Input v-model="rejectReason" />
      </div>
    </Dialog>

    <MesViewDialog
      ref="viewDialogRef"
      width="7xl"
      hide-print
      :title="viewing ? `入库单 ${viewing.entryNo}` : '入库单明细'"
      :fields="viewFields"
      items-title="收货明细"
      :item-columns="VIEW_ITEM_COLS"
      :items="viewItems"
    >
      <template #headerActions>
        <Button
          v-if="viewing?.productionOrderNo"
          label="这张工单到货明细"
          variant="outline"
          color="slate"
          size="sm"
          @click="goOrderArrivals"
        />
        <Button
          label="打印入库单"
          variant="outline"
          color="slate"
          size="sm"
          @click="printEntry"
        />
      </template>
    </MesViewDialog>

    <!-- 入库单票面：只在打印时用，平时不占版面（printElement 克隆它去打印）。 -->
    <div
      v-if="viewing"
      aria-hidden="true"
      class="fixed -left-[9999px] top-0 w-[1000px]"
    >
      <MesStockEntryPrintSheet
        ref="printSheetRef"
        :entry="viewing"
        :items="printRows"
        :supplier="printSupplier"
      />
    </div>

    <!-- 看图层：就地渲染，跟弹窗一起在顶层，点缩略图放大看 -->
    <MesImageLightbox ref="lightboxRef" />
  </div>
</template>
