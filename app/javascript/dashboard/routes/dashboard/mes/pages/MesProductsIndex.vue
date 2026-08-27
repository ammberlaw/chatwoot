<script setup>
import { ref, computed, reactive, onMounted, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useMesProductsStore } from 'dashboard/stores/mes/products';
import { useMesRole } from 'dashboard/composables/useMesRole';
import {
  MES_PRODUCT_LINES,
  productLineLabel,
} from 'dashboard/composables/useMesProductLine';

import ProductGroupsAPI from 'dashboard/api/mes/productGroups';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import MesProductGroupNode from 'dashboard/components-next/mes/MesProductGroupNode.vue';
import MesProductGroupManager from 'dashboard/components-next/mes/MesProductGroupManager.vue';

const store = useMesProductsStore();
const { mesCan } = useMesRole();

const ITEMS_PER_PAGE = 15;
const records = computed(() => store.getRecords);
const totalCount = computed(() => store.getMeta.count || 0);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const saving = computed(
  () => store.getUIFlags.creatingItem || store.getUIFlags.updatingItem
);
// 仅工程与 PMC（及管理员）可增删改产品编码。
const canManage = computed(() => mesCan('product'));

// SKU 编码分类（按仓别），与供应商供应物料/物料档案共用同一套值。
const CATEGORIES = [
  { value: 'FINISHED', label: '成品仓' },
  { value: 'SEMI', label: '半成品仓' },
  { value: 'RAW_MAIN', label: '原材料仓·主料' },
  { value: 'RAW_AUX', label: '原材料仓·辅料' },
  { value: 'DEFECTIVE', label: '不良品仓' },
];
// 旧分类仅用于显示存量数据（编辑时可改成新分类）。
const LEGACY_CATEGORIES = [
  { value: 'STANDARD', label: '标准品' },
  { value: 'CUSTOMIZED', label: '定制品' },
  { value: 'ACCESSORY', label: '配件' },
  { value: 'OTHER', label: '其他' },
];
const categoryLabel = v =>
  [...CATEGORIES, ...LEGACY_CATEGORIES].find(c => c.value === v)?.label || '—';

// 产品线：只能是某条具体线或不指定（不含「全部」筛选项）。
const productLineOptions = [
  { value: '', label: '未指定' },
  ...MES_PRODUCT_LINES.filter(o => o.value),
];

const keyword = ref('');
const categoryFilter = ref('');
const categoryFilterOptions = [{ value: '', label: '全部分类' }, ...CATEGORIES];
const currentPage = ref(1);

// —— 产品分组树（不限层级）——
const groups = ref([]); // 扁平列表 [{id, code, name, parent_id, position, active}]
const selectedGroup = ref(''); // 当前筛选分组 code（''=全部）
const managerRef = ref(null);

const buildGroupTree = list => {
  const byId = new Map(list.map(i => [i.id, { ...i, children: [] }]));
  const roots = [];
  list.forEach(i => {
    const node = byId.get(i.id);
    if (i.parent_id && byId.has(i.parent_id))
      byId.get(i.parent_id).children.push(node);
    else roots.push(node);
  });
  const sortRec = nodes => {
    nodes.sort((a, b) => a.position - b.position);
    nodes.forEach(n => sortRec(n.children));
  };
  sortRec(roots);
  return roots;
};
const groupTree = computed(() => buildGroupTree(groups.value));
const groupLabelByCode = computed(() =>
  Object.fromEntries(groups.value.map(g => [g.code, g.name]))
);
const loadGroups = async () => {
  const { data } = await ProductGroupsAPI.get();
  groups.value = data.payload || [];
};

const load = () =>
  store.get({
    page: currentPage.value,
    per_page: ITEMS_PER_PAGE,
    q: keyword.value.trim() || undefined,
    category: categoryFilter.value || undefined,
    group_code: selectedGroup.value || undefined,
  });
// 翻页触发重拉；搜索/筛选先回到第 1 页（页码变则由 watch 拉，未变则直接拉）。
watch(currentPage, load);
const reload = () => {
  if (currentPage.value !== 1) currentPage.value = 1;
  else load();
};
const changeCategoryFilter = v => {
  categoryFilter.value = v;
  reload();
};
const selectGroup = code => {
  selectedGroup.value = selectedGroup.value === code ? '' : code;
  reload();
};

const dialogRef = ref(null);
const editingId = ref(null);
const form = reactive({
  name: '',
  sku: '',
  productLine: '',
  category: '',
  sourceCategory: '',
  unit: '',
  specification: '',
  remark: '',
  groupCode: '',
  isActive: true,
});
const invalid = computed(() => !form.name.trim() || !form.sku.trim());

