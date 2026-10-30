<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useCrmSalesTargetsStore } from 'dashboard/stores/crm/salesTargets';
import SalesTargetsAPI from 'dashboard/api/crm/salesTargets';

import Button from 'dashboard/components-next/button/Button.vue';
import CrmSalesTargetCreateDialog from 'dashboard/components-next/CRM/CrmSalesTargetCreateDialog.vue';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
const { t } = useI18n();
const route = useRoute();
const store = useCrmSalesTargetsStore();

const createDialogRef = ref(null);
const activeFilter = ref(route.query.filter || 'all');

const records = computed(() => store.getRecords);
const uiFlags = computed(() => store.getUIFlags);
const isFetching = computed(() => uiFlags.value.fetchingList);
const isCreating = computed(() => uiFlags.value.creatingItem);

const currentUser = useMapGetter('getCurrentUser');

// 体检页会摆出每个人的月度保本线，而保本线＝月薪 ÷ 有效提成率，知道点位就能反推月薪。
// 所以按薪资数据同一口径收口，和后端 Crm::SalesTargetPolicy#audit? 一致。
const canAudit = computed(
  () =>
    currentUser.value?.role === 'administrator' ||
    ['deputy_admin', 'hr'].includes(currentUser.value?.crm_role)
);

const filterTabs = computed(() => {
  const tabs = [
    { key: 'all', label: t('CRM.SALES_TARGETS.FILTERS.ALL') },
    { key: 'mine', label: t('CRM.SALES_TARGETS.FILTERS.MINE') },
  ];
  if (canAudit.value) {
    tabs.push({ key: 'audit', label: t('CRM.SALES_TARGETS.FILTERS.AUDIT') });
  }
  return tabs;
});

const auditRows = ref([]);
const auditOrphans = ref([]);
const isAuditing = ref(false);
const isSeeding = ref(false);
const isAuditTab = computed(() => activeFilter.value === 'audit');

const fetchAudit = async () => {
  isAuditing.value = true;
  try {
    const { data } = await SalesTargetsAPI.audit();
    auditRows.value = data.rows || [];
    auditOrphans.value = data.orphans || [];
  } finally {
    isAuditing.value = false;
  }
};

const fetchRecords = () => {
  if (isAuditTab.value) {
    fetchAudit();
    return;
  }
  const filter = activeFilter.value === 'all' ? undefined : activeFilter.value;
  store.get({ filter });
};

// 只补缺的月份，已有目标一律不动——业务员自己定高了的数不能被推回底线。
const seedTargets = async () => {
  isSeeding.value = true;
  try {
    const { data } = await SalesTargetsAPI.seed({ source: 'recorded' });
    useAlert(
      data.created
        ? t('CRM.SALES_TARGETS.AUDIT.SEED_DONE', {
            created: data.created,
            skipped: data.skipped,
          })
        : t('CRM.SALES_TARGETS.AUDIT.SEED_NONE')
    );
    await fetchAudit();
  } catch {
    useAlert(t('CRM.SALES_TARGETS.AUDIT.SEED_ERROR'));
  } finally {
    isSeeding.value = false;
  }
};

const setFilter = key => {
  activeFilter.value = key;
  fetchRecords();
};

const openCreateDialog = () => createDialogRef.value?.open();

const createRecord = async payload => {
  try {
    await store.create(payload);
    createDialogRef.value?.onSuccess();
    useAlert(t('CRM.SALES_TARGETS.CREATE.SUCCESS'));
  } catch {
    useAlert(t('CRM.SALES_TARGETS.CREATE.ERROR'));
  }
};

onMounted(fetchRecords);
watch(
  () => route.query.filter,
  value => {
    activeFilter.value = value || 'all';
    fetchRecords();
  }
);

const fmtMonth = value => {
  if (!value) return '—';
  const d = new Date(value);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
};
const fmtMoney = micros =>
  micros == null ? '—' : `¥ ${(micros / 1_000_000).toLocaleString()}`;

const auditHints = row => [...(row.blockers || []), ...(row.notes || [])];
// 薪资表录的底线优先，没录才落回系统建议值。
const baselineOf = row => row.recorded_micros ?? row.suggested_micros;
// 有效提成率后端给到四位小数，页面上两位就够——2.1747% 读起来像个仪器读数。
const fmtRate = rate => (rate ? `${Number(rate).toFixed(2)}%` : '—');
</script>

