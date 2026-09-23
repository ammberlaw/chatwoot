<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import PageHeader from '@/components/PageHeader.vue';

// MES / ERP 的占位页。后端在本分支里是齐的（MES 20 个控制器、ERP 16 个），
// 所以这里不是空壳，只是手机端页面还没做。要展示什么由路由 meta 给。
defineOptions({ name: 'ModulePlaceholderPage' });

const route = useRoute();
const meta = computed(() => route.meta || {});
</script>

<template>
  <div class="flex flex-col h-full">
    <PageHeader back :title="meta.title" />

    <div class="flex-1 min-h-0 px-4 pt-4 overflow-y-auto">
      <div class="p-6 text-center wt-card">
        <span
          class="grid mx-auto rounded-2xl size-14 place-items-center bg-[color:var(--pb-fill)]"
        >
          <span class="size-7 text-[color:var(--pb-ink)]" :class="meta.icon" />
        </span>
        <p class="mt-4 text-[17px] font-semibold tracking-[-0.43px] text-[color:var(--pb-ink)]">
          即将上线
        </p>
        <p class="mt-1.5 text-[15px] leading-5 text-[color:var(--pb-ink-3)]">
          {{ meta.title }}手机端正在开发，<br />现在请先用电脑端。
        </p>
      </div>

      <h2 class="sec-title">将包含</h2>
      <ul class="overflow-hidden wt-card">
        <li
          v-for="(p, i) in meta.planned || []"
          :key="p"
          class="px-4 py-3 text-[17px] leading-[22px] tracking-[-0.43px] text-[color:var(--pb-ink)]"
          :class="i ? 'border-t-[0.5px] border-[color:var(--pb-sep)]' : ''"
        >
          {{ p }}
        </li>
      </ul>

      <div class="h-36" />
    </div>
  </div>
</template>
