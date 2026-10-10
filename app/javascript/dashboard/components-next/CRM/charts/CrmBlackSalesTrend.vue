<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
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
import { FONT_FAMILY } from './chartColors';

const props = defineProps({
  completeness: { type: Boolean, default: false },
  labels: { type: Array, required: true },
  data: { type: Array, required: true },
  valueFormat: { type: Function, required: true },
});
ChartJS.register(
  Tooltip,
  Filler,
  LineElement,
  PointElement,
  CategoryScale,
  LinearScale
);
const { t } = useI18n();
const recorded = computed(() => {
  const last = props.completeness
    ? props.data.length - 1
    : props.data.findLastIndex(value => value > 0);
  return props.data.slice(0, last + 1);
});
const summary = computed(() => [
  {
    label: props.completeness ? 'PEAK_SCORE' : 'PEAK_REVENUE',
    value: Math.max(...recorded.value, 0),
  },
  {
    label: props.completeness ? 'AVERAGE_SCORE' : 'AVERAGE_REVENUE',
    value:
      recorded.value.reduce((sum, value) => sum + value, 0) /
      (recorded.value.length || 1),
  },
  {
    label: props.completeness ? 'LOW_SCORE' : 'LOW_REVENUE',
    value: recorded.value.length ? Math.min(...recorded.value) : 0,
  },
]);
const collection = computed(() => ({
  labels: props.labels,
  datasets: [
    {
      data: props.data.map((value, index) =>
        index < recorded.value.length ? value : null
      ),
      borderColor: props.completeness ? '#b97552' : '#c69728',
      borderWidth: 2,
      tension: 0.38,
      fill: true,
      backgroundColor: ({ chart }) => {
        if (!chart.chartArea) return '#fff5cf';
        const gradient = chart.ctx.createLinearGradient(
          0,
          chart.chartArea.top,
          0,
          chart.chartArea.bottom
        );
        gradient.addColorStop(
          0,
          props.completeness
            ? 'rgba(214,154,112,0.22)'
            : 'rgba(255,208,82,0.26)'
        );
        gradient.addColorStop(1, 'rgba(255,208,82,0)');
        return gradient;
      },
      pointRadius: 4,
      pointBackgroundColor: '#fff',
      pointBorderColor: props.completeness ? '#b97552' : '#c69728',
      pointBorderWidth: 1.5,
      pointHoverRadius: 6,
    },
  ],
}));
const options = computed(() => ({
  responsive: true,
  maintainAspectRatio: false,
  plugins: {
    legend: { display: false },
    tooltip: {
      backgroundColor: '#191b1b',
      padding: 10,
      cornerRadius: 8,
      displayColors: false,
      callbacks: { label: context => props.valueFormat(context.raw) },
    },
  },
  scales: {
    x: {
      border: { display: false, dash: [3, 3] },
      grid: { color: '#e9eae6', drawTicks: false },
      ticks: { color: '#85887f', font: { family: FONT_FAMILY, size: 11 } },
    },
    y: {
      beginAtZero: true,
      max: props.completeness ? 110 : undefined,
      border: { display: false, dash: [3, 3] },
      grid: { color: '#e9eae6', drawTicks: false },
      ticks: {
        color: '#85887f',
        maxTicksLimit: 4,
        callback: value => props.valueFormat(value),
        font: { family: FONT_FAMILY, size: 11 },
      },
    },
  },
}));
</script>

<template>
  <div class="h-60 min-w-0">
    <Line :data="collection" :options="options" />
  </div>
  <div class="grid grid-cols-3 divide-x divide-[#e9eae6] mt-6">
    <div
      v-for="metric in summary"
      :key="metric.label"
      class="px-4 first:pl-0 last:pr-0"
    >
      <p class="text-label-small text-[#85887f]">
        {{ t(`CRM.DASHBOARD.DESIGN.${metric.label}`) }}
      </p>
      <p
        class="mt-2 text-xl font-interDisplay font-semibold tracking-tight tabular-nums text-[#191b1b]"
      >
        {{ valueFormat(metric.value) }}
      </p>
    </div>
  </div>
</template>
