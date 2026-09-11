<script setup>
import { ref, computed, onMounted } from 'vue';
import PageHeader from '@/components/PageHeader.vue';
import DataState from '@/components/DataState.vue';
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

const monthStart = ref(new Date(new Date().getFullYear(), new Date().getMonth(), 1));
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

// 接口返回的是「展开后的每次发生」，按天分组更贴近日程的读法
const grouped = computed(() => {
  const map = new Map();
  events.value.forEach(e => {
    const key = e.occurrence_date || String(e.starts_at).slice(0, 10);
    if (!map.has(key)) map.set(key, []);
    map.get(key).push(e);
  });
  return [...map.entries()].sort((a, b) => a[0].localeCompare(b[0]));
});

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

const shiftMonth = delta => {
  const s = monthStart.value;
  monthStart.value = new Date(s.getFullYear(), s.getMonth() + delta, 1);
  load();
};

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

const dayHeading = date => {
  const d = new Date(`${date}T00:00:00`);
  const isToday = ymd(new Date()) === date;
  return `${d.getMonth() + 1}月${d.getDate()}日 周${'日一二三四五六'[d.getDay()]}${isToday ? ' · 今天' : ''}`;
};

const timeLabel = ev =>
  ev.all_day ? '全天' : String(ev.starts_at).slice(11, 16);

onMounted(load);
</script>

<template>
  <div class="flex flex-col h-full">
    <PageHeader back title="日程" :subtitle="monthLabel">
      <template #actions>
        <button
          type="button"
          aria-label="上个月"
          class="grid rounded-full size-9 place-items-center text-n-slate-11 active:bg-n-alpha-1"
          @click="shiftMonth(-1)"
        >
          <span class="size-5 i-lucide-chevron-left" />
        </button>
        <button
          type="button"
          aria-label="下个月"
          class="grid rounded-full size-9 place-items-center text-n-slate-11 active:bg-n-alpha-1"
          @click="shiftMonth(1)"
        >
          <span class="size-5 i-lucide-chevron-right" />
        </button>
        <button
          type="button"
          aria-label="新建日程"
          class="grid rounded-full size-9 place-items-center text-n-iris-11 active:bg-n-alpha-1"
          @click="openNew"
        >
          <span class="size-5 i-lucide-plus" />
        </button>
      </template>
    </PageHeader>

    <div class="flex-1 min-h-0 px-4 pt-3 overflow-y-auto">
      <DataState
        :loading="loading"
        :failed="failed"
        :empty="!events.length"
        :stale-at="staleAt"
        empty-text="这个月没有安排"
        @retry="load"
      >
        <template v-for="[date, list] in grouped" :key="date">
          <h2 class="mt-3 mb-2 text-xs font-semibold tracking-wide first:mt-0 text-n-slate-10">
            {{ dayHeading(date) }}
          </h2>
          <ul class="overflow-hidden wt-card">
            <li
              v-for="(ev, i) in list"
              :key="`${ev.id}-${i}`"
              class="flex items-start gap-3 px-3 py-3 border-b last:border-b-0 border-n-weak"
            >
              <button
                type="button"
                :aria-label="ev.done ? '标记未完成' : '标记完成'"
                class="grid flex-none mt-0.5 border rounded-full size-5 place-items-center"
                :class="
                  ev.done
                    ? 'bg-n-teal-9 border-n-teal-9 text-white'
                    : 'border-n-slate-8 text-transparent'
                "
                @click="toggle(ev)"
              >
                <span class="size-3 i-lucide-check" />
              </button>
              <button
                type="button"
                class="flex-1 min-w-0 text-left"
                @click="openEdit(ev)"
              >
                <div
                  class="text-sm font-medium truncate"
                  :class="ev.done ? 'line-through text-n-slate-10' : 'text-n-slate-12'"
                >
                  {{ ev.title }}
                </div>
                <div class="mt-0.5 text-xs truncate text-n-slate-10">
                  {{ timeLabel(ev) }}
                  <template v-if="ev.ref_name"> · {{ ev.ref_name }}</template>
                  <template v-if="ev.location"> · {{ ev.location }}</template>
                  <template v-if="!ev.is_owner"> · {{ ev.owner_name }}</template>
                </div>
              </button>
            </li>
          </ul>
        </template>
        <div class="h-4" />
      </DataState>
    </div>

    <AppSheet :open="sheet" :title="editId ? '编辑日程' : '新建日程'" @close="sheet = false">
      <div class="flex flex-col gap-4">
        <FormField label="标题" required>
          <input v-model="form.title" type="text" placeholder="要做什么" class="wt-field" />
        </FormField>

        <label class="flex items-center gap-2">
          <input v-model="form.all_day" type="checkbox" class="size-4 accent-n-iris-9" />
          <span class="text-sm text-n-slate-12">全天</span>
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

        <p v-if="error" class="text-sm text-n-ruby-11">{{ error }}</p>
      </div>

      <template #footer>
        <div class="flex gap-2">
          <button
            v-if="editId"
            type="button"
            class="flex-none px-4 wt-btn text-n-ruby-11 bg-n-ruby-3 active:bg-n-ruby-4"
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
