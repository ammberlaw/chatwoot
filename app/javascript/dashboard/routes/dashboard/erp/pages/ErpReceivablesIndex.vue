<script setup>
import { ref, reactive, computed, nextTick, onMounted, watch } from 'vue';
import { STATUS_TONE } from 'dashboard/helper/statusTone';
import { useAlert } from 'dashboard/composables';
import { useErpRole } from 'dashboard/composables/useErpRole';
import { fmtMoney } from 'dashboard/helper/erpMoney';
import { printElement } from 'dashboard/helper/printHelper';

import ErpReceivableAPI from 'dashboard/api/erp/receivables';
import ErpReceiptAPI from 'dashboard/api/erp/receiptRecords';
import CrmSalesOrderAPI from 'dashboard/api/crm/salesOrders';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ErpSalesOrderDetailDialog from 'dashboard/components-next/erp/ErpSalesOrderDetailDialog.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import ErpAllocationEditor from 'dashboard/components-next/erp/ErpAllocationEditor.vue';
import ErpAgingTable from 'dashboard/components-next/erp/ErpAgingTable.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import ErpSettlementPrintSheet from 'dashboard/components-next/erp/ErpSettlementPrintSheet.vue';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
import { productLineLabel } from 'dashboard/composables/useMesProductLine';
import { exportRowsToExcel, fetchAllRows } from 'dashboard/helper/erpExcel';
import { useOrderableColumns } from 'dashboard/composables/useOrderableColumns';
import ColumnPicker from 'dashboard/components-next/ColumnPicker.vue';
// 应收：台账（从销售订单建账 + 分期计划）与收款记录（水单 + 核销）两页签。
// 台账的「已收」只由核销维护，页面不提供直接改的入口——改了账就不准了。
const { erpCan } = useErpRole();
const canLedger = computed(() => erpCan('receivable'));
const canSettle = computed(() => erpCan('payment'));

const TABS = [
  { key: 'ledger', label: '应收台账' },
  { key: 'pending', label: '待建账' },
  { key: 'receipts', label: '收款记录' },
  { key: 'aging', label: '账龄分析' },
];
const STATUS_OPTIONS = [
  { value: '', label: '全部状态' },
  { value: 'UNPAID', label: '未收款' },
  { value: 'PARTIAL', label: '部分收款' },
  { value: 'PAID', label: '已收清' },
];
// 待建账清单里展示的销售订单状态（CRM 口径）。
const SO_STATUS_LABELS = {
  IN_PRODUCTION: '生产中',
  PENDING_SHIPMENT: '待出货',
  SHIPPED: '已出货',
  COMPLETED: '已完结',
};
const METHODS = [
  { value: 'TT', label: '电汇 TT' },
  { value: 'LC', label: '信用证 LC' },
  { value: 'WESTERN_UNION', label: '西联' },
  { value: 'PAYPAL', label: 'PayPal' },
  { value: 'RMB', label: '人民币转账' },
  { value: 'OTHER', label: '其他' },
];
const INSTALLMENT_KINDS = [
  { value: 'DEPOSIT', label: '订金' },
  { value: 'BALANCE', label: '尾款' },
  { value: 'OTHER', label: '其他' },
];
const DUE_BASES = [
  { value: 'FIXED', label: '指定日期' },
  { value: 'ORDER_DATE', label: '下单后N天' },
  { value: 'BEFORE_SHIPMENT', label: '出货前' },
  { value: 'AFTER_SHIPMENT', label: '出货后N天' },
  { value: 'BL_COPY', label: '见提单副本' },
];
const INSTALLMENT_STATUS_CLASS = {
  PENDING: 'text-n-slate-11',
  DUE_SOON: 'text-n-amber-11',
  OVERDUE: 'text-n-ruby-11',
  SETTLED: 'text-n-teal-11',
};
const STATUS_CLASS = {
  UNPAID: STATUS_TONE.busy,
  PARTIAL: STATUS_TONE.flow,
  PAID: STATUS_TONE.done,
};

const money = micros => (micros ? fmtMoney(micros) : '—');
const toMicros = value => Math.round(Number(value || 0) * 1_000_000);
const today = () => new Date().toISOString().slice(0, 10);

const activeTab = ref('ledger');
const loading = ref(false);
const keyword = ref('');
const statusFilter = ref('');
// 单据日期区间（＝列表上「单据日期」那一列：首次出库日，没出货的回落到建账日）。
// 单边留空＝只卡一头。
const fromDate = ref('');
const toDate = ref('');
const hasLedgerFilter = computed(() =>
  Boolean(
    keyword.value.trim() || statusFilter.value || fromDate.value || toDate.value
  )
);

const ledgers = ref([]);

// 金额列按财务旧系统的两位小数走；数量/单价保留四位（单价常有 0.6250 这种）。
const num = value =>
  value === null || value === undefined || value === ''
    ? '—'
    : Number(value).toLocaleString('zh-CN', { maximumFractionDigits: 4 });
const amt = value =>
  value === null ||
  value === undefined ||
  value === '' ||
  Number.isNaN(Number(value))
    ? '—'
    : Number(value).toLocaleString('zh-CN', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      });

// 税率列：0 也是有效税率（外贸出口免税），不能被 || 吞成「—」。
const taxRateLabel = row =>
  row.tax_rate === null || row.tax_rate === undefined
    ? '—'
    : `${row.tax_rate}%`;

// 汇率后端是 decimal，序列化成字符串（"7.15"）。
const toNumber = value =>
  value === null || value === undefined || value === '' ? '' : Number(value);

// 一行明细的税额换算。订单上只存一个价和一个「含不含税」标记，财务那张表要同时摆出
// 含税单价 / 实际不含税金额 / 价税合计 / 价税合计本位币，四个数都是从这一个价推的。
//   · 报含税价（内销常见）：填的价就是含税价，不含税金额 = 金额 ÷ (1+税率)；
//   · 报不含税价（外贸常见）：填的价是净价，价税合计 = 金额 × (1+税率)。
// 本位币 = 价税合计 × 汇率（外币单据折人民币，财务看的是这一列合计）。
const lineTax = (row, item) => {
  const has = value => value !== null && value !== undefined && value !== '';
  const factor = 1 + Number(row.tax_rate || 0) / 100;
  // 后端已把「订单没填就跟随账套默认」解析完，这里只认解析后的结果。
  const inclusive = row.amount_includes_tax !== false;
  const toGross = inclusive ? 1 : factor;
  const toNet = inclusive ? 1 / factor : 1;
  const price = has(item.unit_price) ? Number(item.unit_price) : null;
  const amount = has(item.amount) ? Number(item.amount) : null;
  const grossAmount = amount === null ? null : amount * toGross;
  return {
    grossPrice: price === null ? null : price * toGross,
    netAmount: amount === null ? null : amount * toNet,
    grossAmount,
    baseAmount:
      grossAmount === null
        ? null
        : grossAmount * Number(row.exchange_rate || 1),
  };
};

