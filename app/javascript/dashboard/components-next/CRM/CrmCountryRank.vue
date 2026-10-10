<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { COUNTRY_LABELS } from '../../routes/dashboard/crm/constants/countries';
import countries from './charts/worldCountryPaths.json';

const props = defineProps({
  rows: { type: Array, required: true },
  periodLabel: { type: String, required: true },
  valueFormat: { type: Function, required: true },
});
const { t } = useI18n();
const selected = ref(null);
const expanded = ref(false);
const key = country => country.toUpperCase().replaceAll(' ', '_');
const normalized = computed(() => {
  const groups = new Map();
  props.rows.forEach(row => {
    const shape = countries.find(country =>
      country.keys.includes(key(row.country))
    );
    const code = shape?.keys[0] || key(row.country);
    const existing = groups.get(code) || {
      ...row,
      code,
      amount: 0,
      customers: 0,
      shape,
    };
    existing.amount += row.amount;
    existing.customers += row.customers;
    groups.set(code, existing);
  });
  return [...groups.values()].sort((a, b) => b.amount - a.amount);
});
const shown = computed(() =>
  expanded.value ? normalized.value : normalized.value.slice(0, 5)
);
const active = computed(() => selected.value ?? normalized.value[0]?.code);
const label = row =>
  COUNTRY_LABELS[key(row.country)] ||
  row.shape?.name ||
  row.country ||
  t('CRM.DASHBOARD.DESIGN.UNKNOWN_COUNTRY');
const mapColor = country => {
  const row = normalized.value.find(item => item.code === country.keys[0]);
  if (!row) return '#f0f1ed';
  return row.code === active.value ? '#ffd052' : '#74796c';
};
</script>

<template>
  <section
    class="min-w-0 p-6 sm:p-7 rounded-3xl border border-[#e9eae6] bg-white"
  >
    <div class="flex flex-wrap items-start justify-between gap-3 mb-5">
      <div>
        <h2 class="text-heading-2 text-[#191b1b]">
          {{ t('CRM.DASHBOARD.DESIGN.COUNTRY_RANK') }}
        </h2>
        <p class="mt-1 text-label-small text-[#85887f]">
          {{ t('CRM.DASHBOARD.DESIGN.COUNTRY_RANK_NOTE') }}
        </p>
      </div>
      <span class="text-label-small text-[#85887f]">{{ periodLabel }}</span>
    </div>
    <div
      v-if="rows.length"
      class="grid items-center gap-8 lg:grid-cols-[minmax(0,0.9fr)_minmax(0,1.3fr)]"
    >
      <div class="min-w-0">
        <ol class="flex flex-col gap-3 list-none !pl-0">
          <li v-for="(row, index) in shown" :key="row.code">
            <button
              class="relative w-full overflow-hidden rounded-xl bg-[#f5f6f2] px-4 py-3 text-left focus-visible:outline-2 focus-visible:outline-[#a77800]"
              @click="selected = row.code"
            >
              <svg
                class="absolute inset-0 w-full h-full"
                viewBox="0 0 100 100"
                preserveAspectRatio="none"
                aria-hidden="true"
              >
                <rect
                  :width="(row.amount / normalized[0].amount) * 100"
                  height="100"
                  :fill="row.code === active ? '#ffd052' : '#e5e7de'"
                />
              </svg>
              <div class="relative flex items-center justify-between gap-3">
                <span class="flex items-center gap-3 min-w-0"
                  ><span class="text-label-small text-[#686d61]">{{
                    String(index + 1).padStart(2, '0')
                  }}</span
                  ><span class="text-label truncate">{{
                    label(row)
                  }}</span></span
                >
                <strong
                  class="text-label font-interDisplay tabular-nums whitespace-nowrap"
                  >{{ valueFormat(row.amount) }}</strong
                >
              </div>
              <p class="relative ml-7 mt-1 text-label-small text-[#686d61]">
                {{
                  t('CRM.DASHBOARD.DESIGN.DEAL_CUSTOMERS', {
                    count: row.customers,
                  })
                }}
              </p>
            </button>
          </li>
        </ol>
        <button
          v-if="normalized.length > 5"
          class="mt-4 text-label-small text-[#85887f]"
          :aria-expanded="expanded"
          @click="expanded = !expanded"
        >
          {{ t('CRM.DASHBOARD.DESIGN.MORE_COUNTRIES') }} ·
          {{ normalized.length }}
        </button>
      </div>
      <div class="min-w-0">
        <svg
          viewBox="0 0 720 340"
          class="w-full"
          role="img"
          :aria-label="t('CRM.DASHBOARD.DESIGN.COUNTRY_MAP')"
        >
          <path
            v-for="country in countries"
            :key="country.keys[0]"
            :d="country.path"
            :fill="mapColor(country)"
            stroke="#fff"
            stroke-width="0.65"
          >
            <title>{{ country.name }}</title>
          </path>
        </svg>
        <p class="mt-3 text-center text-label-small text-[#85887f]">
          {{
            t('CRM.DASHBOARD.DESIGN.REGIONS_COUNT', {
              count: normalized.filter(row => row.country).length,
            })
          }}
        </p>
      </div>
    </div>
    <div v-else class="grid h-56 place-items-center text-label text-[#85887f]">
      {{ t('CRM.DASHBOARD.DESIGN.NO_DATA') }}
    </div>
  </section>
</template>
