<script setup>
/* global axios */
import { ref, computed, reactive, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesBomsStore } from 'dashboard/stores/mes/boms';
import { useMesMaterialsStore } from 'dashboard/stores/mes/materials';

import Button from 'dashboard/components-next/button/Button.vue';
import { useMesRole } from 'dashboard/composables/useMesRole';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const { accountId } = useAccount();
const store = useMesBomsStore();
const { mesCan } = useMesRole();
const materialsStore = useMesMaterialsStore();

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const saving = computed(
  () => store.getUIFlags.creatingItem || store.getUIFlags.updatingItem
);

// 按阶段预估天数（不含销售出库/物流）。
const LEAD_STAGES = [
  { key: 'purchasingDays', label: '采购原料' },
  { key: 'materialInboundDays', label: '原料入库' },
  { key: 'pickingDays', label: '生产领料' },
  { key: 'productionDays', label: '生产' },
  { key: 'fgInboundDays', label: '成品入库' },
];

const products = ref([]);
const productOptions = computed(() =>
  products.value.map(p => ({ value: String(p.id), label: p.name }))
);
const materialOptions = computed(() =>
  (materialsStore.getRecords || []).map(m => ({
    value: String(m.id),
    label: `${m.name}（${m.unit}）`,
  }))
);

const dialogRef = ref(null);
const editingId = ref(null);
const removedItemIds = ref([]);
const blankLeadDays = () =>
  Object.fromEntries(LEAD_STAGES.map(s => [s.key, '']));
const form = reactive({
  crmProductId: '',
  baseQty: '1',
  unit: '台',
  ...blankLeadDays(),
  rows: [], // { id?, mesMaterialId, qty }
});

const totalLeadDays = computed(() =>
  LEAD_STAGES.reduce((sum, s) => sum + (Number(form[s.key]) || 0), 0)
);

const invalid = computed(
  () =>
    !form.rows.length ||
    form.rows.some(r => !r.mesMaterialId || !Number(r.qty))
);

const addRow = () => form.rows.push({ mesMaterialId: '', qty: '1' });
const removeRow = i => {
  const [removed] = form.rows.splice(i, 1);
  if (removed?.id) removedItemIds.value.push(removed.id);
};

const openCreate = () => {
  editingId.value = null;
  removedItemIds.value = [];
  Object.assign(form, {
    crmProductId: '',
    baseQty: '1',
    unit: '台',
    ...blankLeadDays(),
    rows: [{ mesMaterialId: '', qty: '1' }],
  });
  dialogRef.value?.open();
};
const openEdit = bom => {
  editingId.value = bom.id;
  removedItemIds.value = [];
  Object.assign(form, {
    crmProductId: bom.crmProductId ? String(bom.crmProductId) : '',
    baseQty: String(bom.baseQty ?? '1'),
    unit: bom.unit || '',
    ...Object.fromEntries(LEAD_STAGES.map(s => [s.key, bom[s.key] ?? ''])),
    rows: (bom.bomItems || []).map(it => ({
      id: it.id,
      mesMaterialId: String(it.mesMaterialId),
      qty: String(it.qty),
    })),
  });
  dialogRef.value?.open();
};

const submit = async () => {
  if (invalid.value) return;
  const itemsAttributes = [
    ...form.rows.map(r => ({
      id: r.id || undefined,
      mesMaterialId: Number(r.mesMaterialId),
      qty: Number(r.qty),
    })),
    ...removedItemIds.value.map(id => ({ id, _destroy: true })),
  ];
  const payload = {
    crmProductId: form.crmProductId || null,
    baseQty: Number(form.baseQty) || 1,
    unit: form.unit,
    ...Object.fromEntries(
      LEAD_STAGES.map(s => [s.key, Number(form[s.key]) || null])
    ),
    bomItemsAttributes: itemsAttributes,
  };
  const ok = editingId.value
    ? await store.update({ id: editingId.value, ...payload })
    : await store.create(payload);
  if (ok) {
    useAlert(editingId.value ? 'BOM 已更新' : `已新建 ${ok.bomNo}`);
    dialogRef.value?.close();
  }
};

