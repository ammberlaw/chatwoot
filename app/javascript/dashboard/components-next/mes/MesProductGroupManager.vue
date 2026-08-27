<script setup>
import { ref } from 'vue';
import Draggable from 'vuedraggable';
import { useAlert } from 'dashboard/composables';
import ProductGroupsAPI from 'dashboard/api/mes/productGroups';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import MesProductGroupEditNode from './MesProductGroupEditNode.vue';

// 产品分组树管理：不限层级，重命名/加子项/显隐/删除/同级拖拽，改动即时保存。
// 关闭时通知父级刷新侧栏与下拉。
const emit = defineEmits(['updated']);

const dialogRef = ref(null);
const tree = ref([]);
const loading = ref(false);
const newRootName = ref('');

// 扁平列表 → 树。
const buildTree = list => {
  const byId = new Map(list.map(i => [i.id, { ...i, children: [] }]));
  const roots = [];
  list.forEach(i => {
    const node = byId.get(i.id);
    if (i.parent_id && byId.has(i.parent_id)) {
      byId.get(i.parent_id).children.push(node);
    } else {
      roots.push(node);
    }
  });
  const sortRec = nodes => {
    nodes.sort((a, b) => a.position - b.position);
    nodes.forEach(n => sortRec(n.children));
  };
  sortRec(roots);
  tree.value = roots;
};

const load = async () => {
  loading.value = true;
  try {
    const { data } = await ProductGroupsAPI.get();
    buildTree(data.payload || []);
  } catch (e) {
    useAlert(e?.response?.data?.message || '加载失败');
  } finally {
    loading.value = false;
  }
};

const run = async (fn, okMsg) => {
  try {
    await fn();
    await load();
    emit('updated');
    if (okMsg) useAlert(okMsg);
  } catch (e) {
    useAlert(e?.response?.data?.message || '操作失败');
  }
};

const actions = {
  addChild: (parentId, name) =>
    run(() => ProductGroupsAPI.createItem({ name, parent_id: parentId })),
  rename: (id, name) => run(() => ProductGroupsAPI.updateItem(id, { name })),
  toggle: node =>
    run(() => ProductGroupsAPI.updateItem(node.id, { active: !node.active })),
  remove: node => {
    const extra = node.children?.length ? '，其下子分组将一并删除' : '';
    // eslint-disable-next-line no-alert
    if (!window.confirm(`确定删除「${node.name}」${extra}？`)) return;
    run(() => ProductGroupsAPI.deleteItem(node.id));
  },
  reorderChildren: node =>
    run(() => ProductGroupsAPI.reorder(node.children.map(c => c.id))),
};

const addRoot = () => {
  const name = newRootName.value.trim();
  if (!name) return;
  run(() => ProductGroupsAPI.createItem({ name })).then(() => {
    newRootName.value = '';
  });
};

const onReorderRoots = () =>
  run(() => ProductGroupsAPI.reorder(tree.value.map(r => r.id)));

const open = () => {
  load();
  dialogRef.value?.open();
};
defineExpose({ open });
</script>

<template>
  <Dialog
    :dismissible="false"
    ref="dialogRef"
    width="2xl"
    overflow-y-auto
    title="产品分组管理"
    description="不限层级：可加一级分组，任意节点下加子分组；支持重命名、隐藏、删除、同级拖拽排序。改动即时保存。"
    :show-cancel-button="false"
    confirm-button-label="完成"
    confirm-button-color="iris"
    @confirm="() => dialogRef?.close()"
  >
    <div v-if="loading" class="py-10 text-sm text-center text-n-slate-10">
      加载中…
    </div>
    <template v-else>
      <div class="border rounded-2xl border-white/70 bg-n-solid-1/50">
        <Draggable
          v-model="tree"
          item-key="id"
          handle=".drag-handle"
          @end="onReorderRoots"
        >
          <template #item="{ element: root }">
            <MesProductGroupEditNode
              :node="root"
              :level="0"
              :actions="actions"
            />
          </template>
        </Draggable>
        <div
          v-if="!tree.length"
          class="py-8 text-sm text-center text-n-slate-10"
        >
          还没有分组，在下方添加第一个一级分组。
        </div>
      </div>

      <div class="flex items-center gap-2 mt-4">
        <input
          v-model="newRootName"
          class="flex-1 px-3 text-sm border rounded-lg h-9 border-white/70 bg-n-solid-1/70 text-n-slate-12"
          placeholder="新增一级分组名称"
          @keyup.enter="addRoot"
        />
        <button
          class="px-4 text-sm text-white rounded-lg shadow-sm h-9 bg-gradient-to-br from-n-iris-9 to-n-accent-grad hover:opacity-90"
          @click="addRoot"
        >
          添加
        </button>
      </div>
    </template>
  </Dialog>
</template>
