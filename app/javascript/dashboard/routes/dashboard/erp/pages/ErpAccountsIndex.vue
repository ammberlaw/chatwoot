<script setup>
import { ref, reactive, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useErpLedgerAccountsStore } from 'dashboard/stores/erp/ledgerAccounts';
import { useErpRole } from 'dashboard/composables/useErpRole';
import ErpLedgerAccountAPI from 'dashboard/api/erp/ledgerAccounts';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import { exportRowsToExcel } from 'dashboard/helper/erpExcel';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
// 页签：科目树 / 存货科目映射。映射是科目的用法配置，挂在科目表页下，不另开侧栏项。
const TABS = [
  { key: 'tree', label: '科目表' },
  { key: 'inventory', label: '存货科目映射' },
];
const activeTab = ref('tree');

/* ─── 存货科目映射 ─────────────────────────────────────────────
 * 产品档案的「来源类别」→ 存货科目（原材料/库存商品/委托加工物资），
 * 决定采购入库凭证的借方科目。类别清单实时从产品档案聚合，不存字典表。
 * 未配置的类别一律落原材料：仓库随时会加新类别，不能因此把账做错。
 */
const invRows = ref([]);
const invMeta = ref({ default_code: '1403', options: [], configured_count: 0 });
const invLoading = ref(false);
const invSaving = ref(false);
const invKeyword = ref('');
const invOnlyMapped = ref(false);

const invOptions = computed(() =>
  invMeta.value.options.map(o => ({
    value: o.code,
    label: `${o.code} ${o.name}`,
  }))
);
const invFiltered = computed(() => {
  const q = invKeyword.value.trim().toLowerCase();
  return invRows.value.filter(r => {
    if (invOnlyMapped.value && r.code === invMeta.value.default_code)
      return false;
    return !q || r.category.toLowerCase().includes(q);
  });
});
// 「落在默认科目之外」的条数——财务一眼知道配了多少、还剩多少在吃默认。
const invMappedCount = computed(
  () => invRows.value.filter(r => r.code !== invMeta.value.default_code).length
);

const loadInventoryMap = async () => {
  invLoading.value = true;
  try {
    const { data } = await ErpLedgerAccountAPI.inventoryMap();
    invRows.value = data.payload || [];
    invMeta.value = data.meta || invMeta.value;
  } catch {
    useAlert('存货科目映射取不到');
  } finally {
    invLoading.value = false;
  }
};

// 一键预置：按名字猜（带「成品/外购机/裸机」的归库存商品、带「委托加工/委外」的归委托加工物资），
// 猜完不直接存，留给财务逐条核对再保存。
const applySuggestions = () => {
  let changed = 0;
  invRows.value.forEach(r => {
    if (r.code !== r.suggested) {
      r.code = r.suggested;
      changed += 1;
    }
  });
  useAlert(
    changed
      ? `已按名称预置 ${changed} 个类别，核对后记得保存`
      : '预置结果与当前一致，无需改动'
  );
};

const saveInventoryMap = async () => {
  invSaving.value = true;
  try {
    const map = Object.fromEntries(
      invRows.value.map(r => [r.category, r.code])
    );
    const { data } = await ErpLedgerAccountAPI.updateInventoryMap(map);
    invMeta.value = {
      ...invMeta.value,
      configured_count: data.payload.configured_count,
    };
    useAlert(`已保存，${data.payload.configured_count} 个类别配了非默认科目`);
  } catch {
    useAlert('保存失败');
  } finally {
    invSaving.value = false;
  }
};

const switchTab = key => {
  activeTab.value = key;
  if (key === 'inventory' && !invRows.value.length) loadInventoryMap();
};

// 会计科目表：记账引擎的地基。编码走财政部国标（1 资产 / 2 负债 / 4 权益 / 5 成本 / 6 损益），
// 与金蝶同码——平行跑账期科目可逐条对上。树形展示，只有明细科目（非分类）能记账。
const store = useErpLedgerAccountsStore();
const { erpCan } = useErpRole();
const canWrite = computed(() => erpCan('ledger'));

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const saving = computed(
  () => store.getUIFlags.creatingItem || store.getUIFlags.updatingItem
);

