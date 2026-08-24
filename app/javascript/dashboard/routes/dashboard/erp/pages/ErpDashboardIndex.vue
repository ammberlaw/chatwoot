<script setup>
// 财务看板（E0）：6 张 KPI 占位卡，全为零值。真实数据在各切片落地后接入
// （回款/应收/应付=E3，资金/毛利=E4）。后端 GET erp/dashboard 已就绪并做 403 门禁。
const KPIS = [
  { key: 'month_receipt', label: '本月回款', slice: 'E3', icon: 'i-lucide-hand-coins' },
  { key: 'receivable_balance', label: '应收余额', slice: 'E3', icon: 'i-lucide-file-input' },
  { key: 'overdue_receivable', label: '逾期应收', slice: 'E3', icon: 'i-lucide-alarm-clock' },
  { key: 'payable_balance', label: '应付余额', slice: 'E3', icon: 'i-lucide-file-output' },
  { key: 'cash_balance', label: '资金余额', slice: 'E4', icon: 'i-lucide-wallet' },
  { key: 'month_profit', label: '本月毛利', slice: 'E4', icon: 'i-lucide-trending-up' },
];
</script>

<template>
  <div class="flex flex-col w-full h-full gap-4 p-6 overflow-auto">
    <div class="flex items-center gap-2">
      <div class="i-lucide-landmark size-5 text-n-iris-9" />
      <h1 class="text-lg font-semibold text-n-slate-12">财务看板</h1>
    </div>

    <div class="grid grid-cols-2 gap-4 md:grid-cols-3">
      <div
        v-for="kpi in KPIS"
        :key="kpi.key"
        class="flex flex-col gap-2 p-4 border rounded-xl border-n-weak bg-n-solid-1 shadow-sm"
      >
        <div class="flex items-center justify-between">
          <span class="text-sm text-n-slate-11">{{ kpi.label }}</span>
          <div :class="kpi.icon" class="size-4 text-n-iris-9" />
        </div>
        <div class="text-2xl font-semibold text-n-slate-12">0.00</div>
        <div class="text-xs text-n-slate-10">数据接入中 · {{ kpi.slice }}</div>
      </div>
    </div>
  </div>
</template>
