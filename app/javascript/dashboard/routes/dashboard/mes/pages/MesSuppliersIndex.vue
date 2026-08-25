<script setup>
import { ref, computed, reactive, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useMesSuppliersStore } from 'dashboard/stores/mes/suppliers';
import MesMaterialAPI from 'dashboard/api/mes/materials';
import { useMesRole } from 'dashboard/composables/useMesRole';
import {
  MES_PRODUCT_LINES,
  productLineLabel,
} from 'dashboard/composables/useMesProductLine';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

const store = useMesSuppliersStore();
const { mesCan } = useMesRole();

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const saving = computed(
  () => store.getUIFlags.creatingItem || store.getUIFlags.updatingItem
);
// 供应商档案由采购 / PMC（及管理员）维护，其他角色只读。
const canManage = computed(() => mesCan('master'));

// 事业部 = MES 产品线（含具体线或不指定，不做「全部」筛选项）。
const productLineOptions = [
  { value: '', label: '未指定' },
  ...MES_PRODUCT_LINES.filter(o => o.value),
];

// SKU 编码分类（按仓别），与物料档案共享同一套值
const SKU_CATEGORIES = [
  { value: 'FINISHED', label: '成品仓' },
  { value: 'SEMI', label: '半成品仓' },
  { value: 'RAW_MAIN', label: '原材料仓·主料' },
  { value: 'RAW_AUX', label: '原材料仓·辅料' },
  { value: 'DEFECTIVE', label: '不良品仓' },
];
const skuCategoryFilterOptions = [
  { value: '', label: '全部分类' },
  ...SKU_CATEGORIES,
];
const skuCategoryValues = SKU_CATEGORIES.map(o => o.value);

const keyword = ref('');
const itemCategory = ref('');
const load = () =>
  store.get({
    q: keyword.value.trim() || undefined,
    item_category: itemCategory.value || undefined,
  });
const changeCategoryFilter = v => {
  itemCategory.value = v;
  load();
};

const blankItem = () => ({
  id: null,
  materialCode: '',
  codeSearch: '',
  category: '',
  name: '',
  color: '',
  specification: '',
  unit: '',
  unitPrice: '',
});

// 物料档案列表（编码下拉数据源）：初始加载 + 输入时服务端搜索增量合并。
const materialsList = ref([]);
const mergeMaterials = list => {
  const known = new Set(materialsList.value.map(m => m.material_no));
  materialsList.value.push(...list.filter(m => !known.has(m.material_no)));
};
const loadMaterials = async (q = '') => {
  try {
    const { data } = await MesMaterialAPI.get(q ? { q } : {});
    mergeMaterials(data.payload || []);
  } catch {
    // 搜索失败不阻塞录入
  }
};
const onCodeSearch = (row, term) => {
  row.codeSearch = term || '';
  if (row.codeSearch.trim()) loadMaterials(row.codeSearch.trim());
};

// 下拉选项：档案匹配项在前；输入了新编码（档案没有）则附「新建」项；当前值兜底保显示。
const codeOptionsFor = row => {
  const raw = (row.codeSearch || '').trim();
  const term = raw.toLowerCase();
  let list = materialsList.value;
  if (term) {
    list = list.filter(
      m =>
        (m.material_no || '').toLowerCase().includes(term) ||
        (m.name || '').includes(raw)
    );
  }
  const opts = list.slice(0, 50).map(m => ({
    value: m.material_no,
    label: `${m.material_no}｜${m.name}`,
  }));
  const exists = materialsList.value.some(
    m => (m.material_no || '').toLowerCase() === term
  );
  if (raw && !exists) {
    opts.push({ value: raw, label: `新编码「${raw}」（保存后自动建档）` });
  }
  if (row.materialCode && !opts.some(o => o.value === row.materialCode)) {
    opts.unshift({ value: row.materialCode, label: row.materialCode });
  }
  return opts;
};

