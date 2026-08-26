<script setup>
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useErpRole } from 'dashboard/composables/useErpRole';
import { useMapGetter } from 'dashboard/composables/store';
import { fmtMoney } from 'dashboard/helper/erpMoney';
import ErpFiscalPeriodAPI from 'dashboard/api/erp/fiscalPeriods';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import MonthPicker from 'dashboard/components-next/monthpicker/MonthPicker.vue';
import { useErpLedgerAccountsStore } from 'dashboard/stores/erp/ledgerAccounts';

// 期末结账：一个月一行，显示凭证数/待过账/借贷是否平，够条件才让结账。
// 结账会生成损益结转凭证并冻结该期间；反结账限管理员且留痕。
const { erpCan } = useErpRole();
const currentUser = useMapGetter('getCurrentUser');
const canClose = computed(() => erpCan('close'));
const isAdmin = computed(() => currentUser.value?.role === 'administrator');

const money = micros => (micros ? fmtMoney(micros) : '—');
// 汇总行的 0 要实打实显示 0.00，显示成「—」会让人以为没算。
const money0 = micros => fmtMoney(micros || 0);
const toMicros = value => Math.round(Number(value || 0) * 1_000_000);
const rows = ref([]);
const loading = ref(false);

const TABS = [
  { key: 'close', label: '期末结账' },
  { key: 'opening', label: '期初建账' },
  { key: 'reconcile', label: '两账对平' },
  { key: 'revalue', label: '期末调汇' },
  { key: 'baddebt', label: '坏账计提' },
  { key: 'yearend', label: '年度结转' },
];
const activeTab = ref('close');
const accountStore = useErpLedgerAccountsStore();

/* 期初建账：一张特殊凭证，借贷必平才让存 */
const openingRows = ref([]);
const openingAsOf = ref(new Date().toISOString().slice(0, 10));
const openingMeta = ref({});
const leafOptions = computed(() =>
  accountStore.getRecords
    .filter(a => !a.isGroup && a.isActive)
    .map(a => ({ value: a.id, label: `${a.code} ${a.name}` }))
);
// 合计按本位币算（外币行 × 汇率），与后端平衡校验同口径。
const baseOf = (value, rate) => Math.round(toMicros(value) * Number(rate || 1));
const openingDebit = computed(() =>
  openingRows.value.reduce(
    (sum, row) => sum + baseOf(row.debit, row.exchangeRate),
    0
  )
);
const openingCredit = computed(() =>
  openingRows.value.reduce(
    (sum, row) => sum + baseOf(row.credit, row.exchangeRate),
    0
  )
);
const openingBalanced = computed(
  () => openingDebit.value === openingCredit.value && openingDebit.value > 0
);

// 外币科目按外币录，汇率折本位币；本位币科目汇率留 1。
const addOpeningRow = () =>
  openingRows.value.push({
    ledgerAccountId: '',
    debit: '',
    credit: '',
    exchangeRate: 1,
  });

const loadOpening = async () => {
  if (!accountStore.getRecords.length) await accountStore.get({});
  const { data } = await ErpFiscalPeriodAPI.openingBalance();
  openingMeta.value = data;
  openingRows.value = (data.rows || []).map(row => ({
    ledgerAccountId: row.ledger_account_id,
    debit: row.debit_micros ? (row.debit_micros / 1_000_000).toFixed(2) : '',
    credit: row.credit_micros ? (row.credit_micros / 1_000_000).toFixed(2) : '',
    exchangeRate: Number(row.exchange_rate || 1),
  }));
  if (data.as_of) openingAsOf.value = data.as_of;
  if (!openingRows.value.length) addOpeningRow();
};
const removeOpeningRow = index => openingRows.value.splice(index, 1);
const saveOpening = async () => {
  try {
    const { data } = await ErpFiscalPeriodAPI.saveOpeningBalance({
      as_of: openingAsOf.value,
      rows: openingRows.value
        .filter(row => row.ledgerAccountId && (row.debit || row.credit))
        .map(row => ({
          ledger_account_id: row.ledgerAccountId,
          debit_micros: toMicros(row.debit),
          credit_micros: toMicros(row.credit),
          exchange_rate: row.exchangeRate || 1,
        })),
    });
    useAlert(`期初已保存，凭证 ${data.voucher_no}`);
    loadOpening();
  } catch (error) {
    useAlert(error?.response?.data?.error || '保存失败');
  }
};

