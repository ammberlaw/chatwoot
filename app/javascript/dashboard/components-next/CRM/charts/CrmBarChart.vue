<script setup>
import { computed } from 'vue';
import { Bar } from 'vue-chartjs';
import {
  Chart as ChartJS,
  Tooltip,
  BarElement,
  CategoryScale,
  LinearScale,
} from 'chart.js';
import { chartPalette, FONT_FAMILY } from './chartColors';

const props = defineProps({
  labels: { type: Array, required: true },
  data: { type: Array, required: true },
  colors: { type: Array, default: () => [] },
  horizontal: { type: Boolean, default: false },
  showValues: { type: Boolean, default: false },
  valueFormat: { type: Function, default: v => v },
});

ChartJS.register(Tooltip, BarElement, CategoryScale, LinearScale);

// 在柱端绘制数值标签（无需外部插件）。
const valueLabelPlugin = {
  id: 'crmValueLabel',
  afterDatasetsDraw(chart) {
    if (!props.showValues) return;
    const { ctx } = chart;
    const meta = chart.getDatasetMeta(0);
    const c = chartPalette();
    ctx.save();
    ctx.font = `600 11px ${FONT_FAMILY}`;
    ctx.fillStyle = c.ink;
    meta.data.forEach((bar, i) => {
      const label = props.valueFormat(props.data[i]);
      if (props.horizontal) {
        ctx.textAlign = 'left';
        ctx.textBaseline = 'middle';
        ctx.fillText(label, bar.x + 6, bar.y);
      } else {
        ctx.textAlign = 'center';
        ctx.textBaseline = 'bottom';
        ctx.fillText(label, bar.x, bar.y - 6);
      }
    });
    ctx.restore();
  },
};

const collection = computed(() => {
  const c = chartPalette();
  const bg = props.data.map((_, i) => props.colors[i] || c.brand);
  return {
    labels: props.labels,
    datasets: [
      {
        data: props.data,
        backgroundColor: bg,
        borderRadius: 8,
        borderSkipped: false,
        maxBarThickness: props.horizontal ? 22 : 48,
      },
    ],
  };
});

const options = computed(() => {
  const c = chartPalette();
  const valueAxis = {
    border: { display: false },
    grid: { display: false },
    ticks: { display: false },
    grace: '18%',
  };
  const catAxis = {
    border: { display: false },
    grid: { display: false },
    ticks: { color: c.muted, font: { family: FONT_FAMILY, size: 11 } },
  };
  return {
    indexAxis: props.horizontal ? 'y' : 'x',
    responsive: true,
    maintainAspectRatio: false,
    layout: { padding: props.horizontal ? { right: 44 } : { top: 18 } },
    plugins: {
      legend: { display: false },
      tooltip: {
        backgroundColor: c.ink,
        padding: 10,
        cornerRadius: 8,
        displayColors: false,
        bodyFont: { family: FONT_FAMILY },
        callbacks: { label: ctx => props.valueFormat(ctx.raw) },
      },
    },
    scales: props.horizontal
      ? { x: valueAxis, y: catAxis }
      : { x: catAxis, y: valueAxis },
  };
});
</script>

<template>
  <Bar :data="collection" :options="options" :plugins="[valueLabelPlugin]" />
</template>
