<script setup>
import { ref, computed, reactive, onMounted, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useMesProductsStore } from 'dashboard/stores/mes/products';
import { useMesRole } from 'dashboard/composables/useMesRole';
import {
  MES_PRODUCT_LINES,
  productLineLabel,
  getActiveProductLine,
} from 'dashboard/composables/useMesProductLine';

import MesProductAPI from 'dashboard/api/mes/products';
import ProductGroupsAPI from 'dashboard/api/mes/productGroups';
import { exportRowsToExcel, fetchAllRows } from 'dashboard/helper/erpExcel';
import ProductCategoriesAPI from 'dashboard/api/mes/productCategories';
import Draggable from 'vuedraggable';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import camelcaseKeys from 'camelcase-keys';
import ProductAuxAttributesAPI from 'dashboard/api/mes/productAuxAttributes';
import MesProductGroupNode from 'dashboard/components-next/mes/MesProductGroupNode.vue';
import MesProductGroupManager from 'dashboard/components-next/mes/MesProductGroupManager.vue';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
const store = useMesProductsStore();
const { mesCan } = useMesRole();

// 每页条数自己选，记在本机。生产上近 5000 个料号，15 条一页要翻 333 页——
// 采购编新料号时得翻到同字母流水号的末尾才知道编到几号（用户原话「金蝶是 1000 条/页」）。
const PER_PAGE_KEY = 'mes.products.perPage';
const PER_PAGE_OPTIONS = [20, 50, 100, 200, 500, 1000].map(n => ({
  value: String(n),
  label: `${n} 条/页`,
}));
const readPerPage = () => {
  const saved = Number(localStorage.getItem(PER_PAGE_KEY));
  return PER_PAGE_OPTIONS.some(o => Number(o.value) === saved) ? saved : 50;
};
const itemsPerPage = ref(readPerPage());
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
// 点中的那一行高亮，方便在几十列里对着看——再点一次取消。只是视觉焦点，不参与任何提交。
const selectedId = ref(null);

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

// —— 商品类别树（产品线 → 商品类别）——
// 金蝶左侧那棵树的对应物。分类值来自导入时带进来的「商品类别」列，不用另行维护。
const categoryTree = ref([]); // [{ product_line, count, categories: [{ category, count }] }]
const selectedSourceCategory = ref(''); // ''=全部
const categoryKeyword = ref('');
const collapsedLines = reactive({});

const loadCategoryTree = async () => {
  try {
    const { data } = await ProductCategoriesAPI.tree();
    categoryTree.value = data.payload || [];
  } catch {
    categoryTree.value = [];
  }
};

// 类别多达两百来个（商显尤其），所以树自带查找框，按关键字过滤子节点。
// 过滤后父节点若一个子节点都不剩就整条隐藏。
const filteredCategoryTree = computed(() => {
  const kw = categoryKeyword.value.trim().toLowerCase();
  return categoryTree.value
    .map(line => ({
      ...line,
      categories: kw
        ? line.categories.filter(c => c.category.toLowerCase().includes(kw))
        : line.categories,
    }))
    .filter(line => line.categories.length);
});
const categoryTotal = computed(() =>
  categoryTree.value.reduce((sum, line) => sum + line.count, 0)
);
// 有关键字时强制展开，否则找到了也看不见。
const isLineOpen = line =>
  !!categoryKeyword.value.trim() || !collapsedLines[line];
const toggleLine = line => {
  collapsedLines[line] = !collapsedLines[line];
};

const load = () =>
  store.get({
    page: currentPage.value,
    per_page: itemsPerPage.value,
    q: keyword.value.trim() || undefined,
    category: categoryFilter.value || undefined,
    source_category: selectedSourceCategory.value || undefined,
    group_code: selectedGroup.value || undefined,
  });
