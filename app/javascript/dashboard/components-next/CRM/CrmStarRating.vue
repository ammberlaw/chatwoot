<script setup>
import { computed } from 'vue';
import {
  customerStarFromMicros,
  STAR_TIER_HINTS,
} from 'dashboard/routes/dashboard/crm/helper/customerStar';

const props = defineProps({
  // 累计成交额（micros，人民币）。星级由它自动算出。
  micros: { type: [Number, String], default: 0 },
  size: { type: String, default: 'sm' }, // sm | md
});

const star = computed(() => customerStarFromMicros(props.micros));
const starSize = computed(() => (props.size === 'md' ? 'size-5' : 'size-4'));

// 鼠标悬浮解释：标题 + 六档标准，当前档高亮。html 由 floating-vue 渲染，
// 用 Tailwind class（tooltip 挂在同一文档，工具类生效），不写内联样式。
const tooltip = computed(() => {
  const rows = STAR_TIER_HINTS.map(
    (hint, idx) =>
      `<div class="${idx === star.value ? 'text-n-amber-11 font-medium' : ''}">${hint}</div>`
  ).join('');
  return {
    content: `<div class="text-left leading-relaxed"><div class="font-semibold mb-1">客户星级 · 按累计成交额自动评定</div>${rows}</div>`,
    html: true,
  };
});
</script>

<template>
  <span
    v-tooltip.top="tooltip"
    class="inline-flex items-center gap-0.5 align-middle cursor-help"
  >
    <span
      v-for="i in 5"
      :key="i"
      class="i-ph-star-fill"
      :class="[starSize, i <= star ? 'text-n-amber-9' : 'text-n-slate-5']"
    />
  </span>
</template>
