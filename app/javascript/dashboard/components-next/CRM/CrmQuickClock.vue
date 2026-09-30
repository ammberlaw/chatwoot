<script setup>
/* global axios */
// 工作台顶部「快捷打卡」（仿钉钉）：一屏内看今日打卡状态 + 一键上/下班打卡，无需进考勤页。
// 复用考勤模块的 /clock 与 GET(本月) 接口；仅对已加入考勤组（有 setting）的成员显示。
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';

// compact=只渲染紫色圆按钮（放工作台右上角）；默认=完整卡片。
defineProps({ compact: { type: Boolean, default: false } });

const router = useRouter();
const { accountId } = useAccount();
const api = () => `/api/v1/accounts/${accountId.value}/crm/attendances`;

const STATUS_META = {
  NORMAL: { label: '正常', cls: 'bg-n-teal-3 text-n-teal-11' },
  LATE: { label: '迟到', cls: 'bg-n-amber-3 text-n-amber-11' },
  EARLY_LEAVE: { label: '早退', cls: 'bg-n-amber-3 text-n-amber-11' },
  LATE_EARLY: { label: '迟到+早退', cls: 'bg-n-amber-3 text-n-amber-11' },
  ABSENT: { label: '旷工', cls: 'bg-n-ruby-3 text-n-ruby-11' },
  LEAVE: { label: '请假', cls: 'bg-n-iris-3 text-n-iris-11' },
  HALF_LEAVE: { label: '请假(半天)', cls: 'bg-n-iris-3 text-n-iris-11' },
  FIELD: { label: '外勤', cls: 'bg-n-blue-3 text-n-blue-11' },
};

const pad = n => String(n).padStart(2, '0');
const todayStr = () => {
  const d = new Date();
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
};

const setting = ref(null);
const records = ref([]);
const loaded = ref(false);
const todayRec = computed(
  () => records.value.find(r => r.work_date === todayStr()) || null
);
const isClockedIn = computed(() => !!todayRec.value?.clock_in_at);
// 忘打上班卡、过了「上班~下班时段中点」再来打，后端记的是下班卡
// （见 attendances_controller 的 past_workday_midpoint?）。按钮必须显示同一口径，
// 否则晚上补打的人看到「上班」，以为下班卡打不了。
// 与后端 clock_out_window_start 同一公式：下班前 60 分钟起算「这一下是下班卡」。
// 上下班间隔不足两小时的班次退回中点，避免阈值落到上班时间之前。
const CLOCK_OUT_WINDOW_MINUTES = 60;
const clockOutWindowStart = (i, o) =>
  o - i < CLOCK_OUT_WINDOW_MINUTES * 2
    ? (i + o) / 2
    : o - CLOCK_OUT_WINDOW_MINUTES;

const hm = raw => {
  const m = /^(\d{1,2}):(\d{2})$/.exec(String(raw || ''));
  return m ? Number(m[1]) * 60 + Number(m[2]) : null;
};
const willClockOut = computed(() => {
  if (todayRec.value?.clock_out_at) return false;
  if (isClockedIn.value) return true;
  const i = hm(setting.value?.clock_in_time);
  const o = hm(setting.value?.clock_out_time);
  if (i === null || o === null || o <= i) return false;
  const d = new Date();
  return d.getHours() * 60 + d.getMinutes() >= clockOutWindowStart(i, o);
});

// 实时时钟（每秒刷新）。
const now = ref(new Date());
let timer = null;
const clockText = computed(
  () =>
    `${pad(now.value.getHours())}:${pad(now.value.getMinutes())}:${pad(now.value.getSeconds())}`
);
const WEEK = ['日', '一', '二', '三', '四', '五', '六'];
const dateText = computed(
  () =>
    `${now.value.getMonth() + 1}月${now.value.getDate()}日 周${WEEK[now.value.getDay()]}`
);

// 迟到预警：已过「上班时间+宽限」且今天还没打上班卡（且是工作日、非节假日）。
const lateHint = computed(() => {
  if (!setting.value || isClockedIn.value) return null;
  // 已过中点、这一下记的是下班卡，就不该再提示迟到。
  if (willClockOut.value) return null;
  const [h, m] = (setting.value.clock_in_time || '09:00')
    .split(':')
    .map(Number);
  const dow = now.value.getDay() || 7;
  if (!(setting.value.work_days || []).includes(dow)) return null;
  if ((setting.value.holidays || []).includes(todayStr())) return null;
  const nowMin = now.value.getHours() * 60 + now.value.getMinutes();
  const dueMin = h * 60 + m + (setting.value.grace_minutes || 0);
  return nowMin > dueMin
    ? `已超过上班时间 ${nowMin - dueMin} 分钟，现在打卡将记迟到`
    : null;
});

const fetchToday = async () => {
  try {
    const { data } = await axios.get(api(), {
      params: { month: todayStr().slice(0, 7) },
    });
    records.value = data.payload || [];
    setting.value = data.setting;
  } catch {
    setting.value = null;
  } finally {
    loaded.value = true;
  }
};

