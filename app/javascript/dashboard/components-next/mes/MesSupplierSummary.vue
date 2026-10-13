<script setup>
defineProps({
  names: { type: Array, default: () => [] },
  // [{ id, no, name }]——一张单里每家供应商的专属采购订单号。给了就连号一起显示：
  // 供应商交货、仓库入库、财务对账认的都是他那张单的号，列表上看不到号就对不上。
  suppliers: { type: Array, default: () => [] },
});
</script>

<template>
  <details v-if="names.length > 1" class="text-sm" @click.stop>
    <summary
      class="cursor-pointer whitespace-nowrap text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
    >
      {{ names.length }} 家供应商
    </summary>
    <ul
      class="mt-2 p-3 space-y-2 w-80 max-w-full max-h-60 overflow-y-auto whitespace-normal break-words rounded-lg border border-n-weak bg-n-solid-1 text-n-slate-12"
    >
      <li
        v-for="(row, index) in suppliers.length
          ? suppliers
          : names.map(n => ({ name: n }))"
        :key="index"
        class="flex items-baseline gap-2"
      >
        <span
          v-if="row.no"
          class="shrink-0 font-mono text-label-small text-n-slate-11"
        >
          {{ row.no }}
        </span>
        <span>{{ row.name }}</span>
      </li>
    </ul>
  </details>
  <span
    v-else
    class="inline-block max-w-56 truncate align-middle"
    :title="names[0] || undefined"
  >
    {{ names[0] || '—' }}
  </span>
</template>
