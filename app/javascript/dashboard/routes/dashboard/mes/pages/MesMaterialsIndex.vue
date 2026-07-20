<script setup>
import { ref, computed, reactive, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useMesMaterialsStore } from 'dashboard/stores/mes/materials';
import { useMesSuppliersStore } from 'dashboard/stores/mes/suppliers';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const store = useMesMaterialsStore();
const suppliersStore = useMesSuppliersStore();

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const saving = computed(() => store.getUIFlags.creatingItem);

const CATEGORIES = [
  { value: 'RAW', label: '原料' },
  { value: 'SEMI', label: '半成品' },
  { value: 'CONSUMABLE', label: '耗材' },
];
const categoryLabel = v => CATEGORIES.find(c => c.value === v)?.label || '—';
const categoryOptions = [{ value: '', label: '未分类' }, ...CATEGORIES];

const supplierOptions = computed(() =>
  (suppliersStore.getRecords || []).map(s => ({
    value: String(s.id),
    label: s.name,
  }))
);

const dialogRef = ref(null);
const form = reactive({
  name: '',
  unit: '',
  category: '',
  specification: '',
  safetyStock: '',
  defaultSupplierId: '',
  remark: '',
});
const invalid = computed(() => !form.name.trim() || !form.unit.trim());

const openCreate = () => {
  Object.assign(form, {
    name: '',
    unit: '',
    category: '',
    specification: '',
    safetyStock: '',
    defaultSupplierId: '',
    remark: '',
  });
  if (!suppliersStore.getRecords?.length) suppliersStore.get();
  dialogRef.value?.open();
};
const submit = async () => {
  if (invalid.value) return;
  const ok = await store.create({ ...form });
  if (ok) {
    useAlert(`已新增物料 ${ok.materialNo}`);
    dialogRef.value?.close();
  }
};

onMounted(() => {
  store.get();
  suppliersStore.get();
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between px-6 py-4">
      <h1 class="text-xl font-semibold text-n-slate-12">物料</h1>
      <Button label="新增物料" color="iris" size="sm" @click="openCreate" />
    </div>

    <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto">
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">加载中…</div>
      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left text-n-slate-11 border-b border-n-weak">
            <th class="px-3 py-3 font-medium">编号</th>
            <th class="px-3 py-3 font-medium">名称</th>
            <th class="px-3 py-3 font-medium">类别</th>
            <th class="px-3 py-3 font-medium">单位</th>
            <th class="px-3 py-3 font-medium">规格</th>
            <th class="px-3 py-3 font-medium">安全库存</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="m in records" :key="m.id" class="border-b border-n-weak">
            <td class="px-3 py-3 text-n-slate-11">{{ m.materialNo }}</td>
            <td class="px-3 py-3 font-medium text-n-slate-12">{{ m.name }}</td>
            <td class="px-3 py-3 text-n-slate-11">{{ categoryLabel(m.category) }}</td>
            <td class="px-3 py-3 text-n-slate-11">{{ m.unit }}</td>
            <td class="px-3 py-3 text-n-slate-11">{{ m.specification || '—' }}</td>
            <td class="px-3 py-3 text-n-slate-11">{{ m.safetyStock || '—' }}</td>
          </tr>
          <tr v-if="!records.length">
            <td colspan="6" class="px-3 py-10 text-center text-n-slate-11">
              还没有物料。
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <Dialog
      ref="dialogRef"
      width="lg"
      confirm-button-color="iris"
      title="新增物料"
      :is-loading="saving"
      :disable-confirm-button="invalid"
      @confirm="submit"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              名称 <span class="text-n-ruby-11">*</span>
            </label>
            <Input v-model="form.name" autofocus />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              单位 <span class="text-n-ruby-11">*</span>
            </label>
            <Input v-model="form.unit" placeholder="片 / 个 / kg" />
          </div>
        </div>
        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">类别</label>
            <Select
              :model-value="form.category"
              :options="categoryOptions"
              @update:model-value="v => (form.category = v)"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">安全库存</label>
            <Input v-model="form.safetyStock" type="number" />
          </div>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">规格型号</label>
          <Input v-model="form.specification" />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">默认供应商</label>
          <ComboBox
            v-model="form.defaultSupplierId"
            :options="supplierOptions"
            placeholder="选择供应商（可选）"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">备注</label>
          <Input v-model="form.remark" />
        </div>
      </div>
    </Dialog>
  </div>
</template>
