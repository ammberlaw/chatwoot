<script setup>
import { computed } from 'vue';
import { Doughnut } from 'vue-chartjs';
import { Chart as ChartJS, Tooltip, ArcElement } from 'chart.js';
import { chartPalette, FONT_FAMILY } from './chartColors';
import { useThemeSignal } from './useThemeSignal';

const props = defineProps({
  labels: { type: Array, default: () => [] },
  data: { type: Array, default: () => [] },
  colors: { type: Array, default: () => [] },
  // gauge: 底部半圆仪表（首段为进度、末段为轨道）；否则普通环形。
  gauge: { type: Boolean, default: false },
  cutout: { type: String, default: '72%' },
  continuous: { type: Boolean, default: false },
  valueFormat: { type: Function, default: v => v },
});

// 切主题时触发 computed 重算 → 图表重绘（详见 useThemeSignal）。
const themeSignal = useThemeSignal();

ChartJS.register(Tooltip, ArcElement);

const collection = computed(() => {
  void themeSignal.value;
  const c = chartPalette();
  const segmentRadius = props.continuous ? 0 : 4;
  const fallback = [c.brand, c.amber, c.iris, c.blue, c.ruby];
  const bg = props.gauge
    ? [props.colors[0] || c.brand, c.track]
    : props.data.map(
        (_, i) => props.colors[i] || fallback[i % fallback.length]
      );
  return {
    labels: props.labels,
    datasets: [
      {
        data: props.data,
        backgroundColor: bg,
        borderWidth: 0,
        // 仪表：只有进度那段两头是圆的，轨道段在交界处必须切平。
        // 两段都给圆角的话，后画的轨道会把进度末端的圆帽咬掉一块，看着像被截断。
        borderRadius: props.gauge
          ? [8, { outerStart: 0, innerStart: 0, outerEnd: 8, innerEnd: 8 }]
          : segmentRadius,
        spacing: props.gauge || props.continuous ? 0 : 2,
      },
    ],
  };
});

const options = computed(() => {
  void themeSignal.value;
  const c = chartPalette();
  return {
    responsive: true,
    maintainAspectRatio: false,
    cutout: props.cutout,
    rotation: props.gauge ? -90 : 0,
    circumference: props.gauge ? 180 : 360,
    plugins: {
      legend: { display: false },
      tooltip: {
        enabled: !props.gauge,
        backgroundColor: c.ink,
        padding: 10,
        cornerRadius: 8,
        bodyFont: { family: FONT_FAMILY },
        callbacks: {
          label: ctx => ` ${ctx.label}: ${props.valueFormat(ctx.raw)}`,
        },
      },
    },
  };
});
</script>

<template>
  <div class="relative w-full h-full">
    <Doughnut :data="collection" :options="options" />
    <div
      class="absolute inset-0 flex flex-col items-center justify-center pointer-events-none"
      :class="gauge ? 'pb-1 justify-end' : ''"
    >
      <slot name="center" />
    </div>
  </div>
</template>
