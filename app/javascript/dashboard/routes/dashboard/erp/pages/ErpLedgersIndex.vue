<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useErpLedgerAccountsStore } from 'dashboard/stores/erp/ledgerAccounts';
import { frontendURL } from 'dashboard/helper/URLHelper';
import ErpLedgerAPI from 'dashboard/api/erp/ledgers';

import Button from 'dashboard/components-next/button/Button.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import { exportRowsToExcel } from 'dashboard/helper/erpExcel';

// 账簿：科目余额表 / 明细账 / 维度明细账。数字全部按 POSTED 凭证实时算（草稿与作废不进账），
// 金额一律本位币。维度明细账是比金蝶强的地方：按客户/供应商/订单/部门/业务员切发生额。
const router = useRouter();
const route = useRoute();
const accountId = useMapGetter('getCurrentAccountId');
const accountStore = useErpLedgerAccountsStore();

const TABS = [
  { key: 'balances', label: '科目余额表' },
  { key: 'entries', label: '明细账' },
  { key: 'dimensions', label: '维度明细账' },
];
const DIMENSIONS = [
  { value: 'customer', label: '客户' },
  { value: 'supplier', label: '供应商' },
  { value: 'order', label: '订单' },
  { value: 'department', label: '部门' },
  { value: 'member', label: '业务员' },
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

const money = micros =>
  micros == null || micros === 0
    ? '—'
    : (micros / 1_000_000).toLocaleString('zh-CN', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      });
// 余额是按科目自身方向算的：为负说明实际余额在另一方（如损益类汇总行下面挂着收入和费用）。
// 金蝶同款处理——方向标记翻过来、金额取绝对值，别让财务看一列负数。
const dirLabel = d => (d === 'DEBIT' ? '借' : '贷');
const balanceDirection = row =>
  row.closing_micros < 0
    ? dirLabel(row.direction === 'DEBIT' ? 'CREDIT' : 'DEBIT')
    : dirLabel(row.direction);
const balanceMoney = micros => money(Math.abs(micros || 0));

const activeTab = ref('balances');
const from = ref(monthStart());
const to = ref(monthEnd());
const loading = ref(false);

const balanceRows = ref([]);
const balanceMeta = ref({});
const leavesOnly = ref(false);
const includeEmpty = ref(false);

const entryAccountId = ref('');
const entryRows = ref([]);
const entryMeta = ref({});

const dimension = ref('customer');
const dimensionAccountId = ref('');
const dimensionRows = ref([]);

const accountOptions = computed(() =>
  accountStore.getRecords.map(a => ({
    value: a.id,
    label: `${a.code} ${a.name}`,
  }))
);
const leafAccountOptions = computed(() =>
  accountStore.getRecords
    .filter(a => !a.isGroup)
    .map(a => ({ value: a.id, label: `${a.code} ${a.name}` }))
);

const loadBalances = async () => {
  loading.value = true;
  try {
    const { data } = await ErpLedgerAPI.balances({
      from: from.value,
      to: to.value,
      leaves_only: leavesOnly.value ? 'true' : '',
      include_empty: includeEmpty.value ? 'true' : '',
    });
    balanceRows.value = data.payload;
    balanceMeta.value = data.meta;
  } finally {
    loading.value = false;
  }
};

const loadEntries = async () => {
  if (!entryAccountId.value) {
    entryRows.value = [];
    return;
  }
  loading.value = true;
  try {
    const { data } = await ErpLedgerAPI.entries({
      ledger_account_id: entryAccountId.value,
      from: from.value,
      to: to.value,
    });
    entryRows.value = data.payload;
    entryMeta.value = data.meta;
  } finally {
    loading.value = false;
  }
};

const loadDimensions = async () => {
  loading.value = true;
  try {
    const { data } = await ErpLedgerAPI.dimensions({
      dimension: dimension.value,
      ledger_account_id: dimensionAccountId.value,
      from: from.value,
      to: to.value,
    });
    dimensionRows.value = data.payload;
  } finally {
    loading.value = false;
  }
};

const reload = () => {
  if (activeTab.value === 'balances') return loadBalances();
  if (activeTab.value === 'entries') return loadEntries();
  return loadDimensions();
};

const switchTab = key => {
  activeTab.value = key;
  reload();
};

// 余额表点科目 → 直接钻到该科目明细账。
const drillDown = row => {
  entryAccountId.value = row.id;
  activeTab.value = 'entries';
  loadEntries();
};

// 明细账点凭证号 → 跳凭证中心并按字号过滤。
const openVoucher = voucherNo => {
  router.push({
    path: frontendURL(`accounts/${accountId.value}/erp/vouchers`),
    query: { q: voucherNo },
  });
};

