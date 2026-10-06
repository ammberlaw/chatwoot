<script setup>
import { ref, reactive, computed, nextTick, onMounted, watch } from 'vue';
import { STATUS_TONE } from 'dashboard/helper/statusTone';
import { useAlert } from 'dashboard/composables';
import { useErpRole } from 'dashboard/composables/useErpRole';
import { fmtMoney } from 'dashboard/helper/erpMoney';
import { printElement } from 'dashboard/helper/printHelper';

import ErpPayableAPI from 'dashboard/api/erp/payables';
import ErpPaymentAPI from 'dashboard/api/erp/paymentRecords';
import MesPurchaseOrderAPI from 'dashboard/api/mes/purchaseOrders';
import MesSupplierAPI from 'dashboard/api/mes/suppliers';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import ErpAllocationEditor from 'dashboard/components-next/erp/ErpAllocationEditor.vue';
import ErpSettlementPrintSheet from 'dashboard/components-next/erp/ErpSettlementPrintSheet.vue';
import ErpAgingTable from 'dashboard/components-next/erp/ErpAgingTable.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';

// 应付：台账（按采购单建账，按明细行供应商分组）/ 付款记录（核销）/ 供应商对账 三页签。
// 与应收同构；台账「已付」只由核销维护。
const { erpCan } = useErpRole();
const canLedger = computed(() => erpCan('payable'));
const canSettle = computed(() => erpCan('payment'));

