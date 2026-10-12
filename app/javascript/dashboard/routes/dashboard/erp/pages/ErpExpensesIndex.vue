<script setup>
import { ref, reactive, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useErpRole } from 'dashboard/composables/useErpRole';
import { fmtMoney } from 'dashboard/helper/erpMoney';
import ErpExpensePayoutAPI from 'dashboard/api/erp/expensePayouts';
import ErpLedgerAccountAPI from 'dashboard/api/erp/ledgerAccounts';
import ErpCashAccountAPI from 'dashboard/api/erp/cashAccounts';
import CrmSalesOrderAPI from 'dashboard/api/crm/salesOrders';
import { exportRowsToExcel, fetchAllRows } from 'dashboard/helper/erpExcel';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
// 费用报销（财务端）：员工照旧在 OA 提报销，审批通过后这里付钱、入账、归集订单成本。
// 打款 = 一笔出纳日记账 + 一张待过账凭证（借 费用科目 / 贷 货币资金）+ 挂订单的一行成本。
const { erpCan } = useErpRole();
const canPay = computed(() => erpCan('claim'));

const TABS = [
  { key: 'pending', label: '待打款' },
  { key: 'paid', label: '打款记录' },
];
// 挂订单时这笔报销算哪类成本。默认「报销费用」，佣金/运费类报销可改。
const COST_TYPES = [
  { value: 'EXPENSE', label: '报销费用' },
  { value: 'COMMISSION', label: '佣金' },
  { value: 'FREIGHT', label: '运费' },
  { value: 'OTHER', label: '其他' },
];

const money = micros => (micros ? fmtMoney(micros) : '—');
const toMicros = value => Math.round(Number(value || 0) * 1_000_000);
const today = () => new Date().toISOString().slice(0, 10);

const activeTab = ref('pending');
const loading = ref(false);
const pendingRows = ref([]);
const payouts = ref([]);
const paidSummary = ref({});
// 打款日期区间（后端按 paid_at 筛）。只对「打款记录」页签有意义——
// 待打款那些还没打款，没有日期可筛。
const fromDate = ref('');
const toDate = ref('');
const expenseAccounts = ref([]);
const cashAccounts = ref([]);

const pendingTotal = computed(() =>
  pendingRows.value.reduce(
    (sum, row) => sum + Number(row.amount_micros || 0),
    0
  )
);

const loadPending = async () => {
  loading.value = true;
  try {
    const { data } = await ErpExpensePayoutAPI.pending();
    pendingRows.value = data.payload;
  } finally {
    loading.value = false;
  }
};
const loadPayouts = async () => {
  loading.value = true;
  try {
    const { data } = await ErpExpensePayoutAPI.get({
      per_page: 100,
      from: fromDate.value || undefined,
      to: toDate.value || undefined,
    });
    payouts.value = data.payload;
    paidSummary.value = data.meta || {};
  } finally {
    loading.value = false;
  }
};
const switchTab = key => {
  activeTab.value = key;
  if (key === 'pending') loadPending();
  else loadPayouts();
};

// 费用科目只列末级的损益类费用科目（6601 销售费用 / 6602 管理费用 / 6603 财务费用）。
const loadOptions = async () => {
  const [{ data: accounts }, { data: cash }] = await Promise.all([
    ErpLedgerAccountAPI.get({ per_page: 500 }),
    ErpCashAccountAPI.get(),
  ]);
  expenseAccounts.value = (accounts?.payload || [])
    .filter(a => !a.is_group && a.is_active && String(a.code).startsWith('66'))
    .map(a => ({ value: a.id, label: `${a.code} ${a.name}` }));
  cashAccounts.value = (cash?.payload || [])
    .filter(a => a.is_active !== false)
    .map(a => ({ value: a.id, label: `${a.name}（${a.currency}）` }));
};

const dialogRef = ref(null);
const orderOptions = ref([]);
const submitting = ref(false);
const form = reactive({
  requestId: null,
  requestTitle: '',
  applicantName: '',
  category: '',
  amount: '',
  expenseLedgerAccountId: '',
  cashAccountId: '',
  crmSalesOrderId: '',
  costType: 'EXPENSE',
  paidAt: today(),
  remark: '',
});
const { isDirty, markPristine } = useDirtyGuard(() => form);

