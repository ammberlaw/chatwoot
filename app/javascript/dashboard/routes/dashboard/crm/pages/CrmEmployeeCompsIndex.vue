<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCrmEmployeeCompsStore } from 'dashboard/stores/crm/employeeComps';

import Button from 'dashboard/components-next/button/Button.vue';
import CrmEmployeeCompCreateDialog from 'dashboard/components-next/CRM/CrmEmployeeCompCreateDialog.vue';

const { t } = useI18n();
const store = useCrmEmployeeCompsStore();

const createDialogRef = ref(null);

const records = computed(() => store.getRecords);
const uiFlags = computed(() => store.getUIFlags);
const isFetching = computed(() => uiFlags.value.fetchingList);
const isCreating = computed(() => uiFlags.value.creatingItem);

const fetchRecords = () => store.get();

const openCreateDialog = () => createDialogRef.value?.open();

const createRecord = async payload => {
  try {
    await store.create(payload);
    createDialogRef.value?.onSuccess();
    useAlert(t('CRM.EMPLOYEE_COMPS.CREATE.SUCCESS'));
  } catch {
    useAlert(t('CRM.EMPLOYEE_COMPS.CREATE.ERROR'));
  }
};

onMounted(fetchRecords);

const fmtMoney = micros =>
  micros == null ? '—' : `¥ ${(micros / 1_000_000).toLocaleString()}`;
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
          {{ t('CRM.EMPLOYEE_COMPS.HEADER') }}
        </h1>
        <p class="mt-0.5 text-xs text-n-slate-11">
          {{ t('CRM.EMPLOYEE_COMPS.SUBTITLE') }}
        </p>
      </div>
      <Button
        :label="t('CRM.EMPLOYEE_COMPS.NEW')"
        icon="i-lucide-plus"
        color="iris"
        @click="openCreateDialog"
      />
    </div>

    <div class="flex-1 px-6 py-4">
      <div
        v-if="isFetching"
        class="flex items-center justify-center p-8 text-base text-n-slate-11"
      >
        {{ t('CRM.EMPLOYEE_COMPS.LOADING') }}
      </div>
      <div
        v-else-if="!records.length"
        class="flex items-center justify-center p-8 text-base text-n-slate-11"
      >
        {{ t('CRM.EMPLOYEE_COMPS.EMPTY') }}
      </div>
      <table v-else class="w-full text-sm text-left border-collapse">
        <thead class="text-n-slate-11">
          <tr class="border-b border-n-weak">
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.EMPLOYEE_COMPS.TABLE.NAME') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.EMPLOYEE_COMPS.TABLE.MEMBER') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.EMPLOYEE_COMPS.TABLE.MONTHLY_SALARY') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.EMPLOYEE_COMPS.TABLE.PERF_RATIO') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.EMPLOYEE_COMPS.TABLE.BASELINE_TARGET') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.EMPLOYEE_COMPS.TABLE.RANK_NOTE') }}
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
              {{ record.ownerName ?? '—' }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ fmtMoney(record.monthlySalaryMicros) }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ record.performanceRatio != null ? `${record.performanceRatio}%` : '—' }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ fmtMoney(record.baselineTargetMicros) }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ record.rankNote ?? '—' }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <CrmEmployeeCompCreateDialog
      ref="createDialogRef"
      :is-loading="isCreating"
      @create="createRecord"
    />
  </div>
</template>
