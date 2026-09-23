<script setup>
import { useRouter } from 'vue-router';

// iOS 导航栏：默认只是一条半透明细栏，内容从下面滚过去；
// 页面滚过大标题后，行内标题才淡入（大标题本身放在滚动内容里，会自然滚走）。
defineProps({
  title: { type: String, default: '' },
  back: { type: Boolean, default: false },
  showTitle: { type: Boolean, default: false },
});

const router = useRouter();
const goBack = () => (window.history.length > 1 ? router.back() : router.push('/home'));
</script>

<template>
  <header
    class="sticky top-0 z-20 flex-none transition-colors pt-safeTop"
    :class="showTitle ? 'wt-glass-bar border-b border-white/40' : ''"
  >
    <div class="relative flex items-center px-2 h-11">
      <button
        v-if="back"
        type="button"
        aria-label="返回"
        class="relative z-10 flex items-center -ml-1 text-[color:var(--pb-accent)] active:opacity-50"
        @click="goBack"
      >
        <span class="size-[26px] i-lucide-chevron-left" />
      </button>
      <!-- 行内标题在栏里居中，与返回键互不挤占 -->
      <span
        class="absolute inset-x-12 text-center truncate transition-opacity ios-headline text-[color:var(--pb-ink)]"
        :class="showTitle ? 'opacity-100' : 'opacity-0'"
      >
        {{ title }}
      </span>
      <div class="flex items-center gap-1 ml-auto">
        <slot name="actions" />
      </div>
    </div>
  </header>
</template>
