<script setup>
import { ref, reactive, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import CrmKpiSchemeAPI from 'dashboard/api/crm/kpiSchemes';
import { useCrmKpiSchemesStore } from 'dashboard/stores/crm/kpiSchemes';

import Button from 'dashboard/components-next/button/Button.vue';
import CrmKpiDistributeDialog from 'dashboard/components-next/CRM/CrmKpiDistributeDialog.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useCrmKpiSchemesStore();
const { accountId } = useAccount();

const DATA_SOURCES = ['CRM_SALES', 'CRM_NEWCUST', 'MANUAL', 'MANAGER'];
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
  status: 'DRAFT',
  payoutNote: '',
  resultNote: '',
  items: [],
  tiers: [],
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

const totalWeight = computed(() =>
  form.items.reduce((sum, i) => sum + (Number(i.weight) || 0), 0)
);
const isFormInvalid = computed(() => !form.name.trim() || !form.month);

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
  'w-full h-9 px-2 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12';
const fieldCls =
  'h-10 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12';
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <!-- 顶栏 -->
    <div
      class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak"
    >
      <div class="flex items-center gap-3">
        <Button icon="i-lucide-arrow-left" size="sm" variant="ghost" color="slate" @click="goBack" />
        <div>
          <h1 class="text-xl font-medium text-n-slate-12">
            {{ isEdit ? t('CRM.KPI_SCHEMES.EDIT.TITLE') : t('CRM.KPI_SCHEMES.CREATE.TITLE') }}
          </h1>
          <p class="mt-0.5 text-xs text-n-slate-11">{{ t('CRM.KPI_SCHEMES.SUBTITLE') }}</p>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <Button
          :label="t('CRM.KPI_SCHEMES.EDITOR.DISTRIBUTE')"
          icon="i-lucide-send"
          color="amber"
          variant="faded"
          @click="openDistribute"
        />
        <Button
          :label="submitting ? t('CRM.KPI_SCHEMES.EDITOR.SAVING') : t('CRM.KPI_SCHEMES.EDITOR.SAVE')"
          icon="i-lucide-check"
          color="iris"
          :is-disabled="isFormInvalid || submitting"
          @click="submit"
        />
      </div>
    </div>

    <div v-if="loading" class="flex items-center justify-center flex-1 text-base text-n-slate-11">
      {{ t('CRM.KPI_SCHEMES.LOADING') }}
    </div>

    <div v-else class="flex flex-col w-full gap-8 px-6 py-6">
      <!-- 方案基本信息 -->
      <section class="flex flex-col gap-3">
        <div class="text-xs font-semibold tracking-wide uppercase text-n-slate-10">
          {{ t('CRM.KPI_SCHEMES.EDITOR.SECTION_BASIC') }}
        </div>
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">{{ t('CRM.KPI_SCHEMES.FORM.NAME') }} <span class="text-n-ruby-11">*</span></span>
            <input v-model="form.name" :class="fieldCls" />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">{{ t('CRM.KPI_SCHEMES.FORM.MONTH') }} <span class="text-n-ruby-11">*</span></span>
            <input v-model="form.month" type="month" :class="fieldCls" />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">{{ t('CRM.KPI_SCHEMES.FORM.STATUS') }}</span>
            <select v-model="form.status" :class="fieldCls">
              <option value="DRAFT">{{ t('CRM.KPI_SCHEMES.STATUS.DRAFT') }}</option>
              <option value="PUBLISHED">{{ t('CRM.KPI_SCHEMES.STATUS.PUBLISHED') }}</option>
            </select>
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">{{ t('CRM.KPI_SCHEMES.FORM.PASS_SCORE') }}</span>
            <input v-model="form.passScore" type="number" :class="fieldCls" />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">{{ t('CRM.KPI_SCHEMES.FORM.CAP_PCT') }}</span>
            <input v-model="form.itemScoreCapPct" type="number" :class="fieldCls" />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">{{ t('CRM.KPI_SCHEMES.EDITOR.TOTAL_SCORE') }}</span>
            <input :value="totalWeight" disabled :class="fieldCls" class="opacity-60" />
          </label>
        </div>
      </section>

      <!-- 考核指标 -->
      <section class="flex flex-col gap-3">
        <div class="flex items-center justify-between">
          <div class="text-xs font-semibold tracking-wide uppercase text-n-slate-10">
            {{ t('CRM.KPI_SCHEMES.ITEMS.TITLE', { total: totalWeight }) }}
          </div>
          <Button :label="t('CRM.KPI_SCHEMES.ITEMS.ADD')" icon="i-lucide-plus" size="sm" variant="faded" color="slate" @click="addItem" />
        </div>
        <datalist id="kpi-dims">
          <option v-for="d in dimOptions" :key="d" :value="d" />
        </datalist>
        <div class="overflow-x-auto">
          <table class="w-full text-sm border-collapse min-w-[880px]">
            <thead class="text-n-slate-11">
              <tr class="border-b border-n-weak">
                <th class="px-2 py-1.5 font-medium text-left w-28">{{ t('CRM.KPI_SCHEMES.ITEMS.DIMENSION') }}</th>
                <th class="px-2 py-1.5 font-medium text-left w-32">{{ t('CRM.KPI_SCHEMES.ITEMS.NAME') }}</th>
                <th class="px-2 py-1.5 font-medium text-left">{{ t('CRM.KPI_SCHEMES.ITEMS.STANDARD') }}</th>
                <th class="px-2 py-1.5 font-medium text-left w-16">{{ t('CRM.KPI_SCHEMES.ITEMS.WEIGHT') }}</th>
                <th class="px-2 py-1.5 font-medium text-left w-24">{{ t('CRM.KPI_SCHEMES.ITEMS.BASELINE') }}</th>
                <th class="px-2 py-1.5 font-medium text-left w-24">{{ t('CRM.KPI_SCHEMES.ITEMS.TARGET') }}</th>
                <th class="px-2 py-1.5 font-medium text-left w-28">{{ t('CRM.KPI_SCHEMES.ITEMS.SOURCE') }}</th>
                <th class="w-10" />
              </tr>
            </thead>
            <tbody>
              <tr v-for="(item, i) in form.items" :key="`item-${i}`" class="border-b border-n-weak align-top">
                <td class="px-1 py-1">
                  <input
                    v-model="item.dimension"
                    list="kpi-dims"
                    :placeholder="t('CRM.KPI_SCHEMES.EDITOR.DIM_PLACEHOLDER')"
                    :class="inputCls"
                    class="!text-n-iris-11 !bg-n-iris-3/40 font-medium"
                  />
                </td>
                <td class="px-1 py-1"><input v-model="item.name" :class="inputCls" /></td>
                <td class="px-1 py-1">
                  <textarea v-model="item.standard" rows="2" :class="inputCls" class="min-h-[52px] leading-relaxed py-1.5" />
                </td>
                <td class="px-1 py-1"><input v-model="item.weight" type="number" step="0.5" :class="inputCls" class="text-center font-medium" /></td>
                <td class="px-1 py-1"><input v-model="item.baselineValue" :class="inputCls" /></td>
                <td class="px-1 py-1"><input v-model="item.targetValue" :class="inputCls" /></td>
                <td class="px-1 py-1">
                  <select v-model="item.dataSource" :class="inputCls">
                    <option v-for="ds in DATA_SOURCES" :key="ds" :value="ds">{{ t(`CRM.KPI_SCHEMES.SOURCE.${ds}`) }}</option>
                  </select>
                </td>
                <td class="px-1 py-1 text-center">
                  <Button icon="i-lucide-trash-2" size="sm" variant="ghost" color="ruby" @click="removeItem(i)" />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <!-- 月度数据统计（参考，不计分） -->
      <section class="flex flex-col gap-3">
        <div class="text-xs font-semibold tracking-wide uppercase text-n-slate-10">
          {{ t('CRM.KPI_SCHEMES.EDITOR.SECTION_STATS') }}
        </div>
        <div class="grid grid-cols-2 gap-2 sm:grid-cols-4 lg:grid-cols-7">
          <div
            v-for="[k, src] in STAT_KEYS"
            :key="k"
            class="p-3 rounded-xl border border-n-weak bg-n-solid-1/60"
          >
            <div class="text-xs text-n-slate-10">{{ t(`CRM.KPI_SCHEMES.STATS.${k}`) }}</div>
            <div class="mt-1 text-sm font-medium text-n-slate-11">{{ t(`CRM.KPI_SCHEMES.STATS.${src}`) }}</div>
          </div>
        </div>
      </section>

      <!-- 发放系数档 -->
      <section class="flex flex-col gap-3">
        <div class="flex items-center justify-between">
          <div class="text-xs font-semibold tracking-wide uppercase text-n-slate-10">
            {{ t('CRM.KPI_SCHEMES.TIERS.TITLE') }}
          </div>
          <Button :label="t('CRM.KPI_SCHEMES.TIERS.ADD')" icon="i-lucide-plus" size="sm" variant="faded" color="slate" @click="addTier" />
        </div>
        <table class="w-full text-sm border-collapse">
          <thead class="text-n-slate-11">
            <tr class="border-b border-n-weak">
              <th class="px-2 py-1.5 font-medium text-left">{{ t('CRM.KPI_SCHEMES.TIERS.NAME') }}</th>
              <th class="px-2 py-1.5 font-medium text-left w-28">{{ t('CRM.KPI_SCHEMES.TIERS.MIN') }}</th>
              <th class="px-2 py-1.5 font-medium text-left w-28">{{ t('CRM.KPI_SCHEMES.TIERS.MAX') }}</th>
              <th class="px-2 py-1.5 font-medium text-left w-28">{{ t('CRM.KPI_SCHEMES.TIERS.COEFFICIENT') }}</th>
              <th class="px-2 py-1.5 font-medium text-left w-36">{{ t('CRM.KPI_SCHEMES.TIERS.PROPORTIONAL') }}</th>
              <th class="w-10" />
            </tr>
          </thead>
          <tbody>
            <tr v-for="(tier, i) in form.tiers" :key="`tier-${i}`" class="border-b border-n-weak">
              <td class="px-1 py-1"><input v-model="tier.name" :class="inputCls" /></td>
              <td class="px-1 py-1"><input v-model="tier.minScore" type="number" :class="inputCls" /></td>
              <td class="px-1 py-1"><input v-model="tier.maxScore" type="number" :class="inputCls" /></td>
              <td class="px-1 py-1"><input v-model="tier.coefficient" type="number" step="0.01" :class="inputCls" /></td>
              <td class="px-2 py-1 text-center"><input v-model="tier.proportional" type="checkbox" /></td>
              <td class="px-1 py-1 text-center">
                <Button icon="i-lucide-trash-2" size="sm" variant="ghost" color="ruby" @click="removeTier(i)" />
              </td>
            </tr>
          </tbody>
        </table>
      </section>

      <!-- 规则 & 结果应用 -->
      <section class="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <label class="flex flex-col gap-2 p-4 rounded-2xl border border-n-weak bg-n-solid-1/60">
          <span class="text-sm font-medium text-n-slate-12">💰 {{ t('CRM.KPI_SCHEMES.EDITOR.SECTION_RULES') }}</span>
          <textarea v-model="form.payoutNote" rows="5" :class="fieldCls" class="!h-auto py-2 leading-relaxed" />
        </label>
        <label class="flex flex-col gap-2 p-4 rounded-2xl border border-n-weak bg-n-solid-1/60">
          <span class="text-sm font-medium text-n-slate-12">📌 {{ t('CRM.KPI_SCHEMES.EDITOR.SECTION_RESULT') }}</span>
          <textarea v-model="form.resultNote" rows="5" :class="fieldCls" class="!h-auto py-2 leading-relaxed" />
        </label>
      </section>
    </div>

    <CrmKpiDistributeDialog ref="distributeRef" />
  </div>
</template>
