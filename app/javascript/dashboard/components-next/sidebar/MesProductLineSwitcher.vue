<script setup>
import { useMesProductLine } from 'dashboard/composables/useMesProductLine';

// 生产管理产品线切换：商显工控 / 平板 / 全部。切换后全站 MES 页面按线过滤（axios 拦截注入）。
const { activeProductLine, options, setActiveProductLine } =
  useMesProductLine();

// 切线即改产品线；MES 布局壳（MesLayout）的 router-view 以产品线为 key，
// 切换时只重挂当前 MES 页（重跑 onMounted 拉取），不刷新整个应用，丝滑很多。
const selectLine = value => setActiveProductLine(value);
</script>

<template>
  <div data-sidebar-module-select class="px-2 mb-1 [.theme-classic-black_&]:mx-3 [.theme-classic-black_&]:px-3 [.theme-classic-black_&]:py-3 [.theme-classic-black_&]:mb-4 [.theme-classic-black_&]:rounded-2xl [.theme-classic-black_&]:bg-[#242426] [.theme-classic-black_&]:border [.theme-classic-black_&]:border-[#414144]">
    <span class="block px-1 mb-1 text-label-small font-medium text-n-slate-10 [.theme-classic-black_&]:mb-2 [.theme-classic-black_&]:!text-[#f1f1f2] [.theme-classic-black_&]:font-semibold">
      产品线
    </span>
    <div
      class="flex gap-0.5 p-0.5 rounded-lg outline outline-1 outline-n-weak bg-n-alpha-black1 [.theme-classic-black_&]:gap-1 [.theme-classic-black_&]:p-1 [.theme-classic-black_&]:rounded-2xl [.theme-classic-black_&]:!outline-none [.theme-classic-black_&]:!bg-[#171719]"
    >
      <button
        v-for="opt in options"
        :key="opt.value"
        type="button"
        class="flex-1 px-1 py-1 text-label-small font-medium rounded-md transition-colors duration-100 truncate [.theme-classic-black_&]:h-9 [.theme-classic-black_&]:rounded-xl [.theme-classic-black_&]:focus-visible:outline [.theme-classic-black_&]:focus-visible:outline-2 [.theme-classic-black_&]:focus-visible:outline-[#e9ce80]"
        :class="
          activeProductLine === opt.value
            ? 'bg-n-solid-3 text-n-slate-12 shadow-sm [.theme-classic-black_&]:!bg-[#ffd34f] [.theme-classic-black_&]:!text-[#27251f] [.theme-classic-black_&]:font-semibold [.theme-classic-black_&]:shadow-none'
            : 'text-n-slate-10 hover:text-n-slate-12 [.theme-classic-black_&]:!text-[#b3b3b8] [.theme-classic-black_&]:hover:!bg-[#333336] [.theme-classic-black_&]:hover:!text-white'
        "
        :title="opt.label"
        :aria-pressed="activeProductLine === opt.value"
        @click="selectLine(opt.value)"
      >
        {{ opt.short }}
      </button>
    </div>
  </div>
</template>