/* 两账对平 */
const reconcileRows = ref([]);
const loadReconcile = async () => {
  const { data } = await ErpFiscalPeriodAPI.reconciliation();
  reconcileRows.value = data.payload;
};

/* 期末调汇：外币科目按期末汇率重算本位币，差额进汇兑损益 */
const revalPeriod = ref(new Date().toISOString().slice(0, 7));
const revalRates = ref({});
const revalRows = ref([]);
const revalMeta = ref(null);
const revalError = ref('');

const loadRevaluation = async () => {
  revalError.value = '';
  try {
    const { data } = await ErpFiscalPeriodAPI.revaluation({
      period: revalPeriod.value,
      rates: revalRates.value,
    });
    revalMeta.value = data.meta;
    revalRows.value = data.payload;
  } catch (error) {
    // 汇率没填全时后端会直接拒；把币种列表捞回来好渲染输入框。
    revalError.value = error?.response?.data?.error || '取数失败';
    revalRows.value = [];
  }
};

const doRevalue = async () => {
  try {
    const { data } = await ErpFiscalPeriodAPI.revalue({
      period: revalPeriod.value,
      rates: revalRates.value,
    });
    revalMeta.value = data.meta;
    revalRows.value = data.payload;
    useAlert(
      data.meta.voucher_no
        ? `调汇凭证 ${data.meta.voucher_no} 已生成（待过账）`
        : '各外币科目已按该汇率折算，没有调汇差额'
    );
  } catch (error) {
    useAlert(error?.response?.data?.error || '调汇失败');
  }
};

const load = async () => {
  loading.value = true;
  try {
    const { data } = await ErpFiscalPeriodAPI.get();
    rows.value = data.payload;
  } finally {
    loading.value = false;
  }
};

/* 坏账计提：按建账日账龄分段乘比例，只补「应有 − 已提」的差额 */
const badDebtPeriod = ref(new Date().toISOString().slice(0, 7));
const badDebtRates = ref({});
const badDebtRows = ref([]);
const badDebtMeta = ref(null);

const loadBadDebt = async () => {
  const { data } = await ErpFiscalPeriodAPI.badDebt({
    period: badDebtPeriod.value,
    rates: Object.keys(badDebtRates.value).length
      ? badDebtRates.value
      : undefined,
  });
  badDebtMeta.value = data.meta;
  badDebtRows.value = data.payload;
  // 首次进来用账套已存的比例回填输入框。
  if (!Object.keys(badDebtRates.value).length) {
    badDebtRates.value = { ...data.meta.rates };
  }
};

const doProvision = async () => {
  try {
    const { data } = await ErpFiscalPeriodAPI.provisionBadDebt({
      period: badDebtPeriod.value,
      rates: badDebtRates.value,
    });
    badDebtMeta.value = data.meta;
    badDebtRows.value = data.payload;
    useAlert(
      data.meta.voucher_no
        ? `凭证 ${data.meta.voucher_no} 已生成（待过账）`
        : '坏账准备余额已经等于应计提数，无需调整'
    );
  } catch (error) {
    useAlert(error?.response?.data?.error || '计提失败');
  }
};

/* 年度结转：本年利润 → 利润分配。年结是一次性重大动作，单独一步，不挂在 12 月结账里 */
const yearEndYear = ref(String(new Date().getFullYear()));
const surplusRate = ref('');
const yearEndMeta = ref(null);
const yearEndError = ref('');

const loadYearEnd = async () => {
  yearEndError.value = '';
  try {
    const { data } = await ErpFiscalPeriodAPI.yearEnd({
      year: yearEndYear.value,
      surplus_rate: surplusRate.value || 0,
    });
    yearEndMeta.value = data.meta;
  } catch (error) {
    yearEndError.value = error?.response?.data?.error || '取数失败';
    yearEndMeta.value = null;
  }
};

const doCloseYear = async () => {
  try {
    const { data } = await ErpFiscalPeriodAPI.closeYear({
      year: yearEndYear.value,
      surplus_rate: surplusRate.value || 0,
    });
    yearEndMeta.value = data.meta;
    useAlert(`${yearEndYear.value} 年度已结转，凭证 ${data.meta.voucher_no}`);
  } catch (error) {
    useAlert(error?.response?.data?.error || '年结失败');
  }
};

