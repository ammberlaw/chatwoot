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
  <header
    class="sticky top-0 z-10 flex-none border-b border-n-weak bg-n-background/95 backdrop-blur-xl pt-safeTop"
  >
    <div class="flex items-center gap-2 px-2 min-h-[52px]">
      <button
        v-if="back"
        type="button"
        aria-label="返回"
        class="grid flex-none rounded-full size-9 place-items-center text-n-slate-11 active:bg-n-alpha-1"
        @click="goBack"
      >
        <span class="size-5 i-lucide-chevron-left" />
      </button>
      <div v-else class="flex-none w-2" />

      <div class="flex-1 min-w-0">
        <h1
          class="font-bold truncate text-n-slate-12"
          :class="back ? 'text-base' : 'text-2xl'"
        >
          {{ title }}
        </h1>
        <p v-if="subtitle" class="text-xs truncate text-n-slate-11">
          {{ subtitle }}
        </p>
      </div>

      <div class="flex items-center flex-none gap-1 pr-1">
        <slot name="actions" />
      </div>
    </div>
    <slot name="below" />
  </header>
</template>
