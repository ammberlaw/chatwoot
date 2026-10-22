<script setup>
import { ref, reactive, computed, nextTick, onMounted, watch } from 'vue';
import { STATUS_TONE } from 'dashboard/helper/statusTone';
import { useAlert } from 'dashboard/composables';
import { useErpRole } from 'dashboard/composables/useErpRole';
import { fmtMoney } from 'dashboard/helper/erpMoney';
import { printElement } from 'dashboard/helper/printHelper';

import ErpPayableAPI from 'dashboard/api/erp/payables';
import ErpPayableReconAPI from 'dashboard/api/erp/payableReconciliations';
import ErpPaymentAPI from 'dashboard/api/erp/paymentRecords';
import MesPurchaseOrderAPI from 'dashboard/api/mes/purchaseOrders';
import MesSupplierAPI from 'dashboard/api/mes/suppliers';

import Button from 'dashboard/components-next/button/Button.vue';
import ColResizeHandle from 'dashboard/components-next/table/ColResizeHandle.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ErpPayableDetailDialog from 'dashboard/components-next/erp/ErpPayableDetailDialog.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import MonthPicker from 'dashboard/components-next/monthpicker/MonthPicker.vue';
import ErpAllocationEditor from 'dashboard/components-next/erp/ErpAllocationEditor.vue';
import ErpSettlementPrintSheet from 'dashboard/components-next/erp/ErpSettlementPrintSheet.vue';
import ErpAgingTable from 'dashboard/components-next/erp/ErpAgingTable.vue';
import ErpPayableMonthlyTable from 'dashboard/components-next/erp/ErpPayableMonthlyTable.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
import { exportRowsToExcel, fetchAllRows } from 'dashboard/helper/erpExcel';
import { useOrderableColumns } from 'dashboard/composables/useOrderableColumns';
import ColumnPicker from 'dashboard/components-next/ColumnPicker.vue';
import TableHeaderFilter from 'dashboard/components-next/tablefilter/TableHeaderFilter.vue';
// 应付：台账（按采购单建账，按明细行供应商分组）/ 付款记录（核销）/ 供应商对账 三页签。
// 与应收同构；台账「已付」只由核销维护。
const { erpCan } = useErpRole();
const canLedger = computed(() => erpCan('payable'));
const canSettle = computed(() => erpCan('payment'));

const TABS = [
  // 待对账排在台账前面：先对账、对好了才建账（2026-10-21 财务定的流程），
  // 顺序就按流程走，别让人先看到台账再回头找对账在哪。
  { key: 'reconcile', label: '待对账' },
  { key: 'ledger', label: '应付台账' },
  { key: 'payments', label: '付款记录' },
  { key: 'statement', label: '供应商对账' },
  { key: 'monthly', label: '按月未付' },
  { key: 'aging', label: '账龄分析' },
];
const STATUS_OPTIONS = [
  { value: '', label: '全部状态' },
  { value: 'UNPAID', label: '未付款' },
  { value: 'PARTIAL', label: '部分付款' },
  { value: 'PAID', label: '已付清' },
];
const METHODS = [
  { value: 'RMB', label: '人民币转账' },
  { value: 'TT', label: '电汇 TT' },
  { value: 'LC', label: '信用证 LC' },
  { value: 'PAYPAL', label: 'PayPal' },
  { value: 'WESTERN_UNION', label: '西联' },
  { value: 'OTHER', label: '其他' },
];
const STATUS_CLASS = {
  UNPAID: STATUS_TONE.busy,
  PARTIAL: STATUS_TONE.flow,
  PAID: STATUS_TONE.done,
};

const money = micros => (micros ? fmtMoney(micros) : '—');
// 页头汇总：筛选筛到一条不剩时要显示 0.00。单元格里空值用「—」没问题，
// 汇总写「应付 —」看着像算不出来，财务会以为系统坏了。
const sum = micros => fmtMoney(micros || 0);
const toMicros = value => Math.round(Number(value || 0) * 1_000_000);
const today = () => new Date().toISOString().slice(0, 10);

const activeTab = ref('ledger');
const loading = ref(false);
const keyword = ref('');
const statusFilter = ref('');
// 发生日期区间（货到那天，不是财务录单那天）。单边留空＝只卡一头。
const fromDate = ref('');
const toDate = ref('');
// 结算方式：钱打公司账户＝有票含税，打个人账户＝无票未税。财务对账时这两摊钱要分开看。
// 界面只说含税/未税（后端 Erp::Payable::SETTLE_TYPE_LABELS 同口径）。
const settleFilter = ref('');
// 空列表时要分清「还没建账」和「筛没了」——两种情况该做的事完全不同。
const hasLedgerFilter = computed(() =>
  Boolean(
    keyword.value.trim() ||
    statusFilter.value ||
    settleFilter.value ||
    fromDate.value ||
    toDate.value
  )
);
const SETTLE_OPTIONS = [
  { value: '', label: '全部结算' },
  { value: 'PUBLIC', label: '含税' },
  { value: 'PRIVATE', label: '未税' },
];

const ledgers = ref([]);

// 一笔应付摊成几行物料：台账级单元格用 rowspan 跨完整笔，明细列一行一项。
// 在这里摊平而不是模板里套 <template v-for>，省得整块表格缩进全挪。
const ledgerRows = computed(() =>
  ledgers.value.flatMap(row => {
    // 没有明细的老单也要占一行，否则整笔台账不显示。
    const items = row.line_items?.length ? row.line_items : [{}];
    return items.map((item, li) => ({ row, item, li, span: items.length }));
  })
);
// 含税/未税默认按供应商档案带出来。个别单实际开没开票不一样（临时补票、说好开票又没开），
// 财务点一下这个角标就地改，不用回头去改供应商档案——档案是默认值，不是这一单的事实。
const toggleSettleType = async row => {
  const next = row.settle_type === 'PRIVATE' ? 'PUBLIC' : 'PRIVATE';
  const before = { type: row.settle_type, label: row.settle_type_label };
  row.settle_type = next;
  row.settle_type_label = next === 'PRIVATE' ? '未税' : '含税';
  try {
    await ErpPayableAPI.update(row.id, { payable: { settle_type: next } });
  } catch (error) {
    row.settle_type = before.type;
    row.settle_type_label = before.label;
    useAlert(error?.response?.data?.error || '结算方式保存失败');
  }
};

// 数量是原样的数（不是微元），只做千分位。
const qty = value =>
  value === null || value === undefined || value === ''
    ? '—'
    : Number(value).toLocaleString('zh-CN', { maximumFractionDigits: 3 });
