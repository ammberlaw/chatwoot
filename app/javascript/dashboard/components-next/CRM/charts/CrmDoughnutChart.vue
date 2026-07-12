<script setup>
import { computed } from 'vue';
import { Doughnut } from 'vue-chartjs';
import { Chart as ChartJS, Tooltip, ArcElement } from 'chart.js';
import { chartPalette, FONT_FAMILY } from './chartColors';

const props = defineProps({
  labels: { type: Array, default: () => [] },
  data: { type: Array, required: true },
  colors: { type: Array, default: () => [] },
  // gauge: 底部半圆仪表（首段为进度、末段为轨道）；否则普通环形。
  gauge: { type: Boolean, default: false },
  cutout: { type: String, default: '72%' },
  valueFormat: { type: Function, default: v => v },
});

ChartJS.register(Tooltip, ArcElement);

const collection = computed(() => {
  const c = chartPalette();
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
        borderRadius: props.gauge ? 8 : 4,
        spacing: props.gauge ? 0 : 2,
      },
    ],
  };
});

const options = computed(() => {
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
