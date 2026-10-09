<script setup>
import { ref, computed, nextTick } from 'vue';
import { onClickOutside, useEventListener } from '@vueuse/core';

// 紫色玻璃下拉「小卡片」，替换原生 <select>（系统蓝列表丑、没法染色）。
// 与 MonthPicker 同款外壳：弹层 Teleport 到 body + fixed 定位，滚动/缩放即关，
// 在对话框 / overflow 滚动容器里也不会被裁切。API 与 components-next/select/Select.vue 兼容。
const props = defineProps({
  // [{ value, label, disabled?, note? }]  note = 右侧灰字补充说明
  options: {
    type: Array,
    default: () => [],
    validator: opts =>
      opts.every(o => typeof o === 'object' && 'value' in o && 'label' in o),
  },
  placeholder: { type: String, default: '请选择' },
  disabled: { type: Boolean, default: false },
  align: { type: String, default: 'left' }, // 'left' | 'right'：弹层对齐边
  triggerClass: { type: String, default: '' }, // 触发器额外类（宽度/高度）
  block: { type: Boolean, default: false }, // true=触发器占满父容器宽（表单用）；默认内容宽（筛选用）
  // 选项一多就得滚半天找——超过 SEARCH_MIN 项自动长出搜索框。
  // 'auto'（默认）按条数决定；传 searchable / :searchable="false" 可强制开或关。
  searchable: { type: [Boolean, String], default: 'auto' },
  searchPlaceholder: { type: String, default: '搜索…' },
});

// 多少项起自动给搜索框：一屏（max-h-72）大约放得下 8 项，再多就得滚。
const SEARCH_MIN = 8;
// 一次最多渲染多少项：客户档案这种有几千条，全渲染出来开下拉要卡一下。
// 超出的用搜索找，列表底部写明还剩多少。
const MAX_RENDER = 200;

const modelValue = defineModel({
  type: [String, Number, Boolean],
  default: '',
});

const open = ref(false);
const triggerEl = ref(null);
const popoverEl = ref(null);
const searchEl = ref(null);
const query = ref('');
// 初值就带上 position:fixed——弹层**第一帧**要是还按普通块插进去，对话框会被它撑高、
// 居中弹窗跟着上移，而定位恰好在这一帧之后量触发器，量到的是位移后的坐标；
// 随后弹层脱离文档流、对话框落回原位，弹层就整个偏上去盖住了触发框。
// 先挪到屏幕外，等 positionPopover 算完再落位。
const OFFSCREEN = { position: 'fixed', top: '-10000px', left: '0px' };
const popStyle = ref({ ...OFFSCREEN });
// 若在原生 <dialog>（showModal 顶层）内，弹层要 Teleport 进该 dialog 才不被顶层遮住；否则回退 body。
const teleportTarget = ref('body');

onClickOutside(triggerEl, () => { open.value = false; }, { ignore: [popoverEl] }); // prettier-ignore
// 外部滚动即关（fixed 弹层会与触发器错位）；但弹层自身长列表的内部滚动要放行，否则下滑选项就被误关。
useEventListener(
  'scroll',
  e => {
    if (!open.value) return;
    if (popoverEl.value?.contains(e.target)) return;
    open.value = false;
  },
  { capture: true, passive: true }
);
useEventListener('resize', () => {
  if (open.value) open.value = false;
});

const showSearch = computed(() =>
  props.searchable === 'auto'
    ? props.options.length >= SEARCH_MIN
    : Boolean(props.searchable)
);

// 过滤只看 label 和可选的 searchText（调用方可以把编号、客户名之类也塞进来一起搜）。
const matchedOptions = computed(() => {
  const q = query.value.trim().toLowerCase();
  if (!q) return props.options;
  return props.options.filter(o =>
    `${o.label} ${o.searchText || ''}`.toLowerCase().includes(q)
  );
});
const visibleOptions = computed(() =>
  matchedOptions.value.slice(0, MAX_RENDER)
);
const hiddenCount = computed(() =>
  Math.max(0, matchedOptions.value.length - visibleOptions.value.length)
);

const selectedLabel = computed(() => {
  const hit = props.options.find(o => o.value === modelValue.value);
  return hit ? hit.label : props.placeholder;
});
const isPlaceholder = computed(
  () => !props.options.some(o => o.value === modelValue.value)
);

