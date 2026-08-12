<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCrmRole } from 'dashboard/composables/useCrmRole';
import { useCrmKpiSheetsStore } from 'dashboard/stores/crm/kpiSheets';
import CrmKpiSheetAPI from 'dashboard/api/crm/kpiSheets';
import MonthPicker from 'dashboard/components-next/monthpicker/MonthPicker.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';

const { t } = useI18n();
const router = useRouter();
const { accountId } = useAccount();
const store = useCrmKpiSheetsStore();

// 搜索栏只给能看多人考核表的角色（管理员/超管/部门负责人/人事）；业务员和普通成员只看自己的，无需搜索。
const { isAdmin, isCrmDeputyAdmin, isCrmManager, isCrmHr, isCrmFinance } =
  useCrmRole();
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
const paidFilter = ref(''); // 财务专用：'' 全部 / 'unpaid' 待发放 / 'paid' 已发放
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
const paidFilterOptions = computed(() => [
  { value: '', label: '发放状态' },
  { value: 'unpaid', label: t('CRM.KPI_SHEETS.PAYOUT.UNPAID') },
  { value: 'paid', label: t('CRM.KPI_SHEETS.PAYOUT.PAID') },
]);
const filteredRecords = computed(() => {
  const kw = q.value.trim().toLowerCase();
  return records.value.filter(
    s =>
      (!monthFilter.value || fmtMonth(s.periodMonth) === monthFilter.value) &&
      (!statusFilter.value || s.status === statusFilter.value) &&
      (!paidFilter.value ||
        (paidFilter.value === 'paid' ? !!s.paidAt : !s.paidAt)) &&
      (!kw ||
        `${s.ownerName || ''} ${s.schemeName || ''}`.toLowerCase().includes(kw))
  );
});

const fmtDate = v => (v ? new Date(v).toLocaleDateString() : '');

// ── 财务发放（仅 crm_finance）：勾选「已归档且未发放」的绩效表批量标记已发放 ──
const selected = ref([]);
const isSelectable = s => s.status === 'ARCHIVED' && !s.paidAt;
const selectableIds = computed(() =>
  filteredRecords.value.filter(isSelectable).map(s => s.id)
);
const allSelected = computed(
  () =>
    selectableIds.value.length > 0 &&
    selectableIds.value.every(id => selected.value.includes(id))
);
const toggleSelect = id => {
  selected.value = selected.value.includes(id)
    ? selected.value.filter(x => x !== id)
    : [...selected.value, id];
};
const toggleAll = () => {
  selected.value = allSelected.value ? [] : [...selectableIds.value];
};

const refresh = async () => {
  selected.value = [];
  await store.get();
};

const markPaidBatch = async () => {
  if (!selected.value.length) return;
  try {
    const { data } = await CrmKpiSheetAPI.markPaid(selected.value);
    await refresh();
    useAlert(t('CRM.KPI_SHEETS.PAYOUT.MARKED', { n: data?.count ?? 0 }));
  } catch (e) {
    useAlert(e?.response?.data?.error || t('CRM.KPI_SHEETS.PAYOUT.ERROR'));
  }
};

const markPaidOne = async s => {
  try {
    await CrmKpiSheetAPI.markPaid([s.id]);
    await refresh();
    useAlert(t('CRM.KPI_SHEETS.PAYOUT.MARKED', { n: 1 }));
  } catch (e) {
    useAlert(e?.response?.data?.error || t('CRM.KPI_SHEETS.PAYOUT.ERROR'));
  }
};

