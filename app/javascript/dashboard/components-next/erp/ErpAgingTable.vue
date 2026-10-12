<script setup>
import { ref, computed } from 'vue';
import { fmtMoney } from 'dashboard/helper/erpMoney';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { printElement } from 'dashboard/helper/printHelper';
import { exportRowsToExcel } from 'dashboard/helper/erpExcel';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
// 账龄分析表（应收按客户、应付按供应商共用一张）。
// 两种口径：逾期账龄（从到期日算，催款用）/ 账龄（从建账日算，坏账计提用）。
// 点客户行展开该客户的单据明细；金额一律本位币，明细里带原币便于核对。
const props = defineProps({
  title: { type: String, required: true },
  partyLabel: { type: String, required: true },
  fetcher: { type: Function, required: true },
});

const BASIS_OPTIONS = [
  { value: 'due', label: '逾期账龄（按到期日）' },
  { value: 'invoice', label: '账龄（按建账日）' },
];

const money = micros => (micros ? fmtMoney(micros) : '—');

const asOf = ref(new Date().toLocaleDateString('sv'));
const basis = ref('due');
const loading = ref(false);
const rows = ref([]);
const meta = ref(null);
const expanded = ref(new Set());

const buckets = computed(() => meta.value?.buckets || []);
const totals = computed(() => meta.value?.totals || { cells: {} });

const load = async () => {
  loading.value = true;
  try {
    const { data } = await props.fetcher({
      as_of: asOf.value,
      basis: basis.value,
    });
    rows.value = data.payload;
    meta.value = data.meta;
    expanded.value = new Set();
  } finally {
    loading.value = false;
  }
};

const toggle = partyId => {
  const next = new Set(expanded.value);
  if (next.has(partyId)) next.delete(partyId);
  else next.add(partyId);
  expanded.value = next;
};

// 打印只出报表本体，不带上面那条查询栏。
const sheetRef = ref(null);
const print = () =>
  printElement(sheetRef.value, `${props.title} ${meta.value?.as_of || ''}`);

// 导出：接口一次给全量（没有分页），屏幕上的 rows 就是全量，不用再要一次。
// 账龄桶是动态列（口径不同桶不同），列定义照 meta.buckets 现搭。
// 只导汇总行，不展开单据明细——明细在台账页导，这里导出来一张行数翻十倍的表反而没法用。
const exportExcel = () => {
  const basisLabel =
    BASIS_OPTIONS.find(o => o.value === basis.value)?.label || '';
  exportRowsToExcel(
    {
      title: props.title,
      meta: [
        {
          label: '导出时间',
          value: new Date().toLocaleString('sv').slice(0, 16),
        },
        { label: '截至', value: meta.value?.as_of || asOf.value },
        { label: '口径', value: basisLabel },
        { label: '单位', value: '元（本位币）' },
        { label: `${props.partyLabel}数`, value: rows.value.length },
      ],
      columns: [
        { label: props.partyLabel, key: 'party_name' },
        { label: '未结合计', key: 'total_micros', money: true },
        ...buckets.value.map(bucket => ({
          label: bucket.label,
          key: bucket.key,
          money: true,
        })),
      ],
      // cells 是个按桶 key 的对象，摊平到行上才喂得进列定义。
      rows: rows.value.map(row => ({
        party_name: row.party_name,
        total_micros: row.total_micros,
        ...row.cells,
      })),
    },
    `${props.title}_${meta.value?.as_of || asOf.value}`
  );
};

defineExpose({ load });
</script>

