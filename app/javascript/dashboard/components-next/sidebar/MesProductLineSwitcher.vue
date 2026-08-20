<script setup>
import { useMesProductLine } from 'dashboard/composables/useMesProductLine';

// 生产管理产品线切换：商显工控 / 平板 / 全部。切换后全站 MES 页面按线过滤（axios 拦截注入）。
const { activeProductLine, options, setActiveProductLine } =
  useMesProductLine();
</script>

<template>
  <div class="px-2 mb-1">
    <span class="block px-1 mb-1 text-xs font-medium text-n-slate-10">
      产品线
    </span>
    <div
      class="flex gap-0.5 p-0.5 rounded-lg outline outline-1 outline-n-weak bg-n-alpha-black1"
    >
      <button
        v-for="opt in options"
        :key="opt.value"
        type="button"
        class="flex-1 px-1 py-1 text-xs font-medium rounded-md transition-colors duration-100 truncate"
        :class="
          activeProductLine === opt.value
            ? 'bg-n-solid-3 text-n-slate-12 shadow-sm'
            : 'text-n-slate-10 hover:text-n-slate-12'
        "
        :title="opt.label"
        @click="setActiveProductLine(opt.value)"
      >
        {{ opt.short }}
      </button>
    </div>
  </div>
</template>