// 翻页触发重拉；搜索/筛选先回到第 1 页（页码变则由 watch 拉，未变则直接拉）。
watch(currentPage, load);
const changePerPage = v => {
  itemsPerPage.value = Number(v);
  localStorage.setItem(PER_PAGE_KEY, String(v));
  // 换了每页条数页码就对不上了，回第一页重取
  if (currentPage.value !== 1) currentPage.value = 1;
  else load();
};
const reload = () => {
  if (currentPage.value !== 1) currentPage.value = 1;
  else load();
};
// 整页重取：列表 + 左侧分类目录 + 产品分组。
// 新编一个料号存完，左边目录的条数不跟着变，看着像没存上（反馈原话
// 「我新编了代码，保存以后，目录里面没有及时显示出来」）——那两棵树得一起重拉。
const refreshAll = async () => {
  await Promise.all([load(), loadCategoryTree(), loadGroups()]);
};
// 清空搜索并立刻回到全部档案（光清输入框不重新取数，列表还停在搜索结果上）。
const clearKeyword = () => {
  keyword.value = '';
  reload();
};
const changeCategoryFilter = v => {
  categoryFilter.value = v;
  reload();
};
const selectGroup = code => {
  selectedGroup.value = selectedGroup.value === code ? '' : code;
  reload();
};
// 点类别即筛选；再点一次取消（回到全部）。
// 搜索时不给拖：过滤后的顺序对不上完整列表，拖出来的次序没有意义。
// 只读用户也不给拖（后端策略同样卡住 reorder_categories）。
const canDragCategories = computed(
  () => canManage.value && !categoryKeyword.value.trim()
);
// 拖完把该产品线下的类别顺序整体写回。失败就重拉一次，别让界面停在一个没存上的顺序。
const persistCategoryOrder = async line => {
  try {
    await ProductCategoriesAPI.reorder(line.categories.map(c => c.category));
  } catch {
    useAlert('类别顺序没保存上，已恢复');
    loadCategoryTree();
  }
};

const selectSourceCategory = value => {
  selectedSourceCategory.value =
    selectedSourceCategory.value === value ? '' : value;
  reload();
};

const dialogRef = ref(null);
const editingId = ref(null);

// ── 辅助属性：同一物料编码下的变体（喷码6000 / 喷码3500…），开单时单选其一 ──
// 只在「编辑已有产品」时维护：新建还没有 id，属性挂不上去，存完再回来加。
const auxList = ref([]);
const auxDraft = ref('');
const auxBusy = ref(false);

const loadAux = async productId => {
  auxList.value = [];
  if (!productId) return;
  try {
    const { data } = await ProductAuxAttributesAPI.list(productId);
    auxList.value = camelcaseKeys(data?.payload || [], { deep: true });
  } catch {
    auxList.value = [];
  }
};

const addAux = async () => {
  const name = auxDraft.value.trim();
  if (!name || !editingId.value) return;
  auxBusy.value = true;
  try {
    const { data } = await ProductAuxAttributesAPI.add(editingId.value, {
      name,
    });
    auxList.value.push(camelcaseKeys(data.payload, { deep: true }));
    auxDraft.value = '';
  } catch (e) {
    useAlert(e?.response?.data?.error || '新增辅助属性失败');
  } finally {
    auxBusy.value = false;
  }
};

// 被单据选过的只会停用（后端返回 deactivated: true），没被选过的才真删。
const removeAux = async attr => {
  auxBusy.value = true;
  try {
    const { data } = await ProductAuxAttributesAPI.remove(
      editingId.value,
      attr.id
    );
    if (data?.payload?.deactivated) {
      useAlert(
        `「${attr.name}」已被单据引用，已停用（不再出现在下拉里），历史单据保持不变`
      );
      await loadAux(editingId.value);
    } else {
      auxList.value = auxList.value.filter(a => a.id !== attr.id);
    }
  } catch (e) {
    useAlert(e?.response?.data?.error || '操作失败');
  } finally {
    auxBusy.value = false;
  }
};

