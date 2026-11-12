<script setup>
import { computed } from 'vue';

// 业务员发信排行（竖条黄黑：榜首品牌黄 + 数值浮标，其余石墨色）。
// 原先只长在 CRM 数据看板里，团队看板要同一张图，所以抽出来共用——
// 两边口径不同由调用方决定：数据看板按所选期间汇总，团队看板是**全公司当月**。
const props = defineProps({
  // [{ name, count }]，已按从多到少排好
  rows: { type: Array, default: () => [] },
  periodLabel: { type: String, default: '' },
  title: { type: String, default: '业务员发信排行' },
  emptyText: { type: String, default: '这段时间还没有发出去的邮件' },
});

const TOP_COLOR = '#ffc53d';
const REST_COLOR = '#2a2e37';

const visibleRows = computed(() => props.rows);
const isEmpty = computed(() => !visibleRows.value.length);
const maxValue = computed(() =>
  Math.max(...visibleRows.value.map(r => Number(r.count) || 0), 1)
);
// 左侧刻度：最高 / 一半 / 0，自上而下。
const ticks = computed(() => [
  maxValue.value,
  Math.round(maxValue.value / 2),
  0,
]);
const bars = computed(() =>
  visibleRows.value.map((row, i) => ({
    name: row.name,
    value: Number(row.count) || 0,
    // 留 6% 底座，免得只发一两封的人细成一条线看不见
    pct:
      Number(row.count) > 0
        ? Math.max(
            6,
            Math.round(((Number(row.count) || 0) / maxValue.value) * 100)
          )
        : 0,
    top: i === 0,
  }))
);
</script>

<template>
  <div
    class="p-5 border shadow-sm min-w-0 rounded-2xl border-white/60 bg-n-solid-1/45 backdrop-blur-2xl backdrop-saturate-150"
  >
    <div class="flex items-center justify-between gap-3 mb-5">
      <h2 class="text-base font-medium text-n-slate-12">{{ title }}</h2>
      <span v-if="periodLabel" class="text-xs text-n-slate-10">
        {{ periodLabel }}
      </span>
    </div>
    <div
      v-if="isEmpty"
      class="flex items-center justify-center h-56 text-sm text-n-slate-10"
    >
      {{ emptyText }}
    </div>
    <div v-else class="min-w-0 overflow-x-auto">
      <div class="flex gap-3 w-max min-w-full">
        <!-- 左侧刻度：最高 / 一半 / 0，贴着绘图区上中下三档 -->
        <div
          class="flex flex-col justify-between w-8 h-44 pt-7 shrink-0 text-[10px] text-n-slate-10 tabular-nums text-right"
        >
          <span v-for="tick in ticks" :key="tick">{{ tick }}</span>
        </div>
        <div>
          <div class="flex items-end h-44 gap-1 pt-7">
            <div
              v-for="bar in bars"
              :key="bar.name"
              class="relative flex justify-center w-7 h-full shrink-0"
              :title="`${bar.name}：${bar.value} 封`"
            >
              <!-- 数值贴在条子顶上，不占条子的高度：榜首是白色浮标，其余只写数字 -->
              <span
                v-if="bar.top"
                class="absolute z-10 -translate-x-1/2 left-1/2 px-2 py-0.5 bg-n-solid-1 text-n-slate-12 shadow-md whitespace-nowrap text-label-small rounded-full"
                :style="{ bottom: `calc(${bar.pct}% + 6px)` }"
              >
                {{ bar.value }} 封
              </span>
              <span
                v-else
                class="absolute z-10 -translate-x-1/2 left-1/2 text-[10px] font-medium text-n-slate-11 tabular-nums whitespace-nowrap"
                :style="{ bottom: `calc(${bar.pct}% + 4px)` }"
              >
                {{ bar.value }}
              </span>
              <div
                class="self-end w-full transition-all rounded-full"
                :style="{
                  height: `${bar.pct}%`,
                  backgroundColor: bar.top ? TOP_COLOR : REST_COLOR,
                }"
              />
            </div>
          </div>
          <!-- 名字斜 45° 写在条子下：只放首字母缩写看不出是谁，斜排后全名放得下且不占宽。 -->
          <div class="flex gap-1 mt-2 h-[72px]">
            <div
              v-for="bar in bars"
              :key="`l-${bar.name}`"
              class="relative w-7 shrink-0"
            >
              <span
                class="absolute top-0 right-1/2 origin-top-right -rotate-45 max-w-24 truncate text-[10px] leading-none text-n-slate-10 whitespace-nowrap"
                :title="`${bar.name}：${bar.value} 封`"
              >
                {{ bar.name }}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
