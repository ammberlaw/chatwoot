<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { useCrmKpiSchemesStore } from 'dashboard/stores/crm/kpiSchemes';
import CrmKpiSchemeAPI from 'dashboard/api/crm/kpiSchemes';

import Button from 'dashboard/components-next/button/Button.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';

const { t } = useI18n();
const router = useRouter();
const store = useCrmKpiSchemesStore();
const { accountId } = useAccount();
const currentUser = useMapGetter('getCurrentUser');

const records = computed(() => store.getRecords);
const uiFlags = computed(() => store.getUIFlags);
const isFetching = computed(() => uiFlags.value.fetchingList);

// 增删改：超级管理员/管理员/部门负责人/人事。
const canManage = computed(() => {
  const role = currentUser.value?.role;
  return (
    role === 'administrator' ||
    currentUser.value?.crm_manager === true ||
    ['deputy_admin', 'manager', 'hr'].includes(currentUser.value?.crm_role)
  );
});

const fetchRecords = () => store.get();

// ── 按年份归档筛选：默认当年，可切历史年份或全部 ──
const yearFilter = ref(String(new Date().getFullYear()));
// 进入默认本月（可在下拉选「全部月份」看全部）
const monthFilter = ref(String(new Date().getMonth() + 1));
const yearOf = r => String(new Date(r.schemeMonth).getFullYear());
const monthOf = r => String(new Date(r.schemeMonth).getMonth() + 1);
const yearOptions = computed(() => {
  const years = new Set(records.value.map(yearOf));
  years.add(String(new Date().getFullYear()));
  return [...years].sort().reverse();
});
// 当前年份下有方案的月份（供月份下拉），倒序。
const monthOptions = computed(() => {
  const inYear = yearFilter.value
    ? records.value.filter(r => yearOf(r) === yearFilter.value)
    : records.value;
  return [...new Set(inYear.map(monthOf))].sort(
    (a, b) => Number(b) - Number(a)
  );
});
// 年/月归档筛选的紫玻璃 SelectCard 选项（含「全部」空值项）。
const yearFilterOptions = computed(() => [
  { value: '', label: '全部年份' },
  ...yearOptions.value.map(y => ({ value: y, label: `${y} 年` })),
]);
const monthFilterOptions = computed(() => [
  { value: '', label: '全部月份' },
  ...monthOptions.value.map(m => ({ value: m, label: `${m} 月` })),
]);
const filteredRecords = computed(() =>
  records.value.filter(
    r =>
      (!yearFilter.value || yearOf(r) === yearFilter.value) &&
      (!monthFilter.value || monthOf(r) === monthFilter.value)
  )
);
// 切换年份时重置月份筛选，避免残留无效月份导致空列表。
watch(yearFilter, () => {
  monthFilter.value = '';
});

const openCreate = () =>
  router.push({
    name: 'crm_kpi_scheme_editor',
    params: { accountId: accountId.value },
  });
const openEdit = scheme => {
  if (!canManage.value) return;
  router.push({
    name: 'crm_kpi_scheme_editor',
    params: { accountId: accountId.value },
    query: { id: scheme.id },
  });
};

const deleteScheme = async (scheme, event) => {
  event.stopPropagation();
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('CRM.KPI_SCHEMES.DELETE.CONFIRM'))) return;
  try {
    await store.delete(scheme.id);
    useAlert(t('CRM.KPI_SCHEMES.DELETE.SUCCESS'));
  } catch {
    useAlert(t('CRM.KPI_SCHEMES.DELETE.ERROR'));
  }
};

// 复制方案：整份拷贝出一份「(副本)」草稿，复制后刷新列表。
const duplicateScheme = async (scheme, event) => {
  event.stopPropagation();
  try {
    await CrmKpiSchemeAPI.duplicate(scheme.id);
    await store.get();
    useAlert('已复制为草稿副本');
  } catch {
    useAlert('复制失败，请重试');
  }
};

onMounted(fetchRecords);

const fmtMonth = value => {
  if (!value) return '—';
  const d = new Date(value);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
};
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
          {{ t('CRM.KPI_SCHEMES.HEADER') }}
        </h1>
        <p class="mt-0.5 text-xs text-n-slate-11">
          {{ t('CRM.KPI_SCHEMES.SUBTITLE') }}
        </p>
      </div>
      <Button
        v-if="canManage"
        :label="t('CRM.KPI_SCHEMES.NEW')"
        icon="i-lucide-plus"
        color="iris"
        @click="openCreate"
      />
    </div>

    <div class="flex-1 px-6 py-4">
      <!-- 年份 / 月份归档筛选 -->
      <div class="flex items-center gap-2 mb-3">
        <SelectCard
          v-model="yearFilter"
          :options="yearFilterOptions"
          trigger-class="w-28"
        />
        <SelectCard
          v-model="monthFilter"
          :options="monthFilterOptions"
          trigger-class="w-28"
        />
        <span class="text-xs text-n-slate-10">
          {{ `共 ${filteredRecords.length} 套方案` }}
        </span>
      </div>
      <div
        v-if="isFetching"
        class="flex items-center justify-center p-8 text-base text-n-slate-11"
      >
        {{ t('CRM.KPI_SCHEMES.LOADING') }}
      </div>
      <div
        v-else-if="!filteredRecords.length"
        class="flex items-center justify-center p-8 text-base text-n-slate-11"
      >
        {{ t('CRM.KPI_SCHEMES.EMPTY') }}
      </div>
      <table v-else class="w-full text-sm text-left border-collapse">
        <thead class="text-n-slate-11">
          <tr class="border-b border-n-weak">
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.KPI_SCHEMES.TABLE.NAME') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.KPI_SCHEMES.TABLE.MONTH') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.KPI_SCHEMES.TABLE.STATUS') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.KPI_SCHEMES.TABLE.PASS_SCORE') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.KPI_SCHEMES.TABLE.ITEMS') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.KPI_SCHEMES.TABLE.TIERS') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.KPI_SCHEMES.TABLE.CREATOR') }}
            </th>
            <th v-if="canManage" class="px-3 py-2" />
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="record in filteredRecords"
            :key="record.id"
            class="border-b border-n-weak hover:bg-n-alpha-1"
            :class="{ 'cursor-pointer': canManage }"
            @click="openEdit(record)"
          >
            <td class="px-3 py-2 font-medium text-n-slate-12">
              {{ record.name }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ fmtMonth(record.schemeMonth) }}
            </td>
            <td class="px-3 py-2">
              <span
                class="inline-flex px-2 py-0.5 rounded-full text-xs"
                :class="
                  record.status === 'PUBLISHED'
                    ? 'bg-n-teal-3 text-n-teal-11'
                    : 'bg-n-slate-3 text-n-slate-11'
                "
              >
                {{ t(`CRM.KPI_SCHEMES.STATUS.${record.status}`) }}
              </span>
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ record.passScore ?? '—' }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ (record.schemeItems || []).length }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ (record.payoutTiers || []).length }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ record.createdByName || '—' }}
            </td>
            <td v-if="canManage" class="px-3 py-2 text-right">
              <Button
                icon="i-lucide-copy"
                size="sm"
                variant="ghost"
                color="slate"
                title="复制方案"
                @click="duplicateScheme(record, $event)"
              />
              <Button
                icon="i-lucide-trash-2"
                size="sm"
                variant="ghost"
                color="ruby"
                @click="deleteScheme(record, $event)"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
