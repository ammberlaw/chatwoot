<script setup>
import { ref, computed, nextTick, watch } from 'vue';
import { onClickOutside, useEventListener } from '@vueuse/core';

// 紫色玻璃「日期」选择器（日级），替换原生 <input type="date">（蓝、全宽、没法染色）。
// 与 MonthPicker/SelectCard 同款外壳：弹层 Teleport 到最近 <dialog> 顶层或 body，fixed 定位，
// 滚动/缩放即关，在对话框 / overflow 滚动容器里都不被裁切。值为 'YYYY-MM-DD'，空串=未选。
//
// with-time：日历下面多两列时分（替换原生 <input type="datetime-local">，如邮件定时发送），
// 值变成 'YYYY-MM-DDTHH:mm'，与原生同格式，接它的后端/换算逻辑不用改。
// min：可选的最早时刻（'YYYY-MM-DD' 或 'YYYY-MM-DDTHH:mm'），更早的日期/时分置灰点不动。
const props = defineProps({
  modelValue: { type: String, default: '' },
  placeholder: { type: String, default: '年 / 月 / 日' },
  align: { type: String, default: 'left' },
  triggerClass: { type: String, default: 'w-44' },
  block: { type: Boolean, default: false }, // true=触发器占满父容器宽（表单网格用）
  clearable: { type: Boolean, default: true },
  withTime: { type: Boolean, default: false },
  min: { type: String, default: '' },
});
const emit = defineEmits(['update:modelValue', 'change']);

const WEEKDAYS = ['日', '一', '二', '三', '四', '五', '六'];
const VALUE_RE = /^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2}))?$/;
const MINUTE_STEP = 5;
const DEFAULT_HM = '09:00';

const pad = n => String(n).padStart(2, '0');
const now = new Date();
const curYmd = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;

const popWidth = computed(() => (props.withTime ? 300 : 260));

const open = ref(false);
const triggerEl = ref(null);
const popoverEl = ref(null);
const hourListEl = ref(null);
const minuteListEl = ref(null);
const popStyle = ref({});
const teleportTarget = ref('body');

onClickOutside(triggerEl, () => { open.value = false; }, { ignore: [popoverEl] }); // prettier-ignore
// 页面滚动即关；但时分列自己滚不算——它也会冒泡上来，不排除掉就是「一滚就关」。
useEventListener(
  'scroll',
  e => {
    if (!open.value) return;
    const t = e.target;
    if (t instanceof Node && popoverEl.value?.contains(t)) return;
    open.value = false;
  },
  { capture: true, passive: true }
);
useEventListener('resize', () => {
  if (open.value) open.value = false;
});

const parsed = computed(() => {
  const m = VALUE_RE.exec(props.modelValue || '');
  if (!m) return null;
  return {
    y: +m[1],
    mo: +m[2],
    d: +m[3],
    h: m[4] === undefined ? null : +m[4],
    mi: m[5] === undefined ? null : +m[5],
  };
});
// 已选的日期部分；时分单独拿，没选到时分就是空串。
const pickedYmd = computed(() =>
  parsed.value
    ? `${parsed.value.y}-${pad(parsed.value.mo)}-${pad(parsed.value.d)}`
    : ''
);
const pickedHm = computed(() =>
  parsed.value && parsed.value.h !== null
    ? `${pad(parsed.value.h)}:${pad(parsed.value.mi)}`
    : ''
);
const label = computed(() => {
  if (!parsed.value) return props.placeholder;
  return props.withTime && pickedHm.value
    ? `${pickedYmd.value} ${pickedHm.value}`
    : pickedYmd.value;
});

// ── 最早可选 ──
const minYmd = computed(() => {
  const m = VALUE_RE.exec(props.min || '');
  return m ? `${m[1]}-${m[2]}-${m[3]}` : '';
});
const minHm = computed(() => {
  const m = VALUE_RE.exec(props.min || '');
  return m && m[4] !== undefined ? `${m[4]}:${m[5]}` : '';
});
// 当前选中的那天正好是最早那天时，时分才需要卡下限。
const onMinDay = computed(
  () => !!minHm.value && (pickedYmd.value || minYmd.value) === minYmd.value
);