const dimensionLabel = computed(
  () => DIMENSIONS.find(d => d.value === dimension.value)?.label || ''
);

// 导出 Excel：导当前页签那张表，金额走数值（财务要在 Excel 里接着算）。
// 三张表口径不同，各自一套列——账簿是给事务所看的，列名要跟界面上一模一样。
const EXPORT_META = () => [
  { label: '期间', value: `${from.value} 至 ${to.value}` },
  { label: '口径', value: '仅已过账凭证，金额为本位币' },
  { label: '导出时间', value: new Date().toLocaleString() },
];

const BALANCE_COLUMNS = [
  { label: '科目编码', key: 'code' },
  { label: '科目名称', key: 'name' },
  { label: '方向', key: 'direction' },
  { label: '期初余额', key: 'opening_micros', money: true },
  { label: '本期借方', key: 'debit_micros', money: true },
  { label: '本期贷方', key: 'credit_micros', money: true },
  { label: '期末余额', key: 'closing_micros', money: true },
];
const ENTRY_COLUMNS = [
  { label: '日期', key: 'voucher_date' },
  { label: '凭证字号', key: 'voucher_no' },
  { label: '摘要', key: 'summary' },
  { label: '科目', key: 'account' },
  { label: '核算维度', key: 'dimension' },
  { label: '借方', key: 'debit', money: true },
  { label: '贷方', key: 'credit', money: true },
  { label: '余额', key: 'balance_micros', money: true },
];

// 明细账一行的维度：挂了哪个客户/供应商/订单/部门/业务员就写哪个，没挂就空着。
const entryDimension = row =>
  [
    row.crm_customer_name,
    row.mes_supplier_name,
    row.crm_sales_order_no,
    row.department_name,
    row.member_name,
  ]
    .filter(Boolean)
    .join(' / ');

const exportBalances = () =>
  exportRowsToExcel(
    {
      title: '科目余额表',
      meta: EXPORT_META(),
      columns: BALANCE_COLUMNS,
      rows: balanceRows.value.map(row => ({
        ...row,
        direction: balanceDirection(row),
        // 界面上负余额是「方向翻过来 + 取绝对值」，导出跟界面一致，否则两边数字对不上。
        opening_micros: Math.abs(row.opening_micros || 0),
        closing_micros: Math.abs(row.closing_micros || 0),
      })),
    },
    `科目余额表_${from.value}_${to.value}`
  );

const exportEntries = () =>
  exportRowsToExcel(
    {
      title: `明细账 ${entryMeta.value.ledger_account?.code || ''} ${entryMeta.value.ledger_account?.name || ''}`,
      meta: [
        ...EXPORT_META(),
        {
          label: '期初余额',
          value: (entryMeta.value.opening_micros || 0) / 1_000_000,
        },
        {
          label: '期末余额',
          value: (entryMeta.value.closing_micros || 0) / 1_000_000,
        },
      ],
      columns: ENTRY_COLUMNS,
      rows: entryRows.value.map(row => ({
        ...row,
        summary: row.summary || row.voucher_summary,
        account: `${row.ledger_account_code} ${row.ledger_account_name}`,
        dimension: entryDimension(row),
        debit: row.direction === 'DEBIT' ? row.base_amount_micros : null,
        credit: row.direction === 'CREDIT' ? row.base_amount_micros : null,
      })),
    },
    `明细账_${entryMeta.value.ledger_account?.code || ''}_${from.value}_${to.value}`
  );

const exportDimensions = () =>
  exportRowsToExcel(
    {
      title: `维度明细账（按${dimensionLabel.value}）`,
      meta: EXPORT_META(),
      columns: [
        { label: dimensionLabel.value, key: 'name' },
        { label: '借方发生', key: 'debit_micros', money: true },
        { label: '贷方发生', key: 'credit_micros', money: true },
        { label: '净额（借-贷）', key: 'net_micros', money: true },
      ],
      rows: dimensionRows.value.map(row => ({
        ...row,
        name: row.name || row.id,
        net_micros: (row.debit_micros || 0) - (row.credit_micros || 0),
      })),
    },
    `维度明细账_${dimensionLabel.value}_${from.value}_${to.value}`
  );

const currentRowCount = computed(() => {
  if (activeTab.value === 'balances') return balanceRows.value.length;
  if (activeTab.value === 'entries') return entryRows.value.length;
  return dimensionRows.value.length;
});

const exportExcel = () => {
  if (activeTab.value === 'balances') return exportBalances();
  if (activeTab.value === 'entries') return exportEntries();
  return exportDimensions();
};

