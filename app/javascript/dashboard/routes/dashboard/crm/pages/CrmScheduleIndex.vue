<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import ScheduleAPI from 'dashboard/api/crm/scheduleEvents';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import { onClickOutside } from '@vueuse/core';

const { accountId } = useAccount();
const store = useStore();
const agents = useMapGetter('agents/getAgents');
const currentUser = useMapGetter('getCurrentUser');

const COLORS = ['blue', 'teal', 'violet', 'rose', 'lime', 'sky'];
// 预声明完整类名，供 Tailwind JIT 扫描（勿动态拼接）。
const DOT = {
  blue: 'bg-[#5b9bef]',
  teal: 'bg-[#3ec3a2]',
  violet: 'bg-[#8b78ee]',
  rose: 'bg-[#ef7f9c]',
  lime: 'bg-[#9fd162]',
  sky: 'bg-[#38bdf8]',
};
const RECUR_LABEL = {
  none: '不重复',
  daily: '每日',
  weekly: '每周',
  monthly: '每月',
};
const recurOptions = Object.entries(RECUR_LABEL).map(([value, label]) => ({
  value,
  label,
}));
// 时间下拉（半小时一档），复用玻璃 SelectCard。
const timeOptions = (() => {
  const out = [];
  for (let h = 0; h < 24; h += 1) {
    ['00', '30'].forEach(mm => {
      const v = `${String(h).padStart(2, '0')}:${mm}`;
      out.push({ value: v, label: v });
    });
  }
  return out;
})();
const WEEK = ['一', '二', '三', '四', '五', '六', '日'];

const pad = n => String(n).padStart(2, '0');
const ymd = d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const todayStr = ymd(new Date());

const view = ref({ y: new Date().getFullYear(), m: new Date().getMonth() });
const selectedDate = ref(todayStr);
const occurrences = ref([]);
const loading = ref(false);

const monthLabel = computed(() => `${view.value.y} 年 ${view.value.m + 1} 月`);

// 拉当月（多取前后各一周边界，避免跨月首尾日漏）。
const fetchEvents = async () => {
  loading.value = true;
  const from = new Date(view.value.y, view.value.m, 1);
  const to = new Date(view.value.y, view.value.m + 1, 0);
  try {
    const { data } = await ScheduleAPI.get(accountId.value, {
      from: ymd(from),
      to: ymd(to),
    });
    occurrences.value = data.payload || [];
  } catch {
    useAlert('日程加载失败');
  } finally {
    loading.value = false;
  }
};

const byDate = computed(() => {
  const map = {};
  occurrences.value.forEach(o => {
    (map[o.occurrence_date] ||= []).push(o);
  });
  return map;
});

const calendar = computed(() => {
  const first = new Date(view.value.y, view.value.m, 1);
  const startDow = (first.getDay() + 6) % 7; // 周一=0
  const start = new Date(view.value.y, view.value.m, 1 - startDow);
  const cells = [];
  for (let i = 0; i < 42; i += 1) {
    const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
    const key = ymd(d);
    cells.push({
      key,
      day: d.getDate(),
      inMonth: d.getMonth() === view.value.m,
      isToday: key === todayStr,
      events: byDate.value[key] || [],
    });
    if (i >= 34 && d.getMonth() !== view.value.m) break;
  }
  return cells;
});

const hhmm = iso => (iso ? iso.slice(11, 16) : '');
const WEEKDAY = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
const mmdd = k => {
  const p = k.split('-');
  return `${+p[1]}/${+p[2]}`;
};
const weekdayOf = k => {
  const [y, m, d] = k.split('-').map(Number);
  return WEEKDAY[new Date(y, m - 1, d).getDay()];
};
// 今日所在周的周一~周日（用于本周分组）。
const weekBounds = (() => {
  const d = new Date();
  const dow = (d.getDay() + 6) % 7;
  const mon = new Date(d.getFullYear(), d.getMonth(), d.getDate() - dow);
  const sun = new Date(mon.getFullYear(), mon.getMonth(), mon.getDate() + 6);
  return { start: ymd(mon), end: ymd(sun) };
})();
// 右侧日程表：把加载到的（当月）事件分成 今日 / 本周(除今日) / 本月(除本周)。
const agendaGroups = computed(() => {
  const sorted = occurrences.value
    .slice()
    .sort((a, b) => (a.starts_at < b.starts_at ? -1 : 1));
  const inWeek = k => k >= weekBounds.start && k <= weekBounds.end;
  return [
    {
      key: 'today',
      title: '今日安排',
      items: sorted.filter(o => o.occurrence_date === todayStr),
      empty: '今天没有安排',
    },
    {
      key: 'week',
      title: '本周安排',
      items: sorted.filter(
        o => inWeek(o.occurrence_date) && o.occurrence_date !== todayStr
      ),
      empty: '本周暂无其它安排',
    },
    {
      key: 'month',
      title: '本月安排',
      items: sorted.filter(o => !inWeek(o.occurrence_date)),
      empty: '本月暂无其它安排',
    },
  ];
});

