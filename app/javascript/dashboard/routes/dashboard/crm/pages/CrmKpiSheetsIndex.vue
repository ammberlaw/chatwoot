<script setup>
import { computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCrmKpiSheetsStore } from 'dashboard/stores/crm/kpiSheets';

const { t } = useI18n();
const router = useRouter();
const { accountId } = useAccount();
const store = useCrmKpiSheetsStore();

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

const yuan = m => (m == null ? '—' : `¥${Math.round(m / 1_000_000).toLocaleString()}`);
const fmtMonth = v => {
  if (!v) return '—';
  const d = new Date(v);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
};
const statusClass = s =>
  s === 'ARCHIVED'
    ? 'bg-n-teal-3 text-n-teal-11'
    : s === 'PENDING'
      ? 'bg-n-amber-3 text-n-amber-11'
      : 'bg-n-iris-3 text-n-iris-11';
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5">
    <div class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak">
      <div>
        <h1 class="text-xl font-medium text-n-slate-12">{{ t('CRM.KPI_SHEETS.LIST_HEADER') }}</h1>
        <p class="mt-0.5 text-xs text-n-slate-11">{{ t('CRM.KPI_SHEETS.LIST_SUBTITLE') }}</p>
      </div>
    </div>
    <div class="flex-1 px-6 py-4">
      <div v-if="isFetching" class="flex items-center justify-center p-8 text-n-slate-11">{{ t('CRM.KPI_SHEETS.LOADING') }}</div>
      <div v-else-if="!records.length" class="flex items-center justify-center p-8 text-n-slate-11">{{ t('CRM.KPI_SHEETS.EMPTY') }}</div>
      <table v-else class="w-full text-sm text-left border-collapse">
        <thead class="text-n-slate-11">
          <tr class="border-b border-n-weak">
            <th class="px-3 py-2 font-medium">{{ t('CRM.KPI_SHEETS.COL_OWNER') }}</th>
            <th class="px-3 py-2 font-medium">{{ t('CRM.KPI_SHEETS.COL_MONTH') }}</th>
            <th class="px-3 py-2 font-medium">{{ t('CRM.KPI_SHEETS.COL_SCHEME') }}</th>
            <th class="px-3 py-2 font-medium">{{ t('CRM.KPI_SHEETS.COL_STATUS') }}</th>
            <th class="px-3 py-2 font-medium">{{ t('CRM.KPI_SHEETS.COL_SCORE') }}</th>
            <th class="px-3 py-2 font-medium">{{ t('CRM.KPI_SHEETS.COL_PAYOUT') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="s in records" :key="s.id" class="border-b border-n-weak cursor-pointer hover:bg-n-alpha-1" @click="open(s)">
            <td class="px-3 py-2 font-medium text-n-slate-12">{{ s.ownerName || '—' }}</td>
            <td class="px-3 py-2 text-n-slate-11">{{ fmtMonth(s.periodMonth) }}</td>
            <td class="px-3 py-2 text-n-slate-11">{{ s.schemeName || '—' }}</td>
            <td class="px-3 py-2"><span class="inline-flex px-2 py-0.5 rounded-full text-xs" :class="statusClass(s.status)">{{ t(`CRM.KPI_SHEETS.STATUS.${s.status}`) }}</span></td>
            <td class="px-3 py-2 text-n-slate-11">{{ s.totalScore != null ? `${s.totalScore}/100` : '—' }}</td>
            <td class="px-3 py-2 font-medium text-n-slate-12">{{ yuan(s.actualPayoutMicros) }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