const doReopenYear = async () => {
  try {
    const { data } = await ErpFiscalPeriodAPI.reopenYear({
      year: yearEndYear.value,
    });
    yearEndMeta.value = data.meta;
    useAlert(`${yearEndYear.value} 年度已反年结`);
  } catch (error) {
    useAlert(error?.response?.data?.error || '反年结失败');
  }
};

const switchTab = async key => {
  activeTab.value = key;
  if (key === 'close') await load();
  if (key === 'yearend') await loadYearEnd();
  if (key === 'baddebt') await loadBadDebt();
  if (key === 'opening') await loadOpening();
  if (key === 'reconcile') await loadReconcile();
  if (key === 'revalue') await loadRevaluation();
};

const closable = row =>
  canClose.value &&
  row.status === 'OPEN' &&
  row.draft_count === 0 &&
  row.balanced;

const doClose = async row => {
  try {
    const { data } = await ErpFiscalPeriodAPI.close(row.period);
    useAlert(
      data.closing_voucher_no
        ? `${row.period} 已结账，结转凭证 ${data.closing_voucher_no}`
        : `${row.period} 已结账（该期间无损益发生，未生成结转凭证）`
    );
    load();
  } catch (error) {
    useAlert(error?.response?.data?.error || '结账失败');
  }
};

const confirmRef = ref(null);
const reopening = ref(null);
const askReopen = row => {
  reopening.value = row;
  confirmRef.value?.open();
};
const doReopen = async () => {
  try {
    await ErpFiscalPeriodAPI.reopen(reopening.value.period);
    useAlert(`${reopening.value.period} 已反结账，结转凭证已撤销`);
    load();
  } catch (error) {
    useAlert(error?.response?.data?.error || '反结账失败');
  }
};