const shiftMonth = delta => {
  const d = new Date(view.value.y, view.value.m + delta, 1);
  view.value = { y: d.getFullYear(), m: d.getMonth() };
};
const gotoToday = () => {
  view.value = { y: new Date().getFullYear(), m: new Date().getMonth() };
  selectedDate.value = todayStr;
  dayView.value = false;
};

// 点日历某天 → 右侧切到该日视图（空则空态）；「总览/回到今天」回到分组视图。
const dayView = ref(false);
const selectDate = key => {
  selectedDate.value = key;
  dayView.value = true;
};
const backToOverview = () => {
  dayView.value = false;
};
const dayEvents = computed(() =>
  (byDate.value[selectedDate.value] || [])
    .slice()
    .sort((a, b) => (a.starts_at < b.starts_at ? -1 : 1))
);

// 按发生日期打勾/取消完成（乐观更新，失败回滚）。仅创建者可标记。
const toggleDone = async e => {
  if (!e.is_owner) return;
  const prev = e.done;
  e.done = !e.done;
  try {
    await ScheduleAPI.toggleDone(accountId.value, e.id, e.occurrence_date);
  } catch {
    e.done = prev;
    useAlert('标记失败');
  }
};

// ---- 弹窗 ----
const dialog = ref(false);
const saving = ref(false);
const blankForm = () => ({
  id: null,
  isOwner: true,
  title: '',
  date: selectedDate.value,
  allDay: false,
  start: '09:00',
  end: '10:00',
  color: 'blue',
  recurrence: 'none',
  recurrenceUntil: '',
  participantIds: [],
  location: '',
  note: '',
});
const form = ref(blankForm());

const inviteAgents = computed(() =>
  (agents.value || []).filter(a => a.id !== currentUser.value?.id)
);
// 参与人搜索选择器：只显示已选 chip + 搜索下拉，避免成员多时一墙 chip。
const participantQuery = ref('');
const participantOpen = ref(false);
const pickerRef = ref(null);
onClickOutside(pickerRef, () => {
  participantOpen.value = false;
});
const agentName = a => a.available_name || a.name || '';
const selectedParticipants = computed(() =>
  (agents.value || []).filter(a => form.value.participantIds.includes(a.id))
);
const filteredAgents = computed(() => {
  const q = participantQuery.value.trim().toLowerCase();
  return inviteAgents.value
    .filter(a => !form.value.participantIds.includes(a.id))
    .filter(a => !q || agentName(a).toLowerCase().includes(q))
    .slice(0, 30);
});
const addParticipant = id => {
  if (!form.value.participantIds.includes(id)) form.value.participantIds.push(id);
  participantQuery.value = '';
};

const openCreate = date => {
  form.value = { ...blankForm(), date: date || selectedDate.value };
  dialog.value = true;
};
const openEdit = occ => {
  form.value = {
    id: occ.id,
    isOwner: occ.is_owner,
    title: occ.title,
    date: occ.starts_at.slice(0, 10),
    allDay: occ.all_day,
    start: hhmm(occ.starts_at) || '09:00',
    end: hhmm(occ.ends_at) || '10:00',
    color: occ.color,
    recurrence: occ.recurrence,
    recurrenceUntil: occ.recurrence_until || '',
    participantIds: [...(occ.participant_ids || [])],
    location: occ.location || '',
    note: occ.note || '',
  };
  dialog.value = true;
};
const toggleParticipant = id => {
  const arr = form.value.participantIds;
  const i = arr.indexOf(id);
  if (i >= 0) arr.splice(i, 1);
  else arr.push(id);
};

