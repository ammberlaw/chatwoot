<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCrmRole } from 'dashboard/composables/useCrmRole';
import { useCrmKpiSheetsStore } from 'dashboard/stores/crm/kpiSheets';
import MonthPicker from 'dashboard/components-next/monthpicker/MonthPicker.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import { fmtYuan } from 'dashboard/helper/crmMoney';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
const { t } = useI18n();
const router = useRouter();
const { accountId } = useAccount();
const store = useCrmKpiSheetsStore();

// 搜索栏只给能看多人考核表的角色（管理员/超管/部门负责人/人事）；业务员和普通成员只看自己的，无需搜索。
const { isAdmin, isCrmDeputyAdmin, isCrmManager, isCrmHr } = useCrmRole();
const showSearch = computed(
  () =>
    isAdmin.value ||
    isCrmDeputyAdmin.value ||
    isCrmManager.value ||
    isCrmHr.value
);

const records = computed(() => store.getRecords);
const uiFlags = computed(() => store.getUIFlags);
const isFetching = computed(() => uiFlags.value.fetchingList);

onMounted(() => store.get());

const open = sheet =>
  router.push({
    name: 'crm_kpi_sheet_detail',
    params: { accountId: accountId.value },
    query: { id: sheet.id },
  });

// 撤回下发：仅「待填报」阶段、且管理员/副管理员/主管/人事可见（作用域由后端最终把关）。
const canRecall = computed(
  () =>
    isAdmin.value ||
    isCrmDeputyAdmin.value ||
    isCrmManager.value ||
    isCrmHr.value
);
const recall = async sheet => {
  if (
    !window.confirm(
      t('CRM.KPI_SHEETS.RECALL.CONFIRM', {
        name: sheet.ownerName || '该员工',
      })
    )
  ) {
    return;
  }
  try {
    await store.delete(sheet.id);
    useAlert(t('CRM.KPI_SHEETS.RECALL.SUCCESS'));
  } catch (e) {
    useAlert(e?.response?.data?.error || t('CRM.KPI_SHEETS.RECALL.ERROR'));
  }
};

const yuan = m => (m == null ? '—' : `¥${fmtYuan(m)}`);
const fmtMonth = v => {
  if (!v) return '—';
  const d = new Date(v);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
};
// ── 月份 / 状态筛选（客户端过滤，考核表量级小）──
// 进入默认本月：月份堆多了不用每次手动筛（可清空看全部）
const monthFilter = ref(fmtMonth(new Date()));
const statusFilter = ref('');
const q = ref('');
const STATUS_KEYS = [
  'PENDING',
  'SUBMITTED',
  'SCORED',
  'HR_CONFIRMED',
  'ARCHIVED',
];
// 原生 select → 紫玻璃 SelectCard 的筛选选项（含「全部」空值项）。
const statusFilterOptions = computed(() => [
  { value: '', label: '全部状态' },
  ...STATUS_KEYS.map(k => ({
    value: k,
    label: t(`CRM.KPI_SHEETS.STATUS.${k}`),
  })),
]);
const filteredRecords = computed(() => {
  const kw = q.value.trim().toLowerCase();
  return records.value.filter(
    s =>
      (!monthFilter.value || fmtMonth(s.periodMonth) === monthFilter.value) &&
      (!statusFilter.value || s.status === statusFilter.value) &&
      (!kw ||
        `${s.ownerName || ''} ${s.schemeName || ''}`.toLowerCase().includes(kw))
  );
});

const statusClass = s =>
  s === 'ARCHIVED'
    ? 'bg-n-teal-3 text-n-teal-11'
    : s === 'PENDING'
      ? 'bg-n-amber-3 text-n-amber-11'
      : 'bg-n-iris-3 text-n-iris-11';
</script>

