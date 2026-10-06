<script setup>
import { computed } from 'vue';

// 经典灰主题下看板顶部的 KPI 卡。
//
// 和紫玻璃那版渐变卡的区别不只是配色：这版把「这个数字是好是坏」也放进卡里——
// 大数下面挂环比，右边挂一条走势。原来四张卡各自只有一个光秃秃的数字，
// 看的人没有参照系，只能自己翻上个月。
//
// 配色一律走 n-* token（经典灰/暗色各自的值由 theme class 覆盖），不写死任何色值；
// 字体跟随全局 font-sans，不引第三方字族。
const props = defineProps({
  label: { type: String, required: true },
  value: { type: [String, Number], required: true },
  unit: { type: String, default: '' },
  icon: { type: String, default: '' },
  // { text: '+2.1%', dir: 'up' | 'down' | 'flat', vs: '较上月 ¥3,274,374' }
  delta: { type: Object, default: null },
  // 右侧那块按指标性质换形式，没有可画的就传 null：
  //   { type: 'line' | 'bars', series: number[] }  连续金额用折线，离散个数用微型柱
  //   { type: 'arc', percent: 55 }                 完成率这种「离目标还有多远」用半圆
  //   { type: 'split', rows: [{ label, value, tone }] }  构成用分档
  viz: { type: Object, default: null },
});

const DELTA_CLASS = {
  up: 'text-n-teal-11',
  down: 'text-n-ruby-11',
  flat: 'text-n-slate-10',
};
const deltaClass = computed(
  () => DELTA_CLASS[props.delta?.dir] || DELTA_CLASS.flat
);

// ── 右侧走势 ──
// 画布 78×34，上下各留 2px 让线和端点不被裁掉。
const W = 62;
const H = 34;
const PAD = 2;

const series = computed(() =>
  (props.viz?.series || []).map(v => Number(v) || 0)
);

// 只有一个点画不出折线；全等高时让线走中间，不要除零。
const points = computed(() => {
  const s = series.value;
  if (s.length < 2) return [];
  const max = Math.max(...s);
  const min = Math.min(...s);
  const span = max - min;
  const step = (W - PAD * 2) / (s.length - 1);
  return s.map((v, i) => ({
    x: PAD + i * step,
    y: span === 0 ? H / 2 : H - PAD - ((v - min) / span) * (H - PAD * 2),
  }));
});

const linePath = computed(() =>
  points.value
    .map((p, i) => `${i ? 'L' : 'M'}${p.x.toFixed(1)},${p.y.toFixed(1)}`)
    .join(' ')
);
const areaPath = computed(() => {
  const pts = points.value;
  if (!pts.length) return '';
  return `${linePath.value} L${pts[pts.length - 1].x.toFixed(1)},${H} L${pts[0].x.toFixed(1)},${H} Z`;
});
const lastPoint = computed(() => points.value[points.value.length - 1] || null);

// 半圆仪表：r=26 的上半弧，弧长 πr≈81.68，按百分比截一段。
const ARC_R = 26;
const ARC_LEN = Math.PI * ARC_R;
const ARC_PATH = `M4,32 A${ARC_R},${ARC_R} 0 0 1 56,32`;
const arcDash = computed(() => {
  const pct = Math.min(100, Math.max(0, Number(props.viz?.percent) || 0));
  return `${((pct / 100) * ARC_LEN).toFixed(2)} ${ARC_LEN.toFixed(2)}`;
});

// 分档的色点：语义色（达标/进行中/落后），和涨跌用的是同一组 token
const TONE_CLASS = {
  good: 'bg-n-teal-9',
  warn: 'bg-n-amber-9',
  crit: 'bg-n-ruby-9',
  ink: 'bg-n-slate-11',
  mute: 'bg-n-slate-9',
};
const toneClass = tone => TONE_CLASS[tone] || TONE_CLASS.ink;

