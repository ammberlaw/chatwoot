<script setup>
defineProps({
  title: { type: String, required: true },
  description: { type: String, default: '' },
  width: {
    type: String,
    default: 'standard',
    validator: value => ['narrow', 'standard', 'wide'].includes(value),
  },
});
const widths = {
  narrow: 'max-w-3xl',
  standard: 'max-w-4xl',
  wide: 'max-w-5xl',
};
</script>

<template>
  <div
    class="flex h-full w-full flex-col overflow-hidden rounded-3xl border backdrop-blur-2xl backdrop-saturate-150 bg-n-solid-1/80 border-n-weak/70 shadow-wintouch-glass"
  >
    <header class="shrink-0 border-b border-n-weak">
      <div
        class="flex w-full items-center justify-between gap-4 px-5 py-4 sm:px-8"
      >
        <div class="min-w-0">
          <h1 class="text-heading-1 text-n-slate-12">{{ title }}</h1>
          <p
            v-if="description"
            class="mb-0 mt-1 text-label-small leading-relaxed text-n-slate-11"
          >
            {{ description }}
          </p>
        </div>
        <div v-if="$slots.actions" class="flex shrink-0 items-center gap-2">
          <slot name="actions" />
        </div>
      </div>
    </header>
    <div class="min-h-0 flex-1 overflow-y-auto">
      <div class="mx-auto w-full px-5 py-6 sm:px-8" :class="widths[width]">
        <div v-if="$slots.toolbar" class="mb-5"><slot name="toolbar" /></div>
        <slot />
      </div>
    </div>
  </div>
</template>
