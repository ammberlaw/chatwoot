<script setup>
import { ref, reactive, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useErpRole } from 'dashboard/composables/useErpRole';
import { useErpLedgerAccountsStore } from 'dashboard/stores/erp/ledgerAccounts';
import { fmtMoney } from 'dashboard/helper/erpMoney';
import ErpCashAccountAPI from 'dashboard/api/erp/cashAccounts';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import MonthPicker from 'dashboard/components-next/monthpicker/MonthPicker.vue';
import { exportRowsToExcel } from 'dashboard/helper/erpExcel';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';

// 资金账户与出纳日记账：账户余额 = 期初 + 流入 - 流出（流水只增不改，任何时点都能对银行对账单）。
// 收付款单落库会自动记一笔流水；这里另外提供内部划转（成对流水 + 自动凭证）。
const { erpCan } = useErpRole();
const canWrite = computed(() => erpCan('cash'));
const accountStore = useErpLedgerAccountsStore();

const KINDS = [
  { value: 'BANK', label: '银行账户' },
  { value: 'CASH', label: '现金' },
  { value: 'PAYPAL', label: 'PayPal' },
  { value: 'WESTERN_UNION', label: '西联' },
  { value: 'OTHER', label: '其他' },
];
const CURRENCIES = [
  { value: 'CNY', label: '人民币 CNY' },
  { value: 'USD', label: '美元 USD' },
  { value: 'EUR', label: '欧元 EUR' },
];
const KIND_ICON = {
  BANK: 'i-lucide-landmark',
  CASH: 'i-lucide-wallet',
  PAYPAL: 'i-lucide-circle-dollar-sign',
  WESTERN_UNION: 'i-lucide-send',
  OTHER: 'i-lucide-piggy-bank',
};

const money = micros => fmtMoney(micros || 0);
const toMicros = value => Math.round(Number(value || 0) * 1_000_000);
const today = () => new Date().toISOString().slice(0, 10);

const accounts = ref([]);
const transactions = ref([]);
const transactionsMeta = ref({});
const loading = ref(false);
const filterAccountId = ref('');

const totalByCurrency = computed(() => {
  const map = {};
  accounts.value.forEach(a => {
    map[a.currency] = (map[a.currency] || 0) + a.balance_micros;
  });
  return map;
});

const loadAccounts = async () => {
  const { data } = await ErpCashAccountAPI.get();
  accounts.value = data.payload;
};
const loadTransactions = async () => {
  loading.value = true;
  try {
    const { data } = await ErpCashAccountAPI.transactions({
      cash_account_id: filterAccountId.value || undefined,
    });
    transactions.value = data.payload;
    transactionsMeta.value = data.meta || {};
  } finally {
    loading.value = false;
  }
};
const reload = async () => {
  await loadAccounts();
  await loadTransactions();
};

/* ---------------- 资金报表（ERP_SPEC §9.3） ---------------- */
// 日记账看的是一笔笔流水，报表看的是一个月里每个账户进出了多少——月末对账、给老板看现金流。
const TABS = [
  { key: 'ledger', label: '出纳日记账' },
  { key: 'report', label: '资金报表' },
];
const activeTab = ref('ledger');
const reportPeriod = ref(new Date().toISOString().slice(0, 7));
const report = ref(null);
const reportLoading = ref(false);

const loadReport = async () => {
  reportLoading.value = true;
  try {
    const { data } = await ErpCashAccountAPI.report({
      period: reportPeriod.value,
    });
    report.value = data.payload;
  } catch (error) {
    useAlert(error?.response?.data?.error || '资金报表加载失败');
    report.value = null;
  } finally {
    reportLoading.value = false;
  }
};

const switchTab = key => {
  activeTab.value = key;
  if (key === 'report' && !report.value) loadReport();
};

// 折 CNY 列：外币账户没填期初本位币就显示「—」，不拿原币数字充数。
const baseMoney = micros => (micros == null ? '—' : money(micros));

/* ---------------- 导出 ---------------- */
// 按当前页签导：日记账导流水，报表导四栏表。
// ⚠️ 日记账页面只给 200 笔，导出重新向后端要全量——导一张自己缺了一截还不说的流水表，
// 拿去跟银行对账就是白对。
const exporting = ref(false);