// 台账表的列。rowspan=true 的是「台账级」字段（一笔应付跨完整几行物料），
// 其余是「明细级」（一行料一行）。列序可拖、用不到的列可收起，按人记在本机——
// 同应收台账与 MES 那几张表一套交互。
const LEDGER_COLUMN_DEFS = [
  // filter: 'text'（关键字 + 八种条件）| 'enum'（取值固定，直接选值）。
  // 标了哪几列必须和控制器的 LEDGER_COLUMN_SQL 对齐。明细行按「任一行命中」筛。
  // 金额/数量这类数字列不出漏斗——按文本比大小没意义。
  { key: 'no', label: '台账单号', rowspan: true, filter: 'text' },
  { key: 'supplier', label: '供应商 / 采购单', rowspan: true, filter: 'text' },
  {
    key: 'settle',
    label: '结算',
    rowspan: true,
    filter: 'enum',
    filterOptions: 'settle',
  },
  // 发生日期＝货到那天。已经能按它筛了，但表上一直没有这一列，
  // 筛完对不上「我筛的到底是哪个日期」。
  { key: 'incurredOn', label: '发生日期', rowspan: true },
  { key: 'code', label: '物料编码', filter: 'text' },
  { key: 'name', label: '品名', filter: 'text' },
  { key: 'spec', label: '规格', filter: 'text' },
  { key: 'qty', label: '数量', right: true },
  { key: 'price', label: '单价', right: true },
  { key: 'amount', label: '金额', right: true },
  { key: 'total', label: '应付', rowspan: true, right: true },
  { key: 'paid', label: '已付', rowspan: true, right: true },
  { key: 'outstanding', label: '未付', rowspan: true, right: true },
  { key: 'dueDate', label: '到期日', rowspan: true },
  {
    key: 'status',
    label: '状态',
    rowspan: true,
    filter: 'enum',
    filterOptions: 'status',
  },
];
const {
  orderedColumns: ledgerCols,
  visibleColumns: ledgerVisibleCols,
  isHidden: isLedgerColHidden,
  toggleColumn: toggleLedgerCol,
  showAllColumns: showAllLedgerCols,
  isDragging: isLedgerColDragging,
  onColDragStart: onLedgerColDragStart,
  onColDrop: onLedgerColDrop,
  resetOrder: resetLedgerColOrder,
  colStyle: ledgerColStyle,
  isResizing: isLedgerColResizing,
  startResize: startLedgerColResize,
  autoFitColumn: autoFitLedgerCol,
} = useOrderableColumns(LEDGER_COLUMN_DEFS, 'erp.apLedgerCols.v1');
const hiddenLedgerCols = computed(
  () => LEDGER_COLUMN_DEFS.length - ledgerVisibleCols.value.length
);
const ledgerMeta = ref({});
const payments = ref([]);
const paymentMeta = ref({});
// 供应商对账：接口一次给全量（没有分页），屏幕上的就是全部，前端筛就对。
const statementSupplierFilter = ref({});
const statementRows = ref([]);
const filteredStatementRows = computed(() => {
  const f = statementSupplierFilter.value;
  if (!f?.op) return statementRows.value;
  const kw = String(f.value || '').toLowerCase();
  return statementRows.value.filter(r =>
    String(r.name || '')
      .toLowerCase()
      .includes(kw)
  );
});

// 分页：meta.count 是全量数，超过一页给翻页入口——静默截断=「数据消失」。
const PER_PAGE = 50;
const ledgerPage = ref(1);
// 表头漏斗筛选（对标金蝶）：{ 列名: { op, value } }。服务端按列筛，不是只筛当前这一页——
// 列表是分页的，筛 50 行说「没有」，翻到第二页它又在。
const colFilters = ref({});
// 付款记录 / 供应商对账 / 按月未付 各自的表头筛选（列不一样，分开存）。
const paymentColFilters = ref({});
// 两个页签筛的不是同一个日期，占位文案要说清楚，不然筛不出来还以为坏了。
const DATE_LABEL = { ledger: '发生日期', payments: '付款日' };
// axios 默认序列化器把嵌套对象拍成 "[object Object]"，所以自己展开成
// cf[列][op] / cf[列][value]——Rails 按方括号解回嵌套 params。
const colFilterParams = (source = colFilters.value) => {
  const out = {};
  Object.entries(source).forEach(([key, f]) => {
    if (!f?.op) return;
    out[`cf[${key}][op]`] = f.op;
    out[`cf[${key}][value]`] = f.value ?? '';
  });
  return out;
};
const paymentPage = ref(1);

const loadLedgers = async () => {
  loading.value = true;
  try {
    const { data } = await ErpPayableAPI.get({
      q: keyword.value.trim(),
      status: statusFilter.value,
      settle_type: settleFilter.value,
      from: fromDate.value,
      to: toDate.value,
      page: ledgerPage.value,
      per_page: PER_PAGE,
      ...colFilterParams(),
    });
    ledgers.value = data.payload;
    ledgerMeta.value = data.meta;
  } finally {
    loading.value = false;
  }
};

const loadPayments = async () => {
  loading.value = true;
  try {
    const { data } = await ErpPaymentAPI.get({
      q: keyword.value.trim(),
      from: fromDate.value,
      to: toDate.value,
      page: paymentPage.value,
      per_page: PER_PAGE,
      ...colFilterParams(paymentColFilters.value),
    });
    payments.value = data.payload;
    paymentMeta.value = data.meta;
  } finally {
    loading.value = false;
  }
};

watch([keyword, statusFilter, settleFilter, fromDate, toDate], () => {
  ledgerPage.value = 1;
  paymentPage.value = 1;
});
watch(ledgerPage, loadLedgers);

const FILTER_OPTION_SETS = {
  paymentStatus: [
    { value: 'NORMAL', label: '正常' },
    { value: 'VOID', label: '已作废' },
  ],
  status: STATUS_OPTIONS.filter(o => o.value),
  settle: SETTLE_OPTIONS.filter(o => o.value),
};
const onColFilterChange = () => {
  ledgerPage.value = 1;
  loadLedgers();
};
const activeColFilterCount = computed(
  () => Object.values(colFilters.value).filter(f => f?.op).length
);
const clearColFilters = () => {
  colFilters.value = {};
  onColFilterChange();
};
watch(paymentPage, loadPayments);

const onPaymentColFilter = () => {
  paymentPage.value = 1;
  loadPayments();
};

const loadStatement = async () => {
  loading.value = true;
  try {
    const { data } = await ErpPayableAPI.supplierStatement();
    statementRows.value = data.payload;
  } finally {
    loading.value = false;
  }
};

/* ---------------- 待对账 ---------------- */
// 收了货先跟供应商核对，对好了才落应付台账（见 Erp::PayableReconciliationsController）。
// 每行＝一张采购单 × 一家供应商，按**已过账**的实收数量算该欠多少。
const reconRows = ref([]);
const reconLoading = ref(false);
const confirmingRecon = ref(null);
const loadRecon = async () => {
  reconLoading.value = true;
  try {
    const { data } = await ErpPayableReconAPI.get();
    reconRows.value = data.payload || [];
  } catch (error) {
    useAlert(error?.response?.data?.error || '待对账清单加载失败');
  } finally {
    reconLoading.value = false;
  }
};
const reconKey = row => `${row.mes_purchase_order_id}-${row.mes_supplier_id}`;
// 差额＝该欠的减去台账已建的。首次建账时已建为 0，差额就是全额。
const reconDiff = row => (row.received_micros || 0) - (row.booked_micros || 0);
// 收货日期：同一张采购单上不同供应商的货未必同一天到，所以这是**这家**的收货区间。
// 同一天就写一个日期；跨天后半段省掉年份，不然一列塞 23 个字符把表撑歪。
const reconDate = row => {
  const first = row.first_receipt_on;
  const last = row.last_receipt_on;
  if (!first) return '—';
  return !last || last === first ? first : `${first} ~ ${last.slice(5)}`;
};
// 按月对账：财务是一个月一个月核的，默认不筛（全看）。按**最近收货日**归月——
// 跨月到货的那一笔算在收尾那个月，与应付台账「发生日期」取最后一次入库是同一口径。
const reconMonth = ref('');
const filteredReconRows = computed(() => {
  if (!reconMonth.value) return reconRows.value;
  return reconRows.value.filter(
    row => (row.last_receipt_on || '').slice(0, 7) === reconMonth.value
  );
});
const reconPendingTotal = computed(() =>
  filteredReconRows.value.reduce((acc, row) => acc + reconDiff(row), 0)
);
const confirmRecon = async row => {
  confirmingRecon.value = reconKey(row);
  try {
    const { data } = await ErpPayableReconAPI.confirm(
      row.mes_purchase_order_id,
      row.mes_supplier_id
    );
    const { payable_no: payableNo, warning } = data.payload || {};
    // 警告（按实收重算后低于已付）要单独说，被「已建账」的提示盖掉财务就不知道。
    useAlert(warning || `已建账 ${payableNo}`);
    await loadRecon();
    if (activeTab.value === 'ledger') loadLedgers();
  } catch (error) {
    useAlert(error?.response?.data?.error || '建账失败');
  } finally {
    confirmingRecon.value = null;
  }
};

