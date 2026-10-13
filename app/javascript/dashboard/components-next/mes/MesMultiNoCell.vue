<script setup>
// 多个单号挤在一格里（金蝶导进来的合并单，采购单号本身就是「A、B、C」拼的）。
// 十几个号排成一行会把整张表撑到屏幕外，所以默认只露第一个 + 「+N」，点开才展全。
// 单个号照旧直接显示，不多这一层。
import { computed } from 'vue';

const props = defineProps({
  value: { type: String, default: '' },
});

const parts = computed(() =>
  String(props.value || '')
    .split(/[、,，]/)
    .map(s => s.trim())
    .filter(Boolean)
);
</script>

<template>
  <span v-if="parts.length <= 1">{{ parts[0] || '—' }}</span>
  <details v-else class="inline-block align-middle" @click.stop>
    <summary
      class="cursor-pointer whitespace-nowrap list-none focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
    >
      <span>{{ parts[0] }}</span>
      <span class="ml-1 text-xs text-n-blue-11 hover:underline">
        +{{ parts.length - 1 }}
      </span>
    </summary>
    <ul
      class="mt-2 p-2 space-y-1 w-56 max-w-full max-h-52 overflow-y-auto whitespace-normal break-words rounded-lg border border-n-weak bg-n-solid-1 text-n-slate-12"
    >
      <li v-for="(no, i) in parts" :key="i" class="font-mono text-xs">
        {{ no }}
      </li>
    </ul>
  </details>
</template>
