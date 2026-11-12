<script setup>
import { ref, computed, watch } from 'vue';
import { useHrSensitiveSession } from 'dashboard/composables/useHrSensitiveSession';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCrmEmployeeCompsStore } from 'dashboard/stores/crm/employeeComps';

import Button from 'dashboard/components-next/button/Button.vue';
import CrmEmployeeCompCreateDialog from 'dashboard/components-next/CRM/CrmEmployeeCompCreateDialog.vue';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
const { t } = useI18n();
const store = useCrmEmployeeCompsStore();
const label = key => t(`CRM.HR_WORKFLOW.${key}`);
const showHistory = ref(false);
let dialogGeneration = 0;

const createDialogRef = ref(null);

const records = computed(() => store.getRecords);
const uiFlags = computed(() => store.getUIFlags);
const isFetching = computed(() => uiFlags.value.fetchingList);
const isCreating = computed(() => uiFlags.value.creatingItem);
const isUpdating = computed(() => uiFlags.value.updatingItem);
const isDialogLoading = computed(() => isCreating.value || isUpdating.value);

const {
  active: sudoActive,
  checking: sudoChecking,
  password: sudoPassword,
  error: sudoError,
  verifying: sudoVerifying,
  unlock,
  handleError: handleSensitiveError,
} = useHrSensitiveSession();

const fetchRecords = async () => {
  try {
    await store.get({ history: showHistory.value });
  } catch (failure) {
    if (!handleSensitiveError(failure))
      useAlert(failure.message || label('FAILED'));
  }
  if (!sudoActive.value) store.records = [];
};

const openCreateDialog = () => {
  dialogGeneration += 1;
  createDialogRef.value?.open();
};
const openEditDialog = record => {
  dialogGeneration += 1;
  createDialogRef.value?.openEdit(record);
};

const createRecord = async payload => {
  const request = dialogGeneration;
  try {
    await store.create(payload);
    await fetchRecords();
    if (!sudoActive.value || request !== dialogGeneration) return;
    createDialogRef.value?.onSuccess();
    useAlert(t('CRM.EMPLOYEE_COMPS.CREATE.SUCCESS'));
  } catch (failure) {
    if (!handleSensitiveError(failure) && request === dialogGeneration)
      useAlert(failure.message || t('CRM.EMPLOYEE_COMPS.CREATE.ERROR'));
  }
};

const updateRecord = async payload => {
  const request = dialogGeneration;
  try {
    await store.update(payload);
    await fetchRecords();
    if (!sudoActive.value || request !== dialogGeneration) return;
    createDialogRef.value?.onSuccess();
    useAlert(t('CRM.EMPLOYEE_COMPS.EDIT.SUCCESS'));
  } catch (failure) {
    if (!handleSensitiveError(failure) && request === dialogGeneration)
      useAlert(failure.message || t('CRM.EMPLOYEE_COMPS.EDIT.ERROR'));
  }
};

const deleteRecord = async record => {
  if (!window.confirm(label('PAY_ARCHIVE_CONFIRM'))) {
    return;
  }
  try {
    await store.delete(record.id);
    fetchRecords();
    useAlert(label('PAY_ARCHIVED'));
  } catch (failure) {
    if (!handleSensitiveError(failure))
      useAlert(failure.message || t('CRM.EMPLOYEE_COMPS.DELETE.ERROR'));
  }
};

// ── 敏感区二次验证：先输登录密码解锁（15 分钟免验），解锁后才拉数据 ──
const togglePayHistory = () => {
  showHistory.value = !showHistory.value;
  fetchRecords();
};

// 金额默认打码，页头开关显隐（防旁人瞟屏）。
const showMoney = ref(false);
const fmtMoney = micros => {
  if (micros == null) return '—';
  return showMoney.value
    ? `¥ ${(micros / 1_000_000).toLocaleString()}`
    : '¥ ******';
};
watch(
  sudoActive,
  unlocked => {
    if (unlocked) fetchRecords();
    else {
      dialogGeneration += 1;
      store.records = [];
      showMoney.value = false;
      createDialogRef.value?.onSuccess();
    }
  },
  { flush: 'sync', immediate: true }
);
</script>