const agingRef = ref(null);
const monthlyRef = ref(null);
// 供应商对账与账龄分析不吃关键字（各自有自己的查询条），隐掉顶部搜索。
const isDocTab = computed(() =>
  ['ledger', 'payments'].includes(activeTab.value)
);
const reload = () => {
  if (activeTab.value === 'ledger') return loadLedgers();
  if (activeTab.value === 'payments') return loadPayments();
  if (activeTab.value === 'reconcile') return loadRecon();
  if (activeTab.value === 'statement') return loadStatement();
  if (activeTab.value === 'monthly') return monthlyRef.value?.load();
  return agingRef.value?.load();
};
const switchTab = key => {
  // 两个页签筛的不是同一个日期（发生日期/付款日），带过去必然筛空。
  fromDate.value = '';
  toDate.value = '';
  activeTab.value = key;
  nextTick(reload);
};

/* ---------------- 从采购单建账 ---------------- */
// 点台账单号就地看明细：这笔钱是哪张采购单、哪几行料、货到没到、付了几次。
const detailDialogRef = ref(null);
const openPayableDetail = id => detailDialogRef.value?.open(id);

const buildDialogRef = ref(null);
const purchaseOrderOptions = ref([]);
const selectedPurchaseOrderId = ref('');
const searchPurchaseOrders = async q => {
  const { data } = await MesPurchaseOrderAPI.get({ q, per_page: 20 });
  purchaseOrderOptions.value = (data?.payload || []).map(po => ({
    value: po.id,
    label: `${po.po_no}${po.supplier_names ? ` · ${po.supplier_names}` : ''}`,
  }));
};
const openBuild = () => {
  selectedPurchaseOrderId.value = '';
  searchPurchaseOrders('');
  buildDialogRef.value?.open();
};
const submitBuild = async () => {
  if (!selectedPurchaseOrderId.value) return;
  try {
    const { data } = await ErpPayableAPI.buildFromPurchaseOrder(
      selectedPurchaseOrderId.value
    );
    useAlert(`已按供应商生成 ${data.payload.length} 条应付台账`);
    buildDialogRef.value?.close();
    loadLedgers();
  } catch (error) {
    useAlert(error?.response?.data?.error || '建账失败');
  }
};

/* ---------------- 付款单 ---------------- */
const paymentDialogRef = ref(null);
const editingPayment = ref(null);
const openPayables = ref([]);
const allocationRows = ref([]);
const supplierOptions = ref([]);
const paymentForm = reactive({
  mesSupplierId: '',
  amount: '',
  currency: 'CNY',
  exchangeRate: 1,
  bankCharge: '',
  method: 'RMB',
  paidAt: today(),
  referenceNo: '',
  remark: '',
});
const { isDirty, markPristine } = useDirtyGuard(() => paymentForm);
const allocationLedgers = computed(() =>
  openPayables.value.map(p => ({
    id: p.id,
    no: p.payable_no,
    label: `${p.po_no || p.supplier_name} · 应付 ${fmtMoney(p.total_amount_micros)}`,
    outstanding_micros: p.outstanding_micros,
  }))
);
// 可核销上限是毛额（付出净额＋手续费），与后端 AllocationService 口径一致
const paymentAmountMicros = computed(
  () => toMicros(paymentForm.amount) + toMicros(paymentForm.bankCharge)
);

const searchSuppliers = async q => {
  const { data } = await MesSupplierAPI.get({ q, active: 'true' });
  supplierOptions.value = (data?.payload || []).map(s => ({
    value: s.id,
    label: s.name,
  }));
};

const loadOpenPayables = async supplierId => {
  if (!supplierId) {
    openPayables.value = [];
    return;
  }
  const { data } = await ErpPayableAPI.openList({
    mes_supplier_id: supplierId,
  });
  openPayables.value = data.payload;
};

const openPayment = async (record = null) => {
  editingPayment.value = record;
  allocationRows.value = record
    ? record.allocations.map(a => ({
        ledgerId: a.payable_id,
        amount: (a.amount_micros / 1_000_000).toFixed(2),
      }))
    : [];
  Object.assign(paymentForm, {
    mesSupplierId: record?.mes_supplier_id || '',
    amount: record ? (record.amount_micros / 1_000_000).toFixed(2) : '',
    currency: record?.currency || 'CNY',
    exchangeRate: record ? Number(record.exchange_rate) : 1,
    bankCharge: record?.bank_charge_micros
      ? (record.bank_charge_micros / 1_000_000).toFixed(2)
      : '',
    method: record?.method || 'RMB',
    paidAt: record?.paid_at || today(),
    referenceNo: record?.reference_no || '',
    remark: record?.remark || '',
  });
  await searchSuppliers('');
  await loadOpenPayables(paymentForm.mesSupplierId);
  markPristine();
  paymentDialogRef.value?.open();
};

const onSupplierChange = () => {
  allocationRows.value = [];
  loadOpenPayables(paymentForm.mesSupplierId);
};

const paymentInvalid = computed(
  () => !paymentForm.mesSupplierId || !paymentForm.amount || !paymentForm.paidAt
);

const submitPayment = async () => {
  if (paymentInvalid.value) return;
  const payload = {
    payment: {
      mes_supplier_id: paymentForm.mesSupplierId,
      amount_micros: paymentAmountMicros.value,
      currency: paymentForm.currency,
      exchange_rate: paymentForm.exchangeRate,
      bank_charge_micros: toMicros(paymentForm.bankCharge),
      method: paymentForm.method,
      paid_at: paymentForm.paidAt,
      reference_no: paymentForm.referenceNo,
      remark: paymentForm.remark,
    },
    allocations: allocationRows.value
      .filter(row => row.amount)
      .map(row => ({
        payable_id: row.ledgerId,
        amount_micros: toMicros(row.amount),
      })),
  };
  try {
    const { data } = editingPayment.value
      ? await ErpPaymentAPI.updateWithAllocations(
          editingPayment.value.id,
          payload
        )
      : await ErpPaymentAPI.createWithAllocations(payload);
    useAlert(`付款单 ${data.payment_no} 已保存`);
    paymentDialogRef.value?.close();
    loadPayments();
    if (ledgers.value.length) loadLedgers();
  } catch (error) {
    useAlert(error?.response?.data?.error || '保存失败');
  }
};

const voidPayment = async record => {
  try {
    await ErpPaymentAPI.void(record.id);
    useAlert(`${record.payment_no} 已作废，核销与台账余额已回滚`);
    loadPayments();
    if (ledgers.value.length) loadLedgers();
  } catch (error) {
    useAlert(error?.response?.data?.error || '作废失败');
  }
};

/* ---------------- 打印 ---------------- */
const printAreaRef = ref(null);
const printSheets = ref([]);
const printPayment = async record => {
  printSheets.value = [record];
  await nextTick();
  printElement(printAreaRef.value, `付款单 ${record.payment_no}`);
};

/* ---------------- 导出 Excel ---------------- */
// 按当前页签导当前这张表，带上屏幕上的筛选条件——财务筛完再导、导出来却是全量，
// 等于筛了个寂寞。
// ⚠️ 全量：列表一页 50 条，这里重新向后端分页要完（ERP 后端 per_page 夹在 100）。
// 「按月未付」的导出在 ErpPayableMonthlyTable 组件自己身上，这里不重复做。
const exporting = ref(false);
const stamp = () => new Date().toLocaleString('sv').slice(0, 16);

// 台账导明细行：一笔应付几行物料就几行。Excel 里没有 rowspan，
// 台账级字段每行重复写，筛选/透视才用得上。
const ledgerExportRows = rows =>
  rows.flatMap(row => {
    const items = row.line_items?.length ? row.line_items : [{}];
    return items.map(item => ({
      payable_no: row.payable_no,
      supplier_name: row.supplier_name,
      po_no: row.po_no,
      settle_type_label: row.settle_type_label,
      incurred_on: row.incurred_on,
      code: item.code,
      name: item.name,
      spec: item.spec,
      unit: item.unit,
      quantity: item.quantity,
      unit_price_micros: item.unit_price_micros,
      amount_micros: item.amount_micros,
      currency: row.currency,
      total_amount_micros: row.total_amount_micros,
      paid_amount_micros: row.paid_amount_micros,
      outstanding_micros: row.outstanding_micros,
      due_date: row.due_date,
      status_label: row.status_label,
    }));
  });

