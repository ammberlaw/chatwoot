<script setup>
import { ref, reactive, computed, nextTick, onMounted } from 'vue';
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
import ErpSettlementPrintSheet from 'dashboard/components-next/erp/ErpSettlementPrintSheet.vue';

// 应收：台账（从销售订单建账 + 分期计划）与收款记录（水单 + 核销）两页签。
// 台账的「已收」只由核销维护，页面不提供直接改的入口——改了账就不准了。
const { erpCan } = useErpRole();
const canLedger = computed(() => erpCan('receivable'));
const canSettle = computed(() => erpCan('payment'));

const TABS = [
  { key: 'ledger', label: '应收台账' },
  { key: 'receipts', label: '收款记录' },
];
const STATUS_OPTIONS = [
  { value: '', label: '全部状态' },
  { value: 'UNPAID', label: '未收款' },
  { value: 'PARTIAL', label: '部分收款' },
  { value: 'PAID', label: '已收清' },
];
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
  UNPAID: 'bg-n-amber-3 text-n-amber-11',
  PARTIAL: 'bg-n-iris-3 text-n-iris-11',
  PAID: 'bg-n-teal-3 text-n-teal-11',
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

const loadLedgers = async () => {
  loading.value = true;
  try {
    const { data } = await ErpReceivableAPI.get({
      q: keyword.value.trim(),
      status: statusFilter.value,
      per_page: 50,
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
      per_page: 50,
    });
    receipts.value = data.payload;
    receiptMeta.value = data.meta;
  } finally {
    loading.value = false;
  }
};

const reload = () =>
  activeTab.value === 'ledger' ? loadLedgers() : loadReceipts();
const switchTab = key => {
  activeTab.value = key;
  reload();
};

/* ---------------- 建账（从销售订单） ---------------- */
const ledgerDialogRef = ref(null);
const orderOptions = ref([]);
const ledgerForm = reactive({
  crmSalesOrderId: '',
  installments: [],
});
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
    ledgerDialogRef.value?.close();
    loadLedgers();
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
const receiptAmountMicros = computed(() => toMicros(receiptForm.amount));

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

onMounted(loadLedgers);
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between gap-3 px-6 py-4">
      <div class="flex items-center gap-2">
        <div class="i-lucide-hand-coins size-5 text-n-iris-9" />
        <h1 class="text-xl font-semibold text-n-slate-12">应收管理</h1>
        <span v-if="activeTab === 'ledger'" class="text-sm text-n-slate-11">
          应收 {{ money(ledgerMeta.total_micros) }} · 已收
          {{ money(ledgerMeta.received_micros) }} · 未收
          <span class="text-n-slate-12">{{
            money(ledgerMeta.outstanding_micros)
          }}</span>
        </span>
        <span v-else class="text-sm text-n-slate-11">
          本页收款合计 {{ money(receiptMeta.amount_micros) }}
        </span>
      </div>
      <div class="flex items-center gap-2">
        <Input
          v-model="keyword"
          size="sm"
          placeholder="搜单号 / 客户"
          custom-input-class="w-44"
          @keyup.enter="reload"
        />
        <Button label="查询" color="slate" size="sm" @click="reload" />
        <Button
          v-if="canLedger && activeTab === 'ledger'"
          label="从销售订单建账"
          color="iris"
          size="sm"
          @click="openBuild"
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

    <div class="flex items-center gap-2 px-6 pb-3">
      <button
        v-for="tab in TABS"
        :key="tab.key"
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

      <!-- 应收台账 -->
      <table v-else-if="activeTab === 'ledger'" class="w-full text-sm">
        <thead>
          <tr class="text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-3 py-3 font-medium">台账单号</th>
            <th class="px-3 py-3 font-medium">客户 / 订单</th>
            <th class="px-3 py-3 font-medium text-right">应收</th>
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
            <td class="px-3 py-2 text-n-slate-12">
              {{ row.customer_name }}
              <span v-if="row.order_no" class="text-xs text-n-slate-10">
                · {{ row.order_no }}
              </span>
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
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
            <td colspan="7" class="px-3 py-10 text-center text-n-slate-11">
              还没有应收台账。点右上角「从销售订单建账」把订单转成应收。
            </td>
          </tr>
        </tbody>
      </table>

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
                  row.status === 'VOID'
                    ? 'bg-n-slate-3 text-n-slate-11'
                    : 'bg-n-teal-3 text-n-teal-11'
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
    </div>

    <!-- 建账弹窗 -->
    <Dialog
      ref="ledgerDialogRef"
      width="3xl"
      confirm-button-color="iris"
      title="从销售订单建应收账"
      :disable-confirm-button="!ledgerForm.crmSalesOrderId"
      @confirm="submitBuild"
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
      @confirm="submitReceipt"
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