const CATEGORIES = [
  { value: 'ASSET', label: '资产类' },
  { value: 'LIABILITY', label: '负债类' },
  { value: 'EQUITY', label: '所有者权益类' },
  { value: 'COST', label: '成本类' },
  { value: 'PL', label: '损益类' },
];
const DIRECTIONS = [
  { value: 'DEBIT', label: '借' },
  { value: 'CREDIT', label: '贷' },
];
// 业务钩子：自动凭证/报表/期末按此找科目，不靠中文名匹配（后端 ACCOUNT_TYPES 同表）。
const ACCOUNT_TYPES = [
  { value: '', label: '普通科目' },
  { value: 'CASH', label: '现金' },
  { value: 'BANK', label: '银行存款' },
  { value: 'RECEIVABLE', label: '应收账款' },
  { value: 'PAYABLE', label: '应付账款' },
  { value: 'STOCK', label: '存货' },
  { value: 'FIXED_ASSET', label: '固定资产' },
  { value: 'ACCUM_DEPRECIATION', label: '累计折旧' },
  { value: 'TAX', label: '税金' },
  { value: 'INCOME', label: '收入' },
  { value: 'COGS', label: '主营成本' },
  { value: 'EXPENSE', label: '费用' },
  { value: 'DEPRECIATION', label: '折旧费用' },
  { value: 'EXCHANGE_DIFF', label: '汇兑损益' },
  { value: 'ROUND_OFF', label: '整数差异' },
];
const CURRENCIES = [
  { value: '', label: '本位币（人民币）' },
  { value: 'USD', label: '美元 USD' },
  { value: 'EUR', label: '欧元 EUR' },
];
const DIMENSIONS = [
  { value: 'customer', label: '客户' },
  { value: 'supplier', label: '供应商' },
  { value: 'order', label: '订单' },
  { value: 'department', label: '部门' },
  { value: 'member', label: '业务员' },
];
const dimensionLabel = v => DIMENSIONS.find(d => d.value === v)?.label || v;
const accountTypeLabel = v =>
  ACCOUNT_TYPES.find(t => t.value === (v || ''))?.label || v;

const keyword = ref('');
const categoryFilter = ref('');
const showInactive = ref(true);
const collapsed = ref(new Set());

const visibleRecords = computed(() => {
  let list = records.value;
  if (categoryFilter.value) {
    list = list.filter(a => a.category === categoryFilter.value);
  }
  if (!showInactive.value) list = list.filter(a => a.isActive);
  return list;
});

// 扁平列表 → 树 → 再按展开状态摊平成表格行（带层级缩进）。
// 搜索结果后端已带上祖先链，故树不会断层。
const rows = computed(() => {
  const list = visibleRecords.value;
  const byParent = new Map();
  const ids = new Set(list.map(a => a.id));
  list.forEach(item => {
    // 上级被筛掉时（如按类别筛）当作根节点挂出来，避免整棵子树消失。
    const parentKey = ids.has(item.parentId) ? item.parentId : null;
    if (!byParent.has(parentKey)) byParent.set(parentKey, []);
    byParent.get(parentKey).push(item);
  });
  byParent.forEach(children =>
    children.sort((a, b) => a.code.localeCompare(b.code))
  );

  const result = [];
  const walk = (parentKey, depth) => {
    (byParent.get(parentKey) || []).forEach(item => {
      const children = byParent.get(item.id) || [];
      const isCollapsed = collapsed.value.has(item.id);
      result.push({ ...item, depth, childCount: children.length, isCollapsed });
      if (children.length && !isCollapsed) walk(item.id, depth + 1);
    });
  };
  walk(null, 0);
  return result;
});

