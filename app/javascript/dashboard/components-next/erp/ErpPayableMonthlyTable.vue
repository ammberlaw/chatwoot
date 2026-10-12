<script setup>
import { ref, computed } from 'vue';
import { fmtMoney } from 'dashboard/helper/erpMoney';
import { exportRowsToExcel, microsToYuan } from 'dashboard/helper/erpExcel';
import { printElement } from 'dashboard/helper/printHelper';
import MonthPicker from 'dashboard/components-next/monthpicker/MonthPicker.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';

// 应付「按月未付」：行 = 供应商 × 结算方式（含税/未税），列 = 各月未付货款，末列 = 期末未付合计。
// 回答「截止到 8 月底还欠哪些供应商多少、欠的是哪几个月的货」——账龄分析看的是逾期多久，
// 这张看的是欠在哪个月，两张表不互相替代。
const props = defineProps({
  fetcher: { type: Function, required: true },
});

const L = {
  title: '应付账款台账（按月未付）',
  asOf: '截止到',
  span: '往前看',
  query: '查询',
  print: '打印',
  export: '导出 Excel',
  supplier: '供应商',
  settle: '结算',
  earlier: '更早',
  total: '期末未付',
  loading: '加载中…',
  empty: '这个口径下没有未付的货款。',
  unit: '单位：元（本位币）',
  note: '金额＝截止日当天仍未付的部分；截止日之后付的款不冲抵。',
  grand: '合计',
};
const SPANS = [6, 12, 18, 24].map(n => ({
  value: String(n),
  label: `${n} 个月`,
}));

const money = micros => (micros ? fmtMoney(micros) : '—');
const monthLabel = key => `${key.slice(5)}月`;

const asOf = ref(new Date().toLocaleDateString('sv').slice(0, 7));
const span = ref('12');
const loading = ref(false);
const rows = ref([]);
const meta = ref(null);
const sheetRef = ref(null);

const months = computed(() => meta.value?.months || []);
const totals = computed(() => meta.value?.totals || {});
const earlierKey = computed(() => meta.value?.earlier_key || 'earlier');
// 「更早」那列全是 0 就别占地方——12 个月已经够宽了。
const showEarlier = computed(() => (totals.value[earlierKey.value] || 0) > 0);

const load = async () => {
  loading.value = true;
  try {
    const { data } = await props.fetcher({
      as_of: `${asOf.value}-01`,
      months: span.value,
    });
    rows.value = data.payload;
    meta.value = data.meta;
  } finally {
    loading.value = false;
  }
};

const print = () =>
  printElement(sheetRef.value, `${L.title} ${meta.value?.as_of || ''}`);

const exportExcel = () => {
  const columns = [
    { label: L.supplier, key: 'supplier' },
    { label: L.settle, key: 'settle' },
    ...(showEarlier.value ? [{ label: L.earlier, key: earlierKey.value }] : []),
    ...months.value.map(m => ({ label: monthLabel(m), key: m })),
    { label: L.total, key: 'total' },
  ];
  const body = rows.value.map(row => {
    const cells = {
      supplier: row.supplier_name,
      settle: row.settle_type_label,
    };
    if (showEarlier.value) {
      cells[earlierKey.value] = microsToYuan(
        row.by_month[earlierKey.value] || 0
      );
    }
    months.value.forEach(m => {
      cells[m] = microsToYuan(row.by_month[m] || 0);
    });
    cells.total = microsToYuan(row.total_micros);
    return cells;
  });
  exportRowsToExcel(
    {
      title: L.title,
      meta: [
        { label: L.asOf, value: meta.value?.as_of || '' },
        { label: '口径', value: L.note },
      ],
      columns,
      rows: body,
    },
    `应付按月未付-${meta.value?.as_of || ''}`
  );
};

defineExpose({ load });
</script>

