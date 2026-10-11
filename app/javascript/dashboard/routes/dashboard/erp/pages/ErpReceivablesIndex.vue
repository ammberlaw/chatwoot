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
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import ErpAllocationEditor from 'dashboard/components-next/erp/ErpAllocationEditor.vue';
import ErpAgingTable from 'dashboard/components-next/erp/ErpAgingTable.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import ErpSettlementPrintSheet from 'dashboard/components-next/erp/ErpSettlementPrintSheet.vue';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';

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

const ledgers = ref([]);
const ledgerMeta = ref({});
const receipts = ref([]);
const receiptMeta = ref({});

// 分页：meta.count 是全量数，超过一页必须给翻页入口——迁移进来的客户量早超一页，静默截断=「数据消失」。
const PER_PAGE = 50;
const ledgerPage = ref(1);
const receiptPage = ref(1);

const loadLedgers = async () => {
  loading.value = true;
  try {
    const { data } = await ErpReceivableAPI.get({
      q: keyword.value.trim(),
      status: statusFilter.value,
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

watch([keyword, statusFilter], () => {
  ledgerPage.value = 1;
  receiptPage.value = 1;
});
watch(ledgerPage, loadLedgers);
watch(receiptPage, loadReceipts);

/* ---------------- 销售订单详情：出了什么货、单价、挂了哪些 MES 单据 ---------------- */
// 待建账/台账只有抬头（单号客户金额），财务对不上「这单到底发了什么、什么价」。
// 走 ERP 侧接口：财务多半没有 crm_role，CRM 那套接口会 403。
const orderDialogRef = ref(null);
const orderDetail = ref(null);
const orderLoading = ref(false);

const PO_STATUS_LABELS = {
  DRAFT: '草稿',
  IN_PROGRESS: '进行中',
  COMPLETED: '已完结',
  CANCELLED: '已取消',
};

const openOrderDetail = async orderId => {
  if (!orderId) return;
  orderDetail.value = null;
  orderLoading.value = true;
  orderDialogRef.value?.open();
  try {
    const { data } = await ErpReceivableAPI.orderDetail(orderId);
    orderDetail.value = data.payload;
  } catch {
    useAlert('订单详情取不到，可能已被删除');
    orderDialogRef.value?.close();
  } finally {
    orderLoading.value = false;
  }
};

// 明细里的「数量 × 单价」：运费这类行没有数量和单价、只有金额，照原样显示别补 0。
const num = v => (v === null || v === undefined || v === '' ? '—' : v);
const plainMoney = v =>
  v === null || v === undefined || v === ''
    ? '—'
    : Number(v).toLocaleString('zh-CN', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      });

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
const loadPendingOrders = async ({ silent = false } = {}) => {
  if (!silent) loading.value = true;
  try {
    const { data } = await ErpReceivableAPI.pendingOrders();
    pendingOrders.value = data.payload;
    pendingCount.value = data.meta?.pending_count || 0;
    fiscalStartDate.value = data.meta?.fiscal_start_date || '';
    beforeFiscalCount.value = data.meta?.before_fiscal_count || 0;
    selectedOrderIds.value = [];
  } finally {
    if (!silent) loading.value = false;
  }
};

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
onMounted(() => {
  loadLedgers();
  loadPendingOrders({ silent: true });
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between gap-3 px-6 py-4 [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8">
      <div class="flex items-center gap-2">
        <div class="i-lucide-hand-coins size-5 text-n-iris-9" />
        <h1 class="text-xl font-semibold text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8">应收管理</h1>
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

    <div class="flex items-center gap-2 px-6 pb-3 [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8">
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
      <SelectCard
        v-if="activeTab === 'ledger'"
        v-model="statusFilter"
        :options="STATUS_OPTIONS"
        @update:model-value="loadLedgers"
      />
    </div>

    <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8">
      <div v-if="loading" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>

      <!-- 应收台账 -->
      <!-- 列多了给表自己一条横向滚动，别让整页横着滚。 -->
      <table
        v-else-if="activeTab === 'ledger'"
        class="w-full text-sm min-w-[88rem]"
      >
        <thead>
          <tr class="text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-3 py-3 font-medium whitespace-nowrap">台账单号</th>
            <th class="px-3 py-3 font-medium">客户 / 订单</th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">PI 号</th>
            <th class="px-3 py-3 font-medium">型号</th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">下单 / 交期</th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">订单状态</th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">收入凭证</th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              应收
            </th>
            <th class="px-3 py-3 font-medium text-right">已收</th>
            <th class="px-3 py-3 font-medium text-right">未收</th>
            <th class="px-3 py-3 font-medium">分期计划</th>
            <th class="px-3 py-3 font-medium">状态</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in ledgers"
            :key="row.id"
            class="border-b border-n-weak hover:bg-n-alpha-1"
          >
            <td class="px-3 py-2 font-mono whitespace-nowrap text-n-slate-12">
              {{ row.receivable_no }}
            </td>
            <td class="px-3 py-2 whitespace-nowrap text-n-slate-12">
              {{ row.customer_name }}
              <button
                v-if="row.order_no"
                type="button"
                class="text-xs underline reset-base text-n-iris-11 underline-offset-2 hover:text-n-iris-12"
                @click="openOrderDetail(row.crm_sales_order_id)"
              >
                · {{ row.order_no }}
              </button>
            </td>
            <td
              class="px-3 py-2 font-mono text-xs whitespace-nowrap text-n-slate-11"
            >
              {{ row.pi_no || '—' }}
            </td>
            <!-- 型号只摆第一项 + 共几项；全部走 title 悬浮，免得一行货把整表撑开。 -->
            <td
              class="px-3 py-2 text-n-slate-11 max-w-[14rem] truncate"
              :title="(row.product_names || []).join('\n') || ''"
            >
              {{ row.product_summary || '—' }}
            </td>
            <!-- 两个日期都没有就只出一个「—」，别渲染成「—／交 —」两行占着位置。 -->
            <td class="px-3 py-2 text-xs whitespace-nowrap text-n-slate-11">
              <template v-if="row.order_date || row.delivery_date">
                {{ (row.order_date || '').slice(0, 10) || '—' }}
                <span class="block text-n-slate-10">
                  交 {{ (row.delivery_date || '').slice(0, 10) || '—' }}
                </span>
              </template>
              <span v-else>—</span>
            </td>
            <td class="px-3 py-2 text-xs whitespace-nowrap text-n-slate-11">
              {{
                SO_STATUS_LABELS[row.order_status] || row.order_status || '—'
              }}
            </td>
            <!-- 有没有入总账一眼可见；没有的标红，不用去凭证列表逐条翻。 -->
            <td class="px-3 py-2 font-mono text-xs whitespace-nowrap">
              <span v-if="row.revenue_voucher_no" class="text-n-slate-11">
                {{ row.revenue_voucher_no }}
              </span>
              <span v-else class="text-n-ruby-11">未入账</span>
            </td>
            <td
              class="px-3 py-2 font-mono text-right whitespace-nowrap text-n-slate-12"
            >
              {{ row.currency }} {{ money(row.total_amount_micros) }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-11">
              {{ money(row.received_amount_micros) }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
              {{ money(row.outstanding_micros) }}
            </td>
            <td class="px-3 py-2 text-xs">
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
              <span v-if="!row.installments?.length" class="text-n-slate-10">
                —
              </span>
            </td>
            <td class="px-3 py-2">
              <span
                class="px-2 py-0.5 text-xs rounded whitespace-nowrap"
                :class="STATUS_CLASS[row.status]"
              >
                {{ row.status_label }}
              </span>
            </td>
          </tr>
          <tr v-if="!ledgers.length">
            <td colspan="12" class="px-3 py-10 text-center text-n-slate-11">
              还没有应收台账。点右上角「从销售订单建账」把订单转成应收。
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
              <th class="w-10 px-3 py-3">
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
              <th class="px-3 py-3 font-medium">客户 / 国家</th>
              <th class="px-3 py-3 font-medium">型号</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">业务员</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">下单日期</th>
              <th class="px-3 py-3 font-medium text-right">订单金额</th>
              <th class="px-3 py-3 font-medium text-right">建账金额</th>
              <th class="px-3 py-3 font-medium">状态</th>
              <th class="px-3 py-3 font-medium text-right">操作</th>
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
              <td
                class="px-3 py-3 text-right whitespace-nowrap text-n-slate-12"
              >
                {{ order.currency || 'CNY' }}
                {{ money(order.amount_micros) }}
              </td>
              <!-- 建账金额 = 收入 + 销项税（客户实付）。不含税单比订单金额多一个税，
                 摆出来免得财务以为系统把金额算错了。 -->
              <td
                class="px-3 py-3 text-right whitespace-nowrap text-n-slate-12"
              >
                {{ money(order.receivable_amount_micros) }}
                <span
                  v-if="order.receivable_amount_micros !== order.amount_micros"
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
            <th class="px-3 py-3 font-medium">收款单号</th>
            <th class="px-3 py-3 font-medium">客户</th>
            <th class="px-3 py-3 font-medium">到账日</th>
            <th class="px-3 py-3 font-medium text-right">到账金额</th>
            <th class="px-3 py-3 font-medium">方式 / 水单</th>
            <th class="px-3 py-3 font-medium">核销</th>
            <th class="px-3 py-3 font-medium">状态</th>
            <th class="px-3 py-3 font-medium text-right">操作</th>
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

    <!-- 销售订单详情：出了什么货、单价多少、挂了哪些 MES 单据 -->
    <Dialog
      ref="orderDialogRef"
      :dismissible="false"
      width="4xl"
      overflow-y-auto
      :show-confirm-button="false"
      show-cancel-button
      cancel-button-label="关闭"
      title="销售订单详情"
    >
      <div v-if="orderLoading" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <div v-else-if="orderDetail" class="flex flex-col gap-5">
        <!-- 抬头 -->
        <div
          class="grid grid-cols-2 gap-x-6 gap-y-2 text-sm sm:grid-cols-4 text-n-slate-12"
        >
          <div class="flex flex-col">
            <span class="text-xs text-n-slate-11">订单号</span>
            <span class="font-mono">{{ orderDetail.order.order_no }}</span>
          </div>
          <div class="flex flex-col">
            <span class="text-xs text-n-slate-11">客户</span>
            <span>{{ orderDetail.order.customer_name || '—' }}</span>
          </div>
          <div class="flex flex-col">
            <span class="text-xs text-n-slate-11">业务员</span>
            <span>{{ orderDetail.order.owner_name || '—' }}</span>
          </div>
          <div class="flex flex-col">
            <span class="text-xs text-n-slate-11">状态</span>
            <span>{{
              SO_STATUS_LABELS[orderDetail.order.status] ||
              orderDetail.order.status
            }}</span>
          </div>
          <div class="flex flex-col">
            <span class="text-xs text-n-slate-11">下单日期</span>
            <span>{{
              (orderDetail.order.order_date || '—').slice(0, 10)
            }}</span>
          </div>
          <div class="flex flex-col">
            <span class="text-xs text-n-slate-11">交期</span>
            <span>{{
              (orderDetail.order.delivery_date || '—').slice(0, 10)
            }}</span>
          </div>
          <div class="flex flex-col">
            <span class="text-xs text-n-slate-11">PI 编号</span>
            <span class="font-mono">{{ orderDetail.order.pi_no || '—' }}</span>
          </div>
          <div class="flex flex-col">
            <span class="text-xs text-n-slate-11">订单金额</span>
            <span class="font-mono">
              {{ orderDetail.order.currency || 'CNY' }}
              {{ money(orderDetail.order.amount_micros) }}
            </span>
          </div>
          <div v-if="orderDetail.order.opportunity_name" class="flex flex-col">
            <span class="text-xs text-n-slate-11">来源商机</span>
            <span>{{ orderDetail.order.opportunity_name }}</span>
          </div>
          <div v-if="orderDetail.order.payment_term" class="flex flex-col">
            <span class="text-xs text-n-slate-11">付款方式</span>
            <span>{{ orderDetail.order.payment_term }}</span>
          </div>
          <div v-if="orderDetail.receivable" class="flex flex-col">
            <span class="text-xs text-n-slate-11">已建应收</span>
            <span class="font-mono">{{
              orderDetail.receivable.receivable_no
            }}</span>
          </div>
        </div>

        <!-- 订单明细：出了什么货、单价多少 -->
        <div class="flex flex-col gap-2">
          <span class="text-heading-3 text-n-slate-12">
            订单明细（{{ (orderDetail.line_items || []).length }} 行）
          </span>
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr
                  class="text-left border-b text-n-slate-11 border-n-weak whitespace-nowrap"
                >
                  <th class="px-2 py-2 font-medium">编码</th>
                  <th class="px-2 py-2 font-medium">品名</th>
                  <th class="px-2 py-2 font-medium">规格</th>
                  <th class="px-2 py-2 font-medium text-right">数量</th>
                  <th class="px-2 py-2 font-medium text-right">单价</th>
                  <th class="px-2 py-2 font-medium text-right">金额</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="(item, i) in orderDetail.line_items || []"
                  :key="`li-${i}`"
                  class="border-b border-n-weak align-top"
                >
                  <td
                    class="px-2 py-2 font-mono text-xs whitespace-nowrap text-n-slate-11"
                  >
                    {{ item.sku || '—' }}
                  </td>
                  <td class="px-2 py-2 text-n-slate-12">{{ item.name }}</td>
                  <td
                    class="px-2 py-2 text-xs text-n-slate-11 max-w-md whitespace-pre-wrap"
                  >
                    {{ item.spec || '—' }}
                  </td>
                  <td class="px-2 py-2 font-mono text-right">
                    {{ num(item.quantity) }}
                  </td>
                  <td class="px-2 py-2 font-mono text-right">
                    {{ plainMoney(item.unit_price) }}
                  </td>
                  <td class="px-2 py-2 font-mono text-right text-n-slate-12">
                    {{ plainMoney(item.amount) }}
                  </td>
                </tr>
                <tr v-if="!(orderDetail.line_items || []).length">
                  <td colspan="6" class="px-2 py-6 text-center text-n-slate-11">
                    这张订单没有录明细行。
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <!-- 关联 MES：生产订单 -->
        <div class="flex flex-col gap-2">
          <span class="text-heading-3 text-n-slate-12">
            关联生产订单（{{ (orderDetail.production_orders || []).length }}）
          </span>
          <div
            v-for="po in orderDetail.production_orders || []"
            :key="po.order_no"
            class="flex flex-col gap-1 px-3 py-2 border rounded-lg border-n-weak"
          >
            <div class="flex flex-wrap items-center gap-x-3 text-sm">
              <span class="font-mono text-n-slate-12">{{ po.order_no }}</span>
              <span class="text-n-slate-12">{{ po.product_name }}</span>
              <span class="text-n-slate-11">
                {{ po.qty }} {{ po.unit || '' }}
              </span>
              <span class="text-xs text-n-slate-11">
                {{ po.stage_label }} ·
                {{ PO_STATUS_LABELS[po.status] || po.status }}
              </span>
            </div>
            <div
              v-if="(po.stock_entries || []).length"
              class="flex flex-wrap gap-x-4 text-xs text-n-slate-11"
            >
              <span
                v-for="e in po.stock_entries"
                :key="e.entry_no"
                class="font-mono"
              >
                {{ e.purpose_label }} {{ e.entry_no }}（{{ e.status_label }}）
              </span>
            </div>
          </div>
          <p
            v-if="!(orderDetail.production_orders || []).length"
            class="text-sm text-n-slate-11"
          >
            这张销售订单没有挂生产订单（外购/现货单，或还没转生产）。
          </p>
        </div>

        <!-- 关联 MES：出货单 —— 实际出了什么货 -->
        <div class="flex flex-col gap-2">
          <span class="text-heading-3 text-n-slate-12">
            出货记录（{{ (orderDetail.shipments || []).length }}）
          </span>
          <div
            v-for="sp in orderDetail.shipments || []"
            :key="sp.shipment_no"
            class="flex flex-col gap-1 px-3 py-2 border rounded-lg border-n-weak"
          >
            <div class="flex flex-wrap items-center gap-x-3 text-sm">
              <span class="font-mono text-n-slate-12">{{
                sp.shipment_no
              }}</span>
              <span class="text-n-slate-11">{{ sp.kind_label }}</span>
              <span class="text-n-slate-11">{{ sp.status_label }}</span>
              <span v-if="sp.warehouse" class="text-xs text-n-slate-11">
                {{ sp.warehouse }}
              </span>
              <span v-if="sp.shipped_at" class="text-xs text-n-slate-11">
                出库 {{ (sp.shipped_at || '').slice(0, 10) }}
              </span>
            </div>
            <div
              v-for="(it, i) in sp.items || []"
              :key="`si-${i}`"
              class="flex flex-wrap gap-x-3 text-xs text-n-slate-11"
            >
              <span class="text-n-slate-12">{{ it.product_name || '—' }}</span>
              <span v-if="it.product_sku" class="font-mono">{{
                it.product_sku
              }}</span>
              <span class="font-mono">{{ it.qty }} {{ it.unit || '' }}</span>
              <span v-if="it.remark">{{ it.remark }}</span>
            </div>
          </div>
          <p
            v-if="!(orderDetail.shipments || []).length"
            class="text-sm text-n-slate-11"
          >
            还没有出货单。
          </p>
        </div>

        <p v-if="orderDetail.order.remark" class="text-xs text-n-slate-11">
          订单备注：{{ orderDetail.order.remark }}
        </p>
      </div>
    </Dialog>

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
