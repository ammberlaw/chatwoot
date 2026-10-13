<script setup>
import { ref, computed, nextTick, onBeforeUnmount } from 'vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';

// 表头上的列筛选漏斗（对标金蝶：每个竖行自己能过滤）。
// 三种列：text 关键字 / select 枚举 / date 日期区间（带今天·本周·本月这些快捷段）。
//
// ⚠️ 筛选条件交给调用方发给后端，不在前端过滤本页数据——列表是分页的，
// 本页过滤只会在第 1 页里挑，第 2 页往后的命中全看不见。
const props = defineProps({
  // 'text' | 'select' | 'date'
  type: { type: String, default: 'text' },
  // select 用：[{ value, label }]
  options: { type: Array, default: () => [] },
  // text/select 是字符串；date 是 { from, to }
  modelValue: { type: [String, Object], default: '' },
  placeholder: { type: String, default: '输入关键字' },
});
const emit = defineEmits(['update:modelValue', 'change']);

const open = ref(false);
const panel = ref(null);
const inputEl = ref(null);
const trigger = ref(null);
const pos = ref({ top: 0, left: 0 });

const isDate = computed(() => props.type === 'date');
const active = computed(() => {
  if (isDate.value)
    return Boolean(props.modelValue?.from || props.modelValue?.to);
  return Boolean(props.modelValue);
});

const draft = ref('');
const draftRange = ref({ from: '', to: '' });

// 面板 fixed 定位挂 body：表头所在的滚动容器有 overflow，挂在里面会被裁掉。
const place = () => {
  const r = trigger.value?.getBoundingClientRect();
  if (!r) return;
  const width = isDate.value ? 260 : 220;
  pos.value = {
    top: r.bottom + 4,
    left: Math.min(r.left, window.innerWidth - width - 8),
  };
};

const toggle = async () => {
  if (open.value) {
    open.value = false;
    return;
  }
  draft.value = isDate.value ? '' : String(props.modelValue || '');
  draftRange.value = isDate.value
    ? { from: props.modelValue?.from || '', to: props.modelValue?.to || '' }
    : { from: '', to: '' };
  open.value = true;
  await nextTick();
  place();
  inputEl.value?.focus();
  window.addEventListener('scroll', place, true);
  window.addEventListener('resize', place);
};

const close = () => {
  open.value = false;
  window.removeEventListener('scroll', place, true);
  window.removeEventListener('resize', place);
};
onBeforeUnmount(close);

const commit = value => {
  emit('update:modelValue', value);
  emit('change', value);
  close();
};
const apply = () =>
  commit(isDate.value ? { ...draftRange.value } : draft.value.trim());
const reset = () => commit(isDate.value ? { from: '', to: '' } : '');

// 点开别处关闭：文本列把当前输入落实（没有「确定」按钮了），枚举/日期列直接关。
const dismiss = () => (props.type === 'text' ? apply() : close());

// 日期快捷段：和金蝶那张筛选面板一一对应。
const ymd = d => d.toLocaleDateString('sv');
const QUICK = [
  [
    '今天',
    () => {
      const t = new Date();
      return [ymd(t), ymd(t)];
    },
  ],
  [
    '本周',
    () => {
      const t = new Date();
      const s = new Date(t);
      // 周一为一周之始（国内习惯），getDay() 周日是 0。
      s.setDate(t.getDate() - ((t.getDay() + 6) % 7));
      return [ymd(s), ymd(t)];
    },
  ],
  [
    '本月',
    () => {
      const t = new Date();
      return [ymd(new Date(t.getFullYear(), t.getMonth(), 1)), ymd(t)];
    },
  ],
  [
    '上月',
    () => {
      const t = new Date();
      return [
        ymd(new Date(t.getFullYear(), t.getMonth() - 1, 1)),
        ymd(new Date(t.getFullYear(), t.getMonth(), 0)),
      ];
    },
  ],
  [
    '近三个月',
    () => {
      const t = new Date();
      return [
        ymd(new Date(t.getFullYear(), t.getMonth() - 3, t.getDate())),
        ymd(t),
      ];
    },
  ],
];
const pickQuick = fn => {
  const [from, to] = fn();
  commit({ from, to });
};
</script>

