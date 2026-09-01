<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import ScheduleAPI from 'dashboard/api/crm/scheduleEvents';
import CrmCustomerAPI from 'dashboard/api/crm/customers';
import OpportunityAPI from 'dashboard/api/crm/opportunities';
import SalesOrderAPI from 'dashboard/api/crm/salesOrders';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import { onClickOutside } from '@vueuse/core';
import { holidaysFor } from 'dashboard/routes/dashboard/crm/constants/holidays';

const { accountId } = useAccount();
const router = useRouter();
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
const ymd = d =>
  `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const todayStr = ymd(new Date());

const view = ref({ y: new Date().getFullYear(), m: new Date().getMonth() });
const selectedDate = ref(todayStr);
const occurrences = ref([]);
const loading = ref(false);
// 视图模式：月历总览 / 周视图看板。
const mode = ref('month');
// 周视图锚点（该周内任意一天）。
const weekAnchor = ref(new Date());

const monthLabel = computed(() => `${view.value.y} 年 ${view.value.m + 1} 月`);

// 周一为一周起点：返回锚点所在周的周一。
const mondayOf = d => {
  const dow = (d.getDay() + 6) % 7;
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() - dow);
};

// 按当前模式拉取事件窗口：月模式取整月，周模式取该周（周一~周日）。
const fetchEvents = async () => {
  loading.value = true;
  let from;
  let to;
  if (mode.value === 'week') {
    from = mondayOf(weekAnchor.value);
    to = new Date(from.getFullYear(), from.getMonth(), from.getDate() + 6);
  } else {
    from = new Date(view.value.y, view.value.m, 1);
    to = new Date(view.value.y, view.value.m + 1, 0);
  }
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
    const d = new Date(
      start.getFullYear(),
      start.getMonth(),
      start.getDate() + i
    );
    const key = ymd(d);
    cells.push({
      key,
      day: d.getDate(),
      inMonth: d.getMonth() === view.value.m,
      isToday: key === todayStr,
      events: byDate.value[key] || [],
      holidays: holidaysFor(key),
    });
    if (i >= 34 && d.getMonth() !== view.value.m) break;
  }
  return cells;
});

const hhmm = iso => (iso ? iso.slice(11, 16) : '');
// 逾期未完成：发生日早于今天且未打勾。
const isOverdue = e => e.occurrence_date < todayStr && !e.done;
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

// 周视图：锚点所在周的 7 天（周一起），每天含当天事件（按时间排序）。
const weekColumns = computed(() => {
  const mon = mondayOf(weekAnchor.value);
  return Array.from({ length: 7 }, (_, i) => {
    const d = new Date(mon.getFullYear(), mon.getMonth(), mon.getDate() + i);
    const key = ymd(d);
    return {
      key,
      dayNum: d.getDate(),
      weekday: WEEKDAY[d.getDay()],
      isToday: key === todayStr,
      events: (byDate.value[key] || [])
        .slice()
        .sort((a, b) => (a.starts_at < b.starts_at ? -1 : 1)),
    };
  });
});
const weekLabel = computed(() => {
  const cols = weekColumns.value;
  return `${mmdd(cols[0].key)} – ${mmdd(cols[6].key)}`;
});
const shiftWeek = delta => {
  const d = weekAnchor.value;
  weekAnchor.value = new Date(
    d.getFullYear(),
    d.getMonth(),
    d.getDate() + delta * 7
  );
};
const setMode = m => {
  mode.value = m;
  if (m === 'week') weekAnchor.value = new Date();
};

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
// 选中日的节日（只读，供业务给该市场客户发问候参考）。
const selectedHolidays = computed(() => holidaysFor(selectedDate.value));
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

// 勾选处理：客户跟进提醒 → 打开「完成跟进」写记录；普通日程 → 直接打勾。
const handleCheck = e => {
  if (!e.is_owner) return;
  if (e.kind === 'follow_up' && e.customer_id) {
    openComplete(e);
    return;
  }
  toggleDone(e);
};

// ---- 完成跟进弹窗 ----
const METHOD_OPTS = [
  { value: '', label: '未选择方式' },
  { value: 'EMAIL', label: '邮件' },
  { value: 'PHONE', label: '电话' },
  { value: 'MEETING', label: '会议' },
  { value: 'WHATSAPP', label: 'WhatsApp' },
  { value: 'WECHAT', label: '微信' },
];
const RESULT_OPTS = [
  { value: '', label: '未选择结果' },
  { value: 'INTERESTED', label: '有意向' },
  { value: 'WAITING_CUSTOMER', label: '等客户回复' },
  { value: 'WAITING_INTERNAL', label: '等内部处理' },
  { value: 'INVALID', label: '无效' },
];
const completeDialog = ref(false);
const completeSaving = ref(false);
const completeForm = ref({});
const openComplete = e => {
  completeForm.value = {
    eventId: e.id,
    customerId: e.customer_id,
    customerName: e.customer_name || '',
    body: '',
    method: '',
    resultTag: '',
    nextDate: '',
  };
  completeDialog.value = true;
};
const submitComplete = async () => {
  const f = completeForm.value;
  if (!f.body.trim()) {
    useAlert('请填写本次跟进内容');
    return;
  }
  completeSaving.value = true;
  try {
    await ScheduleAPI.completeFollowUp(accountId.value, f.eventId, {
      body: f.body.trim(),
      follow_up_method: f.method,
      result_tag: f.resultTag,
      next_follow_up_at: f.nextDate ? `${f.nextDate}T09:00:00` : null,
    });
    completeDialog.value = false;
    await fetchEvents();
    useAlert(f.nextDate ? '跟进已记录，提醒已顺延' : '跟进已记录，提醒已完成');
  } catch {
    useAlert('保存失败');
  } finally {
    completeSaving.value = false;
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
  refType: '',
  refId: null,
  refName: '',
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
  if (!form.value.participantIds.includes(id))
    form.value.participantIds.push(id);
  participantQuery.value = '';
};

const openCreate = date => {
  form.value = { ...blankForm(), date: date || selectedDate.value };
  refQuery.value = '';
  refOpen.value = false;
  refList.value = [];
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
    customerId: occ.customer_id || null,
    customerName: occ.customer_name || '',
    refType: occ.ref_type || '',
    refId: occ.ref_id || null,
    refName: occ.ref_name || '',
  };
  refQuery.value = '';
  refOpen.value = false;
  dialog.value = true;
};
const gotoCustomer = () => {
  if (!form.value.customerId) return;
  dialog.value = false;
  router.push({
    name: 'crm_customer_detail_index',
    params: { accountId: accountId.value, id: form.value.customerId },
  });
};

// ---- 关联对象（客户/商机/订单）选择器 ----
const REF_TYPE_OPTS = [
  { value: '', label: '不关联' },
  { value: 'customer', label: '客户' },
  { value: 'opportunity', label: '商机' },
  { value: 'order', label: '订单' },
];
const REF_ROUTE = {
  customer: 'crm_customer_detail_index',
  opportunity: 'crm_opportunities_index',
  order: 'crm_sales_orders_index',
};
const refQuery = ref('');
const refOpen = ref(false);
const refLoading = ref(false);
const refList = ref([]); // 当前类型的候选（拉一页，前端过滤）
const refPickerRef = ref(null);
onClickOutside(refPickerRef, () => {
  refOpen.value = false;
});
const refApi = t =>
  ({
    customer: CrmCustomerAPI,
    opportunity: OpportunityAPI,
    order: SalesOrderAPI,
  })[t];
const refItemName = (t, r) =>
  t === 'order' ? r.name || r.order_no || `#${r.id}` : r.name || `#${r.id}`;