const exportLedger = async () => {
  // 导出跟着屏幕上看到的走：漏斗筛掉的行不该又出现在 Excel 里。
  const raw = await fetchAllRows(params => ErpPayableAPI.get(params), {
    q: keyword.value.trim(),
    status: statusFilter.value,
    settle_type: settleFilter.value,
    from: fromDate.value,
    to: toDate.value,
    ...colFilterParams(),
  });
  const rows = ledgerExportRows(raw);
  exportRowsToExcel(
    {
      title: '应付账款台账',
      meta: [
        { label: '导出时间', value: stamp() },
        { label: '关键字', value: keyword.value.trim() || '（无）' },
        {
          label: '状态',
          value:
            STATUS_OPTIONS.find(o => o.value === statusFilter.value)?.label ||
            '全部状态',
        },
        {
          label: '结算',
          value:
            SETTLE_OPTIONS.find(o => o.value === settleFilter.value)?.label ||
            '全部结算',
        },
        {
          label: '发生日期',
          value: `${fromDate.value || '不限'} ~ ${toDate.value || '不限'}`,
        },
        { label: '台账笔数', value: raw.length },
        { label: '明细行数', value: rows.length },
      ],
      columns: [
        { label: '台账单号', key: 'payable_no' },
        { label: '供应商', key: 'supplier_name' },
        { label: '采购单', key: 'po_no' },
        { label: '结算', key: 'settle_type_label' },
        { label: '发生日期', key: 'incurred_on' },
        { label: '物料编码', key: 'code' },
        { label: '品名', key: 'name' },
        { label: '规格', key: 'spec' },
        { label: '单位', key: 'unit' },
        { label: '数量', key: 'quantity', num: true },
        { label: '单价', key: 'unit_price_micros', money: true },
        { label: '金额', key: 'amount_micros', money: true },
        { label: '币种', key: 'currency' },
        { label: '应付', key: 'total_amount_micros', money: true },
        { label: '已付', key: 'paid_amount_micros', money: true },
        { label: '未付', key: 'outstanding_micros', money: true },
        { label: '到期日', key: 'due_date' },
        { label: '状态', key: 'status_label' },
      ],
      rows,
    },
    `应付账款台账_${stamp().slice(0, 10)}`
  );
};

const exportPayments = async () => {
  const rows = await fetchAllRows(params => ErpPaymentAPI.get(params), {
    q: keyword.value.trim(),
    from: fromDate.value,
    to: toDate.value,
  });
  exportRowsToExcel(
    {
      title: '付款记录',
      meta: [
        { label: '导出时间', value: stamp() },
        { label: '关键字', value: keyword.value.trim() || '（无）' },
        { label: '付款笔数', value: rows.length },
      ],
      columns: [
        { label: '付款单号', key: 'payment_no' },
        { label: '供应商', key: 'supplier_name' },
        { label: '付款日', key: 'paid_at' },
        { label: '币种', key: 'currency' },
        { label: '付款金额', key: 'amount_micros', money: true },
        { label: '未核销', key: 'unallocated_micros', money: true },
        { label: '付款方式', key: 'method_label' },
        { label: '水单号', key: 'reference_no' },
        { label: '状态', key: 'status_label' },
      ],
      rows: rows.map(row => ({
        ...row,
        paid_at: (row.paid_at || '').slice(0, 10),
      })),
    },
    `付款记录_${stamp().slice(0, 10)}`
  );
};

// 供应商对账接口一次给全量（没有分页），屏幕上的就是全量。
const exportStatement = async () => {
  if (!statementRows.value.length) await loadStatement();
  exportRowsToExcel(
    {
      title: '供应商对账',
      meta: [
        { label: '导出时间', value: stamp() },
        { label: '单位', value: '元（本位币）' },
        { label: '供应商数', value: statementRows.value.length },
      ],
      columns: [
        { label: '供应商', key: 'name' },
        { label: '应付合计', key: 'total_micros', money: true },
        { label: '已付合计', key: 'paid_micros', money: true },
        { label: '未付合计', key: 'outstanding_micros', money: true },
      ],
      rows: statementRows.value,
    },
    `供应商对账_${stamp().slice(0, 10)}`
  );
};

// 待对账：屏幕上就是全量（接口不分页），导的就是月份筛完剩下的那些。
// 财务拿这张表去跟供应商核，核完回来点「对好了，建账」。
const exportReconcile = async () => {
  if (!reconRows.value.length) await loadRecon();
  exportRowsToExcel(
    {
      title: '应付待对账',
      meta: [
        { label: '导出时间', value: stamp() },
        { label: '收货月份', value: reconMonth.value || '全部' },
        { label: '单位', value: '元（本位币）' },
        { label: '条数', value: filteredReconRows.value.length },
        { label: '待建合计', value: money(reconPendingTotal.value) },
      ],
      columns: [
        { label: '首次收货', key: 'first_receipt_on' },
        { label: '最近收货', key: 'last_receipt_on' },
        { label: '入库单数', key: 'entry_count', num: true },
        { label: '采购单', key: 'po_no' },
        { label: '供应商', key: 'supplier_name' },
        { label: '已收货金额', key: 'received_micros', money: true },
        { label: '台账已建', key: 'booked_micros', money: true },
        { label: '待建金额', key: 'diff_micros', money: true },
      ],
      rows: filteredReconRows.value.map(row => ({
        ...row,
        diff_micros: reconDiff(row),
      })),
    },
    `应付待对账_${stamp().slice(0, 10)}`
  );
};

const EXPORTERS = {
  ledger: exportLedger,
  payments: exportPayments,
  statement: exportStatement,
  reconcile: exportReconcile,
};
const canExport = computed(() => Boolean(EXPORTERS[activeTab.value]));
const exportCurrent = async () => {
  const run = EXPORTERS[activeTab.value];
  if (!run) return;

  exporting.value = true;
  try {
    await run();
  } catch (error) {
    useAlert('导出失败，请重试');
  } finally {
    exporting.value = false;
  }
};

/* ---------------- 补出应付凭证 ---------------- */
// 应付的凭证不在这张台账上生成——它是原料入库**过账时**自动出的（借存货 / 贷应付账款）。
// 自动规则 2026-10-09 才上线，在那之前过账的单一张凭证都没有，而台账上又没有任何补出的
// 入口：财务看到的就是「应付有账、总账没账」，而且问不出为什么。
// 这里把该出没出的入库单捞出来，一次补完；出不了的原因由后端判定后原样带回。
const canVoucher = computed(() => erpCan('voucher'));
const pendingVouchers = ref([]);
const buildingVouchers = ref(false);
const loadPendingVouchers = async () => {
  if (!canVoucher.value) return;
  try {
    const { data } = await ErpPayableAPI.pendingVouchers();
    pendingVouchers.value = data.payload || [];
  } catch {
    // 补出凭证是附带功能，拉不到名单不该让整个台账页报错
    pendingVouchers.value = [];
  }
};
// 面板：把名单摆出来让财务挑，而不是一按全补。
// 用户原话「一个月的入库单核对好了后，怎么选中入库单生成凭证」——按月核、按月出凭证
// 是财务的实际节奏，一次性全补对不上她手里的那叠单。
const voucherDialogRef = ref(null);
const voucherMonth = ref('');
const selectedVouchers = ref([]);
const openVoucherPanel = async () => {
  await loadPendingVouchers();
  voucherMonth.value = '';
  // 默认勾上所有能出的：多数时候就是全补，逐个点一遍是白费力气。
  selectedVouchers.value = pendingVouchers.value
    .filter(row => !row.blocker)
    .map(row => row.id);
  voucherDialogRef.value?.open();
};
const filteredVouchers = computed(() => {
  if (!voucherMonth.value) return pendingVouchers.value;
  return pendingVouchers.value.filter(
    row => (row.posted_on || '').slice(0, 7) === voucherMonth.value
  );
});
// 出不了的不参与勾选——勾了也只会换来一条失败提示。
const buildableVouchers = computed(() =>
  filteredVouchers.value.filter(row => !row.blocker)
);
const voucherChecked = id => selectedVouchers.value.includes(id);
const toggleVoucher = id => {
  selectedVouchers.value = voucherChecked(id)
    ? selectedVouchers.value.filter(x => x !== id)
    : [...selectedVouchers.value, id];
};
const allVouchersChecked = computed(
  () =>
    buildableVouchers.value.length > 0 &&
    buildableVouchers.value.every(row => voucherChecked(row.id))
);
const toggleAllVouchers = () => {
  const ids = buildableVouchers.value.map(row => row.id);
  selectedVouchers.value = allVouchersChecked.value
    ? selectedVouchers.value.filter(id => !ids.includes(id))
    : [...new Set([...selectedVouchers.value, ...ids])];
};
// 只统计屏幕上这批里勾中的：筛了月份还把别的月算进合计，财务对不上数。
const selectedVoucherRows = computed(() =>
  filteredVouchers.value.filter(row => voucherChecked(row.id))
);
const selectedVoucherTotal = computed(() =>
  selectedVoucherRows.value.reduce(
    (acc, row) => acc + (row.amount_micros || 0),
    0
  )
);
const purposeLabel = row =>
  row.purpose === 'MATERIAL_RETURN' ? '采购退货' : '采购入库';