const searchOrders = async q => {
  const { data } = await CrmSalesOrderAPI.get({ q, page: 1 });
  orderOptions.value = (data?.payload || []).map(o => ({
    value: o.id,
    label: `${o.order_no} ${o.name || ''}`.trim(),
  }));
};

const openPay = row => {
  Object.assign(form, {
    requestId: row.id,
    requestTitle: row.title,
    applicantName: row.applicant_name,
    category: row.category || '',
    // 实付默认＝申请金额，允许财务核减（发票不全、超标部分不报）。
    amount: row.amount_micros ? row.amount_micros / 1_000_000 : '',
    expenseLedgerAccountId: row.suggested_expense_ledger_account_id || '',
    cashAccountId: cashAccounts.value[0]?.value || '',
    crmSalesOrderId: '',
    costType: 'EXPENSE',
    paidAt: today(),
    remark: '',
  });
  searchOrders('');
  markPristine();
  dialogRef.value?.open();
};

const canSubmit = computed(
  () =>
    Number(form.amount) > 0 &&
    !!form.expenseLedgerAccountId &&
    !!form.cashAccountId
);

const submitPay = async () => {
  if (!canSubmit.value) return;
  submitting.value = true;
  try {
    await ErpExpensePayoutAPI.create({
      payout: {
        oa_approval_request_id: form.requestId,
        amount_micros: toMicros(form.amount),
        expense_ledger_account_id: form.expenseLedgerAccountId,
        cash_account_id: form.cashAccountId,
        crm_sales_order_id: form.crmSalesOrderId || null,
        cost_type: form.crmSalesOrderId ? form.costType : null,
        paid_at: form.paidAt,
        remark: form.remark,
      },
    });
    useAlert('已打款，凭证已进待过账队列');
    dialogRef.value?.close();
    loadPending();
  } catch (error) {
    useAlert(error?.response?.data?.error || '打款失败');
  } finally {
    submitting.value = false;
  }
};

const voidPayout = async row => {
  try {
    const { data } = await ErpExpensePayoutAPI.void(row.id);
    // 凭证若已过账，自动凭证不会被动掉——如实告诉财务去红冲哪一张。
    useAlert(
      data?.posted_voucher_no
        ? `已作废。凭证 ${data.posted_voucher_no} 已过账，请手工红冲`
        : '已作废，资金流水与订单成本已回滚'
    );
    loadPayouts();
  } catch (error) {
    useAlert(error?.response?.data?.error || '作废失败');
  }
};

/* ---------------- 导出 Excel ---------------- */
// 按当前页签导：待打款导待付清单，打款记录导已付流水。
const exporting = ref(false);
const stamp = () => new Date().toLocaleString('sv').slice(0, 16);

const exportPending = () => {
  // 待打款走的是 pending 接口（不分页，一次给全），屏幕上的就是全量。
  exportRowsToExcel(
    {
      title: '待打款报销单',
      meta: [
        { label: '导出时间', value: stamp() },
        { label: '单数', value: pendingRows.value.length },
      ],
      columns: [
        { label: '报销人', key: 'applicant_name' },
        { label: '部门', key: 'department_name' },
        { label: '费用类型', key: 'category' },
        { label: '申请金额', key: 'amount_micros', money: true },
        { label: '费用说明', key: 'note' },
        { label: '发票', key: 'invoices' },
        { label: '审批通过', key: 'approved_on' },
      ],
      rows: pendingRows.value.map(row => ({
        ...row,
        note: row.form_data?.note,
        invoices: row.form_data?.invoices,
        approved_on: (row.approved_at || '').slice(0, 10),
      })),
    },
    `待打款报销单_${stamp().slice(0, 10)}`
  );
};

