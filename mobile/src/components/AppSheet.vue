<script setup>
// 底部弹层。用 fixed 覆盖层而非原生 <dialog>，避免 iOS webview 顶层与键盘的交互问题。
defineProps({
  open: { type: Boolean, default: false },
  title: { type: String, default: '' },
});
defineEmits(['close']);
</script>

<template>
  <Teleport to="body">
    <Transition name="sheet">
      <div v-if="open" class="fixed inset-0 z-50 flex flex-col justify-end">
        <div class="absolute inset-0 bg-black/40" @click="$emit('close')" />
        <div
          class="relative flex flex-col bg-n-background rounded-t-3xl max-h-[88%] pb-safeBottom"
        >
          <div
            class="flex items-center flex-none gap-2 px-4 border-b min-h-[52px] border-n-weak"
          >
            <h2 class="flex-1 text-base font-bold truncate text-n-slate-12">
              {{ title }}
            </h2>
            <button
              type="button"
              aria-label="关闭"
              class="grid flex-none rounded-full size-9 place-items-center text-n-slate-11 active:bg-n-alpha-1"
              @click="$emit('close')"
            >
              <span class="size-5 i-lucide-x" />
            </button>
          </div>
          <div class="flex-1 min-h-0 px-4 py-4 overflow-y-auto">
            <slot />
          </div>
          <div v-if="$slots.footer" class="flex-none px-4 pt-2 pb-4">
            <slot name="footer" />
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.sheet-enter-active,
.sheet-leave-active {
  transition: opacity 0.2s ease;
}
.sheet-enter-active > div:last-child,
.sheet-leave-active > div:last-child {
  transition: transform 0.24s cubic-bezier(0.32, 0.72, 0, 1);
}
.sheet-enter-from,
.sheet-leave-to {
  opacity: 0;
}
.sheet-enter-from > div:last-child,
.sheet-leave-to > div:last-child {
  transform: translateY(100%);
}
</style>
