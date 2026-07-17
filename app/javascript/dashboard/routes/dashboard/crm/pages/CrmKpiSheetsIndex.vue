<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCrmRole } from 'dashboard/composables/useCrmRole';
import { useCrmKpiSheetsStore } from 'dashboard/stores/crm/kpiSheets';

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

const yuan = m =>
  m == null ? '—' : `¥${Math.round(m / 1_000_000).toLocaleString()}`;
const fmtMonth = v => {
  if (!v) return '—';
  const d = new Date(v);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
};
// ── 月份 / 状态筛选（客户端过滤，考核表量级小）──
const monthFilter = ref('');
const statusFilter = ref('');
const q = ref('');
const STATUS_KEYS = [
  'PENDING',
  'SUBMITTED',
  'SCORED',
  'HR_CONFIRMED',
  'ARCHIVED',
];
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
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div
      class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak"
    >
      <div>
        <h1 class="text-xl font-medium text-n-slate-12">
          {{ t('CRM.KPI_SHEETS.LIST_HEADER') }}
        </h1>
        <p class="mt-0.5 text-xs text-n-slate-11">
          {{ t('CRM.KPI_SHEETS.LIST_SUBTITLE') }}
        </p>
      </div>
    </div>
    <div class="flex-1 px-6 py-4">
      <!-- 月份 / 状态筛选 -->
      <div class="flex flex-wrap items-center gap-2 mb-3">
        <input
          v-if="showSearch"
          v-model="q"
          class="h-8 px-3 text-sm border rounded-lg reset-base w-52 border-n-weak bg-n-solid-1 text-n-slate-12"
          placeholder="搜索业务员 / 方案名"
        />
        <input
          v-model="monthFilter"
          type="month"
          class="h-8 px-2 text-sm border rounded-lg reset-base w-44 border-n-weak bg-n-solid-1 text-n-slate-12"
        />
        <select
          v-model="statusFilter"
          class="h-8 px-2 mb-0 text-sm border rounded-lg reset-base w-36 border-n-weak bg-n-solid-1 text-n-slate-12"
        >
          <option value="">全部状态</option>
          <option v-for="k in STATUS_KEYS" :key="k" :value="k">
            {{ t(`CRM.KPI_SHEETS.STATUS.${k}`) }}
          </option>
        </select>
        <button
          v-if="q || monthFilter || statusFilter"
          class="h-8 px-2 text-xs rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
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
        {{ t('CRM.KPI_SHEETS.EMPTY') }}
      </div>
      <table v-else class="w-full text-sm text-left border-collapse">
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
            <td class="px-3 py-2 text-n-slate-11">{{ s.schemeName || '—' }}</td>
            <td class="px-3 py-2">
              <span
                class="inline-flex px-2 py-0.5 rounded-full text-xs"
                :class="statusClass(s.status)"
              >
                {{ t(`CRM.KPI_SHEETS.STATUS.${s.status}`) }}
              </span>
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ s.totalScore != null ? `${s.totalScore}/100` : '—' }}
            </td>
            <td class="px-3 py-2 font-medium text-n-slate-12">
              {{ yuan(s.actualPayoutMicros) }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
