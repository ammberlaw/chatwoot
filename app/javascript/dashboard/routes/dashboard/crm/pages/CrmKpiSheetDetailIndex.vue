<script setup>
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
import {
  DropdownBody,
  DropdownContainer,
  DropdownItem,
} from 'dashboard/components-next/dropdown-menu/base';

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

const goBack = () =>
  router.push({
    name: 'crm_kpi_sheets_index',
    params: { accountId: accountId.value },
  });

const fmtMonth = v => {
  if (!v) return '—';
  const d = new Date(v);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
};
const fmtDate = v => (v ? new Date(v).toLocaleDateString() : '');

const load = async () => {
  loading.value = true;
  try {
    const { data } = await CrmKpiSheetAPI.show(sheetId);
    sheet.value = await camel(data);
    items.value = sheet.value.sheetItems || [];
    remark.value = sheet.value.remark || '';
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

// ── 转发到团队沟通：把本绩效表的摘要 + 回跳链接（可选表图）发到某个团队沟通会话 ──
const forwardRef = ref(null);
const captureRef = ref(null);
// 屏幕上折叠长标准；打印和转发时仍包含完整规则。
const withExpandedDetails = async action => {
  const collapsed = Array.from(
    captureRef.value.querySelectorAll('details:not([open])')
  );
  collapsed.forEach(detail => {
    detail.open = true;
  });
  try {
    return await action();
  } finally {
    collapsed.forEach(detail => {
      detail.open = false;
    });
  }
};
// 现场把绩效表主体截成 PNG File 当附件。
const makeSheetImage = async () => {
  if (!captureRef.value) return null;
  const dataUrl = await withExpandedDetails(() =>
    toPng(captureRef.value, {
      backgroundColor: '#ffffff',
      pixelRatio: 2,
      cacheBust: true,
    })
  );
  const blob = await (await fetch(dataUrl)).blob();
  const name = `绩效表-${sheet.value.ownerName || ''}-${fmtMonth(sheet.value.periodMonth)}.png`;
  return new File([blob], name, { type: 'image/png' });
};
// 直接打印：把考核表主体（步骤/指标/得分/签名）交给浏览器打印对话框，可出纸或另存 PDF。
const printSheet = () => {
  if (!sheet.value) return;
  withExpandedDetails(() =>
    printElement(
      captureRef.value,
      `绩效考核表-${sheet.value.ownerName || ''}-${fmtMonth(sheet.value.periodMonth)}`
    )
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
      sheet: {
        sheet_items: rows,
        ...(canScore.value ? { remark: remark.value } : {}),
      },
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

const hasScores = computed(() =>
  items.value.some(item => item.score != null && item.score !== '')
);
const signatureRows = computed(() => [
  {
    key: 'employee',
    label: t('CRM.KPI_SHEETS.UI.EMPLOYEE'),
    url: sheet.value?.employeeSignatureUrl,
    name: sheet.value?.ownerName,
    date: sheet.value?.employeeSignedAt,
  },
  {
    key: 'manager',
    label: t('CRM.KPI_SHEETS.UI.MANAGER'),
    url: sheet.value?.managerSignatureUrl,
    name: sheet.value?.managerName,
    date: sheet.value?.managerSignedAt,
  },
  {
    key: 'hr',
    label: t('CRM.KPI_SHEETS.UI.HR'),
    url: sheet.value?.hrSignatureUrl,
    name: sheet.value?.hrName,
    date: sheet.value?.hrConfirmedAt,
  },
  {
    key: 'gm',
    label: t('CRM.KPI_SHEETS.UI.GM'),
    url: sheet.value?.gmSignatureUrl,
    name: sheet.value?.gmName,
    date: sheet.value?.gmConfirmedAt,
  },
]);
const inCls =
  'reset-base w-full h-10 px-3 text-label border rounded-lg outline-none border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-slate-10 focus:ring-2 focus:ring-n-slate-3 disabled:opacity-50';
</script>

<template>
  <div
    class="flex h-full w-full flex-col overflow-y-auto rounded-3xl border border-n-weak bg-n-slate-2"
  >
    <header
      class="flex flex-wrap items-start justify-between gap-4 px-5 py-6 sm:px-8"
    >
      <div v-if="sheet" class="min-w-0">
        <button
          type="button"
          class="mb-3 inline-flex items-center gap-1.5 text-label-small text-n-slate-11 hover:text-n-slate-12"
          @click="goBack"
        >
          <span class="i-lucide-arrow-left size-3.5" />
          {{ t('CRM.KPI_SHEETS.LIST_HEADER') }}
        </button>
        <div class="flex flex-wrap items-center gap-3">
          <h1 class="text-heading-1 text-n-slate-12">
            {{ t('CRM.KPI_SHEETS.TITLE', { name: sheet.ownerName || '—' }) }}
          </h1>
          <span
            class="rounded-md bg-n-amber-3 px-2.5 py-1 text-label-small text-n-slate-12"
            >{{ t(`CRM.KPI_SHEETS.STATUS.${status}`) }}</span
          >
        </div>
        <p class="mb-0 mt-1.5 text-label-small text-n-slate-11">
          {{ fmtMonth(sheet.periodMonth) }} · {{ sheet.schemeName }}
        </p>
      </div>
      <div v-if="sheet" class="flex items-center gap-2">
        <DropdownContainer class="z-30 [&>div]:right-0">
          <template #trigger="{ toggle, isOpen }">
            <Button
              :label="t('CRM.KPI_SHEETS.UI.MORE')"
              icon="i-lucide-ellipsis"
              variant="outline"
              color="slate"
              size="sm"
              :aria-expanded="isOpen"
              @click="toggle"
            />
          </template>
          <DropdownBody class="right-0 top-0 w-56">
            <DropdownItem
              :label="t('CRM.KPI_SHEETS.UI.PRINT')"
              icon="i-lucide-printer"
              :click="printSheet"
            />
            <DropdownItem
              :label="t('CRM.KPI_SHEETS.UI.FORWARD')"
              icon="i-lucide-send"
              :click="openForward"
            />
            <DropdownItem
              v-if="canReopenScoring"
              :label="t('CRM.KPI_SHEETS.REOPEN')"
              icon="i-lucide-rotate-ccw"
              :disabled="busy"
              :click="() => (reopening = true)"
            />
          </DropdownBody>
        </DropdownContainer>
        <Button
          v-if="canFillActual || canScore"
          :label="t('CRM.KPI_SHEETS.UI.SAVE_DRAFT')"
          variant="outline"
          color="slate"
          size="sm"
          :is-disabled="busy"
          @click="save"
        />
      </div>
    </header>
    <div
      v-if="loading"
      class="flex flex-1 items-center justify-center text-n-slate-11"
    >
      {{ t('CRM.KPI_SHEETS.LOADING') }}
    </div>
    <div
      v-else-if="sheet"
      ref="captureRef"
      class="flex flex-col gap-5 px-4 pb-8 sm:px-6 xl:px-8"
    >
      <ol
        :aria-label="t('CRM.KPI_SHEETS.UI.WORKFLOW')"
        class="m-0 flex list-none items-center gap-2 overflow-x-auto px-1 py-2 text-label sm:gap-3 lg:justify-between"
      >
        <li
          v-for="(st, i) in STEPS"
          :key="st"
          class="flex shrink-0 items-center gap-2.5"
          :class="i === STEPS.length - 1 ? '' : 'grow'"
          :aria-current="i === stepIndex ? 'step' : undefined"
        >
          <span
            class="grid size-8 shrink-0 place-content-center rounded-full text-label"
            :class="
              i < stepIndex
                ? 'bg-n-slate-12 text-n-solid-1'
                : i === stepIndex
                  ? 'bg-n-amber-9 text-n-slate-12'
                  : 'bg-n-slate-4 text-n-slate-10'
            "
            >{{ i < stepIndex ? '✓' : i + 1 }}</span
          >
          <span
            class="whitespace-nowrap"
            :class="
              i <= stepIndex ? 'font-medium text-n-slate-12' : 'text-n-slate-10'
            "
            >{{ t(`CRM.KPI_SHEETS.STEP.${st}`) }}</span
          >
          <span
            v-if="i < STEPS.length - 1"
            class="mx-1 h-px min-w-5 flex-1 bg-n-weak lg:mx-3"
          />
        </li>
      </ol>
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
          <span v-if="sheet.returnedByName" class="text-xs text-n-slate-10">{{
            t('CRM.KPI_SHEETS.UI.ACTOR_DATE', {
              name: sheet.returnedByName,
              date: fmtDate(sheet.returnedAt),
            })
          }}</span>
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
          <span v-if="sheet.returnedByName" class="text-xs text-n-slate-10">{{
            t('CRM.KPI_SHEETS.UI.ACTOR_DATE', {
              name: sheet.returnedByName,
              date: fmtDate(sheet.returnedAt),
            })
          }}</span>
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

      <div
        class="grid min-w-0 grid-cols-1 items-start gap-4 xl:grid-cols-[minmax(0,1fr)_300px] 2xl:grid-cols-[minmax(0,1fr)_340px]"
      >
        <div class="flex min-w-0 flex-col gap-4">
          <section
            class="min-w-0 rounded-2xl border border-n-weak bg-n-solid-1 p-4 lg:p-5"
          >
            <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
              <div class="flex flex-wrap items-baseline gap-3">
                <h2 class="text-heading-2 text-n-slate-12">
                  {{ t('CRM.KPI_SHEETS.UI.DETAIL') }}
                </h2>
                <span class="text-label-small text-n-slate-11">{{
                  t('CRM.KPI_SHEETS.UI.DETAIL_HINT')
                }}</span>
              </div>
              <div v-if="canScore" class="flex items-center gap-2">
                <Button
                  :label="t('CRM.KPI_SHEETS.AI_SUGGEST')"
                  icon="i-ph-sparkle-fill"
                  size="sm"
                  variant="ghost"
                  color="slate"
                  :is-loading="aiBusy"
                  :is-disabled="busy || aiBusy"
                  @click="aiSuggest"
                />
                <Button
                  v-if="hasSuggestions"
                  :label="t('CRM.KPI_SHEETS.AI_ADOPT_ALL')"
                  size="sm"
                  variant="ghost"
                  color="slate"
                  :is-disabled="busy || aiBusy"
                  @click="adoptAll"
                />
              </div>
            </div>
            <HScrollButtons />
            <div class="overflow-x-auto">
              <table class="w-full min-w-[760px] border-collapse text-label">
                <thead class="bg-n-slate-3 text-n-slate-11">
                  <tr>
                    <th
                      class="w-24 rounded-l-lg px-3 py-2.5 text-left font-medium"
                    >
                      {{ t('CRM.KPI_SCHEMES.ITEMS.DIMENSION') }}
                    </th>
                    <th class="min-w-[220px] px-3 py-2.5 text-left font-medium">
                      {{ t('CRM.KPI_SHEETS.UI.INDICATOR') }}
                    </th>
                    <th class="w-16 px-3 py-2.5 text-right font-medium">
                      {{ t('CRM.KPI_SCHEMES.ITEMS.WEIGHT') }}
                    </th>
                    <th class="w-28 px-3 py-2.5 text-right font-medium">
                      {{ t('CRM.KPI_SHEETS.UI.EMPLOYEE_ACTUAL') }}
                    </th>
                    <th class="w-36 px-3 py-2.5 text-left font-medium">
                      {{ t('CRM.KPI_SHEETS.CHECKED') }}
                    </th>
                    <th
                      class="w-40 rounded-r-lg px-3 py-2.5 text-left font-medium"
                    >
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
                    <td class="px-3 py-4">
                      <span
                        class="inline-block rounded-md bg-n-slate-3 px-2 py-1 text-label-small text-n-slate-11"
                        >{{ item.dimension || '—' }}</span
                      >
                    </td>
                    <td class="px-3 py-4">
                      <p class="mb-2 font-medium text-n-slate-12">
                        {{ item.name }}
                      </p>
                      <details class="text-label-small text-n-slate-11">
                        <summary class="cursor-pointer hover:text-n-slate-12">
                          {{ t('CRM.KPI_SHEETS.UI.VIEW_STANDARD') }}
                        </summary>
                        <p
                          class="mb-2 mt-2 whitespace-pre-wrap leading-relaxed"
                        >
                          {{ item.standard || '—' }}
                        </p>
                        <dl
                          class="m-0 grid grid-cols-[auto_1fr] gap-x-3 gap-y-1"
                        >
                          <dt>{{ t('CRM.KPI_SCHEMES.ITEMS.BASELINE') }}</dt>
                          <dd class="m-0">{{ item.baselineValue || '—' }}</dd>
                          <dt>{{ t('CRM.KPI_SCHEMES.ITEMS.TARGET') }}</dt>
                          <dd class="m-0">{{ item.targetValue || '—' }}</dd>
                        </dl>
                      </details>
                    </td>
                    <td class="px-3 py-4 text-right tabular-nums">
                      {{ item.weight ?? '—' }}
                    </td>
                    <td class="px-3 py-4 text-right tabular-nums">
                      <input
                        v-if="canFillActual"
                        v-model="item.actualValue"
                        :aria-label="`${item.name} · ${t('CRM.KPI_SHEETS.ACTUAL')}`"
                        :class="inCls"
                        :disabled="busy"
                      />
                      <span v-else>{{ item.actualValue || '—' }}</span>
                    </td>
                    <td class="px-3 py-4">
                      <input
                        v-if="canScore"
                        v-model="item.checkedValue"
                        :class="inCls"
                        :aria-label="`${item.name} · ${t('CRM.KPI_SHEETS.CHECKED')}`"
                        :placeholder="item.actualValue || ''"
                        :disabled="busy"
                      />
                      <span v-else>{{
                        item.checkedValue || item.actualValue || '—'
                      }}</span>
                    </td>
                    <td class="px-3 py-4">
                      <template v-if="canScore">
                        <input
                          v-model="item.score"
                          type="number"
                          :class="inCls"
                          :aria-label="`${item.name} · ${t('CRM.KPI_SHEETS.SCORE_COL')}`"
                          :placeholder="
                            t('CRM.KPI_SHEETS.UI.SCORE_PLACEHOLDER')
                          "
                          :disabled="busy"
                        />
                        <button
                          v-if="item.suggestedScore != null"
                          type="button"
                          class="mt-2 inline-flex items-center gap-1 rounded-md bg-n-amber-2 px-2 py-1 text-label-small text-n-slate-12 hover:bg-n-amber-3 disabled:opacity-50"
                          :disabled="busy || aiBusy"
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
                          class="mb-0 mt-1 text-label-small leading-relaxed text-n-slate-11"
                        >
                          {{ item.suggestedReason }}
                        </p>
                      </template>
                      <span v-else class="font-medium">{{
                        item.score ?? '—'
                      }}</span>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <div
              class="mt-4 flex flex-wrap items-center justify-between gap-2 text-label-small text-n-slate-11"
            >
              <span>{{
                hasScores
                  ? t('CRM.KPI_SHEETS.UI.SCORED_COUNT', {
                      count: items.filter(
                        item => item.score != null && item.score !== ''
                      ).length,
                      total: items.length,
                    })
                  : t('CRM.KPI_SHEETS.UI.NOT_SCORED')
              }}</span>
              <span class="text-label text-n-slate-12"
                >{{ t('CRM.KPI_SHEETS.TOTAL') }}
                <strong class="ml-2 tabular-nums">{{
                  t('CRM.KPI_SHEETS.UI.TOTAL_VALUE', {
                    score: hasScores ? totalScore : '—',
                  })
                }}</strong></span
              >
            </div>
          </section>
          <section
            v-if="canScore || remark"
            class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 lg:p-5"
          >
            <h2 class="mb-3 text-heading-2 text-n-slate-12">
              <label for="kpi-remark">{{ t('CRM.KPI_SHEETS.REMARK') }}</label>
            </h2>
            <textarea
              v-if="canScore"
              id="kpi-remark"
              v-model="remark"
              rows="3"
              :placeholder="t('CRM.KPI_SHEETS.REMARK_PLACEHOLDER')"
              class="reset-base w-full resize-y rounded-xl border border-n-weak bg-n-solid-1 p-3 text-label text-n-slate-12 outline-none focus:border-n-slate-10"
              :disabled="busy"
            />
            <p
              v-else
              class="mb-0 whitespace-pre-wrap text-label text-n-slate-11"
            >
              {{ remark }}
            </p>
          </section>
          <section
            v-if="sheet.payoutNote || sheet.resultNote"
            class="rounded-2xl border border-n-weak bg-n-solid-1 px-4 lg:px-5"
          >
            <details v-if="sheet.payoutNote" class="group py-4">
              <summary
                class="flex cursor-pointer list-none items-center justify-between gap-3 text-heading-3 text-n-slate-12"
              >
                <span>{{ t('CRM.KPI_SHEETS.UI.RULES') }}</span
                ><span
                  class="i-lucide-chevron-down size-4 transition-transform group-open:rotate-180"
                />
              </summary>
              <p
                class="mb-0 mt-4 whitespace-pre-wrap text-label leading-relaxed text-n-slate-11"
              >
                {{ sheet.payoutNote }}
              </p>
            </details>
            <details
              v-if="sheet.resultNote"
              class="group border-t border-n-weak py-4 first:border-0"
            >
              <summary
                class="flex cursor-pointer list-none items-center justify-between gap-3 text-heading-3 text-n-slate-12"
              >
                <span>{{ t('CRM.KPI_SHEETS.SECTION_RESULT') }}</span
                ><span
                  class="i-lucide-chevron-down size-4 transition-transform group-open:rotate-180"
                />
              </summary>
              <p
                class="mb-0 mt-4 whitespace-pre-wrap text-label leading-relaxed text-n-slate-11"
              >
                {{ sheet.resultNote }}
              </p>
            </details>
          </section>
          <section
            class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 lg:p-5"
          >
            <h2 class="mb-3 text-heading-2 text-n-slate-12">
              {{ t('CRM.KPI_SHEETS.SIGN') }}
            </h2>
            <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 2xl:grid-cols-4">
              <div
                v-for="signer in signatureRows"
                :key="signer.key"
                class="min-w-0 rounded-xl border border-n-weak p-3"
              >
                <div class="flex items-center justify-between gap-2 text-label">
                  <span class="text-n-slate-12">{{ signer.label }}</span>
                  <span
                    class="rounded px-1.5 py-0.5 text-label-small"
                    :class="
                      signer.url
                        ? 'bg-n-slate-3 text-n-slate-12'
                        : 'bg-n-amber-2 text-n-slate-12'
                    "
                    >{{
                      signer.url
                        ? t('CRM.KPI_SHEETS.UI.SIGNED')
                        : t('CRM.KPI_SHEETS.NOT_SIGNED')
                    }}</span
                  >
                </div>
                <img
                  v-if="signer.url"
                  :src="signer.url"
                  :alt="signer.label"
                  class="mt-2 h-10 w-full rounded object-contain bg-white"
                />
                <p class="mb-0 mt-2 truncate text-label-small text-n-slate-10">
                  {{
                    signer.date
                      ? `${signer.name || ''} · ${fmtDate(signer.date)}`
                      : '—'
                  }}
                </p>
              </div>
            </div>
          </section>
        </div>
        <aside
          class="rounded-2xl border border-n-weak bg-n-solid-1 p-5 xl:sticky xl:top-4"
        >
          <h2 class="mb-1 text-heading-2 text-n-slate-12">
            {{ t('CRM.KPI_SHEETS.UI.REVIEW') }}
          </h2>
          <p class="mb-5 text-label-small text-n-slate-11">
            {{ t('CRM.KPI_SHEETS.UI.CURRENT_STEP') }} ·
            {{ t(`CRM.KPI_SHEETS.STEP.${STEPS[stepIndex]}`) }}
          </p>
          <p class="mb-2 text-heading-1 text-n-slate-12">
            {{ t(`CRM.KPI_SHEETS.STATUS.${status}`) }}
          </p>
          <p class="mb-5 text-label-small text-n-slate-11">
            {{
              hasScores
                ? t('CRM.KPI_SHEETS.UI.SCORED_COUNT', {
                    count: items.filter(
                      item => item.score != null && item.score !== ''
                    ).length,
                    total: items.length,
                  })
                : t('CRM.KPI_SHEETS.UI.NOT_SCORED')
            }}
          </p>
          <div
            v-if="
              canFillActual ||
              canScore ||
              (status === 'SCORED' && isHr) ||
              (status === 'HR_CONFIRMED' && isGm) ||
              canReturn
            "
            class="flex flex-col gap-3 border-t border-n-weak pt-5"
          >
            <Button
              v-if="canFillActual"
              class="!bg-n-slate-12 !text-n-solid-1 hover:enabled:!bg-n-slate-11"
              :label="t('CRM.KPI_SHEETS.SUBMIT')"
              color="slate"
              :is-disabled="busy"
              @click="submitSheet"
            />
            <Button
              v-if="canScore"
              class="!bg-n-slate-12 !text-n-solid-1 hover:enabled:!bg-n-slate-11"
              :label="t('CRM.KPI_SHEETS.SCORE')"
              color="slate"
              :is-disabled="busy"
              @click="scoreSheet"
            />
            <Button
              v-if="status === 'SCORED' && isHr"
              class="!bg-n-slate-12 !text-n-solid-1 hover:enabled:!bg-n-slate-11"
              :label="t('CRM.KPI_SHEETS.HR_CONFIRM')"
              color="slate"
              :is-disabled="busy"
              @click="hrConfirm"
            />
            <Button
              v-if="status === 'HR_CONFIRMED' && isGm"
              class="!bg-n-slate-12 !text-n-solid-1 hover:enabled:!bg-n-slate-11"
              :label="t('CRM.KPI_SHEETS.GM_CONFIRM')"
              color="slate"
              :is-disabled="busy"
              @click="gmConfirm"
            />
            <Button
              v-if="canReturn"
              :label="t('CRM.KPI_SHEETS.RETURN')"
              variant="ghost"
              color="slate"
              :is-disabled="busy"
              @click="returning = true"
            />
          </div>
        </aside>
      </div>
    </div>
    <MySignatureDialog ref="signatureDialogRef" />
    <CrmForwardToTeamChatDialog ref="forwardRef" />
  </div>
</template>