const save = async () => {
  const f = form.value;
  if (!f.title.trim()) {
    useAlert('请填写日程标题');
    return;
  }
  const starts = f.allDay ? `${f.date}T00:00:00` : `${f.date}T${f.start}:00`;
  const ends = f.allDay ? `${f.date}T23:59:00` : `${f.date}T${f.end}:00`;
  const payload = {
    title: f.title.trim(),
    starts_at: starts,
    ends_at: ends,
    all_day: f.allDay,
    color: f.color,
    recurrence: f.recurrence,
    recurrence_until: f.recurrence === 'none' ? null : f.recurrenceUntil || null,
    location: f.location,
    note: f.note,
    participant_ids: f.participantIds,
  };
  saving.value = true;
  try {
    if (f.id) await ScheduleAPI.update(accountId.value, f.id, payload);
    else await ScheduleAPI.create(accountId.value, payload);
    dialog.value = false;
    selectedDate.value = f.date;
    await fetchEvents();
    useAlert(f.id ? '日程已更新' : '日程已创建');
  } catch {
    useAlert('保存失败');
  } finally {
    saving.value = false;
  }
};

const remove = async () => {
  if (!form.value.id) return;
  saving.value = true;
  try {
    await ScheduleAPI.delete(accountId.value, form.value.id);
    dialog.value = false;
    await fetchEvents();
    useAlert('日程已删除');
  } catch {
    useAlert('删除失败');
  } finally {
    saving.value = false;
  }
};