const exportPayouts = async () => {
  // ⚠️ 打款记录页面只给 100 条，导出重新向后端分页要完。
  const rows = await fetchAllRows(params => ErpExpensePayoutAPI.get(params), {
    from: fromDate.value || undefined,
    to: toDate.value || undefined,
  });
  exportRowsToExcel(
    {
      title: '报销打款记录',
      meta: [
        { label: '导出时间', value: stamp() },
        {
          label: '打款日期',
          value: `${fromDate.value || '不限'} ~ ${toDate.value || '不限'}`,
        },
        { label: '打款笔数', value: rows.length },
      ],
      columns: [
        { label: '单号', key: 'payout_no' },
        { label: '报销人', key: 'applicant_name' },
        { label: '金额', key: 'amount_micros', money: true },
        { label: '费用科目', key: 'expense_account' },
        { label: '付款账户', key: 'cash_account_name' },
        { label: '挂订单', key: 'sales_order_no' },
        { label: '打款日期', key: 'paid_on' },
        { label: '状态', key: 'status_label' },
      ],
      rows: rows.map(row => ({
        ...row,
        expense_account: [row.expense_account_code, row.expense_account_name]
          .filter(Boolean)
          .join(' '),
        paid_on: (row.paid_at || '').slice(0, 10),
      })),
    },
    `报销打款记录_${stamp().slice(0, 10)}`
  );
};

const exportCurrent = async () => {
  exporting.value = true;
  try {
    if (activeTab.value === 'pending') exportPending();
    else await exportPayouts();
  } catch (error) {
    useAlert('导出失败，请重试');
  } finally {
    exporting.value = false;
  }
};