const exportPendingVouchers = () => {
  exportRowsToExcel(
    {
      title: '待补应付凭证',
      meta: [
        { label: '导出时间', value: stamp() },
        { label: '过账月份', value: voucherMonth.value || '全部' },
        { label: '单位', value: '元（本位币）' },
        { label: '入库单数', value: filteredVouchers.value.length },
      ],
      columns: [
        { label: '过账日', key: 'posted_on' },
        { label: '类型', key: 'purpose_label' },
        { label: '入库单号', key: 'entry_no' },
        { label: '采购单', key: 'po_no' },
        { label: '供应商', key: 'supplier_names' },
        { label: '金额', key: 'amount_micros', money: true },
        { label: '出不了的原因', key: 'blocker' },
      ],
      rows: filteredVouchers.value.map(row => ({
        ...row,
        purpose_label: purposeLabel(row),
        blocker: row.blocker || '',
      })),
    },
    `待补应付凭证_${stamp().slice(0, 10)}`
  );
};

const buildPendingVouchers = async () => {
  const targets = selectedVoucherRows.value.filter(row => !row.blocker);
  if (!targets.length) return;
  buildingVouchers.value = true;
  let done = 0;
  const failures = [];
  try {
    // 逐张补：出不了的各有各的原因（科目没配、采购行没填金额），
    // 一张失败不该把其余的也挡住，最后把原因一并报出来（同应收那边）。
    for (let i = 0; i < targets.length; i += 1) {
      try {
        // eslint-disable-next-line no-await-in-loop
        await ErpPayableAPI.buildReceiptVoucher(targets[i].id);
        done += 1;
      } catch (error) {
        failures.push(
          `${targets[i].entry_no}：${error?.response?.data?.error || '补出失败'}`
        );
      }
    }
  } finally {
    buildingVouchers.value = false;
  }
  await loadPendingVouchers();
  // 补完的已经从名单里消失，勾选跟着收敛到还剩下的那些。
  selectedVouchers.value = selectedVouchers.value.filter(id =>
    pendingVouchers.value.some(row => row.id === id)
  );
  if (!pendingVouchers.value.length) voucherDialogRef.value?.close();
  useAlert(
    failures.length
      ? `补出 ${done} 张，${failures.length} 张没出：${failures[0]}${
          failures.length > 1 ? ` 等 ${failures.length} 条` : ''
        }`
      : `已补出 ${done} 张应付凭证`
  );
};

