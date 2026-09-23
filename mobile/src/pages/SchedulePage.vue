<script setup>
import { ref, computed, onMounted } from 'vue';
import PageHeader from '@/components/PageHeader.vue';
import DataState from '@/components/DataState.vue';
import EmptyState from '@/components/EmptyState.vue';
import { useAuthStore } from '@/stores/auth';
import { wallTime } from '@/utils/format';
import AppSheet from '@/components/AppSheet.vue';
import FormField from '@/components/FormField.vue';
import CustomerPicker from '@/components/CustomerPicker.vue';
import {
  fetchScheduleEvents,
  createScheduleEvent,
  updateScheduleEvent,
  deleteScheduleEvent,
  toggleScheduleDone,
} from '@/api/crm';

defineOptions({ name: 'SchedulePage' });

const auth = useAuthStore();

const monthStart = ref(new Date(new Date().getFullYear(), new Date().getMonth(), 1));
// 选中的那一天（时间轴只画这一天）。月数据照旧整月拉，周条上的小圆点要靠它。
const selected = ref(new Date());
const events = ref([]);
const loading = ref(true);
const failed = ref(false);
const staleAt = ref(null);

const monthLabel = computed(
  () => `${monthStart.value.getFullYear()} 年 ${monthStart.value.getMonth() + 1} 月`
);

// 本地时区下的 YYYY-MM-DD，别用 toISOString——那是 UTC，跨时区会差一天
const ymd = d =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

const range = computed(() => {
  const s = monthStart.value;
  return {
    from: ymd(s),
    to: ymd(new Date(s.getFullYear(), s.getMonth() + 1, 0)),
  };
});

const dayKey = e => e.occurrence_date || String(e.starts_at).slice(0, 10);

// 哪几天有安排——周条上的小圆点用
const daysWithEvents = computed(() => new Set(events.value.map(dayKey)));

// 周条：以选中日所在周的周一为起点
const weekDays = computed(() => {
  const d = new Date(selected.value);
  const dow = (d.getDay() + 6) % 7; // 周一=0
  const mon = new Date(d.getFullYear(), d.getMonth(), d.getDate() - dow);
  return Array.from({ length: 7 }, (_, i) => {
    const x = new Date(mon.getFullYear(), mon.getMonth(), mon.getDate() + i);
    return { date: x, key: ymd(x), day: x.getDate(), w: '一二三四五六日'[i] };
  });
});

// 选中那天的安排，按时间排。全天的排最前。
const dayEvents = computed(() =>
  events.value
    .filter(e => dayKey(e) === ymd(selected.value))
    .sort((a, b) => {
      if (a.all_day !== b.all_day) return a.all_day ? -1 : 1;
      return String(a.starts_at).localeCompare(String(b.starts_at));
    })
);

// 高亮「当前或下一个」——今天才有，其它日子不高亮，免得误导
const activeId = computed(() => {
  if (ymd(selected.value) !== ymd(new Date())) return null;
  const now = new Date();
  const hit = dayEvents.value.find(
    e => !e.all_day && !e.done && new Date(e.ends_at || e.starts_at) >= now
  );
  return hit ? `${hit.id}-${dayKey(hit)}` : null;
});

const hhmm = wallTime;
const rowKey = e => `${e.id}-${dayKey(e)}`;

