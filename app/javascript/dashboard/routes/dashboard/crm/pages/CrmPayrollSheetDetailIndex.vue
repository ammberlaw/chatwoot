<script setup>
// 工资表明细：财务/人事在这里核算。
// 只填「原始项」——基本工资、补贴、出勤天数、加班、扣款、社保；
// 出勤工资 / 应发 / 实发由后端按模板公式算，这里只读，改完保存就重算。
// 已确认的表整页只读（后端也挡着）。
import { ref, computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import camelcaseKeys from 'camelcase-keys';
import { useAlert } from 'dashboard/composables';
import PayrollAPI from 'dashboard/api/crm/payrollSheets';
import Button from 'dashboard/components-next/button/Button.vue';
import { fmtYuan } from 'dashboard/helper/crmMoney';
import CrmSensitiveGate from 'dashboard/components-next/CRM/CrmSensitiveGate.vue';

const route = useRoute();
const router = useRouter();
const sheetId = Number(route.query.id);

const sheet = ref(null);
const items = ref([]);
const loading = ref(true);
const busy = ref(false);

const M = 1_000_000;
const toYuan = v => (v == null ? '' : (Number(v) / M).toFixed(2));
const toMicros = v => Math.round((Number(v) || 0) * M);

const isWorkshop = computed(() => sheet.value?.template === 'WORKSHOP');
const editable = computed(() => sheet.value?.editable === true);

// 列定义随模板变：车间有工龄补贴/优秀员工奖，办公室有绩效工资。
// 两边都有的放前面，差异列插在中间，顺序跟财务现在那张表一致。
const COLS = computed(() => {
  const base = [
    { k: 'basicSalaryMicros', label: '基本工资', money: true },
    { k: 'positionAllowanceMicros', label: '职位补贴', money: true },
  ];
  const mid = isWorkshop.value
    ? [
        { k: 'seniorityAllowanceMicros', label: '工龄补贴', money: true },
        { k: 'excellentBonusMicros', label: '优秀员工奖', money: true },
      ]
    : [{ k: 'performanceSalaryMicros', label: '绩效工资', money: true }];
  return [
    ...base,
    ...mid,
    { k: 'mealAllowanceMicros', label: '伙食补贴', money: true },
    { k: 'lodgingAllowanceMicros', label: '外宿补助', money: true },
    { k: 'attendanceBonusMicros', label: '全勤奖', money: true },
    { k: 'commissionSalaryMicros', label: '提成工资', money: true },
    { k: 'weekdayOtHours', label: '平时加班' },
    { k: 'weekdayOtRateMicros', label: '平时时薪', money: true },
    { k: 'weekendOtHours', label: '周末加班' },
    { k: 'weekendOtRateMicros', label: '周末时薪', money: true },
    { k: 'actualDays', label: '实出勤' },
    { k: 'expectedDays', label: '应出勤' },
    { k: 'leaveDays', label: '请假' },
    { k: 'lateDeductionMicros', label: '迟到扣款', money: true },
    { k: 'absenceDeductionMicros', label: '未打卡扣款', money: true },
    { k: 'adjustmentMicros', label: '个别调整', money: true },
    { k: 'socialInsuranceMicros', label: '社保扣款', money: true },
    { k: 'incomeTaxMicros', label: '个税扣款', money: true },
  ];
});

const load = async () => {
  loading.value = true;
  try {
    const { data } = await PayrollAPI.show(sheetId);
    const p = camelcaseKeys(data.payload, { deep: true });
    sheet.value = p;
    items.value = (p.items || []).map(i => ({ ...i, _dirty: false }));
  } catch (e) {
    useAlert(e?.response?.data?.error || '打不开这张工资表');
  } finally {
    loading.value = false;
  }
};

const cellValue = (item, col) =>
  col.money ? toYuan(item[col.k]) : item[col.k];

const onEdit = (item, col, raw) => {
  item[col.k] = col.money ? toMicros(raw) : Number(raw) || 0;
  item._dirty = true;
};

const dirtyCount = computed(() => items.value.filter(i => i._dirty).length);

const save = async () => {
  const changed = items.value.filter(i => i._dirty);
  if (!changed.length) return;
  busy.value = true;
  try {
    const payload = changed.map(i => {
      const row = { id: i.id };
      COLS.value.forEach(c => {
        row[c.k.replace(/([A-Z])/g, (m, s) => `_${s.toLowerCase()}`)] = i[c.k];
      });
      row.adjustment_reason = i.adjustmentReason;
      return row;
    });
    const { data } = await PayrollAPI.update(sheetId, {
      sheet: { items: payload },
    });
    const p = camelcaseKeys(data.payload, { deep: true });
    sheet.value = p;
    items.value = (p.items || []).map(i => ({ ...i, _dirty: false }));
    useAlert('已保存并重算');
  } catch (e) {
    useAlert(e?.response?.data?.error || '保存失败');
  } finally {
    busy.value = false;
  }
};

const confirmSheet = async () => {
  if (dirtyCount.value) return useAlert('还有未保存的改动，先保存再确认');
  if (!window.confirm('确认后这张表就锁定了，要改得先退回核算中。继续？'))
    return undefined;
  busy.value = true;
  try {
    const { data } = await PayrollAPI.confirm(sheetId);
    sheet.value = camelcaseKeys(data.payload, { deep: true });
    useAlert('已确认');
  } catch (e) {
    useAlert(e?.response?.data?.error || '确认失败');
  } finally {
    busy.value = false;
  }
  return undefined;
};

const reopen = async () => {
  busy.value = true;
  try {
    const { data } = await PayrollAPI.reopen(sheetId);
    sheet.value = camelcaseKeys(data.payload, { deep: true });
    useAlert('已退回核算中');
  } catch (e) {
    useAlert(e?.response?.data?.error || '退回失败');
  } finally {
    busy.value = false;
  }
};

const goBack = () => router.push({ name: 'crm_payroll_sheets_index' });

// 解锁前不拉数据：后端每个动作都挂着 ensure_sensitive_session（见 CrmSensitiveGate）。
const onUnlocked = () => load();
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-solid-1">
    <header
      class="flex flex-wrap items-start justify-between gap-3 px-5 py-5 sm:px-8"
    >
      <div class="min-w-0">
        <button
          type="button"
          class="mb-2 inline-flex items-center gap-1.5 text-label-small text-n-slate-11 hover:text-n-slate-12"
          @click="goBack"
        >
          <span class="i-lucide-arrow-left size-3.5 shrink-0" />
          工资表
        </button>
        <div v-if="sheet" class="flex flex-wrap items-center gap-3">
          <h1 class="text-heading-1 text-n-slate-12">{{ sheet.title }}</h1>
          <span
            class="px-2 py-0.5 rounded bg-n-alpha-2 text-label-small text-n-slate-11"
          >
            {{ sheet.templateLabel }}
          </span>
          <span
            class="px-2 py-0.5 rounded text-label-small"
            :class="
              sheet.status === 'CONFIRMED'
                ? 'bg-n-teal-3 text-n-teal-11'
                : 'bg-n-amber-3 text-n-slate-12'
            "
          >
            {{ sheet.statusLabel }}
          </span>
        </div>
        <p v-if="sheet" class="mt-1.5 text-label-small text-n-slate-11">
          {{ sheet.itemCount }} 人 · 应发合计
          {{ fmtYuan(sheet.totalGrossMicros) }} · 实发合计
          {{ fmtYuan(sheet.totalNetMicros) }}
          <span v-if="sheet.confirmedByName">
            · 由 {{ sheet.confirmedByName }} 确认
          </span>
        </p>
      </div>
      <div v-if="sheet" class="flex items-center gap-2">
        <Button
          v-if="editable"
          :label="dirtyCount ? `保存（${dirtyCount} 行已改）` : '保存'"
          color="slate"
          variant="outline"
          :is-disabled="busy || !dirtyCount"
          @click="save"
        />
        <Button
          v-if="editable"
          label="确认封账"
          color="slate"
          class="!bg-n-slate-12 !text-n-solid-1 hover:enabled:!bg-n-slate-11"
          :is-disabled="busy"
          @click="confirmSheet"
        />
        <Button
          v-else
          label="退回核算中"
          variant="outline"
          color="slate"
          :is-disabled="busy"
          @click="reopen"
        />
      </div>
    </header>

    <CrmSensitiveGate subject="工资表" @unlocked="onUnlocked">
      <p v-if="loading" class="py-10 text-sm text-center text-n-slate-10">
        加载中…
      </p>

      <div v-else class="flex-1 px-5 overflow-auto sm:px-8">
        <table class="w-max min-w-full text-sm">
          <thead class="sticky top-0 bg-n-solid-1">
            <tr class="text-left border-b text-n-slate-11 border-n-weak">
              <th class="px-2 py-2 font-medium whitespace-nowrap">姓名</th>
              <th class="px-2 py-2 font-medium whitespace-nowrap">职位</th>
              <th
                v-for="c in COLS"
                :key="c.k"
                class="px-2 py-2 font-medium text-right whitespace-nowrap"
              >
                {{ c.label }}
              </th>
              <th
                class="px-2 py-2 font-medium text-right whitespace-nowrap bg-n-alpha-1"
              >
                出勤工资
              </th>
              <th
                class="px-2 py-2 font-medium text-right whitespace-nowrap bg-n-alpha-1"
              >
                应发
              </th>
              <th
                class="px-2 py-2 font-medium text-right whitespace-nowrap bg-n-alpha-1"
              >
                实发
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="item in items"
              :key="item.id"
              class="border-b border-n-weak hover:bg-n-alpha-1"
            >
              <td
                class="px-2 py-1.5 font-medium whitespace-nowrap text-n-slate-12"
              >
                {{ item.employeeName }}
                <span
                  v-if="!item.hasAccount"
                  class="ml-1 text-label-small text-n-slate-10"
                  title="系统里没有这个人的账号，工资条发不出去"
                >
                  无账号
                </span>
              </td>
              <td class="px-2 py-1.5 whitespace-nowrap text-n-slate-11">
                {{ item.position || '—' }}
              </td>
              <td v-for="c in COLS" :key="c.k" class="px-1 py-1 text-right">
                <input
                  :value="cellValue(item, c)"
                  type="number"
                  step="0.01"
                  :disabled="!editable"
                  class="reset-base mb-0 h-8 w-24 rounded-md border border-transparent bg-transparent px-1.5 text-right text-sm tabular-nums text-n-slate-12 hover:border-n-weak focus:border-n-brand disabled:text-n-slate-11"
                  @change="onEdit(item, c, $event.target.value)"
                />
              </td>
              <td
                class="px-2 py-1.5 text-right tabular-nums text-n-slate-11 bg-n-alpha-1"
              >
                {{ fmtYuan(item.attendancePayMicros) }}
              </td>
              <td
                class="px-2 py-1.5 text-right tabular-nums text-n-slate-12 bg-n-alpha-1"
              >
                {{ fmtYuan(item.grossPayMicros) }}
              </td>
              <td
                class="px-2 py-1.5 font-medium text-right tabular-nums text-n-slate-12 bg-n-alpha-1"
              >
                {{ fmtYuan(item.netPayMicros) }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </CrmSensitiveGate>
  </div>
</template>
