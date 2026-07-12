<script setup>
import { computed } from 'vue';
import { Line } from 'vue-chartjs';
import {
  Chart as ChartJS,
  Tooltip,
  Filler,
  LineElement,
  PointElement,
  CategoryScale,
  LinearScale,
} from 'chart.js';
import { chartPalette, FONT_FAMILY } from './chartColors';

const props = defineProps({
  labels: { type: Array, required: true },
  data: { type: Array, required: true },
  activeIndex: { type: Number, default: -1 },
  valueFormat: { type: Function, default: v => v },
});

ChartJS.register(
  Tooltip,
  Filler,
  LineElement,
  PointElement,
  CategoryScale,
  LinearScale
);

const collection = computed(() => {
  const c = chartPalette();
  return {
    labels: props.labels,
    datasets: [
      {
        data: props.data,
        borderColor: c.brand,
        borderWidth: 2.5,
        tension: 0.4,
        fill: true,
        backgroundColor: ctx => {
          const { chart } = ctx;
          const { ctx: g, chartArea } = chart;
          if (!chartArea) return c.brandSoft;
          const grad = g.createLinearGradient(
            0,
            chartArea.top,
            0,
            chartArea.bottom
          );
          grad.addColorStop(0, c.brandSoft);
          grad.addColorStop(1, 'rgba(0,0,0,0)');
          return grad;
        },
        pointRadius: props.data.map((_, i) =>
          i === props.activeIndex ? 5 : 0
        ),
        pointBackgroundColor: c.brand,
        pointBorderColor: '#fff',
        pointBorderWidth: 2,
        pointHoverRadius: 5,
      },
    ],
  };
});

const options = computed(() => {
  const c = chartPalette();
  return {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: { display: false },
      tooltip: {
        backgroundColor: c.ink,
        padding: 10,
        cornerRadius: 8,
        displayColors: false,
        callbacks: { label: ctx => props.valueFormat(ctx.raw) },
      },
    },
    scales: {
      x: {
        border: { display: false },
        grid: { display: false },
        ticks: { color: c.muted, font: { family: FONT_FAMILY, size: 11 } },
      },
      y: {
        border: { display: false },
        grid: { color: c.grid, drawTicks: false },
        ticks: {
          color: c.muted,
          font: { family: FONT_FAMILY, size: 11 },
          maxTicksLimit: 5,
          callback: v => props.valueFormat(v),
        },
      },
    },
  };
});
</script>

<template>
  <Line :data="collection" :options="options" />
</template>
