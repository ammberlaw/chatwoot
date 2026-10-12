<script setup>
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useErpRole } from 'dashboard/composables/useErpRole';
import { useMapGetter } from 'dashboard/composables/store';
import { fmtMoney } from 'dashboard/helper/erpMoney';
import ErpFiscalPeriodAPI from 'dashboard/api/erp/fiscalPeriods';
import ErpStockLayerAPI from 'dashboard/api/erp/stockLayers';
import { downloadBlob } from 'dashboard/helper/erpDownload';
import { exportRowsToExcel } from 'dashboard/helper/erpExcel';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import MonthPicker from 'dashboard/components-next/monthpicker/MonthPicker.vue';
import ErpDimensionFields from 'dashboard/components-next/erp/ErpDimensionFields.vue';
import { useErpLedgerAccountsStore } from 'dashboard/stores/erp/ledgerAccounts';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
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
  { key: 'stock', label: '成品存货' },
  { key: 'reconcile', label: '两账对平' },
  { key: 'revalue', label: '期末调汇' },
  { key: 'baddebt', label: '坏账计提' },
  { key: 'yearend', label: '年度结转' },
];
const activeTab = ref('close');

/* ---------------- 成品存货（FIFO 批次层） ---------------- */
// 金蝶用先进先出，我们照同一口径：每次入库一层，出库按进货先后逐层扣。
// 这一页给财务看当前批次与账面价值，并把金蝶导出的期初批次导进来。
const stockLayers = ref([]);
const stockMeta = ref({});
const stockIncludeEmpty = ref(false);
const stockImporting = ref(false);
const stockFileRef = ref(null);

const loadStockLayers = async () => {
  loading.value = true;
  try {
    const { data } = await ErpStockLayerAPI.get({
      include_empty: stockIncludeEmpty.value ? 'true' : undefined,
      per_page: 100,
    });
    stockLayers.value = data.payload;
    stockMeta.value = data.meta;
  } finally {
    loading.value = false;
  }
};

const downloadStockTemplate = async () => {
  const { data } = await ErpStockLayerAPI.importTemplate();
  downloadBlob(data, '成品期初存货模板.csv');
};

const onStockFile = async event => {
  const file = event.target.files?.[0];
  if (!file) return;
  stockImporting.value = true;
  try {
    const { data } = await ErpStockLayerAPI.import(file);
    const r = data.payload;
    useAlert(`已导入 ${r.created} 条期初批次，合计 ${r.total_qty} 件`);
    await loadStockLayers();
  } catch (e) {
    useAlert(e?.response?.data?.error || '导入失败');
  } finally {
    stockImporting.value = false;
    event.target.value = '';
  }
};
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
// 往来科目的期初要挂到具体客户/供应商上，否则账龄和对账单从第一天就查不出来。
// 判定口径与凭证录入页一致（应收→客户、应付→供应商）。
const accountById = id =>
  accountStore.getRecords.find(a => a.id === Number(id));
const REQUIRED_DIMENSION = { RECEIVABLE: 'customer', PAYABLE: 'supplier' };
const requiredDimensionOf = row =>
  REQUIRED_DIMENSION[accountById(row.ledgerAccountId)?.accountType] || '';
