<script setup>
import { ref, onMounted } from 'vue';
import Draggable from 'vuedraggable';
import { useAlert } from 'dashboard/composables';
import OptionItemsAPI from 'dashboard/api/crm/optionItems';
import { useCrmOptions } from 'dashboard/composables/useCrmOptions';

// 客户设置：客户分组 / 客户来源 的自定义项（二级层级 + 显隐 + 拖拽排序）。
// 页面与侧栏入口已按 isAdminLike 限定；写操作后端 policy 再次校验管理员/副管理员。
const TABS = [
  { key: 'customer_group', label: '分组设置' },
  { key: 'customer_source', label: '客户来源' },
];

const activeTab = ref('customer_group');
const tree = ref([]); // [{ ...root, children: [...] }]
const loading = ref(false);
const editing = ref({ id: null, name: '' });
const newRootName = ref('');
const addingChildFor = ref(null);
const newChildName = ref('');

const { refresh } = useCrmOptions();

const buildTree = list => {
  const roots = list
    .filter(i => !i.parent_id)
    .sort((a, b) => a.position - b.position);
  tree.value = roots.map(root => ({
    ...root,
    children: list
      .filter(i => i.parent_id === root.id)
      .sort((a, b) => a.position - b.position),
  }));
};

const load = async () => {
  loading.value = true;
  try {
    const { data } = await OptionItemsAPI.get(activeTab.value);
    buildTree(data.payload || []);
  } catch (e) {
    useAlert(e?.response?.data?.message || '加载失败');
  } finally {
    loading.value = false;
  }
};

// 增删改后重取并同步全站下拉缓存。
const reloadAndSync = async () => {
  await load();
  refresh(activeTab.value);
};

const switchTab = key => {
  activeTab.value = key;
  editing.value = { id: null, name: '' };
  addingChildFor.value = null;
  load();
};

const run = async (fn, okMsg) => {
  try {
    await fn();
    await reloadAndSync();
    if (okMsg) useAlert(okMsg);
  } catch (e) {
    useAlert(e?.response?.data?.message || '操作失败');
  }
};

const addRoot = () => {
  const name = newRootName.value.trim();
  if (!name) return;
  run(async () => {
    await OptionItemsAPI.createItem({ category: activeTab.value, name });
    newRootName.value = '';
  });
};

const startAddChild = root => {
  addingChildFor.value = root.id;
  newChildName.value = '';
};

const addChild = root => {
  const name = newChildName.value.trim();
  if (!name) return;
  run(async () => {
    await OptionItemsAPI.createItem({
      category: activeTab.value,
      name,
      parent_id: root.id,
    });
    addingChildFor.value = null;
    newChildName.value = '';
  });
};

const startEdit = item => {
  editing.value = { id: item.id, name: item.name };
};

const saveEdit = item => {
  const name = editing.value.name.trim();
  editing.value = { id: null, name: '' };
  if (!name || name === item.name) return;
  run(() => OptionItemsAPI.updateItem(item.id, { name }));
};

const toggleActive = item =>
  run(() => OptionItemsAPI.updateItem(item.id, { active: !item.active }));

const remove = item => {
  const extra = item.children?.length ? '，其下子项将一并删除' : '';
  // eslint-disable-next-line no-alert
  if (!window.confirm(`确定删除「${item.name}」${extra}？`)) return;
  run(() => OptionItemsAPI.deleteItem(item.id));
};

const onReorderRoots = () =>
  run(() => OptionItemsAPI.reorder(tree.value.map(r => r.id)));

const onReorderChildren = root =>
  run(() => OptionItemsAPI.reorder(root.children.map(c => c.id)));