onMounted(() => {
  loadLedgers();
  loadPendingVouchers();
  // 进页面就拉一次：待对账的条数要显示在页签上，不然财务不知道有货等着对。
  loadRecon();
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div
      class="flex items-center justify-between gap-3 px-6 py-4 [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8"
    >
      <div class="flex items-center gap-2">
        <div class="i-lucide-file-output size-5 text-n-iris-9" />
        <h1
          class="text-xl font-semibold text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8"
        >
          应付管理
        </h1>
        <span v-if="activeTab === 'ledger'" class="text-sm text-n-slate-11">
          应付 {{ sum(ledgerMeta.total_micros) }} · 已付
          {{ sum(ledgerMeta.paid_micros) }} · 未付
          <span class="text-n-slate-12">{{
            sum(ledgerMeta.outstanding_micros)
          }}</span>
        </span>
        <span
          v-else-if="activeTab === 'payments'"
          class="text-sm text-n-slate-11"
        >
          本页付款合计 {{ money(paymentMeta.amount_micros) }}
        </span>
        <span
          v-else-if="activeTab === 'reconcile'"
          class="text-sm text-n-slate-11"
        >
          待对账 {{ filteredReconRows.length }} 条 · 待建合计
          <span class="text-n-slate-12">{{ money(reconPendingTotal) }}</span>
        </span>
      </div>
      <div class="flex items-center gap-2">
        <Input
          v-if="isDocTab"
          v-model="keyword"
          size="sm"
          placeholder="搜单号 / 供应商 / 采购单号"
          custom-input-class="w-44"
          @keyup.enter="reload"
        />
        <!-- 按月对账：财务一个月一个月地核，没有月份就只能从头翻到尾 -->
        <MonthPicker
          v-if="activeTab === 'reconcile'"
          v-model="reconMonth"
          placeholder="收货月份"
          trigger-class="w-32 h-8"
        />
        <!-- 漏斗筛了几列就显示几，点一下全清——逐列点回「重置」太费事 -->
        <Button
          v-if="activeColFilterCount"
          :label="`清除筛选 (${activeColFilterCount})`"
          variant="ghost"
          color="ruby"
          size="sm"
          @click="clearColFilters"
        />
        <Button
          v-if="isDocTab"
          label="查询"
          color="slate"
          size="sm"
          @click="reload"
        />
        <!-- 列序是本机记忆，拖乱了要有路回来 -->
        <Button
          v-if="activeTab === 'ledger'"
          label="恢复默认列序"
          variant="ghost"
          color="slate"
          size="sm"
          @click="resetLedgerColOrder"
        />
        <ColumnPicker
          v-if="activeTab === 'ledger'"
          :columns="ledgerCols"
          :is-hidden="isLedgerColHidden"
          :hidden-count="hiddenLedgerCols"
          @toggle="toggleLedgerCol"
          @show-all="showAllLedgerCols"
        />
        <!-- 导出是只读动作，不挂写权限 -->
        <Button
          v-if="canExport"
          label="导出 Excel"
          color="slate"
          variant="faded"
          size="sm"
          :is-loading="exporting"
          @click="exportCurrent"
        />
        <!-- 应付凭证是入库过账时出的，规则上线前过账的老单一张都没出——台账上得有条补的路 -->
        <Button
          v-if="canVoucher && activeTab === 'ledger' && pendingVouchers.length"
          :label="`补出凭证 (${pendingVouchers.length})`"
          color="amber"
          variant="faded"
          size="sm"
          @click="openVoucherPanel"
        />
        <Button
          v-if="canLedger && activeTab === 'ledger'"
          label="从采购单建账"
          color="iris"
          size="sm"
          @click="openBuild"
        />
        <Button
          v-if="canSettle && activeTab === 'payments'"
          label="登记付款"
          color="iris"
          size="sm"
          @click="openPayment()"
        />
      </div>
    </div>

    <div
      class="flex items-center gap-2 px-6 pb-3 [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8"
    >
      <div class="flex items-center gap-2" data-tabbar="page">
        <button
          v-for="tab in TABS"
          :key="tab.key"
          :aria-selected="activeTab === tab.key"
          class="h-9 px-3 text-sm transition-colors rounded-lg"
          :class="
            activeTab === tab.key
              ? 'bg-n-iris-9 text-white'
              : 'text-n-slate-11 hover:bg-n-alpha-2'
          "
          @click="switchTab(tab.key)"
        >
          {{ tab.label }}
          <!-- 有货等着对账就把条数写在页签上，不然财务不知道该进来 -->
          <span
            v-if="tab.key === 'reconcile' && reconRows.length"
            class="ml-1 px-1.5 py-0.5 text-xs rounded-full"
            :class="
              activeTab === tab.key
                ? 'bg-white/25 text-white'
                : 'bg-n-amber-4 text-n-amber-11'
            "
          >
            {{ reconRows.length }}
          </span>
        </button>
      </div>
      <!-- 台账筛选：状态 / 结算（含税·未税）/ 发生日期区间。
           发生日期＝货到那天，跟「按月未付」表同一个口径，两处数才对得上。 -->
      <template v-if="activeTab === 'ledger'">
        <SelectCard
          v-model="statusFilter"
          :options="STATUS_OPTIONS"
          @update:model-value="loadLedgers"
        />
        <SelectCard
          v-model="settleFilter"
          :options="SETTLE_OPTIONS"
          @update:model-value="loadLedgers"
        />
      </template>
      <!-- 日期区间：两个「一行一张单」的页签都要（台账＝发生日期、付款记录＝付款日）。
           对账/按月未付/账龄是汇总报表，各有自己的截止口径，不在这儿。 -->
      <template v-if="isDocTab">
        <DatePicker
          v-model="fromDate"
          :placeholder="`${DATE_LABEL[activeTab]}起`"
          trigger-class="w-36"
          @change="reload"
        />
        <span class="text-sm text-n-slate-10">至</span>
        <DatePicker
          v-model="toDate"
          :placeholder="`${DATE_LABEL[activeTab]}止`"
          trigger-class="w-36"
          @change="reload"
        />
      </template>
    </div>

    <HScrollButtons />
    <div
      class="flex-1 min-h-0 px-6 pb-6 overflow-auto [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8"
    >
      <div v-if="loading" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>

      <!-- 应付台账 -->
      <!-- 列序可拖、用不到的列可收起（同应收台账与 MES 那几张表），按人记在本机。 -->
      <table
        v-else-if="activeTab === 'ledger'"
        class="w-full text-sm min-w-max"
      >
        <thead>
          <tr class="text-left border-b text-n-slate-11 border-n-weak">
            <th
              v-for="col in ledgerVisibleCols"
              :key="col.key"
              draggable="true"
              class="relative px-3 py-3 font-medium transition-colors cursor-move select-none whitespace-nowrap"
              :class="[
                col.right ? 'text-right' : '',
                isLedgerColDragging(col.key) ? 'opacity-40' : '',
              ]"
              :style="ledgerColStyle(col.key)"
              title="拖动可调整列顺序"
              @dragstart="onLedgerColDragStart(col.key)"
              @dragover.prevent
              @drop="onLedgerColDrop(col.key)"
            >
              <span
                class="inline-flex items-center gap-1"
                :class="col.right ? 'flex-row-reverse' : ''"
              >
                {{ col.label }}
                <TableHeaderFilter
                  v-if="col.filter"
                  v-model="colFilters[col.key]"
                  :kind="col.filter"
                  :options="FILTER_OPTION_SETS[col.filterOptions] || []"
                  @change="onColFilterChange"
                />
              </span>
              <ColResizeHandle
                :column-key="col.key"
                :active="isLedgerColResizing(col.key)"
                @resize-start="(e, th) => startLedgerColResize(col.key, e, th)"
                @auto-fit="autoFitLedgerCol"
              />
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="{ row, item, li, span } in ledgerRows"
            :key="`${row.id}-${li}`"
            class="border-b border-n-weak hover:bg-n-alpha-1"
          >
            <!-- 台账级的列只在第一行出一次、跨完整笔；明细级一行料一行。
                 v-if 不能和 v-for 同元素，所以外面套一层 template。 -->
            <template v-for="col in ledgerVisibleCols" :key="col.key">
              <td
                v-if="!col.rowspan || li === 0"
                :rowspan="col.rowspan ? span : null"
                class="px-3 py-2 whitespace-nowrap text-n-slate-11"
                :class="[
                  col.right ? 'font-mono text-right' : '',
                  col.rowspan ? 'align-top' : '',
                  ledgerColStyle(col.key).width && 'truncate',
                ]"
                :style="ledgerColStyle(col.key)"
              >
                <template v-if="col.key === 'no'">
                  <button
                    type="button"
                    class="font-mono underline reset-base text-n-iris-11 underline-offset-2 hover:opacity-80"
                    title="点开看这笔应付的采购明细、入库和付款"
                    @click="openPayableDetail(row.id)"
                  >
                    {{ row.payable_no }}
                  </button>
                </template>
                <template v-else-if="col.key === 'supplier'">
                  {{ row.supplier_name }}
                  <span v-if="row.po_no" class="text-xs text-n-slate-10">
                    · {{ row.po_no }}
                  </span>
                </template>
                <template v-else-if="col.key === 'settle'">
                  <component
                    :is="canLedger ? 'button' : 'span'"
                    :type="canLedger ? 'button' : null"
                    :title="canLedger ? '点击切换含税／未税' : null"
                    class="px-2 py-0.5 text-xs rounded-full"
                    :class="[
                      row.settle_type === 'PRIVATE'
                        ? 'bg-n-amber-3 text-n-amber-11'
                        : 'bg-n-iris-3 text-n-iris-11',
                      canLedger ? 'hover:opacity-80' : '',
                    ]"
                    @click="canLedger && toggleSettleType(row)"
                  >
                    {{ row.settle_type_label || '含税' }}
                  </component>
                </template>
                <template v-else-if="col.key === 'incurredOn'">
                  {{ row.incurred_on || '—' }}
                </template>
                <template v-else-if="col.key === 'code'">
                  {{ item.code || '—' }}
                </template>
                <template v-else-if="col.key === 'name'">
                  {{ item.name || '—' }}
                </template>
                <template v-else-if="col.key === 'spec'">
                  {{ item.spec || '—' }}
                </template>
                <template v-else-if="col.key === 'qty'">
                  {{ qty(item.quantity) }}{{ item.unit || '' }}
                </template>
                <template v-else-if="col.key === 'price'">
                  {{ money(item.unit_price_micros) }}
                </template>
                <template v-else-if="col.key === 'amount'">
                  {{ money(item.amount_micros) }}
                </template>
                <template v-else-if="col.key === 'total'">
                  {{ row.currency }} {{ money(row.total_amount_micros) }}
                </template>
                <template v-else-if="col.key === 'paid'">
                  {{ money(row.paid_amount_micros) }}
                </template>
                <template v-else-if="col.key === 'outstanding'">
                  {{ money(row.outstanding_micros) }}
                </template>
                <template v-else-if="col.key === 'dueDate'">
                  {{ row.due_date || '—' }}
                </template>
                <template v-else-if="col.key === 'status'">
                  <span
                    class="px-2 py-0.5 text-xs rounded whitespace-nowrap"
                    :class="STATUS_CLASS[row.status]"
                  >
                    {{ row.status_label }}
                  </span>
                </template>
              </td>
            </template>
          </tr>
          <tr v-if="!ledgers.length">
            <td
              :colspan="ledgerVisibleCols.length"
              class="px-3 py-10 text-center text-n-slate-11"
            >
              <template v-if="hasLedgerFilter">
                没有符合筛选条件的应付台账。换个日期区间或结算方式再看看。
              </template>
              <template v-else>
                还没有应付台账。点右上角「从采购单建账」按供应商生成应付。
              </template>
            </td>
          </tr>
        </tbody>
      </table>

      <!-- 付款记录 -->
      <table v-else-if="activeTab === 'payments'" class="w-full text-sm">
        <thead>
          <tr class="text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-3 py-3 font-medium whitespace-nowrap">
              <span class="inline-flex items-center gap-1">
                付款单号
                <TableHeaderFilter
                  v-model="paymentColFilters['no']"
                  kind="text"
                  @change="onPaymentColFilter"
                />
              </span>
            </th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">
              <span class="inline-flex items-center gap-1">
                供应商
                <TableHeaderFilter
                  v-model="paymentColFilters['supplier']"
                  kind="text"
                  @change="onPaymentColFilter"
                />
              </span>
            </th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">付款日</th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              付款金额
            </th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">
              <span class="inline-flex items-center gap-1">
                方式 / 凭据
                <TableHeaderFilter
                  v-model="paymentColFilters['reference']"
                  kind="text"
                  @change="onPaymentColFilter"
                />
              </span>
            </th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">核销</th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">
              <span class="inline-flex items-center gap-1">
                状态
                <TableHeaderFilter
                  v-model="paymentColFilters['status']"
                  kind="enum"
                  :options="FILTER_OPTION_SETS.paymentStatus"
                  @change="onPaymentColFilter"
                />
              </span>
            </th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              操作
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in payments"
            :key="row.id"
            class="border-b border-n-weak hover:bg-n-alpha-1"
          >
            <td class="px-3 py-2 font-mono whitespace-nowrap text-n-slate-12">
              {{ row.payment_no }}
            </td>
            <td class="px-3 py-2 text-n-slate-12">{{ row.supplier_name }}</td>
            <td class="px-3 py-2 whitespace-nowrap text-n-slate-11">
              {{ row.paid_at }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
              {{ row.currency }} {{ money(row.amount_micros) }}
            </td>
            <td class="px-3 py-2 text-xs text-n-slate-11">
              {{ row.method_label }}
              <span v-if="row.reference_no">· {{ row.reference_no }}</span>
            </td>
            <td class="px-3 py-2 text-xs">
              <span
                v-for="allocation in row.allocations"
                :key="allocation.id"
                class="text-n-slate-11"
              >
                {{ allocation.payable_no }}
                {{ money(allocation.amount_micros) }}；
              </span>
              <span v-if="row.unallocated_micros > 0" class="text-n-amber-11">
                待核销 {{ money(row.unallocated_micros) }}
              </span>
            </td>
            <td class="px-3 py-2">
              <span
                class="px-2 py-0.5 text-xs rounded whitespace-nowrap"
                :class="
                  row.status === 'VOID' ? STATUS_TONE.idle : STATUS_TONE.done
                "
              >
                {{ row.status_label }}
              </span>
            </td>
            <td class="px-3 py-2">
              <div class="flex items-center justify-end gap-1">
                <Button
                  label="打印"
                  color="slate"
                  variant="ghost"
                  size="xs"
                  @click="printPayment(row)"
                />
                <template v-if="canSettle && row.status !== 'VOID'">
                  <Button
                    label="编辑"
                    color="slate"
                    variant="ghost"
                    size="xs"
                    @click="openPayment(row)"
                  />
                  <Button
                    label="作废"
                    color="ruby"
                    variant="ghost"
                    size="xs"
                    @click="voidPayment(row)"
                  />
                </template>
              </div>
            </td>
          </tr>
          <tr v-if="!payments.length">
            <td colspan="8" class="px-3 py-10 text-center text-n-slate-11">
              还没有付款记录。点右上角「登记付款」录付款并核销到台账。
            </td>
          </tr>
        </tbody>
      </table>

      <!-- 按月未付：截止某月末还欠哪些供应商、欠的是哪几个月的货，含税/未税分行 -->
      <ErpPayableMonthlyTable
        v-else-if="activeTab === 'monthly'"
        ref="monthlyRef"
        :fetcher="ErpPayableAPI.monthly"
      />

      <!-- 账龄分析 -->
      <ErpAgingTable
        v-else-if="activeTab === 'aging'"
        ref="agingRef"
        title="应付账龄分析表"
        party-label="供应商"
        :fetcher="ErpPayableAPI.aging"
      />

      <!-- 待对账：收了货、还没跟供应商核对过的。核对无误点「对好了，建账」才进台账。 -->
      <table
        v-else-if="activeTab === 'reconcile'"
        class="w-full min-w-[900px] text-sm"
      >
        <thead>
          <tr class="text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-3 py-3 font-medium whitespace-nowrap">收货日期</th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">采购单</th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">供应商</th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              已收货金额
            </th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              台账已建
            </th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              待建金额
            </th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              操作
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in filteredReconRows"
            :key="reconKey(row)"
            class="border-b border-n-weak"
          >
            <td class="px-3 py-2 whitespace-nowrap text-n-slate-12">
              {{ reconDate(row) }}
              <span v-if="row.entry_count > 1" class="ml-1 text-n-slate-10">
                {{ row.entry_count }} 张
              </span>
            </td>
            <td class="px-3 py-2 text-n-slate-12">{{ row.po_no }}</td>
            <td class="px-3 py-2 text-n-slate-12">{{ row.supplier_name }}</td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
              {{ money(row.received_micros) }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-11">
              {{ money(row.booked_micros) }}
            </td>
            <td
              class="px-3 py-2 font-mono text-right"
              :class="reconDiff(row) < 0 ? 'text-n-ruby-11' : 'text-n-amber-11'"
            >
              {{ money(reconDiff(row)) }}
            </td>
            <td class="px-3 py-2 text-right">
              <Button
                v-if="canLedger"
                label="对好了，建账"
                color="amber"
                size="sm"
                :is-loading="confirmingRecon === reconKey(row)"
                @click="confirmRecon(row)"
              />
            </td>
          </tr>
          <tr v-if="!filteredReconRows.length && !reconLoading">
            <td colspan="7" class="px-3 py-10 text-center text-n-slate-11">
              <template v-if="reconMonth">
                {{ reconMonth }} 没有待对账的收货，换个月份看看。
              </template>
              <template v-else>
                没有待对账的收货——收到的货都已经跟供应商核对过并建了账。
              </template>
            </td>
          </tr>
        </tbody>
      </table>

      <!-- 供应商对账 -->
      <table v-else class="w-full max-w-3xl text-sm">
        <thead>
          <tr class="text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-3 py-3 font-medium whitespace-nowrap">
              <span class="inline-flex items-center gap-1">
                供应商
                <TableHeaderFilter v-model="statementSupplierFilter" />
              </span>
            </th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              应付合计
            </th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              已付
            </th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              未付
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in filteredStatementRows"
            :key="row.id"
            class="border-b border-n-weak"
          >
            <td class="px-3 py-2 text-n-slate-12">{{ row.name }}</td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
              {{ money(row.total_micros) }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-11">
              {{ money(row.paid_micros) }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
              {{ money(row.outstanding_micros) }}
            </td>
          </tr>
          <tr v-if="!filteredStatementRows.length">
            <td colspan="4" class="px-3 py-10 text-center text-n-slate-11">
              还没有应付数据。
            </td>
          </tr>
        </tbody>
      </table>
      <PaginationFooter
        v-if="activeTab === 'ledger' && (ledgerMeta.count || 0) > PER_PAGE"
        :current-page="ledgerPage"
        :total-items="ledgerMeta.count"
        :items-per-page="PER_PAGE"
        class="!bg-transparent before:!hidden"
        @update:current-page="ledgerPage = $event"
      />
      <PaginationFooter
        v-if="activeTab === 'payments' && (paymentMeta.count || 0) > PER_PAGE"
        :current-page="paymentPage"
        :total-items="paymentMeta.count"
        :items-per-page="PER_PAGE"
        class="!bg-transparent before:!hidden"
        @update:current-page="paymentPage = $event"
      />
    </div>

    <!-- 建账弹窗 -->
    <ErpPayableDetailDialog ref="detailDialogRef" />

    <Dialog
      ref="buildDialogRef"
      width="2xl"
      confirm-button-color="iris"
      title="从采购单建应付账"
      :disable-confirm-button="!selectedPurchaseOrderId"
      @confirm="submitBuild"
    >
      <div class="flex flex-col gap-1">
        <label class="text-heading-3 text-n-slate-12">
          采购单 <span class="text-n-ruby-11">*</span>
        </label>
        <ComboBox
          v-model="selectedPurchaseOrderId"
          :options="purchaseOrderOptions"
          use-api-results
          placeholder="搜采购单号"
          @search="searchPurchaseOrders"
        />
        <span class="text-xs text-n-slate-10">
          按明细行的供应商分组，每个供应商生成一条应付；行上没有金额时按供应商报价
          × 数量 ×（1+税率）算
        </span>
      </div>
    </Dialog>

    <!-- 付款弹窗 -->
    <Dialog
      ref="paymentDialogRef"
      width="3xl"
      confirm-button-color="iris"
      :title="
        editingPayment ? `编辑付款单 ${editingPayment.payment_no}` : '登记付款'
      "
      :disable-confirm-button="paymentInvalid"
      :dirty="isDirty"
      dirty-save-label="保存"
      @confirm="submitPayment"
      @close="markPristine"
      @save="submitPayment"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-3 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              收款供应商 <span class="text-n-ruby-11">*</span>
            </label>
            <ComboBox
              v-model="paymentForm.mesSupplierId"
              :options="supplierOptions"
              use-api-results
              placeholder="搜供应商"
              @search="searchSuppliers"
              @update:model-value="onSupplierChange"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              付款金额 <span class="text-n-ruby-11">*</span>
            </label>
            <Input
              v-model="paymentForm.amount"
              size="sm"
              type="number"
              custom-input-class="!h-9"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">付款日期</label>
            <DatePicker v-model="paymentForm.paidAt" :clearable="false" block />
          </div>
        </div>

        <div class="grid grid-cols-4 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">付款方式</label>
            <SelectCard v-model="paymentForm.method" :options="METHODS" block />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">币种 / 汇率</label>
            <div class="flex items-center gap-1">
              <Input
                v-model="paymentForm.currency"
                size="sm"
                custom-input-class="!h-9 w-16"
              />
              <Input
                v-model="paymentForm.exchangeRate"
                size="sm"
                type="number"
                custom-input-class="!h-9"
              />
            </div>
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">银行手续费</label>
            <Input
              v-model="paymentForm.bankCharge"
              size="sm"
              type="number"
              custom-input-class="!h-9"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">付款凭据号</label>
            <Input
              v-model="paymentForm.referenceNo"
              size="sm"
              custom-input-class="!h-9"
            />
          </div>
        </div>

        <ErpAllocationEditor
          v-model="allocationRows"
          :ledgers="allocationLedgers"
          :amount-micros="paymentAmountMicros"
          empty-hint="该供应商没有未付清的应付台账（可先建账，或留作预付挂账）"
        />

        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">备注</label>
          <Input
            v-model="paymentForm.remark"
            size="sm"
            custom-input-class="!h-9"
          />
        </div>
      </div>
    </Dialog>

    <!-- 补出应付凭证：名单摆出来按月挑着补。正常过账的入库单凭证是自动出的，
         这里只会出现「该出没出」的那些（多半是自动规则上线前过的账）。 -->
    <Dialog
      ref="voucherDialogRef"
      width="5xl"
      title="补出应付凭证"
      :show-confirm-button="false"
      cancel-button-label="关闭"
    >
      <div class="flex flex-col gap-3">
        <div class="flex flex-wrap items-center gap-2">
          <span class="text-sm text-n-slate-11">
            这些入库单已过账、但没有应付凭证
          </span>
          <MonthPicker
            v-model="voucherMonth"
            placeholder="过账月份"
            trigger-class="w-32 h-8"
          />
          <span class="flex-1" />
          <Button
            label="导出 Excel"
            color="slate"
            variant="faded"
            size="sm"
            @click="exportPendingVouchers"
          />
        </div>

        <div class="overflow-auto max-h-[52vh]">
          <table class="w-full text-sm min-w-[860px]">
            <thead class="sticky top-0 bg-n-solid-1">
              <tr class="text-left border-b text-n-slate-11 border-n-weak">
                <th class="px-3 py-2 w-9">
                  <input
                    type="checkbox"
                    class="align-middle"
                    :checked="allVouchersChecked"
                    :disabled="!buildableVouchers.length"
                    @change="toggleAllVouchers"
                  />
                </th>
                <th class="px-3 py-2 font-medium whitespace-nowrap">过账日</th>
                <th class="px-3 py-2 font-medium whitespace-nowrap">
                  入库单号
                </th>
                <th class="px-3 py-2 font-medium whitespace-nowrap">采购单</th>
                <th class="px-3 py-2 font-medium min-w-[220px]">供应商</th>
                <th class="px-3 py-2 font-medium text-right whitespace-nowrap">
                  金额
                </th>
                <th class="px-3 py-2 font-medium min-w-[200px]">能不能出</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="row in filteredVouchers"
                :key="row.id"
                class="border-b border-n-weak"
              >
                <td class="px-3 py-2 align-top">
                  <input
                    type="checkbox"
                    class="mt-1 align-middle"
                    :checked="voucherChecked(row.id)"
                    :disabled="Boolean(row.blocker)"
                    @change="toggleVoucher(row.id)"
                  />
                </td>
                <td
                  class="px-3 py-2 align-top whitespace-nowrap text-n-slate-11"
                >
                  {{ row.posted_on }}
                </td>
                <td
                  class="px-3 py-2 align-top whitespace-nowrap text-n-slate-12"
                >
                  {{ row.entry_no }}
                  <span
                    v-if="row.purpose === 'MATERIAL_RETURN'"
                    class="ml-1 text-n-ruby-11"
                  >
                    退货
                  </span>
                </td>
                <td
                  class="px-3 py-2 align-top whitespace-nowrap text-n-slate-11"
                >
                  {{ row.po_no || '—' }}
                </td>
                <!-- 一张入库单可以跨好几家供应商（生产上最多 7 家），名字全排出来是为了
                     凭证摘要能搜到人，但列宽得按住，否则整张表被一行撑到横向滚动。 -->
                <td class="px-3 py-2 align-top break-words text-n-slate-11">
                  {{ row.supplier_names || '—' }}
                </td>
                <td
                  class="px-3 py-2 font-mono text-right align-top text-n-slate-12"
                >
                  {{ money(row.amount_micros) }}
                </td>
                <td class="px-3 py-2 text-xs align-top">
                  <span v-if="!row.blocker" class="text-n-teal-11">能出</span>
                  <span v-else class="text-n-amber-11">{{ row.blocker }}</span>
                </td>
              </tr>
              <tr v-if="!filteredVouchers.length">
                <td colspan="7" class="px-3 py-10 text-center text-n-slate-11">
                  {{ voucherMonth }} 这个月没有要补的入库单。
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="flex flex-wrap items-center gap-3 pt-1">
          <span class="text-sm text-n-slate-11">
            已选 {{ selectedVoucherRows.length }} 张 · 合计
            <b class="font-mono text-n-slate-12">
              {{ money(selectedVoucherTotal) }}
            </b>
          </span>
          <span class="flex-1" />
          <Button
            :label="`补出选中 (${selectedVoucherRows.length})`"
            color="amber"
            size="sm"
            :disabled="!selectedVoucherRows.length"
            :is-loading="buildingVouchers"
            @click="buildPendingVouchers"
          />
        </div>
      </div>
    </Dialog>

    <div class="fixed top-0 -left-[10000px] w-[794px]">
      <div ref="printAreaRef">
        <ErpSettlementPrintSheet
          v-for="sheet in printSheets"
          :key="sheet.id"
          :record="sheet"
          kind="payment"
        />
      </div>
    </div>
  </div>
</template>
