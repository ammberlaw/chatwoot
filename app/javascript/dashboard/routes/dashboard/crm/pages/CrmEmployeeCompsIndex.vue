<script setup>
/* global axios */
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
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

// ── 敏感区二次验证：先输登录密码解锁（15 分钟免验），解锁后才拉数据 ──
const { accountId } = useAccount();
const sudoActive = ref(false);
const sudoChecking = ref(true);
const sudoPassword = ref('');
const sudoError = ref('');
const sudoVerifying = ref(false);
const sudoUrl = () =>
  `/api/v1/accounts/${accountId.value}/crm/sensitive_session`;
const checkSudo = async () => {
  try {
    const { data } = await axios.get(sudoUrl());
    sudoActive.value = !!data.active;
  } catch {
    sudoActive.value = false;
  } finally {
    sudoChecking.value = false;
  }
  if (sudoActive.value) fetchRecords();
};
const unlock = async () => {
  if (!sudoPassword.value || sudoVerifying.value) return;
  sudoVerifying.value = true;
  sudoError.value = '';
  try {
    await axios.post(sudoUrl(), { password: sudoPassword.value });
    sudoActive.value = true;
    sudoPassword.value = '';
    fetchRecords();
  } catch (e) {
    sudoError.value =
      e.response?.status === 401 ? '密码不正确' : '验证失败，请重试';
  } finally {
    sudoVerifying.value = false;
  }
};

onMounted(checkSudo);

// 金额默认打码，页头开关显隐（防旁人瞟屏）。
const showMoney = ref(false);
const fmtMoney = micros => {
  if (micros == null) return '—';
  return showMoney.value
    ? `¥ ${(micros / 1_000_000).toLocaleString()}`
    : '¥ ******';
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
          {{ t('CRM.EMPLOYEE_COMPS.HEADER') }}
        </h1>
        <p class="mt-0.5 text-xs text-n-slate-11">
          {{ t('CRM.EMPLOYEE_COMPS.SUBTITLE') }}
        </p>
      </div>
      <div v-if="sudoActive" class="flex items-center gap-2">
        <Button
          :label="showMoney ? '隐藏金额' : '显示金额'"
          :icon="showMoney ? 'i-lucide-eye-off' : 'i-lucide-eye'"
          color="slate"
          variant="faded"
          @click="showMoney = !showMoney"
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
      class="flex flex-col items-center justify-center gap-3 px-6 py-24"
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
          class="h-9 px-4 text-sm font-medium text-white rounded-lg shrink-0 whitespace-nowrap bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-50"
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

    <div v-else class="flex-1 px-6 py-4">
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
