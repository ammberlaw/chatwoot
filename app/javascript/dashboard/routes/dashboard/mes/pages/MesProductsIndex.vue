<script setup>
import { ref, computed, reactive, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useMesProductsStore } from 'dashboard/stores/mes/products';
import { useMesRole } from 'dashboard/composables/useMesRole';
import {
  MES_PRODUCT_LINES,
  productLineLabel,
} from 'dashboard/composables/useMesProductLine';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const store = useMesProductsStore();
const { mesCan } = useMesRole();

const records = computed(() => store.getRecords);
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
const load = () =>
  store.get({
    q: keyword.value.trim() || undefined,
    category: categoryFilter.value || undefined,
  });
const changeCategoryFilter = v => {
  categoryFilter.value = v;
  load();
};

const dialogRef = ref(null);
const editingId = ref(null);
const form = reactive({
  name: '',
  sku: '',
  productLine: '',
  category: '',
  unit: '',
  specification: '',
  remark: '',
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

const openCreate = () => {
  editingId.value = null;
  Object.assign(form, {
    name: '',
    sku: '',
    productLine: '',
    category: '',
    unit: '',
    specification: '',
    remark: '',
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
    unit: p.unit || '',
    specification: p.specification || '',
    remark: p.remark || '',
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
    unit: form.unit.trim() || null,
    specification: form.specification.trim() || null,
    remark: form.remark.trim() || null,
    isActive: form.isActive,
  };
  const ok = editingId.value
    ? await store.update({ id: editingId.value, ...payload })
    : await store.create(payload);
  if (ok) {
    useAlert(editingId.value ? '产品已更新' : `已新增产品 ${ok.sku}`);
    dialogRef.value?.close();
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

onMounted(() => store.get());
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between px-6 py-4">
      <h1 class="text-xl font-semibold text-n-slate-12">产品档案</h1>
      <div class="flex items-center gap-2">
        <SelectCard
          :model-value="categoryFilter"
          :options="categoryFilterOptions"
          class="w-44"
          @update:model-value="changeCategoryFilter"
        />
        <input
          v-model="keyword"
          placeholder="搜索编码 / 名称"
          class="h-9 px-3 text-sm rounded-lg outline-none w-56 border border-n-weak bg-n-solid-1 text-n-slate-12"
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
          label="新增产品"
          color="iris"
          size="sm"
          @click="openCreate"
        />
      </div>
    </div>

    <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto">
      <p v-if="!canManage" class="mb-3 text-xs text-n-slate-11">
        产品编码由工程 / PMC 维护，你当前为只读。
      </p>
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left text-n-slate-11 border-b border-n-weak">
            <th class="px-3 py-3 font-medium">商品编码</th>
            <th class="px-3 py-3 font-medium">商品名称</th>
            <th class="px-3 py-3 font-medium">产品线</th>
            <th class="px-3 py-3 font-medium">商品类别</th>
            <th class="px-3 py-3 font-medium">单位</th>
            <th class="px-3 py-3 font-medium">状态</th>
            <th class="px-3 py-3 font-medium text-right">操作</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="p in records" :key="p.id" class="border-b border-n-weak">
            <td class="px-3 py-3 font-mono text-n-slate-11">{{ p.sku }}</td>
            <td class="px-3 py-3 font-medium text-n-slate-12">{{ p.name }}</td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ productLineLabel(p.productLine) || '—' }}
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
            <td colspan="7" class="px-3 py-10 text-center text-n-slate-11">
              还没有产品。
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <Dialog
      ref="dialogRef"
      width="lg"
      confirm-button-color="iris"
      :title="editingId ? '编辑产品' : '新增产品'"
      :is-loading="saving"
      :disable-confirm-button="invalid"
      @confirm="submit"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-2 gap-4">
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
        <div class="grid grid-cols-2 gap-4">
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
            <SelectCard
              size="form"
              :model-value="form.category"
              :options="categoryOptions"
              @update:model-value="v => (form.category = v)"
            />
          </div>
        </div>
        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">单位</label>
            <Input v-model="form.unit" placeholder="台 / 个 / pcs" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">规格型号</label>
            <Input v-model="form.specification" />
          </div>
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
      ref="confirmRef"
      type="alert"
      width="sm"
      confirm-button-color="ruby"
      title="删除产品"
      :description="`确定删除「${deleting?.name || ''}」（${deleting?.sku || ''}）？已关联的 BOM / 采购 / 出库将解除引用。`"
      confirm-label="删除"
      @confirm="doDelete"
    />
  </div>
</template>
