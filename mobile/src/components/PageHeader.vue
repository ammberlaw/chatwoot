<script setup>
import { useRouter } from 'vue-router';

defineProps({
  title: { type: String, required: true },
  subtitle: { type: String, default: '' },
  // 有返回箭头的是二级页；tab 页不传
  back: { type: Boolean, default: false },
});

const router = useRouter();
const goBack = () => (window.history.length > 1 ? router.back() : router.push('/home'));
</script>

<template>
  <!-- 两种形态：
       · 一级页（不传 back）＝ 25px 大标题 + 灰色副标题，左对齐，不加边框不加背景，
         让它和页面是一体的（工作台/日程就是这个形）。
       · 二级页（传 back）＝ 紧凑一行，返回键 + 17px 标题，底部一道 0.5px 发丝线。
       两种都不给 sticky 背景色——内容滚过去时靠各页自己的磨砂条处理。 -->
  <header class="flex-none pt-safeTop">
    <template v-if="back">
      <!-- px-4 与页面内容同一条左边线；返回键用 -ml-2 让图标（而非 36px 点击区）压在 16px 上 -->
      <div class="flex items-center gap-1 px-4 min-h-[48px]">
        <button
          type="button"
          aria-label="返回"
          class="grid flex-none -ml-2 rounded-full size-9 place-items-center text-[color:var(--pb-ink)] transition-opacity active:opacity-50"
          @click="goBack"
        >
          <span class="size-6 i-lucide-chevron-left" />
        </button>

        <div class="flex-1 min-w-0">
          <h1
            class="text-[17px] font-semibold leading-[22px] tracking-[-0.43px] truncate text-[color:var(--pb-ink)]"
          >
            {{ title }}
          </h1>
          <p
            v-if="subtitle"
            class="text-[12px] leading-4 truncate text-[color:var(--pb-ink-3)]"
          >
            {{ subtitle }}
          </p>
        </div>

        <div class="flex items-center flex-none gap-1 -mr-2">
          <slot name="actions" />
        </div>
      </div>
      <div class="h-[0.5px] bg-[color:var(--pb-sep)]" />
    </template>

    <template v-else>
      <div class="flex items-center justify-between gap-3 px-4 pt-3 pb-3">
        <div class="min-w-0">
          <h1
            class="text-[32px] font-bold leading-[38px] tracking-[-0.8px] truncate text-[color:var(--pb-ink)]"
          >
            {{ title }}
          </h1>
          <p
            v-if="subtitle"
            class="mt-1 text-[14px] leading-[19px] truncate text-[color:var(--pb-ink-2)]"
          >
            {{ subtitle }}
          </p>
        </div>

        <div class="flex items-center flex-none gap-1.5">
          <slot name="actions" />
        </div>
      </div>
    </template>

    <slot name="below" />
  </header>
</template>
