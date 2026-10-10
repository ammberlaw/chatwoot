<script setup>
import { computed } from 'vue';

/**
 * 气泡底下那排表情回应（❤️ 2）。
 *
 * 数据来自 content_attributes.reactions，每条是
 * { emoji, actor: 'contact'|'agent', actor_id, actor_name }——
 * 同一个人对同一条消息最多一个回应（WhatsApp 的语义，后端按这个去重）。
 *
 * 这里按 emoji 归并计数；点自己已经点过的那个 = 撤销（传空字符串），
 * 点别人点过的 = 自己也点一个。
 */
const props = defineProps({
  reactions: { type: Array, default: () => [] },
  currentUserId: { type: [Number, String], default: null },
  orientation: { type: String, default: 'left' },
});

const emit = defineEmits(['toggle']);

// 接口返回的键会被深度驼峰化（actor_id → actorId），但 websocket 推来的
// message.updated 不一定走同一套转换，两种拼法都认。
const actorIdOf = r => r.actorId ?? r.actor_id;
const actorNameOf = r => r.actorName ?? r.actor_name;

const groups = computed(() => {
  const byEmoji = new Map();
  props.reactions.forEach(r => {
    if (!r?.emoji) return;
    const row = byEmoji.get(r.emoji) || {
      emoji: r.emoji,
      names: [],
      mine: false,
    };
    row.names.push(actorNameOf(r) || (r.actor === 'agent' ? '同事' : '客户'));
    if (
      r.actor === 'agent' &&
      String(actorIdOf(r)) === String(props.currentUserId)
    ) {
      row.mine = true;
    }
    byEmoji.set(r.emoji, row);
  });
  return [...byEmoji.values()];
});

// 自己点过就撤销，没点过就点上。
const onClick = row => emit('toggle', row.mine ? '' : row.emoji);
</script>

<template>
  <div
    v-show="groups.length"
    class="flex flex-wrap gap-1 mt-1"
    :class="orientation === 'right' ? 'justify-end' : 'justify-start'"
  >
    <button
      v-for="row in groups"
      :key="row.emoji"
      v-tooltip.top="row.names.join('、')"
      type="button"
      class="flex items-center h-6 gap-1 px-2 text-xs border rounded-full bg-n-slate-4 border-n-weak text-n-slate-12 hover:bg-n-slate-5"
      :class="row.mine ? 'border-n-brand' : ''"
      @click="onClick(row)"
    >
      <span class="text-sm leading-none">{{ row.emoji }}</span>
      <span v-if="row.names.length > 1">{{ row.names.length }}</span>
    </button>
  </div>
</template>