<template>
  <div class="flex flex-col gap-3">
    <div class="flex flex-wrap items-center gap-2">
      <span class="text-sm text-n-slate-11">{{ L.asOf }}</span>
      <MonthPicker v-model="asOf" :clearable="false" trigger-class="w-32" />
      <span class="text-sm text-n-slate-11">{{ L.span }}</span>
      <SelectCard v-model="span" :options="SPANS" @update:model-value="load" />
      <Button :label="L.query" color="iris" size="sm" @click="load" />
      <Button
        v-if="meta"
        :label="L.print"
        icon="i-lucide-printer"
        color="slate"
        variant="faded"
        size="sm"
        @click="print"
      />
      <Button
        v-if="meta"
        :label="L.export"
        icon="i-lucide-download"
        color="slate"
        variant="faded"
        size="sm"
        @click="exportExcel"
      />
      <span v-if="meta" class="text-sm text-n-slate-11">
        {{ L.total }}
        <span class="font-mono text-n-slate-12">
          {{ money(totals.total) }}
        </span>
      </span>
    </div>

    <div v-if="loading" class="py-10 text-center text-n-slate-11">
      {{ L.loading }}
    </div>

    <div v-else-if="meta" ref="sheetRef" class="flex flex-col gap-3">
      <div class="text-base font-semibold text-center text-n-slate-12">
        {{ L.title }}
      </div>
      <div class="-mt-2 text-xs text-center text-n-slate-11">
        {{ L.asOf }} {{ meta.as_of }} · {{ L.unit }} · {{ L.note }}
      </div>
      <HScrollButtons />
      <div class="overflow-x-auto">
        <table class="w-full text-sm">
          <thead>
            <tr class="text-left border-b text-n-slate-11 border-n-weak">
              <th class="px-3 py-2 font-medium whitespace-nowrap">
                {{ L.supplier }}
              </th>
              <th class="px-3 py-2 font-medium whitespace-nowrap">
                {{ L.settle }}
              </th>
              <th
                v-if="showEarlier"
                class="px-3 py-2 font-medium text-right whitespace-nowrap"
              >
                {{ L.earlier }}
              </th>
              <th
                v-for="m in months"
                :key="m"
                class="px-3 py-2 font-medium text-right whitespace-nowrap"
              >
                {{ monthLabel(m) }}
              </th>
              <th class="px-3 py-2 font-medium text-right whitespace-nowrap">
                {{ L.total }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in rows"
              :key="`${row.supplier_id}-${row.settle_type}`"
              class="border-b border-n-weak hover:bg-n-alpha-1"
            >
              <td class="px-3 py-2 text-n-slate-12 whitespace-nowrap">
                {{ row.supplier_name }}
              </td>
              <td class="px-3 py-2 whitespace-nowrap">
                <span
                  class="px-2 py-0.5 text-xs rounded-full"
                  :class="
                    row.settle_type === 'PRIVATE'
                      ? 'bg-n-amber-3 text-n-amber-11'
                      : 'bg-n-iris-3 text-n-iris-11'
                  "
                >
                  {{ row.settle_type_label }}
                </span>
              </td>
              <td
                v-if="showEarlier"
                class="px-3 py-2 font-mono text-right text-n-slate-11"
              >
                {{ money(row.by_month[earlierKey]) }}
              </td>
              <td
                v-for="m in months"
                :key="m"
                class="px-3 py-2 font-mono text-right text-n-slate-11"
              >
                {{ money(row.by_month[m]) }}
              </td>
              <td
                class="px-3 py-2 font-mono font-medium text-right text-n-slate-12"
              >
                {{ money(row.total_micros) }}
              </td>
            </tr>
            <tr v-if="!rows.length">
              <td colspan="99" class="py-10 text-center text-n-slate-11">
                {{ L.empty }}
              </td>
            </tr>
            <tr v-else class="font-medium border-t-2 border-n-strong">
              <td class="px-3 py-2 text-n-slate-12" colspan="2">
                {{ L.grand }}
              </td>
              <td
                v-if="showEarlier"
                class="px-3 py-2 font-mono text-right text-n-slate-12"
              >
                {{ money(totals[earlierKey]) }}
              </td>
              <td
                v-for="m in months"
                :key="m"
                class="px-3 py-2 font-mono text-right text-n-slate-12"
              >
                {{ money(totals[m]) }}
              </td>
              <td class="px-3 py-2 font-mono text-right text-n-slate-12">
                {{ money(totals.total) }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</template>