// 旧物料分类映射到 SKU 仓别五档（RAW→主料 / CONSUMABLE→辅料）。
const LEGACY_CAT_MAP = { RAW: 'RAW_MAIN', CONSUMABLE: 'RAW_AUX', SEMI: 'SEMI' };
const selectCode = (row, v) => {
  row.materialCode = v || '';
  const hit = materialsList.value.find(m => m.material_no === v);
  if (!hit) return;
  row.name = hit.name || row.name;
  row.specification = hit.specification || row.specification;
  row.unit = hit.unit || row.unit;
  const cat = LEGACY_CAT_MAP[hit.category] || hit.category;
  if (skuCategoryValues.includes(cat)) row.category = cat;
};

const blankForm = () => ({
  supplierNo: '',
  name: '',
  productLine: '',
  department: '',
  category: '',
  contactName: '',
  phone: '',
  email: '',
  address: '',
  taxRate: '',
  invoiceTitle: '',
  taxNo: '',
  bankName: '',
  bankAccount: '',
  bankAddress: '',
  remark: '',
  isActive: true,
  items: [blankItem()],
});

const dialogRef = ref(null);
const editingId = ref(null);
const removedItemIds = ref([]);
// 存量供应商可能还没录物料（历史数据），编辑时不强制补齐；新建一律必填。
const hadItems = ref(false);
const form = reactive(blankForm());

// 含税单价 = 未税单价 × (1 + 税率%)，随表单税率实时算。
const taxedPrice = row => {
  const price = Number(row.unitPrice);
  if (!row.unitPrice || Number.isNaN(price)) return '—';
  const rate = Number(form.taxRate);
  if (!form.taxRate || Number.isNaN(rate)) return price.toFixed(2);
  return (price * (1 + rate / 100)).toFixed(2);
};

const itemRowInvalid = row =>
  !row.materialCode.trim() ||
  !row.category ||
  !row.name.trim() ||
  !row.color.trim() ||
  !row.specification.trim() ||
  !row.unit.trim() ||
  row.unitPrice === '' ||
  Number.isNaN(Number(row.unitPrice)) ||
  Number(row.unitPrice) < 0;

const duplicateCodes = computed(() => {
  const codes = form.items.map(r => r.materialCode.trim()).filter(Boolean);
  return new Set(codes.filter((c, i) => codes.indexOf(c) !== i));
});

const itemsRequired = computed(() => !editingId.value || hadItems.value);
const invalid = computed(() => {
  if (!form.name.trim()) return true;
  if (itemsRequired.value && !form.items.length) return true;
  if (form.items.some(itemRowInvalid)) return true;
  if (duplicateCodes.value.size) return true;
  return false;
});

const addItem = () => form.items.push(blankItem());
const removeItem = idx => {
  const row = form.items[idx];
  if (row.id) removedItemIds.value.push(row.id);
  form.items.splice(idx, 1);
};

const openCreate = () => {
  editingId.value = null;
  removedItemIds.value = [];
  hadItems.value = false;
  Object.assign(form, blankForm());
  loadMaterials();
  dialogRef.value?.open();
};
const openEdit = s => {
  editingId.value = s.id;
  removedItemIds.value = [];
  hadItems.value = (s.supplierItems || []).length > 0;
  Object.assign(form, {
    supplierNo: s.supplierNo || '',
    name: s.name || '',
    productLine: s.productLine || '',
    department: s.department || '',
    category: s.category || '',
    contactName: s.contactName || '',
    phone: s.phone || '',
    email: s.email || '',
    address: s.address || '',
    taxRate: s.taxRate ?? '',
    invoiceTitle: s.invoiceTitle || '',
    taxNo: s.taxNo || '',
    bankName: s.bankName || '',
    bankAccount: s.bankAccount || '',
    bankAddress: s.bankAddress || '',
    remark: s.remark || '',
    isActive: s.isActive !== false,
    items: (s.supplierItems || []).map(it => ({
      id: it.id,
      materialCode: it.materialCode || '',
      codeSearch: '',
      category: it.category || '',
      name: it.name || '',
      color: it.color || '',
      specification: it.specification || '',
      unit: it.unit || '',
      unitPrice: it.unitPrice ?? '',
    })),
  });
  if (!form.items.length && !hadItems.value) form.items.push(blankItem());
  loadMaterials();
  dialogRef.value?.open();
};