const unmarkPaid = async s => {
  if (!window.confirm(t('CRM.KPI_SHEETS.PAYOUT.UNMARK_CONFIRM'))) return;
  try {
    await CrmKpiSheetAPI.unmarkPaid([s.id]);
    await refresh();
    useAlert(t('CRM.KPI_SHEETS.PAYOUT.UNMARKED'));
  } catch (e) {
    useAlert(e?.response?.data?.error || t('CRM.KPI_SHEETS.PAYOUT.ERROR'));
  }
};

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
    <div class="flex-1 px-6 py-4">
      <!-- 月份 / 状态筛选 -->
      <div class="flex flex-wrap items-center gap-2 mb-3">
        <input
          v-if="showSearch"
          v-model="q"
          class="h-9 px-3 text-sm border rounded-lg reset-base w-52 border-n-weak bg-n-solid-1 text-n-slate-12"
          placeholder="搜索业务员 / 方案名"
        />
        <MonthPicker v-model="monthFilter" trigger-class="w-44 h-9" />
        <SelectCard
          v-model="statusFilter"
          :options="statusFilterOptions"
          trigger-class="w-36"
        />
        <SelectCard
          v-if="isCrmFinance"
          v-model="paidFilter"
          :options="paidFilterOptions"
          trigger-class="w-32"
        />
        <button
          v-if="q || monthFilter || statusFilter || paidFilter"
          class="h-9 px-2 text-xs rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
          @click="
            q = '';
            monthFilter = '';
            statusFilter = '';
            paidFilter = '';
          "
        >
          清除筛选
        </button>
        <span class="text-xs text-n-slate-10">
          {{ `共 ${filteredRecords.length} 张` }}
        </span>
        <button
          v-if="isCrmFinance && selected.length"
          class="h-8 px-3 ml-auto text-xs font-medium text-white rounded-lg bg-n-teal-9 hover:bg-n-teal-10"
          @click="markPaidBatch"
        >
          {{ t('CRM.KPI_SHEETS.PAYOUT.MARK_BATCH', { n: selected.length }) }}
        </button>
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
      <table v-else class="w-full text-sm text-left border-collapse">
        <thead class="text-n-slate-11">
          <tr class="border-b border-n-weak">
            <th v-if="isCrmFinance" class="w-8 px-3 py-2">
              <input
                type="checkbox"
                class="accent-n-teal-9"
                :checked="allSelected"
                :disabled="!selectableIds.length"
                @change="toggleAll"
              />
            </th>
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
            <th
              v-if="canRecall || isCrmFinance"
              class="px-3 py-2 font-medium text-right"
            >
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
            <td v-if="isCrmFinance" class="px-3 py-2" @click.stop>
              <input
                v-if="isSelectable(s)"
                type="checkbox"
                class="accent-n-teal-9"
                :checked="selected.includes(s.id)"
                @change="toggleSelect(s.id)"
              />
            </td>
            <td class="px-3 py-2 font-medium text-n-slate-12">
              {{ s.ownerName || '—' }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ fmtMonth(s.periodMonth) }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">{{ s.schemeName || '—' }}</td>
            <td class="px-3 py-2">
              <div class="flex items-center gap-1.5">
                <span
                  class="inline-flex px-2 py-0.5 rounded-full text-xs"
                  :class="statusClass(s.status)"
                >
                  {{ t(`CRM.KPI_SHEETS.STATUS.${s.status}`) }}
                </span>
                <span
                  v-if="s.paidAt"
                  class="inline-flex px-2 py-0.5 rounded-full text-xs bg-n-teal-3 text-n-teal-11"
                  :title="`${s.paidByName || ''} · ${fmtDate(s.paidAt)}`"
                >
                  {{ t('CRM.KPI_SHEETS.PAYOUT.PAID') }}
                </span>
              </div>
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ s.totalScore != null ? `${s.totalScore}/100` : '—' }}
            </td>
            <td class="px-3 py-2 font-medium text-n-slate-12">
              {{ yuan(s.actualPayoutMicros) }}
            </td>
            <td
              v-if="canRecall || isCrmFinance"
              class="px-3 py-2 text-right"
              @click.stop
            >
              <button
                v-if="canRecall && s.status === 'PENDING'"
                class="px-2 py-1 text-xs rounded-lg text-n-ruby-11 hover:bg-n-ruby-3"
                @click="recall(s)"
              >
                {{ t('CRM.KPI_SHEETS.RECALL.BUTTON') }}
              </button>
              <button
                v-if="isCrmFinance && s.status === 'ARCHIVED' && !s.paidAt"
                class="px-2 py-1 text-xs rounded-lg text-n-teal-11 hover:bg-n-teal-3"
                @click="markPaidOne(s)"
              >
                {{ t('CRM.KPI_SHEETS.PAYOUT.MARK_ONE') }}
              </button>
              <button
                v-if="isCrmFinance && s.paidAt"
                class="px-2 py-1 text-xs rounded-lg text-n-slate-10 hover:bg-n-alpha-2"
                @click="unmarkPaid(s)"
              >
                {{ t('CRM.KPI_SHEETS.PAYOUT.UNMARK') }}
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
