<script setup>
import { ref, computed, onMounted } from 'vue';
import { Capacitor } from '@capacitor/core';
import { Haptics, ImpactStyle } from '@capacitor/haptics';
import PageHeader from '@/components/PageHeader.vue';
import DataState from '@/components/DataState.vue';
import AppSheet from '@/components/AppSheet.vue';
import { fetchAttendance, clockAttendance } from '@/api/crm';

defineOptions({ name: 'AttendancePage' });

// 与后端 Crm::AttendanceRecord::STATUSES 和网页端考勤表同一套口径
const STATUS_LABELS = {
  NORMAL: '正常',
  LATE: '迟到',
  EARLY_LEAVE: '早退',
  LATE_EARLY: '迟到+早退',
  ABSENT: '缺卡',
  LEAVE: '请假',
  HALF_LEAVE: '请假(半天)',
  FIELD: '外勤',
};
const STATUS_CLASS = {
  NORMAL: 'text-[color:var(--pb-ink)]',
  FIELD: 'text-[color:var(--pb-accent)]',
  LATE: 'text-[color:var(--pb-brand-ink)]',
  EARLY_LEAVE: 'text-[color:var(--pb-brand-ink)]',
  LATE_EARLY: 'text-[color:var(--pb-brand-ink)]',
  ABSENT: 'text-[#C4383C]',
  LEAVE: 'text-[color:var(--pb-accent)]',
  HALF_LEAVE: 'text-[color:var(--pb-accent)]',
};

const records = ref([]);
const setting = ref({});
const month = ref(new Date().toISOString().slice(0, 7));
const loading = ref(true);
const failed = ref(false);
const staleAt = ref(null);
const clocking = ref(false);
const message = ref('');
const error = ref('');
const fieldSheet = ref(false);

const today = new Date().toISOString().slice(0, 10);
const todayRecord = computed(() => records.value.find(r => r.work_date === today));

const clockedIn = computed(() => !!todayRecord.value?.clock_in_at);
const nowLabel = computed(() =>
  new Date().toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit', hour12: false })
);

// 本月统计：出勤天数与异常天数，给个整体感觉
const summary = computed(() => {
  const worked = records.value.filter(r => r.clock_in_at).length;
  const abnormal = records.value.filter(r =>
    ['LATE', 'EARLY_LEAVE', 'LATE_EARLY', 'ABSENT'].includes(r.status)
  ).length;
  return { worked, abnormal };
});