// 一笔台账摊成几行货：台账级单元格用 rowspan 跨完整笔，明细列一行一项。
// 在这里摊平而不是模板里套一层 <template v-for>，省得整块表格缩进全挪。
const ledgerRows = computed(() =>
  ledgers.value.flatMap(row => {
    // 没有明细的老单也要占一行，否则整笔台账不显示。
    const items = row.line_items?.length ? row.line_items : [{}];
    return items.map((item, li) => ({
      row,
      item,
      li,
      span: items.length,
      tax: lineTax(row, item),
    }));
  })
);
// 台账表的列。rowspan=true 的是「台账级」字段（一笔应收跨完整几行货），
// 其余是「明细级」（一行货一行）。列序可拖、可收起，按人记在本机——
// 财务各人核的东西不一样，35 列全摆着谁都嫌长。
const LEDGER_COLUMN_DEFS = [
  { key: 'no', label: '台账单号', rowspan: true },
  { key: 'docDate', label: '单据日期', rowspan: true },
  { key: 'docNo', label: '单据编号', rowspan: true },
  { key: 'insuranceNo', label: '信保订单号', rowspan: true },
  { key: 'orderNo', label: '订单单号', rowspan: true },
  { key: 'piNo', label: 'PI 号', rowspan: true },
  { key: 'customerCode', label: '客户编码', rowspan: true },
  { key: 'customer', label: '客户', rowspan: true },
  { key: 'owner', label: '业务员', rowspan: true },
  { key: 'department', label: '部门', rowspan: true },
  { key: 'warehouse', label: '仓库', rowspan: true },
  { key: 'sku', label: '商品编码' },
  { key: 'name', label: '商品名称' },
  { key: 'spec', label: '规格型号' },
  { key: 'currency', label: '币别', rowspan: true },
  { key: 'rate', label: '汇率', rowspan: true, right: true },
  { key: 'freight', label: '客户承担运费', rowspan: true, right: true },
  { key: 'unit', label: '单位' },
  { key: 'qty', label: '数量', right: true },
  { key: 'price', label: '单价', right: true },
  { key: 'taxRate', label: '增值税', rowspan: true, right: true },
  { key: 'grossPrice', label: '含税单价', right: true },
  { key: 'netAmount', label: '实际不含税金额', right: true },
  { key: 'grossAmount', label: '价税合计', right: true },
  { key: 'baseAmount', label: '价税合计本位币', right: true },
  { key: 'productLine', label: '事业部' },
  { key: 'unitCost', label: '单位成本', right: true },
  { key: 'orderDate', label: '下单 / 交期', rowspan: true },
  { key: 'orderStatus', label: '订单状态', rowspan: true },
  { key: 'voucher', label: '收入凭证', rowspan: true },
  { key: 'total', label: '应收', rowspan: true, right: true },
  { key: 'received', label: '已收', rowspan: true, right: true },
  { key: 'outstanding', label: '未收', rowspan: true, right: true },
  { key: 'installments', label: '分期计划', rowspan: true },
  { key: 'status', label: '状态', rowspan: true },
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
} = useOrderableColumns(LEDGER_COLUMN_DEFS, 'erp.arLedgerCols.v1');
const hiddenLedgerCols = computed(
  () => LEDGER_COLUMN_DEFS.length - ledgerVisibleCols.value.length
);
const ledgerMeta = ref({});
const receipts = ref([]);
const receiptMeta = ref({});

// 分页：meta.count 是全量数，超过一页必须给翻页入口——迁移进来的客户量早超一页，静默截断=「数据消失」。
const PER_PAGE = 50;
const ledgerPage = ref(1);
const receiptPage = ref(1);
const pendingPage = ref(1);

const loadLedgers = async () => {
  loading.value = true;
  try {
    const { data } = await ErpReceivableAPI.get({
      q: keyword.value.trim(),
      status: statusFilter.value,
      from: fromDate.value,
      to: toDate.value,
      page: ledgerPage.value,
      per_page: PER_PAGE,
    });
    ledgers.value = data.payload;
    ledgerMeta.value = data.meta;
  } finally {
    loading.value = false;
  }
};

const loadReceipts = async () => {
  loading.value = true;
  try {
    const { data } = await ErpReceiptAPI.get({
      q: keyword.value.trim(),
      page: receiptPage.value,
      per_page: PER_PAGE,
    });
    receipts.value = data.payload;
    receiptMeta.value = data.meta;
  } finally {
    loading.value = false;
  }
};

watch([keyword, statusFilter, fromDate, toDate], () => {
  ledgerPage.value = 1;
  receiptPage.value = 1;
  pendingPage.value = 1;
});
watch(ledgerPage, loadLedgers);
watch(receiptPage, loadReceipts);

/* ---------------- 销售订单详情：出了什么货、单价、挂了哪些 MES 单据 ---------------- */
// 待建账/台账只有抬头（单号客户金额），财务对不上「这单到底发了什么、什么价」。
// 走 ERP 侧接口：财务多半没有 crm_role，CRM 那套接口会 403。
const orderDialogRef = ref(null);
const openOrderDetail = orderId => orderDialogRef.value?.open(orderId);

/* ---------------- 待建账：已确认但还没建应收的订单 ---------------- */
// 漏建账 = 应收报表少一笔且没有任何提示，这个页签就是那个提示。
// 不做自动建账：金额/币种/分期是财务确认动作，系统替财务建错了没人发现。
const pendingOrders = ref([]);
const pendingCount = ref(0);
const selectedOrderIds = ref([]);
const buildingBatch = ref(false);
// 会计启用日：日切之前的单（上线时一次性迁进来的历史单）不列在这里。
// 没设的时候要明说，否则财务看着满屏历史单会照着批量建，建出一堆假应收。
const fiscalStartDate = ref('');
const beforeFiscalCount = ref(0);

