<script setup>
import { computed } from 'vue';

const props = defineProps({
  loading: { type: Boolean, default: false },
  failed: { type: Boolean, default: false },
  empty: { type: Boolean, default: false },
  emptyText: { type: String, default: '暂无数据' },
  // 非空 = 当前展示的是缓存数据，展示落款时间
  staleAt: { type: Number, default: null },
});

defineEmits(['retry']);

const staleLabel = computed(() =>
  props.staleAt
    ? new Date(props.staleAt).toLocaleString('zh-CN', {
        month: 'numeric',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
      })
    : ''
);
</script>

<template>
  <p v-if="loading" class="py-10 text-sm text-center text-[color:var(--pb-ink-2)]">加载中…</p>

  <div
    v-else-if="failed"
    class="p-5 text-center border rounded-2xl border-[color:var(--pb-sep)] bg-[color:var(--pb-card)]"
  >
    <p class="text-sm text-[color:var(--pb-ink-2)]">加载失败</p>
    <button
      type="button"
      class="px-4 mt-3 text-sm font-medium rounded-lg h-11 text-[color:var(--pb-accent)] bg-[color:var(--pb-fill)] active:bg-[color:var(--pb-fill)]"
      @click="$emit('retry')"
    >
      重试
    </button>
  </div>

  <template v-else>
    <p v-if="staleAt" class="mb-2 text-xs text-[color:var(--pb-ink-3)]">
      离线，显示 {{ staleLabel }} 的数据
    </p>
    <template v-if="empty">
      <!-- 想要插画空态的页面传 #empty；不传就退回一行灰字 -->
      <slot name="empty">
        <p class="py-10 text-sm text-center text-[color:var(--pb-ink-2)]">{{ emptyText }}</p>
      </slot>
    </template>
    <slot v-else />
  </template>
</template>
