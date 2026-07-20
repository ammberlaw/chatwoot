<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import CrmKpiSheetAPI from 'dashboard/api/crm/kpiSheets';
import CrmPerfSettingsAPI from 'dashboard/api/crm/performanceSettings';

import Button from 'dashboard/components-next/button/Button.vue';
import MySignatureDialog from 'dashboard/components-next/CRM/MySignatureDialog.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { accountId } = useAccount();
const currentUser = useMapGetter('getCurrentUser');

const STEPS = ['PENDING', 'SUBMITTED', 'SCORED', 'HR_CONFIRMED', 'ARCHIVED'];
const sheetId = Number(route.query.id);

const sheet = ref(null);
const items = ref([]);
const setting = ref({});
const loading = ref(true);
const busy = ref(false);
const signatureDialogRef = ref(null);

const camel = async data => (await import('camelcase-keys')).default(data, { deep: true });

const load = async () => {
  loading.value = true;
  try {
    const { data } = await CrmKpiSheetAPI.show(sheetId);
    sheet.value = await camel(data);
    items.value = sheet.value.sheetItems || [];
    try {
      const s = await CrmPerfSettingsAPI.get();
      setting.value = await camel(s.data);
    } catch { setting.value = {}; }
  } catch {
    useAlert(t('CRM.KPI_SHEETS.LOAD_ERROR'));
    goBack();
  } finally {
    loading.value = false;
  }
};

const uid = computed(() => currentUser.value?.id);
const isAdmin = computed(() => currentUser.value?.role === 'administrator');
const canManage = computed(() => isAdmin.value || currentUser.value?.crm_role === 'manager');
const isOwner = computed(() => sheet.value?.ownerId === uid.value);
const isHr = computed(() => isAdmin.value || uid.value === setting.value?.hrOwnerId);
const isGm = computed(() => isAdmin.value || uid.value === setting.value?.gmOwnerId);
const status = computed(() => sheet.value?.status);

const stepIndex = computed(() => STEPS.indexOf(status.value));
const canFillActual = computed(() => isOwner.value && status.value === 'PENDING');
const canScore = computed(() => canManage.value && status.value === 'SUBMITTED');

const totalScore = computed(() =>
  items.value.reduce((s, i) => s + (Number(i.score) || 0), 0)
);

const goBack = () =>
  router.push({ name: 'crm_kpi_sheets_index', params: { accountId: accountId.value } });

const yuan = m => (m == null ? '—' : `¥${Math.round(m / 1_000_000).toLocaleString()}`);
const fmtMonth = v => {
  if (!v) return '—';
  const d = new Date(v);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
};
const fmtDate = v => (v ? new Date(v).toLocaleDateString() : '');

// 保存完成值 / 得分（按当前可编辑列）。
const save = async () => {
  busy.value = true;
  try {
    const rows = items.value.map(i => ({
      id: i.id,
      ...(canFillActual.value ? { actual_value: i.actualValue } : {}),
      ...(canScore.value ? { score: i.score === '' ? null : i.score } : {}),
    }));
    const { data } = await CrmKpiSheetAPI.update(sheetId, { sheet: { sheet_items: rows } });
    sheet.value = await camel(data);
    items.value = sheet.value.sheetItems || [];
    useAlert(t('CRM.KPI_SHEETS.SAVED'));
  } catch {
    useAlert(t('CRM.KPI_SHEETS.SAVE_ERROR'));
  } finally {
    busy.value = false;
  }
};

// 一键盖章：不传文件，后端取签字人存的个人签名盖上；未设置则弹「我的签名」引导设置。
const runAction = async fn => {
  busy.value = true;
  try {
    const { data } = await fn(sheetId);
    sheet.value = await camel(data);
    items.value = sheet.value.sheetItems || [];
    useAlert(t('CRM.KPI_SHEETS.STEP_OK'));
  } catch (err) {
    const msg = err?.response?.data?.error || t('CRM.KPI_SHEETS.STEP_ERROR');
    useAlert(msg);
    if (msg.includes('个人签名')) signatureDialogRef.value?.open();
  } finally {
    busy.value = false;
  }
};