watch(view, fetchEvents, { deep: true });
onMounted(() => {
  store.dispatch('agents/get'); // 拉全体成员，供参与人选择
  fetchEvents();
});
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-hidden bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <!-- 头 -->
    <div
      class="flex flex-wrap items-center justify-between flex-shrink-0 gap-3 px-6 py-4 border-b border-n-weak"
    >
      <h1 class="text-xl font-semibold text-n-slate-12">日程 Schedule</h1>
      <button
        class="flex items-center gap-1.5 px-3.5 py-2 text-sm font-semibold text-white rounded-xl bg-n-iris-9 hover:bg-n-iris-10"
        @click="openCreate()"
      >
        <Icon icon="i-lucide-plus" class="size-4" /> 新建日程
      </button>
    </div>

    <div class="flex-1 overflow-hidden p-5">
      <div class="grid h-full gap-5 lg:grid-cols-[280px_1fr]">
        <!-- 左：小日历 -->
        <div class="flex flex-col gap-3 overflow-auto">
          <div class="p-4 border rounded-2xl border-n-weak bg-n-solid-1/60">
            <div class="flex items-center justify-between mb-3">
              <button
                class="grid rounded-lg size-7 place-items-center text-n-slate-11 hover:bg-n-alpha-2"
                @click="shiftMonth(-1)"
              >
                <Icon icon="i-lucide-chevron-left" class="size-4" />
              </button>
              <span class="text-sm font-semibold text-n-slate-12">
                {{ monthLabel }}
              </span>
              <button
                class="grid rounded-lg size-7 place-items-center text-n-slate-11 hover:bg-n-alpha-2"
                @click="shiftMonth(1)"
              >
                <Icon icon="i-lucide-chevron-right" class="size-4" />
              </button>
            </div>
            <div class="grid grid-cols-7 mb-1">
              <span
                v-for="w in WEEK"
                :key="w"
                class="text-[11px] font-medium text-center text-n-slate-10"
              >{{ w }}</span>
            </div>
            <div class="grid grid-cols-7 gap-0.5">
              <button
                v-for="c in calendar"
                :key="c.key"
                class="relative flex flex-col items-center pt-2 rounded-lg h-[52px] transition-colors"
                :class="[
                  c.inMonth ? 'text-n-slate-12' : 'text-n-slate-8',
                  selectedDate === c.key ? 'bg-n-iris-4' : 'hover:bg-n-alpha-2',
                ]"
                @click="selectDate(c.key)"
                @dblclick="openCreate(c.key)"
              >
                <span
                  class="grid text-[13px] rounded-full size-6 place-items-center"
                  :class="c.isToday ? 'bg-n-iris-9 text-white font-semibold' : ''"
                >{{ c.day }}</span>
                <div class="flex gap-0.5 mt-1">
                  <span
                    v-for="(e, i) in c.events.slice(0, 4)"
                    :key="i"
                    class="rounded-full size-1"
                    :class="DOT[e.color] || DOT.blue"
                  />
                </div>
              </button>
            </div>
          </div>
          <button
            class="py-2 text-xs font-medium border rounded-lg text-n-slate-11 border-n-weak hover:bg-n-alpha-2"
            @click="gotoToday"
          >
            回到今天
          </button>
        </div>

        <!-- 右：日程表 -->
        <div class="flex flex-col gap-5 pr-1 overflow-auto">
          <!-- 单日视图（点了具体日期） -->
          <template v-if="dayView">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-2">
                <h2 class="text-[15px] font-semibold text-n-slate-12">
                  {{ mmdd(selectedDate) }} {{ weekdayOf(selectedDate) }}
                </h2>
                <span class="text-xs text-n-slate-10">{{ dayEvents.length }} 项</span>
              </div>
              <button
                class="flex items-center gap-1 text-xs font-medium text-n-iris-11 hover:underline"
                @click="backToOverview"
              >
                <Icon icon="i-lucide-arrow-left" class="size-3.5" /> 总览
              </button>
            </div>
            <div v-if="dayEvents.length" class="flex flex-col gap-2">
              <button
                v-for="e in dayEvents"
                :key="e.id + e.starts_at"
                class="flex items-start gap-3 p-3 text-left transition-colors border rounded-xl border-n-weak hover:border-n-slate-6 hover:bg-n-alpha-1"
                :class="{ 'opacity-60': e.done }"
                @click="openEdit(e)"
              >
                <span
                  v-if="e.is_owner"
                  class="grid mt-0.5 border rounded-full cursor-pointer size-5 place-items-center shrink-0 transition-colors"
                  :class="
                    e.done
                      ? 'bg-n-teal-9 border-n-teal-9 text-white'
                      : 'border-n-slate-6 text-transparent hover:border-n-teal-8'
                  "
                  @click.stop="toggleDone(e)"
                >
                  <Icon icon="i-lucide-check" class="size-3" />
                </span>
                <span
                  class="self-stretch w-1 rounded-full shrink-0"
                  :class="DOT[e.color] || DOT.blue"
                />
                <div class="flex-1 min-w-0">
                  <div
                    class="text-sm font-medium truncate"
                    :class="e.done ? 'line-through text-n-slate-9' : 'text-n-slate-12'"
                  >
                    {{ e.title }}
                  </div>
                  <div class="mt-0.5 text-xs text-n-slate-10">
                    <template v-if="e.all_day">全天</template>
                    <template v-else>{{ hhmm(e.starts_at) }} – {{ hhmm(e.ends_at) }}</template>
                    <template v-if="e.recurrence !== 'none'"> · {{ RECUR_LABEL[e.recurrence] }}</template>
                  </div>
                  <div
                    v-if="e.participant_names && e.participant_names.length"
                    class="mt-1 text-[11px] text-n-slate-9 truncate"
                  >
                    <Icon icon="i-lucide-users" class="inline size-3 -mt-0.5" />
                    {{ e.owner_name }}、{{ e.participant_names.join('、') }}
                  </div>
                </div>
              </button>
            </div>
            <div
              v-else
              class="flex flex-col items-center justify-center py-16 text-center text-n-slate-10"
            >
              <Icon
                icon="i-lucide-calendar-check-2"
                class="mb-2 size-8 text-n-slate-8"
              />
              <p class="text-sm">这一天没有安排</p>
              <button
                class="mt-3 text-xs font-medium text-n-iris-11 hover:underline"
                @click="openCreate(selectedDate)"
              >
                ＋ 在这天新建
              </button>
            </div>
          </template>

          <!-- 总览：今日 / 本周 / 本月 -->
          <template v-else>
            <section v-for="grp in agendaGroups" :key="grp.key">
              <div class="flex items-center gap-2 mb-2">
                <h2 class="text-[15px] font-semibold text-n-slate-12">
                  {{ grp.title }}
                </h2>
                <span class="text-xs text-n-slate-10">{{ grp.items.length }} 项</span>
              </div>
              <div v-if="grp.items.length" class="flex flex-col gap-2">
                <button
                  v-for="e in grp.items"
                  :key="e.id + e.starts_at"
                  class="flex items-start gap-3 p-3 text-left transition-colors border rounded-xl border-n-weak hover:border-n-slate-6 hover:bg-n-alpha-1"
                  :class="{ 'opacity-60': e.done }"
                  @click="openEdit(e)"
                >
                  <span
                    v-if="e.is_owner"
                    class="grid mt-0.5 border rounded-full cursor-pointer size-5 place-items-center shrink-0 transition-colors"
                    :class="
                      e.done
                        ? 'bg-n-teal-9 border-n-teal-9 text-white'
                        : 'border-n-slate-6 text-transparent hover:border-n-teal-8'
                    "
                    @click.stop="toggleDone(e)"
                  >
                    <Icon icon="i-lucide-check" class="size-3" />
                  </span>
                  <span
                    class="self-stretch w-1 rounded-full shrink-0"
                    :class="DOT[e.color] || DOT.blue"
                  />
                  <div class="w-12 text-center shrink-0">
                    <div class="text-sm font-semibold text-n-slate-12">
                      {{ mmdd(e.occurrence_date) }}
                    </div>
                    <div class="text-[11px] text-n-slate-10">
                      {{ weekdayOf(e.occurrence_date) }}
                    </div>
                  </div>
                  <div class="flex-1 min-w-0">
                    <div
                      class="text-sm font-medium truncate"
                      :class="e.done ? 'line-through text-n-slate-9' : 'text-n-slate-12'"
                    >
                      {{ e.title }}
                    </div>
                    <div class="mt-0.5 text-xs text-n-slate-10">
                      <template v-if="e.all_day">全天</template>
                      <template v-else>{{ hhmm(e.starts_at) }} – {{ hhmm(e.ends_at) }}</template>
                      <template v-if="e.recurrence !== 'none'"> · {{ RECUR_LABEL[e.recurrence] }}</template>
                    </div>
                    <div
                      v-if="e.participant_names && e.participant_names.length"
                      class="mt-1 text-[11px] text-n-slate-9 truncate"
                    >
                      <Icon icon="i-lucide-users" class="inline size-3 -mt-0.5" />
                      {{ e.owner_name }}、{{ e.participant_names.join('、') }}
                    </div>
                  </div>
                </button>
              </div>
              <div v-else class="py-4 text-sm text-n-slate-10">{{ grp.empty }}</div>
            </section>
          </template>
        </div>
      </div>
    </div>

    <!-- 新建/编辑弹窗 -->
    <div
      v-if="dialog"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-black2"
      @click.self="dialog = false"
    >
      <div class="w-full max-w-[460px] max-h-[90vh] overflow-auto p-5 rounded-2xl bg-n-solid-1 shadow-xl border border-n-weak">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-base font-semibold text-n-slate-12">
            {{ form.id ? '编辑日程' : '新建日程' }}
          </h3>
          <button class="grid rounded-lg size-7 place-items-center text-n-slate-10 hover:bg-n-alpha-2" @click="dialog = false">
            <Icon icon="i-lucide-x" class="size-4" />
          </button>
        </div>

        <div class="flex flex-col gap-3.5">
          <input
            v-model="form.title"
            type="text"
            placeholder="日程标题"
            class="w-full px-3 py-2 text-sm border rounded-lg outline-none bg-n-alpha-1 border-n-weak text-n-slate-12 focus:border-n-iris-7"
          />

          <div class="flex items-center gap-3">
            <div class="flex-1">
              <DatePicker v-model="form.date" block :clearable="false" />
            </div>
            <label class="flex items-center gap-1.5 text-sm text-n-slate-11 shrink-0">
              <input v-model="form.allDay" type="checkbox" class="accent-n-iris-9" /> 全天
            </label>
          </div>

          <div v-if="!form.allDay" class="flex items-center gap-2">
            <div class="flex-1">
              <SelectCard v-model="form.start" :options="timeOptions" block />
            </div>
            <span class="text-n-slate-10 shrink-0">–</span>
            <div class="flex-1">
              <SelectCard v-model="form.end" :options="timeOptions" block />
            </div>
          </div>

          <!-- 颜色 -->
          <div class="flex items-center gap-2">
            <span class="text-xs text-n-slate-10 w-12">颜色</span>
            <button
              v-for="c in COLORS"
              :key="c"
              class="rounded-full size-6 transition-transform"
              :class="[DOT[c], form.color === c ? 'ring-2 ring-offset-2 ring-n-slate-8 ring-offset-n-solid-1 scale-110' : '']"
              @click="form.color = c"
            />
          </div>

          <!-- 重复 -->
          <div class="flex items-center gap-2">
            <span class="text-xs text-n-slate-10 w-12 shrink-0">重复</span>
            <div class="flex-1">
              <SelectCard v-model="form.recurrence" :options="recurOptions" block />
            </div>
            <div v-if="form.recurrence !== 'none'" class="flex-1">
              <DatePicker
                v-model="form.recurrenceUntil"
                block
                placeholder="截止(可空)"
              />
            </div>
          </div>

          <!-- 参与人 -->
          <div>
            <div class="mb-1.5 text-xs text-n-slate-10">
              参与人（被邀人在自己日历也能看到）
            </div>
            <!-- 已选 -->
            <div
              v-if="selectedParticipants.length"
              class="flex flex-wrap gap-1.5 mb-2"
            >
              <span
                v-for="a in selectedParticipants"
                :key="a.id"
                class="inline-flex items-center gap-1 py-1 pl-2.5 pr-1.5 text-xs text-white rounded-full bg-n-iris-9"
              >
                {{ agentName(a) }}
                <button
                  type="button"
                  class="grid rounded-full size-4 place-items-center hover:bg-white/20"
                  @click="toggleParticipant(a.id)"
                >
                  <Icon icon="i-lucide-x" class="size-3" />
                </button>
              </span>
            </div>
            <!-- 搜索添加 -->
            <div ref="pickerRef" class="relative">
              <input
                v-model="participantQuery"
                type="text"
                placeholder="搜索成员添加…"
                class="w-full px-3 py-2 text-sm border rounded-lg outline-none bg-n-alpha-1 border-n-weak text-n-slate-12 focus:border-n-iris-7"
                @focus="participantOpen = true"
              />
              <div
                v-if="participantOpen && filteredAgents.length"
                class="absolute z-20 w-full mt-1 overflow-auto border rounded-lg shadow-lg max-h-44 border-n-weak bg-n-solid-1"
              >
                <button
                  v-for="a in filteredAgents"
                  :key="a.id"
                  type="button"
                  class="flex items-center w-full px-3 py-2 text-sm text-left text-n-slate-12 hover:bg-n-alpha-2"
                  @click="addParticipant(a.id)"
                >
                  {{ agentName(a) }}
                </button>
              </div>
              <div
                v-else-if="participantOpen"
                class="absolute z-20 w-full px-3 py-2 mt-1 text-xs border rounded-lg shadow-lg text-n-slate-9 border-n-weak bg-n-solid-1"
              >
                {{ participantQuery ? '无匹配成员' : '没有更多可邀成员' }}
              </div>
            </div>
          </div>

          <input
            v-model="form.location"
            type="text"
            placeholder="地点（可空）"
            class="w-full px-3 py-2 text-sm border rounded-lg outline-none bg-n-alpha-1 border-n-weak text-n-slate-12 focus:border-n-iris-7"
          />
          <textarea
            v-model="form.note"
            rows="2"
            placeholder="备注（可空）"
            class="w-full px-3 py-2 text-sm border rounded-lg outline-none resize-none bg-n-alpha-1 border-n-weak text-n-slate-12 focus:border-n-iris-7"
          />
        </div>

        <div class="flex items-center justify-between mt-5">
          <button
            v-if="form.id && form.isOwner"
            class="px-3 py-2 text-sm font-medium rounded-lg text-n-ruby-11 hover:bg-n-ruby-3"
            :disabled="saving"
            @click="remove"
          >
            删除
          </button>
          <div class="flex gap-2 ml-auto">
            <button
              class="px-4 py-2 text-sm font-medium rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
              @click="dialog = false"
            >
              取消
            </button>
            <button
              class="px-4 py-2 text-sm font-semibold text-white rounded-lg bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-60"
              :disabled="saving"
              @click="save"
            >
              {{ saving ? '保存中…' : '保存' }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
