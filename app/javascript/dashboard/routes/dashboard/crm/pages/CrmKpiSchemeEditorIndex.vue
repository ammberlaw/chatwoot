<script setup>
import { ref, reactive, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import CrmKpiSchemeAPI from 'dashboard/api/crm/kpiSchemes';
import { useCrmKpiSchemesStore } from 'dashboard/stores/crm/kpiSchemes';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import CrmKpiDistributeDialog from 'dashboard/components-next/CRM/CrmKpiDistributeDialog.vue';
import MonthPicker from 'dashboard/components-next/monthpicker/MonthPicker.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useCrmKpiSchemesStore();
const { accountId } = useAccount();

const DATA_SOURCES = [
  'CRM_SALES',
  'CRM_NEWCUST',
  'MANUAL',
  'MANAGER',
  'SYSTEM',
];
// 原生 select → 紫玻璃 SelectCard 的选项。
const statusOptions = computed(() => [
  { value: 'DRAFT', label: t('CRM.KPI_SCHEMES.STATUS.DRAFT') },
  { value: 'PUBLISHED', label: t('CRM.KPI_SCHEMES.STATUS.PUBLISHED') },
]);
const dataSourceOptions = computed(() =>
  DATA_SOURCES.map(ds => ({
    value: ds,
    label: t(`CRM.KPI_SCHEMES.SOURCE.${ds}`),
  }))
);
const DIM_PRESETS = t('CRM.KPI_SCHEMES.ITEMS.DIM_PRESETS').split(',');
const STAT_KEYS = [
  ['INQUIRY_TM', 'MANUAL'],
  ['AFTER_FILTER', 'MANUAL'],
  ['DEAL_CUSTOMERS', 'AUTO'],
  ['REPEAT_CUSTOMERS', 'AUTO'],
  ['REPEAT_AMOUNT', 'AUTO'],
  ['NEW_CUSTOMERS', 'AUTO'],
  ['NEW_AMOUNT', 'AUTO'],
];
const currentMonth = () => new Date().toISOString().slice(0, 7);

const editingId = ref(route.query.id ? Number(route.query.id) : null);
const isEdit = computed(() => editingId.value !== null);
const submitting = ref(false);
const loading = ref(false);

const form = reactive({
  name: '',
  month: currentMonth(),
  passScore: '70',
  itemScoreCapPct: '120',
  totalScoreCap: '',
  status: 'DRAFT',
  payoutNote: '',
  resultNote: '',
  items: [],
  tiers: [],
  detailTables: [],
});

const blankItem = () => ({
  name: '',
  dimension: '',
  standard: '',
  weight: '',
  baselineValue: '',
  targetValue: '',
  dataSource: 'MANUAL',
});
const blankTier = () => ({
  name: '',
  minScore: '',
  maxScore: '',
  coefficient: '',
  proportional: false,
});

const addItem = () => form.items.push(blankItem());
const removeItem = i => form.items.splice(i, 1);
const addTier = () => form.tiers.push(blankTier());
const removeTier = i => form.tiers.splice(i, 1);

// 平台数据明细表：结构自由的小表格（标题+列头+行），运营方案的明细表A/B等。
const addTable = () =>
  form.detailTables.push({ title: '', columns: ['', ''], rows: [['', '']] });
const removeTable = ti => form.detailTables.splice(ti, 1);
const addTableColumn = tbl => {
  tbl.columns.push('');
  tbl.rows.forEach(row => row.push(''));
};
const removeTableColumn = (tbl, ci) => {
  if (tbl.columns.length <= 1) return;
  tbl.columns.splice(ci, 1);
  tbl.rows.forEach(row => row.splice(ci, 1));
};
const addTableRow = tbl => tbl.rows.push(tbl.columns.map(() => ''));
const removeTableRow = (tbl, ri) => tbl.rows.splice(ri, 1);

const totalWeight = computed(() =>
  form.items.reduce((sum, i) => sum + (Number(i.weight) || 0), 0)
);
const isFormInvalid = computed(() => !form.name.trim() || !form.month);

// 月度数据统计是业务考核专属参考区：仅指标挂了 CRM 数据源的方案显示。
const showStats = computed(() =>
  form.items.some(i => ['CRM_SALES', 'CRM_NEWCUST'].includes(i.dataSource))
);

// 维度候选：预设 + 已录入的自定义值（去重）。
const dimOptions = computed(() => {
  const used = form.items.map(i => i.dimension).filter(Boolean);
  return [...new Set([...DIM_PRESETS, ...used])];
});

const hydrate = scheme => {
  form.name = scheme.name || '';
  form.month = scheme.schemeMonth
    ? new Date(scheme.schemeMonth).toISOString().slice(0, 7)
    : currentMonth();
  form.passScore = scheme.passScore != null ? String(scheme.passScore) : '';
  form.itemScoreCapPct =
    scheme.itemScoreCapPct != null ? String(scheme.itemScoreCapPct) : '';
  form.totalScoreCap =
    scheme.totalScoreCap != null ? String(scheme.totalScoreCap) : '';
  form.status = scheme.status || 'DRAFT';
  form.payoutNote = scheme.payoutNote || '';
  form.resultNote = scheme.resultNote || '';
  form.items = (scheme.schemeItems || []).map(i => ({
    name: i.name || '',
    dimension: i.dimension || '',
    standard: i.standard || '',
    weight: i.weight != null ? String(i.weight) : '',
    baselineValue: i.baselineValue || '',
    targetValue: i.targetValue || '',
    dataSource: i.dataSource || 'MANUAL',
  }));
  form.tiers = (scheme.payoutTiers || []).map(tt => ({
    name: tt.name || '',
    minScore: tt.minScore != null ? String(tt.minScore) : '',
    maxScore: tt.maxScore != null ? String(tt.maxScore) : '',
    coefficient: tt.coefficient != null ? String(tt.coefficient) : '',
    proportional: !!tt.proportional,
  }));
  form.detailTables = (scheme.detailTables || []).map(tbl => ({
    title: tbl.title || '',
    columns: [...(tbl.columns || [])],
    rows: (tbl.rows || []).map(row => [...row]),
  }));
  if (!form.items.length) form.items = [blankItem()];
  if (!form.tiers.length) form.tiers = [blankTier()];
};

const goBack = () =>
  router.push({
    name: 'crm_kpi_schemes_index',
    params: { accountId: accountId.value },
  });

const distributeRef = ref(null);
const openDistribute = () => {
  if (!isEdit.value) {
    useAlert(t('CRM.KPI_SCHEMES.EDITOR.DISTRIBUTE_SAVE_FIRST'));
    return;
  }
  distributeRef.value?.open(editingId.value);
};

const num = v => (v === '' || v == null ? null : Number(v));

const submit = async () => {
  if (isFormInvalid.value || submitting.value) return;
  submitting.value = true;
  const payload = {
    name: form.name.trim(),
    schemeMonth: `${form.month}-01`,
    passScore: num(form.passScore),
    itemScoreCapPct: num(form.itemScoreCapPct),
    totalScoreCap: num(form.totalScoreCap),
    status: form.status,
    payoutNote: form.payoutNote.trim() || null,
    resultNote: form.resultNote.trim() || null,
    schemeItems: form.items
      .filter(i => i.name.trim())
      .map((i, idx) => ({
        name: i.name.trim(),
        dimension: i.dimension.trim() || null,
        standard: i.standard.trim() || null,
        weight: num(i.weight),
        baselineValue: i.baselineValue.trim() || null,
        targetValue: i.targetValue.trim() || null,
        dataSource: i.dataSource,
        sortOrder: idx,
      })),
    detailTables: form.detailTables
      .filter(
        tbl =>
          tbl.title.trim() ||
          tbl.rows.some(row => row.some(cell => cell.trim()))
      )
      .map(tbl => ({
        title: tbl.title.trim(),
        columns: tbl.columns.map(c => c.trim()),
        rows: tbl.rows.map(row => row.map(cell => cell.trim())),
      })),
    payoutTiers: form.tiers
      .filter(tt => tt.name.trim())
      .map((tt, idx) => ({
        name: tt.name.trim(),
        minScore: num(tt.minScore),
        maxScore: num(tt.maxScore),
        coefficient: num(tt.coefficient),
        proportional: !!tt.proportional,
        sortOrder: idx,
      })),
  };
  try {
    if (isEdit.value) {
      await store.update({ id: editingId.value, ...payload });
      useAlert(t('CRM.KPI_SCHEMES.EDIT.SUCCESS'));
    } else {
      await store.create(payload);
      useAlert(t('CRM.KPI_SCHEMES.CREATE.SUCCESS'));
    }
    goBack();
  } catch {
    useAlert(t('CRM.KPI_SCHEMES.CREATE.ERROR'));
  } finally {
    submitting.value = false;
  }
};

onMounted(async () => {
  if (isEdit.value) {
    loading.value = true;
    try {
      const { data } = await CrmKpiSchemeAPI.show(editingId.value);
      const camel = (await import('camelcase-keys')).default;
      hydrate(camel(data, { deep: true }));
    } catch {
      useAlert(t('CRM.KPI_SCHEMES.CREATE.ERROR'));
      goBack();
    } finally {
      loading.value = false;
    }
  } else {
    form.items = [blankItem()];
    form.tiers = [blankTier()];
  }
});

const inputCls =
  'reset-base w-full h-10 px-3 text-label !border !border-solid rounded-lg outline-none border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-slate-10 focus:ring-2 focus:ring-n-slate-3';
const fieldCls =
  'reset-base w-full h-10 px-3 text-label !border !border-solid rounded-lg outline-none border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-slate-10 focus:ring-2 focus:ring-n-slate-3';
</script>

<template>
  <div
    class="flex h-full w-full flex-col overflow-y-auto rounded-3xl border border-n-weak bg-n-slate-2"
  >
    <!-- 顶栏 -->
    <div
      class="sticky top-0 z-20 flex shrink-0 flex-wrap items-center justify-between gap-3 border-b border-n-weak bg-n-slate-2 px-5 py-4 sm:px-8 sm:py-5"
    >
      <div class="flex items-center gap-3 min-w-0">
        <Button
          icon="i-lucide-arrow-left"
          size="sm"
          variant="ghost"
          color="slate"
          @click="goBack"
        />
        <div class="min-w-0">
          <h1 class="text-heading-1 text-n-slate-12">
            {{
              isEdit
                ? t('CRM.KPI_SCHEMES.EDIT.TITLE')
                : t('CRM.KPI_SCHEMES.CREATE.TITLE')
            }}
          </h1>
        </div>
      </div>
      <div class="flex items-center gap-2 flex-wrap">
        <Button
          :label="t('CRM.KPI_SCHEMES.EDITOR.DISTRIBUTE')"
          icon="i-lucide-send"
          color="slate"
          variant="outline"
          @click="openDistribute"
        />
        <Button
          :label="
            submitting
              ? t('CRM.KPI_SCHEMES.EDITOR.SAVING')
              : t('CRM.KPI_SCHEMES.EDITOR.SAVE')
          "
          icon="i-lucide-check"
          color="slate"
          class="!bg-n-slate-12 !text-n-solid-1 hover:enabled:!bg-n-slate-11"
          :is-disabled="isFormInvalid || submitting"
          @click="submit"
        />
      </div>
    </div>

    <div
      v-if="loading"
      class="flex items-center justify-center flex-1 text-base text-n-slate-11"
    >
      {{ t('CRM.KPI_SCHEMES.LOADING') }}
    </div>

    <div
      v-else
      class="flex w-full min-w-0 flex-col gap-4 px-4 py-5 sm:px-6 xl:px-8"
    >
      <!-- 方案基本信息 -->
      <section
        class="flex min-w-0 flex-col gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-4 lg:p-5"
      >
        <h2 class="text-heading-2 text-n-slate-12">
          {{ t('CRM.KPI_SCHEMES.EDITOR.SECTION_BASIC') }}
        </h2>
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-12">
          <label
            class="flex min-w-0 flex-col gap-2 sm:col-span-2 xl:col-span-6"
          >
            <span class="text-label text-n-slate-11">
              {{ t('CRM.KPI_SCHEMES.FORM.NAME') }}
              <span class="text-n-ruby-11">*</span>
            </span>
            <input v-model="form.name" :class="fieldCls" />
          </label>
          <label class="flex min-w-0 flex-col gap-2 xl:col-span-3">
            <span class="text-label text-n-slate-11">
              {{ t('CRM.KPI_SCHEMES.FORM.MONTH') }}
              <span class="text-n-ruby-11">*</span>
            </span>
            <MonthPicker v-model="form.month" block />
          </label>
          <label class="flex min-w-0 flex-col gap-2 xl:col-span-3">
            <span class="text-label text-n-slate-11">{{
              t('CRM.KPI_SCHEMES.FORM.STATUS')
            }}</span>
            <SelectCard
              v-model="form.status"
              :options="statusOptions"
              trigger-class="!h-10 !text-label"
              block
            />
          </label>
          <label class="flex min-w-0 flex-col gap-2 xl:col-span-4">
            <span class="text-label text-n-slate-11">{{
              t('CRM.KPI_SCHEMES.FORM.PASS_SCORE')
            }}</span>
            <input v-model="form.passScore" type="number" :class="fieldCls" />
          </label>
          <label class="flex min-w-0 flex-col gap-2 xl:col-span-4">
            <span class="text-label text-n-slate-11">{{
              t('CRM.KPI_SCHEMES.FORM.CAP_PCT')
            }}</span>
            <input
              v-model="form.itemScoreCapPct"
              type="number"
              :class="fieldCls"
            />
          </label>
          <label class="flex min-w-0 flex-col gap-2 xl:col-span-4">
            <span class="text-label text-n-slate-11">{{
              t('CRM.KPI_SCHEMES.FORM.TOTAL_CAP')
            }}</span>
            <input
              v-model="form.totalScoreCap"
              type="number"
              :class="fieldCls"
            />
          </label>
          <label class="flex min-w-0 flex-col gap-2 xl:col-span-4">
            <span class="text-label text-n-slate-11">{{
              t('CRM.KPI_SCHEMES.EDITOR.TOTAL_SCORE')
            }}</span>
            <input
              :value="totalWeight"
              disabled
              :class="fieldCls"
              class="opacity-60"
            />
          </label>
        </div>
      </section>

      <!-- 考核指标 -->
      <section
        class="flex min-w-0 flex-col gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-4 lg:p-5"
      >
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h2 class="text-heading-2 text-n-slate-12">
            {{ t('CRM.KPI_SCHEMES.ITEMS.TITLE', { total: totalWeight }) }}
          </h2>
          <Button
            :label="t('CRM.KPI_SCHEMES.ITEMS.ADD')"
            icon="i-lucide-plus"
            size="sm"
            variant="faded"
            color="slate"
            @click="addItem"
          />
        </div>
        <datalist id="kpi-dims">
          <option v-for="d in dimOptions" :key="d" :value="d" />
        </datalist>
        <HScrollButtons />
        <div class="overflow-x-auto">
          <table
            class="w-full min-w-[1120px] table-fixed border-collapse text-label"
          >
            <thead class="bg-n-slate-3 text-n-slate-11">
              <tr class="border-b border-n-weak">
                <th class="px-2 py-3 text-left font-medium w-28">
                  {{ t('CRM.KPI_SCHEMES.ITEMS.DIMENSION') }}
                </th>
                <th class="px-2 py-3 text-left font-medium w-44">
                  {{ t('CRM.KPI_SCHEMES.ITEMS.NAME') }}
                </th>
                <th class="px-2 py-3 text-left font-medium">
                  {{ t('CRM.KPI_SCHEMES.ITEMS.STANDARD') }}
                </th>
                <th class="px-2 py-3 text-left font-medium w-[88px]">
                  {{ t('CRM.KPI_SCHEMES.ITEMS.WEIGHT') }}
                </th>
                <th class="px-2 py-3 text-left font-medium w-28">
                  {{ t('CRM.KPI_SCHEMES.ITEMS.BASELINE') }}
                </th>
                <th class="px-2 py-3 text-left font-medium w-32">
                  {{ t('CRM.KPI_SCHEMES.ITEMS.TARGET') }}
                </th>
                <th class="px-2 py-3 text-left font-medium w-40">
                  {{ t('CRM.KPI_SCHEMES.ITEMS.SOURCE') }}
                </th>
                <th class="w-10" />
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(item, i) in form.items"
                :key="`item-${i}`"
                class="border-b border-n-weak align-top"
              >
                <td class="px-2 py-4">
                  <input
                    v-model="item.dimension"
                    list="kpi-dims"
                    :placeholder="t('CRM.KPI_SCHEMES.EDITOR.DIM_PLACEHOLDER')"
                    :class="inputCls"
                    class="font-medium"
                  />
                </td>
                <td class="px-2 py-4">
                  <textarea
                    v-model="item.name"
                    rows="2"
                    :aria-label="t('CRM.KPI_SCHEMES.ITEMS.NAME')"
                    :class="inputCls"
                    class="!h-auto min-h-[68px] resize-y py-2 leading-relaxed"
                  />
                </td>
                <td class="px-2 py-4">
                  <textarea
                    v-model="item.standard"
                    rows="2"
                    :class="inputCls"
                    class="!h-auto min-h-[88px] resize-y py-2 leading-relaxed"
                  />
                </td>
                <td class="px-2 py-4">
                  <input
                    v-model="item.weight"
                    type="number"
                    step="0.5"
                    :class="inputCls"
                    class="text-center font-medium"
                  />
                </td>
                <td class="px-2 py-4">
                  <input v-model="item.baselineValue" :class="inputCls" />
                </td>
                <td class="px-2 py-4">
                  <input v-model="item.targetValue" :class="inputCls" />
                </td>
                <td class="px-2 py-4">
                  <SelectCard
                    v-model="item.dataSource"
                    :options="dataSourceOptions"
                    trigger-class="!h-10 !text-label"
                    block
                  />
                </td>
                <td class="px-2 py-4 text-center">
                  <Button
                    icon="i-lucide-trash-2"
                    size="sm"
                    variant="ghost"
                    color="ruby"
                    @click="removeItem(i)"
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <!-- 平台数据明细表（参考）：运营方案的明细表A/B、三平台询盘明细等 -->
      <section
        class="flex min-w-0 flex-col gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-4 lg:p-5"
      >
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h2 class="text-heading-2 text-n-slate-12">
            {{ t('CRM.KPI_SCHEMES.TABLES.TITLE') }}
          </h2>
          <Button
            :label="t('CRM.KPI_SCHEMES.TABLES.ADD')"
            icon="i-lucide-plus"
            size="sm"
            variant="faded"
            color="slate"
            @click="addTable"
          />
        </div>
        <div
          v-for="(tbl, ti) in form.detailTables"
          :key="ti"
          class="flex flex-col gap-2 p-3 rounded-xl border border-n-weak bg-n-solid-1"
        >
          <div class="flex items-center gap-2">
            <input
              v-model="tbl.title"
              :placeholder="t('CRM.KPI_SCHEMES.TABLES.NAME_PLACEHOLDER')"
              :class="inputCls"
              class="flex-1 font-medium"
            />
            <Button
              icon="i-lucide-columns-3"
              size="sm"
              variant="ghost"
              color="slate"
              :title="t('CRM.KPI_SCHEMES.TABLES.ADD_COL')"
              @click="addTableColumn(tbl)"
            />
            <Button
              icon="i-lucide-trash-2"
              size="sm"
              variant="ghost"
              color="ruby"
              @click="removeTable(ti)"
            />
          </div>
          <HScrollButtons />
          <div class="overflow-x-auto -mx-3 px-3 sm:mx-0 sm:px-0">
            <table class="w-full text-label border-collapse min-w-[480px]">
              <thead>
                <tr class="border-b border-n-weak">
                  <th
                    v-for="(col, ci) in tbl.columns"
                    :key="ci"
                    class="px-1 py-1 font-medium"
                  >
                    <div class="flex items-center gap-1">
                      <input
                        v-model="tbl.columns[ci]"
                        :placeholder="
                          t('CRM.KPI_SCHEMES.TABLES.COL_PLACEHOLDER')
                        "
                        :class="inputCls"
                        class="text-center"
                      />
                      <button
                        v-if="tbl.columns.length > 1"
                        class="text-n-slate-9 hover:text-n-ruby-11"
                        @click="removeTableColumn(tbl, ci)"
                      >
                        <Icon icon="i-lucide-x" class="size-3.5" />
                      </button>
                    </div>
                  </th>
                  <th class="w-9" />
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="(row, ri) in tbl.rows"
                  :key="ri"
                  class="border-b border-n-weak/60"
                >
                  <td v-for="(cell, ci) in row" :key="ci" class="px-1 py-1">
                    <input v-model="row[ci]" :class="inputCls" />
                  </td>
                  <td class="px-1 py-1 text-center">
                    <Button
                      icon="i-lucide-trash-2"
                      size="sm"
                      variant="ghost"
                      color="ruby"
                      @click="removeTableRow(tbl, ri)"
                    />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <div>
            <Button
              :label="t('CRM.KPI_SCHEMES.TABLES.ADD_ROW')"
              icon="i-lucide-plus"
              size="sm"
              variant="ghost"
              color="slate"
              @click="addTableRow(tbl)"
            />
          </div>
        </div>
        <p
          v-if="!form.detailTables.length"
          class="text-label-small text-n-slate-10"
        >
          {{ t('CRM.KPI_SCHEMES.TABLES.EMPTY') }}
        </p>
      </section>

      <!-- 月度数据统计（参考，不计分）：仅业务考核（含 CRM 数据源指标）显示 -->
      <section
        v-if="showStats"
        class="flex min-w-0 flex-col gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-4 lg:p-5"
      >
        <h2 class="text-heading-2 text-n-slate-12">
          {{ t('CRM.KPI_SCHEMES.EDITOR.SECTION_STATS') }}
        </h2>
        <div
          class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4 2xl:grid-cols-7"
        >
          <div
            v-for="[k, src] in STAT_KEYS"
            :key="k"
            class="p-3 rounded-xl border border-n-weak bg-n-solid-1"
          >
            <div class="text-label-small text-n-slate-10">
              {{ t(`CRM.KPI_SCHEMES.STATS.${k}`) }}
            </div>
            <div class="mt-1 text-label text-n-slate-11">
              {{ t(`CRM.KPI_SCHEMES.STATS.${src}`) }}
            </div>
          </div>
        </div>
      </section>

      <!-- 发放系数档 -->
      <section
        class="flex min-w-0 flex-col gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-4 lg:p-5"
      >
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h2 class="text-heading-2 text-n-slate-12">
            {{ t('CRM.KPI_SCHEMES.TIERS.TITLE') }}
          </h2>
          <Button
            :label="t('CRM.KPI_SCHEMES.TIERS.ADD')"
            icon="i-lucide-plus"
            size="sm"
            variant="faded"
            color="slate"
            @click="addTier"
          />
        </div>
        <HScrollButtons />
        <div class="overflow-x-auto -mx-4 px-4 sm:mx-0 sm:px-0">
          <table class="w-full text-label border-collapse min-w-[640px]">
            <thead class="text-n-slate-11">
              <tr class="border-b border-n-weak">
                <th class="px-2 py-1.5 font-medium text-left">
                  {{ t('CRM.KPI_SCHEMES.TIERS.NAME') }}
                </th>
                <th class="px-2 py-1.5 font-medium text-left w-28">
                  {{ t('CRM.KPI_SCHEMES.TIERS.MIN') }}
                </th>
                <th class="px-2 py-1.5 font-medium text-left w-28">
                  {{ t('CRM.KPI_SCHEMES.TIERS.MAX') }}
                </th>
                <th class="px-2 py-1.5 font-medium text-left w-28">
                  {{ t('CRM.KPI_SCHEMES.TIERS.COEFFICIENT') }}
                </th>
                <th class="px-2 py-1.5 font-medium text-left w-36">
                  {{ t('CRM.KPI_SCHEMES.TIERS.PROPORTIONAL') }}
                </th>
                <th class="w-10" />
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(tier, i) in form.tiers"
                :key="`tier-${i}`"
                class="border-b border-n-weak"
              >
                <td class="px-1 py-1">
                  <input v-model="tier.name" :class="inputCls" />
                </td>
                <td class="px-1 py-1">
                  <input
                    v-model="tier.minScore"
                    type="number"
                    :class="inputCls"
                  />
                </td>
                <td class="px-1 py-1">
                  <input
                    v-model="tier.maxScore"
                    type="number"
                    :class="inputCls"
                  />
                </td>
                <td class="px-1 py-1">
                  <input
                    v-model="tier.coefficient"
                    type="number"
                    step="0.01"
                    :class="inputCls"
                  />
                </td>
                <td class="px-2 py-1 text-center">
                  <input v-model="tier.proportional" type="checkbox" />
                </td>
                <td class="px-1 py-1 text-center">
                  <Button
                    icon="i-lucide-trash-2"
                    size="sm"
                    variant="ghost"
                    color="ruby"
                    @click="removeTier(i)"
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <!-- 规则 & 结果应用 -->
      <section class="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <label
          class="flex min-w-0 flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 lg:p-5"
        >
          <span class="text-label text-n-slate-12">{{
            t('CRM.KPI_SCHEMES.EDITOR.SECTION_RULES')
          }}</span>
          <textarea
            v-model="form.payoutNote"
            rows="5"
            :class="fieldCls"
            class="!h-auto resize-y py-3 leading-relaxed"
          />
        </label>
        <label
          class="flex min-w-0 flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 lg:p-5"
        >
          <span class="text-label text-n-slate-12">{{
            t('CRM.KPI_SCHEMES.EDITOR.SECTION_RESULT')
          }}</span>
          <textarea
            v-model="form.resultNote"
            rows="5"
            :class="fieldCls"
            class="!h-auto resize-y py-3 leading-relaxed"
          />
        </label>
      </section>
    </div>

    <CrmKpiDistributeDialog ref="distributeRef" />
  </div>
</template>