onMounted(load);
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between gap-3 px-6 py-4">
      <div class="flex items-center gap-2">
        <div class="i-lucide-calendar-check size-5 text-n-iris-9" />
        <h1 class="text-xl font-semibold text-n-slate-12">期末结账</h1>
        <span class="text-sm text-n-slate-11">
          结账＝结转损益到本年利润 + 冻结该期间凭证
        </span>
      </div>
      <Button label="刷新" color="slate" size="sm" @click="load" />
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

    <!-- 期初建账 -->
    <div
      v-if="activeTab === 'opening'"
      class="flex-1 min-h-0 px-6 pb-6 overflow-auto"
    >
      <div class="flex flex-wrap items-center gap-3 mb-3">
        <span class="text-sm text-n-slate-11">启用日期</span>
        <DatePicker
          v-model="openingAsOf"
          :clearable="false"
          trigger-class="w-36"
        />
        <span class="text-sm text-n-slate-11">
          借方合计
          <span class="font-mono text-n-slate-12">{{
            money(openingDebit)
          }}</span>
          · 贷方合计
          <span class="font-mono text-n-slate-12">
            {{ money(openingCredit) }}
          </span>
        </span>
        <span
          class="px-2 py-0.5 text-xs rounded"
          :class="
            openingBalanced
              ? 'bg-n-teal-3 text-n-teal-11'
              : 'bg-n-ruby-3 text-n-ruby-11'
          "
        >
          {{ openingBalanced ? '借贷平衡' : '借贷不平' }}
        </span>
        <Button
          label="加一行"
          color="slate"
          variant="faded"
          size="sm"
          @click="addOpeningRow"
        />
        <Button
          label="保存期初"
          color="iris"
          size="sm"
          :disabled="!openingBalanced"
          @click="saveOpening"
        />
        <span v-if="openingMeta.voucher_no" class="text-xs text-n-slate-10">
          当前期初凭证 {{ openingMeta.voucher_no }}
        </span>
      </div>

      <div class="flex flex-col max-w-4xl gap-2">
        <div
          v-for="(row, index) in openingRows"
          :key="index"
          class="grid items-center grid-cols-12 gap-2"
        >
          <div class="col-span-5">
            <ComboBox
              v-model="row.ledgerAccountId"
              :options="leafOptions"
              placeholder="选末级科目"
            />
          </div>
          <div class="col-span-2">
            <Input
              v-model="row.debit"
              size="sm"
              type="number"
              placeholder="借方期初"
            />
          </div>
          <div class="col-span-2">
            <Input
              v-model="row.credit"
              size="sm"
              type="number"
              placeholder="贷方期初"
            />
          </div>
          <div class="col-span-1">
            <Input
              v-model="row.exchangeRate"
              size="sm"
              type="number"
              placeholder="汇率"
            />
          </div>
          <button
            class="flex items-center justify-center col-span-1 size-8 text-n-slate-11 hover:text-n-ruby-11"
            @click="removeOpeningRow(index)"
          >
            <div class="i-lucide-trash-2 size-4" />
          </button>
        </div>
      </div>
      <p class="mt-4 text-xs text-n-slate-10">
        期初会生成一张已记账的「期初建账」凭证（日期＝启用日），账簿与报表的期初余额由它带出；重新保存＝整张替换。
      </p>
    </div>

    <!-- 两账对平 -->
    <div
      v-else-if="activeTab === 'reconcile'"
      class="flex-1 min-h-0 px-6 pb-6 overflow-auto"
    >
      <table class="w-full max-w-3xl text-sm">
        <thead>
          <tr class="text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-3 py-3 font-medium">对账项</th>
            <th class="px-3 py-3 font-medium text-right">业务台账</th>
            <th class="px-3 py-3 font-medium text-right">会计总账</th>
            <th class="px-3 py-3 font-medium text-right">差额</th>
            <th class="px-3 py-3 font-medium">结果</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in reconcileRows"
            :key="row.key"
            class="border-b border-n-weak"
          >
            <td class="px-3 py-2 text-n-slate-12">{{ row.label }}</td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
              {{ money(row.business_micros) }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
              {{ money(row.ledger_micros) }}
            </td>
            <td
              class="px-3 py-2 font-mono text-right"
              :class="row.matched ? 'text-n-slate-11' : 'text-n-ruby-11'"
            >
              {{ money(row.diff_micros) }}
            </td>
            <td class="px-3 py-2">
              <span
                class="px-2 py-0.5 text-xs rounded whitespace-nowrap"
                :class="
                  row.matched
                    ? 'bg-n-teal-3 text-n-teal-11'
                    : 'bg-n-ruby-3 text-n-ruby-11'
                "
              >
                {{ row.matched ? '对平' : '有差异' }}
              </span>
              <span v-if="row.note" class="block mt-1 text-xs text-n-slate-10">
                {{ row.note }}
              </span>
            </td>
          </tr>
        </tbody>
      </table>
      <p class="mt-4 text-xs text-n-slate-10">
        每月结账前这三行都应为「对平」。有差异通常是单据没生成凭证、或凭证记错了科目。
      </p>
    </div>

    <!-- 期末调汇 -->
    <div
      v-else-if="activeTab === 'revalue'"
      class="flex-1 min-h-0 px-6 pb-6 overflow-auto"
    >
      <div class="flex flex-wrap items-center gap-2 mb-4">
        <span class="text-sm text-n-slate-11">会计期间</span>
        <MonthPicker v-model="revalPeriod" :clearable="false" />
        <template
          v-for="currency in revalMeta?.currencies || []"
          :key="currency"
        >
          <span class="text-sm text-n-slate-11">{{ currency }} 期末汇率</span>
          <div class="w-28">
            <Input
              v-model="revalRates[currency]"
              size="sm"
              type="number"
              placeholder="如 7.1200"
            />
          </div>
        </template>
        <Button label="试算" color="slate" size="sm" @click="loadRevaluation" />
        <Button
          v-if="canClose"
          label="生成调汇凭证"
          color="iris"
          size="sm"
          :disabled="!revalMeta?.rates_ready"
          @click="doRevalue"
        />
      </div>

      <p v-if="revalError" class="mb-3 text-sm text-n-ruby-11">
        {{ revalError }}
      </p>
      <p
        v-else-if="revalMeta && !revalMeta.rates_ready"
        class="mb-3 text-sm text-n-slate-11"
      >
        填入各外币的期末汇率后点「试算」，先看差额再决定是否生成凭证。
      </p>

      <table v-if="revalRows.length" class="w-full max-w-5xl text-sm">
        <thead>
          <tr class="text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-3 py-3 font-medium">科目</th>
            <th class="px-3 py-3 font-medium">核算单位</th>
            <th class="px-3 py-3 font-medium text-right">原币余额</th>
            <th class="px-3 py-3 font-medium text-right">账面本位币</th>
            <th class="px-3 py-3 font-medium text-right">期末应有</th>
            <th class="px-3 py-3 font-medium text-right">调汇差额</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="(row, index) in revalRows"
            :key="`${row.ledger_account_id}-${row.party_id || index}`"
            class="border-b border-n-weak"
          >
            <td class="px-3 py-2 text-n-slate-12">
              <span class="font-mono text-xs text-n-slate-11">
                {{ row.code }}
              </span>
              {{ row.name }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ row.party_name || '—' }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
              {{ row.currency }} {{ money(row.original_micros) }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-11">
              {{ money(row.booked_micros) }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-11">
              {{ money(row.should_be_micros) }}
            </td>
            <td
              class="px-3 py-2 font-mono text-right"
              :class="row.diff_micros ? 'text-n-amber-11' : 'text-n-slate-11'"
            >
              {{ money(row.diff_micros) }}
            </td>
          </tr>
          <tr class="font-semibold">
            <td class="px-3 py-2 text-n-slate-12" colspan="5">
              净调汇差额（进汇兑损益）
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
              {{ money(revalMeta?.total_diff_micros) }}
            </td>
          </tr>
        </tbody>
      </table>

      <p class="mt-4 text-xs text-n-slate-10">
        调汇只调本位币、不动原币；生成的是「待过账」凭证，记账仍要财务点过账。
        同一汇率重复调汇不会翻倍——账面调平后差额自然为 0。
      </p>
    </div>

    <!-- 坏账计提（账龄分析法） -->
    <div
      v-else-if="activeTab === 'baddebt'"
      class="flex-1 min-h-0 px-6 pb-6 overflow-auto"
    >
      <div class="flex flex-wrap items-center gap-2 mb-4">
        <span class="text-sm text-n-slate-11">会计期间</span>
        <MonthPicker v-model="badDebtPeriod" :clearable="false" />
        <Button label="试算" color="slate" size="sm" @click="loadBadDebt" />
        <Button
          v-if="canClose"
          label="生成计提凭证"
          color="iris"
          size="sm"
          @click="doProvision"
        />
      </div>

      <div
        v-if="badDebtMeta"
        class="flex flex-wrap items-center gap-3 p-3 mb-4 rounded-lg bg-n-alpha-1"
      >
        <span class="text-sm text-n-slate-11">计提比例（%）</span>
        <div
          v-for="bucket in badDebtMeta.buckets"
          :key="bucket.key"
          class="flex items-center gap-1.5"
        >
          <span class="text-xs whitespace-nowrap text-n-slate-11">
            {{ bucket.label }}
          </span>
          <div class="w-20">
            <Input v-model="badDebtRates[bucket.key]" size="sm" type="number" />
          </div>
        </div>
      </div>

      <table v-if="badDebtRows.length" class="w-full max-w-5xl text-sm">
        <thead>
          <tr class="text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-3 py-3 font-medium">客户</th>
            <th class="px-3 py-3 font-medium text-right">未结应收</th>
            <th
              v-for="bucket in badDebtMeta.buckets"
              :key="bucket.key"
              class="px-3 py-3 font-medium text-right whitespace-nowrap"
            >
              {{ bucket.label }}
            </th>
            <th class="px-3 py-3 font-medium text-right">应计提</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in badDebtRows"
            :key="row.party_id"
            class="border-b border-n-weak"
          >
            <td class="px-3 py-2 text-n-slate-12">{{ row.party_name }}</td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
              {{ money(row.total_micros) }}
            </td>
            <td
              v-for="bucket in badDebtMeta.buckets"
              :key="bucket.key"
              class="px-3 py-2 font-mono text-right text-n-slate-11"
            >
              {{ money(row.cells[bucket.key].base_micros) }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
              {{ money(row.provision_micros) }}
            </td>
          </tr>
        </tbody>
      </table>

      <div
        v-if="badDebtMeta"
        class="flex flex-wrap gap-6 max-w-5xl px-3 py-3 mt-3 text-sm border-t border-n-weak"
      >
        <span class="text-n-slate-11">
          期末应有坏账准备
          <span class="font-mono text-n-slate-12">
            {{ money0(badDebtMeta.required_micros) }}
          </span>
        </span>
        <span class="text-n-slate-11">
          已计提
          <span class="font-mono text-n-slate-12">
            {{ money0(badDebtMeta.booked_micros) }}
          </span>
        </span>
        <span class="font-medium text-n-slate-11">
          本次{{ badDebtMeta.adjustment_micros < 0 ? '转回' : '计提' }}
          <span class="font-mono text-n-slate-12">
            {{ money0(Math.abs(badDebtMeta.adjustment_micros)) }}
          </span>
        </span>
      </div>

      <p class="mt-4 text-xs text-n-slate-10">
        账龄按「建账日」算（不是到期日）。坏账准备是余额科目，本次只补「应有 −
        已提」的差额，
        应有数变小时会自动生成转回分录，重复试算不会翻倍。计提比例是公司会计政策，改了要一贯执行。
      </p>
    </div>

    <!-- 年度结转 -->
    <div
      v-else-if="activeTab === 'yearend'"
      class="flex-1 min-h-0 px-6 pb-6 overflow-auto"
    >
      <div class="flex flex-wrap items-center gap-2 mb-4">
        <span class="text-sm text-n-slate-11">会计年度</span>
        <div class="w-24">
          <Input v-model="yearEndYear" size="sm" type="number" />
        </div>
        <span class="text-sm text-n-slate-11">法定盈余公积（%）</span>
        <div class="w-20">
          <Input
            v-model="surplusRate"
            size="sm"
            type="number"
            placeholder="不提"
          />
        </div>
        <Button label="试算" color="slate" size="sm" @click="loadYearEnd" />
        <Button
          v-if="canClose && yearEndMeta && !yearEndMeta.voucher_no"
          label="执行年度结转"
          color="iris"
          size="sm"
          @click="doCloseYear"
        />
        <Button
          v-if="isAdmin && yearEndMeta && yearEndMeta.voucher_no"
          label="反年结"
          color="ruby"
          variant="faded"
          size="sm"
          @click="doReopenYear"
        />
      </div>

      <p v-if="yearEndError" class="mb-3 text-sm text-n-ruby-11">
        {{ yearEndError }}
      </p>

      <template v-if="yearEndMeta">
        <p
          v-if="yearEndMeta.unclosed_periods.length"
          class="mb-3 text-sm text-n-amber-11"
        >
          {{ yearEndMeta.unclosed_periods.join('、') }}
          还没结账，全年 12 个月都结完才能年结。
        </p>
        <p
          v-else-if="yearEndMeta.voucher_no"
          class="mb-3 text-sm text-n-teal-11"
        >
          {{ yearEndMeta.year }} 年度已结转，凭证 {{ yearEndMeta.voucher_no }}。
        </p>

        <table class="w-full max-w-2xl text-sm">
          <tbody>
            <tr class="border-b border-n-weak">
              <td class="px-3 py-2 text-n-slate-12">
                本年利润（{{ yearEndMeta.year }} 年度）
              </td>
              <td class="px-3 py-2 font-mono text-right text-n-slate-12">
                {{ money0(yearEndMeta.profit_micros) }}
              </td>
            </tr>
            <tr class="border-b border-n-weak">
              <td class="px-3 py-2 text-n-slate-11">
                减：提取法定盈余公积
                <span class="text-xs text-n-slate-10">
                  {{ Number(yearEndMeta.surplus_rate) }}%
                </span>
              </td>
              <td class="px-3 py-2 font-mono text-right text-n-slate-11">
                {{ money0(yearEndMeta.surplus_micros) }}
              </td>
            </tr>
            <tr class="font-semibold">
              <td class="px-3 py-2 text-n-slate-12">转入未分配利润</td>
              <td class="px-3 py-2 font-mono text-right text-n-slate-12">
                {{ money0(yearEndMeta.retained_micros) }}
              </td>
            </tr>
          </tbody>
        </table>
      </template>

      <p class="mt-4 text-xs text-n-slate-10">
        月度结账只把损益结转到「本年利润」，本年利润自己不会归零；不做年结，第二年起
        资产负债表上的本年利润里就混着以前年度的利润、未分配利润永远是 0。
        年结是单独一步、不挂在 12
        月结账里；做完之后要反结该年度的月份，得先反年结。
        法定盈余公积留空就是不提。
      </p>
    </div>

    <!-- 期末结账 -->
    <div v-else class="flex-1 min-h-0 px-6 pb-6 overflow-auto">
      <div v-if="loading" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <table v-else class="w-full max-w-5xl text-sm">
        <thead>
          <tr class="text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-3 py-3 font-medium">会计期间</th>
            <th class="px-3 py-3 font-medium text-right">凭证数</th>
            <th class="px-3 py-3 font-medium text-right">待过账</th>
            <th class="px-3 py-3 font-medium text-right">借方合计</th>
            <th class="px-3 py-3 font-medium text-right">贷方合计</th>
            <th class="px-3 py-3 font-medium">试算</th>
            <th class="px-3 py-3 font-medium">期末事项</th>
            <th class="px-3 py-3 font-medium">状态</th>
            <th class="px-3 py-3 font-medium text-right">操作</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in rows"
            :key="row.period"
            class="border-b border-n-weak hover:bg-n-alpha-1"
          >
            <td class="px-3 py-2 font-mono text-n-slate-12">
              {{ row.period }}
            </td>
            <td class="px-3 py-2 text-right text-n-slate-11">
              {{ row.voucher_count }}
            </td>
            <td
              class="px-3 py-2 text-right"
              :class="row.draft_count ? 'text-n-amber-11' : 'text-n-slate-11'"
            >
              {{ row.draft_count }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
              {{ money(row.debit_micros) }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
              {{ money(row.credit_micros) }}
            </td>
            <td class="px-3 py-2">
              <span
                class="px-2 py-0.5 text-xs rounded whitespace-nowrap"
                :class="
                  row.balanced
                    ? 'bg-n-teal-3 text-n-teal-11'
                    : 'bg-n-ruby-3 text-n-ruby-11'
                "
              >
                {{ row.balanced ? '平' : '不平' }}
              </span>
            </td>
            <td class="px-3 py-2">
              <div v-if="row.checklist.length" class="flex flex-wrap gap-1">
                <span
                  v-for="item in row.checklist"
                  :key="item.key"
                  class="px-2 py-0.5 text-xs rounded whitespace-nowrap"
                  :class="
                    item.done
                      ? 'bg-n-teal-3 text-n-teal-11'
                      : 'bg-n-amber-3 text-n-amber-11'
                  "
                  :title="item.done ? '本期已做' : item.hint"
                >
                  {{ item.done ? '✓' : '待' }} {{ item.label }}
                </span>
              </div>
              <span v-else class="text-xs text-n-slate-10">—</span>
            </td>
            <td class="px-3 py-2">
              <span
                class="px-2 py-0.5 text-xs rounded whitespace-nowrap"
                :class="
                  row.status === 'CLOSED'
                    ? 'bg-n-slate-3 text-n-slate-11'
                    : 'bg-n-iris-3 text-n-iris-11'
                "
              >
                {{ row.status === 'CLOSED' ? '已结账' : '未结账' }}
              </span>
              <span
                v-if="row.closing_voucher_no"
                class="ml-1 text-xs text-n-slate-10"
              >
                {{ row.closing_voucher_no }}
              </span>
            </td>
            <td class="px-3 py-2">
              <div class="flex items-center justify-end gap-1">
                <Button
                  v-if="row.status === 'OPEN'"
                  label="结账"
                  color="iris"
                  variant="ghost"
                  size="xs"
                  :disabled="!closable(row)"
                  @click="doClose(row)"
                />
                <Button
                  v-else-if="isAdmin"
                  label="反结账"
                  color="ruby"
                  variant="ghost"
                  size="xs"
                  @click="askReopen(row)"
                />
              </div>
            </td>
          </tr>
          <tr v-if="!rows.length">
            <td colspan="9" class="px-3 py-10 text-center text-n-slate-11">
              还没有凭证，无需结账。
            </td>
          </tr>
        </tbody>
      </table>

      <p class="mt-4 text-xs text-n-slate-10">
        结账条件：该期间没有待过账凭证、且借贷试算平衡。结账后凭证冻结，需管理员反结账才能改。
        「期末事项」是提示不是硬拦——做不做是会计政策，但结完账再想起来就得反结账重来。
      </p>
    </div>

    <Dialog
      ref="confirmRef"
      type="alert"
      width="sm"
      confirm-button-color="ruby"
      title="反结账"
      :description="`确定把 ${reopening?.period || ''} 重新打开？结转凭证会被撤销，该期间凭证恢复可改，操作会留痕。`"
      confirm-label="反结账"
      @confirm="doReopen"
    />
  </div>
</template>