<template>
  <div class="flex flex-col gap-3">
    <div class="flex flex-wrap items-center gap-2">
      <SelectCard
        v-model="basis"
        :options="BASIS_OPTIONS"
        @update:model-value="load"
      />
      <span class="text-sm text-n-slate-11">截至</span>
      <DatePicker v-model="asOf" :clearable="false" trigger-class="w-36" />
      <Button label="查询" color="iris" size="sm" @click="load" />
      <Button
        v-if="meta"
        label="打印"
        icon="i-lucide-printer"
        color="slate"
        variant="faded"
        size="sm"
        @click="print"
      />
      <Button
        v-if="meta"
        label="导出 Excel"
        icon="i-lucide-download"
        color="slate"
        variant="faded"
        size="sm"
        @click="exportExcel"
      />
      <span v-if="meta" class="text-sm text-n-slate-11">
        未结合计
        <span class="font-mono text-n-slate-12">
          {{ money(totals.total_micros) }}
        </span>
      </span>
    </div>

    <div v-if="loading" class="py-10 text-center text-n-slate-11">加载中…</div>

    <div v-else-if="meta" ref="sheetRef" class="flex flex-col gap-3">
      <div class="text-base font-semibold text-center text-n-slate-12">
        {{ title }}
      </div>
      <div class="-mt-2 text-xs text-center text-n-slate-11">
        截至 {{ meta.as_of }} · 单位：元（本位币）
      </div>
      <HScrollButtons />
      <div class="overflow-x-auto">
        <table class="w-full text-sm">
          <thead>
            <tr class="text-left border-b text-n-slate-11 border-n-weak">
              <th class="px-3 py-2 font-medium">{{ partyLabel }}</th>
              <th class="px-3 py-2 font-medium text-right whitespace-nowrap">
                未结合计
              </th>
              <th
                v-for="bucket in buckets"
                :key="bucket.key"
                class="px-3 py-2 font-medium text-right whitespace-nowrap"
              >
                {{ bucket.label }}
              </th>
            </tr>
          </thead>
          <tbody>
            <template v-for="row in rows" :key="row.party_id">
              <tr
                class="border-b cursor-pointer border-n-weak hover:bg-n-alpha-1"
                @click="toggle(row.party_id)"
              >
                <td class="px-3 py-2 text-n-slate-12">
                  <div class="flex items-center gap-1">
                    <div
                      class="size-4 text-n-slate-11"
                      :class="
                        expanded.has(row.party_id)
                          ? 'i-lucide-chevron-down'
                          : 'i-lucide-chevron-right'
                      "
                    />
                    {{ row.party_name }}
                  </div>
                </td>
                <td class="px-3 py-2 font-mono text-right text-n-slate-12">
                  {{ money(row.total_micros) }}
                </td>
                <td
                  v-for="bucket in buckets"
                  :key="bucket.key"
                  class="px-3 py-2 font-mono text-right"
                  :class="
                    bucket.key === 'OVER' && row.cells[bucket.key]
                      ? 'text-n-ruby-11'
                      : 'text-n-slate-12'
                  "
                >
                  {{ money(row.cells[bucket.key]) }}
                </td>
              </tr>
              <tr
                v-if="expanded.has(row.party_id)"
                class="border-b border-n-weak"
              >
                <td
                  :colspan="buckets.length + 2"
                  class="px-3 py-2 bg-n-alpha-1"
                >
                  <table class="text-xs w-fit">
                    <thead>
                      <tr class="text-left text-n-slate-11">
                        <th
                          class="py-1 pr-6 font-normal w-36 whitespace-nowrap"
                        >
                          单号
                        </th>
                        <th
                          class="py-1 pr-6 font-normal w-20 whitespace-nowrap"
                        >
                          款项
                        </th>
                        <th class="py-1 pr-6 font-normal w-28">
                          {{ meta.basis === 'invoice' ? '建账日' : '到期日' }}
                        </th>
                        <th
                          class="py-1 pr-6 font-normal w-20 whitespace-nowrap"
                        >
                          账龄
                        </th>
                        <th
                          class="py-1 pr-6 font-normal text-right w-36 whitespace-nowrap"
                        >
                          未结（原币）
                        </th>
                        <th
                          class="py-1 font-normal text-right w-32 whitespace-nowrap"
                        >
                          本位币
                        </th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr
                        v-for="(doc, index) in row.documents"
                        :key="`${doc.no}-${index}`"
                        class="text-n-slate-11"
                      >
                        <td class="py-1 pr-6 font-mono">{{ doc.no }}</td>
                        <td class="py-1 pr-6">{{ doc.note }}</td>
                        <td class="py-1 pr-6">{{ doc.date || '未定日期' }}</td>
                        <td class="py-1 pr-6">
                          {{ doc.days === null ? '未到期' : `${doc.days} 天` }}
                        </td>
                        <td class="py-1 pr-6 font-mono text-right">
                          {{ doc.currency }} {{ money(doc.open_micros) }}
                        </td>
                        <td class="py-1 font-mono text-right text-n-slate-12">
                          {{ money(doc.base_micros) }}
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </td>
              </tr>
            </template>
            <tr v-if="!rows.length">
              <td
                :colspan="buckets.length + 2"
                class="py-10 text-center text-n-slate-11"
              >
                没有未结单据
              </td>
            </tr>
            <tr v-else class="font-semibold">
              <td class="px-3 py-2 text-n-slate-12">合计</td>
              <td class="px-3 py-2 font-mono text-right text-n-slate-12">
                {{ money(totals.total_micros) }}
              </td>
              <td
                v-for="bucket in buckets"
                :key="bucket.key"
                class="px-3 py-2 font-mono text-right text-n-slate-12"
              >
                {{ money(totals.cells[bucket.key]) }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</template>
