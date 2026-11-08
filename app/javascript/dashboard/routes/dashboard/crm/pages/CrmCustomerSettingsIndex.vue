<script setup>
import { useI18n } from 'vue-i18n';
import CrmSettingsLayout from 'dashboard/components-next/CRM/CrmSettingsLayout.vue';
import { ref, onMounted } from 'vue';
import Draggable from 'vuedraggable';
import { useAlert } from 'dashboard/composables';
import OptionItemsAPI from 'dashboard/api/crm/optionItems';
import { useCrmOptions } from 'dashboard/composables/useCrmOptions';

// 客户设置：客户分组 / 客户来源 的自定义项（二级层级 + 显隐 + 拖拽排序）。
// 页面与侧栏入口已按 isAdminLike 限定；写操作后端 policy 再次校验管理员/副管理员。
const { t } = useI18n();
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
  <CrmSettingsLayout
    width="narrow"
    :title="t('CRM.SETTINGS_PAGE.CUSTOMER')"
    :description="t('CRM.SETTINGS_PAGE.CUSTOMER_NOTE')"
  >
    <template #toolbar
      ><nav
        class="flex w-fit max-w-full gap-1 overflow-x-auto rounded-xl bg-n-alpha-2 p-1"
        :aria-label="t('CRM.SETTINGS_PAGE.CUSTOMER')"
      >
        <button
          v-for="tab in TABS"
          :key="tab.key"
          type="button"
          :aria-pressed="activeTab === tab.key"
          class="min-h-10 shrink-0 rounded-lg px-4 text-label transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-slate-10"
          :class="
            activeTab === tab.key
              ? 'bg-n-slate-12 text-n-solid-1 shadow-sm'
              : 'text-n-slate-11 hover:bg-n-alpha-2'
          "
          @click="switchTab(tab.key)"
        >
          {{ tab.label }}
        </button>
      </nav></template
    >
    <div v-if="loading" class="py-10 text-label text-center text-n-slate-10">
      {{ t('CRM.SETTINGS_COPY.CUSTOMERSETTINGS_1') }}
    </div>

    <template v-else>
      <!-- 添加一级项 -->
      <div class="mb-4 flex items-center gap-3">
        <input
          v-model="newRootName"
          class="min-w-0 flex-1 h-9 px-3 text-label border rounded-lg border-n-weak bg-n-alpha-1 text-n-slate-12"
          :placeholder="
            activeTab === 'customer_group' ? '新增一级分组名称' : '新增来源名称'
          "
          @keyup.enter="addRoot"
        />
        <button
          class="h-9 px-4 text-label rounded-xl bg-wintouch-yellow text-wintouch-ink hover:enabled:bg-wintouch-yellow-hover focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-wintouch-ink/50 transition-colors duration-150"
          @click="addRoot"
        >
          {{ t('CRM.SETTINGS_COPY.CUSTOMERSETTINGS_2') }}
        </button>
      </div>

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
            class="overflow-hidden rounded-2xl border border-n-weak bg-n-solid-1"
          >
            <!-- 一级行 -->
            <div class="flex min-h-12 items-center gap-2 px-4 py-2">
              <span
                class="cursor-move root-handle i-lucide-grip-vertical size-4 text-n-slate-9 shrink-0"
              />
              <template v-if="editing.id === root.id">
                <input
                  v-model="editing.name"
                  class="min-w-0 flex-1 h-8 px-2 text-label border rounded-lg border-n-weak bg-n-alpha-1 text-n-slate-12"
                  @keyup.enter="saveEdit(root)"
                  @blur="saveEdit(root)"
                />
              </template>
              <span
                v-else
                class="flex-1 text-label font-medium truncate"
                :class="
                  root.active
                    ? 'text-n-slate-12'
                    : 'text-n-slate-9 line-through'
                "
              >
                {{ root.name }}
              </span>
              <button
                class="grid size-9 shrink-0 place-items-center rounded-lg text-n-slate-10 hover:bg-n-alpha-1"
                :title="t('CRM.SETTINGS_COPY.CUSTOMERSETTINGS_3')"
                @click="startAddChild(root)"
              >
                <span class="i-lucide-plus size-4" />
              </button>
              <button
                class="grid size-9 shrink-0 place-items-center rounded-lg text-n-slate-10 hover:bg-n-alpha-1"
                :title="t('CRM.SETTINGS_COPY.CUSTOMERSETTINGS_4')"
                @click="startEdit(root)"
              >
                <span class="i-lucide-pencil size-4" />
              </button>
              <button
                class="grid size-9 shrink-0 place-items-center rounded-lg text-n-slate-10 hover:bg-n-alpha-1"
                :title="root.active ? '隐藏' : '显示'"
                @click="toggleActive(root)"
              >
                <span
                  class="size-4"
                  :class="root.active ? 'i-lucide-eye' : 'i-lucide-eye-off'"
                />
              </button>
              <button
                class="grid size-9 shrink-0 place-items-center rounded-lg text-n-ruby-10 hover:bg-n-ruby-2"
                :title="t('CRM.SETTINGS_COPY.CUSTOMERSETTINGS_5')"
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
                      class="min-w-0 flex-1 h-8 px-2 text-label border rounded-lg border-n-weak bg-n-alpha-1 text-n-slate-12"
                      @keyup.enter="saveEdit(child)"
                      @blur="saveEdit(child)"
                    />
                  </template>
                  <span
                    v-else
                    class="flex-1 text-label truncate"
                    :class="
                      child.active
                        ? 'text-n-slate-11'
                        : 'text-n-slate-9 line-through'
                    "
                  >
                    {{ child.name }}
                  </span>
                  <button
                    class="grid size-9 shrink-0 place-items-center rounded-lg text-n-slate-10 hover:bg-n-alpha-1"
                    :title="t('CRM.SETTINGS_COPY.CUSTOMERSETTINGS_4')"
                    @click="startEdit(child)"
                  >
                    <span class="i-lucide-pencil size-4" />
                  </button>
                  <button
                    class="grid size-9 shrink-0 place-items-center rounded-lg text-n-slate-10 hover:bg-n-alpha-1"
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
                    class="grid size-9 shrink-0 place-items-center rounded-lg text-n-ruby-10 hover:bg-n-ruby-2"
                    :title="t('CRM.SETTINGS_COPY.CUSTOMERSETTINGS_5')"
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
                class="min-w-0 flex-1 h-8 px-2 text-label border rounded-lg border-n-weak bg-n-alpha-1 text-n-slate-12"
                :placeholder="t('CRM.SETTINGS_COPY.CUSTOMERSETTINGS_6')"
                @keyup.enter="addChild(root)"
              />
              <button
                class="h-8 px-3 text-label rounded-xl bg-wintouch-yellow text-wintouch-ink hover:enabled:bg-wintouch-yellow-hover focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-wintouch-ink/50 transition-colors duration-150"
                @click="addChild(root)"
              >
                {{ t('CRM.SETTINGS_COPY.CUSTOMERSETTINGS_2') }}
              </button>
              <button
                class="h-8 px-2 text-label rounded text-n-slate-11 hover:bg-n-alpha-1"
                @click="addingChildFor = null"
              >
                {{ t('CRM.SETTINGS_COPY.CUSTOMERSETTINGS_7') }}
              </button>
            </div>
          </div>
        </template>
      </Draggable>
    </template>
  </CrmSettingsLayout>
</template>