<template>
  <HScrollButtons />
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div
      class="flex items-center justify-between flex-shrink-0 px-4 py-3 sm:px-6 sm:py-4 border-b border-n-weak [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:sm:!px-8"
    >
      <h1 class="text-xl font-medium text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8">
        {{ t('CRM.SALES_TARGETS.HEADER') }}
      </h1>
      <Button
        v-if="!isAuditTab"
        :label="t('CRM.SALES_TARGETS.NEW')"
        icon="i-lucide-plus"
        color="iris"
        @click="openCreateDialog"
      />
    </div>

    <div
      class="flex flex-wrap items-center gap-2 px-4 py-3 sm:px-6 border-b border-n-weak [.theme-classic_&]:sm:!px-8"
    >
      <div class="contents" data-tabbar="page" data-tabbar-theme="classic">
        <Button
          v-for="tab in filterTabs"
          :key="tab.key"
          :label="tab.label"
          size="sm"
          :aria-selected="activeFilter === tab.key"
          :variant="activeFilter === tab.key ? 'solid' : 'faded'"
          :color="activeFilter === tab.key ? 'iris' : 'slate'"
          @click="setFilter(tab.key)"
        />
      </div>
      <Button
        v-if="isAuditTab"
        :label="t('CRM.SALES_TARGETS.AUDIT.SEED')"
        icon="i-lucide-wand-sparkles"
        size="sm"
        color="iris"
        class="ml-auto"
        :is-loading="isSeeding"
        :disabled="isSeeding"
        @click="seedTargets"
      />
    </div>

    <div class="flex-1 px-4 py-3 sm:px-6 sm:py-4 [.theme-classic_&]:sm:!px-8">
      <div v-if="isAuditTab" class="flex flex-col gap-4">
        <div
          v-if="isAuditing"
          class="flex items-center justify-center p-8 text-base text-n-slate-11"
        >
          {{ t('CRM.SALES_TARGETS.LOADING') }}
        </div>
        <div
          v-else-if="!auditRows.length"
          class="flex items-center justify-center p-8 text-base text-n-slate-11"
        >
          {{ t('CRM.SALES_TARGETS.AUDIT.EMPTY') }}
        </div>
        <template v-else>
          <div class="flex flex-col gap-2 md:hidden">
            <div
              v-for="row in auditRows"
              :key="row.owner_id"
              class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl"
            >
              <div class="flex items-center gap-2">
                <span class="font-medium text-n-slate-12 truncate">
                  {{ row.name }}
                </span>
                <span
                  v-if="row.missing_current_month"
                  class="shrink-0 px-1.5 py-0.5 rounded text-label-small bg-n-ruby-3 text-n-ruby-11"
                >
                  {{ t('CRM.SALES_TARGETS.AUDIT.MISSING') }}
                </span>
                <span
                  v-if="row.new_hire"
                  class="shrink-0 px-1.5 py-0.5 rounded text-label-small bg-n-amber-3 text-n-amber-11"
                >
                  {{ t('CRM.SALES_TARGETS.AUDIT.NEW_HIRE') }}
                </span>
              </div>
              <div
                class="flex flex-wrap gap-x-3 gap-y-1 mt-2 text-label-small text-n-slate-11"
              >
                <span>
                  {{ t('CRM.SALES_TARGETS.AUDIT.TABLE.BASELINE') }}
                  {{ fmtMoney(baselineOf(row)) }}
                </span>
                <span>
                  {{ t('CRM.SALES_TARGETS.AUDIT.TABLE.YEAR_TOTAL') }}
                  {{ fmtMoney(row.year_total_micros) }}
                </span>
                <span>
                  {{
                    t('CRM.SALES_TARGETS.AUDIT.MONTHS', {
                      count: row.months_set,
                    })
                  }}
                </span>
                <span v-if="row.shortfall_micros" class="text-n-ruby-11">
                  {{ t('CRM.SALES_TARGETS.AUDIT.TABLE.SHORTFALL') }}
                  {{ fmtMoney(row.shortfall_micros) }}
                </span>
              </div>
              <p
                v-for="hint in auditHints(row)"
                :key="hint"
                class="mt-1 text-label-small text-n-slate-10"
              >
                {{ hint }}
              </p>
            </div>
          </div>
          <div class="hidden md:block overflow-x-auto">
            <table class="w-max min-w-full text-sm text-left border-collapse">
              <thead class="text-n-slate-11">
                <tr class="border-b border-n-weak">
                  <th class="px-3 py-2 font-medium whitespace-nowrap">
                    {{ t('CRM.SALES_TARGETS.AUDIT.TABLE.NAME') }}
                  </th>
                  <th
                    class="px-3 py-2 font-medium text-right whitespace-nowrap"
                  >
                    {{ t('CRM.SALES_TARGETS.AUDIT.TABLE.CURRENT') }}
                  </th>
                  <th
                    class="px-3 py-2 font-medium text-right whitespace-nowrap"
                  >
                    {{ t('CRM.SALES_TARGETS.AUDIT.TABLE.MONTHS_SET') }}
                  </th>
                  <th
                    class="px-3 py-2 font-medium text-right whitespace-nowrap"
                  >
                    {{ t('CRM.SALES_TARGETS.AUDIT.TABLE.YEAR_TOTAL') }}
                  </th>
                  <th
                    class="px-3 py-2 font-medium text-right whitespace-nowrap"
                  >
                    {{ t('CRM.SALES_TARGETS.AUDIT.TABLE.BASELINE') }}
                  </th>
                  <th
                    class="px-3 py-2 font-medium text-right whitespace-nowrap"
                  >
                    {{ t('CRM.SALES_TARGETS.AUDIT.TABLE.SHORTFALL') }}
                  </th>
                  <th
                    class="px-3 py-2 font-medium text-right whitespace-nowrap"
                  >
                    {{ t('CRM.SALES_TARGETS.AUDIT.TABLE.RATE') }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="row in auditRows"
                  :key="row.owner_id"
                  class="border-b border-n-weak hover:bg-n-alpha-1"
                >
                  <td class="px-3 py-2 whitespace-nowrap">
                    <div class="flex items-center gap-2">
                      <span class="font-medium text-n-slate-12">
                        {{ row.name }}
                      </span>
                      <span
                        v-if="row.new_hire"
                        class="shrink-0 px-1.5 py-0.5 rounded text-label-small bg-n-amber-3 text-n-amber-11"
                      >
                        {{ t('CRM.SALES_TARGETS.AUDIT.NEW_HIRE') }}
                      </span>
                    </div>
                    <p
                      v-for="hint in auditHints(row)"
                      :key="hint"
                      class="text-label-small text-n-slate-10"
                    >
                      {{ hint }}
                    </p>
                  </td>
                  <td
                    class="px-3 py-2 text-right tabular-nums whitespace-nowrap"
                    :class="
                      row.missing_current_month
                        ? 'text-n-ruby-11 font-medium'
                        : 'text-n-slate-11'
                    "
                  >
                    {{
                      row.missing_current_month
                        ? t('CRM.SALES_TARGETS.AUDIT.MISSING')
                        : fmtMoney(row.current_month_micros)
                    }}
                  </td>
                  <td
                    class="px-3 py-2 text-right tabular-nums whitespace-nowrap text-n-slate-11"
                  >
                    {{
                      t('CRM.SALES_TARGETS.AUDIT.MONTHS', {
                        count: row.months_set,
                      })
                    }}
                  </td>
                  <td
                    class="px-3 py-2 text-right tabular-nums whitespace-nowrap text-n-slate-11"
                  >
                    {{ fmtMoney(row.year_total_micros) }}
                  </td>
                  <td class="px-3 py-2 text-right whitespace-nowrap">
                    <span class="tabular-nums text-n-slate-12">
                      {{ fmtMoney(baselineOf(row)) }}
                    </span>
                    <span
                      v-if="baselineOf(row)"
                      class="ml-1 text-label-small text-n-slate-10"
                    >
                      {{
                        row.recorded_micros
                          ? t('CRM.SALES_TARGETS.AUDIT.FROM_SALARY')
                          : t('CRM.SALES_TARGETS.AUDIT.SUGGESTED')
                      }}
                    </span>
                  </td>
                  <td
                    class="px-3 py-2 text-right tabular-nums whitespace-nowrap"
                    :class="
                      row.shortfall_micros
                        ? 'text-n-ruby-11 font-medium'
                        : 'text-n-slate-11'
                    "
                  >
                    {{ fmtMoney(row.shortfall_micros) }}
                  </td>
                  <td
                    class="px-3 py-2 text-right tabular-nums whitespace-nowrap text-n-slate-11"
                  >
                    {{ fmtRate(row.effective_rate) }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <div v-if="auditOrphans.length" class="flex flex-col gap-1">
            <p class="text-label text-n-slate-11">
              {{ t('CRM.SALES_TARGETS.AUDIT.ORPHANS') }}
            </p>
            <p
              v-for="orphan in auditOrphans"
              :key="orphan.id"
              class="text-label-small text-n-slate-10"
            >
              {{ orphan.owner_name || t('CRM.SALES_TARGETS.AUDIT.NO_OWNER') }}
              · {{ fmtMonth(orphan.target_month) }} ·
              {{ fmtMoney(orphan.target_amount_micros) }}
            </p>
          </div>
        </template>
      </div>
      <div
        v-else-if="isFetching"
        class="flex items-center justify-center p-8 text-base text-n-slate-11"
      >
        {{ t('CRM.SALES_TARGETS.LOADING') }}
      </div>
      <div
        v-else-if="!records.length"
        class="flex items-center justify-center p-8 text-base text-n-slate-11"
      >
        {{ t('CRM.SALES_TARGETS.EMPTY') }}
      </div>
      <template v-else>
        <div class="flex flex-col gap-2 md:hidden">
          <div
            v-for="record in records"
            :key="record.id"
            class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl active:bg-n-alpha-1"
          >
            <div class="flex items-center gap-2">
              <span class="font-medium text-n-slate-12 truncate">
                {{ record.name }}
              </span>
            </div>
            <div
              class="flex flex-wrap gap-x-3 gap-y-1 mt-2 text-xs text-n-slate-11"
            >
              <span>
                {{ t('CRM.SALES_TARGETS.TABLE.MONTH') }}:
                {{ fmtMonth(record.targetMonth) }}
              </span>
              <span>
                {{ t('CRM.SALES_TARGETS.TABLE.AMOUNT') }}:
                {{ fmtMoney(record.targetAmountMicros) }}
              </span>
              <span>
                {{ t('CRM.SALES_TARGETS.TABLE.NEW_CUSTOMERS') }}:
                {{ record.targetOrderCount ?? '—' }}
              </span>
            </div>
          </div>
        </div>
        <table class="hidden md:table w-full text-sm text-left border-collapse">
          <thead class="text-n-slate-11">
            <tr class="border-b border-n-weak">
              <th class="px-3 py-2 font-medium">
                {{ t('CRM.SALES_TARGETS.TABLE.NAME') }}
              </th>
              <th class="px-3 py-2 font-medium">
                {{ t('CRM.SALES_TARGETS.TABLE.MONTH') }}
              </th>
              <th class="px-3 py-2 font-medium">
                {{ t('CRM.SALES_TARGETS.TABLE.AMOUNT') }}
              </th>
              <th class="px-3 py-2 font-medium">
                {{ t('CRM.SALES_TARGETS.TABLE.NEW_CUSTOMERS') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="record in records"
              :key="record.id"
              class="border-b border-n-weak hover:bg-n-alpha-1"
            >
              <td class="px-3 py-2 font-medium text-n-slate-12">
                {{ record.name }}
              </td>
              <td class="px-3 py-2 text-n-slate-11">
                {{ fmtMonth(record.targetMonth) }}
              </td>
              <td class="px-3 py-2 text-n-slate-11">
                {{ fmtMoney(record.targetAmountMicros) }}
              </td>
              <td class="px-3 py-2 text-n-slate-11">
                {{ record.targetOrderCount ?? '—' }}
              </td>
            </tr>
          </tbody>
        </table>
      </template>
    </div>

    <CrmSalesTargetCreateDialog
      ref="createDialogRef"
      :is-loading="isCreating"
      @create="createRecord"
    />
  </div>
</template>