const exportLedger = async () => {
  const { data } = await ErpCashAccountAPI.transactions({
    cash_account_id: filterAccountId.value || undefined,
    limit: 5000,
  });
  const rows = data.payload;
  exportRowsToExcel(
    {
      title: '出纳日记账',
      meta: [
        { label: '导出时间', value: new Date().toLocaleString() },
        {
          label: '账户',
          value:
            accounts.value.find(a => a.id === filterAccountId.value)?.name ||
            '全部账户',
        },
        { label: '流水笔数', value: rows.length },
      ],
      columns: [
        { label: '日期', key: 'happened_at' },
        { label: '账户', key: 'cash_account_name' },
        { label: '摘要', key: 'summary' },
        { label: '往来单位', key: 'counterparty' },
        { label: '币种', key: 'currency' },
        { label: '收入', key: 'in_micros', money: true },
        { label: '支出', key: 'out_micros', money: true },
        { label: '经办', key: 'created_by_name' },
      ],
      rows: rows.map(row => ({
        ...row,
        in_micros: row.direction === 'IN' ? row.amount_micros : null,
        out_micros: row.direction === 'OUT' ? row.amount_micros : null,
      })),
    },
    `出纳日记账_${new Date().toISOString().slice(0, 10)}`
  );
  if (data.meta?.truncated) {
    useAlert(
      `共 ${data.meta.count} 笔流水，本次只导出了前 ${rows.length} 笔，请按账户或日期缩小范围再导一次`
    );
  }
};

const exportReport = () =>
  exportRowsToExcel(
    {
      title: '资金报表',
      meta: [
        { label: '期间', value: `${report.value.from} 至 ${report.value.to}` },
        {
          label: '口径',
          value: '折 CNY 走账面本位币（各笔按发生日汇率），与总账一致',
        },
        ...(report.value.missing_base_accounts.length
          ? [
              {
                label: '未计入合计',
                value: `${report.value.missing_base_accounts.join('、')}（未填期初余额折 CNY）`,
              },
            ]
          : []),
      ],
      columns: [
        { label: '账户', key: 'name' },
        { label: '类型', key: 'kind_label' },
        { label: '币种', key: 'currency' },
        { label: '期初', key: 'opening_micros', money: true },
        { label: '本期收', key: 'in_micros', money: true },
        { label: '本期支', key: 'out_micros', money: true },
        { label: '期末', key: 'closing_micros', money: true },
        { label: '期末折 CNY', key: 'closing_base_micros', money: true },
      ],
      rows: report.value.rows,
    },
    `资金报表_${report.value.period}`
  );

const exportExcel = async () => {
  exporting.value = true;
  try {
    if (activeTab.value === 'ledger') await exportLedger();
    else exportReport();
  } catch (error) {
    useAlert(error?.response?.data?.error || '导出失败');
  } finally {
    exporting.value = false;
  }
};

const canExport = computed(() =>
  activeTab.value === 'ledger'
    ? transactions.value.length > 0
    : Boolean(report.value?.rows?.length)
);

/* ---------------- 账户维护 ---------------- */
const accountDialogRef = ref(null);
const editing = ref(null);
const form = reactive({
  name: '',
  kind: 'BANK',
  currency: 'CNY',
  accountNo: '',
  bankName: '',
  ledgerAccountId: '',
  openingBalance: '',
  openingBase: '',
  isActive: true,
});
const { isDirty, markPristine } = useDirtyGuard(() => form);
// 外币账户的期初余额折多少人民币，只有财务知道——不填的话资金报表里这个账户
// 的本位币列留空（绝不按 1:1 当人民币加）。CNY 账户不用填，它自己就是本位币。
const needsOpeningBase = computed(() => form.currency !== 'CNY');
const ledgerOptions = computed(() =>
  accountStore.getRecords
    .filter(a => !a.isGroup && ['CASH', 'BANK'].includes(a.accountType))
    .map(a => ({ value: a.id, label: `${a.code} ${a.name}` }))
);
const openAccount = (record = null) => {
  editing.value = record;
  Object.assign(form, {
    name: record?.name || '',
    kind: record?.kind || 'BANK',
    currency: record?.currency || 'CNY',
    accountNo: record?.account_no || '',
    bankName: record?.bank_name || '',
    ledgerAccountId: record?.ledger_account_id || '',
    openingBalance: record
      ? (record.opening_balance_micros / 1_000_000).toFixed(2)
      : '',
    openingBase:
      record?.opening_base_amount_micros != null
        ? (record.opening_base_amount_micros / 1_000_000).toFixed(2)
        : '',
    isActive: record ? record.is_active : true,
  });
  markPristine();
  accountDialogRef.value?.open();
};
// CNY 账户的期初本位币就是它自己；外币账户留空＝「财务还没填」，存 null 让报表如实留空。
const openingBaseMicros = () => {
  if (!needsOpeningBase.value) return toMicros(form.openingBalance);

  return form.openingBase === '' ? null : toMicros(form.openingBase);
};