// 表单分类选项：新五档；正在编辑的存量产品若还是旧分类，附带显示旧值以免下拉空白。
const categoryOptions = computed(() => {
  const opts = [{ value: '', label: '未分类' }, ...CATEGORIES];
  const legacy = LEGACY_CATEGORIES.find(c => c.value === form.category);
  if (legacy) opts.push({ ...legacy, label: `${legacy.label}（旧）` });
  return opts;
});

// 表单分组下拉：拍平成「一级 / 二级 / 三级」全路径缩进项（隐藏项不列，编辑时保留当前值）。
const groupSelectOptions = computed(() => {
  const opts = [{ value: '', label: '未分组' }];
  const walk = (nodes, prefix) => {
    nodes.forEach(n => {
      const path = prefix ? `${prefix} / ${n.name}` : n.name;
      if (n.active || n.code === form.groupCode)
        opts.push({ value: n.code, label: path });
      walk(n.children, path);
    });
  };
  walk(groupTree.value, '');
  return opts;
});

const openCreate = () => {
  editingId.value = null;
  Object.assign(form, {
    name: '',
    sku: '',
    productLine: '',
    category: '',
    sourceCategory: '',
    unit: '',
    specification: '',
    remark: '',
    groupCode: selectedGroup.value || '',
    isActive: true,
  });
  dialogRef.value?.open();
};
const openEdit = p => {
  editingId.value = p.id;
  Object.assign(form, {
    name: p.name || '',
    sku: p.sku || '',
    productLine: p.productLine || '',
    category: p.category || '',
    sourceCategory: p.sourceCategory || '',
    unit: p.unit || '',
    specification: p.specification || '',
    remark: p.remark || '',
    groupCode: p.groupCode || '',
    isActive: p.isActive !== false,
  });
  dialogRef.value?.open();
};

const submit = async () => {
  if (invalid.value) return;
  const payload = {
    name: form.name.trim(),
    sku: form.sku.trim(),
    productLine: form.productLine || null,
    category: form.category || null,
    sourceCategory: form.sourceCategory.trim() || null,
    unit: form.unit.trim() || null,
    specification: form.specification.trim() || null,
    remark: form.remark.trim() || null,
    groupCode: form.groupCode || null,
    isActive: form.isActive,
  };
  try {
    const ok = editingId.value
      ? await store.update({ id: editingId.value, ...payload })
      : await store.create(payload);
    if (ok) {
      useAlert(editingId.value ? '产品已更新' : `已新增产品 ${ok.sku}`);
      dialogRef.value?.close();
    }
  } catch (error) {
    useAlert(error?.message || '保存失败，请检查填写内容');
  }
};

// 禁用/启用：改 is_active，不删数据（保住 BOM/采购/出库的引用）。
const toggleActive = async p => {
  const ok = await store.update({ id: p.id, isActive: !p.isActive });
  if (ok) useAlert(ok.isActive ? '已启用' : '已禁用');
};

const confirmRef = ref(null);
const deleting = ref(null);
const askDelete = p => {
  deleting.value = p;
  confirmRef.value?.open();
};
const doDelete = async () => {
  if (!deleting.value) return;
  const ok = await store.delete(deleting.value.id);
  if (ok) useAlert('产品已删除');
  confirmRef.value?.close();
  deleting.value = null;
};