const submitSheet = () => save().then(() => runAction(CrmKpiSheetAPI.submit));
const scoreSheet = () => save().then(() => runAction(CrmKpiSheetAPI.score));
const hrConfirm = () => runAction(CrmKpiSheetAPI.hrConfirm);
const gmConfirm = () => runAction(CrmKpiSheetAPI.gmConfirm);

onMounted(load);

const inCls = 'w-full h-9 px-2 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12';
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5">
    <div class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak">
      <div class="flex items-center gap-3">
        <Button icon="i-lucide-arrow-left" size="sm" variant="ghost" color="slate" @click="goBack" />
        <div v-if="sheet">
          <h1 class="text-xl font-medium text-n-slate-12">
            {{ t('CRM.KPI_SHEETS.TITLE', { name: sheet.ownerName || '—' }) }}
            <span class="ml-2 inline-flex px-2 py-0.5 rounded-full text-xs bg-n-iris-3 text-n-iris-11">{{ t(`CRM.KPI_SHEETS.STATUS.${status}`) }}</span>
          </h1>
          <p class="mt-0.5 text-xs text-n-slate-11">{{ fmtMonth(sheet.periodMonth) }} · {{ sheet.schemeName }}</p>
        </div>
      </div>
      <div v-if="sheet" class="flex items-center gap-2">
        <Button v-if="canFillActual || canScore" :label="t('CRM.KPI_SHEETS.SAVE')" icon="i-lucide-save" size="sm" variant="faded" color="slate" :is-disabled="busy" @click="save" />
        <Button v-if="isOwner && status==='PENDING'" :label="t('CRM.KPI_SHEETS.SUBMIT')" icon="i-lucide-send" color="iris" :is-disabled="busy" @click="submitSheet" />
        <Button v-if="canScore" :label="t('CRM.KPI_SHEETS.SCORE')" icon="i-lucide-check" color="teal" :is-disabled="busy" @click="scoreSheet" />
      </div>
    </div>

    <div v-if="loading" class="flex items-center justify-center flex-1 text-n-slate-11">{{ t('CRM.KPI_SHEETS.LOADING') }}</div>

    <div v-else-if="sheet" class="flex flex-col gap-7 px-6 py-6">
      <!-- 步骤条 -->
      <div class="flex items-center flex-wrap gap-1 text-sm">
        <template v-for="(st, i) in STEPS" :key="st">
          <div class="flex items-center gap-2" :class="i < stepIndex ? 'text-n-teal-11 font-medium' : i === stepIndex ? 'text-n-iris-11 font-medium' : 'text-n-slate-10'">
            <span class="grid w-6 h-6 text-xs font-bold rounded-full place-content-center"
              :class="i < stepIndex ? 'bg-n-teal-9 text-white' : i === stepIndex ? 'bg-n-iris-9 text-white' : 'bg-n-slate-3 text-n-slate-10'">
              {{ i < stepIndex ? '✓' : i + 1 }}
            </span>
            {{ t(`CRM.KPI_SHEETS.STEP.${st}`) }}
          </div>
          <span v-if="i < STEPS.length - 1" class="w-6 h-px mx-1 bg-n-weak" />
        </template>
      </div>

      <!-- 指标表 -->
      <section class="flex flex-col gap-2">
        <div class="text-xs font-semibold tracking-wide uppercase text-n-slate-10">{{ t('CRM.KPI_SHEETS.DETAIL') }}</div>
        <div class="overflow-x-auto">
          <table class="w-full text-sm border-collapse min-w-[860px]">
            <thead class="text-n-slate-11">
              <tr class="border-b border-n-weak">
                <th class="px-2 py-1.5 font-medium text-left w-24">{{ t('CRM.KPI_SCHEMES.ITEMS.DIMENSION') }}</th>
                <th class="px-2 py-1.5 font-medium text-left w-32">{{ t('CRM.KPI_SCHEMES.ITEMS.NAME') }}</th>
                <th class="px-2 py-1.5 font-medium text-left">{{ t('CRM.KPI_SCHEMES.ITEMS.STANDARD') }}</th>
                <th class="px-2 py-1.5 font-medium text-left w-14">{{ t('CRM.KPI_SCHEMES.ITEMS.WEIGHT') }}</th>
                <th class="px-2 py-1.5 font-medium text-left w-24">{{ t('CRM.KPI_SCHEMES.ITEMS.TARGET') }}</th>
                <th class="px-2 py-1.5 font-medium text-left w-32">{{ t('CRM.KPI_SHEETS.ACTUAL') }}</th>
                <th class="px-2 py-1.5 font-medium text-left w-24">{{ t('CRM.KPI_SHEETS.SCORE_COL') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="item in items" :key="item.id" class="border-b border-n-weak align-top">
                <td class="px-2 py-2"><span class="inline-block px-2 py-0.5 rounded text-xs bg-n-iris-3 text-n-iris-11">{{ item.dimension || '—' }}</span></td>
                <td class="px-2 py-2 font-medium text-n-slate-12">{{ item.name }}</td>
                <td class="px-2 py-2 text-xs leading-relaxed text-n-slate-11">{{ item.standard || '—' }}</td>
                <td class="px-2 py-2 text-center">{{ item.weight ?? '—' }}</td>
                <td class="px-2 py-2 text-n-slate-11">{{ item.targetValue || '—' }}</td>
                <td class="px-1 py-1">
                  <input v-if="canFillActual" v-model="item.actualValue" :class="inCls" class="!border-n-iris-8" />
                  <span v-else class="text-n-slate-12">{{ item.actualValue || '—' }}</span>
                </td>
                <td class="px-1 py-1">
                  <input v-if="canScore" v-model="item.score" type="number" :class="inCls" class="!border-n-amber-8 text-center font-medium" />
                  <span v-else class="font-medium text-n-slate-12">{{ item.score ?? '—' }}</span>
                </td>
              </tr>
              <tr class="bg-n-iris-3/40">
                <td colspan="6" class="px-2 py-2 font-medium text-right">{{ t('CRM.KPI_SHEETS.TOTAL') }}</td>
                <td class="px-2 py-2 font-bold text-center text-n-iris-11">{{ totalScore }} / 100</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <!-- 绩效核算 -->
      <section class="flex flex-col gap-2">
        <div class="text-xs font-semibold tracking-wide uppercase text-n-slate-10">{{ t('CRM.KPI_SHEETS.PAYOUT') }}</div>
        <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <div class="p-4 rounded-2xl border border-n-weak bg-n-solid-1/60">
            <div class="text-xs text-n-slate-10">{{ t('CRM.KPI_SHEETS.BASE') }}（{{ yuan(sheet.monthlySalaryMicros) }} × {{ sheet.performanceRatio ?? '—' }}%）</div>
            <div class="mt-1 text-lg font-bold text-n-iris-11">{{ yuan(sheet.performanceBaseMicros) }}</div>
          </div>
          <div class="p-4 rounded-2xl border border-n-weak bg-n-solid-1/60">
            <div class="text-xs text-n-slate-10">{{ t('CRM.KPI_SHEETS.COEFFICIENT') }}（{{ t('CRM.KPI_SHEETS.SCORE_COL') }} {{ sheet.totalScore ?? totalScore }}）</div>
            <div class="mt-1 text-lg font-bold text-n-iris-11">{{ sheet.payoutCoefficient ?? '—' }}</div>
          </div>
          <div class="p-4 rounded-2xl border border-n-iris-6 bg-gradient-to-br from-n-iris-3/60 to-n-iris-4/40 sm:col-span-2">
            <div class="text-xs text-n-slate-10">{{ t('CRM.KPI_SHEETS.ACTUAL_PAYOUT') }}</div>
            <div class="mt-1 text-2xl font-bold text-n-iris-11">{{ yuan(sheet.actualPayoutMicros) }}</div>
          </div>
        </div>
      </section>

      <!-- 4 方电子签 -->
      <section class="flex flex-col gap-2">
        <div class="text-xs font-semibold tracking-wide uppercase text-n-slate-10">{{ t('CRM.KPI_SHEETS.SIGN') }}</div>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <!-- 员工 -->
          <div class="flex flex-col gap-2 p-4 border border-dashed rounded-2xl border-n-strong bg-n-solid-1/40">
            <h4 class="text-sm font-medium text-n-slate-12">① {{ t('CRM.KPI_SHEETS.SIGN_EMPLOYEE') }}</h4>
            <img v-if="sheet.employeeSignatureUrl" :src="sheet.employeeSignatureUrl" class="object-contain w-full h-20 bg-white rounded-lg" />
            <div v-else class="h-20 grid place-content-center text-xs text-n-slate-10 bg-n-alpha-1 rounded-lg">{{ t('CRM.KPI_SHEETS.NOT_SIGNED') }}</div>
            <div class="text-xs text-n-slate-10">{{ sheet.employeeSignedAt ? t('CRM.KPI_SHEETS.SIGNED_AT', { date: fmtDate(sheet.employeeSignedAt) }) : '—' }}</div>
          </div>
          <!-- 主管 -->
          <div class="flex flex-col gap-2 p-4 border border-dashed rounded-2xl border-n-strong bg-n-solid-1/40">
            <h4 class="text-sm font-medium text-n-slate-12">② {{ t('CRM.KPI_SHEETS.SIGN_MANAGER') }}</h4>
            <img v-if="sheet.managerSignatureUrl" :src="sheet.managerSignatureUrl" class="object-contain w-full h-20 bg-white rounded-lg" />
            <div v-else class="h-20 grid place-content-center text-xs text-n-slate-10 bg-n-alpha-1 rounded-lg">{{ t('CRM.KPI_SHEETS.NOT_SIGNED') }}</div>
            <div class="text-xs text-n-slate-10">{{ sheet.managerName ? `${sheet.managerName} · ${fmtDate(sheet.managerSignedAt)}` : '—' }}</div>
          </div>
          <!-- 人事 -->
          <div class="flex flex-col gap-2 p-4 border border-dashed rounded-2xl border-n-strong bg-n-solid-1/40">
            <h4 class="text-sm font-medium text-n-slate-12">③ {{ t('CRM.KPI_SHEETS.SIGN_HR') }}</h4>
            <img v-if="sheet.hrSignatureUrl" :src="sheet.hrSignatureUrl" class="object-contain w-full h-20 bg-white rounded-lg" />
            <template v-else-if="status==='SCORED' && isHr">
              <Button :label="t('CRM.KPI_SHEETS.HR_CONFIRM')" size="sm" color="iris" :is-disabled="busy" @click="hrConfirm" />
            </template>
            <div v-else class="h-20 grid place-content-center text-xs text-n-slate-10 bg-n-alpha-1 rounded-lg">{{ t('CRM.KPI_SHEETS.WAIT_PREV') }}</div>
            <div class="text-xs text-n-slate-10">{{ sheet.hrName ? `${sheet.hrName} · ${fmtDate(sheet.hrConfirmedAt)}` : '—' }}</div>
          </div>
          <!-- 总经理 -->
          <div class="flex flex-col gap-2 p-4 border border-dashed rounded-2xl border-n-strong bg-n-solid-1/40">
            <h4 class="text-sm font-medium text-n-slate-12">④ {{ t('CRM.KPI_SHEETS.SIGN_GM') }}</h4>
            <img v-if="sheet.gmSignatureUrl" :src="sheet.gmSignatureUrl" class="object-contain w-full h-20 bg-white rounded-lg" />
            <template v-else-if="status==='HR_CONFIRMED' && isGm">
              <Button :label="t('CRM.KPI_SHEETS.GM_CONFIRM')" size="sm" color="iris" :is-disabled="busy" @click="gmConfirm" />
            </template>
            <div v-else class="h-20 grid place-content-center text-xs text-n-slate-10 bg-n-alpha-1 rounded-lg">{{ t('CRM.KPI_SHEETS.WAIT_PREV') }}</div>
            <div class="text-xs text-n-slate-10">{{ sheet.gmName ? `${sheet.gmName} · ${fmtDate(sheet.gmConfirmedAt)}` : '—' }}</div>
          </div>
        </div>
      </section>
    </div>
    <MySignatureDialog ref="signatureDialogRef" />
  </div>
</template>