// 按触发器位置算弹层坐标：优先向下、空间不足向上；左右按 align 且钳在视口内。
//
// 宽度不再写死成触发器宽度——窄触发器会把选项截成「MO-20261001-0…」，
// 一串单号长得一模一样，根本分不出是哪张。改成：下限=触发器宽，上限=560/视口，
// 中间由内容撑开；渲染后按实际宽度再钳一次 left，免得撑宽后溢出屏幕右侧。
const MAX_POPOVER_HEIGHT = 288; // = max-h-72，与 class 上的上限一致
const GAP = 6;

// 纵向**不量弹层高度**：往下开就钉 top，往上开就钉 bottom，再把 maxHeight 压到那一侧的可用高度。
// 原来是「top = 触发器顶 − 量到的高度」，量不准（ref 还没挂上时回落到一个猜的值）就会算低，
// 弹层直接盖住触发框——矮屏幕上必现。钉 bottom 之后高度算错也不可能压到触发器上。
const positionPopover = async () => {
  const el = triggerEl.value;
  if (!el) return;
  const r = el.getBoundingClientRect();
  const minWidth = Math.max(r.width, 160);
  const maxWidth = Math.min(560, window.innerWidth - 16);
  const spaceBelow = window.innerHeight - r.bottom - GAP - 8;
  const spaceAbove = r.top - GAP - 8;
  // 下方塞不下、且上方更宽裕才往上翻
  const flipUp = spaceBelow < MAX_POPOVER_HEIGHT && spaceAbove > spaceBelow;
  const vertical = flipUp
    ? { bottom: `${window.innerHeight - r.top + GAP}px` }
    : { top: `${r.bottom + GAP}px` };

  popStyle.value = {
    position: 'fixed',
    ...vertical,
    left: `${r.left}px`,
    minWidth: `${minWidth}px`,
    maxWidth: `${maxWidth}px`,
    maxHeight: `${Math.max(120, Math.min(MAX_POPOVER_HEIGHT, flipUp ? spaceAbove : spaceBelow))}px`,
  };

  // 宽度要等渲染完才知道（选项长短不一），只为把 left 钳回屏幕内。
  await nextTick();
  const popW = popoverEl.value?.offsetWidth || minWidth;
  let left = props.align === 'right' ? r.right - popW : r.left;
  left = Math.max(8, Math.min(left, window.innerWidth - popW - 8));
  popStyle.value = { ...popStyle.value, left: `${left}px` };
};

const closePopover = () => {
  open.value = false;
  popStyle.value = { ...OFFSCREEN };
};

const pick = opt => {
  if (opt.disabled) return;
  modelValue.value = opt.value;
  closePopover();
};

// Esc 在下拉开着时**只收下拉**。不拦住的话事件会一路冒到原生 <dialog>，
// 本来只想取消一下选择，整张表单跟着被关掉（对话框里的下拉必现）。
// 下拉没开时不拦，Esc 照旧关对话框。
const onEscape = e => {
  if (!open.value) return;
  e.preventDefault();
  e.stopPropagation();
  closePopover();
  triggerEl.value?.focus();
};

const toggle = async () => {
  if (props.disabled) return;
  if (open.value) {
    open.value = false;
    return;
  }
  teleportTarget.value = triggerEl.value?.closest('dialog') || 'body';
  query.value = '';
  open.value = true;
  await nextTick();
  positionPopover();
  searchEl.value?.focus();
};

// 搜索框里按键：Esc 关掉，回车直接选中当前第一条（搜完不用再挪鼠标）。
const onSearchKeydown = e => {
  if (e.key === 'Escape') {
    onEscape(e);
    return;
  }
  if (e.key !== 'Enter') return;
  e.preventDefault();
  const first = visibleOptions.value.find(o => !o.disabled);
  if (first) pick(first);
};
</script>