onMounted(() => {
  load();
  loadGroups();
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div
      class="flex flex-col gap-3 px-4 py-3 sm:px-6 sm:py-4 md:flex-row md:items-center md:justify-between"
    >
      <div class="flex items-baseline gap-2">
        <h1 class="text-xl font-semibold text-n-slate-12">产品档案</h1>
        <span class="text-sm text-n-slate-11">共 {{ totalCount }} 条</span>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <SelectCard
          :model-value="categoryFilter"
          :options="categoryFilterOptions"
          class="w-full sm:w-44"
          @update:model-value="changeCategoryFilter"
        />
        <input
          v-model="keyword"
          placeholder="搜索编码 / 名称 / 规格 / 类别"
          class="h-9 px-3 text-sm rounded-lg outline-none w-full sm:w-56 border border-n-weak bg-n-solid-1 text-n-slate-12"
          @keyup.enter="reload"
        />
        <Button
          label="搜索"
          variant="outline"
          color="slate"
          size="sm"
          @click="reload"
        />
        <Button
          v-if="canManage"
          label="新增产品"
          color="iris"
          size="sm"
          @click="openCreate"
        />
      </div>
    </div>

    <div class="flex flex-1 min-h-0">
      <!-- 左侧分组树（不限层级）：点节点连带子树筛选 -->
      <aside
        class="flex-col hidden gap-1 px-2 py-3 overflow-y-auto border-r md:flex w-52 shrink-0 border-n-weak"
      >
        <div class="flex items-center justify-between px-2 mb-1">
          <span class="text-xs font-medium text-n-slate-11">产品分组</span>
          <button
            v-if="canManage"
            class="text-xs text-n-iris-11 hover:underline"
            @click="managerRef?.open()"
          >
            管理
          </button>
        </div>
        <button
          type="button"
          class="flex items-center w-full gap-1 px-2 py-1.5 text-sm text-left rounded-lg hover:bg-n-alpha-1"
          :class="
            selectedGroup === ''
              ? 'bg-n-iris-3 text-n-iris-11 font-medium'
              : 'text-n-slate-12'
          "
          @click="selectGroup('')"
        >
          全部
        </button>
        <MesProductGroupNode
          v-for="node in groupTree"
          :key="node.id"
          :node="node"
          :selected="selectedGroup"
          @select="selectGroup"
        />
        <p
          v-if="!groupTree.length && canManage"
          class="px-2 mt-2 text-xs text-n-slate-10"
        >
          还没有分组，点「管理」新建。
        </p>
      </aside>

      <div class="flex-1 min-h-0 px-4 pb-6 overflow-auto sm:px-6">
        <p v-if="!canManage" class="mb-3 text-xs text-n-slate-11">
          产品编码由工程 / PMC 维护，你当前为只读。
        </p>
        <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
          加载中…
        </div>
        <template v-else>
          <!-- 手机卡片列表 -->
          <div class="flex flex-col gap-2 md:hidden">
            <div
              v-for="p in records"
              :key="p.id"
              class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl active:bg-n-alpha-1"
              @click="canManage && openEdit(p)"
            >
              <div class="flex items-center gap-2">
                <span class="font-medium text-n-slate-12 truncate">
                  {{ p.name }}
                </span>
                <span
                  class="shrink-0 px-2 py-0.5 text-xs rounded-full"
                  :class="
                    p.isActive
                      ? 'bg-n-teal-3 text-n-teal-12'
                      : 'bg-n-slate-4 text-n-slate-11'
                  "
                >
                  {{ p.isActive ? '启用' : '已禁用' }}
                </span>
                <span class="flex-1" />
                <div v-if="canManage" class="flex shrink-0 gap-1">
                  <Button
                    :label="p.isActive ? '禁用' : '启用'"
                    variant="ghost"
                    color="slate"
                    size="sm"
                    @click.stop="toggleActive(p)"
                  />
                  <Button
                    label="删除"
                    variant="ghost"
                    color="ruby"
                    size="sm"
                    @click.stop="askDelete(p)"
                  />
                </div>
              </div>
              <div class="mt-1 font-mono text-xs text-n-slate-11">
                {{ p.sku }}
              </div>
              <div
                class="mt-1 flex flex-wrap gap-x-3 gap-y-1 text-xs text-n-slate-11"
              >
                <span>规格：{{ p.specification || '—' }}</span>
                <span
                  >产品线：{{ productLineLabel(p.productLine) || '—' }}</span
                >
              </div>
              <div
                class="mt-1 flex flex-wrap gap-x-3 gap-y-1 text-xs text-n-slate-11"
              >
                <span>分组：{{ groupLabelByCode[p.groupCode] || '—' }}</span>
                <span>商品类别：{{ p.sourceCategory || '—' }}</span>
                <span>仓别分类：{{ categoryLabel(p.category) }}</span>
                <span>单位：{{ p.unit || '—' }}</span>
              </div>
            </div>
            <div
              v-if="!records.length"
              class="py-10 text-center text-n-slate-11"
            >
              还没有产品。
            </div>
          </div>

          <table class="hidden md:table w-full text-sm">
            <thead>
              <tr class="text-left text-n-slate-11 border-b border-n-weak">
                <th class="px-3 py-3 font-medium">商品编码</th>
                <th class="px-3 py-3 font-medium">商品名称</th>
                <th class="px-3 py-3 font-medium">分组</th>
                <th class="px-3 py-3 font-medium">规格</th>
                <th class="px-3 py-3 font-medium">产品线</th>
                <th class="px-3 py-3 font-medium">商品类别</th>
                <th class="px-3 py-3 font-medium">仓别分类</th>
                <th class="px-3 py-3 font-medium">单位</th>
                <th class="px-3 py-3 font-medium">状态</th>
                <th class="px-3 py-3 font-medium text-right">操作</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="p in records"
                :key="p.id"
                class="border-b border-n-weak"
              >
                <td class="px-3 py-3 font-mono text-n-slate-11">{{ p.sku }}</td>
                <td class="px-3 py-3 font-medium text-n-slate-12">
                  {{ p.name }}
                </td>
                <td class="px-3 py-3 text-n-slate-11">
                  {{ groupLabelByCode[p.groupCode] || '—' }}
                </td>
                <td class="px-3 py-3 text-n-slate-11">
                  {{ p.specification || '—' }}
                </td>
                <td class="px-3 py-3 text-n-slate-11">
                  {{ productLineLabel(p.productLine) || '—' }}
                </td>
                <td class="px-3 py-3 text-n-slate-11">
                  {{ p.sourceCategory || '—' }}
                </td>
                <td class="px-3 py-3 text-n-slate-11">
                  {{ categoryLabel(p.category) }}
                </td>
                <td class="px-3 py-3 text-n-slate-11">{{ p.unit || '—' }}</td>
                <td class="px-3 py-3">
                  <span
                    class="px-2 py-0.5 text-xs rounded-full"
                    :class="
                      p.isActive
                        ? 'bg-n-teal-3 text-n-teal-12'
                        : 'bg-n-slate-4 text-n-slate-11'
                    "
                  >
                    {{ p.isActive ? '启用' : '已禁用' }}
                  </span>
                </td>
                <td class="px-3 py-3">
                  <div v-if="canManage" class="flex justify-end gap-1">
                    <Button
                      label="编辑"
                      variant="ghost"
                      size="sm"
                      @click="openEdit(p)"
                    />
                    <Button
                      :label="p.isActive ? '禁用' : '启用'"
                      variant="ghost"
                      color="slate"
                      size="sm"
                      @click="toggleActive(p)"
                    />
                    <Button
                      label="删除"
                      variant="ghost"
                      color="ruby"
                      size="sm"
                      @click="askDelete(p)"
                    />
                  </div>
                  <span v-else class="block text-right text-n-slate-10">—</span>
                </td>
              </tr>
              <tr v-if="!records.length">
                <td colspan="10" class="px-3 py-10 text-center text-n-slate-11">
                  还没有产品。
                </td>
              </tr>
            </tbody>
          </table>
        </template>

        <PaginationFooter
          v-if="totalCount > ITEMS_PER_PAGE"
          :current-page="currentPage"
          :total-items="totalCount"
          :items-per-page="ITEMS_PER_PAGE"
          class="mt-3 !bg-transparent before:!hidden"
          @update:current-page="currentPage = $event"
        />
      </div>
    </div>

    <Dialog
      :dismissible="false"
      ref="dialogRef"
      width="lg"
      confirm-button-color="iris"
      :title="editingId ? '编辑产品' : '新增产品'"
      :is-loading="saving"
      :disable-confirm-button="invalid"
      @confirm="submit"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              商品名称 <span class="text-n-ruby-11">*</span>
            </label>
            <Input v-model="form.name" autofocus />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              商品编码 <span class="text-n-ruby-11">*</span>
            </label>
            <Input v-model="form.sku" placeholder="如 TAB-156" />
          </div>
        </div>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">产品线</label>
            <SelectCard
              size="form"
              :model-value="form.productLine"
              :options="productLineOptions"
              @update:model-value="v => (form.productLine = v)"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">商品类别</label>
            <Input
              v-model="form.sourceCategory"
              placeholder="如 背包屏 / 商显主板"
            />
          </div>
        </div>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">仓别分类</label>
            <SelectCard
              size="form"
              :model-value="form.category"
              :options="categoryOptions"
              @update:model-value="v => (form.category = v)"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">计量单位</label>
            <Input v-model="form.unit" placeholder="台 / 个 / pcs" />
          </div>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">产品分组</label>
          <SelectCard
            block
            :model-value="form.groupCode"
            :options="groupSelectOptions"
            @update:model-value="v => (form.groupCode = v)"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">规格型号</label>
          <Input v-model="form.specification" />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">备注</label>
          <Input v-model="form.remark" />
        </div>
        <label class="flex items-center gap-2 text-heading-3 text-n-slate-12">
          <input v-model="form.isActive" type="checkbox" class="w-4 h-4" />
          启用（取消勾选则禁用，不出现在建单成品下拉）
        </label>
      </div>
    </Dialog>

    <Dialog
      :dismissible="false"
      ref="confirmRef"
      type="alert"
      width="sm"
      confirm-button-color="ruby"
      title="删除产品"
      :description="`确定删除「${deleting?.name || ''}」（${deleting?.sku || ''}）？已关联的 BOM / 采购 / 出库将解除引用。`"
      confirm-label="删除"
      @confirm="doDelete"
    />

    <MesProductGroupManager ref="managerRef" @updated="loadGroups" />
  </div>
</template>