const dimensionsOf = row => accountById(row.ledgerAccountId)?.dimensions || [];
// 往来科目没挂单位就别让存——后端也会拦，但在这里拦能直接指出是哪一行。
const openingMissingParty = computed(() =>
  openingRows.value.some(row => {
    const dim = requiredDimensionOf(row);
    if (!dim) return false;
    if (!row.debit && !row.credit) return false;
    return !(dim === 'customer' ? row.crmCustomerId : row.mesSupplierId);
  })
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
    crmCustomerId: '',
    mesSupplierId: '',
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
    crmCustomerId: row.crm_customer_id || '',
    // 名字给下拉做回显用：不给的话重进页面只剩一个 id，框里是空的。
    crmCustomerName: row.crm_customer_name || '',
    mesSupplierId: row.mes_supplier_id || '',
    mesSupplierName: row.mes_supplier_name || '',
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
          crm_customer_id: row.crmCustomerId || null,
          mes_supplier_id: row.mesSupplierId || null,
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

/* 导出：两账对平与成品存货都是要留档、要给审计看的表 */
const exporting = ref(false);

const exportReconcile = () =>
  exportRowsToExcel(
    {
      title: '两账对平（业务台账 vs 会计总账）',
      meta: [
        { label: '导出时间', value: new Date().toLocaleString() },
        {
          label: '结论',
          value: reconcileRows.value.every(row => row.matched)
            ? '全部对平'
            : `${reconcileRows.value.filter(row => !row.matched).length} 项有差异`,
        },
      ],
      columns: [
        { label: '对账项', key: 'label' },
        { label: '业务台账', key: 'business_micros', money: true },
        { label: '会计总账', key: 'ledger_micros', money: true },
        { label: '差额', key: 'diff_micros', money: true },
        { label: '结果', key: 'result' },
        { label: '备注', key: 'note' },
      ],
      rows: reconcileRows.value.map(row => ({
        ...row,
        result: row.matched ? '对平' : '有差异',
      })),
    },
    `两账对平_${new Date().toISOString().slice(0, 10)}`
  );

// 批次层后端每页封顶 100（刻意防一把拉全表），导出就翻页拉完——
// 只导第一页的存货表拿去盘点，少的那些货就成了盘亏。
const STOCK_EXPORT_MAX_PAGES = 50;
const fetchAllStockLayers = async () => {
  const layers = [];
  for (let page = 1; page <= STOCK_EXPORT_MAX_PAGES; page += 1) {
    // eslint-disable-next-line no-await-in-loop
    const { data } = await ErpStockLayerAPI.get({
      include_empty: stockIncludeEmpty.value ? 'true' : undefined,
      per_page: 100,
      page,
    });
    layers.push(...data.payload);
    if (!data.payload.length || layers.length >= (data.meta?.count ?? 0)) break;
  }
  return layers;
};

const exportStock = async () => {
  const layers = await fetchAllStockLayers();
  exportRowsToExcel(
    {
      title: '成品存货批次（FIFO）',
      meta: [
        { label: '导出时间', value: new Date().toLocaleString() },
        { label: '批次数', value: layers.length },
        { label: '结存数量', value: stockMeta.value.qty ?? '' },
        {
          label: '账面价值',
          value: (stockMeta.value.amount_micros || 0) / 1_000_000,
        },
        {
          label: '范围',
          value: stockIncludeEmpty.value ? '含已耗尽批次' : '仅有余量批次',
        },
      ],
      columns: [
        { label: '入库日期', key: 'received_at' },
        { label: '成品', key: 'product_name' },
        { label: '编码', key: 'product_sku' },
        { label: '仓库', key: 'warehouse_name' },
        { label: '入库数', key: 'qty_in' },
        { label: '剩余', key: 'qty_remaining' },
        { label: '单位成本', key: 'unit_cost_micros', money: true },
        { label: '结存金额', key: 'amount_remaining_micros', money: true },
        { label: '来源', key: 'remark' },
      ],
      rows: layers.map(layer => ({
        ...layer,
        received_at: (layer.received_at || '').slice(0, 10),
      })),
    },
    `成品存货批次_${new Date().toISOString().slice(0, 10)}`
  );
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

// 其余几个页签也导：期末结账看各期间的凭证/试算/状态，期末调汇和坏账计提
// 是要留档给审计的计算过程，年度结转/期初建账没有行表（是操作面板），不出按钮。
const stamp = () => new Date().toLocaleString('sv').slice(0, 16);

const exportClose = () =>
  exportRowsToExcel(
    {
      title: '会计期间结账情况',
      meta: [
        { label: '导出时间', value: stamp() },
        { label: '期间数', value: rows.value.length },
      ],
      columns: [
        { label: '会计期间', key: 'period' },
        { label: '凭证数', key: 'voucher_count', num: true },
        { label: '待过账', key: 'draft_count', num: true },
        { label: '借方合计', key: 'debit_micros', money: true },
        { label: '贷方合计', key: 'credit_micros', money: true },
        { label: '试算', key: 'balanced_label' },
        { label: '期末事项', key: 'checklist_label' },
        { label: '状态', key: 'status_label' },
      ],
      rows: rows.value.map(row => ({
        ...row,
        balanced_label: row.balanced ? '平' : '不平',
        // 勾选项摊成一串「✓已做 / 待未做」，Excel 里装不下徽章。
        checklist_label: (row.checklist || [])
          .map(item => `${item.done ? '✓' : '待'}${item.label}`)
          .join(' / '),
        status_label: row.status === 'CLOSED' ? '已结账' : '未结账',
      })),
    },
    `会计期间结账情况_${stamp().slice(0, 10)}`
  );

const exportReval = () =>
  exportRowsToExcel(
    {
      title: '期末调汇',
      meta: [
        { label: '导出时间', value: stamp() },
        { label: '期间', value: revalPeriod.value },
        { label: '单位', value: '元（本位币）' },
        { label: '行数', value: revalRows.value.length },
      ],
      columns: [
        { label: '科目编码', key: 'code' },
        { label: '科目名称', key: 'name' },
        { label: '核算单位', key: 'party_name' },
        { label: '币种', key: 'currency' },
        { label: '原币余额', key: 'original_micros', money: true },
        { label: '账面本位币', key: 'booked_micros', money: true },
        { label: '期末应有', key: 'should_be_micros', money: true },
        { label: '调汇差额', key: 'diff_micros', money: true },
      ],
      rows: revalRows.value,
    },
    `期末调汇_${revalPeriod.value}`
  );

const exportBadDebt = () =>
  exportRowsToExcel(
    {
      title: '坏账计提',
      meta: [
        { label: '导出时间', value: stamp() },
        { label: '单位', value: '元（本位币）' },
        { label: '客户数', value: badDebtRows.value.length },
      ],
      columns: [
        { label: '客户', key: 'party_name' },
        { label: '未结应收', key: 'total_micros', money: true },
        // 账龄桶是动态列（口径不同桶不同），照 meta.buckets 现搭。
        ...(badDebtMeta.value?.buckets || []).map(bucket => ({
          label: bucket.label,
          key: bucket.key,
          money: true,
        })),
        { label: '应计提', key: 'provision_micros', money: true },
      ],
      // cells 是按桶 key 的对象，摊平到行上才喂得进列定义。
      rows: badDebtRows.value.map(row => ({
        party_name: row.party_name,
        total_micros: row.total_micros,
        ...row.cells,
        provision_micros: row.provision_micros,
      })),
    },
    `坏账计提_${stamp().slice(0, 10)}`
  );

const EXPORTERS = {
  close: exportClose,
  reconcile: exportReconcile,
  stock: exportStock,
  revalue: exportReval,
  baddebt: exportBadDebt,
};

const exportExcel = async () => {
  exporting.value = true;
  try {
    await EXPORTERS[activeTab.value]?.();
  } catch (error) {
    useAlert(error?.response?.data?.error || '导出失败');
  } finally {
    exporting.value = false;
  }
};

// 期初建账是录入面板、年度结转是一次性操作，都没有行表可导，不出按钮。
const canExport = computed(() => {
  const tab = activeTab.value;
  if (tab === 'close') return rows.value.length > 0;
  if (tab === 'reconcile') return reconcileRows.value.length > 0;
  if (tab === 'stock') return stockLayers.value.length > 0;
  if (tab === 'revalue') return revalRows.value.length > 0;
  if (tab === 'baddebt') return badDebtRows.value.length > 0;
  return false;
});

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
  if (key === 'stock') await loadStockLayers();
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
    <div class="flex items-center justify-between gap-3 px-6 py-4 [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8">
      <div class="flex items-center gap-2">
        <div class="i-lucide-calendar-check size-5 text-n-iris-9" />
        <h1 class="text-xl font-semibold text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8">期末结账</h1>
        <span class="text-sm text-n-slate-11">
          结账＝结转损益到本年利润 + 冻结该期间凭证
        </span>
      </div>
      <Button
        v-if="canExport"
        label="导出 Excel"
        color="slate"
        variant="faded"
        size="sm"
        :is-loading="exporting"
        @click="exportExcel"
      />
      <Button label="刷新" color="slate" size="sm" @click="load" />
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
    </div>

    <!-- 期初建账 -->
    <div
      v-if="activeTab === 'opening'"
      class="flex-1 min-h-0 px-6 pb-6 overflow-auto [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8"
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
          :disabled="!openingBalanced || openingMissingParty"
          @click="saveOpening"
        />
        <span v-if="openingMissingParty" class="text-xs text-n-ruby-11">
          {{ '有应收/应付的行还没挂客户或供应商' }}
        </span>
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
          <!-- 往来科目（应收/应付）的期初必须挂到具体客户/供应商，否则账龄、对账单取不到数 -->
          <div class="col-span-12 pb-1 pl-1 -mt-1">
            <ErpDimensionFields
              v-model="openingRows[index]"
              :dimensions="dimensionsOf(row)"
              :required-dimension="requiredDimensionOf(row)"
            />
          </div>
        </div>
      </div>
      <p class="mt-4 text-xs text-n-slate-10">
        期初会生成一张已记账的「期初建账」凭证（日期＝启用日），账簿与报表的期初余额由它带出；重新保存＝整张替换。
      </p>
    </div>

    <!-- 成品存货（FIFO 批次层） -->
    <HScrollButtons v-if="activeTab === 'stock'" />
    <div
      v-if="activeTab === 'stock'"
      class="flex-1 min-h-0 px-6 pb-6 overflow-auto [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8"
    >
      <div class="flex flex-wrap items-center gap-3 mb-4">
        <span class="text-sm text-n-slate-11">
          结存
          <span class="font-mono text-n-slate-12">
            {{ stockMeta.qty || 0 }}
          </span>
          件 · 账面价值
          <span class="font-mono text-n-slate-12">
            {{ money(stockMeta.amount_micros) }}
          </span>
        </span>
        <!-- 批次层是 ERP 的成本账，实物结存是仓库的账；差额＝有货没成本（期初漏导那种） -->
        <span v-if="stockMeta.diff_qty" class="text-sm text-n-amber-11">
          实物结存 {{ stockMeta.physical_qty }} 件，比有成本的批次多
          {{ stockMeta.diff_qty }} 件——这部分出库会按 0 成本结转，请补导期初
        </span>
        <label
          class="flex items-center gap-1.5 text-sm cursor-pointer text-n-slate-11"
        >
          <input
            v-model="stockIncludeEmpty"
            type="checkbox"
            class="accent-n-iris-9"
            @change="loadStockLayers"
          />
          含已耗尽批次
        </label>
        <div class="flex items-center gap-2 ml-auto">
          <Button
            label="下载模板"
            color="slate"
            variant="faded"
            size="sm"
            @click="downloadStockTemplate"
          />
          <Button
            v-if="canClose"
            label="导入期初"
            color="iris"
            size="sm"
            :is-loading="stockImporting"
            @click="stockFileRef?.click()"
          />
          <input
            ref="stockFileRef"
            type="file"
            accept=".csv"
            class="hidden"
            @change="onStockFile"
          />
        </div>
      </div>

      <table class="w-full text-sm">
        <thead>
          <tr class="text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-3 py-3 font-medium whitespace-nowrap">入库日期</th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">成品</th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">仓库</th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              入库数
            </th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              剩余
            </th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              单位成本
            </th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              结存金额
            </th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">来源</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in stockLayers"
            :key="row.id"
            class="border-b border-n-weak"
          >
            <td class="px-3 py-2 text-n-slate-11">
              {{ (row.received_at || '').slice(0, 10) }}
            </td>
            <td class="px-3 py-2 text-n-slate-12">
              {{ row.product_name }}
              <span class="text-xs text-n-slate-10">{{ row.product_sku }}</span>
            </td>
            <td class="px-3 py-2 text-n-slate-11">{{ row.warehouse_name }}</td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-11">
              {{ row.qty_in }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
              {{ row.qty_remaining }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-11">
              {{ money(row.unit_cost_micros) }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
              {{ money(row.amount_remaining_micros) }}
            </td>
            <td class="px-3 py-2 text-xs text-n-slate-10">{{ row.remark }}</td>
          </tr>
          <tr v-if="!stockLayers.length">
            <td colspan="8" class="px-3 py-10 text-center text-n-slate-11">
              还没有成品批次。点「导入期初」把金蝶里现有的成品批次搬进来，之后采购收货与完工入库会自动建批次。
            </td>
          </tr>
        </tbody>
      </table>
      <p class="mt-4 text-xs text-n-slate-10">
        先进先出：出库按入库日期从早到晚逐层扣成本，与金蝶同口径。现货出库的成本自动挂到对应销售订单（毛利表可见）；
        定制单的成本走领料归集，不在这里。
      </p>
    </div>

    <!-- 两账对平 -->
    <HScrollButtons v-if="activeTab === 'reconcile'" />
    <div
      v-if="activeTab === 'reconcile'"
      class="flex-1 min-h-0 px-6 pb-6 overflow-auto [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8"
    >
      <table class="w-full max-w-3xl text-sm">
        <thead>
          <tr class="text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-3 py-3 font-medium whitespace-nowrap">对账项</th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              业务台账
            </th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              会计总账
            </th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              差额
            </th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">结果</th>
          </tr>
        </thead>
        <tbody>
          <template v-for="row in reconcileRows" :key="row.key">
            <tr class="border-b border-n-weak">
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
                <span
                  v-if="row.note"
                  class="block mt-1 text-xs text-n-slate-10"
                >
                  {{ row.note }}
                </span>
              </td>
            </tr>
            <!-- 应收差额的构成：时点差（已建账未发货）不是错账，摆出来才看得出
                 哪一段要动手。「其他」不为零才是要排查的。 -->
            <tr
              v-for="part in row.matched ? [] : row.breakdown || []"
              :key="`${row.key}-${part.key}`"
              class="border-b border-n-weak bg-n-slate-2"
            >
              <td class="py-1.5 pl-8 pr-3 text-n-slate-11">
                └ {{ part.label }}
                <span class="block text-xs text-n-slate-10">{{
                  part.note
                }}</span>
              </td>
              <td colspan="2" />
              <td
                class="px-3 py-1.5 font-mono text-right"
                :class="
                  part.key === 'other' && part.amount_micros !== 0
                    ? 'text-n-ruby-11'
                    : 'text-n-slate-11'
                "
              >
                {{ money(part.amount_micros) }}
              </td>
              <td />
            </tr>
          </template>
        </tbody>
      </table>
      <p class="mt-4 text-xs text-n-slate-10">
        每月结账前这三行都应为「对平」。应收的差额已按构成拆开：「已建账·尚未发货」是时点差（台账在订单确认时建，
        应收账款在发货确认收入时才借记），发货后自动消除；「其他」不为零才说明有凭证记错科目或手工动过应收账款。
      </p>
    </div>

    <!-- 期末调汇 -->
    <HScrollButtons v-if="activeTab === 'revalue'" />
    <div
      v-if="activeTab === 'revalue'"
      class="flex-1 min-h-0 px-6 pb-6 overflow-auto [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8"
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
            <Input v-model="revalRates[currency]" size="sm" type="number" />
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
            <th class="px-3 py-3 font-medium whitespace-nowrap">科目</th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">核算单位</th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              原币余额
            </th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              账面本位币
            </th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              期末应有
            </th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              调汇差额
            </th>
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
    <HScrollButtons v-if="activeTab === 'baddebt'" />
    <div
      v-if="activeTab === 'baddebt'"
      class="flex-1 min-h-0 px-6 pb-6 overflow-auto [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8"
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
            <th class="px-3 py-3 font-medium whitespace-nowrap">客户</th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              未结应收
            </th>
            <th
              v-for="bucket in badDebtMeta.buckets"
              :key="bucket.key"
              class="px-3 py-3 font-medium text-right whitespace-nowrap"
            >
              {{ bucket.label }}
            </th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              应计提
            </th>
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
    <HScrollButtons v-if="activeTab === 'yearend'" />
    <div
      v-if="activeTab === 'yearend'"
      class="flex-1 min-h-0 px-6 pb-6 overflow-auto [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8"
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
    <HScrollButtons v-if="activeTab === 'close'" />
    <div
      v-if="activeTab === 'close'"
      class="flex-1 min-h-0 px-6 pb-6 overflow-auto [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8"
    >
      <div v-if="loading" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <table v-else class="w-full max-w-5xl text-sm">
        <thead>
          <tr class="text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-3 py-3 font-medium whitespace-nowrap">会计期间</th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              凭证数
            </th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              待过账
            </th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              借方合计
            </th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              贷方合计
            </th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">试算</th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">期末事项</th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">状态</th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              操作
            </th>
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
