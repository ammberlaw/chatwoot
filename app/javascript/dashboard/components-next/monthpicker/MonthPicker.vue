<script setup>
import { ref, computed, nextTick } from 'vue';
import { onClickOutside, useEventListener } from '@vueuse/core';

// 自定义月份选择器（紫色玻璃圆角），替换原生 <input type="month"> 与 年/月 双下拉。
// 值为 'YYYY-MM' 字符串，空串表示未选。弹层 Teleport（对话框内挂进 dialog，否则挂 body）+ fixed 定位，
// 在对话框 / 滚动容器里也不会被裁切。
const props = defineProps({
  modelValue: { type: String, default: '' },
  placeholder: { type: String, default: '----年--月' },
  align: { type: String, default: 'left' }, // 'left' | 'right'：弹层对齐边
  triggerClass: { type: String, default: 'w-40 h-10' },
  block: { type: Boolean, default: false }, // true=触发器占满父容器宽（表单用）
  clearable: { type: Boolean, default: true }, // 必填场景（看板/目标）关掉「清除」
});
const emit = defineEmits(['update:modelValue', 'change']);

const MONTHS = ['1月', '2月', '3月', '4月', '5月', '6月', '7月', '8月', '9月', '10月', '11月', '12月']; // prettier-ignore
const POP_W = 240; // 弹层宽度 w-60 = 15rem

const now = new Date();
const curYear = now.getFullYear();
const curMonth = now.getMonth() + 1;

const open = ref(false);
const triggerEl = ref(null);
const popoverEl = ref(null);
const popStyle = ref({});
const teleportTarget = ref('body');

onClickOutside(triggerEl, () => { open.value = false; }, { ignore: [popoverEl] }); // prettier-ignore
// 滚动/缩放时关闭，避免 fixed 弹层与触发器错位。
useEventListener('scroll', () => { if (open.value) open.value = false; }, { capture: true, passive: true }); // prettier-ignore
useEventListener('resize', () => {
  if (open.value) open.value = false;
});

// 解析当前值
const selectedYear = computed(() => {
  const [y] = (props.modelValue || '').split('-');
  return y ? Number(y) : null;
});
const selectedMonth = computed(() => {
  const [, m] = (props.modelValue || '').split('-');
  return m ? Number(m) : null;
});

// 弹层里正在浏览的年份（打开时定位到已选年或今年）
const viewYear = ref(selectedYear.value || curYear);

const label = computed(() => {
  if (!selectedYear.value || !selectedMonth.value) return props.placeholder;
  return `${selectedYear.value}年${selectedMonth.value}月`;
});
const hasValue = computed(() => !!selectedYear.value && !!selectedMonth.value);

// 按触发器位置算弹层坐标：优先向下，空间不足则向上；左右按 align 且钳制在视口内。
const positionPopover = () => {
  const el = triggerEl.value;
  if (!el) return;
  const r = el.getBoundingClientRect();
  const popH = popoverEl.value?.offsetHeight || 320;
  const below = r.bottom + 8;
  const top =
    below + popH > window.innerHeight && r.top - popH - 8 > 0
      ? r.top - popH - 8
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
  viewYear.value = selectedYear.value || curYear;
  // 在 <dialog>.showModal() 里要挂进 dialog 本身，teleport 到 body 会被顶层遮住
  teleportTarget.value = triggerEl.value?.closest('dialog') || 'body';
  open.value = true;
  await nextTick();
  positionPopover();
};

const commit = value => {
  emit('update:modelValue', value);
  emit('change', value);
};

const pick = month => {
  commit(`${viewYear.value}-${String(month).padStart(2, '0')}`);
  open.value = false;
};

const clear = () => {
  commit('');
  open.value = false;
};

const thisMonth = () => {
  viewYear.value = curYear;
  commit(`${curYear}-${String(curMonth).padStart(2, '0')}`);
  open.value = false;
};

const isSelected = month =>
  selectedYear.value === viewYear.value && selectedMonth.value === month;
const isCurrent = month => viewYear.value === curYear && curMonth === month;
</script>

<template>
  <div :class="block ? 'w-full' : 'shrink-0'">
    <!-- 触发器：样式对齐旁边的输入框/下拉 -->
    <button
      ref="triggerEl"
      type="button"
      :class="block ? 'w-full h-10' : triggerClass"
      class="flex items-center justify-between gap-2 pl-3 pr-2.5 text-sm text-left rounded-lg outline outline-1 outline-n-weak bg-n-solid-1 hover:outline-n-brand focus:outline-n-brand"
      @click="toggle"
    >
      <span :class="hasValue ? 'text-n-slate-12' : 'text-n-slate-9'">
        {{ label }}
      </span>
      <span class="text-n-slate-10 i-lucide-calendar size-4 shrink-0" />
    </button>

    <!-- 紫色玻璃弹层：Teleport 出去 + fixed 定位，不被容器裁切 -->
    <teleport :to="teleportTarget">
      <transition
        enter-active-class="transition duration-150 ease-out"
        enter-from-class="opacity-0 scale-95 -translate-y-1"
        enter-to-class="opacity-100 scale-100 translate-y-0"
        leave-active-class="transition duration-100 ease-in"
        leave-from-class="opacity-100 scale-100"
        leave-to-class="opacity-0 scale-95"
      >
        <!-- data-glass-popover：对话框 onClickOutside 按此忽略本弹层。靠 @vueuse ignore 判定，
             不能再 @pointerdown.stop（stop 会把 ignore 判定也挡掉，反而关掉对话框）。 -->
        <div
          v-if="open"
          ref="popoverEl"
          data-glass-popover
          :style="popStyle"
          class="z-[9999] p-3 origin-top border shadow-xl w-60 rounded-2xl border-white/50 bg-n-solid-1/70 backdrop-blur-2xl backdrop-saturate-150 shadow-n-iris-9/15"
        >
          <!-- 年份切换 -->
          <div class="flex items-center justify-between px-1 mb-2">
            <button
              type="button"
              class="flex items-center justify-center rounded-lg size-7 text-n-slate-11 hover:bg-n-alpha-2"
              @click="viewYear -= 1"
            >
              <span class="i-lucide-chevron-left size-4" />
            </button>
            <span class="text-sm font-semibold text-n-slate-12 tabular-nums">
              {{ viewYear }}年
            </span>
            <button
              type="button"
              class="flex items-center justify-center rounded-lg size-7 text-n-slate-11 hover:bg-n-alpha-2"
              @click="viewYear += 1"
            >
              <span class="i-lucide-chevron-right size-4" />
            </button>
          </div>

          <!-- 12 个月网格 -->
          <div class="grid grid-cols-3 gap-1.5">
            <button
              v-for="(m, i) in MONTHS"
              :key="m"
              type="button"
              class="h-9 text-sm rounded-lg transition-colors tabular-nums"
              :class="
                isSelected(i + 1)
                  ? 'bg-n-iris-9 text-white font-medium shadow-sm shadow-n-iris-9/30'
                  : isCurrent(i + 1)
                    ? 'text-n-iris-11 bg-n-iris-3 hover:bg-n-iris-4'
                    : 'text-n-slate-12 hover:bg-n-alpha-2'
              "
              @click="pick(i + 1)"
            >
              {{ m }}
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
              @click="thisMonth"
            >
              本月
            </button>
          </div>
        </div>
      </transition>
    </teleport>
  </div>
</template>
