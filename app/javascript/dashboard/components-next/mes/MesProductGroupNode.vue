<script setup>
import { ref } from 'vue';

const props = defineProps({
  node: { type: Object, required: true }, // { id, code, name, active, children: [] }
  selected: { type: String, default: '' },
  level: { type: Number, default: 0 },
});

const emit = defineEmits(['select']);

// 产品分组侧栏筛选：递归渲染一个节点 + 其子树（不限层级）。只读、可点选、可折叠。
defineOptions({ name: 'MesProductGroupNode' });

const expanded = ref(true);
const hasChildren = () => (props.node.children?.length || 0) > 0;
</script>

<template>
  <div>
    <button
      type="button"
      class="flex items-center w-full gap-1 py-1.5 pr-2 text-sm text-left rounded-lg hover:bg-n-alpha-1"
      :class="
        selected === node.code
          ? 'bg-n-iris-3 text-n-iris-11 font-medium'
          : 'text-n-slate-12'
      "
      :style="{ paddingLeft: `${level * 14 + 8}px` }"
      @click="emit('select', node.code)"
    >
      <span
        v-if="hasChildren()"
        class="transition-transform i-lucide-chevron-right size-3.5 shrink-0 text-n-slate-10"
        :class="expanded ? 'rotate-90' : ''"
        @click.stop="expanded = !expanded"
      />
      <span v-else class="size-3.5 shrink-0" />
      <span class="truncate" :class="node.active ? '' : 'text-n-slate-9'">
        {{ node.name }}
      </span>
    </button>
    <template v-if="expanded && hasChildren()">
      <MesProductGroupNode
        v-for="child in node.children"
        :key="child.id"
        :node="child"
        :selected="selected"
        :level="level + 1"
        @select="c => emit('select', c)"
      />
    </template>
  </div>
</template>