// silent：进页面时只为点亮角标而拉，不能抢台账表格的 loading 态（两个请求会互相踩）。
// 分页与台账同样 50 条/页：原先后端 limit(200)、前端不翻页，超出的单在界面上消失，
// 而角标走的是全量 count，于是「角标 318、列表 200」对不上。
const loadPendingOrders = async ({ silent = false } = {}) => {
  if (!silent) loading.value = true;
  try {
    const { data } = await ErpReceivableAPI.pendingOrders({
      page: pendingPage.value,
      per_page: PER_PAGE,
    });
    pendingOrders.value = data.payload;
    pendingCount.value = data.meta?.pending_count || 0;
    fiscalStartDate.value = data.meta?.fiscal_start_date || '';
    beforeFiscalCount.value = data.meta?.before_fiscal_count || 0;
    selectedOrderIds.value = [];
  } finally {
    if (!silent) loading.value = false;
  }
};
watch(pendingPage, () => loadPendingOrders());

const allPendingSelected = computed(
  () =>
    pendingOrders.value.length > 0 &&
    selectedOrderIds.value.length === pendingOrders.value.length
);
const toggleSelectAll = () => {
  selectedOrderIds.value = allPendingSelected.value
    ? []
    : pendingOrders.value.map(order => order.id);
};
const toggleOrder = id => {
  const index = selectedOrderIds.value.indexOf(id);
  if (index === -1) selectedOrderIds.value.push(id);
  else selectedOrderIds.value.splice(index, 1);
};

// 批量只按默认口径建（整单一期尾款）；要分期的走「从销售订单建账」单张建。
const bulkBuild = async () => {
  buildingBatch.value = true;
  try {
    const { data } = await ErpReceivableAPI.bulkBuild(selectedOrderIds.value);
    const {
      built_count: built = 0,
      failed = [],
      voucher_warnings: vw = [],
    } = data.payload || {};
    const failedNote = failed.length
      ? `，${failed.length} 张失败（${failed[0].order_no}：${failed[0].error}）`
      : '';
    useAlert(`已建账 ${built} 张${failedNote}`);
    // 凭证没出来要单独说——建账成功的提示会把它盖过去，财务就以为账已经入了。
    if (vw.length) useAlert(`${vw.length} 张没出收入凭证：${vw[0]}`);
    await loadPendingOrders();
  } catch (error) {
    useAlert(error?.response?.data?.error || '批量建账失败');
  } finally {
    buildingBatch.value = false;
  }
};

const agingRef = ref(null);
// 账龄分析有自己的查询条（口径 + 截至日），待建账是订单清单，两者都隐掉顶部关键字搜索。
const isDocTab = computed(() =>
  ['ledger', 'receipts'].includes(activeTab.value)
);
const reload = () => {
  if (activeTab.value === 'ledger') return loadLedgers();
  if (activeTab.value === 'pending') return loadPendingOrders();
  if (activeTab.value === 'receipts') return loadReceipts();
  return agingRef.value?.load();
};
const switchTab = key => {
  activeTab.value = key;
  nextTick(reload);
};

/* ---------------- 建账（从销售订单） ---------------- */
const ledgerDialogRef = ref(null);
const orderOptions = ref([]);
const ledgerForm = reactive({
  crmSalesOrderId: '',
  installments: [],
});
const { isDirty, markPristine } = useDirtyGuard(() => ledgerForm);
const searchOrders = async q => {
  const { data } = await CrmSalesOrderAPI.get({ q, page: 1 });
  orderOptions.value = (data?.payload || []).map(o => ({
    value: o.id,
    label: `${o.order_no} ${o.name || ''}`.trim(),
  }));
};
const openBuild = () => {
  Object.assign(ledgerForm, { crmSalesOrderId: '', installments: [] });
  searchOrders('');
  markPristine();
  ledgerDialogRef.value?.open();
};
// 单张建账：从待建账某一行直接带进弹窗。批量只能按默认口径（整单一期尾款），
// 要分期、要先核一眼明细的，走这个入口。
const openBuildForOrder = order => {
  Object.assign(ledgerForm, { crmSalesOrderId: order.id, installments: [] });
  // ComboBox 走 use-api-results，不预置这一条就只有空值显示不出单号。
  orderOptions.value = [
    { value: order.id, label: `${order.order_no} ${order.name || ''}`.trim() },
  ];
  markPristine();
  ledgerDialogRef.value?.open();
};
const addInstallment = () =>
  ledgerForm.installments.push({
    kind: 'BALANCE',
    amount: '',
    dueBasis: 'FIXED',
    dueDays: '',
    dueDate: '',
  });
const removeInstallment = index => ledgerForm.installments.splice(index, 1);

const submitBuild = async () => {
  if (!ledgerForm.crmSalesOrderId) return;
  try {
    const { data } = await ErpReceivableAPI.create({
      crm_sales_order_id: ledgerForm.crmSalesOrderId,
      installments: ledgerForm.installments
        .filter(row => row.amount)
        .map(row => ({
          kind: row.kind,
          amount_micros: toMicros(row.amount),
          due_basis: row.dueBasis,
          due_days: row.dueDays || null,
          due_date: row.dueDate || null,
        })),
    });
    useAlert(`已建账 ${data.receivable_no}`);
    if (data.voucher_warning) useAlert(data.voucher_warning);
    ledgerDialogRef.value?.close();
    loadLedgers();
    loadPendingOrders({ silent: true }); // 建完这单待建账角标要跟着掉
  } catch (error) {
    useAlert(error?.response?.data?.error || '建账失败');
  }
};

// 补出收入凭证：建账时该出没出的（规则上线前建的老账、或当时订单还没发货）。
// 出不了的原因由后端判定后原样带回，不在前端重判一遍。
const buildingVoucherId = ref(null);
const buildRevenueVoucher = async row => {
  buildingVoucherId.value = row.id;
  try {
    const { data } = await ErpReceivableAPI.buildRevenueVoucher(row.id);
    row.revenue_voucher_no = data.revenue_voucher_no;
    useAlert(`已生成收入凭证 ${data.revenue_voucher_no}`);
  } catch (error) {
    useAlert(error?.response?.data?.error || '补出凭证失败');
  } finally {
    buildingVoucherId.value = null;
  }
};

/* ---------------- 收款单 ---------------- */
const receiptDialogRef = ref(null);
const editingReceipt = ref(null);
const openReceivables = ref([]);
const allocationRows = ref([]);
const receiptForm = reactive({
  crmCustomerId: '',
  amount: '',
  currency: 'CNY',
  exchangeRate: 1,
  bankCharge: '',
  method: 'TT',
  receivedAt: today(),
  referenceNo: '',
  remark: '',
});
const { isDirty: isReceiptDirty, markPristine: markReceiptPristine } =
  useDirtyGuard(() => receiptForm);
