<script setup>
import { computed } from 'vue';
import { fmtMoney } from 'dashboard/helper/erpMoney';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// 核销编辑器：把一笔收/付款拆到未结台账上。收款与付款共用（ledgers 由外部按客户/供应商拉好）。
// 守恒规则后端 AllocationService 兜底，这里只做录入体验：实时提示剩余待核销、超额红字、一键平账。
const props = defineProps({
  ledgers: { type: Array, default: () => [] }, // [{ id, no, label, outstanding_micros }]
  amountMicros: { type: Number, default: 0 }, // 单据金额
  emptyHint: { type: String, default: '该往来单位没有未结台账' },
});

// [{ ledgerId, amount }]，amount 以「元」为单位（表单值）
const rows = defineModel({ type: Array, default: () => [] });

const toMicros = value => Math.round(Number(value || 0) * 1_000_000);
const allocatedMicros = computed(() =>
  rows.value.reduce((sum, row) => sum + toMicros(row.amount), 0)
);
const remainingMicros = computed(
  () => props.amountMicros - allocatedMicros.value
);
const overAllocated = computed(() => remainingMicros.value < 0);

const amountOf = ledgerId =>
  rows.value.find(row => row.ledgerId === ledgerId)?.amount ?? '';

const setAmount = (ledgerId, value) => {
  const index = rows.value.findIndex(row => row.ledgerId === ledgerId);
  if (!value) {
    if (index !== -1) rows.value.splice(index, 1);
    return;
  }
  if (index === -1) rows.value.push({ ledgerId, amount: value });
  else rows.value[index].amount = value;
};

// 一键平账：按台账顺序把单据金额铺下去，铺满为止（每张不超过其未结余额）。
const autoAllocate = () => {
  let left = props.amountMicros;
  const next = [];
  props.ledgers.forEach(ledger => {
    if (left <= 0) return;
    const take = Math.min(left, ledger.outstanding_micros);
    if (take <= 0) return;
    next.push({ ledgerId: ledger.id, amount: (take / 1_000_000).toFixed(2) });
    left -= take;
  });
  rows.value = next;
};

const clearAll = () => {
  rows.value = [];
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <div class="flex items-center justify-between">
      <label class="text-heading-3 text-n-slate-12">核销到台账</label>
      <div class="flex items-center gap-2">
        <span
          class="text-xs"
          :class="overAllocated ? 'text-n-ruby-11' : 'text-n-slate-11'"
        >
          {{ overAllocated ? '超额' : '待核销' }}
          {{ fmtMoney(Math.abs(remainingMicros)) }}
        </span>
        <Button
          label="一键平账"
          color="slate"
          variant="faded"
          size="xs"
          :disabled="!ledgers.length || !amountMicros"
          @click="autoAllocate"
        />
        <Button
          label="清空"
          color="slate"
          variant="ghost"
          size="xs"
          :disabled="!rows.length"
          @click="clearAll"
        />
      </div>
    </div>

    <div
      v-if="!ledgers.length"
      class="px-3 py-4 text-sm text-center rounded-lg text-n-slate-11 bg-n-alpha-1"
    >
      {{ emptyHint }}
    </div>
    <div v-else class="flex flex-col gap-1.5 max-h-64 overflow-auto">
      <div
        v-for="ledger in ledgers"
        :key="ledger.id"
        class="grid items-center grid-cols-12 gap-2 px-2 py-1.5 border rounded-lg border-n-weak"
      >
        <span class="col-span-3 font-mono text-xs text-n-slate-11">
          {{ ledger.no }}
        </span>
        <span class="col-span-5 text-sm truncate text-n-slate-12">
          {{ ledger.label }}
        </span>
        <span class="col-span-2 font-mono text-xs text-right text-n-slate-11">
          未结 {{ fmtMoney(ledger.outstanding_micros) }}
        </span>
        <div class="col-span-2">
          <Input
            size="sm"
            type="number"
            placeholder="核销额"
            :model-value="amountOf(ledger.id)"
            @update:model-value="v => setAmount(ledger.id, v)"
          />
        </div>
      </div>
    </div>
  </div>
</template>
