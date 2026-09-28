<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import ErpReportAPI from 'dashboard/api/erp/reports';
import { fmtMoney } from 'dashboard/helper/erpMoney';
import { frontendURL } from 'dashboard/helper/URLHelper';
import { printElement } from 'dashboard/helper/printHelper';
import { downloadBlob } from 'dashboard/helper/erpDownload';
import { exportRowsToExcel } from 'dashboard/helper/erpExcel';

import Button from 'dashboard/components-next/button/Button.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';

// 财务报表：资产负债表（时点）/ 利润表 / 现金流量表 / 科目余额表 / 试算平衡表（期间）/ 勾稽检查。
// 全部实时按已记账凭证算。资产负债表按传统左右分栏排（左资产、右负债与所有者权益），打印直接出这个版式。
//
// 科目余额表与试算平衡表**只列末级科目**：分类科目是下级的汇总，跟着进合计就翻倍，
// 试算平衡的「借贷合计相等」立刻对不上（想看科目树去「账簿」页那张）。
const TABS = [
  { key: 'balance', label: '资产负债表' },
  { key: 'income', label: '利润表' },
  { key: 'cashflow', label: '现金流量表' },
  { key: 'accountBalances', label: '科目余额表' },
  { key: 'trial', label: '试算平衡表' },
  { key: 'tie', label: '勾稽检查' },
];

const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');

const monthStart = () => {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth(), 1).toLocaleDateString(
    'sv'
  );
};
const monthEnd = () => {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth() + 1, 0).toLocaleDateString(
    'sv'
  );
};

const money = micros => (micros ? fmtMoney(micros) : '—');

// 余额按科目自身方向算，为负说明余额实际在相反方（如应收账款的贷方余额＝预收货款）。
// 照账簿页那张的规矩：方向标记翻过来、金额取绝对值，别让财务看一列负数。
const dirLabel = d => (d === 'DEBIT' ? '借' : '贷');
const balanceDir = (micros, direction) =>
  micros < 0
    ? dirLabel(direction === 'DEBIT' ? 'CREDIT' : 'DEBIT')
    : dirLabel(direction);
const balanceText = (micros, direction) =>
  micros
    ? `${balanceDir(micros, direction)} ${fmtMoney(Math.abs(micros))}`
    : '—';

const activeTab = ref('balance');
const asOf = ref(monthEnd());
const from = ref(monthStart());
const to = ref(monthEnd());
const loading = ref(false);

const balanceSheet = ref(null);
const incomeStatement = ref(null);
const cashFlow = ref(null);
const accountBalances = ref(null);
const trialBalance = ref(null);
const tieCheck = ref(null);
const reportRef = ref(null);

const loadBalanceSheet = async () => {
  loading.value = true;
  try {
    const { data } = await ErpReportAPI.balanceSheet({ as_of: asOf.value });
    balanceSheet.value = data;
  } finally {
    loading.value = false;
  }
};

const loadIncomeStatement = async () => {
  loading.value = true;
  try {
    const { data } = await ErpReportAPI.incomeStatement({
      from: from.value,
      to: to.value,
    });
    incomeStatement.value = data;
  } finally {
    loading.value = false;
  }
};

const loadCashFlow = async () => {
  loading.value = true;
  try {
    const { data } = await ErpReportAPI.cashFlow({
      from: from.value,
      to: to.value,
    });
    cashFlow.value = data;
  } finally {
    loading.value = false;
  }
};

const loadAccountBalances = async () => {
  loading.value = true;
  try {
    const { data } = await ErpReportAPI.accountBalances({
      from: from.value,
      to: to.value,
    });
    accountBalances.value = data;
  } finally {
    loading.value = false;
  }
};

const loadTrialBalance = async () => {
  loading.value = true;
  try {
    const { data } = await ErpReportAPI.trialBalance({
      from: from.value,
      to: to.value,
    });
    trialBalance.value = data;
  } finally {
    loading.value = false;
  }
};

const loadTieCheck = async () => {
  loading.value = true;
  try {
    const { data } = await ErpReportAPI.tieCheck({ as_of: asOf.value });
    tieCheck.value = data;
  } finally {
    loading.value = false;
  }
};

const LOADERS = {
  balance: loadBalanceSheet,
  income: loadIncomeStatement,
  cashflow: loadCashFlow,
  accountBalances: loadAccountBalances,
  trial: loadTrialBalance,
  tie: loadTieCheck,
};