const submitAccount = async () => {
  if (!form.name.trim()) return;
  const payload = {
    cash_account: {
      name: form.name.trim(),
      kind: form.kind,
      currency: form.currency,
      account_no: form.accountNo,
      bank_name: form.bankName,
      ledger_account_id: form.ledgerAccountId || null,
      opening_balance_micros: toMicros(form.openingBalance),
      opening_base_amount_micros: openingBaseMicros(),
      is_active: form.isActive,
    },
  };
  try {
    if (editing.value)
      await ErpCashAccountAPI.update(editing.value.id, payload);
    else await ErpCashAccountAPI.create(payload);
    useAlert('资金账户已保存');
    accountDialogRef.value?.close();
    reload();
    // 期初（尤其是期初折 CNY）一改，报表的期初/期末/合计就全变了，停在报表页签时要重算。
    if (activeTab.value === 'report') loadReport();
  } catch (error) {
    useAlert(error?.response?.data?.error || '保存失败');
  }
};

/* ---------------- 内部划转 ---------------- */
const transferDialogRef = ref(null);
const transferForm = reactive({
  fromId: '',
  toId: '',
  amount: '',
  exchangeRate: '',
  happenedAt: today(),
  summary: '',
});
const { isDirty: isTransferDirty, markPristine: markTransferPristine } =
  useDirtyGuard(() => transferForm);
// 外币账户互转（USD→USD）要填划转日汇率折本位币；CNY 恒为 1，不显示输入框。
const transferCurrency = computed(
  () => accounts.value.find(a => a.id === transferForm.fromId)?.currency || ''
);
const transferNeedsRate = computed(
  () => transferCurrency.value && transferCurrency.value !== 'CNY'
);
const accountOptions = computed(() =>
  accounts.value.map(a => ({
    value: a.id,
    label: `${a.name}（${a.currency} ${money(a.balance_micros)}）`,
  }))
);
const openTransfer = () => {
  Object.assign(transferForm, {
    fromId: '',
    toId: '',
    amount: '',
    exchangeRate: '',
    happenedAt: today(),
    summary: '',
  });
  markTransferPristine();
  transferDialogRef.value?.open();
};
const transferInvalid = computed(
  () =>
    !transferForm.fromId ||
    !transferForm.toId ||
    transferForm.fromId === transferForm.toId ||
    !transferForm.amount ||
    (transferNeedsRate.value && !(Number(transferForm.exchangeRate) > 0))
);
const submitTransfer = async () => {
  if (transferInvalid.value) return;
  try {
    await ErpCashAccountAPI.transfer({
      from_id: transferForm.fromId,
      to_id: transferForm.toId,
      amount_micros: toMicros(transferForm.amount),
      happened_at: transferForm.happenedAt,
      summary: transferForm.summary,
      exchange_rate: transferNeedsRate.value ? transferForm.exchangeRate : 1,
    });
    useAlert('划转完成，已生成成对流水与待过账凭证');
    transferDialogRef.value?.close();
    reload();
    if (activeTab.value === 'report') loadReport();
  } catch (error) {
    useAlert(error?.response?.data?.error || '划转失败');
  }
};