// 带 ?account_id= 进来＝从别处（如报表页的资产负债表）钻某个科目的明细账，
// 顺带把期间也带过来，否则钻进来看的是本月、跟来源报表的截止日对不上。
onMounted(async () => {
  if (!accountStore.getRecords.length) await accountStore.get({});
  const { account_id: drillAccountId, from: qFrom, to: qTo } = route.query;
  if (qFrom) from.value = qFrom;
  if (qTo) to.value = qTo;
  if (drillAccountId) {
    entryAccountId.value = String(drillAccountId);
    activeTab.value = 'entries';
    return loadEntries();
  }
  return loadBalances();
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between gap-3 px-6 py-4 [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8">
      <div class="flex items-center gap-2">
        <div class="i-lucide-book-open-check size-5 text-n-iris-9" />
        <h1 class="text-xl font-semibold text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8">账簿</h1>
        <span
          v-if="activeTab === 'balances' && balanceMeta.total_debit_micros"
          class="px-2 py-0.5 text-xs rounded"
          :class="
            balanceMeta.balanced
              ? 'bg-n-teal-3 text-n-teal-11'
              : 'bg-n-ruby-3 text-n-ruby-11'
          "
        >
          {{ balanceMeta.balanced ? '试算平衡' : '借贷不平' }}
          {{ money(balanceMeta.total_debit_micros) }} /
          {{ money(balanceMeta.total_credit_micros) }}
        </span>
      </div>
      <div class="flex items-center gap-2">
        <DatePicker v-model="from" :clearable="false" trigger-class="w-36" />
        <span class="text-sm text-n-slate-11">至</span>
        <DatePicker v-model="to" :clearable="false" trigger-class="w-36" />
        <Button label="查询" color="iris" size="sm" @click="reload" />
        <Button
          label="导出 Excel"
          color="slate"
          variant="faded"
          size="sm"
          :disabled="!currentRowCount"
          @click="exportExcel"
        />
      </div>
    </div>

    <div class="flex items-center gap-2 px-6 pb-3 [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8">
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

      <template v-if="activeTab === 'balances'">
        <label class="flex items-center gap-2 ml-2 text-sm text-n-slate-11">
          <input
            v-model="leavesOnly"
            type="checkbox"
            class="w-4 h-4"
            @change="loadBalances"
          />
          只看末级科目
        </label>
        <label class="flex items-center gap-2 text-sm text-n-slate-11">
          <input
            v-model="includeEmpty"
            type="checkbox"
            class="w-4 h-4"
            @change="loadBalances"
          />
          显示无发生额科目
        </label>
      </template>

      <template v-else-if="activeTab === 'entries'">
        <div class="w-64 ml-2">
          <ComboBox
            v-model="entryAccountId"
            :options="accountOptions"
            placeholder="选科目（分类科目含下级）"
            @update:model-value="loadEntries"
          />
        </div>
      </template>

      <template v-else>
        <div class="ml-2">
          <SelectCard
            v-model="dimension"
            :options="DIMENSIONS"
            @update:model-value="loadDimensions"
          />
        </div>
        <div class="w-64">
          <ComboBox
            v-model="dimensionAccountId"
            :options="leafAccountOptions"
            placeholder="限定科目（可不选）"
            @update:model-value="loadDimensions"
          />
        </div>
      </template>
    </div>

    <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8">
      <div v-if="loading" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>

      <!-- 科目余额表 -->
      <table v-else-if="activeTab === 'balances'" class="w-full text-sm">
        <thead>
          <tr class="text-left text-n-slate-11 border-b border-n-weak">
            <th class="px-3 py-3 font-medium">科目</th>
            <th class="px-3 py-3 font-medium">方向</th>
            <th class="px-3 py-3 font-medium text-right">期初余额</th>
            <th class="px-3 py-3 font-medium text-right">本期借方</th>
            <th class="px-3 py-3 font-medium text-right">本期贷方</th>
            <th class="px-3 py-3 font-medium text-right">期末余额</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in balanceRows"
            :key="row.id"
            class="border-b cursor-pointer border-n-weak hover:bg-n-alpha-1"
            @click="drillDown(row)"
          >
            <td class="px-3 py-2 whitespace-nowrap">
              <span class="font-mono text-n-slate-11">{{ row.code }}</span>
              <span
                class="ml-1.5 text-n-slate-12"
                :class="{ 'font-medium': row.is_group }"
              >
                {{ row.name }}
              </span>
              <span v-if="row.is_group" class="ml-1 text-xs text-n-slate-10">
                汇总
              </span>
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ balanceDirection(row) }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-11">
              {{ balanceMoney(row.opening_micros) }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
              {{ money(row.debit_micros) }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
              {{ money(row.credit_micros) }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
              {{ balanceMoney(row.closing_micros) }}
            </td>
          </tr>
          <tr v-if="!balanceRows.length">
            <td colspan="6" class="px-3 py-10 text-center text-n-slate-11">
              该期间没有发生额。凭证过账后这里才有数（草稿凭证不进账）。
            </td>
          </tr>
        </tbody>
      </table>

      <!-- 明细账 -->
      <template v-else-if="activeTab === 'entries'">
        <div
          v-if="entryMeta.ledger_account"
          class="flex items-center gap-4 pb-3 text-sm text-n-slate-11"
        >
          <span>
            科目
            <span class="text-n-slate-12">
              {{ entryMeta.ledger_account.code }}
              {{ entryMeta.ledger_account.name }}
            </span>
          </span>
          <span>
            期初
            <span class="font-mono text-n-slate-12">
              {{ money(entryMeta.opening_micros) }}
            </span>
          </span>
          <span>
            期末
            <span class="font-mono text-n-slate-12">
              {{ money(entryMeta.closing_micros) }}
            </span>
          </span>
        </div>
        <table class="w-full text-sm">
          <thead>
            <tr class="text-left text-n-slate-11 border-b border-n-weak">
              <th class="px-3 py-3 font-medium">日期</th>
              <th class="px-3 py-3 font-medium">凭证字号</th>
              <th class="px-3 py-3 font-medium">摘要</th>
              <th class="px-3 py-3 font-medium">科目 / 维度</th>
              <th class="px-3 py-3 font-medium text-right">借方</th>
              <th class="px-3 py-3 font-medium text-right">贷方</th>
              <th class="px-3 py-3 font-medium text-right">余额</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in entryRows"
              :key="row.id"
              class="border-b border-n-weak hover:bg-n-alpha-1"
            >
              <td class="px-3 py-2 whitespace-nowrap text-n-slate-11">
                {{ row.voucher_date }}
              </td>
              <td class="px-3 py-2 whitespace-nowrap">
                <button
                  class="font-mono text-n-iris-11 hover:underline"
                  @click="openVoucher(row.voucher_no)"
                >
                  {{ row.voucher_no }}
                </button>
              </td>
              <td class="px-3 py-2 text-n-slate-12">
                {{ row.summary || row.voucher_summary || '—' }}
              </td>
              <td class="px-3 py-2 text-xs text-n-slate-11">
                {{ row.ledger_account_code }} {{ row.ledger_account_name }}
                <span v-if="row.crm_customer_name">
                  · {{ row.crm_customer_name }}
                </span>
                <span v-if="row.mes_supplier_name">
                  · {{ row.mes_supplier_name }}
                </span>
                <span v-if="row.crm_sales_order_no">
                  · {{ row.crm_sales_order_no }}
                </span>
              </td>
              <td class="px-3 py-2 font-mono text-right text-n-slate-12">
                {{
                  row.direction === 'DEBIT' ? money(row.base_amount_micros) : ''
                }}
              </td>
              <td class="px-3 py-2 font-mono text-right text-n-slate-12">
                {{
                  row.direction === 'CREDIT'
                    ? money(row.base_amount_micros)
                    : ''
                }}
              </td>
              <td class="px-3 py-2 font-mono text-right text-n-slate-12">
                {{ money(row.balance_micros) }}
              </td>
            </tr>
            <tr v-if="!entryRows.length">
              <td colspan="7" class="px-3 py-10 text-center text-n-slate-11">
                选一个科目查看逐笔明细，或从「科目余额表」点科目钻进来。
              </td>
            </tr>
          </tbody>
        </table>
      </template>

      <!-- 维度明细账 -->
      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left text-n-slate-11 border-b border-n-weak">
            <th class="px-3 py-3 font-medium">{{ dimensionLabel }}</th>
            <th class="px-3 py-3 font-medium text-right">借方发生</th>
            <th class="px-3 py-3 font-medium text-right">贷方发生</th>
            <th class="px-3 py-3 font-medium text-right">净额（借-贷）</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in dimensionRows"
            :key="row.id"
            class="border-b border-n-weak hover:bg-n-alpha-1"
          >
            <td class="px-3 py-2 text-n-slate-12">{{ row.name || row.id }}</td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
              {{ money(row.debit_micros) }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
              {{ money(row.credit_micros) }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
              {{ money(row.net_micros) }}
            </td>
          </tr>
          <tr v-if="!dimensionRows.length">
            <td colspan="4" class="px-3 py-10 text-center text-n-slate-11">
              该期间没有带「{{
                dimensionLabel
              }}」维度的分录。录凭证时在分录行选维度才会统计到。
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
