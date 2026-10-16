<script setup>
// 记账凭证的「分位金额格」——兆千百十亿千百十万千百十元角分，一位一格。
//
// 中国传统记账凭证的经典样式（金蝶/用友都这么摆），财务看惯了：扫一眼格子位置就知道
// 量级，不用去数逗号。
//
// 录入不在格子里敲——一格一格按数字键是没法用的，金蝶也不是这么做的：
// 点一下整块变成一个普通输入框，输完失焦再按位摆回去。
import { ref, computed, nextTick } from 'vue';

const props = defineProps({
  // 元为单位的字符串/数字（与 form.lines 里的 debit/credit 一致，不做单位转换）
  modelValue: { type: [String, Number], default: '' },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue', 'input']);

// 15 位：兆千百十 亿千百十 万千百十 元角分。万/元/角分的分界要加粗线，财务靠它定位。
const UNITS = [
  { label: '兆', group: 'zhao' },
  { label: '千', group: 'yi' },
  { label: '百', group: 'yi' },
  { label: '十', group: 'yi' },
  { label: '亿', group: 'yi' },
  { label: '千', group: 'wan' },
  { label: '百', group: 'wan' },
  { label: '十', group: 'wan' },
  { label: '万', group: 'wan' },
  { label: '千', group: 'yuan' },
  { label: '百', group: 'yuan' },
  { label: '十', group: 'yuan' },
  { label: '元', group: 'yuan' },
  { label: '角', group: 'jiao' },
  { label: '分', group: 'jiao' },
];

// 金额 → 15 个格子。空值全留白（不是摆一串 0，那样分不清「没填」和「零元」）。
const digits = computed(() => {
  const raw = String(props.modelValue ?? '').trim();
  if (!raw || Number.isNaN(Number(raw))) return Array(UNITS.length).fill('');
  // 四舍五入到分，再铺成「整数部分 + 角分」两位
  const cents = Math.round(Number(raw) * 100);
  const sign = cents < 0 ? '-' : '';
  const body = String(Math.abs(cents));
  const padded = body
    .padStart(UNITS.length, ' ')
    .slice(-UNITS.length)
    .split('');
  // 负数把减号摆在最高有效位前一格
  const firstIdx = padded.findIndex(c => c !== ' ');
  if (sign && firstIdx > 0) padded[firstIdx - 1] = '-';
  return padded.map(c => (c === ' ' ? '' : c));
});

const editing = ref(false);
const draft = ref('');
const inputRef = ref(null);
const startEdit = async () => {
  if (props.disabled) return;
  draft.value = String(props.modelValue ?? '');
  editing.value = true;
  await nextTick();
  inputRef.value?.focus();
  inputRef.value?.select();
};
const commit = () => {
  editing.value = false;
  // type=number 的 v-model 会把值转成数字，这里统一按字符串回传（跟原来 Input 的行为一致）
  const v = String(draft.value ?? '').trim();
  emit('update:modelValue', v);
  emit('input', v);
};
</script>

<template>
  <div class="relative h-8">
    <!-- 编辑态：就是个普通数字输入框，盖在格子上 -->
    <input
      v-if="editing"
      ref="inputRef"
      v-model="draft"
      type="number"
      step="0.01"
      class="absolute inset-0 w-full h-full px-2 text-sm text-right rounded reset-base outline outline-1 outline-n-brand bg-n-solid-1 text-n-slate-12"
      @blur="commit"
      @keydown.enter.prevent="commit"
      @keydown.esc.prevent="editing = false"
    />
    <!-- 展示态：一位一格 -->
    <button
      v-else
      type="button"
      :disabled="disabled"
      class="flex w-full h-full reset-base disabled:cursor-not-allowed"
      @click="startEdit"
    >
      <span
        v-for="(u, i) in UNITS"
        :key="i"
        class="flex items-center justify-center flex-1 min-w-0 text-xs tabular-nums border-r text-n-slate-12 last:border-r-0"
        :class="[
          u.group === 'jiao' ? 'bg-n-amber-2/40' : '',
          // 万 / 元 两道分界线加重，财务靠它一眼定位量级
          UNITS[i + 1] && UNITS[i + 1].group !== u.group
            ? 'border-n-slate-7'
            : 'border-n-weak',
        ]"
      >
        {{ digits[i] }}
      </span>
    </button>
  </div>
</template>
