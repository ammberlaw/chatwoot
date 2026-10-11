<script setup>
/* global axios */
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { toPng } from 'html-to-image';
import { printElement } from 'dashboard/helper/printHelper';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import CrmKpiSheetAPI from 'dashboard/api/crm/kpiSheets';
import CrmPerfSettingsAPI from 'dashboard/api/crm/performanceSettings';

import Button from 'dashboard/components-next/button/Button.vue';
import MySignatureDialog from 'dashboard/components-next/CRM/MySignatureDialog.vue';
import CrmForwardToTeamChatDialog from 'dashboard/components-next/CRM/CrmForwardToTeamChatDialog.vue';
import { fmtYuan } from 'dashboard/helper/crmMoney';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
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
const aiBusy = ref(false);
const signatureDialogRef = ref(null);
const remark = ref('');
const returning = ref(false);
const returnReason = ref('');
const reopening = ref(false);
const reopenReason = ref('');

const camel = async data =>
  (await import('camelcase-keys')).default(data, { deep: true });

// 只读考勤参考：拉考核对象在考核月的出勤/迟到/缺勤/请假/出勤率（后端按权限收口）。
const attendance = ref(null);
const loadAttendance = async () => {
  attendance.value = null;
  const pm = sheet.value?.periodMonth;
  if (!sheet.value?.ownerId || !pm) return;
  const d = new Date(pm);
  const month = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/crm/attendances/user_summary`,
      { params: { user_id: sheet.value.ownerId, month } }
    );
    attendance.value = data;
  } catch {
    attendance.value = null;
  }
};

const load = async () => {
  loading.value = true;
  try {
    const { data } = await CrmKpiSheetAPI.show(sheetId);
    sheet.value = await camel(data);
    items.value = sheet.value.sheetItems || [];
    remark.value = sheet.value.remark || '';
    loadAttendance();
    try {
      const s = await CrmPerfSettingsAPI.get();
      setting.value = await camel(s.data);
    } catch {
      setting.value = {};
    }
  } catch {
    useAlert(t('CRM.KPI_SHEETS.LOAD_ERROR'));
    goBack();
  } finally {
    loading.value = false;
  }
};

const uid = computed(() => currentUser.value?.id);
const isAdmin = computed(() => currentUser.value?.role === 'administrator');
const canManage = computed(
  () =>
    isAdmin.value ||
    currentUser.value?.crm_manager === true ||
    currentUser.value?.crm_role === 'manager'
);
const isOwner = computed(() => sheet.value?.ownerId === uid.value);
// 审批人 id 优先取考核表自带的(show 已下发)；再兜底那个仅管理员能拉的绩效设置。
// 关键：人事/总经理不是管理员，拉不到绩效设置，只能靠考核表自带的 hrOwnerId/gmOwnerId。
const hrOwnerId = computed(
  () => sheet.value?.hrOwnerId ?? setting.value?.hrOwnerId
);
const gmOwnerId = computed(
  () => sheet.value?.gmOwnerId ?? setting.value?.gmOwnerId
);
const isHr = computed(() => isAdmin.value || uid.value === hrOwnerId.value);
const isGm = computed(() => isAdmin.value || uid.value === gmOwnerId.value);
const status = computed(() => sheet.value?.status);

const stepIndex = computed(() => STEPS.indexOf(status.value));
const canFillActual = computed(
  () => isOwner.value && status.value === 'PENDING'
);
const canScore = computed(
  () => canManage.value && status.value === 'SUBMITTED'
);

// 退回权限：当前审批步的审批人可退回到「待填报」；总经理可任意阶段越级打回。
const canReturn = computed(() => {
  if (status.value === 'SUBMITTED') return canManage.value || isGm.value;
  if (status.value === 'SCORED') return isHr.value || isGm.value;
  if (status.value === 'HR_CONFIRMED') return isGm.value;
  // 已归档：仅总经理/管理员可退回重填。
  if (status.value === 'ARCHIVED') return isAdmin.value || isGm.value;
  return false;
});
// 退回主管改分：待人事/待总经理确认时主管/人事/总经理可退；已归档时仅总经理/管理员可退，均回到「待打分」。
const canReopenScoring = computed(() => {
  if (status.value === 'ARCHIVED') return isAdmin.value || isGm.value;
  return (
    ['SCORED', 'HR_CONFIRMED'].includes(status.value) &&
    (canManage.value || isHr.value || isGm.value)
  );
});
// 被退回提醒：回到待填报且带退回原因时展示给员工。
const returnedNotice = computed(() =>
  status.value === 'PENDING' && sheet.value?.returnReason
    ? sheet.value.returnReason
    : ''
);
// 退回主管改分提醒：回到待打分且带原因时展示给主管。
const reopenNotice = computed(() =>
  status.value === 'SUBMITTED' && sheet.value?.returnReason
    ? sheet.value.returnReason
    : ''
);

// 提交截止日：考核月「次月」的第 N 天（设置里配）。给待填报的员工一个提示。
const deadlineText = computed(() => {
  const day = setting.value?.submitDeadlineDay;
  if (!day || !sheet.value?.periodMonth) return '';
  const d = new Date(sheet.value.periodMonth);
  const deadline = new Date(d.getFullYear(), d.getMonth() + 1, day);
  return `${deadline.getMonth() + 1}月${deadline.getDate()}号`;
});

const totalScore = computed(() =>
  items.value.reduce((s, i) => s + (Number(i.score) || 0), 0)
);
const hasSuggestions = computed(() =>
  items.value.some(i => i.suggestedScore != null)
);

const goBack = () =>
  router.push({
    name: 'crm_kpi_sheets_index',
    params: { accountId: accountId.value },
  });

// ── 转发到团队沟通：把本绩效表的摘要 + 回跳链接（可选表图）发到某个团队沟通会话 ──
const forwardRef = ref(null);
const captureRef = ref(null);
// 现场把绩效表主体截成 PNG File 当附件。
const makeSheetImage = async () => {
  if (!captureRef.value) return null;
  const dataUrl = await toPng(captureRef.value, {
    backgroundColor: '#ffffff',
    pixelRatio: 2,
    cacheBust: true,
  });
  const blob = await (await fetch(dataUrl)).blob();
  const name = `绩效表-${sheet.value.ownerName || ''}-${fmtMonth(sheet.value.periodMonth)}.png`;
  return new File([blob], name, { type: 'image/png' });
};
// 直接打印：把考核表主体（步骤/指标/得分/签名）交给浏览器打印对话框，可出纸或另存 PDF。
const printSheet = () => {
  if (!sheet.value) return;
  printElement(
    captureRef.value,
    `绩效考核表-${sheet.value.ownerName || ''}-${fmtMonth(sheet.value.periodMonth)}`
  );
};
const openForward = () => {
  if (!sheet.value) return;
  const resolved = router.resolve({
    name: 'crm_kpi_sheet_detail',
    query: { id: sheetId },
  });
  const link = `${window.location.origin}${resolved.href}`;
  const statusLabel = t(`CRM.KPI_SHEETS.STATUS.${status.value}`);
  const month = fmtMonth(sheet.value.periodMonth);
  const text =
    `${sheet.value.ownerName || '—'} · ${month} 绩效表\n` +
    `合计得分 ${totalScore.value} · ${statusLabel}\n${link}`;
  forwardRef.value?.open(text, { makeImage: makeSheetImage });
};

const yuan = m => (m == null ? '—' : `¥${fmtYuan(m)}`);
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
      ...(canScore.value
        ? {
            score: i.score === '' ? null : i.score,
            checked_value: i.checkedValue,
          }
        : {}),
    }));
    const { data } = await CrmKpiSheetAPI.update(sheetId, {
      sheet: { sheet_items: rows },
    });
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

// AI 建议分：后端为各指标算建议分并存库，理由随本次响应带回展示。分数只作参考，主管手动采纳/修改。
const aiSuggest = async () => {
  aiBusy.value = true;
  try {
    const { data } = await CrmKpiSheetAPI.aiSuggest(sheetId);
    const { suggestions } = await camel(data);
    const byId = Object.fromEntries((suggestions || []).map(s => [s.id, s]));
    items.value = items.value.map(i =>
      byId[i.id]
        ? {
            ...i,
            suggestedScore: byId[i.id].suggestedScore,
            suggestedReason: byId[i.id].reason,
          }
        : i
    );
    useAlert(t('CRM.KPI_SHEETS.AI_DONE'));
  } catch (err) {
    useAlert(err?.response?.data?.error || t('CRM.KPI_SHEETS.AI_ERROR'));
  } finally {
    aiBusy.value = false;
  }
};

const adopt = item => {
  item.score = item.suggestedScore;
};
const adoptAll = () =>
  items.value.forEach(i => {
    if (i.suggestedScore != null) adopt(i);
  });

// 保存备注/补充条款（主管·管理员）。
const saveRemark = async () => {
  busy.value = true;
  try {
    const { data } = await CrmKpiSheetAPI.update(sheetId, {
      sheet: { remark: remark.value },
    });
    sheet.value = await camel(data);
    items.value = sheet.value.sheetItems || [];
    remark.value = sheet.value.remark || '';
    useAlert(t('CRM.KPI_SHEETS.REMARK_SAVED'));
  } catch {
    useAlert(t('CRM.KPI_SHEETS.SAVE_ERROR'));
  } finally {
    busy.value = false;
  }
};

// 退回重填：填原因后退回到「待填报」。
const submitReturn = async () => {
  if (!returnReason.value.trim()) {
    useAlert(t('CRM.KPI_SHEETS.RETURN_NEED_REASON'));
    return;
  }
  busy.value = true;
  try {
    const { data } = await CrmKpiSheetAPI.returnSheet(
      sheetId,
      returnReason.value.trim()
    );
    sheet.value = await camel(data);
    items.value = sheet.value.sheetItems || [];
    remark.value = sheet.value.remark || '';
    returning.value = false;
    returnReason.value = '';
    useAlert(t('CRM.KPI_SHEETS.RETURNED_OK'));
  } catch (err) {
    useAlert(err?.response?.data?.error || t('CRM.KPI_SHEETS.STEP_ERROR'));
  } finally {
    busy.value = false;
  }
};

// 退回主管改分：退回到「待打分」，原因选填；员工填报与签名不动。
const submitReopen = async () => {
  busy.value = true;
  try {
    const { data } = await CrmKpiSheetAPI.reopenScoring(
      sheetId,
      reopenReason.value.trim()
    );
    sheet.value = await camel(data);
    items.value = sheet.value.sheetItems || [];
    remark.value = sheet.value.remark || '';
    reopening.value = false;
    reopenReason.value = '';
    useAlert(t('CRM.KPI_SHEETS.REOPEN_OK'));
  } catch (err) {
    useAlert(err?.response?.data?.error || t('CRM.KPI_SHEETS.STEP_ERROR'));
  } finally {
    busy.value = false;
  }
};

const submitSheet = () => save().then(() => runAction(CrmKpiSheetAPI.submit));
const scoreSheet = () => save().then(() => runAction(CrmKpiSheetAPI.score));
const hrConfirm = () => runAction(CrmKpiSheetAPI.hrConfirm);
const gmConfirm = () => runAction(CrmKpiSheetAPI.gmConfirm);

onMounted(load);

const inCls =
  'w-full h-9 px-2 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12';
</script>

<template>
  <HScrollButtons />
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div
      class="flex items-start md:items-center justify-between flex-wrap gap-y-3 flex-shrink-0 px-4 py-3 sm:px-6 sm:py-4 border-b border-n-weak [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:sm:!px-8"
    >
      <div class="flex items-center gap-3 min-w-0">
        <Button
          icon="i-lucide-arrow-left"
          size="sm"
          variant="ghost"
          color="slate"
          @click="goBack"
        />
        <div v-if="sheet" class="min-w-0">
          <h1 class="text-lg sm:text-xl font-medium text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8">
            {{ t('CRM.KPI_SHEETS.TITLE', { name: sheet.ownerName || '—' }) }}
            <span
              class="ml-2 inline-flex px-2 py-0.5 rounded-full text-xs bg-n-iris-3 text-n-iris-11"
              >{{ t(`CRM.KPI_SHEETS.STATUS.${status}`) }}</span
            >
          </h1>
          <p class="mt-0.5 text-xs text-n-slate-11 truncate">
            {{ fmtMonth(sheet.periodMonth) }} · {{ sheet.schemeName }}
          </p>
          <!-- 本月考勤只读参考（供打分/核薪时参考，不自动扣分扣款） -->
          <div
            v-if="attendance"
            class="flex flex-wrap items-center mt-1.5 gap-x-3 gap-y-1 text-xs"
          >
            <span class="text-n-slate-10">本月考勤</span>
            <span class="text-n-slate-11">
              出勤
              <b class="text-n-slate-12">{{ attendance.present }}</b>
              /{{ attendance.expected }}
            </span>
            <span class="text-n-slate-11">
              迟到
              <b
                :class="attendance.late ? 'text-n-amber-11' : 'text-n-slate-12'"
              >
                {{ attendance.late }}
              </b>
            </span>
            <span class="text-n-slate-11">
              缺勤
              <b
                :class="
                  attendance.absent ? 'text-n-ruby-11' : 'text-n-slate-12'
                "
              >
                {{ attendance.absent }}
              </b>
            </span>
            <span class="text-n-slate-11">
              请假 <b class="text-n-slate-12">{{ attendance.leave }}</b>
            </span>
            <span v-if="attendance.field" class="text-n-slate-11">
              外勤 <b class="text-n-slate-12">{{ attendance.field }}</b>
            </span>
            <span v-if="attendance.rate != null" class="text-n-slate-11">
              出勤率
              <b class="text-n-teal-11">
                {{ (attendance.rate * 100).toFixed(0) }}%
              </b>
            </span>
          </div>
        </div>
      </div>
      <div v-if="sheet" class="flex items-center flex-wrap gap-2">
        <Button
          label="打印"
          icon="i-lucide-printer"
          size="sm"
          variant="faded"
          color="slate"
          @click="printSheet"
        />
        <Button
          label="转发到团队沟通"
          icon="i-lucide-send"
          size="sm"
          variant="faded"
          color="iris"
          @click="openForward"
        />
        <Button
          v-if="canScore"
          :label="t('CRM.KPI_SHEETS.AI_SUGGEST')"
          icon="i-ph-sparkle-fill"
          size="sm"
          variant="faded"
          color="iris"
          :is-loading="aiBusy"
          :is-disabled="busy || aiBusy"
          @click="aiSuggest"
        />
        <Button
          v-if="canScore && hasSuggestions"
          :label="t('CRM.KPI_SHEETS.AI_ADOPT_ALL')"
          icon="i-lucide-check-check"
          size="sm"
          variant="ghost"
          color="teal"
          :is-disabled="busy || aiBusy"
          @click="adoptAll"
        />
        <Button
          v-if="canFillActual || canScore"
          :label="t('CRM.KPI_SHEETS.SAVE')"
          icon="i-lucide-save"
          size="sm"
          variant="faded"
          color="slate"
          :is-disabled="busy"
          @click="save"
        />
        <Button
          v-if="canReturn"
          :label="t('CRM.KPI_SHEETS.RETURN')"
          icon="i-lucide-undo-2"
          size="sm"
          variant="faded"
          color="ruby"
          :is-disabled="busy"
          @click="returning = true"
        />
        <Button
          v-if="canReopenScoring"
          :label="t('CRM.KPI_SHEETS.REOPEN')"
          icon="i-lucide-rotate-ccw"
          size="sm"
          variant="faded"
          color="amber"
          :is-disabled="busy"
          @click="reopening = true"
        />
        <Button
          v-if="isOwner && status === 'PENDING'"
          :label="t('CRM.KPI_SHEETS.SUBMIT')"
          icon="i-lucide-send"
          color="iris"
          :is-disabled="busy"
          @click="submitSheet"
        />
        <Button
          v-if="canScore"
          :label="t('CRM.KPI_SHEETS.SCORE')"
          icon="i-lucide-check"
          color="teal"
          :is-disabled="busy"
          @click="scoreSheet"
        />
      </div>
    </div>

    <div
      v-if="loading"
      class="flex items-center justify-center flex-1 text-n-slate-11"
    >
      {{ t('CRM.KPI_SHEETS.LOADING') }}
    </div>

    <div
      v-else-if="sheet"
      ref="captureRef"
      class="flex flex-col gap-7 px-4 py-4 sm:px-6 sm:py-6 [.theme-classic_&]:sm:!px-8"
    >
      <!-- 步骤条 -->
      <div class="flex items-center flex-wrap gap-1 text-sm">
        <template v-for="(st, i) in STEPS" :key="st">
          <div
            class="flex items-center gap-2"
            :class="
              i < stepIndex
                ? 'text-n-teal-11 font-medium'
                : i === stepIndex
                  ? 'text-n-iris-11 font-medium'
                  : 'text-n-slate-10'
            "
          >
            <span
              class="grid w-6 h-6 text-xs font-bold rounded-full place-content-center"
              :class="
                i < stepIndex
                  ? 'bg-n-teal-9 text-white'
                  : i === stepIndex
                    ? 'bg-n-iris-9 text-white'
                    : 'bg-n-slate-3 text-n-slate-10'
              "
            >
              {{ i < stepIndex ? '✓' : i + 1 }}
            </span>
            {{ t(`CRM.KPI_SHEETS.STEP.${st}`) }}
          </div>
          <span v-if="i < STEPS.length - 1" class="w-6 h-px mx-1 bg-n-weak" />
        </template>
      </div>

      <!-- 退回原因输入面板 -->
      <div
        v-if="returning"
        class="flex flex-col gap-2 p-4 border rounded-2xl border-n-ruby-6 bg-n-ruby-2"
      >
        <div class="text-sm font-medium text-n-ruby-11">
          {{ t('CRM.KPI_SHEETS.RETURN_TITLE') }}
        </div>
        <textarea
          v-model="returnReason"
          rows="2"
          :placeholder="t('CRM.KPI_SHEETS.RETURN_PLACEHOLDER')"
          class="reset-base w-full p-2 text-sm border rounded-lg outline-none resize-none border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-ruby-8"
        />
        <div class="flex items-center gap-2">
          <Button
            :label="t('CRM.KPI_SHEETS.RETURN_CONFIRM')"
            size="sm"
            color="ruby"
            :is-disabled="busy"
            @click="submitReturn"
          />
          <Button
            :label="t('CRM.KPI_SHEETS.CANCEL')"
            size="sm"
            variant="ghost"
            color="slate"
            :is-disabled="busy"
            @click="returning = false"
          />
        </div>
      </div>

      <!-- 退回主管改分 原因输入面板（原因选填） -->
      <div
        v-if="reopening"
        class="flex flex-col gap-2 p-4 border rounded-2xl border-n-amber-6 bg-n-amber-2"
      >
        <div class="text-sm font-medium text-n-amber-11">
          {{ t('CRM.KPI_SHEETS.REOPEN_TITLE') }}
        </div>
        <textarea
          v-model="reopenReason"
          rows="2"
          :placeholder="t('CRM.KPI_SHEETS.REOPEN_PLACEHOLDER')"
          class="reset-base w-full p-2 text-sm border rounded-lg outline-none resize-none border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-amber-8"
        />
        <div class="flex items-center gap-2">
          <Button
            :label="t('CRM.KPI_SHEETS.REOPEN_CONFIRM')"
            size="sm"
            color="amber"
            :is-disabled="busy"
            @click="submitReopen"
          />
          <Button
            :label="t('CRM.KPI_SHEETS.CANCEL')"
            size="sm"
            variant="ghost"
            color="slate"
            :is-disabled="busy"
            @click="reopening = false"
          />
        </div>
      </div>

      <!-- 被退回提醒（员工侧） -->
      <div
        v-if="returnedNotice"
        class="flex items-start gap-2 p-4 border rounded-2xl border-n-ruby-6 bg-n-ruby-2"
      >
        <span class="i-lucide-undo-2 size-4 mt-0.5 shrink-0 text-n-ruby-11" />
        <div class="text-sm text-n-slate-12">
          <span class="font-medium text-n-ruby-11">{{
            t('CRM.KPI_SHEETS.RETURNED_BANNER')
          }}</span>
          <span v-if="sheet.returnedByName" class="text-xs text-n-slate-10"
            >（{{ sheet.returnedByName }} ·
            {{ fmtDate(sheet.returnedAt) }}）</span
          >
          <div class="mt-1">{{ returnedNotice }}</div>
        </div>
      </div>

      <!-- 退回主管改分 提醒（主管侧） -->
      <div
        v-if="reopenNotice"
        class="flex items-start gap-2 p-4 border rounded-2xl border-n-amber-6 bg-n-amber-2"
      >
        <span
          class="i-lucide-rotate-ccw size-4 mt-0.5 shrink-0 text-n-amber-11"
        />
        <div class="text-sm text-n-slate-12">
          <span class="font-medium text-n-amber-11">{{
            t('CRM.KPI_SHEETS.REOPEN_BANNER')
          }}</span>
          <span v-if="sheet.returnedByName" class="text-xs text-n-slate-10"
            >（{{ sheet.returnedByName }} ·
            {{ fmtDate(sheet.returnedAt) }}）</span
          >
          <div class="mt-1">{{ reopenNotice }}</div>
        </div>
      </div>

      <!-- 待填报截止提醒 -->
      <div
        v-if="isOwner && status === 'PENDING' && deadlineText"
        class="flex items-center gap-1.5 text-xs text-n-amber-11"
      >
        <span class="i-lucide-clock size-3.5" />
        {{ t('CRM.KPI_SHEETS.DEADLINE_HINT', { date: deadlineText }) }}
      </div>

      <!-- 备注 / 补充条款 -->
      <section v-if="canManage || remark" class="flex flex-col gap-2">
        <div
          class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
        >
          {{ t('CRM.KPI_SHEETS.REMARK') }}
        </div>
        <template v-if="canManage">
          <textarea
            v-model="remark"
            rows="2"
            :placeholder="t('CRM.KPI_SHEETS.REMARK_PLACEHOLDER')"
            class="reset-base w-full p-2 text-sm border rounded-lg outline-none resize-none border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-brand"
          />
          <div>
            <Button
              :label="t('CRM.KPI_SHEETS.REMARK_SAVE')"
              icon="i-lucide-save"
              size="sm"
              variant="faded"
              color="slate"
              :is-disabled="busy"
              @click="saveRemark"
            />
          </div>
        </template>
        <p
          v-else
          class="p-3 text-sm border rounded-lg whitespace-pre-line border-n-weak bg-n-alpha-1 text-n-slate-12"
        >
          {{ remark }}
        </p>
      </section>

      <!-- 指标表 -->
      <section class="flex flex-col gap-2">
        <div
          class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
        >
          {{ t('CRM.KPI_SHEETS.DETAIL') }}
        </div>
        <HScrollButtons />
        <div class="overflow-x-auto">
          <table class="w-full text-sm border-collapse min-w-[960px]">
            <thead class="text-n-slate-11">
              <tr class="border-b border-n-weak">
                <th class="px-2 py-1.5 font-medium text-left w-24">
                  {{ t('CRM.KPI_SCHEMES.ITEMS.DIMENSION') }}
                </th>
                <th class="px-2 py-1.5 font-medium text-left w-32">
                  {{ t('CRM.KPI_SCHEMES.ITEMS.NAME') }}
                </th>
                <th class="px-2 py-1.5 font-medium text-left">
                  {{ t('CRM.KPI_SCHEMES.ITEMS.STANDARD') }}
                </th>
                <th class="px-2 py-1.5 font-medium text-left w-14">
                  {{ t('CRM.KPI_SCHEMES.ITEMS.WEIGHT') }}
                </th>
                <th class="px-2 py-1.5 font-medium text-left w-24">
                  {{ t('CRM.KPI_SCHEMES.ITEMS.BASELINE') }}
                </th>
                <th class="px-2 py-1.5 font-medium text-left w-24">
                  {{ t('CRM.KPI_SCHEMES.ITEMS.TARGET') }}
                </th>
                <th class="px-2 py-1.5 font-medium text-left w-32">
                  {{ t('CRM.KPI_SHEETS.ACTUAL') }}
                </th>
                <th class="px-2 py-1.5 font-medium text-left w-32">
                  {{ t('CRM.KPI_SHEETS.CHECKED') }}
                </th>
                <th class="px-2 py-1.5 font-medium text-left w-44">
                  {{ t('CRM.KPI_SHEETS.SCORE_COL') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="item in items"
                :key="item.id"
                class="border-b border-n-weak align-top"
              >
                <td class="px-2 py-2">
                  <span
                    class="inline-block px-2 py-0.5 rounded text-xs bg-n-iris-3 text-n-iris-11"
                    >{{ item.dimension || '—' }}</span
                  >
                </td>
                <td class="px-2 py-2 font-medium text-n-slate-12">
                  {{ item.name }}
                </td>
                <td class="px-2 py-2 text-xs leading-relaxed text-n-slate-11">
                  {{ item.standard || '—' }}
                </td>
                <td class="px-2 py-2 text-center">{{ item.weight ?? '—' }}</td>
                <td class="px-2 py-2 text-n-slate-11">
                  {{ item.baselineValue || '—' }}
                </td>
                <td class="px-2 py-2 text-n-slate-11">
                  {{ item.targetValue || '—' }}
                </td>
                <td class="px-1 py-1">
                  <input
                    v-if="canFillActual"
                    v-model="item.actualValue"
                    :class="inCls"
                    class="!border-n-iris-8"
                  />
                  <span v-else class="text-n-slate-12">{{
                    item.actualValue || '—'
                  }}</span>
                </td>
                <td class="px-1 py-1">
                  <input
                    v-if="canScore"
                    v-model="item.checkedValue"
                    :class="inCls"
                    class="!border-n-teal-8"
                    :placeholder="item.actualValue || ''"
                  />
                  <span v-else class="text-n-slate-12">{{
                    item.checkedValue || item.actualValue || '—'
                  }}</span>
                </td>
                <td class="px-1 py-1">
                  <template v-if="canScore">
                    <input
                      v-model="item.score"
                      type="number"
                      :class="inCls"
                      class="!border-n-amber-8 text-center font-medium"
                    />
                    <button
                      v-if="item.suggestedScore != null"
                      type="button"
                      class="mt-1 inline-flex items-center gap-1 text-xs font-medium text-n-iris-11 hover:underline"
                      @click="adopt(item)"
                    >
                      <span class="i-ph-sparkle-fill size-3 shrink-0" />{{
                        t('CRM.KPI_SHEETS.AI_HINT', {
                          score: item.suggestedScore,
                        })
                      }}
                    </button>
                    <p
                      v-if="item.suggestedReason"
                      class="mt-0.5 text-[11px] leading-snug text-n-slate-10"
                    >
                      {{ item.suggestedReason }}
                    </p>
                  </template>
                  <span v-else class="font-medium text-n-slate-12">{{
                    item.score ?? '—'
                  }}</span>
                </td>
              </tr>
              <tr class="bg-n-iris-3/40">
                <td colspan="8" class="px-2 py-2 font-medium text-right">
                  {{ t('CRM.KPI_SHEETS.TOTAL') }}
                </td>
                <td class="px-2 py-2 font-bold text-center text-n-iris-11">
                  {{ totalScore }} / 100
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <!-- 评分与发放规则 / 考核结果应用（下发时从方案快照）-->
      <section
        v-if="sheet.payoutNote || sheet.resultNote"
        class="grid grid-cols-1 gap-4 lg:grid-cols-2"
      >
        <div
          v-if="sheet.payoutNote"
          class="flex flex-col gap-2 p-4 rounded-2xl border border-n-weak bg-n-solid-1/60"
        >
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('CRM.KPI_SHEETS.SECTION_RULES') }}
          </span>
          <p
            class="text-sm leading-relaxed whitespace-pre-wrap text-n-slate-11"
          >
            {{ sheet.payoutNote }}
          </p>
        </div>
        <div
          v-if="sheet.resultNote"
          class="flex flex-col gap-2 p-4 rounded-2xl border border-n-weak bg-n-solid-1/60"
        >
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('CRM.KPI_SHEETS.SECTION_RESULT') }}
          </span>
          <p
            class="text-sm leading-relaxed whitespace-pre-wrap text-n-slate-11"
          >
            {{ sheet.resultNote }}
          </p>
        </div>
      </section>

      <!-- 绩效核算 -->
      <section class="flex flex-col gap-2">
        <div
          class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
        >
          {{ t('CRM.KPI_SHEETS.PAYOUT.TITLE') }}
        </div>
        <div
          v-if="sheet.probation"
          class="p-4 rounded-2xl border border-n-amber-6 bg-n-amber-3/40 text-sm text-n-slate-12"
        >
          {{ t('CRM.KPI_SHEETS.PROBATION_NOTE') }}
        </div>
        <div v-else class="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <div class="p-4 rounded-2xl border border-n-weak bg-n-solid-1/60">
            <div class="text-xs text-n-slate-10">
              {{ t('CRM.KPI_SHEETS.BASE') }}（{{
                yuan(sheet.monthlySalaryMicros)
              }}
              × {{ sheet.performanceRatio ?? '—' }}%）
            </div>
            <div class="mt-1 text-lg font-bold text-n-iris-11">
              {{ yuan(sheet.performanceBaseMicros) }}
            </div>
          </div>
          <div class="p-4 rounded-2xl border border-n-weak bg-n-solid-1/60">
            <div class="text-xs text-n-slate-10">
              {{ t('CRM.KPI_SHEETS.COEFFICIENT') }}（{{
                t('CRM.KPI_SHEETS.SCORE_COL')
              }}
              {{ sheet.totalScore ?? totalScore }}）
            </div>
            <div class="mt-1 text-lg font-bold text-n-iris-11">
              {{ sheet.payoutCoefficient ?? '—' }}
            </div>
          </div>
          <div
            class="p-4 rounded-2xl border border-n-iris-6 bg-gradient-to-br from-n-iris-3/60 to-n-iris-4/40 sm:col-span-2"
          >
            <div class="text-xs text-n-slate-10">
              {{ t('CRM.KPI_SHEETS.ACTUAL_PAYOUT') }}
            </div>
            <div class="mt-1 text-2xl font-bold text-n-iris-11">
              {{ yuan(sheet.actualPayoutMicros) }}
            </div>
          </div>
        </div>
      </section>

      <!-- 4 方电子签 -->
      <section class="flex flex-col gap-2">
        <div
          class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
        >
          {{ t('CRM.KPI_SHEETS.SIGN') }}
        </div>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <!-- 员工 -->
          <div
            class="flex flex-col gap-2 p-4 border border-dashed rounded-2xl border-n-strong bg-n-solid-1/40"
          >
            <h4 class="text-sm font-medium text-n-slate-12">
              ① {{ t('CRM.KPI_SHEETS.SIGN_EMPLOYEE') }}
            </h4>
            <img
              v-if="sheet.employeeSignatureUrl"
              :src="sheet.employeeSignatureUrl"
              class="object-contain w-full h-20 bg-white rounded-lg"
            />
            <div
              v-else
              class="h-20 grid place-content-center text-xs text-n-slate-10 bg-n-alpha-1 rounded-lg"
            >
              {{ t('CRM.KPI_SHEETS.NOT_SIGNED') }}
            </div>
            <div class="text-xs text-n-slate-10">
              {{
                sheet.employeeSignedAt
                  ? t('CRM.KPI_SHEETS.SIGNED_AT', {
                      date: fmtDate(sheet.employeeSignedAt),
                    })
                  : '—'
              }}
            </div>
          </div>
          <!-- 主管 -->
          <div
            class="flex flex-col gap-2 p-4 border border-dashed rounded-2xl border-n-strong bg-n-solid-1/40"
          >
            <h4 class="text-sm font-medium text-n-slate-12">
              ② {{ t('CRM.KPI_SHEETS.SIGN_MANAGER') }}
            </h4>
            <img
              v-if="sheet.managerSignatureUrl"
              :src="sheet.managerSignatureUrl"
              class="object-contain w-full h-20 bg-white rounded-lg"
            />
            <div
              v-else
              class="h-20 grid place-content-center text-xs text-n-slate-10 bg-n-alpha-1 rounded-lg"
            >
              {{ t('CRM.KPI_SHEETS.NOT_SIGNED') }}
            </div>
            <div class="text-xs text-n-slate-10">
              {{
                sheet.managerName
                  ? `${sheet.managerName} · ${fmtDate(sheet.managerSignedAt)}`
                  : '—'
              }}
            </div>
          </div>
          <!-- 人事 -->
          <div
            class="flex flex-col gap-2 p-4 border border-dashed rounded-2xl border-n-strong bg-n-solid-1/40"
          >
            <h4 class="text-sm font-medium text-n-slate-12">
              ③ {{ t('CRM.KPI_SHEETS.SIGN_HR') }}
            </h4>
            <img
              v-if="sheet.hrSignatureUrl"
              :src="sheet.hrSignatureUrl"
              class="object-contain w-full h-20 bg-white rounded-lg"
            />
            <template v-else-if="status === 'SCORED' && isHr">
              <Button
                :label="t('CRM.KPI_SHEETS.HR_CONFIRM')"
                size="sm"
                color="iris"
                :is-disabled="busy"
                @click="hrConfirm"
              />
            </template>
            <div
              v-else
              class="h-20 grid place-content-center text-xs text-n-slate-10 bg-n-alpha-1 rounded-lg"
            >
              {{ t('CRM.KPI_SHEETS.WAIT_PREV') }}
            </div>
            <div class="text-xs text-n-slate-10">
              {{
                sheet.hrName
                  ? `${sheet.hrName} · ${fmtDate(sheet.hrConfirmedAt)}`
                  : '—'
              }}
            </div>
          </div>
          <!-- 总经理 -->
          <div
            class="flex flex-col gap-2 p-4 border border-dashed rounded-2xl border-n-strong bg-n-solid-1/40"
          >
            <h4 class="text-sm font-medium text-n-slate-12">
              ④ {{ t('CRM.KPI_SHEETS.SIGN_GM') }}
            </h4>
            <img
              v-if="sheet.gmSignatureUrl"
              :src="sheet.gmSignatureUrl"
              class="object-contain w-full h-20 bg-white rounded-lg"
            />
            <template v-else-if="status === 'HR_CONFIRMED' && isGm">
              <Button
                :label="t('CRM.KPI_SHEETS.GM_CONFIRM')"
                size="sm"
                color="iris"
                :is-disabled="busy"
                @click="gmConfirm"
              />
            </template>
            <div
              v-else
              class="h-20 grid place-content-center text-xs text-n-slate-10 bg-n-alpha-1 rounded-lg"
            >
              {{ t('CRM.KPI_SHEETS.WAIT_PREV') }}
            </div>
            <div class="text-xs text-n-slate-10">
              {{
                sheet.gmName
                  ? `${sheet.gmName} · ${fmtDate(sheet.gmConfirmedAt)}`
                  : '—'
              }}
            </div>
          </div>
        </div>
      </section>
    </div>
    <MySignatureDialog ref="signatureDialogRef" />
    <CrmForwardToTeamChatDialog ref="forwardRef" />
  </div>
</template>