<template>
  <div :class="block ? 'w-full' : 'shrink-0'">
    <!-- 触发器：白色小卡片，样式对齐旁边的输入框。
         button 恒 w-full：外层 div 的宽度由调用方的 class 决定（w-44 这种），
         button 以前只按文字撑宽，调用方给了 44 它只占 28，右边空出一截，
         看着像「下拉和旁边的搜索框之间有个大空隙」（产品档案页最明显）。
         没给宽度时外层是 shrink-to-fit，w-full 解析回内容宽，行为不变。 -->
    <button
      ref="triggerEl"
      type="button"
      :disabled="disabled"
      :class="[triggerClass]"
      class="inline-flex items-center justify-between h-9 gap-2 pl-3 text-sm text-left transition-all rounded-lg pr-2.5 outline outline-1 outline-n-weak bg-n-solid-1 hover:outline-n-brand disabled:opacity-60 disabled:cursor-not-allowed w-full"
      @click="toggle"
      @keydown.esc="onEscape"
    >
      <span
        class="truncate min-w-0"
        :class="isPlaceholder ? 'text-n-slate-9' : 'text-n-slate-12'"
      >
        {{ selectedLabel }}
      </span>
      <span
        class="transition-transform i-lucide-chevron-down size-4 text-n-slate-10 shrink-0"
        :class="open ? 'rotate-180' : ''"
      />
    </button>

    <!-- 紫色玻璃弹层：Teleport 到最近 dialog（顶层）或 body，fixed 定位不被容器裁切 -->
    <teleport :to="teleportTarget">
      <transition
        enter-active-class="transition duration-150 ease-out"
        enter-from-class="opacity-0 scale-95 -translate-y-1"
        enter-to-class="opacity-100 scale-100 translate-y-0"
        leave-active-class="transition duration-100 ease-in"
        leave-from-class="opacity-100 scale-100"
        leave-to-class="opacity-0 scale-95"
      >
        <!-- data-glass-popover：对话框 onClickOutside 按此忽略本弹层（点选项不关整个对话框）。
             靠 @vueuse ignore 判定，不能再 @pointerdown.stop（stop 会把 ignore 判定也挡掉）。 -->
        <div
          v-if="open"
          ref="popoverEl"
          data-glass-popover
          :style="popStyle"
          class="z-[9999] p-1.5 origin-top overflow-y-auto border shadow-xl max-h-72 rounded-2xl border-white/50 bg-n-solid-1/70 backdrop-blur-2xl backdrop-saturate-150 shadow-n-iris-9/15"
        >
          <!-- 搜索框钉在弹层顶部：列表滚起来也还在。 -->
          <div
            v-if="showSearch"
            class="sticky top-0 z-10 px-1 pt-0.5 pb-1.5 -mx-0.5 bg-n-solid-1/80 backdrop-blur-sm"
          >
            <input
              ref="searchEl"
              v-model="query"
              type="text"
              :placeholder="searchPlaceholder"
              class="w-full h-8 px-2.5 text-sm rounded-lg reset-base outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-9 focus:outline-n-brand"
              @keydown="onSearchKeydown"
            />
          </div>
          <button
            v-for="opt in visibleOptions"
            :key="String(opt.value)"
            type="button"
            :disabled="opt.disabled"
            class="flex items-center justify-between w-full gap-2 px-3 text-sm text-left transition-colors rounded-lg h-9 disabled:opacity-40"
            :class="
              opt.value === modelValue
                ? 'bg-n-iris-9 text-white font-medium shadow-sm shadow-n-iris-9/30'
                : 'text-n-slate-12 hover:bg-n-iris-3'
            "
            @click="pick(opt)"
          >
            <span class="whitespace-nowrap">{{ opt.label }}</span>
            <span class="flex items-center gap-2 shrink-0">
              <!-- note：选项的补充说明（如「已下 2 张采购单 · 还差 3 项料」），可选 -->
              <span
                v-if="opt.note"
                class="text-xs whitespace-nowrap"
                :class="
                  opt.value === modelValue ? 'text-white/80' : 'text-n-slate-10'
                "
              >
                {{ opt.note }}
              </span>
              <span
                v-if="opt.value === modelValue"
                class="i-lucide-check size-4"
              />
            </span>
          </button>
          <p
            v-if="!matchedOptions.length"
            class="px-3 py-4 text-sm text-center text-n-slate-10"
          >
            没有匹配的选项
          </p>
          <p
            v-else-if="hiddenCount"
            class="px-3 py-2 text-xs text-center text-n-slate-10"
          >
            还有 {{ hiddenCount }} 项，继续输入缩小范围
          </p>
        </div>
      </transition>
    </teleport>
  </div>
</template>