const submit = async () => {
  if (invalid.value) return;
  const trimmed = v => (typeof v === 'string' ? v.trim() : v);
  const itemsAttributes = [
    ...form.items.map(r => ({
      id: r.id || undefined,
      materialCode: r.materialCode.trim(),
      category: r.category,
      name: r.name.trim(),
      color: r.color.trim(),
      specification: r.specification.trim(),
      unit: r.unit.trim(),
      unitPrice: Number(r.unitPrice),
    })),
    ...removedItemIds.value.map(id => ({ id, _destroy: true })),
  ];
  const payload = {
    supplierNo: trimmed(form.supplierNo) || null,
    name: form.name.trim(),
    productLine: form.productLine || null,
    department: trimmed(form.department) || null,
    category: trimmed(form.category) || null,
    contactName: trimmed(form.contactName) || null,
    phone: trimmed(form.phone) || null,
    email: trimmed(form.email) || null,
    address: trimmed(form.address) || null,
    taxRate: form.taxRate === '' ? null : form.taxRate,
    invoiceTitle: trimmed(form.invoiceTitle) || null,
    taxNo: trimmed(form.taxNo) || null,
    bankName: trimmed(form.bankName) || null,
    bankAccount: trimmed(form.bankAccount) || null,
    bankAddress: trimmed(form.bankAddress) || null,
    remark: trimmed(form.remark) || null,
    isActive: form.isActive,
    supplierItemsAttributes: itemsAttributes,
  };
  const ok = editingId.value
    ? await store.update({ id: editingId.value, ...payload })
    : await store.create(payload);
  if (ok) {
    useAlert(
      editingId.value ? '供应商已更新' : `已新增供应商 ${ok.supplierNo}`
    );
    dialogRef.value?.close();
  }
};

// 停用/启用：改 is_active，不删数据（保住物料默认供应商 / 采购单的引用）。
const toggleActive = async s => {
  const ok = await store.update({ id: s.id, isActive: !s.isActive });
  if (ok) useAlert(ok.isActive ? '已启用' : '已停用');
};

const confirmRef = ref(null);
const deleting = ref(null);
const askDelete = s => {
  deleting.value = s;
  confirmRef.value?.open();
};
const doDelete = async () => {
  if (!deleting.value) return;
  const ok = await store.delete(deleting.value.id);
  if (ok) useAlert('供应商已删除');
  confirmRef.value?.close();
  deleting.value = null;
};