// 按时点取数的页签用「截至」单日期，按期间取数的用起止两个日期。
const AS_OF_TABS = ['balance', 'tie'];
const isAsOfTab = computed(() => AS_OF_TABS.includes(activeTab.value));

const reload = () => LOADERS[activeTab.value]();

const switchTab = key => {
  activeTab.value = key;
  reload();
};

const PRINT_TITLES = {
  balance: () => `资产负债表 ${asOf.value}`,
  income: () => `利润表 ${from.value} 至 ${to.value}`,
  cashflow: () => `现金流量表 ${from.value} 至 ${to.value}`,
  accountBalances: () => `科目余额表 ${from.value} 至 ${to.value}`,
  trial: () => `试算平衡表 ${from.value} 至 ${to.value}`,
  tie: () => `勾稽检查 ${asOf.value}`,
};

const print = () =>
  printElement(reportRef.value, PRINT_TITLES[activeTab.value]());

// 审计接口：把当前期间的已记账数据打包给会计师事务所。
const exporting = ref(false);
const downloadAuditPack = async () => {
  exporting.value = true;
  try {
    const { data } = await ErpReportAPI.auditExport({
      from: from.value,
      to: to.value,
    });
    downloadBlob(data, `财务数据_${from.value}_至_${to.value}.zip`);
  } finally {
    exporting.value = false;
  }
};

// 资产负债表是「截至某日」的累计余额，钻进明细账要给个区间：
// 取截止日所在月的 1 号做起点，财务钻下去看的是「这个月这个科目怎么动的」。
const monthStartOf = dateStr => `${String(dateStr).slice(0, 7)}-01`;

// 点科目 → 钻到「账簿 → 明细账」，期间跟着报表口径一起带过去。
const openLedger = (ledgerAccountId, fromDate, toDate) => {
  if (!ledgerAccountId) return;
  router.push({
    path: frontendURL(`accounts/${accountId.value}/erp/ledgers`),
    query: { account_id: ledgerAccountId, from: fromDate, to: toDate },
  });
};

// 科目余额表 / 试算平衡表两张是行表，导 Excel（金额为数值，财务要接着求和）。
// 三张版式报表不导 Excel——它们是打印件，走「打印」按钮。
const BALANCE_COLUMNS = [
  { label: '科目编码', key: 'code' },
  { label: '科目名称', key: 'name' },
  { label: '期初方向', key: 'opening_dir' },
  { label: '期初余额', key: 'opening_abs', money: true },
  { label: '本期借方', key: 'debit_micros', money: true },
  { label: '本期贷方', key: 'credit_micros', money: true },
  { label: '本年累计借方', key: 'ytd_debit_micros', money: true },
  { label: '本年累计贷方', key: 'ytd_credit_micros', money: true },
  { label: '期末方向', key: 'closing_dir' },
  { label: '期末余额', key: 'closing_abs', money: true },
];
const TRIAL_COLUMNS = [
  { label: '科目编码', key: 'code' },
  { label: '科目名称', key: 'name' },
  { label: '期初借方', key: 'opening_debit_micros', money: true },
  { label: '期初贷方', key: 'opening_credit_micros', money: true },
  { label: '本期借方', key: 'debit_micros', money: true },
  { label: '本期贷方', key: 'credit_micros', money: true },
  { label: '期末借方', key: 'closing_debit_micros', money: true },
  { label: '期末贷方', key: 'closing_credit_micros', money: true },
];
const EXPORTABLE = { accountBalances: '科目余额表', trial: '试算平衡表' };
const canExportExcel = computed(() => Boolean(EXPORTABLE[activeTab.value]));

const exportExcel = () => {
  const isTrial = activeTab.value === 'trial';
  const report = isTrial ? trialBalance.value : accountBalances.value;
  if (!report) return;
  const title = EXPORTABLE[activeTab.value];
  const rows = isTrial
    ? report.payload
    : report.payload.map(row => ({
        ...row,
        opening_dir: row.opening_micros
          ? balanceDir(row.opening_micros, row.direction)
          : '',
        opening_abs: Math.abs(row.opening_micros),
        closing_dir: row.closing_micros
          ? balanceDir(row.closing_micros, row.direction)
          : '',
        closing_abs: Math.abs(row.closing_micros),
      }));
  exportRowsToExcel(
    {
      title,
      meta: [
        { label: '期间', value: `${from.value} 至 ${to.value}` },
        { label: '口径', value: '仅已过账凭证、仅末级科目，金额为本位币' },
        { label: '导出时间', value: new Date().toLocaleString() },
      ],
      columns: isTrial ? TRIAL_COLUMNS : BALANCE_COLUMNS,
      rows,
    },
    `${title}_${from.value}_至_${to.value}`
  );
};