const load = async () => {
  loading.value = true;
  failed.value = false;
  try {
    const r = await fetchScheduleEvents(range.value);
    events.value = r.data?.payload || [];
    staleAt.value = r.fromCache ? r.at : null;
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

const shiftWeek = delta => {
  const d = selected.value;
  const next = new Date(d.getFullYear(), d.getMonth(), d.getDate() + delta * 7);
  selected.value = next;
  // 跨月了就重新拉月数据
  if (next.getMonth() !== monthStart.value.getMonth() || next.getFullYear() !== monthStart.value.getFullYear()) {
    monthStart.value = new Date(next.getFullYear(), next.getMonth(), 1);
    load();
  }
};

const pickDay = d => {
  selected.value = d;
};

const longDate = computed(() => {
  const d = selected.value;
  return `${d.getFullYear()} 年 ${d.getMonth() + 1} 月 ${d.getDate()} 日`;
});
const isToday = computed(() => ymd(selected.value) === ymd(new Date()));
const weekdayTitle = computed(() => `周${'日一二三四五六'[selected.value.getDay()]}`);

const goToday = () => {
  const now = new Date();
  selected.value = now;
  if (now.getMonth() !== monthStart.value.getMonth() || now.getFullYear() !== monthStart.value.getFullYear()) {
    monthStart.value = new Date(now.getFullYear(), now.getMonth(), 1);
    load();
  }
};

// 副标题：备注优先，其次关联对象/地点/所有者。黑卡和裸行共用一份口径。
const subtitleOf = ev =>
  ev.note ||
  [ev.ref_name || ev.customer_name, ev.location, ev.is_owner ? '' : ev.owner_name]
    .filter(Boolean)
    .join(' · ');

const toggle = async ev => {
  const date = ev.occurrence_date || String(ev.starts_at).slice(0, 10);
  ev.done = !ev.done;
  try {
    await toggleScheduleDone(ev.id, date);
  } catch {
    ev.done = !ev.done;
  }
};

// ── 新建 / 编辑 ──
const sheet = ref(false);
const saving = ref(false);
const error = ref('');
const editId = ref(null);
const form = ref({});
const customer = ref(null);

const BLANK = () => {
  const now = new Date();
  now.setMinutes(0, 0, 0);
  now.setHours(now.getHours() + 1);
  const pad = n => String(n).padStart(2, '0');
  const local = d =>
    `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
  const end = new Date(now.getTime() + 3600000);
  return {
    title: '',
    starts_at: local(now),
    ends_at: local(end),
    all_day: false,
    location: '',
    note: '',
    color: 'violet',
  };
};

const openNew = () => {
  editId.value = null;
  form.value = BLANK();
  customer.value = null;
  error.value = '';
  sheet.value = true;
};

const openEdit = ev => {
  // 后端只允许本人改自己的日程，别人的直接不给编辑入口
  if (!ev.is_owner) return;
  editId.value = ev.id;
  form.value = {
    title: ev.title,
    starts_at: String(ev.starts_at).slice(0, 16),
    ends_at: ev.ends_at ? String(ev.ends_at).slice(0, 16) : '',
    all_day: !!ev.all_day,
    location: ev.location || '',
    note: ev.note || '',
    color: ev.color || 'violet',
  };
  customer.value =
    ev.ref_type === 'customer' && ev.ref_id
      ? { id: ev.ref_id, name: ev.ref_name || ev.customer_name || '已关联客户' }
      : null;
  error.value = '';
  sheet.value = true;
};

const save = async () => {
  if (!form.value.title.trim()) {
    error.value = '请填写日程标题';
    return;
  }
  saving.value = true;
  error.value = '';
  try {
    const payload = {
      ...form.value,
      ends_at: form.value.ends_at || null,
      ref_type: customer.value ? 'customer' : null,
      ref_id: customer.value?.id || null,
    };
    if (editId.value) await updateScheduleEvent(editId.value, payload);
    else await createScheduleEvent(payload);
    sheet.value = false;
    await load();
  } catch (e) {
    error.value =
      e.response?.data?.error || e.response?.data?.message || '保存失败，请重试';
  } finally {
    saving.value = false;
  }
};

const remove = async () => {
  saving.value = true;
  try {
    await deleteScheduleEvent(editId.value);
    sheet.value = false;
    await load();
  } catch {
    error.value = '删除失败，请重试';
  } finally {
    saving.value = false;
  }
};

const selectedLabel = computed(() => {
  const d = selected.value;
  const isToday = ymd(d) === ymd(new Date());
  return `${d.getMonth() + 1}月${d.getDate()}日 周${'日一二三四五六'[d.getDay()]}${isToday ? ' · 今天' : ''}`;
});

onMounted(load);
</script>

<template>
  <div class="flex flex-col h-full">
    <PageHeader title="日程表">
      <template #actions>
        <button
          type="button"
          aria-label="新建日程"
          class="wt-fab-round wt-press"
          @click="openNew"
        >
          <span class="size-5 i-lucide-plus" />
        </button>
      </template>
    </PageHeader>

    <div class="flex-1 min-h-0 overflow-y-auto">
      <!-- 头部卡：日期行 + 大标题 + 头像 + 周条，全在一张白卡里（定稿的形） -->
      <div class="mx-4 px-5 pt-5 pb-4 rounded-[26px] bg-[color:var(--pb-card)]">
        <div class="flex items-start gap-3">
          <div class="flex-1 min-w-0">
            <p class="text-[15px] leading-5 text-[color:var(--pb-ink-3)]">{{ longDate }}</p>
            <h2
              class="mt-1 text-[30px] font-bold leading-9 tracking-[-0.6px] text-[color:var(--pb-ink)]"
            >
              {{ isToday ? '今天' : weekdayTitle }}
            </h2>
          </div>
          <button
            type="button"
            aria-label="回到今天"
            class="grid flex-none rounded-full size-12 place-items-center text-[15px] font-semibold bg-[color:var(--pb-fill)] text-[color:var(--pb-ink-2)] wt-press"
            @click="goToday"
          >
            {{ (auth.user?.name || '?').trim().slice(0, 1).toUpperCase() }}
          </button>
        </div>

        <!-- 周条：日期在上、周几在下；选中是竖向黑胶囊 + 底部白点 -->
        <div class="flex mt-4">
          <button
            v-for="d in weekDays"
            :key="d.key"
            type="button"
            class="flex flex-col items-center flex-1 gap-1 py-2.5 rounded-full transition-colors"
            :class="d.key === ymd(selected) ? 'bg-[color:var(--pb-ink)]' : ''"
            @click="pickDay(d.date)"
          >
            <span
              class="text-[17px] font-semibold leading-6 tabular-nums"
              :class="
                d.key === ymd(selected)
                  ? 'text-[color:var(--pb-on-ink)]'
                  : 'text-[color:var(--pb-ink-3)]'
              "
            >
              {{ d.day }}
            </span>
            <span
              class="text-[13px] leading-4"
              :class="
                d.key === ymd(selected)
                  ? 'text-[color:var(--pb-on-ink)]'
                  : 'text-[color:var(--pb-ink-3)]'
              "
            >
              周{{ d.w }}
            </span>
            <span
              class="rounded-full size-1"
              :class="
                daysWithEvents.has(d.key)
                  ? d.key === ymd(selected)
                    ? 'bg-[color:var(--pb-on-ink)]'
                    : 'bg-[color:var(--pb-ink-3)]'
                  : 'bg-transparent'
              "
            />
          </button>
        </div>
      </div>

      <div class="px-4 pt-5">
        <DataState
          :loading="loading"
          :failed="failed"
          :empty="!dayEvents.length"
          :stale-at="staleAt"
          @retry="load"
        >
          <template #empty>
            <EmptyState
              icon="i-ri-calendar-2-fill"
              badge="i-ri-add-line"
              title="这一天没有安排"
              action="新建日程"
              @action="openNew"
            />
          </template>

          <!-- 时间轴：左侧只有圆点和竖线（定稿里没有时间刻度列，时间在每条右侧） -->
          <ul>
            <li v-for="(ev, i) in dayEvents" :key="rowKey(ev)" class="flex gap-4">
              <div class="flex flex-col items-center flex-none w-3">
                <span
                  class="mt-2 rounded-full size-3"
                  :class="
                    rowKey(ev) === activeId
                      ? 'bg-[color:var(--pb-ink)] ring-[3px] ring-[color:var(--pb-ink)]/20'
                      : 'ring-[1.5px] ring-[color:var(--pb-ink-3)] bg-transparent'
                  "
                />
                <span
                  v-if="i < dayEvents.length - 1"
                  class="flex-1 w-px mt-1.5 bg-[color:var(--pb-ink-3)]/45"
                />
              </div>

              <!-- 当前项：黑卡 + 波纹 + 参与人 + 勾选 -->
              <button
                v-if="rowKey(ev) === activeId"
                type="button"
                class="flex-1 min-w-0 p-4 mb-6 overflow-hidden text-left rounded-[22px] pb-wave wt-press"
                @click="openEdit(ev)"
              >
                <div class="flex items-start gap-3">
                  <span
                    class="flex-1 min-w-0 text-[20px] font-bold leading-7 truncate text-[color:var(--pb-on-ink)]"
                  >
                    {{ ev.title }}
                  </span>
                  <span class="flex-none mt-1 text-[13px] tabular-nums text-[color:var(--pb-on-ink-2)]">
                    {{ ev.all_day ? '全天' : hhmm(ev.starts_at) }}
                  </span>
                </div>
                <p
                  v-if="subtitleOf(ev)"
                  class="mt-1 text-[14px] leading-5 line-clamp-2 text-[color:var(--pb-on-ink-2)]"
                >
                  {{ subtitleOf(ev) }}
                </p>

                <div class="flex items-center gap-3 mt-4">
                  <div v-if="ev.participant_names?.length" class="flex items-center">
                    <span
                      v-for="(n, k) in ev.participant_names.slice(0, 3)"
                      :key="n + k"
                      class="grid rounded-full size-9 place-items-center text-[13px] font-semibold -ml-2.5 first:ml-0 ring-2 ring-[color:var(--pb-ink)] bg-[color:var(--pb-on-ink-fill)] text-[color:var(--pb-on-ink)]"
                    >
                      {{ String(n).trim().slice(0, 1) }}
                    </span>
                    <span
                      v-if="ev.participant_names.length > 3"
                      class="grid rounded-full size-9 place-items-center text-[12px] font-semibold -ml-2.5 ring-2 ring-[color:var(--pb-ink)] bg-[color:var(--pb-on-ink-fill)] text-[color:var(--pb-on-ink)]"
                    >
                      +{{ ev.participant_names.length - 3 }}
                    </span>
                  </div>
                  <span class="flex-1" />
                  <span
                    :aria-label="ev.done ? '标记未完成' : '标记完成'"
                    class="grid flex-none rounded-xl size-11 place-items-center bg-[color:var(--pb-on-ink)] text-[color:var(--pb-ink)]"
                    @click.stop="toggle(ev)"
                  >
                    <span class="size-5 i-lucide-check" />
                  </span>
                </div>
              </button>

              <!-- 其余项：裸列 -->
              <button
                v-else
                type="button"
                class="flex-1 min-w-0 pb-6 text-left transition-opacity active:opacity-50"
                @click="openEdit(ev)"
              >
                <div class="flex items-start gap-3">
                  <span
                    class="flex-1 min-w-0 text-[20px] font-bold leading-7 truncate"
                    :class="
                      ev.done
                        ? 'line-through text-[color:var(--pb-ink-3)]'
                        : 'text-[color:var(--pb-ink)]'
                    "
                  >
                    {{ ev.title }}
                  </span>
                  <span class="flex-none mt-1 text-[13px] tabular-nums text-[color:var(--pb-ink-3)]">
                    {{ ev.all_day ? '全天' : hhmm(ev.starts_at) }}
                  </span>
                </div>
                <p
                  v-if="subtitleOf(ev)"
                  class="mt-1 text-[14px] leading-5 line-clamp-2 text-[color:var(--pb-ink-3)]"
                >
                  {{ subtitleOf(ev) }}
                </p>
              </button>
            </li>
          </ul>
          <div class="h-36" />
        </DataState>
      </div>
    </div>

    <AppSheet :open="sheet" :title="editId ? '编辑日程' : '新建日程'" @close="sheet = false">
      <div class="flex flex-col gap-4">
        <FormField label="标题" required>
          <input v-model="form.title" type="text" placeholder="要做什么" class="wt-field" />
        </FormField>

        <label class="flex items-center gap-2">
          <input v-model="form.all_day" type="checkbox" class="size-4 accent-[color:var(--pb-ink)]" />
          <span class="text-sm text-[color:var(--pb-ink)]">全天</span>
        </label>

        <div class="grid grid-cols-2 gap-3">
          <FormField label="开始">
            <input v-model="form.starts_at" type="datetime-local" class="wt-field" />
          </FormField>
          <FormField label="结束">
            <input v-model="form.ends_at" type="datetime-local" class="wt-field" />
          </FormField>
        </div>

        <CustomerPicker v-model="customer" />

        <FormField label="地点">
          <input v-model="form.location" type="text" class="wt-field" />
        </FormField>

        <FormField label="备注">
          <textarea v-model="form.note" rows="3" class="wt-field" />
        </FormField>

        <p v-if="error" class="text-sm text-[#C4383C]">{{ error }}</p>
      </div>

      <template #footer>
        <div class="flex gap-2">
          <button
            v-if="editId"
            type="button"
            class="flex-none px-4 wt-btn text-[#C4383C] bg-[#C4383C]/10 active:bg-[#C4383C]/15"
            :disabled="saving"
            @click="remove"
          >
            删除
          </button>
          <button
            type="button"
            class="flex-1 wt-btn-primary"
            :disabled="saving"
            @click="save"
          >
            {{ saving ? '保存中…' : '保存' }}
          </button>
        </div>
      </template>
    </AppSheet>
  </div>
</template>