onMounted(() => {
  loadPending();
  loadOptions();
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between gap-3 px-6 py-4 [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8">
      <div class="flex items-center gap-2">
        <div class="i-lucide-receipt size-5 text-n-iris-9" />
        <h1 class="text-xl font-semibold text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8">费用报销</h1>
        <span v-if="activeTab === 'pending'" class="text-sm text-n-slate-11">
          待打款 {{ pendingRows.length }} 单 ·
          {{ money(pendingTotal) }}
        </span>
        <span v-else class="text-sm text-n-slate-11">
          已打款合计 {{ money(paidSummary.amount_micros) }}
        </span>
      </div>
      <div class="flex items-center gap-2">
        <!-- 导出是只读动作，不挂打款权限 -->
        <Button
          label="导出 Excel"
          color="slate"
          variant="faded"
          size="sm"
          :is-loading="exporting"
          @click="exportCurrent"
        />
      </div>
    </div>

    <div class="flex flex-wrap items-center gap-2 px-6 pb-3 [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8">
      <!-- 全站统一的页面级 Tab（灰槽 + 深色选中块），样式见 _next-colors.scss -->
      <div data-tabbar="page">
        <button
          v-for="tab in TABS"
          :key="tab.key"
          :aria-selected="activeTab === tab.key"
          @click="switchTab(tab.key)"
        >
          {{ tab.label }}
        </button>
      </div>
      <!-- 打款日期区间：只对「打款记录」有意义，待打款那些还没打款、没日期可筛 -->
      <template v-if="activeTab === 'paid'">
        <DatePicker
          v-model="fromDate"
          placeholder="打款日期起"
          trigger-class="w-36"
          @change="loadPayouts"
        />
        <span class="text-sm text-n-slate-10">至</span>
        <DatePicker
          v-model="toDate"
          placeholder="打款日期止"
          trigger-class="w-36"
          @change="loadPayouts"
        />
      </template>
    </div>

    <HScrollButtons />
    <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8">
      <div v-if="loading" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>

      <table v-else-if="activeTab === 'pending'" class="w-full text-sm">
        <thead>
          <tr class="text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-3 py-3 font-medium whitespace-nowrap">报销人</th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">部门</th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">费用类型</th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              申请金额
            </th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">费用说明</th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              发票
            </th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">审批通过</th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              操作
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in pendingRows"
            :key="row.id"
            class="border-b border-n-weak"
          >
            <td class="px-3 py-2 text-n-slate-12">{{ row.applicant_name }}</td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ row.department_name || '—' }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">{{ row.category || '—' }}</td>
            <td class="px-3 py-2 text-right text-n-slate-12">
              {{ money(row.amount_micros) }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ row.form_data?.note || '—' }}
            </td>
            <td class="px-3 py-2 text-right text-n-slate-11">
              {{ row.form_data?.invoices || '—' }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ (row.approved_at || '').slice(0, 10) }}
            </td>
            <td class="px-3 py-2 text-right">
              <Button
                v-if="canPay"
                label="打款"
                color="iris"
                size="xs"
                :disabled="!row.amount_micros"
                @click="openPay(row)"
              />
            </td>
          </tr>
          <tr v-if="!pendingRows.length">
            <td colspan="8" class="px-3 py-10 text-center text-n-slate-11">
              没有待打款的报销单。员工在「OA
              审批」提交费用报销、审批通过后会出现在这里。
            </td>
          </tr>
        </tbody>
      </table>

      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-3 py-3 font-medium whitespace-nowrap">单号</th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">报销人</th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              金额
            </th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">费用科目</th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">付款账户</th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">挂订单</th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">打款日期</th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">状态</th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              操作
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in payouts"
            :key="row.id"
            class="border-b border-n-weak"
          >
            <td class="px-3 py-2 text-n-slate-12">{{ row.payout_no }}</td>
            <td class="px-3 py-2 text-n-slate-11">{{ row.applicant_name }}</td>
            <td class="px-3 py-2 text-right text-n-slate-12">
              {{ money(row.amount_micros) }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ row.expense_account_code }} {{ row.expense_account_name }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ row.cash_account_name }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ row.sales_order_no || '—' }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">{{ row.paid_at }}</td>
            <td class="px-3 py-2">
              <span
                :class="
                  row.status === 'VOID' ? 'text-n-slate-11' : 'text-n-teal-11'
                "
              >
                {{ row.status_label }}
              </span>
            </td>
            <td class="px-3 py-2 text-right">
              <Button
                v-if="canPay && row.status !== 'VOID'"
                label="作废"
                color="ruby"
                variant="faded"
                size="xs"
                @click="voidPayout(row)"
              />
            </td>
          </tr>
          <tr v-if="!payouts.length">
            <td colspan="9" class="px-3 py-10 text-center text-n-slate-11">
              还没有打款记录。
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <Dialog
      ref="dialogRef"
      width="2xl"
      confirm-button-color="iris"
      confirm-button-label="确认打款"
      :title="`报销打款 · ${form.applicantName}`"
      :description="form.requestTitle"
      :is-loading="submitting"
      :disable-confirm-button="!canSubmit"
      :dirty="isDirty"
      dirty-save-label="保存"
      @confirm="submitPay"
      @close="markPristine"
      @save="submitPay"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-3 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              实付金额 <span class="text-n-ruby-11">*</span>
            </label>
            <Input
              v-model="form.amount"
              size="sm"
              type="number"
              custom-input-class="!h-9"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">打款日期</label>
            <DatePicker v-model="form.paidAt" :clearable="false" block />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              付款账户 <span class="text-n-ruby-11">*</span>
            </label>
            <SelectCard
              v-model="form.cashAccountId"
              :options="cashAccounts"
              block
            />
          </div>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">
            费用科目 <span class="text-n-ruby-11">*</span>
            <span v-if="form.category" class="font-normal text-n-slate-11">
              （按「{{ form.category }}」带出，可改）
            </span>
          </label>
          <SelectCard
            v-model="form.expenseLedgerAccountId"
            :options="expenseAccounts"
            block
          />
        </div>
        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              挂销售订单
              <span class="font-normal text-n-slate-11"
                >（选填，进订单成本）</span
              >
            </label>
            <ComboBox
              v-model="form.crmSalesOrderId"
              :options="orderOptions"
              use-api-results
              placeholder="搜订单号"
              @search="searchOrders"
            />
          </div>
          <div v-if="form.crmSalesOrderId" class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">成本类型</label>
            <SelectCard v-model="form.costType" :options="COST_TYPES" block />
          </div>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">备注</label>
          <Input v-model="form.remark" size="sm" custom-input-class="!h-9" />
        </div>
      </div>
    </Dialog>
  </div>
</template>