// 上一次新建用的计量单位，记在本机（这是填单顺手程度的事，不是业务数据，不值得建表）。
const UNIT_KEY = 'mes.products.lastUnit';
const lastUnit = ref(localStorage.getItem(UNIT_KEY) || '');

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
const { isDirty, markPristine } = useDirtyGuard(() => form);
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
  auxList.value = [];
  auxDraft.value = '';
  Object.assign(form, {
    name: '',
    sku: '',
    // 产品线跟着顶部切换的产线走：在「平板」下编码，新码就是平板的。
    // 「全部」视图下拿不到具体产线，留空由人选（后端也会按当前产线兜底）。
    productLine: getActiveProductLine() || '',
    category: '',
    // 商品类别跟着当前筛选走（和下面的 groupCode 一个道理）：人是在「主板」这一类里
    // 翻到流水号末尾才点的新增，新编的码理应还在这一类下。留空的话列表按
    // source_category 筛就看不到它了——新建完「列表里没有、搜索又搜得到」，
    // 人会以为没存上、再建一遍（生产上已经出过 P.03.134 这么一颗）。
    sourceCategory: selectedSourceCategory.value || '',
    // 单位沿用上一次新建时填的：一个人一口气编几十个码，单位基本都是同一个
    // （平板是「片」，商显是「台」），每次重选纯属多余。不一样的改掉就行。
    unit: lastUnit.value,
    specification: '',
    remark: '',
    groupCode: selectedGroup.value || '',
    isActive: true,
  });
  markPristine();
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
  loadAux(p.id);
  markPristine();
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
      // 记住这次用的单位，下一次新建直接带上（见 openCreate）
      if (payload.unit) {
        lastUnit.value = payload.unit;
        try {
          localStorage.setItem(UNIT_KEY, payload.unit);
        } catch {
          // 隐私模式写不进去：这轮内存里仍然生效，不影响建档
        }
      }
      // 新增完不关弹窗，就地转成编辑态：辅助属性要有产品 id 才建得了（编码按产品自动生成），
      // 关掉再回列表翻出这条新料号太费事——采购的原话是「每次新增代码的时候都要有」。
      if (editingId.value) {
        useAlert('产品已更新');
        dialogRef.value?.close();
      } else {
        useAlert(`已新增产品 ${ok.sku}，可以接着编辅助属性`);
        editingId.value = ok.id;
        auxDraft.value = '';
        await loadAux(ok.id);
        markPristine();
      }
      // 存完把列表和左侧目录一起刷新，不然新编的料号要手动刷页面才看得到
      refreshAll();
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

// 导出：带当前筛选（关键字/分类/来源/分组）一起导——筛完再导、导出来是全量，等于白筛。
// ⚠️ 全量：列表一页 15 条，导出重新向后端分页要完，不是导屏幕这一页。
const exporting = ref(false);
const exportList = async () => {
  exporting.value = true;
  try {
    const rows = await fetchAllRows(params => MesProductAPI.get(params), {
      q: keyword.value.trim() || undefined,
      category: categoryFilter.value || undefined,
      source_category: selectedSourceCategory.value || undefined,
      group_code: selectedGroup.value || undefined,
    });
    exportRowsToExcel(
      {
        title: '产品档案',
        meta: [
          {
            label: '导出时间',
            value: new Date().toLocaleString('sv').slice(0, 16),
          },
          { label: '关键字', value: keyword.value.trim() || '（无）' },
          { label: '分类', value: categoryFilter.value || '全部分类' },
          { label: '产品数', value: rows.length },
        ],
        columns: [
          { label: '商品编码', key: 'sku' },
          { label: '产品名称', key: 'name' },
          { label: '规格型号', key: 'specification' },
          { label: '单位', key: 'unit' },
          { label: '分类', key: 'category' },
          { label: '来源分类', key: 'source_category' },
          { label: '分组编码', key: 'group_code' },
          { label: '产品线', key: 'product_line' },
          { label: '状态', key: 'active_label' },
          { label: '备注', key: 'remark' },
        ],
        rows: rows.map(row => ({
          ...row,
          active_label: row.is_active === false ? '已禁用' : '启用中',
        })),
      },
      `产品档案_${new Date().toLocaleDateString('sv')}`
    );
  } catch (error) {
    useAlert('导出失败，请重试');
  } finally {
    exporting.value = false;
  }
};

onMounted(() => {
  load();
  loadGroups();
  loadCategoryTree();
});
</script>