// 切换关联类型：清掉已选并拉该类型候选列表。
const onRefTypeChange = async t => {
  form.value.refType = t;
  form.value.refId = null;
  form.value.refName = '';
  refQuery.value = '';
  refList.value = [];
  if (!t) return;
  refLoading.value = true;
  try {
    const res = await refApi(t).get({ per_page: 100 });
    refList.value = res.data.payload || [];
  } catch {
    refList.value = [];
  } finally {
    refLoading.value = false;
  }
};
const filteredRefs = computed(() => {
  const q = refQuery.value.trim().toLowerCase();
  return refList.value
    .filter(
      r => !q || refItemName(form.value.refType, r).toLowerCase().includes(q)
    )
    .slice(0, 30);
});
const pickRef = r => {
  form.value.refId = r.id;
  form.value.refName = refItemName(form.value.refType, r);
  refOpen.value = false;
  refQuery.value = '';
};
const clearRef = () => {
  form.value.refId = null;
  form.value.refName = '';
};
// 跳到关联对象：客户→详情页，商机/订单→列表页并 focus 该记录。
const gotoRef = () => {
  if (!form.value.refType || !form.value.refId) return;
  dialog.value = false;
  const name = REF_ROUTE[form.value.refType];
  if (form.value.refType === 'customer') {
    router.push({
      name,
      params: { accountId: accountId.value, id: form.value.refId },
    });
  } else {
    router.push({
      name,
      params: { accountId: accountId.value },
      query: { focus: String(form.value.refId) },
    });
  }
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
    recurrence_until:
      f.recurrence === 'none' ? null : f.recurrenceUntil || null,
    location: f.location,
    note: f.note,
    participant_ids: f.participantIds,
    ref_type: f.refType || null,
    ref_id: f.refType ? f.refId : null,
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

// ---- 拖拽改期（仅不重复、本人的事件；保持原时段，仅换日期）----
const draggedOcc = ref(null);
const canDrag = e => e.is_owner && e.recurrence === 'none';
const onDragStart = (e, evt) => {
  if (!canDrag(e)) {
    evt.preventDefault();
    return;
  }
  draggedOcc.value = e;
  evt.dataTransfer.effectAllowed = 'move';
};
const onDragEnd = () => {
  draggedOcc.value = null;
};
const reschedule = async (occ, dateKey) => {
  if (!occ || occ.occurrence_date === dateKey) return;
  const startTime = hhmm(occ.starts_at) || '09:00';
  const endTime = hhmm(occ.ends_at) || startTime;
  const payload = {
    starts_at: occ.all_day
      ? `${dateKey}T00:00:00`
      : `${dateKey}T${startTime}:00`,
    ends_at: occ.all_day ? `${dateKey}T23:59:00` : `${dateKey}T${endTime}:00`,
  };
  try {
    await ScheduleAPI.update(accountId.value, occ.id, payload);
    await fetchEvents();
    useAlert(`已改到 ${mmdd(dateKey)}`);
  } catch {
    useAlert('改期失败');
  }
};
const onDropDay = dateKey => {
  const occ = draggedOcc.value;
  draggedOcc.value = null;
  reschedule(occ, dateKey);
};

watch([view, mode, weekAnchor], fetchEvents, { deep: true });
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
      class="flex flex-wrap items-center justify-between flex-shrink-0 gap-3 px-4 py-3 border-b border-n-weak sm:px-6 sm:py-4"
    >
      <h1 class="text-xl font-semibold text-n-slate-12">日程 Schedule</h1>
      <div class="flex items-center gap-3">
        <!-- 月/周 视图切换 -->
        <div class="flex p-0.5 rounded-xl bg-n-alpha-2">
          <button
            v-for="m in [
              { v: 'month', t: '月' },
              { v: 'week', t: '周' },
            ]"
            :key="m.v"
            class="px-3.5 py-1.5 text-sm font-semibold rounded-lg transition-colors"
            :class="
              mode === m.v
                ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                : 'text-n-slate-10 hover:text-n-slate-12'
            "
            @click="setMode(m.v)"
          >
            {{ m.t }}
          </button>
        </div>
        <button
          class="flex items-center gap-1.5 px-3.5 py-2 text-sm font-semibold text-white rounded-xl bg-n-iris-9 hover:bg-n-iris-10"
          @click="openCreate()"
        >
          <Icon icon="i-lucide-plus" class="size-4" /> 新建日程
        </button>
      </div>
    </div>

    <div class="flex-1 overflow-hidden p-3 sm:p-5">
      <div
        v-if="mode === 'month'"
        class="grid h-full gap-5 lg:grid-cols-[280px_1fr]"
      >
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
                  draggedOcc ? 'ring-1 ring-inset ring-n-iris-6/40' : '',
                ]"
                :title="
                  c.holidays.length
                    ? c.holidays.map(h => `${h.region} · ${h.name}`).join('、')
                    : null
                "
                @click="selectDate(c.key)"
                @dblclick="openCreate(c.key)"
                @dragover.prevent
                @drop.prevent="onDropDay(c.key)"
              >
                <span
                  class="grid text-[13px] rounded-full size-6 place-items-center"
                  :class="
                    c.isToday ? 'bg-n-iris-9 text-white font-semibold' : ''
                  "
                  >{{ c.day }}</span>
                <span
                  v-if="c.holidays.length"
                  class="absolute top-0.5 right-1 text-[10px] leading-none"
                  >{{ c.holidays[0].emoji }}</span>
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
            <div v-if="selectedHolidays.length" class="flex flex-wrap gap-1.5">
              <span
                v-for="(h, i) in selectedHolidays"
                :key="i"
                class="inline-flex items-center gap-1 px-2 py-1 text-xs rounded-lg bg-n-amber-3 text-n-amber-11"
              >
                {{ h.emoji }} {{ h.name }} · {{ h.region }}
              </span>
            </div>
            <div v-if="dayEvents.length" class="flex flex-col gap-2">
              <button
                v-for="e in dayEvents"
                :key="e.id + e.starts_at"
                class="flex items-start gap-3 p-3 text-left transition-colors border rounded-xl border-n-weak hover:border-n-slate-6 hover:bg-n-alpha-1"
                :class="{ 'opacity-60': e.done, 'cursor-grab': canDrag(e) }"
                :draggable="canDrag(e)"
                @click="openEdit(e)"
                @dragstart="onDragStart(e, $event)"
                @dragend="onDragEnd"
              >
                <span
                  v-if="e.is_owner"
                  class="grid mt-0.5 border rounded-full cursor-pointer size-5 place-items-center shrink-0 transition-colors"
                  :class="
                    e.done
                      ? 'bg-n-teal-9 border-n-teal-9 text-white'
                      : 'border-n-slate-6 text-transparent hover:border-n-teal-8'
                  "
                  @click.stop="handleCheck(e)"
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
                    :class="
                      e.done ? 'line-through text-n-slate-9' : 'text-n-slate-12'
                    "
                  >
                    {{ e.title }}
                  </div>
                  <div class="mt-0.5 text-xs text-n-slate-10">
                    <template v-if="e.all_day">全天</template>
                    <template v-else>
                      {{ hhmm(e.starts_at) }} – {{ hhmm(e.ends_at) }}
                    </template>
                    <template v-if="e.recurrence !== 'none'">
                      · {{ RECUR_LABEL[e.recurrence] }}
                    </template>
                    <span
                      v-if="isOverdue(e)"
                      class="ml-1.5 px-1.5 py-0.5 rounded text-[10px] font-semibold text-n-ruby-11 bg-n-ruby-3"
                      >逾期</span>
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
                  :class="{ 'opacity-60': e.done, 'cursor-grab': canDrag(e) }"
                  :draggable="canDrag(e)"
                  @click="openEdit(e)"
                  @dragstart="onDragStart(e, $event)"
                  @dragend="onDragEnd"
                >
                  <span
                    v-if="e.is_owner"
                    class="grid mt-0.5 border rounded-full cursor-pointer size-5 place-items-center shrink-0 transition-colors"
                    :class="
                      e.done
                        ? 'bg-n-teal-9 border-n-teal-9 text-white'
                        : 'border-n-slate-6 text-transparent hover:border-n-teal-8'
                    "
                    @click.stop="handleCheck(e)"
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
                      :class="
                        e.done
                          ? 'line-through text-n-slate-9'
                          : 'text-n-slate-12'
                      "
                    >
                      {{ e.title }}
                    </div>
                    <div class="mt-0.5 text-xs text-n-slate-10">
                      <template v-if="e.all_day">全天</template>
                      <template v-else>
                        {{ hhmm(e.starts_at) }} –
                        {{ hhmm(e.ends_at) }}
                      </template>
                      <template v-if="e.recurrence !== 'none'">
                        · {{ RECUR_LABEL[e.recurrence] }}
                      </template>
                    </div>
                    <div
                      v-if="e.participant_names && e.participant_names.length"
                      class="mt-1 text-[11px] text-n-slate-9 truncate"
                    >
                      <Icon
                        icon="i-lucide-users"
                        class="inline size-3 -mt-0.5"
                      />
                      {{ e.owner_name }}、{{ e.participant_names.join('、') }}
                    </div>
                  </div>
                </button>
              </div>
              <div v-else class="py-4 text-sm text-n-slate-10">
                {{ grp.empty }}
              </div>
            </section>
          </template>
        </div>
      </div>

      <!-- 周视图看板：7 列，可拖卡片跨天改期 -->
      <div v-else class="flex flex-col h-full gap-3">
        <div class="flex items-center justify-between flex-shrink-0">
          <div class="flex items-center gap-2">
            <button
              class="grid rounded-lg size-7 place-items-center text-n-slate-11 hover:bg-n-alpha-2"
              @click="shiftWeek(-1)"
            >
              <Icon icon="i-lucide-chevron-left" class="size-4" />
            </button>
            <span class="text-sm font-semibold text-n-slate-12">
              {{ weekLabel }}
            </span>
            <button
              class="grid rounded-lg size-7 place-items-center text-n-slate-11 hover:bg-n-alpha-2"
              @click="shiftWeek(1)"
            >
              <Icon icon="i-lucide-chevron-right" class="size-4" />
            </button>
          </div>
          <button
            class="px-3 py-1.5 text-xs font-medium border rounded-lg text-n-slate-11 border-n-weak hover:bg-n-alpha-2"
            @click="weekAnchor = new Date()"
          >
            回到本周
          </button>
        </div>
        <div
          class="flex flex-1 gap-2 overflow-x-auto md:grid md:grid-cols-7 md:overflow-hidden"
        >
          <div
            v-for="col in weekColumns"
            :key="col.key"
            class="flex flex-col min-h-0 border rounded-xl shrink-0 basis-[46%] sm:basis-[32%] md:basis-auto md:shrink border-n-weak bg-n-solid-1/50"
            :class="draggedOcc ? 'ring-1 ring-inset ring-n-iris-6/40' : ''"
            @dragover.prevent
            @drop.prevent="onDropDay(col.key)"
          >
            <div
              class="flex items-center justify-between px-2.5 py-2 border-b border-n-weak"
            >
              <span
                class="text-xs font-semibold"
                :class="col.isToday ? 'text-n-iris-11' : 'text-n-slate-11'"
                >{{ col.weekday }}</span
              >
              <span
                class="grid text-xs rounded-full size-6 place-items-center"
                :class="
                  col.isToday
                    ? 'bg-n-iris-9 text-white font-semibold'
                    : 'text-n-slate-10'
                "
                >{{ col.dayNum }}</span
              >
            </div>
            <div class="flex flex-col flex-1 gap-1.5 p-1.5 overflow-auto">
              <button
                v-for="e in col.events"
                :key="e.id + e.starts_at"
                class="flex flex-col gap-0.5 p-2 text-left border rounded-lg border-n-weak hover:border-n-slate-6 hover:bg-n-alpha-1"
                :class="{ 'opacity-60': e.done, 'cursor-grab': canDrag(e) }"
                :draggable="canDrag(e)"
                @click="openEdit(e)"
                @dragstart="onDragStart(e, $event)"
                @dragend="onDragEnd"
              >
                <div class="flex items-center gap-1">
                  <span
                    class="rounded-full size-1.5 shrink-0"
                    :class="DOT[e.color] || DOT.blue"
                  />
                  <span class="text-[11px] text-n-slate-10">
                    {{ e.all_day ? '全天' : hhmm(e.starts_at) }}
                  </span>
                  <span
                    v-if="isOverdue(e)"
                    class="ml-auto px-1 rounded text-[9px] font-semibold text-n-ruby-11 bg-n-ruby-3"
                    >逾期</span
                  >
                </div>
                <div
                  class="text-xs font-medium truncate"
                  :class="
                    e.done ? 'line-through text-n-slate-9' : 'text-n-slate-12'
                  "
                >
                  {{ e.title }}
                </div>
              </button>
              <button
                v-if="!col.events.length"
                type="button"
                class="grid flex-1 min-h-[44px] place-items-center text-sm text-n-slate-8 rounded-lg hover:bg-n-alpha-1 hover:text-n-iris-11"
                @click="openCreate(col.key)"
              >
                ＋
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- 新建/编辑弹窗 -->
    <div
      v-if="dialog"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-black2"
      @click.self="dialog = false"
    >
      <div
        class="w-full max-w-[460px] max-h-[90vh] overflow-auto p-5 rounded-2xl bg-n-solid-1 shadow-xl border border-n-weak"
      >
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-base font-semibold text-n-slate-12">
            {{ form.id ? '编辑日程' : '新建日程' }}
          </h3>
          <button
            class="grid rounded-lg size-7 place-items-center text-n-slate-10 hover:bg-n-alpha-2"
            @click="dialog = false"
          >
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

          <button
            v-if="form.customerId"
            type="button"
            class="flex items-center justify-between w-full px-3 py-2 text-sm border rounded-lg bg-n-iris-2 border-n-iris-6 text-n-iris-11 hover:bg-n-iris-3"
            @click="gotoCustomer"
          >
            <span class="flex items-center gap-1.5 truncate">
              <Icon icon="i-lucide-building-2" class="size-4 shrink-0" />
              <span class="truncate">关联客户：{{ form.customerName || '查看客户' }}</span>
            </span>
            <Icon icon="i-lucide-arrow-right" class="size-4 shrink-0" />
          </button>

          <!-- 关联对象（客户/商机/订单）：跟进提醒已挂客户则不再重复挂 -->
          <div v-if="!form.customerId">
            <div class="flex items-center gap-2">
              <span class="text-xs text-n-slate-10 w-12 shrink-0">关联</span>
              <div class="flex-1">
                <SelectCard
                  :model-value="form.refType"
                  :options="REF_TYPE_OPTS"
                  block
                  @update:model-value="onRefTypeChange"
                />
              </div>
            </div>
            <div v-if="form.refType" class="mt-2">
              <div
                v-if="form.refId"
                class="flex items-center justify-between px-3 py-2 text-sm border rounded-lg bg-n-iris-2 border-n-iris-6 text-n-iris-11"
              >
                <button
                  type="button"
                  class="flex items-center gap-1.5 truncate hover:underline"
                  @click="gotoRef"
                >
                  <Icon icon="i-lucide-link" class="size-4 shrink-0" />
                  <span class="truncate">{{ form.refName || '查看' }}</span>
                  <Icon icon="i-lucide-arrow-right" class="size-3.5 shrink-0" />
                </button>
                <button
                  type="button"
                  class="grid rounded-full size-5 place-items-center hover:bg-n-iris-4"
                  @click="clearRef"
                >
                  <Icon icon="i-lucide-x" class="size-3" />
                </button>
              </div>
              <div v-else ref="refPickerRef" class="relative">
                <input
                  v-model="refQuery"
                  type="text"
                  :placeholder="refLoading ? '加载中…' : '搜索选择…'"
                  class="w-full px-3 py-2 text-sm border rounded-lg outline-none bg-n-alpha-1 border-n-weak text-n-slate-12 focus:border-n-iris-7"
                  @focus="refOpen = true"
                />
                <div
                  v-if="refOpen && filteredRefs.length"
                  class="absolute z-20 w-full mt-1 overflow-auto border rounded-lg shadow-lg max-h-44 border-n-weak bg-n-solid-1"
                >
                  <button
                    v-for="r in filteredRefs"
                    :key="r.id"
                    type="button"
                    class="flex items-center w-full px-3 py-2 text-sm text-left text-n-slate-12 hover:bg-n-alpha-2"
                    @click="pickRef(r)"
                  >
                    {{ refItemName(form.refType, r) }}
                  </button>
                </div>
                <div
                  v-else-if="refOpen && !refLoading"
                  class="absolute z-20 w-full px-3 py-2 mt-1 text-xs border rounded-lg shadow-lg text-n-slate-9 border-n-weak bg-n-solid-1"
                >
                  {{ refQuery ? '无匹配记录' : '没有可选记录' }}
                </div>
              </div>
            </div>
          </div>

          <div class="flex items-center gap-3">
            <div class="flex-1">
              <DatePicker v-model="form.date" block :clearable="false" />
            </div>
            <label
              class="flex items-center gap-1.5 text-sm text-n-slate-11 shrink-0"
            >
              <input
                v-model="form.allDay"
                type="checkbox"
                class="accent-n-iris-9"
              />
              全天
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
              :class="[
                DOT[c],
                form.color === c
                  ? 'ring-2 ring-offset-2 ring-n-slate-8 ring-offset-n-solid-1 scale-110'
                  : '',
              ]"
              @click="form.color = c"
            />
          </div>

          <!-- 重复 -->
          <div class="flex items-center gap-2">
            <span class="text-xs text-n-slate-10 w-12 shrink-0">重复</span>
            <div class="flex-1">
              <SelectCard
                v-model="form.recurrence"
                :options="recurOptions"
                block
              />
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

    <!-- 完成跟进弹窗（客户跟进提醒专用） -->
    <div
      v-if="completeDialog"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-black2"
      @click.self="completeDialog = false"
    >
      <div
        class="w-full max-w-[440px] max-h-[90vh] overflow-auto p-5 rounded-2xl bg-n-solid-1 shadow-xl border border-n-weak"
      >
        <div class="flex items-center justify-between mb-1">
          <h3 class="text-base font-semibold text-n-slate-12">完成跟进</h3>
          <button
            class="grid rounded-lg size-7 place-items-center text-n-slate-10 hover:bg-n-alpha-2"
            @click="completeDialog = false"
          >
            <Icon icon="i-lucide-x" class="size-4" />
          </button>
        </div>
        <p class="mb-4 text-xs text-n-slate-10">
          客户：<span class="font-medium text-n-slate-12">{{
            completeForm.customerName || '—'
          }}</span>
          · 记录本次跟进并可顺延下次提醒
        </p>

        <div class="flex flex-col gap-3.5">
          <textarea
            v-model="completeForm.body"
            rows="3"
            placeholder="本次跟进内容（例如：已发报价，客户询问交期…）"
            class="w-full px-3 py-2 text-sm border rounded-lg outline-none resize-none bg-n-alpha-1 border-n-weak text-n-slate-12 focus:border-n-iris-7"
          />
          <div class="flex items-center gap-2">
            <div class="flex-1">
              <SelectCard
                v-model="completeForm.method"
                :options="METHOD_OPTS"
                block
              />
            </div>
            <div class="flex-1">
              <SelectCard
                v-model="completeForm.resultTag"
                :options="RESULT_OPTS"
                block
              />
            </div>
          </div>
          <div class="flex items-center gap-2">
            <span class="text-xs text-n-slate-10 shrink-0">下次跟进</span>
            <div class="flex-1">
              <DatePicker
                v-model="completeForm.nextDate"
                block
                placeholder="留空＝完成不再提醒"
              />
            </div>
          </div>
        </div>

        <div class="flex justify-end gap-2 mt-5">
          <button
            class="px-4 py-2 text-sm font-medium rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
            @click="completeDialog = false"
          >
            取消
          </button>
          <button
            class="px-4 py-2 text-sm font-semibold text-white rounded-lg bg-n-teal-9 hover:bg-n-teal-10 disabled:opacity-60"
            :disabled="completeSaving"
            @click="submitComplete"
          >
            {{ completeSaving ? '保存中…' : '完成跟进' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