<template>
  <span class="relative inline-flex">
    <button
      ref="trigger"
      type="button"
      class="inline-flex items-center justify-center rounded reset-base size-5 hover:bg-n-alpha-2"
      :class="active ? 'text-n-iris-11' : 'text-n-slate-10'"
      :title="active ? '已筛选，点击修改' : '筛选本列'"
      @click.stop="toggle"
    >
      <span class="i-lucide-chevron-down size-4 shrink-0" />
    </button>

    <Teleport to="body">
      <div
        v-if="open"
        class="fixed inset-0 z-[9998]"
        @click="dismiss"
        @contextmenu.prevent="dismiss"
      />
      <div
        v-if="open"
        ref="panel"
        class="fixed z-[9999] p-1.5 origin-top overflow-y-auto border shadow-xl max-h-72 rounded-2xl border-white/50 bg-n-solid-1/70 backdrop-blur-2xl backdrop-saturate-150 shadow-n-iris-9/15"
        :style="{
          top: `${pos.top}px`,
          left: `${pos.left}px`,
          width: isDate ? '260px' : type === 'select' ? '220px' : '300px',
        }"
        @click.stop
      >
        <template v-if="type === 'select'">
          <div class="flex flex-col max-h-64 gap-0.5 overflow-y-auto">
            <button
              v-for="opt in options"
              :key="String(opt.value)"
              type="button"
              class="flex items-center w-full gap-2 px-3 text-sm text-left transition-colors rounded-lg reset-base h-9"
              :class="
                String(opt.value) === String(modelValue)
                  ? 'bg-n-iris-9 text-white font-medium shadow-sm shadow-n-iris-9/30'
                  : 'text-n-slate-12 hover:bg-n-iris-3'
              "
              @click="commit(String(opt.value))"
            >
              {{ opt.label }}
            </button>
          </div>
        </template>

        <template v-else-if="isDate">
          <div class="flex flex-col gap-0.5">
            <button
              v-for="[label, fn] in QUICK"
              :key="label"
              type="button"
              class="flex items-center w-full px-3 text-sm text-left transition-colors rounded-lg reset-base h-9 text-n-slate-12 hover:bg-n-iris-3"
              @click="pickQuick(fn)"
            >
              {{ label }}
            </button>
          </div>
          <div class="pt-2 mt-2 border-t border-n-weak">
            <div class="mb-1 text-xs text-n-slate-10">从…到…</div>
            <div class="flex flex-col gap-1">
              <DatePicker v-model="draftRange.from" trigger-class="w-full" />
              <DatePicker v-model="draftRange.to" trigger-class="w-full" />
            </div>
          </div>
        </template>

        <!-- 文本列：就一个搜索框。回车或点开别处即生效，清空再回车＝取消这一列的筛选。 -->
        <template v-else>
          <div class="p-1">
            <input
              ref="inputEl"
              v-model="draft"
              type="text"
              :placeholder="placeholder"
              class="w-full h-8 px-2 text-sm border rounded-lg outline-none reset-base border-n-weak bg-n-solid-1 text-n-slate-12"
              @keyup.enter="apply"
            />
          </div>
        </template>

        <!-- 日期列：区间要两头都填完才知道筛什么，留一个「确定」。
             枚举列点一下就生效，不需要底栏。 -->
        <div
          v-if="isDate"
          class="flex justify-end gap-2 pt-2 mt-2 border-t border-n-weak"
        >
          <button
            type="button"
            class="px-2 py-1 text-xs rounded-lg reset-base text-n-slate-11 hover:bg-n-iris-3"
            @click="reset"
          >
            重置
          </button>
          <button
            type="button"
            class="px-2.5 py-1 text-xs text-white rounded-lg reset-base bg-n-iris-9"
            @click="apply"
          >
            确定
          </button>
        </div>
      </div>
    </Teleport>
  </span>
</template>