const customerOptions = computed(() =>
  ledgers.value
    .map(l => ({ value: l.crm_customer_id, label: l.customer_name }))
    .filter(
      (option, index, list) =>
        list.findIndex(item => item.value === option.value) === index
    )
);
const allocationLedgers = computed(() =>
  openReceivables.value.map(r => ({
    id: r.id,
    no: r.receivable_no,
    label: `${r.order_no || r.customer_name} · 应收 ${fmtMoney(r.total_amount_micros)}`,
    outstanding_micros: r.outstanding_micros,
  }))
);
// 可核销上限是毛额（到账净额＋手续费），与后端 AllocationService 口径一致
const receiptAmountMicros = computed(
  () => toMicros(receiptForm.amount) + toMicros(receiptForm.bankCharge)
);

const loadOpenReceivables = async customerId => {
  if (!customerId) {
    openReceivables.value = [];
    return;
  }
  const { data } = await ErpReceivableAPI.openList({
    crm_customer_id: customerId,
  });
  openReceivables.value = data.payload;
};

const openReceipt = async (record = null) => {
  editingReceipt.value = record;
  allocationRows.value = record
    ? record.allocations.map(a => ({
        ledgerId: a.receivable_id,
        amount: (a.amount_micros / 1_000_000).toFixed(2),
      }))
    : [];
  Object.assign(receiptForm, {
    crmCustomerId: record?.crm_customer_id || '',
    amount: record ? (record.amount_micros / 1_000_000).toFixed(2) : '',
    currency: record?.currency || 'CNY',
    exchangeRate: record ? Number(record.exchange_rate) : 1,
    bankCharge: record?.bank_charge_micros
      ? (record.bank_charge_micros / 1_000_000).toFixed(2)
      : '',
    method: record?.method || 'TT',
    receivedAt: record?.received_at || today(),
    referenceNo: record?.reference_no || '',
    remark: record?.remark || '',
  });
  if (!ledgers.value.length) await loadLedgers();
  await loadOpenReceivables(receiptForm.crmCustomerId);
  markReceiptPristine();
  receiptDialogRef.value?.open();
};

const onCustomerChange = () => {
  allocationRows.value = [];
  loadOpenReceivables(receiptForm.crmCustomerId);
};

const receiptInvalid = computed(
  () =>
    !receiptForm.crmCustomerId || !receiptForm.amount || !receiptForm.receivedAt
);

const submitReceipt = async () => {
  if (receiptInvalid.value) return;
  const payload = {
    receipt: {
      crm_customer_id: receiptForm.crmCustomerId,
      amount_micros: receiptAmountMicros.value,
      currency: receiptForm.currency,
      exchange_rate: receiptForm.exchangeRate,
      bank_charge_micros: toMicros(receiptForm.bankCharge),
      method: receiptForm.method,
      received_at: receiptForm.receivedAt,
      reference_no: receiptForm.referenceNo,
      remark: receiptForm.remark,
    },
    allocations: allocationRows.value
      .filter(row => row.amount)
      .map(row => ({
        receivable_id: row.ledgerId,
        amount_micros: toMicros(row.amount),
      })),
  };
  try {
    const { data } = editingReceipt.value
      ? await ErpReceiptAPI.updateWithAllocations(
          editingReceipt.value.id,
          payload
        )
      : await ErpReceiptAPI.createWithAllocations(payload);
    useAlert(`收款单 ${data.receipt_no} 已保存`);
    receiptDialogRef.value?.close();
    loadReceipts();
    if (ledgers.value.length) loadLedgers();
  } catch (error) {
    useAlert(error?.response?.data?.error || '保存失败');
  }
};

const voidReceipt = async record => {
  try {
    await ErpReceiptAPI.void(record.id);
    useAlert(`${record.receipt_no} 已作废，核销与台账余额已回滚`);
    loadReceipts();
    if (ledgers.value.length) loadLedgers();
  } catch (error) {
    useAlert(error?.response?.data?.error || '作废失败');
  }
};

/* ---------------- 打印 ---------------- */
const printAreaRef = ref(null);
const printSheets = ref([]);
const printReceipt = async record => {
  printSheets.value = [record];
  await nextTick();
  printElement(printAreaRef.value, `收款单 ${record.receipt_no}`);
};

// 台账先出，待建账数量同时拉一次——角标要在进页面就亮，不能等点进去才发现漏账。
/* ---------------- 导出 Excel ---------------- */
// 导当前筛选下的应收台账，列与屏幕上这张表一一对应。
// ⚠️ 全量：列表一页 50 条，这里重新向后端分页要完（ERP 后端 per_page 夹在 100）。
const exporting = ref(false);
const stamp = () => new Date().toLocaleString('sv').slice(0, 16);

// 导明细行：一笔应收几行货就几行。Excel 里没有 rowspan，台账级字段每行重复写，
// 否则筛选/透视用不了——财务拿这张表就是去做透视的。
const ledgerExportRows = rows =>
  rows.flatMap(row => {
    const items = row.line_items?.length ? row.line_items : [{}];
    return items.map(item => {
      const tax = lineTax(row, item);
      return {
        receivable_no: row.receivable_no,
        shipped_on: row.shipped_on,
        shipment_no: row.shipment_no,
        insurance_order_no: row.insurance_order_no,
        order_no: row.order_no,
        pi_no: row.pi_no,
        customer_code: row.customer_code,
        customer_name: row.customer_name,
        owner_name: row.owner_name,
        owner_department: row.owner_department,
        warehouse_name: row.warehouse_name,
        sku: item.sku,
        name: item.name,
        spec: item.spec,
        currency: row.currency,
        exchange_rate: toNumber(row.exchange_rate),
        shipping_micros: row.shipping_micros,
        unit: item.unit,
        quantity: item.quantity,
        unit_price: item.unit_price,
        tax_rate: row.tax_rate,
        gross_price: tax.grossPrice,
        net_amount: tax.netAmount,
        gross_amount: tax.grossAmount,
        base_amount: tax.baseAmount,
        product_line: productLineLabel(item.product_line),
        order_date: (row.order_date || '').slice(0, 10),
        delivery_date: (row.delivery_date || '').slice(0, 10),
        order_status: SO_STATUS_LABELS[row.order_status] || row.order_status,
        revenue_voucher_no: row.revenue_voucher_no,
        total_amount_micros: row.total_amount_micros,
        received_amount_micros: row.received_amount_micros,
        outstanding_micros: row.outstanding_micros,
        status_label: row.status_label,
      };
    });
  });

