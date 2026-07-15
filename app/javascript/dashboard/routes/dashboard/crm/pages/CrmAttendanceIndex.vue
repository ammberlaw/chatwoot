<script setup>
/* global axios */
import { ref, reactive, computed, onMounted } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const { accountId } = useAccount();
const currentUser = useMapGetter('getCurrentUser');
const api = () => `/api/v1/accounts/${accountId.value}/crm/attendances`;
const settingApi = () =>
  `/api/v1/accounts/${accountId.value}/crm/attendance_setting`;

const isAdminLike = computed(
  () =>
    currentUser.value?.role === 'administrator' ||
    currentUser.value?.crm_role === 'deputy_admin'
);
const isManager = computed(() => currentUser.value?.crm_role === 'manager');
const canSummary = computed(() => isAdminLike.value || isManager.value);

const STATUS_META = {
  NORMAL: { label: '正常', cls: 'bg-n-teal-3 text-n-teal-11' },
  LATE: { label: '迟到', cls: 'bg-n-amber-3 text-n-amber-11' },
  EARLY_LEAVE: { label: '早退', cls: 'bg-n-amber-3 text-n-amber-11' },
  LATE_EARLY: { label: '迟到+早退', cls: 'bg-n-amber-3 text-n-amber-11' },
  ABSENT: { label: '缺卡', cls: 'bg-n-ruby-3 text-n-ruby-11' },
  LEAVE: { label: '请假', cls: 'bg-n-iris-3 text-n-iris-11' },
};
const WEEK_LABELS = ['一', '二', '三', '四', '五', '六', '日'];

// ── 视图与月份 ──
const view = ref('mine');
const pad = n => String(n).padStart(2, '0');
const todayStr = () => {
  const d = new Date();
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
};
const month = ref(todayStr().slice(0, 7));

// ── 我的考勤 ──
const records = ref([]);
const setting = ref(null);
const loadingMine = ref(false);
const fetchMine = async () => {
  loadingMine.value = true;
  try {
    const { data } = await axios.get(api(), {
      params: { month: month.value },
    });
    records.value = data.payload || [];
    setting.value = data.setting;
  } catch {
    records.value = [];
  } finally {
    loadingMine.value = false;
  }
};

const recordByDate = computed(() =>
  Object.fromEntries(records.value.map(r => [r.work_date, r]))
);
const todayRec = computed(() => recordByDate.value[todayStr()] || null);

// 月历：周一开头；过去的工作日无记录 = 缺卡
const calendarCells = computed(() => {
  const [y, m] = month.value.split('-').map(Number);
  const lead = (new Date(y, m - 1, 1).getDay() + 6) % 7;
  const days = new Date(y, m, 0).getDate();
  const cells = Array(lead).fill(null);
  for (let d = 1; d <= days; d += 1) cells.push(d);
  return cells;
});
const dayStatus = d => {
  const dateStr = `${month.value}-${pad(d)}`;
  const rec = recordByDate.value[dateStr];
  if (rec) return rec.status;
  if (!setting.value) return null;
  const dow = new Date(`${dateStr}T12:00:00`).getDay() || 7;
  if (!setting.value.work_days.includes(dow)) return null;
  if ((setting.value.holidays || []).includes(dateStr)) return null;
  return dateStr < todayStr() ? 'ABSENT' : null;
};
const mineCounts = computed(() => {
  const c = {
    present: 0,
    late: 0,
    early: 0,
    absent: 0,
    leave: 0,
  };
  calendarCells.value.forEach(d => {
    if (!d) return;
    const st = dayStatus(d);
    if (!st) return;
    if (st === 'ABSENT') c.absent += 1;
    else if (st === 'LEAVE') c.leave += 1;
    else {
      c.present += 1;
      if (st === 'LATE' || st === 'LATE_EARLY') c.late += 1;
      if (st === 'EARLY_LEAVE' || st === 'LATE_EARLY') c.early += 1;
    }
  });
  return c;
});

// ── 打卡 ──
const clocking = ref(false);
const clock = async () => {
  if (clocking.value) return;
  clocking.value = true;
  try {
    await axios.post(`${api()}/clock`);
    useAlert(todayRec.value?.clock_in_at ? '下班打卡成功' : '上班打卡成功');
    fetchMine();
  } catch {
    useAlert('打卡失败，请重试');
  } finally {
    clocking.value = false;
  }
};

// ── 汇总 ──
const summaryRows = ref([]);
const loadingSummary = ref(false);
const fetchSummary = async () => {
  loadingSummary.value = true;
  try {
    const { data } = await axios.get(`${api()}/summary`, {
      params: { month: month.value },
    });
    summaryRows.value = data.payload || [];
    setting.value = data.setting;
  } catch {
    summaryRows.value = [];
  } finally {
    loadingSummary.value = false;
  }
};