const load = async () => {
  loading.value = true;
  failed.value = false;
  try {
    const r = await fetchAttendance(month.value);
    records.value = r.data?.payload || [];
    setting.value = r.data?.setting || {};
    staleAt.value = r.fromCache ? r.at : null;
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

// 只有考勤组开了地理围栏才取定位——没开就别向用户要位置权限
const readPosition = async () => {
  if (!setting.value.geo_enabled) return {};
  try {
    const { Geolocation } = await import('@capacitor/geolocation');
    const pos = await Geolocation.getCurrentPosition({ timeout: 10000 });
    return { lat: pos.coords.latitude, lng: pos.coords.longitude };
  } catch {
    // 拿不到定位就按无坐标提交，由后端按公司网络（IP）那条规则判定
    return {};
  }
};

const clock = async (field = false) => {
  clocking.value = true;
  message.value = '';
  error.value = '';
  try {
    const coords = field ? {} : await readPosition();
    const { data } = await clockAttendance({ ...coords, field });
    // 后端返回整条记录，直接替换当天那条，不必重拉整月
    const i = records.value.findIndex(r => r.work_date === data.work_date);
    if (i >= 0) records.value[i] = data;
    else records.value.push(data);
    message.value = data.clock_out_at
      ? `下班打卡成功 ${data.clock_out_at}`
      : `上班打卡成功 ${data.clock_in_at}`;
    fieldSheet.value = false;
    if (Capacitor.isNativePlatform()) {
      await Haptics.impact({ style: ImpactStyle.Medium }).catch(() => {});
    }
  } catch (e) {
    error.value =
      e.response?.data?.error ||
      (e.response ? `打卡失败（HTTP ${e.response.status}）` : '网络不可用，打卡失败');
  } finally {
    clocking.value = false;
  }
};

const dayLabel = date => {
  const d = new Date(`${date}T00:00:00`);
  return `${d.getMonth() + 1}/${d.getDate()} ${'日一二三四五六'[d.getDay()]}`;
};

onMounted(load);
</script>

<template>
  <div class="flex flex-col h-full">
    <PageHeader back title="考勤打卡" :subtitle="setting.name || ''" />

    <div class="flex-1 min-h-0 px-4 pt-3 overflow-y-auto">
      <DataState
        :loading="loading"
        :failed="failed"
        :stale-at="staleAt"
        @retry="load"
      >
        <!-- 打卡卡片 -->
        <div class="p-5 text-center wt-card">
          <div class="text-3xl font-bold tabular-nums text-[color:var(--pb-ink)]">{{ nowLabel }}</div>
          <p class="mt-1 text-xs text-[color:var(--pb-ink-3)]">
            {{ setting.clock_in_time }} 上班 · {{ setting.clock_out_time }} 下班
          </p>

          <div class="flex justify-center gap-6 mt-4">
            <div>
              <div class="text-sm font-semibold text-[color:var(--pb-ink)]">
                {{ todayRecord?.clock_in_at || '—' }}
              </div>
              <div class="mt-0.5 text-xs text-[color:var(--pb-ink-3)]">上班</div>
            </div>
            <div>
              <div class="text-sm font-semibold text-[color:var(--pb-ink)]">
                {{ todayRecord?.clock_out_at || '—' }}
              </div>
              <div class="mt-0.5 text-xs text-[color:var(--pb-ink-3)]">下班</div>
            </div>
          </div>

          <button
            type="button"
            class="w-full mt-5 wt-btn-primary"
            :disabled="clocking"
            @click="clock(false)"
          >
            {{ clocking ? '打卡中…' : clockedIn ? '下班打卡' : '上班打卡' }}
          </button>
          <button
            type="button"
            class="mt-3 text-xs wt-link text-[color:var(--pb-accent)]"
            @click="fieldSheet = true"
          >
            在外面？用外勤打卡
          </button>

          <p v-if="message" class="mt-3 text-sm text-[color:var(--pb-ink)]">{{ message }}</p>
          <p v-if="error" class="mt-3 text-sm text-[#C4383C]">{{ error }}</p>
        </div>

        <!-- 本月概览 -->
        <div class="grid grid-cols-2 mt-3 overflow-hidden wt-card">
          <div class="py-3 text-center border-r border-[color:var(--pb-sep)]">
            <div class="text-xl font-bold text-[color:var(--pb-ink)]">{{ summary.worked }}</div>
            <div class="mt-0.5 text-xs text-[color:var(--pb-ink-3)]">本月出勤</div>
          </div>
          <div class="py-3 text-center">
            <div
              class="text-xl font-bold"
              :class="summary.abnormal ? 'text-[color:var(--pb-brand-ink)]' : 'text-[color:var(--pb-ink)]'"
            >
              {{ summary.abnormal }}
            </div>
            <div class="mt-0.5 text-xs text-[color:var(--pb-ink-3)]">异常天数</div>
          </div>
        </div>

        <h2 class="mt-4 mb-2 text-xs font-semibold tracking-wide text-[color:var(--pb-ink-3)]">本月记录</h2>
        <p v-if="!records.length" class="py-8 text-sm text-center text-[color:var(--pb-ink-2)]">
          本月还没有打卡记录
        </p>
        <ul v-else class="overflow-hidden wt-card">
          <li
            v-for="r in [...records].reverse()"
            :key="r.work_date"
            class="flex items-center gap-3 px-3 py-2.5 border-b last:border-b-0 border-[color:var(--pb-sep)]"
          >
            <span class="flex-none w-16 text-sm text-[color:var(--pb-ink-2)]">{{ dayLabel(r.work_date) }}</span>
            <span class="flex-1 text-sm tabular-nums text-[color:var(--pb-ink)]">
              {{ r.clock_in_at || '—' }} － {{ r.clock_out_at || '—' }}
            </span>
            <span
              class="flex-none text-xs"
              :class="STATUS_CLASS[r.status] || 'text-[color:var(--pb-ink-3)]'"
            >
              {{ STATUS_LABELS[r.status] || r.status }}
            </span>
          </li>
        </ul>
        <div class="h-4" />
      </DataState>
    </div>

    <AppSheet :open="fieldSheet" title="外勤打卡" @close="fieldSheet = false">
      <p class="text-sm leading-relaxed text-[color:var(--pb-ink-2)]">
        出差、展会或在客户现场时用这个。外勤打卡会跳过公司网络与地点校验，记为外勤出勤、不判迟到，
        考勤表上会标明是外勤。
      </p>
      <p v-if="error" class="mt-3 text-sm text-[#C4383C]">{{ error }}</p>
      <template #footer>
        <button
          type="button"
          class="w-full wt-btn-primary"
          :disabled="clocking"
          @click="clock(true)"
        >
          {{ clocking ? '打卡中…' : '确认外勤打卡' }}
        </button>
      </template>
    </AppSheet>
  </div>
</template>