const LEDGER_COLUMNS = [
  { label: '台账单号', key: 'receivable_no' },
  { label: '单据日期', key: 'shipped_on' },
  { label: '单据编号', key: 'shipment_no' },
  { label: '信保订单号', key: 'insurance_order_no' },
  { label: '订单单号', key: 'order_no' },
  { label: 'PI 号', key: 'pi_no' },
  { label: '客户编码', key: 'customer_code' },
  { label: '客户', key: 'customer_name' },
  { label: '业务员', key: 'owner_name' },
  { label: '部门', key: 'owner_department' },
  { label: '仓库', key: 'warehouse_name' },
  { label: '商品编码', key: 'sku' },
  { label: '商品名称', key: 'name' },
  { label: '规格型号', key: 'spec' },
  { label: '币别', key: 'currency' },
  { label: '汇率', key: 'exchange_rate', num: true },
  { label: '客户承担运费', key: 'shipping_micros', money: true },
  { label: '单位', key: 'unit' },
  { label: '数量', key: 'quantity', num: true },
  { label: '单价', key: 'unit_price', num: true },
  { label: '增值税(%)', key: 'tax_rate', num: true },
  { label: '含税单价', key: 'gross_price', num: true },
  { label: '实际不含税金额', key: 'net_amount' },
  { label: '价税合计', key: 'gross_amount' },
  { label: '价税合计本位币', key: 'base_amount' },
  { label: '事业部', key: 'product_line' },
  { label: '单位成本', key: 'unit_cost' },
  { label: '下单日期', key: 'order_date' },
  { label: '交期', key: 'delivery_date' },
  { label: '订单状态', key: 'order_status' },
  { label: '收入凭证', key: 'revenue_voucher_no' },
  { label: '应收', key: 'total_amount_micros', money: true },
  { label: '已收', key: 'received_amount_micros', money: true },
  { label: '未收', key: 'outstanding_micros', money: true },
  { label: '状态', key: 'status_label' },
];

const exportLedger = async () => {
  exporting.value = true;
  try {
    const raw = await fetchAllRows(params => ErpReceivableAPI.get(params), {
      q: keyword.value.trim(),
      status: statusFilter.value,
      from: fromDate.value,
      to: toDate.value,
    });
    const rows = ledgerExportRows(raw);
    exportRowsToExcel(
      {
        title: '应收账款台账',
        meta: [
          { label: '导出时间', value: stamp() },
          { label: '关键字', value: keyword.value.trim() || '（无）' },
          {
            label: '单据日期',
            value: `${fromDate.value || '不限'} ~ ${toDate.value || '不限'}`,
          },
          { label: '台账笔数', value: raw.length },
          { label: '明细行数', value: rows.length },
        ],
        columns: LEDGER_COLUMNS,
        rows,
      },
      `应收账款台账_${stamp().slice(0, 10)}`
    );
  } catch (error) {
    useAlert('导出失败，请重试');
  } finally {
    exporting.value = false;
  }
};