// 下限之后最近的一个整步长时刻（下限 09:02 → 09:05），用作「只选了日期还没选时间」的默认值。
const roundedMinHm = () => {
  if (!minHm.value) return DEFAULT_HM;
  const [h, mi] = minHm.value.split(':').map(Number);
  const stepped = Math.ceil(mi / MINUTE_STEP) * MINUTE_STEP;
  if (stepped > 59) return h >= 23 ? '23:55' : `${pad(h + 1)}:00`;
  return `${pad(h)}:${pad(stepped)}`;
};

// 弹层里正在浏览的年月
const viewYear = ref(now.getFullYear());
const viewMonth = ref(now.getMonth() + 1); // 1-12

// 当月日历 6×7 网格（含上/下月补位）
const cells = computed(() => {
  const first = new Date(viewYear.value, viewMonth.value - 1, 1);
  const startWd = first.getDay();
  const out = [];
  for (let i = 0; i < 42; i += 1) {
    const d = new Date(viewYear.value, viewMonth.value - 1, 1 - startWd + i);
    const ymd = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
    out.push({
      ymd,
      day: d.getDate(),
      inMonth: d.getMonth() + 1 === viewMonth.value,
      disabled: !!minYmd.value && ymd < minYmd.value,
    });
  }
  return out;
});

const prevMonth = () => {
  if (viewMonth.value === 1) {
    viewMonth.value = 12;
    viewYear.value -= 1;
  } else {
    viewMonth.value -= 1;
  }
};
const nextMonth = () => {
  if (viewMonth.value === 12) {
    viewMonth.value = 1;
    viewYear.value += 1;
  } else {
    viewMonth.value += 1;
  }
};

// ── 时分两列 ──
const hourOptions = computed(() => {
  const minHour = onMinDay.value ? +minHm.value.slice(0, 2) : -1;
  return Array.from({ length: 24 }, (_, h) => ({
    value: pad(h),
    disabled: h < minHour,
  }));
});
const minuteOptions = computed(() => {
  const picked = pickedHm.value;
  const values = [];
  for (let m = 0; m < 60; m += MINUTE_STEP) values.push(pad(m));
  // 存量值落在步长外（如 09:07）也要显示出来，否则看着像没选中。
  if (picked && !values.includes(picked.slice(3))) {
    values.push(picked.slice(3));
    values.sort();
  }
  const sameHour =
    onMinDay.value && picked && picked.slice(0, 2) === minHm.value.slice(0, 2);
  return values.map(v => ({
    value: v,
    disabled: sameHour && v < minHm.value.slice(3),
  }));
});

const positionPopover = () => {
  const el = triggerEl.value;
  if (!el) return;
  const r = el.getBoundingClientRect();
  const popH = popoverEl.value?.offsetHeight || 320;
  const below = r.bottom + 6;
  const top =
    below + popH > window.innerHeight && r.top - popH - 6 > 0
      ? r.top - popH - 6
      : below;
  let left = props.align === 'right' ? r.right - popWidth.value : r.left;
  left = Math.max(8, Math.min(left, window.innerWidth - popWidth.value - 8));
  popStyle.value = { position: 'fixed', top: `${top}px`, left: `${left}px` };
};

// 时分列是滚动的，打开时把已选项滚到视野里，不然看着像没选。
const scrollTimeIntoView = () => {
  [hourListEl.value, minuteListEl.value].forEach(list => {
    const active = list?.querySelector('[data-active="true"]');
    if (!active) return;
    // 用 rect 差值而不是 offsetTop：列本身没定位，offsetTop 是相对弹层算的，会把列直接滚到底。
    const delta =
      active.getBoundingClientRect().top - list.getBoundingClientRect().top;
    list.scrollTop += delta - list.clientHeight / 2 + active.offsetHeight / 2;
  });
};

const toggle = async () => {
  if (open.value) {
    open.value = false;
    return;
  }
  if (parsed.value) {
    viewYear.value = parsed.value.y;
    viewMonth.value = parsed.value.mo;
  } else {
    viewYear.value = now.getFullYear();
    viewMonth.value = now.getMonth() + 1;
  }
  teleportTarget.value = triggerEl.value?.closest('dialog') || 'body';
  open.value = true;
  await nextTick();
  positionPopover();
  if (props.withTime) scrollTimeIntoView();
};

watch([open, () => props.modelValue], async ([isOpen]) => {
  if (!isOpen || !props.withTime) return;
  await nextTick();
  scrollTimeIntoView();
});