onMounted(async () => {
  store.get();
  materialsStore.get();
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/crm/products`
    );
    products.value = data?.payload || data || [];
  } catch {
    products.value = [];
  }
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between px-6 py-4">
      <h1 class="text-xl font-semibold text-n-slate-12">工程 BOM</h1>
      <Button v-if="mesCan('bom')" label="新建 BOM" color="iris" size="sm" @click="openCreate" />
    </div>

    <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto">
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">加载中…</div>
      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left text-n-slate-11 border-b border-n-weak">
            <th class="px-3 py-3 font-medium">BOM 号</th>
            <th class="px-3 py-3 font-medium">成品</th>
            <th class="px-3 py-3 font-medium">基准产量</th>
            <th class="px-3 py-3 font-medium">用料项</th>
            <th class="px-3 py-3 font-medium">预估周期(天)</th>
            <th class="px-3 py-3" />
          </tr>
        </thead>
        <tbody>
          <tr v-for="b in records" :key="b.id" class="border-b border-n-weak">
            <td class="px-3 py-3 font-medium text-n-slate-12">{{ b.bomNo }}</td>
            <td class="px-3 py-3 text-n-slate-11">{{ b.productName || '—' }}</td>
            <td class="px-3 py-3 text-n-slate-11">{{ b.baseQty }} {{ b.unit }}</td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ (b.bomItems || []).length }} 项
            </td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ b.totalLeadDays || '—' }}
            </td>
            <td class="px-3 py-3 text-right">
              <Button
                v-if="mesCan('bom')"
                label="编辑"
                variant="ghost"
                size="sm"
                @click="openEdit(b)"
              />
            </td>
          </tr>
          <tr v-if="!records.length">
            <td colspan="6" class="px-3 py-10 text-center text-n-slate-11">
              还没有 BOM。
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <Dialog
      ref="dialogRef"
      width="3xl"
      overflow-y-auto
      confirm-button-color="iris"
      :title="editingId ? '编辑 BOM' : '新建 BOM'"
      :is-loading="saving"
      :disable-confirm-button="invalid"
      @confirm="submit"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">成品</label>
            <ComboBox
              v-model="form.crmProductId"
              :options="productOptions"
              placeholder="选择成品"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">基准产量 / 单位</label>
            <div class="flex gap-2">
              <Input v-model="form.baseQty" type="number" class="w-20" />
              <Input v-model="form.unit" placeholder="台" />
            </div>
          </div>
        </div>

        <div class="flex flex-col gap-2">
          <div class="flex items-center justify-between">
            <span class="text-heading-3 text-n-slate-12">各阶段预估天数</span>
            <span class="text-xs text-n-slate-11">
              预估周期合计：<span class="font-medium text-n-slate-12">{{ totalLeadDays }}</span> 天
            </span>
          </div>
          <div class="grid grid-cols-5 gap-2">
            <div v-for="s in LEAD_STAGES" :key="s.key" class="flex flex-col gap-1">
              <label class="text-xs text-n-slate-11">{{ s.label }}</label>
              <Input v-model="form[s.key]" type="number" placeholder="天" />
            </div>
          </div>
        </div>

        <div class="flex items-center justify-between pt-2 border-t border-n-weak">
          <span class="text-heading-3 text-n-slate-12">
            用料明细 <span class="text-n-ruby-11">*</span>
          </span>
          <Button label="+ 加一行" variant="ghost" size="sm" @click="addRow" />
        </div>

        <div class="flex flex-col gap-2">
          <div
            v-for="(row, i) in form.rows"
            :key="i"
            class="grid items-center grid-cols-12 gap-2"
          >
            <div class="col-span-8">
              <ComboBox
                v-model="row.mesMaterialId"
                :options="materialOptions"
                placeholder="选择物料"
              />
            </div>
            <Input
              v-model="row.qty"
              type="number"
              placeholder="用量"
              class="col-span-3"
            />
            <button
              type="button"
              class="col-span-1 text-n-slate-10 hover:text-n-ruby-11"
              @click="removeRow(i)"
            >
              ✕
            </button>
          </div>
        </div>
      </div>
    </Dialog>
  </div>
</template>