onMounted(load);
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div class="w-full max-w-3xl px-4 py-4 mx-auto sm:px-8 sm:py-6">
      <h1 class="mb-1 text-[22px] font-bold tracking-[-0.01em] text-n-slate-12">
        客户设置
      </h1>
      <p class="mb-5 text-sm text-n-slate-11">
        自定义客户分组与客户来源（支持二级、拖拽排序、隐藏）。仅管理员可维护。
      </p>

      <!-- Tabs -->
      <div
        class="flex gap-1 mb-5 border-b border-n-weak"
        data-tabbar="page"
        data-tabbar-theme="classic"
      >
        <button
          v-for="tab in TABS"
          :key="tab.key"
          :aria-selected="activeTab === tab.key"
          class="px-4 py-2 -mb-px text-sm border-b-2"
          :class="
            activeTab === tab.key
              ? 'border-n-iris-9 text-n-iris-11 font-medium'
              : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
          "
          @click="switchTab(tab.key)"
        >
          {{ tab.label }}
        </button>
      </div>

      <div v-if="loading" class="py-10 text-sm text-center text-n-slate-10">
        加载中…
      </div>

      <template v-else>
        <!-- 一级项拖拽列表 -->
        <Draggable
          v-model="tree"
          item-key="id"
          handle=".root-handle"
          class="flex flex-col gap-2"
          @end="onReorderRoots"
        >
          <template #item="{ element: root }">
            <div
              class="border border-white/70 rounded-2xl bg-n-solid-1/60 shadow-sm"
            >
              <!-- 一级行 -->
              <div class="flex items-center gap-2 px-3 py-2.5">
                <span
                  class="cursor-move root-handle i-lucide-grip-vertical size-4 text-n-slate-9 shrink-0"
                />
                <template v-if="editing.id === root.id">
                  <input
                    v-model="editing.name"
                    class="flex-1 h-8 px-2 text-sm border rounded-lg border-white/70 bg-n-solid-1/70 text-n-slate-12"
                    @keyup.enter="saveEdit(root)"
                    @blur="saveEdit(root)"
                  />
                </template>
                <span
                  v-else
                  class="flex-1 text-sm font-medium truncate"
                  :class="
                    root.active
                      ? 'text-n-slate-12'
                      : 'text-n-slate-9 line-through'
                  "
                >
                  {{ root.name }}
                </span>
                <button
                  class="p-1 rounded text-n-slate-10 hover:bg-n-alpha-1"
                  title="添加子项"
                  @click="startAddChild(root)"
                >
                  <span class="i-lucide-plus size-4" />
                </button>
                <button
                  class="p-1 rounded text-n-slate-10 hover:bg-n-alpha-1"
                  title="重命名"
                  @click="startEdit(root)"
                >
                  <span class="i-lucide-pencil size-4" />
                </button>
                <button
                  class="p-1 rounded text-n-slate-10 hover:bg-n-alpha-1"
                  :title="root.active ? '隐藏' : '显示'"
                  @click="toggleActive(root)"
                >
                  <span
                    class="size-4"
                    :class="root.active ? 'i-lucide-eye' : 'i-lucide-eye-off'"
                  />
                </button>
                <button
                  class="p-1 rounded text-n-ruby-10 hover:bg-n-ruby-2"
                  title="删除"
                  @click="remove(root)"
                >
                  <span class="i-lucide-trash-2 size-4" />
                </button>
              </div>

              <!-- 子项拖拽列表 -->
              <Draggable
                v-if="root.children.length"
                v-model="root.children"
                item-key="id"
                handle=".child-handle"
                class="flex flex-col border-t border-n-weak"
                @end="onReorderChildren(root)"
              >
                <template #item="{ element: child }">
                  <div
                    class="flex items-center gap-2 py-2 pl-8 pr-3 border-b last:border-b-0 border-n-weak"
                  >
                    <span
                      class="cursor-move child-handle i-lucide-grip-vertical size-4 text-n-slate-9 shrink-0"
                    />
                    <template v-if="editing.id === child.id">
                      <input
                        v-model="editing.name"
                        class="flex-1 h-8 px-2 text-sm border rounded-lg border-white/70 bg-n-solid-1/70 text-n-slate-12"
                        @keyup.enter="saveEdit(child)"
                        @blur="saveEdit(child)"
                      />
                    </template>
                    <span
                      v-else
                      class="flex-1 text-sm truncate"
                      :class="
                        child.active
                          ? 'text-n-slate-11'
                          : 'text-n-slate-9 line-through'
                      "
                    >
                      {{ child.name }}
                    </span>
                    <button
                      class="p-1 rounded text-n-slate-10 hover:bg-n-alpha-1"
                      title="重命名"
                      @click="startEdit(child)"
                    >
                      <span class="i-lucide-pencil size-4" />
                    </button>
                    <button
                      class="p-1 rounded text-n-slate-10 hover:bg-n-alpha-1"
                      :title="child.active ? '隐藏' : '显示'"
                      @click="toggleActive(child)"
                    >
                      <span
                        class="size-4"
                        :class="
                          child.active ? 'i-lucide-eye' : 'i-lucide-eye-off'
                        "
                      />
                    </button>
                    <button
                      class="p-1 rounded text-n-ruby-10 hover:bg-n-ruby-2"
                      title="删除"
                      @click="remove(child)"
                    >
                      <span class="i-lucide-trash-2 size-4" />
                    </button>
                  </div>
                </template>
              </Draggable>

              <!-- 添加子项输入 -->
              <div
                v-if="addingChildFor === root.id"
                class="flex items-center gap-2 py-2 pl-8 pr-3 border-t border-n-weak"
              >
                <input
                  v-model="newChildName"
                  class="flex-1 h-8 px-2 text-sm border rounded-lg border-white/70 bg-n-solid-1/70 text-n-slate-12"
                  placeholder="子项名称"
                  @keyup.enter="addChild(root)"
                />
                <button
                  class="h-8 px-3 text-sm text-white rounded-lg bg-gradient-to-br from-n-iris-9 to-n-accent-grad shadow-sm hover:opacity-90"
                  @click="addChild(root)"
                >
                  添加
                </button>
                <button
                  class="h-8 px-2 text-sm rounded text-n-slate-11 hover:bg-n-alpha-1"
                  @click="addingChildFor = null"
                >
                  取消
                </button>
              </div>
            </div>
          </template>
        </Draggable>

        <!-- 添加一级项 -->
        <div class="flex items-center gap-2 mt-4">
          <input
            v-model="newRootName"
            class="flex-1 h-9 px-3 text-sm border rounded-lg border-white/70 bg-n-solid-1/70 text-n-slate-12"
            :placeholder="
              activeTab === 'customer_group'
                ? '新增一级分组名称'
                : '新增来源名称'
            "
            @keyup.enter="addRoot"
          />
          <button
            class="h-9 px-4 text-sm text-white rounded-lg bg-gradient-to-br from-n-iris-9 to-n-accent-grad shadow-sm hover:opacity-90"
            @click="addRoot"
          >
            添加
          </button>
        </div>
      </template>
    </div>
  </div>
</template>
