<script setup>
import { ref } from 'vue';
import Draggable from 'vuedraggable';

const props = defineProps({
  node: { type: Object, required: true },
  level: { type: Number, default: 0 },
  actions: { type: Object, required: true }, // { addChild, rename, toggle, remove, reorderChildren }
});

// 产品分组管理：递归编辑一个节点 + 其子树（不限层级）。重命名/加子项/显隐/删除/同级拖拽。
// 所有写操作走 actions（由管理器注入，集中调 API + 重载），本组件只管交互与本地输入态。
defineOptions({ name: 'MesProductGroupEditNode' });

const renaming = ref(false);
const renameText = ref('');
const addingChild = ref(false);
const childText = ref('');

const startRename = () => {
  renameText.value = props.node.name;
  renaming.value = true;
};
const saveRename = () => {
  const name = renameText.value.trim();
  renaming.value = false;
  if (name && name !== props.node.name)
    props.actions.rename(props.node.id, name);
};
const startAddChild = () => {
  childText.value = '';
  addingChild.value = true;
};
const saveChild = () => {
  const name = childText.value.trim();
  if (!name) return;
  props.actions.addChild(props.node.id, name);
  addingChild.value = false;
  childText.value = '';
};
</script>

<template>
  <div>
    <div
      class="flex items-center gap-2 py-2 pr-2 border-b border-n-weak"
      :style="{ paddingLeft: `${level * 18 + 4}px` }"
    >
      <span
        class="cursor-move drag-handle i-lucide-grip-vertical size-4 text-n-slate-9 shrink-0"
      />
      <input
        v-if="renaming"
        v-model="renameText"
        class="flex-1 h-8 px-2 text-sm border rounded-lg border-white/70 bg-n-solid-1/70 text-n-slate-12"
        @keyup.enter="saveRename"
        @blur="saveRename"
      />
      <span
        v-else
        class="flex-1 text-sm truncate"
        :class="node.active ? 'text-n-slate-12' : 'text-n-slate-9 line-through'"
      >
        {{ node.name }}
      </span>
      <button
        class="p-1 rounded text-n-slate-10 hover:bg-n-alpha-1"
        title="添加子项"
        @click="startAddChild"
      >
        <span class="i-lucide-plus size-4" />
      </button>
      <button
        class="p-1 rounded text-n-slate-10 hover:bg-n-alpha-1"
        title="重命名"
        @click="startRename"
      >
        <span class="i-lucide-pencil size-4" />
      </button>
      <button
        class="p-1 rounded text-n-slate-10 hover:bg-n-alpha-1"
        :title="node.active ? '隐藏' : '显示'"
        @click="actions.toggle(node)"
      >
        <span
          class="size-4"
          :class="node.active ? 'i-lucide-eye' : 'i-lucide-eye-off'"
        />
      </button>
      <button
        class="p-1 rounded text-n-ruby-10 hover:bg-n-ruby-2"
        title="删除"
        @click="actions.remove(node)"
      >
        <span class="i-lucide-trash-2 size-4" />
      </button>
    </div>

    <!-- 添加子项输入 -->
    <div
      v-if="addingChild"
      class="flex items-center gap-2 py-2 pr-2 border-b border-n-weak"
      :style="{ paddingLeft: `${(level + 1) * 18 + 4}px` }"
    >
      <input
        v-model="childText"
        class="flex-1 h-8 px-2 text-sm border rounded-lg border-white/70 bg-n-solid-1/70 text-n-slate-12"
        placeholder="子分组名称"
        @keyup.enter="saveChild"
      />
      <button
        class="h-8 px-3 text-sm text-white rounded-lg shadow-sm bg-gradient-to-br from-n-iris-9 to-n-accent-grad hover:opacity-90"
        @click="saveChild"
      >
        添加
      </button>
      <button
        class="h-8 px-2 text-sm rounded text-n-slate-11 hover:bg-n-alpha-1"
        @click="addingChild = false"
      >
        取消
      </button>
    </div>

    <!-- 子树：同级可拖拽排序（:list 就地改数组，避免 v-model 改 prop 告警）-->
    <Draggable
      v-if="node.children && node.children.length"
      :list="node.children"
      item-key="id"
      handle=".drag-handle"
      @end="actions.reorderChildren(node)"
    >
      <template #item="{ element: child }">
        <MesProductGroupEditNode
          :node="child"
          :level="level + 1"
          :actions="actions"
        />
      </template>
    </Draggable>
  </div>
</template>