const TABS = [
  { key: 'ledger', label: '应付台账' },
  { key: 'payments', label: '付款记录' },
  { key: 'statement', label: '供应商对账' },
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
const toMicros = value => Math.round(Number(value || 0) * 1_000_000);
const today = () => new Date().toISOString().slice(0, 10);

const activeTab = ref('ledger');
const loading = ref(false);
const keyword = ref('');
const statusFilter = ref('');

const ledgers = ref([]);
const ledgerMeta = ref({});
const payments = ref([]);
const paymentMeta = ref({});
const statementRows = ref([]);

// 分页：meta.count 是全量数，超过一页给翻页入口——静默截断=「数据消失」。
const PER_PAGE = 50;
const ledgerPage = ref(1);
const paymentPage = ref(1);

const loadLedgers = async () => {
  loading.value = true;
  try {
    const { data } = await ErpPayableAPI.get({
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

const loadPayments = async () => {
  loading.value = true;
  try {
    const { data } = await ErpPaymentAPI.get({
      q: keyword.value.trim(),
      page: paymentPage.value,
      per_page: PER_PAGE,
    });
    payments.value = data.payload;
    paymentMeta.value = data.meta;
  } finally {
    loading.value = false;
  }
};

watch([keyword, statusFilter], () => {
  ledgerPage.value = 1;
  paymentPage.value = 1;
});
watch(ledgerPage, loadLedgers);
watch(paymentPage, loadPayments);

const loadStatement = async () => {
  loading.value = true;
  try {
    const { data } = await ErpPayableAPI.supplierStatement();
    statementRows.value = data.payload;
  } finally {
    loading.value = false;
  }
};

const agingRef = ref(null);
// 供应商对账与账龄分析不吃关键字（各自有自己的查询条），隐掉顶部搜索。
const isDocTab = computed(() =>
  ['ledger', 'payments'].includes(activeTab.value)
);
const reload = () => {
  if (activeTab.value === 'ledger') return loadLedgers();
  if (activeTab.value === 'payments') return loadPayments();
  if (activeTab.value === 'statement') return loadStatement();
  return agingRef.value?.load();
};
const switchTab = key => {
  activeTab.value = key;
  nextTick(reload);
};

/* ---------------- 从采购单建账 ---------------- */
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

onMounted(loadLedgers);
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between gap-3 px-6 py-4">
      <div class="flex items-center gap-2">
        <div class="i-lucide-file-output size-5 text-n-iris-9" />
        <h1 class="text-xl font-semibold text-n-slate-12">应付管理</h1>
        <span v-if="activeTab === 'ledger'" class="text-sm text-n-slate-11">
          应付 {{ money(ledgerMeta.total_micros) }} · 已付
          {{ money(ledgerMeta.paid_micros) }} · 未付
          <span class="text-n-slate-12">{{
            money(ledgerMeta.outstanding_micros)
          }}</span>
        </span>
        <span
          v-else-if="activeTab === 'payments'"
          class="text-sm text-n-slate-11"
        >
          本页付款合计 {{ money(paymentMeta.amount_micros) }}
        </span>
      </div>
      <div class="flex items-center gap-2">
        <Input
          v-if="isDocTab"
          v-model="keyword"
          size="sm"
          placeholder="搜单号 / 供应商"
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

    <div class="flex items-center gap-2 px-6 pb-3">
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
        </button>
      </div>
      <SelectCard
        v-if="activeTab === 'ledger'"
        v-model="statusFilter"
        :options="STATUS_OPTIONS"
        @update:model-value="loadLedgers"
      />
    </div>

    <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto">
      <div v-if="loading" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>

      <!-- 应付台账 -->
      <table v-else-if="activeTab === 'ledger'" class="w-full text-sm">
        <thead>
          <tr class="text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-3 py-3 font-medium">台账单号</th>
            <th class="px-3 py-3 font-medium">供应商 / 采购单</th>
            <th class="px-3 py-3 font-medium text-right">应付</th>
            <th class="px-3 py-3 font-medium text-right">已付</th>
            <th class="px-3 py-3 font-medium text-right">未付</th>
            <th class="px-3 py-3 font-medium">到期日</th>
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
              {{ row.payable_no }}
            </td>
            <td class="px-3 py-2 text-n-slate-12">
              {{ row.supplier_name }}
              <span v-if="row.po_no" class="text-xs text-n-slate-10">
                · {{ row.po_no }}
              </span>
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
              {{ row.currency }} {{ money(row.total_amount_micros) }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-11">
              {{ money(row.paid_amount_micros) }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
              {{ money(row.outstanding_micros) }}
            </td>
            <td class="px-3 py-2 whitespace-nowrap text-n-slate-11">
              {{ row.due_date || '—' }}
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
            <td colspan="7" class="px-3 py-10 text-center text-n-slate-11">
              还没有应付台账。点右上角「从采购单建账」按供应商生成应付。
            </td>
          </tr>
        </tbody>
      </table>

      <!-- 付款记录 -->
      <table v-else-if="activeTab === 'payments'" class="w-full text-sm">
        <thead>
          <tr class="text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-3 py-3 font-medium">付款单号</th>
            <th class="px-3 py-3 font-medium">供应商</th>
            <th class="px-3 py-3 font-medium">付款日</th>
            <th class="px-3 py-3 font-medium text-right">付款金额</th>
            <th class="px-3 py-3 font-medium">方式 / 凭据</th>
            <th class="px-3 py-3 font-medium">核销</th>
            <th class="px-3 py-3 font-medium">状态</th>
            <th class="px-3 py-3 font-medium text-right">操作</th>
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

      <!-- 账龄分析 -->
      <ErpAgingTable
        v-else-if="activeTab === 'aging'"
        ref="agingRef"
        title="应付账龄分析表"
        party-label="供应商"
        :fetcher="ErpPayableAPI.aging"
      />

      <!-- 供应商对账 -->
      <table v-else class="w-full max-w-3xl text-sm">
        <thead>
          <tr class="text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-3 py-3 font-medium">供应商</th>
            <th class="px-3 py-3 font-medium text-right">应付合计</th>
            <th class="px-3 py-3 font-medium text-right">已付</th>
            <th class="px-3 py-3 font-medium text-right">未付</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in statementRows"
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
          <tr v-if="!statementRows.length">
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
