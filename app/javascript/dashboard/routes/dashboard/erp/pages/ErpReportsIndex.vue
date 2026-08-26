<script setup>
import { ref, computed, onMounted } from 'vue';
import ErpReportAPI from 'dashboard/api/erp/reports';
import { fmtMoney } from 'dashboard/helper/erpMoney';
import { printElement } from 'dashboard/helper/printHelper';

import Button from 'dashboard/components-next/button/Button.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';

// 财务报表：资产负债表（时点）/ 利润表 / 现金流量表（期间），实时按已记账凭证算。
// 资产负债表按传统左右分栏排（左资产、右负债与所有者权益），打印直接出这个版式。
const TABS = [
  { key: 'balance', label: '资产负债表' },
  { key: 'income', label: '利润表' },
  { key: 'cashflow', label: '现金流量表' },
];

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

const activeTab = ref('balance');
const asOf = ref(monthEnd());
const from = ref(monthStart());
const to = ref(monthEnd());
const loading = ref(false);

const balanceSheet = ref(null);
const incomeStatement = ref(null);
const cashFlow = ref(null);
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

const LOADERS = {
  balance: loadBalanceSheet,
  income: loadIncomeStatement,
  cashflow: loadCashFlow,
};

const reload = () => LOADERS[activeTab.value]();

const switchTab = key => {
  activeTab.value = key;
  reload();
};

const PRINT_TITLES = {
  balance: () => `资产负债表 ${asOf.value}`,
  income: () => `利润表 ${from.value} 至 ${to.value}`,
  cashflow: () => `现金流量表 ${from.value} 至 ${to.value}`,
};

const print = () =>
  printElement(reportRef.value, PRINT_TITLES[activeTab.value]());

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
        <template v-if="activeTab === 'balance'">
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
                    <span class="font-mono text-xs text-n-slate-11">
                      {{ line.code }}
                    </span>
                    {{ line.name }}
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
                    <span class="font-mono text-xs text-n-slate-11">
                      {{ line.code }}
                    </span>
                    {{ line.name }}
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
      </div>
    </div>
  </div>
</template>