onMounted(() => {
  loadLedgers();
  loadPendingOrders({ silent: true });
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div
      class="flex items-center justify-between gap-3 px-6 py-4 [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8"
    >
      <div class="flex items-center gap-2">
        <div class="i-lucide-hand-coins size-5 text-n-iris-9" />
        <h1
          class="text-xl font-semibold text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8"
        >
          应收管理
        </h1>
        <span v-if="activeTab === 'ledger'" class="text-sm text-n-slate-11">
          应收 {{ money(ledgerMeta.total_micros) }} · 已收
          {{ money(ledgerMeta.received_micros) }} · 未收
          <span class="text-n-slate-12">{{
            money(ledgerMeta.outstanding_micros)
          }}</span>
        </span>
        <span
          v-else-if="activeTab === 'receipts'"
          class="text-sm text-n-slate-11"
        >
          本页收款合计 {{ money(receiptMeta.amount_micros) }}
        </span>
      </div>
      <div class="flex items-center gap-2">
        <Input
          v-if="isDocTab"
          v-model="keyword"
          size="sm"
          placeholder="搜单号 / 客户"
          custom-input-class="w-44"
          @keyup.enter="reload"
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
          v-if="activeTab === 'ledger'"
          label="导出 Excel"
          color="slate"
          variant="faded"
          size="sm"
          :is-loading="exporting"
          @click="exportLedger"
        />
        <Button
          v-if="isDocTab"
          label="查询"
          color="slate"
          size="sm"
          @click="reload"
        />
        <Button
          v-if="canLedger && activeTab === 'ledger'"
          label="从销售订单建账"
          color="iris"
          size="sm"
          @click="openBuild"
        />
        <Button
          v-if="canLedger && activeTab === 'pending'"
          :label="`批量建账${selectedOrderIds.length ? ` (${selectedOrderIds.length})` : ''}`"
          color="iris"
          size="sm"
          :disabled="!selectedOrderIds.length"
          :is-loading="buildingBatch"
          @click="bulkBuild"
        />
        <Button
          v-if="canSettle && activeTab === 'receipts'"
          label="登记收款"
          color="iris"
          size="sm"
          @click="openReceipt()"
        />
      </div>
    </div>

    <div
      class="flex items-center gap-2 px-6 pb-3 [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8"
    >
      <div
        class="flex items-center gap-2 [.theme-classic_&]:!my-0 [.theme-classic_&]:shrink-0"
        data-tabbar="page"
      >
        <button
          v-for="tab in TABS"
          :key="tab.key"
          :aria-selected="activeTab === tab.key"
          class="h-9 px-3 text-sm transition-colors rounded-lg [.theme-classic_&]:!h-8 [.theme-classic_&]:!py-0"
          :class="
            activeTab === tab.key
              ? 'bg-n-iris-9 text-white'
              : 'text-n-slate-11 hover:bg-n-alpha-2'
          "
          @click="switchTab(tab.key)"
        >
          {{ tab.label }}
          <span
            v-if="tab.key === 'pending' && pendingCount"
            class="ml-1.5 inline-flex items-center justify-center min-w-5 h-5 px-1.5 text-xs rounded-full"
            :class="
              activeTab === tab.key
                ? 'bg-white/25 text-white'
                : 'bg-n-ruby-9 text-white'
            "
          >
            {{ pendingCount }}
          </span>
        </button>
      </div>
      <template v-if="activeTab === 'ledger'">
        <SelectCard
          v-model="statusFilter"
          :options="STATUS_OPTIONS"
          trigger-class="[.theme-classic_&]:!h-[38px]"
          @update:model-value="loadLedgers"
        />
        <DatePicker
          v-model="fromDate"
          placeholder="单据日期起"
          trigger-class="w-36"
          @change="loadLedgers"
        />
        <span class="text-sm text-n-slate-10">至</span>
        <DatePicker
          v-model="toDate"
          placeholder="单据日期止"
          trigger-class="w-36"
          @change="loadLedgers"
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

      <!-- 应收台账 -->
      <!-- 表头对标财务旧系统（金蝶）的「销售出库明细」，右侧接台账自己的收款列。
           列序可拖、用不到的列可收起（同 MES 的几张表），按人记在本机——
           35 列全摆着谁都嫌长，各人核的东西还不一样。 -->
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
              class="px-3 py-3 font-medium transition-colors cursor-move select-none whitespace-nowrap"
              :class="[
                col.right ? 'text-right' : '',
                isLedgerColDragging(col.key) ? 'opacity-40' : '',
              ]"
              title="拖动可调整列顺序"
              @dragstart="onLedgerColDragStart(col.key)"
              @dragover.prevent
              @drop="onLedgerColDrop(col.key)"
            >
              {{ col.label }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="{ row, item, li, span, tax } in ledgerRows"
            :key="`${row.id}-${li}`"
            class="border-b border-n-weak hover:bg-n-alpha-1"
          >
            <!-- 台账级的列（col.rowspan）只在第一行出一次、跨完整笔；明细级一行货一行。
                 v-if 不能和 v-for 同元素，所以外面套一层 template。 -->
            <template v-for="col in ledgerVisibleCols" :key="col.key">
              <td
                v-if="!col.rowspan || li === 0"
                :rowspan="col.rowspan ? span : null"
                class="px-3 py-2 whitespace-nowrap text-n-slate-11"
                :class="[
                  col.right ? 'font-mono text-right' : '',
                  col.rowspan ? 'align-top' : '',
                ]"
              >
                <template v-if="col.key === 'no'">
                  {{ row.receivable_no }}
                </template>
                <template v-else-if="col.key === 'docDate'">
                  {{ row.shipped_on || '—' }}
                </template>
                <template v-else-if="col.key === 'docNo'">
                  {{ row.shipment_no || '—' }}
                </template>
                <template v-else-if="col.key === 'insuranceNo'">
                  {{ row.insurance_order_no || '—' }}
                </template>
                <template v-else-if="col.key === 'orderNo'">
                  <button
                    v-if="row.order_no"
                    type="button"
                    class="text-sm underline reset-base text-n-iris-11 underline-offset-2 hover:text-n-iris-12"
                    @click="openOrderDetail(row.crm_sales_order_id)"
                  >
                    {{ row.order_no }}
                  </button>
                  <span v-else class="text-n-slate-11">—</span>
                </template>
                <template v-else-if="col.key === 'piNo'">
                  {{ row.pi_no || '—' }}
                </template>
                <template v-else-if="col.key === 'customerCode'">
                  {{ row.customer_code || '—' }}
                </template>
                <template v-else-if="col.key === 'customer'">
                  {{ row.customer_name || '—' }}
                </template>
                <template v-else-if="col.key === 'owner'">
                  {{ row.owner_name || '—' }}
                </template>
                <template v-else-if="col.key === 'department'">
                  {{ row.owner_department || '—' }}
                </template>
                <template v-else-if="col.key === 'warehouse'">
                  {{ row.warehouse_name || '—' }}
                </template>
                <template v-else-if="col.key === 'sku'">
                  {{ item.sku || '—' }}
                </template>
                <template v-else-if="col.key === 'name'">
                  {{ item.name || '—' }}
                </template>
                <template v-else-if="col.key === 'spec'">
                  {{ item.spec || '—' }}
                </template>
                <template v-else-if="col.key === 'currency'">
                  {{ row.currency || '—' }}
                </template>
                <template v-else-if="col.key === 'rate'">
                  {{ num(row.exchange_rate) }}
                </template>
                <template v-else-if="col.key === 'freight'">
                  {{ money(row.shipping_micros) }}
                </template>
                <template v-else-if="col.key === 'unit'">
                  {{ item.unit || '—' }}
                </template>
                <template v-else-if="col.key === 'qty'">
                  {{ num(item.quantity) }}
                </template>
                <template v-else-if="col.key === 'price'">
                  {{ num(item.unit_price) }}
                </template>
                <template v-else-if="col.key === 'taxRate'">
                  {{ taxRateLabel(row) }}
                </template>
                <template v-else-if="col.key === 'grossPrice'">
                  {{ num(tax.grossPrice) }}
                </template>
                <template v-else-if="col.key === 'netAmount'">
                  {{ amt(tax.netAmount) }}
                </template>
                <template v-else-if="col.key === 'grossAmount'">
                  {{ amt(tax.grossAmount) }}
                </template>
                <template v-else-if="col.key === 'baseAmount'">
                  {{ amt(tax.baseAmount) }}
                </template>
                <template v-else-if="col.key === 'productLine'">
                  {{ productLineLabel(item.product_line) || '—' }}
                </template>
                <template v-else-if="col.key === 'unitCost'"> — </template>
                <template v-else-if="col.key === 'orderDate'">
                  <template v-if="row.order_date || row.delivery_date">
                    {{ (row.order_date || '').slice(0, 10) || '—' }}
                    <span class="block text-n-slate-10">
                      交 {{ (row.delivery_date || '').slice(0, 10) || '—' }}
                    </span>
                  </template>
                  <span v-else>—</span>
                </template>
                <template v-else-if="col.key === 'orderStatus'">
                  {{
                    SO_STATUS_LABELS[row.order_status] ||
                    row.order_status ||
                    '—'
                  }}
                </template>
                <template v-else-if="col.key === 'voucher'">
                  <span v-if="row.revenue_voucher_no" class="text-n-slate-11">
                    {{ row.revenue_voucher_no }}
                  </span>
                  <span v-else class="flex items-center gap-2">
                    <span class="text-n-ruby-11">未入账</span>
                    <Button
                      v-if="canLedger"
                      variant="link"
                      size="sm"
                      label="补出凭证"
                      :is-loading="buildingVoucherId === row.id"
                      @click="buildRevenueVoucher(row)"
                    />
                  </span>
                </template>
                <template v-else-if="col.key === 'total'">
                  {{ money(row.total_amount_micros) }}
                </template>
                <template v-else-if="col.key === 'received'">
                  {{ money(row.received_amount_micros) }}
                </template>
                <template v-else-if="col.key === 'outstanding'">
                  {{ money(row.outstanding_micros) }}
                </template>
                <template v-else-if="col.key === 'installments'">
                  <div
                    v-for="installment in row.installments"
                    :key="installment.id"
                    :class="INSTALLMENT_STATUS_CLASS[installment.status]"
                  >
                    {{ installment.kind_label }}
                    {{ money(installment.amount_micros) }} ·
                    {{ installment.due_date || installment.due_basis_label }} ·
                    {{ installment.status_label }}
                  </div>
                  <span
                    v-if="!row.installments?.length"
                    class="text-n-slate-10"
                  >
                    —
                  </span>
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
                没有符合筛选条件的应收台账。换个日期区间或状态再看看。
              </template>
              <template v-else>
                还没有应收台账。点右上角「从销售订单建账」把订单转成应收。
              </template>
            </td>
          </tr>
        </tbody>
      </table>

      <!-- 待建账：已确认但还没建应收的销售订单 -->
      <template v-else-if="activeTab === 'pending'">
        <div
          v-if="!fiscalStartDate"
          class="px-3 py-2 mb-3 text-xs border rounded-lg text-n-amber-11 border-n-amber-6 bg-n-amber-2"
        >
          还没设会计启用日，这里列的是**全部**已确认订单，包含上线时迁进来的历史单——
          那些钱早收完了，批量建账会建出一堆假应收。请先到「财务管理 →
          财务设置」设好启用日。
        </div>
        <div v-else class="px-3 mb-3 text-xs text-n-slate-10">
          会计启用日 {{ fiscalStartDate }}，日切之前的
          {{ beforeFiscalCount }} 张历史单不在此列（其余额走期初建账）。
        </div>
        <!-- 12 列了，给表自己一条横向滚动，别让整页横着滚。 -->
        <table class="w-full text-sm min-w-[96rem]">
          <thead>
            <tr class="text-left border-b text-n-slate-11 border-n-weak">
              <th class="w-10 px-3 py-3 whitespace-nowrap">
                <input
                  type="checkbox"
                  class="align-middle reset-base"
                  :checked="allPendingSelected"
                  :disabled="!pendingOrders.length"
                  @change="toggleSelectAll"
                />
              </th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">订单号</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">PI 号</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">
                客户 / 国家
              </th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">型号</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">业务员</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">下单日期</th>
              <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
                订单金额
              </th>
              <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
                建账金额
              </th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">状态</th>
              <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
                操作
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="order in pendingOrders"
              :key="order.id"
              class="border-b border-n-weak hover:bg-n-alpha-1"
            >
              <td class="px-3 py-3">
                <input
                  type="checkbox"
                  class="align-middle reset-base"
                  :checked="selectedOrderIds.includes(order.id)"
                  @change="toggleOrder(order.id)"
                />
              </td>
              <td class="px-3 py-3 whitespace-nowrap">
                <button
                  type="button"
                  class="underline reset-base text-n-iris-11 underline-offset-2 hover:text-n-iris-12"
                  @click="openOrderDetail(order.id)"
                >
                  {{ order.order_no }}
                </button>
              </td>
              <td
                class="px-3 py-3 font-mono text-xs whitespace-nowrap text-n-slate-11"
              >
                {{ order.pi_no || '—' }}
              </td>
              <td class="px-3 py-3 whitespace-nowrap text-n-slate-12">
                {{ order.customer_name || '—' }}
                <span
                  v-if="order.customer_country"
                  class="block text-xs text-n-slate-10"
                >
                  {{ order.customer_country }}
                </span>
              </td>
              <!-- 型号只摆第一项 + 共几项；全部走 title 悬浮，免得一行货把表撑开。 -->
              <td
                class="px-3 py-3 text-n-slate-11 max-w-[14rem] truncate"
                :title="(order.product_names || []).join('\n') || ''"
              >
                {{ order.product_summary || '—' }}
              </td>
              <td class="px-3 py-3 whitespace-nowrap">
                {{ order.owner_name || '—' }}
              </td>
              <td class="px-3 py-3 whitespace-nowrap">
                {{ (order.order_date || '—').slice(0, 10) }}
              </td>
              <!-- 订单金额是净销售、不含运费（运费在订单上单独一栏）。运费挂在同一格里，
                 否则财务看着订单金额对不上建账金额。 -->
              <td
                class="px-3 py-3 text-right whitespace-nowrap text-n-slate-12"
              >
                {{ order.currency || 'CNY' }}
                {{ money(order.amount_micros) }}
                <span
                  v-if="order.shipping_micros"
                  class="block text-xs text-n-slate-10"
                >
                  + 运费 {{ money(order.shipping_micros) }}
                </span>
              </td>
              <!-- 建账金额 = 货款 + 运费 + 销项税（客户实付）。不含税单还要再补一个税，
                 摆出来免得财务以为系统把金额算错了。 -->
              <td
                class="px-3 py-3 text-right whitespace-nowrap text-n-slate-12"
              >
                {{ money(order.receivable_amount_micros) }}
                <span
                  v-if="!order.amount_includes_tax && order.tax_rate"
                  class="block text-xs text-n-slate-10"
                >
                  含 {{ order.tax_rate }}% 销项税
                </span>
              </td>
              <td class="px-3 py-3 whitespace-nowrap text-n-slate-11">
                {{ SO_STATUS_LABELS[order.status] || order.status }}
              </td>
              <td class="px-3 py-3 text-right">
                <Button
                  v-if="canLedger"
                  label="建账"
                  color="slate"
                  variant="faded"
                  size="xs"
                  @click="openBuildForOrder(order)"
                />
              </td>
            </tr>
            <tr v-if="!pendingOrders.length">
              <td colspan="12" class="px-3 py-10 text-center text-n-slate-11">
                没有待建账的订单，已确认的销售订单都建过应收了。
              </td>
            </tr>
          </tbody>
        </table>
      </template>

      <!-- 账龄分析 -->
      <ErpAgingTable
        v-else-if="activeTab === 'aging'"
        ref="agingRef"
        title="应收账龄分析表"
        party-label="客户"
        :fetcher="ErpReceivableAPI.aging"
      />

      <!-- 收款记录 -->
      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-3 py-3 font-medium whitespace-nowrap">收款单号</th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">客户</th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">到账日</th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              到账金额
            </th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">方式 / 水单</th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">核销</th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">状态</th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              操作
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in receipts"
            :key="row.id"
            class="border-b border-n-weak hover:bg-n-alpha-1"
          >
            <td class="px-3 py-2 font-mono whitespace-nowrap text-n-slate-12">
              {{ row.receipt_no }}
            </td>
            <td class="px-3 py-2 text-n-slate-12">{{ row.customer_name }}</td>
            <td class="px-3 py-2 whitespace-nowrap text-n-slate-11">
              {{ row.received_at }}
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
                {{ allocation.receivable_no }}
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
                  @click="printReceipt(row)"
                />
                <template v-if="canSettle && row.status !== 'VOID'">
                  <Button
                    label="编辑"
                    color="slate"
                    variant="ghost"
                    size="xs"
                    @click="openReceipt(row)"
                  />
                  <Button
                    label="作废"
                    color="ruby"
                    variant="ghost"
                    size="xs"
                    @click="voidReceipt(row)"
                  />
                </template>
              </div>
            </td>
          </tr>
          <tr v-if="!receipts.length">
            <td colspan="8" class="px-3 py-10 text-center text-n-slate-11">
              还没有收款记录。点右上角「登记收款」录水单并核销到台账。
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
        v-if="activeTab === 'pending' && pendingCount > PER_PAGE"
        :current-page="pendingPage"
        :total-items="pendingCount"
        :items-per-page="PER_PAGE"
        class="!bg-transparent before:!hidden"
        @update:current-page="pendingPage = $event"
      />
      <PaginationFooter
        v-if="activeTab === 'receipts' && (receiptMeta.count || 0) > PER_PAGE"
        :current-page="receiptPage"
        :total-items="receiptMeta.count"
        :items-per-page="PER_PAGE"
        class="!bg-transparent before:!hidden"
        @update:current-page="receiptPage = $event"
      />
    </div>

    <!-- 建账弹窗 -->
    <Dialog
      ref="ledgerDialogRef"
      width="3xl"
      confirm-button-color="iris"
      title="从销售订单建应收账"
      :disable-confirm-button="!ledgerForm.crmSalesOrderId"
      :dirty="isDirty"
      dirty-save-label="保存"
      @confirm="submitBuild"
      @close="markPristine"
      @save="submitBuild"
    >
      <div class="flex flex-col gap-4">
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">
            销售订单 <span class="text-n-ruby-11">*</span>
          </label>
          <ComboBox
            v-model="ledgerForm.crmSalesOrderId"
            :options="orderOptions"
            use-api-results
            placeholder="搜订单号 / 订单名"
            @search="searchOrders"
          />
          <span class="text-xs text-n-slate-10">
            金额、币种、汇率、归属业务员都从订单带入，建账后可在台账里改
          </span>
        </div>

        <div class="flex flex-col gap-2">
          <div class="flex items-center justify-between">
            <label class="text-heading-3 text-n-slate-12">
              分期计划（不填＝整单一期）
            </label>
            <Button
              label="加一期"
              color="slate"
              variant="faded"
              size="xs"
              @click="addInstallment"
            />
          </div>
          <div
            v-for="(row, index) in ledgerForm.installments"
            :key="index"
            class="grid items-center grid-cols-12 gap-2"
          >
            <div class="col-span-2">
              <SelectCard
                v-model="row.kind"
                :options="INSTALLMENT_KINDS"
                block
              />
            </div>
            <div class="col-span-3">
              <Input
                v-model="row.amount"
                size="sm"
                type="number"
                placeholder="金额"
              />
            </div>
            <div class="col-span-3">
              <SelectCard v-model="row.dueBasis" :options="DUE_BASES" block />
            </div>
            <div class="col-span-2">
              <Input
                v-if="['ORDER_DATE', 'AFTER_SHIPMENT'].includes(row.dueBasis)"
                v-model="row.dueDays"
                size="sm"
                type="number"
                placeholder="N天"
              />
              <DatePicker
                v-else-if="row.dueBasis === 'FIXED'"
                v-model="row.dueDate"
                block
              />
            </div>
            <button
              class="flex items-center justify-center col-span-1 size-8 text-n-slate-11 hover:text-n-ruby-11"
              @click="removeInstallment(index)"
            >
              <div class="i-lucide-trash-2 size-4" />
            </button>
          </div>
        </div>
      </div>
    </Dialog>

    <!-- 收款弹窗 -->
    <Dialog
      ref="receiptDialogRef"
      width="3xl"
      confirm-button-color="iris"
      :title="
        editingReceipt ? `编辑收款单 ${editingReceipt.receipt_no}` : '登记收款'
      "
      :disable-confirm-button="receiptInvalid"
      :dirty="isReceiptDirty"
      dirty-save-label="保存"
      @confirm="submitReceipt"
      @close="markReceiptPristine"
      @save="submitReceipt"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-3 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              付款客户 <span class="text-n-ruby-11">*</span>
            </label>
            <ComboBox
              v-model="receiptForm.crmCustomerId"
              :options="customerOptions"
              placeholder="选客户"
              @update:model-value="onCustomerChange"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              到账金额 <span class="text-n-ruby-11">*</span>
            </label>
            <Input
              v-model="receiptForm.amount"
              size="sm"
              type="number"
              custom-input-class="!h-9"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">到账日期</label>
            <DatePicker
              v-model="receiptForm.receivedAt"
              :clearable="false"
              block
            />
          </div>
        </div>

        <div class="grid grid-cols-4 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">收款方式</label>
            <SelectCard v-model="receiptForm.method" :options="METHODS" block />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">币种 / 汇率</label>
            <div class="flex items-center gap-1">
              <Input
                v-model="receiptForm.currency"
                size="sm"
                custom-input-class="!h-9 w-16"
              />
              <Input
                v-model="receiptForm.exchangeRate"
                size="sm"
                type="number"
                custom-input-class="!h-9"
              />
            </div>
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">银行手续费</label>
            <Input
              v-model="receiptForm.bankCharge"
              size="sm"
              type="number"
              custom-input-class="!h-9"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">水单号</label>
            <Input
              v-model="receiptForm.referenceNo"
              size="sm"
              custom-input-class="!h-9"
            />
          </div>
        </div>

        <ErpAllocationEditor
          v-model="allocationRows"
          :ledgers="allocationLedgers"
          :amount-micros="receiptAmountMicros"
          empty-hint="该客户没有未收清的应收台账（可先建账，或留作预收挂账）"
        />

        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">备注</label>
          <Input
            v-model="receiptForm.remark"
            size="sm"
            custom-input-class="!h-9"
          />
        </div>
      </div>
    </Dialog>

    <!-- 销售订单详情（共享件）：出了什么货、单价多少、挂了哪些 MES 单据；
         里面的生产订单号/出货单号可点，跳到 MES 对应页面定位 -->
    <ErpSalesOrderDetailDialog ref="orderDialogRef" />

    <!-- 打印区：定位在外层，被克隆的是里层（printHelper 的坑，见凭证页注释） -->
    <div class="fixed top-0 -left-[10000px] w-[794px]">
      <div ref="printAreaRef">
        <ErpSettlementPrintSheet
          v-for="sheet in printSheets"
          :key="sheet.id"
          :record="sheet"
          kind="receipt"
        />
      </div>
    </div>
  </div>
</template>