// ── HR 修正 ──
const adjustDialog = ref(null);
const adjustForm = reactive({
  userId: null,
  name: '',
  workDate: '',
  status: 'NORMAL',
  note: '',
});
const adjusting = ref(false);
const openAdjust = row => {
  adjustForm.userId = row.user_id;
  adjustForm.name = row.name;
  adjustForm.workDate = todayStr();
  adjustForm.status = 'NORMAL';
  adjustForm.note = '';
  adjustDialog.value?.open();
};
const saveAdjust = async () => {
  if (adjusting.value || !adjustForm.workDate) return;
  adjusting.value = true;
  try {
    await axios.post(`${api()}/adjust`, {
      user_id: adjustForm.userId,
      work_date: adjustForm.workDate,
      status: adjustForm.status,
      note: adjustForm.note || null,
    });
    adjustDialog.value?.close();
    useAlert('已修正');
    fetchSummary();
  } catch (e) {
    useAlert(e.response?.data?.error || '修正失败');
  } finally {
    adjusting.value = false;
  }
};

// ── 规则设置 ──
const settingForm = reactive({
  workDays: [1, 2, 3, 4, 5],
  clockIn: '09:00',
  clockOut: '18:00',
  grace: 0,
  holidays: [],
});
const newHoliday = ref('');
const addHoliday = () => {
  const d = newHoliday.value;
  if (!d || settingForm.holidays.includes(d)) return;
  settingForm.holidays.push(d);
  settingForm.holidays.sort();
  newHoliday.value = '';
};
const removeHoliday = d => {
  settingForm.holidays = settingForm.holidays.filter(x => x !== d);
};
const savingSetting = ref(false);
const openSettings = async () => {
  view.value = 'settings';
  try {
    const { data } = await axios.get(settingApi());
    settingForm.workDays = data.work_days;
    settingForm.clockIn = data.clock_in_time;
    settingForm.clockOut = data.clock_out_time;
    settingForm.grace = data.grace_minutes;
    settingForm.holidays = data.holidays || [];
  } catch {
    // 保持默认值
  }
};
const toggleWorkDay = d => {
  const i = settingForm.workDays.indexOf(d);
  if (i >= 0) settingForm.workDays.splice(i, 1);
  else settingForm.workDays.push(d);
};
const saveSetting = async () => {
  if (savingSetting.value) return;
  savingSetting.value = true;
  try {
    await axios.put(settingApi(), {
      setting: {
        work_days: settingForm.workDays,
        clock_in_time: settingForm.clockIn,
        clock_out_time: settingForm.clockOut,
        grace_minutes: settingForm.grace,
        holidays: settingForm.holidays,
      },
    });
    useAlert('考勤规则已保存');
    fetchMine();
  } catch (e) {
    useAlert(e.response?.data?.error || '保存失败');
  } finally {
    savingSetting.value = false;
  }
};

const loadView = () => {
  if (view.value === 'summary') fetchSummary();
  else fetchMine();
};
const shiftMonth = delta => {
  const [y, m] = month.value.split('-').map(Number);
  const d = new Date(y, m - 1 + delta, 1);
  month.value = `${d.getFullYear()}-${pad(d.getMonth() + 1)}`;
  loadView();
};
const switchView = v => {
  view.value = v;
  if (v === 'settings') openSettings();
  else loadView();
};