const section = key => balanceSheet.value?.sections?.[key];
const totals = computed(() => balanceSheet.value?.meta?.totals || {});

// 左右两栏行数不同，短的一边补空行，打印时左右框线才齐。
const assetLines = computed(() => [
  ...(section('CURRENT_ASSET')?.lines || []),
  ...(section('NON_CURRENT_ASSET')?.lines || []),
]);
const equityLines = computed(() => [
  ...(section('CURRENT_LIABILITY')?.lines || []),
  ...(section('NON_CURRENT_LIABILITY')?.lines || []),
  ...(section('EQUITY')?.lines || []),
]);
const padRows = computed(() =>
  Math.max(0, assetLines.value.length - equityLines.value.length)
);
const padRowsLeft = computed(() =>
  Math.max(0, equityLines.value.length - assetLines.value.length)
);

onMounted(loadBalanceSheet);
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between gap-3 px-6 py-4">
      <div class="flex items-center gap-2">
        <div class="i-lucide-file-spreadsheet size-5 text-n-iris-9" />
        <h1 class="text-xl font-semibold text-n-slate-12">财务报表</h1>
        <span
          v-if="activeTab === 'balance' && balanceSheet"
          class="px-2 py-0.5 text-xs rounded"
          :class="
            balanceSheet.meta.balanced
              ? 'bg-n-teal-3 text-n-teal-11'
              : 'bg-n-ruby-3 text-n-ruby-11'
          "
        >
          {{ balanceSheet.meta.balanced ? '资产 = 负债 + 权益' : '两边不平' }}
        </span>
        <span
          v-if="activeTab === 'trial' && trialBalance"
          class="px-2 py-0.5 text-xs rounded"
          :class="
            trialBalance.meta.balanced
              ? 'bg-n-teal-3 text-n-teal-11'
              : 'bg-n-ruby-3 text-n-ruby-11'
          "
        >
          {{ trialBalance.meta.balanced ? '三对合计全平' : '有合计不平' }}
        </span>
        <span
          v-if="activeTab === 'tie' && tieCheck"
          class="px-2 py-0.5 text-xs rounded"
          :class="
            tieCheck.meta.passed
              ? 'bg-n-teal-3 text-n-teal-11'
              : 'bg-n-ruby-3 text-n-ruby-11'
          "
        >
          {{
            tieCheck.meta.passed
              ? '5 项全部通过'
              : `${tieCheck.meta.failed_count} 项没过`
          }}
        </span>
        <span
          v-if="activeTab === 'cashflow' && cashFlow"
          class="px-2 py-0.5 text-xs rounded"
          :class="
            cashFlow.meta.balanced
              ? 'bg-n-teal-3 text-n-teal-11'
              : 'bg-n-ruby-3 text-n-ruby-11'
          "
        >
          {{
            cashFlow.meta.balanced
              ? '净增加额 = 期末 − 期初'
              : `与现金余额差 ${money(cashFlow.meta.variance_micros)}`
          }}
        </span>
      </div>
      <div class="flex items-center gap-2">
        <template v-if="isAsOfTab">
          <span class="text-sm text-n-slate-11">截至</span>
          <DatePicker v-model="asOf" :clearable="false" trigger-class="w-36" />
        </template>
        <template v-else>
          <DatePicker v-model="from" :clearable="false" trigger-class="w-36" />
          <span class="text-sm text-n-slate-11">至</span>
          <DatePicker v-model="to" :clearable="false" trigger-class="w-36" />
        </template>
        <Button label="查询" color="iris" size="sm" @click="reload" />
        <Button
          label="打印"
          icon="i-lucide-printer"
          color="slate"
          variant="faded"
          size="sm"
          @click="print"
        />
        <Button
          v-if="canExportExcel"
          label="导出 Excel"
          icon="i-lucide-download"
          color="slate"
          variant="faded"
          size="sm"
          @click="exportExcel"
        />
        <Button
          label="审计数据包"
          icon="i-lucide-file-archive"
          color="slate"
          variant="faded"
          size="sm"
          :is-loading="exporting"
          @click="downloadAuditPack"
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
    </div>

    <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto">
      <div v-if="loading" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>

      <div v-else ref="reportRef" class="max-w-4xl">
        <!-- 资产负债表：左资产 / 右负债与所有者权益 -->
        <template v-if="activeTab === 'balance' && balanceSheet">
          <div class="mb-1 text-lg font-semibold text-center text-n-slate-12">
            资 产 负 债 表
          </div>
          <div class="mb-3 text-xs text-center text-n-slate-11">
            截至 {{ balanceSheet.meta.as_of }} · 单位：元
          </div>
          <div class="grid grid-cols-2 gap-4">
            <table class="w-full text-sm">
              <thead>
                <tr class="text-left border-b text-n-slate-11 border-n-weak">
                  <th class="px-2 py-2 font-medium">资&#12288;产</th>
                  <th class="px-2 py-2 font-medium text-right">期末余额</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="line in assetLines"
                  :key="line.code"
                  class="border-b border-n-weak"
                >
                  <td class="px-2 py-1.5 text-n-slate-12">
                    <button
                      class="text-left hover:text-n-iris-11 hover:underline"
                      title="查看该科目明细账"
                      @click="openLedger(line.id, monthStartOf(asOf), asOf)"
                    >
                      <span class="font-mono text-xs text-n-slate-11">
                        {{ line.code }}
                      </span>
                      {{ line.name }}
                    </button>
                  </td>
                  <td class="px-2 py-1.5 font-mono text-right text-n-slate-12">
                    {{ money(line.amount_micros) }}
                  </td>
                </tr>
                <tr
                  v-for="n in padRowsLeft"
                  :key="`pad-l-${n}`"
                  class="border-b border-n-weak"
                >
                  <td class="px-2 py-1.5">&nbsp;</td>
                  <td class="px-2 py-1.5" />
                </tr>
                <tr class="font-semibold">
                  <td class="px-2 py-2 text-n-slate-12">资产总计</td>
                  <td class="px-2 py-2 font-mono text-right text-n-slate-12">
                    {{ money(totals.assets_micros) }}
                  </td>
                </tr>
              </tbody>
            </table>

            <table class="w-full text-sm">
              <thead>
                <tr class="text-left border-b text-n-slate-11 border-n-weak">
                  <th class="px-2 py-2 font-medium">负债和所有者权益</th>
                  <th class="px-2 py-2 font-medium text-right">期末余额</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="line in equityLines"
                  :key="line.code"
                  class="border-b border-n-weak"
                >
                  <td class="px-2 py-1.5 text-n-slate-12">
                    <button
                      class="text-left hover:text-n-iris-11 hover:underline"
                      title="查看该科目明细账"
                      @click="openLedger(line.id, monthStartOf(asOf), asOf)"
                    >
                      <span class="font-mono text-xs text-n-slate-11">
                        {{ line.code }}
                      </span>
                      {{ line.name }}
                    </button>
                  </td>
                  <td class="px-2 py-1.5 font-mono text-right text-n-slate-12">
                    {{ money(line.amount_micros) }}
                  </td>
                </tr>
                <tr class="border-b border-n-weak">
                  <td class="px-2 py-1.5 text-n-slate-12">
                    本年利润（未结转）
                  </td>
                  <td class="px-2 py-1.5 font-mono text-right text-n-slate-12">
                    {{ money(totals.current_profit_micros) }}
                  </td>
                </tr>
                <tr
                  v-for="n in padRows"
                  :key="`pad-r-${n}`"
                  class="border-b border-n-weak"
                >
                  <td class="px-2 py-1.5">&nbsp;</td>
                  <td class="px-2 py-1.5" />
                </tr>
                <tr class="font-semibold">
                  <td class="px-2 py-2 text-n-slate-12">
                    负债和所有者权益总计
                  </td>
                  <td class="px-2 py-2 font-mono text-right text-n-slate-12">
                    {{ money(totals.liabilities_and_equity_micros) }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </template>

        <!-- 利润表 -->
        <template v-else-if="activeTab === 'income' && incomeStatement">
          <div class="mb-1 text-lg font-semibold text-center text-n-slate-12">
            利 润 表
          </div>
          <div class="mb-3 text-xs text-center text-n-slate-11">
            {{ incomeStatement.meta.from }} 至 {{ incomeStatement.meta.to }} ·
            单位：元
          </div>
          <table class="w-full max-w-2xl mx-auto text-sm">
            <thead>
              <tr class="text-left border-b text-n-slate-11 border-n-weak">
                <th class="px-2 py-2 font-medium">项&#12288;目</th>
                <th class="px-2 py-2 font-medium text-right">本期金额</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="row in incomeStatement.payload"
                :key="row.key"
                class="border-b border-n-weak"
              >
                <td class="px-2 py-1.5 whitespace-pre text-n-slate-12">
                  {{ row.label }}
                </td>
                <td class="px-2 py-1.5 font-mono text-right text-n-slate-12">
                  {{ money(row.amount_micros) }}
                </td>
              </tr>
              <tr class="font-medium border-b border-n-weak">
                <td class="px-2 py-2 text-n-slate-12">二、营业利润</td>
                <td class="px-2 py-2 font-mono text-right text-n-slate-12">
                  {{ money(incomeStatement.meta.operating_profit_micros) }}
                </td>
              </tr>
              <tr class="font-medium border-b border-n-weak">
                <td class="px-2 py-2 text-n-slate-12">三、利润总额</td>
                <td class="px-2 py-2 font-mono text-right text-n-slate-12">
                  {{ money(incomeStatement.meta.total_profit_micros) }}
                </td>
              </tr>
              <tr class="font-semibold">
                <td class="px-2 py-2 text-n-slate-12">四、净利润</td>
                <td class="px-2 py-2 font-mono text-right text-n-slate-12">
                  {{ money(incomeStatement.meta.net_profit_micros) }}
                </td>
              </tr>
            </tbody>
          </table>
        </template>

        <!-- 现金流量表（直接法）：三大活动 + 汇率变动 + 净增加额，末尾与现金余额勾稽 -->
        <template v-else-if="activeTab === 'cashflow' && cashFlow">
          <div class="mb-1 text-lg font-semibold text-center text-n-slate-12">
            现 金 流 量 表
          </div>
          <div class="mb-3 text-xs text-center text-n-slate-11">
            {{ cashFlow.meta.from }} 至 {{ cashFlow.meta.to }} · 单位：元
          </div>
          <table class="w-full max-w-2xl mx-auto text-sm">
            <thead>
              <tr class="text-left border-b text-n-slate-11 border-n-weak">
                <th class="px-2 py-2 font-medium">项&#12288;目</th>
                <th class="px-2 py-2 font-medium text-right">本期金额</th>
              </tr>
            </thead>
            <tbody>
              <template v-for="sec in cashFlow.payload" :key="sec.key">
                <tr class="border-b bg-n-alpha-1 border-n-weak">
                  <td class="px-2 py-2 font-medium text-n-slate-12" colspan="2">
                    {{ sec.label }}
                  </td>
                </tr>
                <tr
                  v-for="row in sec.rows"
                  :key="row.code"
                  class="border-b border-n-weak"
                >
                  <td class="px-2 py-1.5 pl-6 text-n-slate-12">
                    {{ row.label }}
                  </td>
                  <td class="px-2 py-1.5 font-mono text-right text-n-slate-12">
                    {{ money(row.amount_micros) }}
                  </td>
                </tr>
                <tr class="font-medium border-b border-n-weak">
                  <td class="px-2 py-1.5 pl-6 text-n-slate-12">
                    {{ sec.short_label }}活动产生的现金流量净额
                  </td>
                  <td class="px-2 py-1.5 font-mono text-right text-n-slate-12">
                    {{ money(sec.net_micros) }}
                  </td>
                </tr>
              </template>
              <tr class="border-b border-n-weak">
                <td class="px-2 py-2 font-medium text-n-slate-12">
                  四、汇率变动对现金及现金等价物的影响
                </td>
                <td class="px-2 py-2 font-mono text-right text-n-slate-12">
                  {{ money(cashFlow.meta.fx_effect_micros) }}
                </td>
              </tr>
              <tr class="font-medium border-b border-n-weak">
                <td class="px-2 py-2 text-n-slate-12">
                  五、现金及现金等价物净增加额
                </td>
                <td class="px-2 py-2 font-mono text-right text-n-slate-12">
                  {{ money(cashFlow.meta.net_increase_micros) }}
                </td>
              </tr>
              <tr class="border-b border-n-weak">
                <td class="px-2 py-1.5 pl-6 text-n-slate-11">
                  加：期初现金及现金等价物余额
                </td>
                <td class="px-2 py-1.5 font-mono text-right text-n-slate-11">
                  {{ money(cashFlow.meta.opening_cash_micros) }}
                </td>
              </tr>
              <tr class="font-semibold">
                <td class="px-2 py-2 text-n-slate-12">
                  六、期末现金及现金等价物余额
                </td>
                <td class="px-2 py-2 font-mono text-right text-n-slate-12">
                  {{ money(cashFlow.meta.closing_cash_micros) }}
                </td>
              </tr>
            </tbody>
          </table>
          <p class="max-w-2xl mx-auto mt-3 text-xs text-n-slate-11">
            现金流量项目默认按凭证的对方科目自动判定；判定不对时可在凭证的货币资金分录上手工指定。
            内部划转（银行↔现金、人民币户↔外币户）不计入现金流量。
          </p>
        </template>

        <!-- 科目余额表：末级科目的期初/本期借贷/本年累计/期末（列口径对齐金蝶） -->
        <template
          v-else-if="activeTab === 'accountBalances' && accountBalances"
        >
          <div class="mb-1 text-lg font-semibold text-center text-n-slate-12">
            科 目 余 额 表
          </div>
          <div class="mb-3 text-xs text-center text-n-slate-11">
            {{ accountBalances.meta.from }} 至 {{ accountBalances.meta.to }} ·
            本年累计自 {{ accountBalances.meta.ytd_from }} 起 · 仅末级科目 ·
            单位：元
          </div>
          <div class="overflow-x-auto">
            <table class="w-full text-sm min-w-[880px]">
              <thead>
                <tr class="text-left border-b text-n-slate-11 border-n-weak">
                  <th class="px-2 py-2 font-medium">科&#12288;目</th>
                  <th class="px-2 py-2 font-medium text-right">期初余额</th>
                  <th class="px-2 py-2 font-medium text-right">本期借方</th>
                  <th class="px-2 py-2 font-medium text-right">本期贷方</th>
                  <th class="px-2 py-2 font-medium text-right">本年借方</th>
                  <th class="px-2 py-2 font-medium text-right">本年贷方</th>
                  <th class="px-2 py-2 font-medium text-right">期末余额</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="row in accountBalances.payload"
                  :key="row.id"
                  class="border-b border-n-weak"
                >
                  <td class="px-2 py-1.5 text-n-slate-12">
                    <button
                      class="text-left hover:text-n-iris-11 hover:underline"
                      title="查看该科目明细账"
                      @click="openLedger(row.id, from, to)"
                    >
                      <span class="font-mono text-xs text-n-slate-11">
                        {{ row.code }}
                      </span>
                      {{ row.name }}
                    </button>
                  </td>
                  <td class="px-2 py-1.5 font-mono text-right text-n-slate-12">
                    {{ balanceText(row.opening_micros, row.direction) }}
                  </td>
                  <td class="px-2 py-1.5 font-mono text-right text-n-slate-12">
                    {{ money(row.debit_micros) }}
                  </td>
                  <td class="px-2 py-1.5 font-mono text-right text-n-slate-12">
                    {{ money(row.credit_micros) }}
                  </td>
                  <td class="px-2 py-1.5 font-mono text-right text-n-slate-11">
                    {{ money(row.ytd_debit_micros) }}
                  </td>
                  <td class="px-2 py-1.5 font-mono text-right text-n-slate-11">
                    {{ money(row.ytd_credit_micros) }}
                  </td>
                  <td class="px-2 py-1.5 font-mono text-right text-n-slate-12">
                    {{ balanceText(row.closing_micros, row.direction) }}
                  </td>
                </tr>
                <tr class="font-semibold">
                  <td class="px-2 py-2 text-n-slate-12" colspan="2">
                    合&#12288;计
                  </td>
                  <td class="px-2 py-2 font-mono text-right text-n-slate-12">
                    {{ money(accountBalances.meta.totals.debit_micros) }}
                  </td>
                  <td class="px-2 py-2 font-mono text-right text-n-slate-12">
                    {{ money(accountBalances.meta.totals.credit_micros) }}
                  </td>
                  <td class="px-2 py-2 font-mono text-right text-n-slate-12">
                    {{ money(accountBalances.meta.totals.ytd_debit_micros) }}
                  </td>
                  <td class="px-2 py-2 font-mono text-right text-n-slate-12">
                    {{ money(accountBalances.meta.totals.ytd_credit_micros) }}
                  </td>
                  <td class="px-2 py-2" />
                </tr>
              </tbody>
            </table>
          </div>
          <p class="mt-3 text-xs text-n-slate-11">
            余额前的「借/贷」是这笔余额实际在哪一方——应收账款出现贷方余额即预收货款。
            点科目名可钻到该科目明细账；导出的 Excel
            里方向与金额分两列，金额是可直接求和的数值。
          </p>
        </template>

        <!-- 试算平衡表：期初/本期/期末各分借贷两栏，三对合计必须各自相等 -->
        <template v-else-if="activeTab === 'trial' && trialBalance">
          <div class="mb-1 text-lg font-semibold text-center text-n-slate-12">
            试 算 平 衡 表
          </div>
          <div class="mb-3 text-xs text-center text-n-slate-11">
            {{ trialBalance.meta.from }} 至 {{ trialBalance.meta.to }} ·
            仅末级科目 · 单位：元
          </div>
          <div class="overflow-x-auto">
            <table class="w-full text-sm min-w-[860px]">
              <thead>
                <tr class="text-center border-b text-n-slate-11 border-n-weak">
                  <th class="px-2 py-2 font-medium text-left" rowspan="2">
                    科&#12288;目
                  </th>
                  <th class="px-2 py-2 font-medium" colspan="2">期初余额</th>
                  <th class="px-2 py-2 font-medium" colspan="2">本期发生额</th>
                  <th class="px-2 py-2 font-medium" colspan="2">期末余额</th>
                </tr>
                <tr class="border-b text-n-slate-11 border-n-weak">
                  <th class="px-2 py-1.5 font-normal text-right">借方</th>
                  <th class="px-2 py-1.5 font-normal text-right">贷方</th>
                  <th class="px-2 py-1.5 font-normal text-right">借方</th>
                  <th class="px-2 py-1.5 font-normal text-right">贷方</th>
                  <th class="px-2 py-1.5 font-normal text-right">借方</th>
                  <th class="px-2 py-1.5 font-normal text-right">贷方</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="row in trialBalance.payload"
                  :key="row.id"
                  class="border-b border-n-weak"
                >
                  <td class="px-2 py-1.5 text-n-slate-12">
                    <button
                      class="text-left hover:text-n-iris-11 hover:underline"
                      title="查看该科目明细账"
                      @click="openLedger(row.id, from, to)"
                    >
                      <span class="font-mono text-xs text-n-slate-11">
                        {{ row.code }}
                      </span>
                      {{ row.name }}
                    </button>
                  </td>
                  <td class="px-2 py-1.5 font-mono text-right text-n-slate-12">
                    {{ money(row.opening_debit_micros) }}
                  </td>
                  <td class="px-2 py-1.5 font-mono text-right text-n-slate-12">
                    {{ money(row.opening_credit_micros) }}
                  </td>
                  <td class="px-2 py-1.5 font-mono text-right text-n-slate-12">
                    {{ money(row.debit_micros) }}
                  </td>
                  <td class="px-2 py-1.5 font-mono text-right text-n-slate-12">
                    {{ money(row.credit_micros) }}
                  </td>
                  <td class="px-2 py-1.5 font-mono text-right text-n-slate-12">
                    {{ money(row.closing_debit_micros) }}
                  </td>
                  <td class="px-2 py-1.5 font-mono text-right text-n-slate-12">
                    {{ money(row.closing_credit_micros) }}
                  </td>
                </tr>
                <tr class="font-semibold">
                  <td class="px-2 py-2 text-n-slate-12">合&#12288;计</td>
                  <td
                    v-for="key in [
                      'opening_debit_micros',
                      'opening_credit_micros',
                      'debit_micros',
                      'credit_micros',
                      'closing_debit_micros',
                      'closing_credit_micros',
                    ]"
                    :key="key"
                    class="px-2 py-2 font-mono text-right text-n-slate-12"
                  >
                    {{ money(trialBalance.meta.totals[key]) }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <div class="flex flex-wrap gap-2 mt-3">
            <span
              v-for="check in trialBalance.meta.checks"
              :key="check.key"
              class="px-2 py-1 text-xs rounded"
              :class="
                check.balanced
                  ? 'bg-n-teal-3 text-n-teal-11'
                  : 'bg-n-ruby-3 text-n-ruby-11'
              "
            >
              {{ check.label }}：{{
                check.balanced ? '借贷相等' : `差 ${money(check.diff_micros)}`
              }}
            </span>
          </div>
          <p class="mt-3 text-xs text-n-slate-11">
            异常余额（如应收账款的贷方余额）落到相反那一栏，不写负数——这样三对合计才各自相等。
            任何一对不相等都说明账有问题，去「勾稽检查」看原因。
          </p>
        </template>

        <!-- 勾稽检查：资产负债表与科目余额的对应关系，不平时点名是哪个科目掉出了报表 -->
        <template v-else-if="activeTab === 'tie' && tieCheck">
          <div class="mb-1 text-lg font-semibold text-center text-n-slate-12">
            勾 稽 检 查
          </div>
          <div class="mb-4 text-xs text-center text-n-slate-11">
            截至 {{ tieCheck.meta.as_of }} · 单位：元
          </div>
          <div class="flex flex-col max-w-3xl gap-3 mx-auto">
            <div
              v-for="check in tieCheck.payload"
              :key="check.key"
              class="p-4 border rounded-lg border-n-weak"
              :class="check.passed ? '' : 'bg-n-ruby-2 border-n-ruby-6'"
            >
              <div class="flex items-center gap-2">
                <div
                  class="size-4 shrink-0"
                  :class="
                    check.passed
                      ? 'i-lucide-circle-check text-n-teal-10'
                      : 'i-lucide-circle-alert text-n-ruby-10'
                  "
                />
                <span class="text-sm font-medium text-n-slate-12">
                  {{ check.label }}
                </span>
              </div>

              <div
                v-if="!check.passed && check.detail.diff_micros"
                class="mt-2 ml-6 font-mono text-xs text-n-ruby-11"
              >
                差额 {{ money(check.detail.diff_micros) }}
              </div>

              <p v-if="check.hint" class="mt-2 ml-6 text-xs text-n-amber-11">
                {{ check.hint }}
              </p>

              <ul
                v-if="check.detail.accounts?.length"
                class="mt-2 ml-6 flex flex-col gap-1.5"
              >
                <li
                  v-for="item in check.detail.accounts"
                  :key="item.id"
                  class="flex items-center gap-2 text-xs"
                >
                  <button
                    class="text-n-slate-12 hover:text-n-iris-11 hover:underline"
                    title="查看该科目明细账"
                    @click="
                      openLedger(
                        item.id,
                        monthStartOf(tieCheck.meta.as_of),
                        tieCheck.meta.as_of
                      )
                    "
                  >
                    <span class="font-mono text-n-slate-11">
                      {{ item.code }}
                    </span>
                    {{ item.name }}
                  </button>
                  <span class="text-n-slate-11">{{ item.category_label }}</span>
                  <span class="ml-auto font-mono text-n-slate-12">
                    {{ money(item.amount_micros) }}
                  </span>
                </li>
              </ul>

              <ul
                v-if="check.detail.uncovered_accounts?.length"
                class="mt-2 ml-6 flex flex-col gap-1.5"
              >
                <li
                  v-for="item in check.detail.uncovered_accounts"
                  :key="item.id"
                  class="flex items-center gap-2 text-xs"
                >
                  <span class="text-n-slate-11">利润表取不到</span>
                  <span class="font-mono text-n-slate-11">{{ item.code }}</span>
                  <span class="text-n-slate-12">{{ item.name }}</span>
                  <span class="ml-auto font-mono text-n-slate-12">
                    {{ money(item.amount_micros) }}
                  </span>
                </li>
              </ul>
            </div>
          </div>
          <p class="max-w-3xl mx-auto mt-4 text-xs text-n-slate-11">
            这几条按顺序看：第 1 条是账本身平不平，不平就别看后面的；第 2
            条不平时， 原因几乎总在第 3、4
            条——某个科目没设「资产负债表归属段」，它的余额既进不了报表、
            也不算进本年利润，于是凭空消失。点科目名可钻到明细账。
          </p>
        </template>
      </div>
    </div>
  </div>
</template>