<template>
  <HScrollButtons />
  <div
    class="flex flex-col w-full h-full overflow-auto backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border bg-n-solid-1/80 border-n-weak/70 shadow-wintouch-glass"
  >
    <div
      class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8"
    >
      <div>
        <h1 class="text-n-slate-12 text-heading-1">
          {{ t('CRM.KPI_SHEETS.LIST_HEADER') }}
        </h1>
        <p class="mt-0.5 text-xs text-n-slate-11">
          {{
            t(
              showSearch
                ? 'CRM.KPI_SHEETS.LIST_SUBTITLE'
                : 'CRM.KPI_SHEETS.LIST_SUBTITLE_SELF'
            )
          }}
        </p>
      </div>
    </div>
    <div class="flex-1 px-4 py-3 sm:px-6 sm:py-4 [.theme-classic_&]:sm:!px-8">
      <!-- 月份 / 状态筛选 -->
      <div class="flex flex-wrap items-center gap-2 mb-3">
        <input
          v-if="showSearch"
          v-model="q"
          class="h-9 px-3 text-sm border rounded-lg reset-base w-full sm:w-52 border-n-weak bg-n-solid-1 text-n-slate-12"
          placeholder="搜索业务员 / 方案名"
        />
        <MonthPicker v-model="monthFilter" trigger-class="w-44 h-9" />
        <SelectCard
          v-model="statusFilter"
          :options="statusFilterOptions"
          trigger-class="w-36"
        />
        <button
          v-if="q || monthFilter || statusFilter"
          class="h-9 px-2 text-xs rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
          @click="
            q = '';
            monthFilter = '';
            statusFilter = '';
          "
        >
          清除筛选
        </button>
        <span class="text-xs text-n-slate-10">
          {{ `共 ${filteredRecords.length} 张` }}
        </span>
      </div>
      <div
        v-if="isFetching"
        class="flex items-center justify-center p-8 text-n-slate-11"
      >
        {{ t('CRM.KPI_SHEETS.LOADING') }}
      </div>
      <div
        v-else-if="!filteredRecords.length"
        class="flex items-center justify-center p-8 text-n-slate-11"
      >
        {{
          t(showSearch ? 'CRM.KPI_SHEETS.EMPTY' : 'CRM.KPI_SHEETS.EMPTY_SELF')
        }}
      </div>
      <!-- 有数据：手机卡片(<md) + 桌面表格(≥md) -->
      <template v-else>
        <!-- 手机：卡片列表 -->
        <div class="flex flex-col gap-2 md:hidden">
          <div
            v-for="s in filteredRecords"
            :key="s.id"
            class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl active:bg-n-alpha-1"
            @click="open(s)"
          >
            <div class="flex items-center gap-2">
              <span class="font-medium text-n-slate-12 truncate">
                {{ s.ownerName || '—' }}
              </span>
              <span
                class="inline-flex px-2 py-0.5 shrink-0 text-label-small rounded-full"
                :class="statusClass(s.status)"
              >
                {{ t(`CRM.KPI_SHEETS.STATUS.${s.status}`) }}
              </span>
              <span class="flex-1" />
              <button
                v-if="canRecall && s.status === 'PENDING'"
                class="px-2 py-1 text-xs rounded-lg text-n-ruby-11 hover:bg-n-ruby-3 shrink-0"
                @click.stop="recall(s)"
              >
                {{ t('CRM.KPI_SHEETS.RECALL.BUTTON') }}
              </button>
            </div>
            <div class="mt-1 text-xs text-n-slate-11">
              {{ fmtMonth(s.periodMonth) }} · {{ s.schemeName || '—' }}
            </div>
            <div class="flex items-center gap-3 mt-1.5 text-xs">
              <span class="text-n-slate-11">
                {{ t('CRM.KPI_SHEETS.COL_SCORE') }}：{{
                  s.totalScore != null
                    ? `${s.totalScore}/${s.totalScoreCap || 100}`
                    : '—'
                }}
              </span>
              <span class="font-medium text-n-slate-12">
                {{ t('CRM.KPI_SHEETS.COL_PAYOUT') }}：{{
                  yuan(s.actualPayoutMicros)
                }}
              </span>
            </div>
          </div>
        </div>

        <!-- 桌面：表格 -->
        <table class="hidden w-full text-sm text-left border-collapse md:table">
          <thead class="text-n-slate-11">
            <tr class="border-b border-n-weak">
              <th class="px-3 py-2 font-medium">
                {{ t('CRM.KPI_SHEETS.COL_OWNER') }}
              </th>
              <th class="px-3 py-2 font-medium">
                {{ t('CRM.KPI_SHEETS.COL_MONTH') }}
              </th>
              <th class="px-3 py-2 font-medium">
                {{ t('CRM.KPI_SHEETS.COL_SCHEME') }}
              </th>
              <th class="px-3 py-2 font-medium">
                {{ t('CRM.KPI_SHEETS.COL_STATUS') }}
              </th>
              <th class="px-3 py-2 font-medium">
                {{ t('CRM.KPI_SHEETS.COL_SCORE') }}
              </th>
              <th class="px-3 py-2 font-medium">
                {{ t('CRM.KPI_SHEETS.COL_PAYOUT') }}
              </th>
              <th v-if="canRecall" class="px-3 py-2 font-medium text-right">
                {{ t('CRM.KPI_SHEETS.COL_ACTIONS') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="s in filteredRecords"
              :key="s.id"
              class="border-b border-n-weak cursor-pointer hover:bg-n-alpha-1"
              @click="open(s)"
            >
              <td class="px-3 py-2 font-medium text-n-slate-12">
                {{ s.ownerName || '—' }}
              </td>
              <td class="px-3 py-2 text-n-slate-11">
                {{ fmtMonth(s.periodMonth) }}
              </td>
              <td class="px-3 py-2 text-n-slate-11">
                {{ s.schemeName || '—' }}
              </td>
              <td class="px-3 py-2">
                <div class="flex items-center gap-1.5">
                  <span
                    class="inline-flex px-2 py-0.5 text-label-small rounded-full"
                    :class="statusClass(s.status)"
                  >
                    {{ t(`CRM.KPI_SHEETS.STATUS.${s.status}`) }}
                  </span>
                </div>
              </td>
              <td class="px-3 py-2 text-n-slate-11">
                {{
                  s.totalScore != null
                    ? `${s.totalScore}/${s.totalScoreCap || 100}`
                    : '—'
                }}
              </td>
              <td class="px-3 py-2 font-medium text-n-slate-12">
                {{ yuan(s.actualPayoutMicros) }}
              </td>
              <td v-if="canRecall" class="px-3 py-2 text-right" @click.stop>
                <button
                  v-if="canRecall && s.status === 'PENDING'"
                  class="px-2 py-1 text-xs rounded-lg text-n-ruby-11 hover:bg-n-ruby-3"
                  @click="recall(s)"
                >
                  {{ t('CRM.KPI_SHEETS.RECALL.BUTTON') }}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </template>
    </div>
  </div>
</template>