// 微型柱：笔数这类小整数本来就是离散的，用柱子比折线诚实。
// 最小留 2px，否则 0 值那几根整个消失，看不出「这几个月都是 0」。
const bars = computed(() => {
  const s = series.value;
  if (!s.length) return [];
  const max = Math.max(...s, 1);
  return s.map((v, i) => ({
    h: Math.max(2, Math.round((v / max) * H)),
    last: i === s.length - 1,
  }));
});
</script>

<template>
  <div
    class="flex flex-col p-4 sm:p-5 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1"
  >
    <div class="flex items-center gap-2.5 pb-3 sm:pb-3.5">
      <span
        v-if="icon"
        class="flex items-center justify-center border rounded-lg size-8 sm:size-9 shrink-0 border-n-weak bg-n-alpha-1 text-n-slate-12"
      >
        <span class="size-4 sm:size-5" :class="icon" />
      </span>
      <h3 class="truncate text-heading-3 text-n-slate-12">
        {{ label }}
      </h3>
    </div>

    <div
      class="flex items-end justify-between gap-3 pt-3 sm:pt-3.5 border-t border-dashed border-n-weak"
    >
      <div class="min-w-0">
        <div
          class="text-xl font-bold truncate sm:text-2xl tabular-nums text-n-slate-12"
        >
          {{ value }}
          <span v-if="unit" class="text-label-small text-n-slate-10">
            {{ unit }}
          </span>
        </div>
        <div
          v-if="delta"
          class="flex items-center gap-1.5 mt-1.5 min-w-0 text-label-small"
        >
          <span class="font-semibold shrink-0 tabular-nums" :class="deltaClass">
            {{ delta.text }}
          </span>
          <span v-if="delta.vs" class="truncate text-n-slate-10">
            {{ delta.vs }}
          </span>
        </div>
      </div>

      <!-- 卡在手机上只有半屏宽，走势图让位给数字 -->
      <svg
        v-if="viz?.type === 'line' && points.length"
        class="hidden sm:block shrink-0 text-n-amber-9"
        :width="W"
        :height="H"
        :viewBox="`0 0 ${W} ${H}`"
        aria-hidden="true"
      >
        <path :d="areaPath" fill="currentColor" opacity=".16" />
        <path
          :d="linePath"
          fill="none"
          stroke="currentColor"
          stroke-width="1.8"
          stroke-linejoin="round"
          stroke-linecap="round"
        />
        <circle
          v-if="lastPoint"
          :cx="lastPoint.x"
          :cy="lastPoint.y"
          r="2.8"
          fill="currentColor"
        />
      </svg>

      <div
        v-else-if="viz?.type === 'bars' && bars.length"
        class="items-end hidden gap-[3px] sm:flex shrink-0 h-[34px]"
        aria-hidden="true"
      >
        <i
          v-for="(b, i) in bars"
          :key="i"
          class="block w-1 rounded-t-sm"
          :class="b.last ? 'bg-n-amber-9' : 'bg-n-amber-9/40'"
          :style="{ height: `${b.h}px` }"
        />
      </div>

      <svg
        v-else-if="viz?.type === 'arc'"
        class="hidden sm:block shrink-0"
        width="60"
        height="36"
        viewBox="0 0 60 36"
        aria-hidden="true"
      >
        <path
          :d="ARC_PATH"
          fill="none"
          stroke-width="7"
          stroke-linecap="round"
          class="stroke-n-slate-4"
        />
        <path
          :d="ARC_PATH"
          fill="none"
          stroke-width="7"
          stroke-linecap="round"
          :stroke-dasharray="arcDash"
          class="stroke-n-amber-9"
        />
      </svg>

      <div
        v-else-if="viz?.type === 'split'"
        class="flex-col hidden gap-1.5 sm:flex shrink-0 min-w-[6.5rem]"
      >
        <div
          v-for="row in viz.rows"
          :key="row.label"
          class="flex items-center gap-2 text-label-small text-n-slate-11"
        >
          <span
            class="rounded-sm size-1.5 shrink-0"
            :class="toneClass(row.tone)"
          />
          <span class="truncate">{{ row.label }}</span>
          <span class="ml-auto font-semibold tabular-nums text-n-slate-12">
            {{ row.value }}
          </span>
        </div>
      </div>
    </div>
  </div>
</template>
