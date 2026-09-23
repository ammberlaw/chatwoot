<script setup>
// 列表顶部四个概览数。数字跟着当前视图/搜索口径走（后端 stats 接口与列表同一份 scope）。
// 第一张用极浅品牌黄底，其余浅灰——规范里只允许这一张带黄。
defineProps({
  stats: { type: Object, default: () => ({}) },
});

const ITEMS = [
  { key: 'customers', label: '团队客户', brand: true },
  { key: 'new_this_month', label: '本月新增' },
  { key: 'open_opportunities', label: '在谈商机' },
  { key: 'with_orders', label: '有成交订单' },
];
</script>

<template>
  <div class="grid grid-cols-4 gap-2">
    <div
      v-for="it in ITEMS"
      :key="it.key"
      class="flex flex-col items-center justify-center rounded-2xl h-[90px] px-1"
      :class="it.brand ? 'bg-[color:var(--pb-brand-soft)]' : 'bg-[color:var(--surface)]'"
    >
      <span
        class="text-[20px] font-semibold leading-7 tabular-nums text-[color:var(--text)]"
      >
        {{ stats[it.key] ?? '—' }}
      </span>
      <span class="mt-1 text-[12px] leading-4 text-[color:var(--text-secondary)]">
        {{ it.label }}
      </span>
    </div>
  </div>
</template>