const commit = value => {
  emit('update:modelValue', value);
  emit('change', value);
};
// 日期 + 时分拼回对外的值；不带时分模式只回日期。
const commitParts = (ymd, hm) => {
  if (!ymd) return commit('');
  return commit(props.withTime ? `${ymd}T${hm || roundedMinHm()}` : ymd);
};

// 换到某天后，原来的时分可能早于该天的下限（如下限 10/06 09:00，时分停在 08:30），顺手抬到下限。
const fitHmTo = ymd => {
  const hm = pickedHm.value;
  if (!minHm.value || ymd !== minYmd.value) return hm;
  return !hm || hm < minHm.value ? roundedMinHm() : hm;
};

const pick = cell => {
  if (cell.disabled) return;
  if (!props.withTime) {
    commit(cell.ymd);
    open.value = false;
    return;
  }
  // 带时分时不急着关：多半还要接着挑时间。
  commitParts(cell.ymd, fitHmTo(cell.ymd));
};
const pickHour = opt => {
  if (opt.disabled) return;
  const ymd = pickedYmd.value || minYmd.value || curYmd;
  const mi = (pickedHm.value || roundedMinHm()).slice(3);
  const next = `${opt.value}:${mi}`;
  commitParts(
    ymd,
    onMinDay.value && next < minHm.value ? roundedMinHm() : next
  );
};
const pickMinute = opt => {
  if (opt.disabled) return;
  const ymd = pickedYmd.value || minYmd.value || curYmd;
  const h = (pickedHm.value || roundedMinHm()).slice(0, 2);
  commitParts(ymd, `${h}:${opt.value}`);
};
const clear = () => {
  commit('');
  open.value = false;
};
const today = () => {
  if (minYmd.value && curYmd < minYmd.value) return;
  commitParts(curYmd, fitHmTo(curYmd));
  if (!props.withTime) open.value = false;
};
</script>