// 导出 Excel：导的是**筛选后的全部科目**，不是表格上展开着的那些——
// 折叠只是看的人图清爽，导出漏掉收起来的子科目就成了一张残表。
const exportExcel = () => {
  const list = [...visibleRecords.value].sort((a, b) =>
    a.code.localeCompare(b.code)
  );
  exportRowsToExcel(
    {
      title: '会计科目表',
      meta: [
        { label: '导出时间', value: new Date().toLocaleString() },
        {
          label: '筛选',
          value: `${categoryFilter.value ? CATEGORIES.find(c => c.value === categoryFilter.value)?.label : '全部类别'}${showInactive.value ? '' : '，不含已停用'}`,
        },
        { label: '科目数', value: list.length },
      ],
      columns: [
        { label: '科目编码', key: 'code' },
        { label: '科目名称', key: 'name' },
        { label: '类别', key: 'categoryLabel' },
        { label: '方向', key: 'directionLabel' },
        { label: '科目属性', key: 'typeLabel' },
        { label: '币种', key: 'currency' },
        { label: '核算维度', key: 'dimensions' },
        { label: '状态', key: 'status' },
      ],
      rows: list.map(item => ({
        code: item.code,
        name: item.name,
        categoryLabel: item.categoryLabel,
        directionLabel: item.direction === 'DEBIT' ? '借' : '贷',
        typeLabel: item.isGroup
          ? '分类（不记账）'
          : accountTypeLabel(item.accountType),
        currency: item.currency || 'CNY',
        dimensions: (item.dimensions || []).map(dimensionLabel).join('、'),
        status: item.isActive ? '启用' : '已停用',
      })),
    },
    `会计科目表_${new Date().toISOString().slice(0, 10)}`
  );
};

const groupOptions = computed(() => [
  { value: '', label: '无（一级科目）' },
  ...records.value
    .filter(a => a.isGroup)
    .sort((a, b) => a.code.localeCompare(b.code))
    .map(a => ({ value: a.id, label: `${a.code} ${a.name}` })),
]);

const toggle = id => {
  const next = new Set(collapsed.value);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  collapsed.value = next;
};

// 默认只摊开一级科目，二级以下收起——109 个科目全摊开一屏看不完。
const collapseToTopLevel = () => {
  collapsed.value = new Set(
    records.value.filter(a => a.isGroup && a.parentId).map(a => a.id)
  );
};

const fetchList = async () => {
  await store.get({ q: keyword.value.trim() });
  if (keyword.value.trim()) collapsed.value = new Set();
  else collapseToTopLevel();
};

const initializing = ref(false);
const initStandard = async () => {
  initializing.value = true;
  try {
    const { data } = await ErpLedgerAccountAPI.initializeStandard();
    await fetchList();
    useAlert(
      data.created
        ? `已初始化标准科目表：新增 ${data.created} 个科目，现有 ${data.total} 个`
        : `标准科目表已是最新，现有 ${data.total} 个科目`
    );
  } finally {
    initializing.value = false;
  }
};

const dialogRef = ref(null);
const editing = ref(null);
const form = reactive({
  parentId: '',
  code: '',
  name: '',
  category: 'ASSET',
  direction: 'DEBIT',
  isGroup: false,
  accountType: '',
  currency: '',
  dimensions: [],
  remark: '',
  isActive: true,
});
const { isDirty, markPristine } = useDirtyGuard(() => form);
const parentRecord = computed(() =>
  records.value.find(a => a.id === form.parentId)
);
const invalid = computed(() => !form.code.trim() || !form.name.trim());

const openCreate = (parent = null) => {
  editing.value = null;
  Object.assign(form, {
    parentId: parent?.id || '',
    code: parent?.code || '',
    name: '',
    category: parent?.category || 'ASSET',
    direction: parent?.direction || 'DEBIT',
    isGroup: false,
    accountType: '',
    currency: '',
    dimensions: [],
    remark: '',
    isActive: true,
  });
  markPristine();
  dialogRef.value?.open();
};

const openEdit = account => {
  editing.value = account;
  Object.assign(form, {
    parentId: account.parentId || '',
    code: account.code,
    name: account.name,
    category: account.category,
    direction: account.direction,
    isGroup: account.isGroup,
    accountType: account.accountType || '',
    currency: account.currency || '',
    dimensions: [...(account.dimensions || [])],
    remark: account.remark || '',
    isActive: account.isActive,
  });
  markPristine();
  dialogRef.value?.open();
};

const toggleDimension = value => {
  const index = form.dimensions.indexOf(value);
  if (index === -1) form.dimensions.push(value);
  else form.dimensions.splice(index, 1);
};

const submit = async () => {
  if (invalid.value) return;
  const payload = {
    parentId: form.parentId || null,
    code: form.code.trim(),
    name: form.name.trim(),
    category: form.category,
    direction: form.direction,
    isGroup: form.isGroup,
    accountType: form.accountType || null,
    currency: form.currency || null,
    dimensions: form.dimensions,
    remark: form.remark,
    isActive: form.isActive,
  };
  const result = editing.value
    ? await store.update({ id: editing.value.id, ...payload })
    : await store.create(payload);
  if (!result) return;
  await fetchList();
  useAlert(editing.value ? '科目已更新' : `已新增科目 ${result.code}`);
  dialogRef.value?.close();
};

