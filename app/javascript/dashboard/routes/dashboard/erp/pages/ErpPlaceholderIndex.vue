<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';

// E0 共用占位页：按路由名显示所属板块标题 + 所属切片，实现某板块时替换为独立组件。
const TITLES = {
  erp_ledgers_index: ['账簿', 'E2 账簿报表'],
  erp_reports_index: ['财务报表', 'E2 账簿报表'],
  erp_receivables_index: ['应收台账', 'E3 应收应付'],
  erp_payables_index: ['应付台账', 'E3 应收应付'],
};

const route = useRoute();
const info = computed(() => TITLES[route.name] || ['财务管理', '']);
</script>

<template>
  <div
    class="flex flex-col items-center justify-center w-full h-full gap-2 text-n-slate-11"
  >
    <div class="i-lucide-landmark size-8 text-n-iris-9" />
    <div class="text-lg font-semibold text-n-slate-12">{{ info[0] }}</div>
    <div class="text-sm">该模块即将上线</div>
    <div v-if="info[1]" class="text-xs text-n-slate-10">{{ info[1] }}</div>
  </div>
</template>