<template>
  <div :class="block ? 'w-full' : 'shrink-0'">
    <button
      ref="triggerEl"
      type="button"
      :class="[block ? 'w-full' : triggerClass]"
      class="inline-flex items-center justify-between h-9 gap-2 pl-3 text-sm text-left transition-all rounded-lg pr-2.5 outline outline-1 outline-n-weak bg-n-solid-1 hover:outline-n-brand"
      @click="toggle"
    >
      <span :class="parsed ? 'text-n-slate-12' : 'text-n-slate-9'">
        {{ label }}
      </span>
      <span
        class="text-n-slate-10 size-4 shrink-0"
        :class="withTime ? 'i-lucide-clock' : 'i-lucide-calendar'"
      />
    </button>

    <teleport :to="teleportTarget">
      <transition
        enter-active-class="transition duration-150 ease-out"
        enter-from-class="opacity-0 scale-95 -translate-y-1"
        enter-to-class="opacity-100 scale-100 translate-y-0"
        leave-active-class="transition duration-100 ease-in"
        leave-from-class="opacity-100 scale-100"
        leave-to-class="opacity-0 scale-95"
      >
        <!-- data-glass-popover：Teleport 成对话框内容的兄弟节点后，让对话框的 onClickOutside 忽略它，
             点日历不关整个对话框。注意：靠 @vueuse 的 ignore 判定（它在 pointerdown 阶段查 ignore），
             所以这里绝不能再 @pointerdown.stop——一 stop 就把 ignore 判定也挡掉了，反而会关。 -->
        <div
          v-if="open"
          ref="popoverEl"
          data-glass-popover
          :style="popStyle"
          class="z-[9999] p-3 origin-top border shadow-xl rounded-2xl border-white/50 bg-n-solid-1/70 backdrop-blur-2xl backdrop-saturate-150 shadow-n-iris-9/15"
          :class="withTime ? 'w-[300px]' : 'w-[260px]'"
        >
          <!-- 年月切换 -->
          <div class="flex items-center justify-between px-1 mb-2">
            <button
              type="button"
              class="flex items-center justify-center rounded-lg size-7 text-n-slate-11 hover:bg-n-alpha-2"
              @click="prevMonth"
            >
              <span class="i-lucide-chevron-left size-4" />
            </button>
            <span class="text-sm font-semibold text-n-slate-12 tabular-nums">
              {{ viewYear }}年{{ viewMonth }}月
            </span>
            <button
              type="button"
              class="flex items-center justify-center rounded-lg size-7 text-n-slate-11 hover:bg-n-alpha-2"
              @click="nextMonth"
            >
              <span class="i-lucide-chevron-right size-4" />
            </button>
          </div>

          <!-- 星期表头 -->
          <div class="grid grid-cols-7 mb-1">
            <span
              v-for="w in WEEKDAYS"
              :key="w"
              class="text-xs text-center text-n-slate-10"
            >
              {{ w }}
            </span>
          </div>

          <!-- 日期网格 -->
          <div class="grid grid-cols-7 gap-0.5">
            <button
              v-for="c in cells"
              :key="c.ymd"
              type="button"
              :disabled="c.disabled"
              class="text-sm rounded-lg size-8 tabular-nums transition-colors"
              :class="[
                c.ymd === pickedYmd
                  ? 'bg-n-iris-9 text-white font-medium shadow-sm shadow-n-iris-9/30'
                  : c.disabled
                    ? 'text-n-slate-8 cursor-not-allowed'
                    : c.ymd === curYmd
                      ? 'text-n-iris-11 bg-n-iris-3 hover:bg-n-iris-4'
                      : c.inMonth
                        ? 'text-n-slate-12 hover:bg-n-alpha-2'
                        : 'text-n-slate-9 hover:bg-n-alpha-2',
              ]"
              @click="pick(c)"
            >
              {{ c.day }}
            </button>
          </div>

          <!-- 时分（with-time）：两列可滚，选中跟日历同一种高亮 -->
          <div
            v-if="withTime"
            class="flex items-center gap-2 pt-2.5 mt-2.5 border-t border-n-weak/60"
          >
            <span class="text-xs shrink-0 text-n-slate-11">时间</span>
            <div
              ref="hourListEl"
              class="w-16 p-0.5 ml-auto overflow-y-auto rounded-lg h-28 bg-n-alpha-1 scroll-smooth"
            >
              <button
                v-for="h in hourOptions"
                :key="h.value"
                type="button"
                :disabled="h.disabled"
                :data-active="pickedHm.slice(0, 2) === h.value"
                class="w-full py-1 text-sm text-center rounded-md tabular-nums transition-colors"
                :class="
                  pickedHm.slice(0, 2) === h.value
                    ? 'bg-n-iris-9 text-white font-medium'
                    : h.disabled
                      ? 'text-n-slate-8 cursor-not-allowed'
                      : 'text-n-slate-12 hover:bg-n-alpha-2'
                "
                @click="pickHour(h)"
              >
                {{ h.value }}
              </button>
            </div>
            <span class="text-sm text-n-slate-10">:</span>
            <div
              ref="minuteListEl"
              class="w-16 p-0.5 mr-auto overflow-y-auto rounded-lg h-28 bg-n-alpha-1 scroll-smooth"
            >
              <button
                v-for="m in minuteOptions"
                :key="m.value"
                type="button"
                :disabled="m.disabled"
                :data-active="pickedHm.slice(3) === m.value"
                class="w-full py-1 text-sm text-center rounded-md tabular-nums transition-colors"
                :class="
                  pickedHm.slice(3) === m.value
                    ? 'bg-n-iris-9 text-white font-medium'
                    : m.disabled
                      ? 'text-n-slate-8 cursor-not-allowed'
                      : 'text-n-slate-12 hover:bg-n-alpha-2'
                "
                @click="pickMinute(m)"
              >
                {{ m.value }}
              </button>
            </div>
          </div>

          <!-- 底部操作 -->
          <div
            class="flex items-center pt-2.5 mt-2.5 border-t border-n-weak/60"
            :class="clearable ? 'justify-between' : 'justify-end'"
          >
            <button
              v-if="clearable"
              type="button"
              class="px-2 py-1 text-xs rounded-md text-n-slate-11 hover:bg-n-alpha-2"
              @click="clear"
            >
              清除
            </button>
            <div class="flex items-center gap-1">
              <button
                type="button"
                class="px-2 py-1 text-xs font-medium rounded-md text-n-iris-11 hover:bg-n-iris-3"
                @click="today"
              >
                今天
              </button>
              <button
                v-if="withTime"
                type="button"
                class="px-2.5 py-1 text-xs font-medium text-white rounded-md bg-n-iris-9 hover:bg-n-iris-10"
                @click="open = false"
              >
                确定
              </button>
            </div>
          </div>
        </div>
      </transition>
    </teleport>
  </div>
</template>