<template>
  <div class="flex flex-col w-full h-full min-h-0 bg-white">
    <div
      class="flex flex-col gap-3 px-4 py-3 sm:px-6 sm:py-4 md:flex-row md:items-center md:justify-between [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:sm:!px-8"
    >
      <div class="flex items-baseline gap-2">
        <h1
          class="text-heading-1 text-n-slate-12"
        >
          产品档案
        </h1>
        <span class="text-sm text-n-slate-11">共 {{ totalCount }} 条</span>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <Button
          label="刷新"
          variant="outline"
          color="slate"
          size="sm"
          icon="i-lucide-rotate-cw"
          :is-loading="isFetching"
          @click="refreshAll"
        />
        <!-- 导出是只读动作，不挂管理权限 -->
        <Button
          label="导出 Excel"
          variant="faded"
          color="slate"
          size="sm"
          :is-loading="exporting"
          @click="exportList"
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

    <div class="mx-4 mb-3 flex flex-wrap items-center gap-2 border-b border-n-weak pb-3 sm:mx-6 [.theme-classic_&]:sm:!mx-8">
        <SelectCard
          :model-value="categoryFilter"
          :options="categoryFilterOptions"
          class="w-full sm:w-44"
          @update:model-value="changeCategoryFilter"
        />
        <SelectCard
          :model-value="String(itemsPerPage)"
          :options="PER_PAGE_OPTIONS"
          class="w-full sm:w-28"
          @update:model-value="changePerPage"
        />
        <!-- 带清除的搜索框：搜完一个编码后，不清空就看不到全部档案；
             原来只能一个字一个字删，这里给个 X 一键回到全部。 -->
        <div class="relative w-full sm:w-56">
          <input
            v-model="keyword"
            placeholder="搜索编码 / 名称 / 规格 / 类别"
            class="w-full h-9 pl-3 text-sm rounded-lg outline-none border border-n-weak bg-n-solid-1 text-n-slate-12"
            :class="keyword ? 'pr-8' : 'pr-3'"
            @keyup.enter="reload"
          />
          <button
            v-if="keyword"
            type="button"
            title="清空搜索，显示全部档案（搜索期间左侧分类筛选不生效）"
            class="absolute flex items-center justify-center -translate-y-1/2 rounded size-5 right-2 top-1/2 text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12"
            @click="clearKeyword"
          >
            <span class="i-lucide-x size-3.5" />
          </button>
        </div>
        <Button
          label="搜索"
          variant="outline"
          color="slate"
          size="sm"
          @click="reload"
        />
    </div>

    <div class="flex flex-1 min-h-0">
      <!-- 左侧：商品类别树（产品线 → 类别，对齐金蝶）+ 产品分组树 -->
      <aside
        class="flex-col hidden gap-1 px-2 py-3 overflow-y-auto border-r md:flex w-48 shrink-0 bg-n-alpha-1 border-n-weak"
      >
        <div class="flex items-center justify-between px-2 mb-1">
          <span class="text-xs font-medium text-n-slate-11">商品类别</span>
        </div>
        <input
          v-model="categoryKeyword"
          placeholder="查找类别…"
          class="w-full h-8 px-2 mb-1 text-xs border rounded-lg outline-none border-n-weak bg-n-solid-1 text-n-slate-12"
        />
        <button
          type="button"
          class="flex items-center justify-between w-full gap-1 px-2 py-1.5 text-sm text-left rounded-lg hover:bg-n-alpha-1"
          :class="
            selectedSourceCategory === ''
              ? 'bg-n-iris-3 text-n-iris-11 font-medium'
              : 'text-n-slate-12'
          "
          @click="selectSourceCategory('')"
        >
          <span>全部</span>
          <span class="text-xs text-n-slate-10">{{ categoryTotal }}</span>
        </button>
        <template v-for="line in filteredCategoryTree" :key="line.product_line">
          <button
            type="button"
            class="flex items-center gap-1 w-full px-2 py-1.5 text-xs font-medium text-left rounded-lg text-n-slate-11 hover:bg-n-alpha-1"
            @click="toggleLine(line.product_line)"
          >
            <span
              class="i-lucide-chevron-right size-3 shrink-0 transition-transform"
              :class="isLineOpen(line.product_line) ? 'rotate-90' : ''"
            />
            <span class="truncate">
              {{ productLineLabel(line.product_line) || '未指定产品线' }}
            </span>
            <span class="ml-auto text-n-slate-10">{{ line.count }}</span>
          </button>
          <Draggable
            v-if="isLineOpen(line.product_line)"
            :list="line.categories"
            item-key="category"
            handle=".cat-drag"
            :disabled="!canDragCategories"
            @end="persistCategoryOrder(line)"
          >
            <template #item="{ element: c }">
              <div class="flex items-center group">
                <span
                  class="cat-drag i-lucide-grip-vertical size-3 shrink-0 ml-1 mr-0.5 text-n-slate-9"
                  :class="
                    canDragCategories
                      ? 'cursor-grab opacity-0 group-hover:opacity-100'
                      : 'invisible'
                  "
                />
                <button
                  type="button"
                  class="flex items-center justify-between flex-1 min-w-0 gap-1 py-1 pl-1 pr-2 text-sm text-left rounded-lg hover:bg-n-alpha-1"
                  :class="
                    selectedSourceCategory === c.category
                      ? 'bg-n-iris-3 text-n-iris-11 font-medium'
                      : 'text-n-slate-12'
                  "
                  @click="selectSourceCategory(c.category)"
                >
                  <span class="truncate">
                    {{ c.category || '（未填类别）' }}
                  </span>
                  <span class="text-xs shrink-0 text-n-slate-10">
                    {{ c.count }}
                  </span>
                </button>
              </div>
            </template>
          </Draggable>
        </template>
        <p
          v-if="!filteredCategoryTree.length"
          class="px-2 mt-1 text-xs text-n-slate-10"
        >
          {{ categoryKeyword.trim() ? '没有匹配的类别。' : '还没有商品类别。' }}
        </p>

        <div
          class="flex items-center justify-between px-2 pt-3 mt-3 border-t border-n-weak"
        >
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

      <HScrollButtons />
      <div
        class="flex-1 min-h-0 px-4 overflow-auto sm:px-6 [.theme-classic_&]:sm:!px-8"
      >
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
                <span v-if="p.remark">备注：{{ p.remark }}</span>
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

          <!-- 列多：设最小宽度，窄屏外层 overflow-auto 自动横向滑动；仅「规格」长文本允许换行，其余列不换行 -->
          <table class="hidden md:table w-full md:min-w-[1320px] text-sm border-separate border-spacing-0">
            <thead class="sticky top-0 z-10">
              <tr
                class="text-left text-n-slate-11 border-b border-n-weak whitespace-nowrap bg-n-solid-1 [&>th]:bg-n-solid-1"
              >
                <th class="px-3 py-3 font-medium w-12 whitespace-nowrap">#</th>
                <th class="px-3 py-3 font-medium whitespace-nowrap">
                  商品编码
                </th>
                <th class="px-3 py-3 font-medium whitespace-nowrap">
                  商品名称
                </th>
                <th class="px-3 py-3 font-medium whitespace-nowrap">分组</th>
                <th class="px-3 py-3 font-medium whitespace-nowrap">规格</th>
                <th class="px-3 py-3 font-medium whitespace-nowrap">备注</th>
                <th class="px-3 py-3 font-medium whitespace-nowrap">产品线</th>
                <th class="px-3 py-3 font-medium whitespace-nowrap">
                  商品类别
                </th>
                <th class="px-3 py-3 font-medium whitespace-nowrap">
                  仓别分类
                </th>
                <th class="px-3 py-3 font-medium whitespace-nowrap">单位</th>
                <th class="px-3 py-3 font-medium whitespace-nowrap">状态</th>
                <th class="sticky right-0 z-20 min-w-[200px] border-l border-n-weak !bg-white px-3 py-3 font-medium text-right whitespace-nowrap">
                  操作
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(p, i) in records"
                :key="p.id"
                class="border-b cursor-pointer border-n-weak transition-colors"
                :class="
                  selectedId === p.id
                    ? 'bg-n-brand/10 hover:bg-n-brand/10'
                    : 'hover:bg-n-alpha-1'
                "
                @click="selectedId = selectedId === p.id ? null : p.id"
              >
                <td class="px-3 py-3 tabular-nums text-n-slate-10">
                  {{ (currentPage - 1) * itemsPerPage + i + 1 }}
                </td>
                <td class="px-3 py-3 font-mono text-n-slate-11">{{ p.sku }}</td>
                <td
                  class="px-3 py-3 font-medium text-n-slate-12 whitespace-nowrap"
                >
                  {{ p.name }}
                </td>
                <td class="px-3 py-3 text-n-slate-11 whitespace-nowrap">
                  {{ groupLabelByCode[p.groupCode] || '—' }}
                </td>
                <td class="px-3 py-3 text-n-slate-11 min-w-[16rem]">
                  {{ p.specification || '—' }}
                </td>
                <td class="px-3 py-3 text-n-slate-11 min-w-[12rem]">
                  {{ p.remark || '—' }}
                </td>
                <td class="px-3 py-3 text-n-slate-11 whitespace-nowrap">
                  {{ productLineLabel(p.productLine) || '—' }}
                </td>
                <td class="px-3 py-3 text-n-slate-11 whitespace-nowrap">
                  {{ p.sourceCategory || '—' }}
                </td>
                <td class="px-3 py-3 text-n-slate-11 whitespace-nowrap">
                  {{ categoryLabel(p.category) }}
                </td>
                <td class="px-3 py-3 text-n-slate-11 whitespace-nowrap">
                  {{ p.unit || '—' }}
                </td>
                <td class="px-3 py-3 whitespace-nowrap">
                  <span
                    class="inline-block px-2 py-0.5 text-xs rounded-full whitespace-nowrap"
                    :class="
                      p.isActive
                        ? 'bg-n-teal-3 text-n-teal-12'
                        : 'bg-n-slate-4 text-n-slate-11'
                    "
                  >
                    {{ p.isActive ? '启用' : '已禁用' }}
                  </span>
                </td>
                <td class="sticky right-0 z-10 min-w-[200px] border-l border-n-weak !bg-white px-3 py-3 whitespace-nowrap">
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
                <td colspan="11" class="px-3 py-10 text-center text-n-slate-11">
                  还没有产品。
                </td>
              </tr>
            </tbody>
          </table>
        </template>

        <PaginationFooter
          v-if="totalCount > itemsPerPage"
          :current-page="currentPage"
          :total-items="totalCount"
          :items-per-page="itemsPerPage"
          class="mt-0 sticky bottom-0 z-10 bg-white border-t border-n-weak"
          @update:current-page="currentPage = $event"
        />
      </div>
    </div>

    <Dialog
      ref="dialogRef"
      :dismissible="false"
      width="lg"
      confirm-button-color="iris"
      :title="editingId ? '编辑产品' : '新增产品'"
      :is-loading="saving"
      :disable-confirm-button="invalid"
      :dirty="isDirty"
      dirty-save-label="保存"
      @confirm="submit"
      @close="markPristine"
      @save="submit"
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
            <Input v-model="form.sku" />
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
            <Input v-model="form.sourceCategory" />
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

        <!-- 辅助属性：同一编码下的变体，开单时在明细里单选一个 -->
        <div
          v-if="editingId"
          class="flex flex-col gap-2 pt-3 border-t border-n-weak"
        >
          <div class="flex items-baseline gap-2">
            <span class="text-heading-2 text-n-slate-12">辅助属性</span>
            <span class="text-xs text-n-slate-10">
              同一编码下的变体（如 喷码6000 /
              喷码3500）。编码自动生成，开单时在用料明细里单选一个。
            </span>
          </div>

          <div
            v-for="attr in auxList"
            :key="attr.id"
            class="flex items-center gap-2 text-sm"
          >
            <span class="font-mono w-36 shrink-0 text-n-slate-11">
              {{ attr.code }}
            </span>
            <span class="flex-1 text-n-slate-12">{{ attr.name }}</span>
            <span v-if="!attr.isActive" class="text-xs text-n-slate-10">
              已停用
            </span>
            <button
              type="button"
              class="text-xs shrink-0 text-n-slate-10 hover:text-n-ruby-11"
              :disabled="auxBusy"
              @click="removeAux(attr)"
            >
              删除
            </button>
          </div>
          <p v-if="!auxList.length" class="text-xs text-n-slate-10">
            还没有辅助属性。没有变体的物料不用管这一栏。
          </p>

          <div class="flex gap-2">
            <Input
              v-model="auxDraft"
              placeholder="属性名称"
              class="flex-1"
              @keydown.enter.prevent.stop="addAux"
            />
            <Button
              type="button"
              label="添加"
              variant="outline"
              size="sm"
              :is-loading="auxBusy"
              :disabled="!auxDraft.trim()"
              @click="addAux"
            />
          </div>
        </div>

        <!-- 新增态还没有产品 id，变体编码是按产品生成的，建不了。
             摆一句说明让人知道这一栏在：保存后弹窗会就地转成编辑态，接着编，
             不用再回列表里翻出这条刚建的代码。 -->
        <div v-else class="flex flex-col gap-1 pt-3 border-t border-n-weak">
          <span class="text-heading-2 text-n-slate-12">辅助属性</span>
          <span class="text-xs text-n-slate-10">
            保存后这一栏会就地打开，可以直接添加变体（如 喷码6000 /
            喷码3500），不用再回列表找这条代码。
          </span>
        </div>
      </div>
    </Dialog>

    <Dialog
      ref="confirmRef"
      :dismissible="false"
      type="alert"
      width="sm"
      confirm-button-color="ruby"
      title="删除产品"
      :description="`确定删除「${deleting?.name || ''}」（${deleting?.sku || ''}）？已关联的生产任务单 / 采购 / 出库将解除引用。`"
      confirm-label="删除"
      @confirm="doDelete"
    />

    <MesProductGroupManager ref="managerRef" @updated="loadGroups" />
  </div>
</template>