onMounted(async () => {
  if (!accountStore.getRecords.length) accountStore.get({});
  await reload();
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between gap-3 px-6 py-4 [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8">
      <div class="flex items-center gap-2">
        <div class="i-lucide-wallet size-5 text-n-iris-9" />
        <h1 class="text-xl font-semibold text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8">资金账户</h1>
        <span
          v-for="(amount, currency) in totalByCurrency"
          :key="currency"
          class="text-sm text-n-slate-11"
        >
          {{ currency }} 合计
          <span class="font-mono text-n-slate-12">{{ money(amount) }}</span>
        </span>
      </div>
      <div class="flex items-center gap-2">
        <!-- 导出是只读动作，不挂在写权限上 -->
        <Button
          label="导出 Excel"
          color="slate"
          variant="faded"
          size="sm"
          :is-loading="exporting"
          :disabled="!canExport"
          @click="exportExcel"
        />
        <Button
          v-if="canWrite"
          label="内部划转"
          color="slate"
          variant="faded"
          size="sm"
          :disabled="accounts.length < 2"
          @click="openTransfer"
        />
        <Button
          v-if="canWrite"
          label="新建账户"
          color="iris"
          size="sm"
          @click="openAccount()"
        />
      </div>
    </div>

    <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8">
      <div class="grid grid-cols-2 gap-3 mb-5 md:grid-cols-4">
        <button
          v-for="cashAccount in accounts"
          :key="cashAccount.id"
          class="flex flex-col gap-2 p-4 text-left transition-colors border shadow-sm rounded-xl border-n-weak bg-n-solid-1 hover:border-n-iris-8"
          :class="{ 'opacity-60': !cashAccount.is_active }"
          @click="canWrite && openAccount(cashAccount)"
        >
          <div class="flex items-center justify-between">
            <span class="text-sm text-n-slate-11">{{ cashAccount.name }}</span>
            <div
              :class="KIND_ICON[cashAccount.kind]"
              class="size-4 text-n-iris-9"
            />
          </div>
          <div class="font-mono text-xl font-semibold text-n-slate-12">
            {{ cashAccount.currency }} {{ money(cashAccount.balance_micros) }}
          </div>
          <div class="text-xs text-n-slate-10">
            {{ cashAccount.kind_label }}
            <span v-if="cashAccount.ledger_account_label">
              · {{ cashAccount.ledger_account_label }}
            </span>
            <span v-else class="text-n-amber-11">
              · 未映射科目，自动凭证不会生成
            </span>
          </div>
        </button>
        <div
          v-if="!accounts.length"
          class="col-span-4 px-3 py-10 text-sm text-center text-n-slate-11"
        >
          还没有资金账户。点右上角「新建账户」把银行户 / 现金 / PayPal
          建起来，并映射到会计科目。
        </div>
      </div>

      <div class="flex flex-wrap items-center gap-2 mb-3">
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
        <template v-if="activeTab === 'ledger'">
          <SelectCard
            v-model="filterAccountId"
            :options="[{ value: '', label: '全部账户' }, ...accountOptions]"
            @update:model-value="loadTransactions"
          />
          <span class="text-xs text-n-slate-10">
            流水只增不改；单据作废会补一条反向冲销
          </span>
        </template>
        <template v-else>
          <MonthPicker
            v-model="reportPeriod"
            @update:model-value="loadReport"
          />
          <span class="text-xs text-n-slate-10">
            折 CNY 走账面本位币（各笔按发生日汇率），与总账口径一致
          </span>
        </template>
      </div>

      <div
        v-if="activeTab === 'ledger' && loading"
        class="py-10 text-center text-n-slate-11"
      >
        加载中…
      </div>
      <table v-else-if="activeTab === 'ledger'" class="w-full text-sm">
        <thead>
          <tr class="text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-3 py-3 font-medium">日期</th>
            <th class="px-3 py-3 font-medium">账户</th>
            <th class="px-3 py-3 font-medium">摘要</th>
            <th class="px-3 py-3 font-medium">往来单位</th>
            <th class="px-3 py-3 font-medium text-right">收入</th>
            <th class="px-3 py-3 font-medium text-right">支出</th>
            <th class="px-3 py-3 font-medium">经办</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="transaction in transactions"
            :key="transaction.id"
            class="border-b border-n-weak hover:bg-n-alpha-1"
          >
            <td class="px-3 py-2 whitespace-nowrap text-n-slate-11">
              {{ transaction.happened_at }}
            </td>
            <td class="px-3 py-2 text-n-slate-12">
              {{ transaction.cash_account_name }}
            </td>
            <td class="px-3 py-2 text-n-slate-12">{{ transaction.summary }}</td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ transaction.counterparty || '—' }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-teal-11">
              {{
                transaction.direction === 'IN'
                  ? money(transaction.amount_micros)
                  : ''
              }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-ruby-11">
              {{
                transaction.direction === 'OUT'
                  ? money(transaction.amount_micros)
                  : ''
              }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ transaction.created_by_name || '—' }}
            </td>
          </tr>
          <!-- 日记账要跟银行对账单核对，截断必须显式说出来 -->
          <tr v-if="transactionsMeta.truncated">
            <td
              colspan="7"
              class="px-3 py-2 text-center text-xs text-n-amber-11"
            >
              共 {{ transactionsMeta.count }} 笔流水，仅展示最近
              {{ transactions.length }} 笔；更早的请选账户或用日期范围缩小查询
            </td>
          </tr>
          <tr v-if="!transactions.length">
            <td colspan="7" class="px-3 py-10 text-center text-n-slate-11">
              还没有资金流水。登记收付款或做一次内部划转就会出现在这里。
            </td>
          </tr>
        </tbody>
      </table>

      <!-- 资金报表：期初/收/支/期末，原币为主口径，右侧折 CNY -->
      <div v-else-if="reportLoading" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <template v-else-if="report">
        <div
          v-if="report.missing_base_accounts.length"
          class="px-3 py-2 mb-3 text-xs rounded-lg bg-n-amber-3 text-n-amber-11"
        >
          {{ report.missing_base_accounts.join('、') }}
          还没填「期初余额折 CNY」，这些账户的折 CNY 列留空、也未计入下方合计。
          点上方账户卡片补填即可。
        </div>
        <table class="w-full text-sm">
          <thead>
            <tr class="text-left border-b text-n-slate-11 border-n-weak">
              <th class="px-3 py-3 font-medium">账户</th>
              <th class="px-3 py-3 font-medium">币种</th>
              <th class="px-3 py-3 font-medium text-right">期初</th>
              <th class="px-3 py-3 font-medium text-right">本期收</th>
              <th class="px-3 py-3 font-medium text-right">本期支</th>
              <th class="px-3 py-3 font-medium text-right">期末</th>
              <th
                class="px-3 py-3 font-medium text-right border-l border-n-weak"
              >
                期末折 CNY
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in report.rows"
              :key="row.id"
              class="border-b border-n-weak hover:bg-n-alpha-1"
              :class="{ 'opacity-60': !row.is_active }"
            >
              <td class="px-3 py-2 text-n-slate-12">
                {{ row.name }}
                <span class="text-xs text-n-slate-10">
                  {{ row.kind_label }}
                </span>
              </td>
              <td class="px-3 py-2 text-n-slate-11">{{ row.currency }}</td>
              <td class="px-3 py-2 font-mono text-right text-n-slate-11">
                {{ money(row.opening_micros) }}
              </td>
              <td
                class="px-3 py-2 font-mono text-right"
                :class="row.in_micros ? 'text-n-teal-11' : 'text-n-slate-10'"
              >
                {{ row.in_micros ? money(row.in_micros) : '—' }}
              </td>
              <td
                class="px-3 py-2 font-mono text-right"
                :class="row.out_micros ? 'text-n-ruby-11' : 'text-n-slate-10'"
              >
                {{ row.out_micros ? money(row.out_micros) : '—' }}
              </td>
              <td class="px-3 py-2 font-mono text-right text-n-slate-12">
                {{ money(row.closing_micros) }}
              </td>
              <td
                class="px-3 py-2 font-mono text-right border-l border-n-weak"
                :class="
                  row.base_unknown ? 'text-n-amber-11' : 'text-n-slate-11'
                "
              >
                {{ baseMoney(row.closing_base_micros) }}
              </td>
            </tr>

            <!-- 各币种原币小计：外币不折算也看得出进出 -->
            <tr
              v-for="group in report.by_currency"
              :key="group.currency"
              class="border-b border-n-weak bg-n-alpha-1"
            >
              <td class="px-3 py-2 text-n-slate-11" colspan="2">
                {{ group.currency }} 小计（原币）
              </td>
              <td class="px-3 py-2 font-mono text-right text-n-slate-11">
                {{ money(group.opening_micros) }}
              </td>
              <td class="px-3 py-2 font-mono text-right text-n-slate-11">
                {{ money(group.in_micros) }}
              </td>
              <td class="px-3 py-2 font-mono text-right text-n-slate-11">
                {{ money(group.out_micros) }}
              </td>
              <td class="px-3 py-2 font-mono text-right text-n-slate-12">
                {{ money(group.closing_micros) }}
              </td>
              <td class="px-3 py-2 border-l border-n-weak" />
            </tr>

            <tr class="font-medium border-t-2 border-n-strong">
              <td class="px-3 py-3 text-n-slate-12" colspan="2">
                合计（折 CNY）
              </td>
              <td class="px-3 py-3 font-mono text-right text-n-slate-11">
                {{ money(report.totals.opening_base_micros) }}
              </td>
              <td class="px-3 py-3 font-mono text-right text-n-teal-11">
                {{ money(report.totals.in_base_micros) }}
              </td>
              <td class="px-3 py-3 font-mono text-right text-n-ruby-11">
                {{ money(report.totals.out_base_micros) }}
              </td>
              <td class="px-3 py-3 font-mono text-right text-n-slate-12">
                {{ money(report.totals.closing_base_micros) }}
              </td>
              <td class="px-3 py-3 border-l border-n-weak" />
            </tr>

            <tr v-if="!report.rows.length">
              <td colspan="7" class="px-3 py-10 text-center text-n-slate-11">
                还没有资金账户，先建一个再看报表。
              </td>
            </tr>
          </tbody>
        </table>
      </template>
    </div>

    <!-- 账户维护 -->
    <Dialog
      ref="accountDialogRef"
      width="2xl"
      confirm-button-color="iris"
      :title="editing ? `编辑账户 ${editing.name}` : '新建资金账户'"
      :disable-confirm-button="!form.name"
      :dirty="isDirty"
      dirty-save-label="保存"
      @confirm="submitAccount"
      @close="markPristine"
      @save="submitAccount"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-3 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              账户名称 <span class="text-n-ruby-11">*</span>
            </label>
            <Input v-model="form.name" size="sm" custom-input-class="!h-9" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">类型</label>
            <SelectCard v-model="form.kind" :options="KINDS" block />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">币种</label>
            <SelectCard v-model="form.currency" :options="CURRENCIES" block />
          </div>
        </div>

        <div class="grid grid-cols-3 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">开户行</label>
            <Input
              v-model="form.bankName"
              size="sm"
              custom-input-class="!h-9"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">账号</label>
            <Input
              v-model="form.accountNo"
              size="sm"
              custom-input-class="!h-9"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              期初余额<span v-if="needsOpeningBase"
                >（{{ form.currency }}）</span
              >
            </label>
            <Input
              v-model="form.openingBalance"
              size="sm"
              type="number"
              custom-input-class="!h-9"
            />
          </div>
        </div>

        <!-- 外币账户：期初余额折多少人民币，报表要靠它才能加进合计 -->
        <div v-if="needsOpeningBase" class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">期初余额折 CNY</label>
          <Input
            v-model="form.openingBase"
            size="sm"
            type="number"
            custom-input-class="!h-9"
          />
          <span class="text-xs text-n-slate-10">
            不填的话资金报表里这个账户的「折 CNY」列会留空，也不计入合计—— 按
            1:1 把外币当人民币加会直接算错账。
          </span>
        </div>

        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">映射会计科目</label>
          <ComboBox
            v-model="form.ledgerAccountId"
            :options="ledgerOptions"
            placeholder="选货币资金类科目（银行存款 / 库存现金）"
          />
          <span class="text-xs text-n-slate-10">
            自动凭证按这个科目记账；不映射的话收付款不会生成待过账凭证
          </span>
        </div>

        <label class="flex items-center gap-2 text-heading-3 text-n-slate-12">
          <input v-model="form.isActive" type="checkbox" class="w-4 h-4" />
          启用（停用后不出现在收付款的账户下拉）
        </label>
      </div>
    </Dialog>

    <!-- 内部划转 -->
    <Dialog
      ref="transferDialogRef"
      width="2xl"
      confirm-button-color="iris"
      title="内部划转"
      :disable-confirm-button="transferInvalid"
      :dirty="isTransferDirty"
      dirty-save-label="保存"
      @confirm="submitTransfer"
      @close="markTransferPristine"
      @save="submitTransfer"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">转出账户</label>
            <ComboBox
              v-model="transferForm.fromId"
              :options="accountOptions"
              placeholder="选转出账户"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">转入账户</label>
            <ComboBox
              v-model="transferForm.toId"
              :options="accountOptions"
              placeholder="选转入账户"
            />
          </div>
        </div>
        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">划转金额</label>
            <Input
              v-model="transferForm.amount"
              size="sm"
              type="number"
              custom-input-class="!h-9"
            />
          </div>
          <div v-if="transferNeedsRate" class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              划转日汇率（{{ transferCurrency }} → CNY）
            </label>
            <Input
              v-model="transferForm.exchangeRate"
              size="sm"
              type="number"
              step="0.000001"
              custom-input-class="!h-9"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">划转日期</label>
            <DatePicker
              v-model="transferForm.happenedAt"
              :clearable="false"
              block
            />
          </div>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">摘要</label>
          <Input
            v-model="transferForm.summary"
            size="sm"
            custom-input-class="!h-9"
          />
        </div>
      </div>
    </Dialog>
  </div>
</template>