<template>
  <HScrollButtons />
  <div
    class="flex flex-col w-full h-full overflow-auto backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border bg-n-solid-1/80 border-n-weak/70 shadow-wintouch-glass"
  >
    <div
      class="flex items-center justify-between flex-shrink-0 gap-3 px-4 py-3 border-b sm:px-6 sm:py-4 border-n-weak [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:sm:!px-8"
    >
      <div class="min-w-0">
        <h1 class="text-n-slate-12 text-heading-1">
          {{ t('CRM.EMPLOYEE_COMPS.HEADER') }}
        </h1>
        <p class="mt-0.5 text-xs text-n-slate-11">
          {{ t('CRM.EMPLOYEE_COMPS.SUBTITLE') }}
        </p>
      </div>
      <div
        v-if="sudoActive"
        class="flex flex-wrap items-center justify-end gap-2"
      >
        <Button
          :label="showMoney ? '隐藏金额' : '显示金额'"
          :icon="showMoney ? 'i-lucide-eye-off' : 'i-lucide-eye'"
          color="slate"
          variant="faded"
          @click="showMoney = !showMoney"
        />
        <Button
          :label="label(showHistory ? 'CURRENT_ONLY' : 'SHOW_PAY_HISTORY')"
          color="slate"
          variant="outline"
          @click="togglePayHistory"
        />
        <Button
          :label="t('CRM.EMPLOYEE_COMPS.NEW')"
          icon="i-lucide-plus"
          color="iris"
          @click="openCreateDialog"
        />
      </div>
    </div>

    <!-- 敏感区解锁门：二次密码验证，15 分钟免验 -->
    <div
      v-if="!sudoActive"
      class="flex flex-col items-center justify-center gap-3 px-6 py-24 [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8"
    >
      <span class="i-lucide-shield-check size-9 text-n-iris-9" />
      <p class="text-sm font-medium text-n-slate-12">员工薪资为高敏感信息</p>
      <p class="text-xs text-n-slate-11">
        请输入登录密码完成二次验证（15 分钟内免验）；所有查看与修改将留痕。
      </p>
      <div v-if="!sudoChecking" class="flex items-center gap-2 mt-1">
        <input
          v-model="sudoPassword"
          type="password"
          class="h-9 px-3 text-sm border rounded-lg w-56 border-n-weak bg-n-solid-1 text-n-slate-12"
          placeholder="登录密码"
          @keyup.enter="unlock"
        />
        <button
          class="h-9 px-4 shrink-0 whitespace-nowrap disabled:opacity-50 text-label rounded-xl bg-wintouch-yellow text-wintouch-ink hover:enabled:bg-wintouch-yellow-hover focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-wintouch-ink/50 transition-colors duration-150"
          :disabled="!sudoPassword || sudoVerifying"
          @click="unlock"
        >
          {{ sudoVerifying ? '验证中…' : '解锁' }}
        </button>
      </div>
      <span v-if="sudoError" class="text-xs text-n-ruby-11">
        {{ sudoError }}
      </span>
    </div>

    <div
      v-else
      class="flex-1 px-4 py-3 sm:px-6 sm:py-4 [.theme-classic_&]:sm:!px-8"
    >
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
      <template v-else>
        <div class="flex flex-col gap-2 md:hidden">
          <div
            v-for="record in records"
            :key="record.id"
            class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl active:bg-n-alpha-1"
            @click="openEditDialog(record)"
          >
            <div class="flex items-center gap-2">
              <span class="font-medium truncate text-n-slate-12">
                {{ record.name }}
                <span
                  v-if="record.active === false"
                  class="ml-2 text-label-small text-n-slate-10"
                  >{{ label('PAY_HISTORY') }}</span
                >
              </span>
              <span class="flex-1" />
              <Button
                :label="t('CRM.EMPLOYEE_COMPS.TABLE.EDIT')"
                icon="i-lucide-pencil"
                color="slate"
                variant="ghost"
                size="sm"
                @click.stop="openEditDialog(record)"
              />
              <Button
                :label="t('CRM.EMPLOYEE_COMPS.TABLE.DELETE')"
                icon="i-lucide-trash-2"
                color="ruby"
                variant="ghost"
                size="sm"
                :disabled="record.active === false"
                @click.stop="deleteRecord(record)"
              />
            </div>
            <div
              class="mt-2 flex flex-wrap gap-x-3 gap-y-1 text-xs text-n-slate-11"
            >
              <span>
                {{ t('CRM.EMPLOYEE_COMPS.TABLE.MEMBER') }}：{{
                  record.ownerName ?? '—'
                }}
              </span>
              <span>
                {{ t('CRM.EMPLOYEE_COMPS.TABLE.MONTHLY_SALARY') }}：{{
                  fmtMoney(record.monthlySalaryMicros)
                }}
              </span>
              <span>
                {{ t('CRM.EMPLOYEE_COMPS.TABLE.PERF_RATIO') }}：{{
                  record.performanceRatio != null
                    ? `${record.performanceRatio}%`
                    : '—'
                }}
              </span>
              <span>
                {{ t('CRM.EMPLOYEE_COMPS.TABLE.BASELINE_TARGET') }}：{{
                  fmtMoney(record.baselineTargetMicros)
                }}
              </span>
              <span>
                {{ t('CRM.EMPLOYEE_COMPS.TABLE.RANK_NOTE') }}：{{
                  record.rankNote ?? '—'
                }}
              </span>
            </div>
          </div>
        </div>
        <table class="hidden w-full text-sm text-left border-collapse md:table">
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
              <th class="px-3 py-2 font-medium text-right">
                {{ t('CRM.EMPLOYEE_COMPS.TABLE.ACTIONS') }}
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
                {{
                  record.performanceRatio != null
                    ? `${record.performanceRatio}%`
                    : '—'
                }}
              </td>
              <td class="px-3 py-2 text-n-slate-11">
                {{ fmtMoney(record.baselineTargetMicros) }}
              </td>
              <td class="px-3 py-2 text-n-slate-11">
                {{ record.rankNote ?? '—' }}
              </td>
              <td class="px-3 py-2">
                <div class="flex items-center justify-end gap-1">
                  <Button
                    :label="t('CRM.EMPLOYEE_COMPS.TABLE.EDIT')"
                    icon="i-lucide-pencil"
                    color="slate"
                    variant="ghost"
                    size="sm"
                    @click="openEditDialog(record)"
                  />
                  <Button
                    :label="t('CRM.EMPLOYEE_COMPS.TABLE.DELETE')"
                    icon="i-lucide-trash-2"
                    color="ruby"
                    variant="ghost"
                    size="sm"
                    :disabled="record.active === false"
                    @click="deleteRecord(record)"
                  />
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </template>
    </div>

    <CrmEmployeeCompCreateDialog
      v-if="sudoActive"
      ref="createDialogRef"
      :is-loading="isDialogLoading"
      @create="createRecord"
      @update="updateRecord"
      @closed="dialogGeneration += 1"
    />
  </div>
</template>