onMounted(fetchMine);
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div
      class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak"
    >
      <h1 class="text-xl font-medium text-n-slate-12">考勤</h1>
      <div class="flex items-center gap-2">
        <button
          class="h-8 px-3 text-sm rounded-lg border"
          :class="
            view === 'mine'
              ? 'border-n-iris-9 bg-n-iris-9/10 text-n-iris-11 font-medium'
              : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-2'
          "
          @click="switchView('mine')"
        >
          我的考勤
        </button>
        <button
          v-if="canSummary"
          class="h-8 px-3 text-sm rounded-lg border"
          :class="
            view === 'summary'
              ? 'border-n-iris-9 bg-n-iris-9/10 text-n-iris-11 font-medium'
              : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-2'
          "
          @click="switchView('summary')"
        >
          考勤汇总
        </button>
        <button
          v-if="isAdminLike"
          class="h-8 px-3 text-sm rounded-lg border"
          :class="
            view === 'settings'
              ? 'border-n-iris-9 bg-n-iris-9/10 text-n-iris-11 font-medium'
              : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-2'
          "
          @click="switchView('settings')"
        >
          规则设置
        </button>
      </div>
    </div>

    <div class="flex flex-col gap-4 px-6 py-5">
      <!-- 打卡卡片（始终显示） -->
      <div
        v-if="view !== 'settings'"
        class="flex flex-wrap items-center gap-4 p-4 border rounded-2xl border-n-weak bg-n-solid-1/60"
      >
        <div class="flex flex-col gap-0.5">
          <span class="text-sm font-medium text-n-slate-12">
            今天 {{ todayStr() }}
          </span>
          <span v-if="setting" class="text-xs text-n-slate-11">
            工作时间 {{ setting.clock_in_time }} –
            {{ setting.clock_out_time }}
            <template v-if="setting.grace_minutes">
              （宽限 {{ setting.grace_minutes }} 分钟）
            </template>
          </span>
        </div>
        <div class="flex items-center gap-4 ml-auto">
          <div class="flex flex-col items-center gap-0.5 text-xs">
            <span class="text-n-slate-10">上班</span>
            <span class="font-medium text-n-slate-12">
              {{ todayRec?.clock_in_at || '—' }}
            </span>
          </div>
          <div class="flex flex-col items-center gap-0.5 text-xs">
            <span class="text-n-slate-10">下班</span>
            <span class="font-medium text-n-slate-12">
              {{ todayRec?.clock_out_at || '—' }}
            </span>
          </div>
          <span
            v-if="todayRec"
            class="px-2 py-0.5 text-xs rounded-full"
            :class="STATUS_META[todayRec.status]?.cls"
          >
            {{ STATUS_META[todayRec.status]?.label }}
          </span>
          <button
            class="h-10 px-6 text-sm font-medium text-white rounded-xl shrink-0 whitespace-nowrap bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-50"
            :disabled="clocking"
            @click="clock"
          >
            {{ todayRec?.clock_in_at ? '下班打卡' : '上班打卡' }}
          </button>
        </div>
      </div>

      <!-- 月份切换（我的/汇总） -->
      <div v-if="view !== 'settings'" class="flex items-center gap-2">
        <button
          class="h-8 px-2 text-sm rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-2"
          @click="shiftMonth(-1)"
        >
          ‹
        </button>
        <span class="text-sm font-medium text-n-slate-12">{{ month }}</span>
        <button
          class="h-8 px-2 text-sm rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-2"
          @click="shiftMonth(1)"
        >
          ›
        </button>
      </div>

      <!-- ── 我的考勤：月历 ── -->
      <template v-if="view === 'mine'">
        <div class="grid grid-cols-7 gap-1.5 max-w-2xl">
          <div
            v-for="w in WEEK_LABELS"
            :key="w"
            class="py-1 text-xs text-center text-n-slate-10"
          >
            {{ w }}
          </div>
          <template v-for="(d, i) in calendarCells" :key="i">
            <div v-if="!d" />
            <div
              v-else
              class="flex flex-col items-center gap-0.5 py-1.5 border rounded-lg border-n-weak/60"
              :class="
                `${month}-${pad(d)}` === todayStr()
                  ? 'ring-1 ring-n-iris-9'
                  : ''
              "
            >
              <span class="text-xs text-n-slate-12">{{ d }}</span>
              <span
                v-if="dayStatus(d)"
                class="px-1.5 py-0.5 text-[10px] rounded-full"
                :class="STATUS_META[dayStatus(d)]?.cls"
              >
                {{ STATUS_META[dayStatus(d)]?.label }}
              </span>
              <span v-else class="text-[10px] text-n-slate-8">·</span>
            </div>
          </template>
        </div>
        <div class="flex flex-wrap gap-4 text-xs text-n-slate-11">
          <span>出勤 {{ mineCounts.present }} 天</span>
          <span>迟到 {{ mineCounts.late }} 次</span>
          <span>早退 {{ mineCounts.early }} 次</span>
          <span>缺卡 {{ mineCounts.absent }} 天</span>
          <span>请假 {{ mineCounts.leave }} 天</span>
        </div>
      </template>

      <!-- ── 考勤汇总 ── -->
      <template v-else-if="view === 'summary'">
        <div class="overflow-x-auto border rounded-xl border-n-weak">
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left border-b text-n-slate-11 border-n-weak">
                <th class="px-3 py-2 font-medium">成员</th>
                <th class="px-3 py-2 font-medium">出勤</th>
                <th class="px-3 py-2 font-medium">迟到</th>
                <th class="px-3 py-2 font-medium">早退</th>
                <th class="px-3 py-2 font-medium">缺卡</th>
                <th class="px-3 py-2 font-medium">请假</th>
                <th v-if="isAdminLike" class="px-3 py-2 font-medium text-right">
                  操作
                </th>
              </tr>
            </thead>
            <tbody>
              <tr v-if="loadingSummary">
                <td colspan="7" class="px-3 py-6 text-center text-n-slate-11">
                  加载中…
                </td>
              </tr>
              <template v-else>
                <tr
                  v-for="row in summaryRows"
                  :key="row.user_id"
                  class="border-b border-n-weak/60 text-n-slate-12"
                >
                  <td class="px-3 py-2">{{ row.name }}</td>
                  <td class="px-3 py-2">{{ row.present }}</td>
                  <td
                    class="px-3 py-2"
                    :class="row.late ? 'text-n-amber-11' : ''"
                  >
                    {{ row.late }}
                  </td>
                  <td
                    class="px-3 py-2"
                    :class="row.early_leave ? 'text-n-amber-11' : ''"
                  >
                    {{ row.early_leave }}
                  </td>
                  <td
                    class="px-3 py-2"
                    :class="row.absent ? 'text-n-ruby-11' : ''"
                  >
                    {{ row.absent }}
                  </td>
                  <td class="px-3 py-2">{{ row.leave }}</td>
                  <td v-if="isAdminLike" class="px-3 py-2 text-right">
                    <button
                      class="text-xs text-n-iris-11 hover:underline"
                      @click="openAdjust(row)"
                    >
                      修正
                    </button>
                  </td>
                </tr>
              </template>
            </tbody>
          </table>
        </div>
        <p class="text-xs text-n-slate-10">
          口径：只统计工作日且不含未来日期；缺卡=当天没有任何打卡记录；修正会留审计痕迹。
        </p>
      </template>

      <!-- ── 规则设置 ── -->
      <template v-else>
        <div class="flex flex-col max-w-md gap-4">
          <div class="flex flex-col gap-1.5">
            <span class="text-xs text-n-slate-11">工作日</span>
            <div class="flex gap-2">
              <button
                v-for="(w, i) in WEEK_LABELS"
                :key="w"
                class="w-9 h-9 text-sm rounded-lg border"
                :class="
                  settingForm.workDays.includes(i + 1)
                    ? 'border-n-iris-9 bg-n-iris-9/10 text-n-iris-11 font-medium'
                    : 'border-n-weak text-n-slate-11'
                "
                @click="toggleWorkDay(i + 1)"
              >
                {{ w }}
              </button>
            </div>
          </div>
          <div class="grid grid-cols-2 gap-4">
            <label class="flex flex-col gap-1">
              <span class="text-xs text-n-slate-11">上班时间</span>
              <input
                v-model="settingForm.clockIn"
                type="time"
                class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
              />
            </label>
            <label class="flex flex-col gap-1">
              <span class="text-xs text-n-slate-11">下班时间</span>
              <input
                v-model="settingForm.clockOut"
                type="time"
                class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
              />
            </label>
          </div>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">迟到/早退宽限（分钟）</span>
            <input
              v-model.number="settingForm.grace"
              type="number"
              min="0"
              class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <div class="flex flex-col gap-1.5">
            <span class="text-xs text-n-slate-11">
              节假日（不计工作日，如法定假期）
            </span>
            <div class="flex items-center gap-2">
              <input
                v-model="newHoliday"
                type="date"
                class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
              />
              <button
                class="h-9 px-3 text-sm rounded-lg border border-n-weak text-n-slate-12 hover:bg-n-alpha-2"
                @click="addHoliday"
              >
                添加
              </button>
            </div>
            <div
              v-if="settingForm.holidays.length"
              class="flex flex-wrap gap-1.5"
            >
              <span
                v-for="d in settingForm.holidays"
                :key="d"
                class="inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded-full bg-n-iris-3 text-n-iris-11"
              >
                {{ d }}
                <button class="hover:text-n-ruby-11" @click="removeHoliday(d)">
                  ×
                </button>
              </span>
            </div>
          </div>
          <div>
            <button
              class="h-9 px-5 text-sm font-medium text-white rounded-lg bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-50"
              :disabled="savingSetting || !settingForm.workDays.length"
              @click="saveSetting"
            >
              {{ savingSetting ? '保存中…' : '保存规则' }}
            </button>
          </div>
        </div>
      </template>
    </div>

    <!-- HR 修正弹窗 -->
    <Dialog
      ref="adjustDialog"
      :title="`修正考勤 · ${adjustForm.name}`"
      :show-confirm-button="false"
    >
      <div class="flex flex-col gap-4">
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">日期</span>
          <input
            v-model="adjustForm.workDate"
            type="date"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">状态</span>
          <select
            v-model="adjustForm.status"
            class="h-9 px-2 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          >
            <option v-for="(meta, k) in STATUS_META" :key="k" :value="k">
              {{ meta.label }}
            </option>
          </select>
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">备注</span>
          <input
            v-model="adjustForm.note"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="如：出差外勤 / 忘打卡补正常"
          />
        </label>
        <div class="flex justify-end">
          <button
            type="button"
            class="h-9 px-4 text-sm font-medium text-white rounded-lg bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-50"
            :disabled="adjusting"
            @click="saveAdjust"
          >
            {{ adjusting ? '保存中…' : '保存修正' }}
          </button>
        </div>
      </div>
    </Dialog>
  </div>
</template>