const toggleActive = async account => {
  await store.update({ id: account.id, isActive: !account.isActive });
  useAlert(account.isActive ? '科目已停用' : '科目已启用');
};

const confirmRef = ref(null);
const deleting = ref(null);
const askDelete = account => {
  deleting.value = account;
  confirmRef.value?.open();
};
const doDelete = async () => {
  const target = deleting.value;
  const ok = await store.delete(target.id);
  if (ok) useAlert(`已删除科目 ${target.code} ${target.name}`);
};

onMounted(fetchList);
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between gap-3 px-6 py-4 [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8">
      <div class="flex items-center gap-2">
        <div class="i-lucide-list-tree size-5 text-n-iris-9" />
        <h1 class="text-xl font-semibold text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8">会计科目表</h1>
        <span class="text-sm text-n-slate-11">
          共 {{ records.length }} 个科目
        </span>
      </div>
      <div class="flex items-center gap-2">
        <Input
          v-model="keyword"
          size="sm"
          placeholder="搜编码 / 名称"
          custom-input-class="w-52"
          @keyup.enter="fetchList"
        />
        <Button label="查询" color="slate" size="sm" @click="fetchList" />
        <Button
          label="导出 Excel"
          color="slate"
          variant="faded"
          size="sm"
          :disabled="!records.length"
          @click="exportExcel"
        />
        <Button
          v-if="canWrite"
          label="初始化标准科目表"
          color="slate"
          variant="faded"
          size="sm"
          :is-loading="initializing"
          @click="initStandard"
        />
        <Button
          v-if="canWrite"
          label="新建科目"
          color="iris"
          size="sm"
          @click="openCreate()"
        />
      </div>
    </div>

    <div
      data-tabbar="page"
      data-tabbar-theme="classic"
      class="flex items-center gap-1 px-6"
    >
      <button
        v-for="tab in TABS"
        :key="tab.key"
        type="button"
        :aria-selected="activeTab === tab.key"
        class="px-3 py-1.5 text-sm rounded-lg"
        @click="switchTab(tab.key)"
      >
        {{ tab.label }}
      </button>
    </div>

    <div v-if="activeTab === 'tree'" class="flex items-center gap-2 px-6 pb-3 [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8">
      <SelectCard
        v-model="categoryFilter"
        :options="[{ value: '', label: '全部类别' }, ...CATEGORIES]"
      />
      <label class="flex items-center gap-2 text-sm text-n-slate-11">
        <input v-model="showInactive" type="checkbox" class="w-4 h-4" />
        显示已停用
      </label>
    </div>

    <!-- 存货科目映射：来源类别 → 存货科目，决定采购入库凭证的借方科目 -->
    <template v-if="activeTab === 'inventory'">
      <div class="flex flex-wrap items-center gap-2 px-6 pb-3 [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8">
        <Input
          v-model="invKeyword"
          size="sm"
          placeholder="搜来源类别"
          custom-input-class="w-52"
        />
        <label class="flex items-center gap-2 text-sm text-n-slate-11">
          <input v-model="invOnlyMapped" type="checkbox" class="w-4 h-4" />
          只看已配的
        </label>
        <span class="text-sm text-n-slate-11">
          共 {{ invRows.length }} 个类别 · 已配
          <span class="font-medium text-n-slate-12">{{ invMappedCount }}</span>
          个，其余按默认记原材料
        </span>
        <span class="flex-1" />
        <Button
          v-if="canWrite"
          label="按名称预置"
          variant="faded"
          color="slate"
          size="sm"
          @click="applySuggestions"
        />
        <Button
          v-if="canWrite"
          label="保存映射"
          color="iris"
          size="sm"
          :is-loading="invSaving"
          @click="saveInventoryMap"
        />
      </div>

      <HScrollButtons />
      <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8">
        <p class="pb-3 text-xs text-n-slate-11">
          采购入库凭证的借方科目按这张表走：借
          <span class="text-n-slate-12">存货科目</span> ／ 贷
          应付账款。没配过的类别一律记
          <span class="text-n-slate-12">原材料</span
          >，仓库新增类别不会把账做错。
        </p>
        <div v-if="invLoading" class="py-10 text-center text-n-slate-11">
          加载中…
        </div>
        <table v-else class="w-full text-sm">
          <thead>
            <tr class="text-left border-b text-n-slate-11 border-n-weak">
              <th class="px-3 py-2 font-medium whitespace-nowrap">来源类别</th>
              <th class="px-3 py-2 font-medium text-right whitespace-nowrap">
                产品数
              </th>
              <th class="px-3 py-2 font-medium whitespace-nowrap">存货科目</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in invFiltered"
              :key="row.category"
              class="border-b border-n-weak"
            >
              <td class="px-3 py-2 text-n-slate-12">{{ row.category }}</td>
              <td class="px-3 py-2 font-mono text-right text-n-slate-11">
                {{ row.product_count }}
              </td>
              <td class="px-3 py-2">
                <SelectCard
                  v-model="row.code"
                  :options="invOptions"
                  :disabled="!canWrite"
                  class="w-56"
                />
              </td>
            </tr>
            <tr v-if="!invFiltered.length">
              <td colspan="3" class="px-3 py-10 text-center text-n-slate-11">
                没有匹配的来源类别。
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>

    <HScrollButtons v-if="activeTab === 'tree'" />
    <div
      v-if="activeTab === 'tree'"
      class="flex-1 min-h-0 px-6 pb-6 overflow-auto [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8"
    >
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <div
        v-else-if="!records.length"
        class="flex flex-col items-center justify-center gap-3 py-20 text-n-slate-11"
      >
        <div class="i-lucide-list-tree size-8 text-n-iris-9" />
        <div class="text-base font-medium text-n-slate-12">尚未建立科目表</div>
        <div class="text-sm">
          一键生成中国企业会计准则标准科目表（国标编码，与金蝶同码），之后可自行增减明细科目
        </div>
        <Button
          v-if="canWrite"
          label="初始化标准科目表"
          color="iris"
          size="sm"
          :is-loading="initializing"
          @click="initStandard"
        />
      </div>
      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left text-n-slate-11 border-b border-n-weak">
            <th class="px-3 py-3 font-medium w-[34%]">科目</th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">类别</th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">方向</th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">科目属性</th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">币种</th>
            <th class="px-3 py-3 font-medium whitespace-nowrap">核算维度</th>
            <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
              操作
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in rows"
            :key="row.id"
            class="border-b border-n-weak hover:bg-n-alpha-1"
            :class="{ 'opacity-50': !row.isActive }"
          >
            <td class="px-3 py-2">
              <div
                class="flex items-center gap-1.5"
                :style="{ paddingLeft: `${row.depth * 18}px` }"
              >
                <button
                  v-if="row.childCount"
                  class="flex items-center justify-center size-4 text-n-slate-11 hover:text-n-slate-12"
                  @click="toggle(row.id)"
                >
                  <div
                    :class="
                      row.isCollapsed
                        ? 'i-lucide-chevron-right'
                        : 'i-lucide-chevron-down'
                    "
                    class="size-4"
                  />
                </button>
                <div v-else class="size-4" />
                <span class="font-mono text-n-slate-11">{{ row.code }}</span>
                <span
                  class="text-n-slate-12"
                  :class="{ 'font-medium': row.isGroup }"
                >
                  {{ row.name }}
                </span>
                <span
                  v-if="!row.isActive"
                  class="px-1.5 py-0.5 text-xs rounded bg-n-slate-3 text-n-slate-11"
                >
                  已停用
                </span>
              </div>
            </td>
            <td class="px-3 py-2 text-n-slate-11">{{ row.categoryLabel }}</td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ row.direction === 'DEBIT' ? '借' : '贷' }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{
                row.isGroup
                  ? '分类（不记账）'
                  : accountTypeLabel(row.accountType)
              }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ row.currency || 'CNY' }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              <span v-if="!row.dimensions?.length">—</span>
              <span
                v-for="dim in row.dimensions"
                :key="dim"
                class="inline-block px-1.5 py-0.5 mr-1 text-xs rounded bg-n-iris-3 text-n-iris-11"
              >
                {{ dimensionLabel(dim) }}
              </span>
            </td>
            <td class="px-3 py-2">
              <div class="flex items-center justify-end gap-1">
                <template v-if="canWrite">
                  <Button
                    v-if="row.isGroup"
                    label="加明细"
                    color="slate"
                    variant="ghost"
                    size="xs"
                    @click="openCreate(row)"
                  />
                  <Button
                    label="编辑"
                    color="slate"
                    variant="ghost"
                    size="xs"
                    @click="openEdit(row)"
                  />
                  <Button
                    :label="row.isActive ? '停用' : '启用'"
                    color="slate"
                    variant="ghost"
                    size="xs"
                    @click="toggleActive(row)"
                  />
                  <Button
                    v-if="!row.isSystem"
                    label="删除"
                    color="ruby"
                    variant="ghost"
                    size="xs"
                    @click="askDelete(row)"
                  />
                </template>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <Dialog
      ref="dialogRef"
      width="lg"
      confirm-button-color="iris"
      :title="editing ? '编辑科目' : '新建科目'"
      :is-loading="saving"
      :disable-confirm-button="invalid"
      :dirty="isDirty"
      dirty-save-label="保存"
      @confirm="submit"
      @close="markPristine"
      @save="submit"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">上级科目</label>
            <SelectCard v-model="form.parentId" :options="groupOptions" block />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              科目编码 <span class="text-n-ruby-11">*</span>
            </label>
            <Input v-model="form.code" autofocus />
            <span v-if="parentRecord" class="text-xs text-n-slate-10">
              须以上级编码「{{ parentRecord.code }}」开头，如
              {{ parentRecord.code }}01
            </span>
          </div>
        </div>

        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              科目名称 <span class="text-n-ruby-11">*</span>
            </label>
            <Input v-model="form.name" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">余额方向</label>
            <SelectCard v-model="form.direction" :options="DIRECTIONS" block />
          </div>
        </div>

        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">科目类别</label>
            <SelectCard
              v-model="form.category"
              :options="CATEGORIES"
              :disabled="!!parentRecord"
              block
            />
            <span v-if="parentRecord" class="text-xs text-n-slate-10">
              跟随上级科目，不可改
            </span>
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">科目属性</label>
            <SelectCard
              v-model="form.accountType"
              :options="ACCOUNT_TYPES"
              :disabled="form.isGroup"
              block
            />
            <span class="text-xs text-n-slate-10">
              自动凭证与报表按属性找科目（如收款单找「银行存款」）
            </span>
          </div>
        </div>

        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">币种</label>
            <SelectCard v-model="form.currency" :options="CURRENCIES" block />
            <span class="text-xs text-n-slate-10">
              外币科目参与期末调汇，本位币科目不受影响
            </span>
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">核算维度</label>
            <div class="flex flex-wrap items-center gap-1.5">
              <button
                v-for="dim in DIMENSIONS"
                :key="dim.value"
                type="button"
                class="px-2 py-1 text-xs rounded-lg border transition-colors"
                :class="
                  form.dimensions.includes(dim.value)
                    ? 'border-n-iris-8 bg-n-iris-3 text-n-iris-11'
                    : 'border-n-weak text-n-slate-11 hover:text-n-slate-12'
                "
                @click="toggleDimension(dim.value)"
              >
                {{ dim.label }}
              </button>
            </div>
            <span class="text-xs text-n-slate-10">
              录凭证时按维度带客户/供应商/订单，供维度明细账查账
            </span>
          </div>
        </div>

        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">备注</label>
          <Input v-model="form.remark" />
        </div>

        <div class="flex items-center gap-6">
          <label class="flex items-center gap-2 text-heading-3 text-n-slate-12">
            <input v-model="form.isGroup" type="checkbox" class="w-4 h-4" />
            分类科目（只汇总下级，不能记账）
          </label>
          <label class="flex items-center gap-2 text-heading-3 text-n-slate-12">
            <input v-model="form.isActive" type="checkbox" class="w-4 h-4" />
            启用（停用后不出现在凭证科目下拉）
          </label>
        </div>
      </div>
    </Dialog>

    <Dialog
      ref="confirmRef"
      type="alert"
      width="sm"
      confirm-button-color="ruby"
      title="删除科目"
      :description="`确定删除「${deleting?.code || ''} ${deleting?.name || ''}」？已记过账的科目不建议删除，可改为停用。`"
      confirm-button-label="删除"
      @confirm="doDelete"
    />
  </div>
</template>
