<script setup>
defineProps({
  names: { type: Array, default: () => [] },
});
</script>

<template>
  <details v-if="names.length > 1" class="text-sm" @click.stop>
    <summary
      class="cursor-pointer whitespace-nowrap text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
    >
      {{ names.length }} 家供应商
    </summary>
    <ul
      class="mt-2 p-3 space-y-2 w-72 max-w-full max-h-60 overflow-y-auto whitespace-normal break-words rounded-lg border border-n-weak bg-n-solid-1 text-n-slate-12"
    >
      <li v-for="(name, index) in names" :key="index">{{ name }}</li>
    </ul>
  </details>
  <span
    v-else
    class="inline-block max-w-56 truncate align-middle"
    :title="names[0] || undefined"
  >
    {{ names[0] || '—' }}
  </span>
</template>