// 考勤组开启 GPS 校验（或外勤）时先取浏览器定位；失败则空，交后端判定。
const getGeo = () =>
  new Promise(resolve => {
    if (!navigator.geolocation) {
      resolve({});
      return;
    }
    navigator.geolocation.getCurrentPosition(
      pos => resolve({ lat: pos.coords.latitude, lng: pos.coords.longitude }),
      () => resolve({}),
      { enableHighAccuracy: true, timeout: 8000, maximumAge: 60000 }
    );
  });

const clocking = ref(false);
const clock = async (field = false) => {
  if (clocking.value) return;
  // eslint-disable-next-line no-alert
  if (
    field &&
    !window.confirm('确认外勤打卡？将把今日标记为「外勤」（计出勤、不判迟到）')
  ) {
    return;
  }
  clocking.value = true;
  try {
    const body = setting.value?.geo_enabled || field ? await getGeo() : {};
    if (field) body.field = true;
    const wasClockedIn = isClockedIn.value;
    await axios.post(`${api()}/clock`, body);
    if (field) useAlert('外勤打卡成功');
    else useAlert(wasClockedIn ? '下班打卡成功' : '上班打卡成功');
    fetchToday();
  } catch (e) {
    useAlert(e.response?.data?.error || '打卡失败，请重试');
  } finally {
    clocking.value = false;
  }
};

const goDetail = () =>
  router.push({ name: 'crm_attendance_index' }).catch(() => {});

onMounted(() => {
  fetchToday();
  timer = window.setInterval(() => {
    now.value = new Date();
  }, 1000);
});
onBeforeUnmount(() => timer && window.clearInterval(timer));
</script>

<template>
  <!-- 精简：仅一颗紫色圆按钮（一键上/下班打卡），放工作台右上角 -->
  <button
    v-if="compact && loaded && setting"
    type="button"
    class="flex flex-col items-center justify-center text-white transition-colors rounded-full shrink-0 size-14 bg-n-iris-9 hover:bg-n-iris-10 active:bg-n-iris-10 shadow-md shadow-n-iris-9/25 disabled:opacity-50"
    :disabled="clocking"
    :title="lateHint || '考勤打卡'"
    @click="clock()"
  >
    <span class="text-sm font-semibold leading-tight">
      {{ willClockOut ? '下班' : '上班' }}
    </span>
    <span class="text-[10px] opacity-90">打卡</span>
  </button>

  <!-- 完整卡片：大时钟 + 状态 + 一键打卡 + 外勤/明细 -->
  <div
    v-else-if="loaded && setting"
    class="p-4 border shadow-sm rounded-2xl border-white/60 bg-n-solid-1/70 backdrop-blur-xl"
  >
    <div class="flex items-center gap-4">
      <div class="flex-1 min-w-0">
        <div
          class="text-3xl font-semibold tabular-nums text-n-slate-12 leading-none"
        >
          {{ clockText }}
        </div>
        <div class="mt-1 text-xs truncate text-n-slate-11">
          {{ dateText
          }}<template v-if="setting.name"> · {{ setting.name }}</template> ·
          工作 {{ setting.clock_in_time }}–{{ setting.clock_out_time }}
        </div>
        <div class="flex flex-wrap items-center gap-2 mt-1.5 text-xs">
          <span class="text-n-slate-11">
            上班
            <b class="text-n-slate-12">{{ todayRec?.clock_in_at || '—' }}</b>
          </span>
          <span class="text-n-slate-11">
            下班
            <b class="text-n-slate-12">{{ todayRec?.clock_out_at || '—' }}</b>
          </span>
          <span
            v-if="todayRec"
            class="px-1.5 py-0.5 rounded-full"
            :class="STATUS_META[todayRec.status]?.cls"
          >
            {{ STATUS_META[todayRec.status]?.label || todayRec.status }}
          </span>
        </div>
      </div>
      <button
        type="button"
        class="flex flex-col items-center justify-center text-white transition-colors rounded-full shrink-0 size-16 bg-n-iris-9 hover:bg-n-iris-10 active:bg-n-iris-10 disabled:opacity-50"
        :disabled="clocking"
        @click="clock()"
      >
        <span class="text-sm font-semibold leading-tight">
          {{ willClockOut ? '下班' : '上班' }}
        </span>
        <span class="text-[10px] opacity-90">打卡</span>
      </button>
    </div>

    <div
      v-if="lateHint"
      class="inline-flex items-center gap-1 mt-2 text-xs font-medium text-n-amber-11"
    >
      <span class="i-lucide-alarm-clock size-3.5" />
      {{ lateHint }}
    </div>

    <div class="flex items-center gap-4 mt-2.5 text-xs">
      <button
        type="button"
        class="inline-flex items-center gap-1 font-medium text-n-blue-11 hover:underline disabled:opacity-50"
        :disabled="clocking"
        title="出差 / 客户现场打卡，不受打卡范围限制"
        @click="clock(true)"
      >
        <span class="i-lucide-map-pin size-3.5" />
        外勤打卡
      </button>
      <button
        type="button"
        class="inline-flex items-center gap-1 text-n-slate-11 hover:text-n-slate-12"
        @click="goDetail"
      >
        <span class="i-lucide-calendar-days size-3.5" />
        考勤明细
      </button>
    </div>
  </div>
</template>