onMounted(() => {
  store.get();
  loadMaterials();
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div
      class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 px-4 py-3 sm:px-6 sm:py-4"
    >
      <h1 class="text-xl font-semibold text-n-slate-12">供应商</h1>
      <div class="flex flex-wrap items-center gap-2">
        <SelectCard
          :model-value="itemCategory"
          :options="skuCategoryFilterOptions"
          class="w-full sm:w-44"
          @update:model-value="changeCategoryFilter"
        />
        <input
          v-model="keyword"
          placeholder="搜索编号 / 名称"
          class="h-9 px-3 text-sm rounded-lg outline-none w-full sm:w-56 border border-n-weak bg-n-solid-1 text-n-slate-12"
          @keyup.enter="load"
        />
        <Button
          label="搜索"
          variant="outline"
          color="slate"
          size="sm"
          @click="load"
        />
        <Button
          v-if="canManage"
          label="新增供应商"
          color="iris"
          size="sm"
          @click="openCreate"
        />
      </div>
    </div>

    <div class="flex-1 min-h-0 px-4 pb-4 sm:px-6 sm:pb-6 overflow-auto">
      <p v-if="!canManage" class="mb-3 text-xs text-n-slate-11">
        供应商档案由采购 / PMC 维护，你当前为只读。
      </p>
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <template v-else>
        <!-- 手机卡片列表 -->
        <div class="flex flex-col gap-2 md:hidden">
          <div
            v-for="s in records"
            :key="s.id"
            class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl active:bg-n-alpha-1"
            @click="canManage && openEdit(s)"
          >
            <div class="flex items-center gap-2">
              <span class="font-medium text-n-slate-12 truncate">
                {{ s.name }}
              </span>
              <span
                class="shrink-0 px-2 py-0.5 text-xs rounded-full"
                :class="
                  s.isActive
                    ? 'bg-n-teal-3 text-n-teal-12'
                    : 'bg-n-slate-4 text-n-slate-11'
                "
              >
                {{ s.isActive ? '启用' : '已停用' }}
              </span>
              <span class="flex-1" />
              <span class="shrink-0 font-mono text-xs text-n-slate-11">
                {{ s.supplierNo }}
              </span>
            </div>
            <div
              class="mt-1 flex flex-wrap gap-x-3 gap-y-1 text-xs text-n-slate-11"
            >
              <span>事业部：{{ productLineLabel(s.productLine) || '—' }}</span>
              <span>分类：{{ s.category || '—' }}</span>
              <span>联系人：{{ s.contactName || '—' }}</span>
              <span>电话：{{ s.phone || '—' }}</span>
              <span>供应物料：{{ (s.supplierItems || []).length || '—' }}</span>
            </div>
            <div v-if="canManage" class="mt-2 flex flex-wrap gap-1">
              <Button
                label="编辑"
                variant="ghost"
                size="sm"
                @click.stop="openEdit(s)"
              />
              <Button
                :label="s.isActive ? '停用' : '启用'"
                variant="ghost"
                color="slate"
                size="sm"
                @click.stop="toggleActive(s)"
              />
              <Button
                label="删除"
                variant="ghost"
                color="ruby"
                size="sm"
                @click.stop="askDelete(s)"
              />
            </div>
          </div>
          <div v-if="!records.length" class="py-10 text-center text-n-slate-11">
            还没有供应商。
          </div>
        </div>

        <table class="hidden md:table w-full text-sm">
          <thead>
            <tr class="text-left text-n-slate-11 border-b border-n-weak">
              <th class="px-3 py-3 font-medium">编号</th>
              <th class="px-3 py-3 font-medium">名称</th>
              <th class="px-3 py-3 font-medium">事业部</th>
              <th class="px-3 py-3 font-medium">分类</th>
              <th class="px-3 py-3 font-medium">联系人</th>
              <th class="px-3 py-3 font-medium">电话</th>
              <th class="px-3 py-3 font-medium">供应物料</th>
              <th class="px-3 py-3 font-medium">状态</th>
              <th class="px-3 py-3 font-medium text-right">操作</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="s in records" :key="s.id" class="border-b border-n-weak">
              <td class="px-3 py-3 font-mono text-n-slate-11">
                {{ s.supplierNo }}
              </td>
              <td class="px-3 py-3 font-medium text-n-slate-12">
                {{ s.name }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ productLineLabel(s.productLine) || '—' }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">{{ s.category || '—' }}</td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ s.contactName || '—' }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">{{ s.phone || '—' }}</td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ (s.supplierItems || []).length || '—' }}
              </td>
              <td class="px-3 py-3">
                <span
                  class="px-2 py-0.5 text-xs rounded-full"
                  :class="
                    s.isActive
                      ? 'bg-n-teal-3 text-n-teal-12'
                      : 'bg-n-slate-4 text-n-slate-11'
                  "
                >
                  {{ s.isActive ? '启用' : '已停用' }}
                </span>
              </td>
              <td class="px-3 py-3">
                <div v-if="canManage" class="flex justify-end gap-1">
                  <Button
                    label="编辑"
                    variant="ghost"
                    size="sm"
                    @click="openEdit(s)"
                  />
                  <Button
                    :label="s.isActive ? '停用' : '启用'"
                    variant="ghost"
                    color="slate"
                    size="sm"
                    @click="toggleActive(s)"
                  />
                  <Button
                    label="删除"
                    variant="ghost"
                    color="ruby"
                    size="sm"
                    @click="askDelete(s)"
                  />
                </div>
                <span v-else class="block text-right text-n-slate-10">—</span>
              </td>
            </tr>
            <tr v-if="!records.length">
              <td colspan="9" class="px-3 py-10 text-center text-n-slate-11">
                还没有供应商。
              </td>
            </tr>
          </tbody>
        </table>
      </template>
    </div>

    <Dialog
      ref="dialogRef"
      width="6xl"
      overflow-y-auto
      confirm-button-color="iris"
      :title="editingId ? '编辑供应商' : '新增供应商'"
      :is-loading="saving"
      :disable-confirm-button="invalid"
      @confirm="submit"
    >
      <div class="flex flex-col gap-5">
        <!-- 基本信息 -->
        <div class="flex flex-col gap-4">
          <h3 class="text-heading-3 font-semibold text-n-slate-12">基本信息</h3>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div class="flex flex-col gap-1">
              <label class="text-heading-3 text-n-slate-12">供应商编码</label>
              <Input
                v-model="form.supplierNo"
                placeholder="留空自动生成 SUPxxxx"
              />
            </div>
            <div class="flex flex-col gap-1">
              <label class="text-heading-3 text-n-slate-12">
                供应商名称 <span class="text-n-ruby-11">*</span>
              </label>
              <Input v-model="form.name" autofocus />
            </div>
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div class="flex flex-col gap-1">
              <label class="text-heading-3 text-n-slate-12">部门</label>
              <Input v-model="form.department" />
            </div>
            <div class="flex flex-col gap-1">
              <label class="text-heading-3 text-n-slate-12">事业部</label>
              <SelectCard
                size="form"
                :model-value="form.productLine"
                :options="productLineOptions"
                @update:model-value="v => (form.productLine = v)"
              />
            </div>
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div class="flex flex-col gap-1">
              <label class="text-heading-3 text-n-slate-12">供应商分类</label>
              <Input
                v-model="form.category"
                placeholder="如 原材料 / 外购成品"
              />
            </div>
            <div class="flex flex-col gap-1">
              <label class="text-heading-3 text-n-slate-12">联系人</label>
              <Input v-model="form.contactName" />
            </div>
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div class="flex flex-col gap-1">
              <label class="text-heading-3 text-n-slate-12">手机</label>
              <Input v-model="form.phone" />
            </div>
            <div class="flex flex-col gap-1">
              <label class="text-heading-3 text-n-slate-12">邮箱</label>
              <Input v-model="form.email" />
            </div>
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">地址</label>
            <Input v-model="form.address" />
          </div>
        </div>

        <!-- 供应物料：编码与物料档案共享同一编码空间，输入已有编码自动带出档案信息 -->
        <div class="flex flex-col gap-3 pt-1 border-t border-n-weak">
          <div class="flex items-center justify-between pt-2">
            <h3 class="text-heading-3 font-semibold text-n-slate-12">
              供应物料
              <span v-if="itemsRequired" class="text-n-ruby-11">*</span>
            </h3>
            <Button
              type="button"
              label="加一行"
              variant="outline"
              color="slate"
              size="sm"
              @click="addItem"
            />
          </div>
          <p class="text-xs text-n-slate-11">
            物料编码与物料档案共享且唯一：下拉可搜索选择已有编码（自动带出分类/名称/规格/单位）；输入档案没有的新编码可直接选用，保存后自动建物料档案。含税单价按上方税率自动计算。
          </p>
          <div class="overflow-x-auto -mx-4 px-4 md:mx-0 md:px-0">
            <div class="min-w-[720px] md:min-w-0 flex flex-col gap-2">
              <div
                v-if="form.items.length"
                class="grid grid-cols-[repeat(16,minmax(0,1fr))] gap-2 text-xs text-n-slate-11"
              >
                <span class="col-span-3">物料编码 *</span>
                <span class="col-span-2">分类 *</span>
                <span class="col-span-2">产品名称 *</span>
                <span class="col-span-1">颜色 *</span>
                <span class="col-span-2">规格型号 *</span>
                <span class="col-span-1">单位 *</span>
                <span class="col-span-2">未税单价 *</span>
                <span class="col-span-2">含税单价</span>
                <span class="col-span-1" />
              </div>
              <div
                v-for="(row, idx) in form.items"
                :key="idx"
                class="grid grid-cols-[repeat(16,minmax(0,1fr))] gap-2 items-center"
              >
                <div class="col-span-2">
                  <ComboBox
                    :model-value="row.materialCode"
                    :options="codeOptionsFor(row)"
                    use-api-results
                    placeholder="选择/输入编码"
                    search-placeholder="输入编码或名称搜索"
                    @search="term => onCodeSearch(row, term)"
                    @update:model-value="v => selectCode(row, v)"
                  />
                  <p
                    v-if="duplicateCodes.has(row.materialCode.trim())"
                    class="mt-0.5 text-xs text-n-ruby-11"
                  >
                    编码重复
                  </p>
                </div>
                <SelectCard
                  size="form"
                  :model-value="row.category"
                  :options="SKU_CATEGORIES"
                  class="col-span-2"
                  @update:model-value="v => (row.category = v)"
                />
                <Input v-model="row.name" class="col-span-2" />
                <Input v-model="row.color" class="col-span-1" />
                <Input v-model="row.specification" class="col-span-2" />
                <Input
                  v-model="row.unit"
                  class="col-span-1"
                  placeholder="个/件"
                />
                <Input
                  v-model="row.unitPrice"
                  type="number"
                  min="0"
                  step="0.0001"
                  class="col-span-2"
                />
                <span class="col-span-1 text-sm text-n-slate-12">
                  {{ taxedPrice(row) }}
                </span>
                <div class="col-span-1 flex justify-end">
                  <Button
                    type="button"
                    label="删"
                    variant="ghost"
                    color="ruby"
                    size="sm"
                    @click="removeItem(idx)"
                  />
                </div>
              </div>
            </div>
          </div>
          <p
            v-if="itemsRequired && !form.items.length"
            class="text-xs text-n-ruby-11"
          >
            至少需要一条供应物料。
          </p>
        </div>

        <!-- 财务信息 -->
        <div class="flex flex-col gap-4 pt-1 border-t border-n-weak">
          <h3 class="text-heading-3 font-semibold text-n-slate-12 pt-2">
            财务信息
          </h3>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div class="flex flex-col gap-1">
              <label class="text-heading-3 text-n-slate-12">
                增值税税率（%）
              </label>
              <Input v-model="form.taxRate" type="number" placeholder="如 13" />
            </div>
            <div class="flex flex-col gap-1">
              <label class="text-heading-3 text-n-slate-12">开票名称</label>
              <Input v-model="form.invoiceTitle" />
            </div>
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">开票税号</label>
            <Input v-model="form.taxNo" />
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div class="flex flex-col gap-1">
              <label class="text-heading-3 text-n-slate-12">开户行</label>
              <Input v-model="form.bankName" />
            </div>
            <div class="flex flex-col gap-1">
              <label class="text-heading-3 text-n-slate-12">银行账号</label>
              <Input v-model="form.bankAccount" />
            </div>
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">开户地址</label>
            <Input v-model="form.bankAddress" />
          </div>
        </div>

        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">备注</label>
          <Input v-model="form.remark" />
        </div>
        <label class="flex items-center gap-2 text-heading-3 text-n-slate-12">
          <input v-model="form.isActive" type="checkbox" class="w-4 h-4" />
          启用（取消勾选则停用，不出现在采购 / 物料的供应商下拉）
        </label>
      </div>
    </Dialog>

    <Dialog
      ref="confirmRef"
      type="alert"
      width="sm"
      confirm-button-color="ruby"
      title="删除供应商"
      :description="`确定删除「${deleting?.name || ''}」（${deleting?.supplierNo || ''}）？已关联的物料将解除默认供应商引用。`"
      confirm-label="删除"
      @confirm="doDelete"
    />
  </div>
</template>
