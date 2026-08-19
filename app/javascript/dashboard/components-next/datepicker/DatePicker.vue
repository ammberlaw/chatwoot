<script setup>
import { ref, computed, nextTick } from 'vue';
import { onClickOutside, useEventListener } from '@vueuse/core';

// 紫色玻璃「日期」选择器（日级），替换原生 <input type="date">（蓝、全宽、没法染色）。
// 与 MonthPicker/SelectCard 同款外壳：弹层 Teleport 到最近 <dialog> 顶层或 body，fixed 定位，
// 滚动/缩放即关，在对话框 / overflow 滚动容器里都不被裁切。值为 'YYYY-MM-DD'，空串=未选。
const props = defineProps({
  modelValue: { type: String, default: '' },
  placeholder: { type: String, default: '年 / 月 / 日' },
  align: { type: String, default: 'left' },
  triggerClass: { type: String, default: 'w-44' },
  block: { type: Boolean, default: false }, // true=触发器占满父容器宽（表单网格用）
  clearable: { type: Boolean, default: true },
});
const emit = defineEmits(['update:modelValue', 'change']);

const WEEKDAYS = ['日', '一', '二', '三', '四', '五', '六'];
const POP_W = 260;

const pad = n => String(n).padStart(2, '0');
const now = new Date();
const curYmd = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;

const open = ref(false);
const triggerEl = ref(null);
const popoverEl = ref(null);
const popStyle = ref({});
const teleportTarget = ref('body');

onClickOutside(triggerEl, () => { open.value = false; }, { ignore: [popoverEl] }); // prettier-ignore
useEventListener('scroll', () => { if (open.value) open.value = false; }, { capture: true, passive: true }); // prettier-ignore
useEventListener('resize', () => {
  if (open.value) open.value = false;
});

const parsed = computed(() => {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(props.modelValue || '');
  return m ? { y: +m[1], mo: +m[2], d: +m[3] } : null;
});
const label = computed(() =>
  parsed.value
    ? `${parsed.value.y}-${pad(parsed.value.mo)}-${pad(parsed.value.d)}`
    : props.placeholder
);

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
    out.push({
      ymd: `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`,
      day: d.getDate(),
      inMonth: d.getMonth() + 1 === viewMonth.value,
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
  let left = props.align === 'right' ? r.right - POP_W : r.left;
  left = Math.max(8, Math.min(left, window.innerWidth - POP_W - 8));
  popStyle.value = { position: 'fixed', top: `${top}px`, left: `${left}px` };
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
};

const commit = value => {
  emit('update:modelValue', value);
  emit('change', value);
};
const pick = cell => {
  commit(cell.ymd);
  open.value = false;
};
const clear = () => {
  commit('');
  open.value = false;
};
const today = () => {
  commit(curYmd);
  open.value = false;
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
      <span class="text-n-slate-10 i-lucide-calendar size-4 shrink-0" />
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
          class="z-[9999] p-3 origin-top border shadow-xl w-[260px] rounded-2xl border-white/50 bg-n-solid-1/70 backdrop-blur-2xl backdrop-saturate-150 shadow-n-iris-9/15"
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
              class="text-sm rounded-lg size-8 tabular-nums transition-colors"
              :class="[
                c.ymd === modelValue
                  ? 'bg-n-iris-9 text-white font-medium shadow-sm shadow-n-iris-9/30'
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
            <button
              type="button"
              class="px-2 py-1 text-xs font-medium rounded-md text-n-iris-11 hover:bg-n-iris-3"
              @click="today"
            >
              今天
            </button>
          </div>
        </div>
      </transition>
    </teleport>
  </div>
</template>
