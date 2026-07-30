<script setup>
/* global axios */
import { ref, computed, reactive, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesStockEntriesStore } from 'dashboard/stores/mes/stockEntries';
import { useMesWarehousesStore } from 'dashboard/stores/mes/warehouses';
import { useMesMaterialsStore } from 'dashboard/stores/mes/materials';
import MesProductionOrderAPI from 'dashboard/api/mes/productionOrders';

import Button from 'dashboard/components-next/button/Button.vue';
import MesBoardOwnerBar from 'dashboard/components-next/mes/MesBoardOwnerBar.vue';
import { useMesRole } from 'dashboard/composables/useMesRole';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import MesViewDialog from 'dashboard/components-next/mes/MesViewDialog.vue';
import MesReturnControls from 'dashboard/components-next/mes/MesReturnControls.vue';

const { accountId } = useAccount();
const store = useMesStockEntriesStore();
const { mesCan } = useMesRole();
const warehousesStore = useMesWarehousesStore();
const materialsStore = useMesMaterialsStore();

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const saving = computed(() => store.getUIFlags.creatingItem);
const posting = computed(() => store.getUIFlags.updatingItem);
const day = d => (d ? new Date(d).toLocaleDateString() : '—');
const STATUS_LABELS = { DRAFT: '草稿', POSTED: '已过账', CANCELLED: '已取消' };

// 只读查看
const whName = id =>
  (warehousesStore.getRecords || []).find(w => w.id === id)?.name || '—';
const viewDialogRef = ref(null);
const viewing = ref(null);
const openView = e => {
  viewing.value = e;
  viewDialogRef.value?.open();
};
const viewFields = computed(() => {
  const e = viewing.value || {};
  return [
    { label: '单号', value: e.entryNo },
    { label: '生产订单', value: e.productionOrderNo },
    { label: '归属人', value: e.productionOrderOwnerName },
    { label: '领料仓', value: whName(e.fromWarehouseId) },
    { label: '状态', value: STATUS_LABELS[e.status] || e.status },
    { label: '过账时间', value: day(e.postedAt) },
    { label: '制单人', value: e.ownerName },
    { label: '备注', value: e.remark },
  ];
});
const VIEW_ITEM_COLS = [
  { label: '物料编码', key: 'materialNo' },
  { label: '物料名称', key: 'name' },
  { label: '领用量', key: 'qty', align: 'right' },
  { label: '单位', key: 'unit' },
];
const viewItems = computed(() =>
  (viewing.value?.stockEntryItems || []).map(it => ({
    materialNo: it.materialNo,
    name: it.materialName || it.productName,
    qty: it.qty,
    unit: it.unit,
  }))
);

const fetchList = () => store.get({ purpose: 'MATERIAL_ISSUE' });

const productionOrders = ref([]);
const productionOrderOptions = computed(() => [
  { value: '', label: '选择生产订单…' },
  ...productionOrders.value.map(p => ({
    value: String(p.id),
    label: `${p.order_no} · ${p.product_name}`,
  })),
]);
const warehouseOptions = computed(() =>
  (warehousesStore.getRecords || []).map(w => ({
    value: String(w.id),
    label: w.name,
  }))
);
const materialOptions = computed(() =>
  (materialsStore.getRecords || []).map(m => ({
    value: String(m.id),
    label: `${m.name}（${m.unit}）`,
  }))
);

const dialogRef = ref(null);
const form = reactive({
  productionOrderId: '',
  warehouseId: '',
  rows: [], // { mesMaterialId, qty }
});
const invalid = computed(
  () =>
    !form.warehouseId ||
    !form.rows.length ||
    form.rows.some(r => !r.mesMaterialId || !Number(r.qty))
);

const addRow = () => form.rows.push({ mesMaterialId: '', qty: '1' });
const removeRow = i => form.rows.splice(i, 1);

// 按选中生产订单的 BOM 推料。
const pushFromBom = async () => {
  if (!form.productionOrderId) {
    useAlert('请先选生产订单');
    return;
  }
  try {
    const { data } = await MesProductionOrderAPI.requirement(
      form.productionOrderId
    );
    const reqs = data?.payload || [];
    if (!reqs.length) {
      useAlert('该生产订单未挂 BOM 或无用料');
      return;
    }
    form.rows = reqs.map(r => ({
      mesMaterialId: String(r.mes_material_id),
      qty: String(r.qty),
    }));
  } catch {
    useAlert('推料失败');
  }
};

const openCreate = () => {
  const raw = (warehousesStore.getRecords || []).find(w => w.kind === 'RAW');
  Object.assign(form, {
    productionOrderId: '',
    warehouseId: raw ? String(raw.id) : '',
    rows: [{ mesMaterialId: '', qty: '1' }],
  });
  dialogRef.value?.open();
};

const submit = async () => {
  if (invalid.value) return;
  const payload = {
    purpose: 'MATERIAL_ISSUE',
    productionOrderId: form.productionOrderId || null,
    fromWarehouseId: Number(form.warehouseId),
    stockEntryItemsAttributes: form.rows.map(r => ({
      itemType: 'MATERIAL',
      mesMaterialId: Number(r.mesMaterialId),
      qty: Number(r.qty),
      warehouseId: Number(form.warehouseId),
    })),
  };
  const ok = await store.create(payload);
  if (ok) {
    useAlert(`已建领料单 ${ok.entryNo}，待过账`);
    dialogRef.value?.close();
  }
};

const postEntry = async entry => {
  const ok = await store.post(entry.id);
  if (ok) useAlert(`${ok.entryNo} 已过账，库存已扣减`);
};

onMounted(async () => {
  fetchList();
  warehousesStore.get();
  materialsStore.get();
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/production_orders`
    );
    productionOrders.value = data?.payload || [];
  } catch {
    productionOrders.value = [];
  }
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between px-6 py-4">
      <h1 class="text-xl font-semibold text-n-slate-12">生产领料</h1>
      <Button
        v-if="mesCan('stock')"
        label="新建领料单"
        color="iris"
        size="sm"
        @click="openCreate"
      />
    </div>

    <MesBoardOwnerBar board-key="mes_material_issues_index" />

    <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto">
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left text-n-slate-11 border-b border-n-weak">
            <th class="px-3 py-3 font-medium">单号</th>
            <th class="px-3 py-3 font-medium">生产订单</th>
            <th class="px-3 py-3 font-medium">归属人</th>
            <th class="px-3 py-3 font-medium">状态</th>
            <th class="px-3 py-3 font-medium">过账时间</th>
            <th class="px-3 py-3" />
          </tr>
        </thead>
        <tbody>
          <tr v-for="e in records" :key="e.id" class="border-b border-n-weak">
            <td class="px-3 py-3 font-medium text-n-slate-12">
              {{ e.entryNo }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ e.productionOrderNo || '—' }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ e.productionOrderOwnerName || '—' }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ STATUS_LABELS[e.status] }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">{{ day(e.postedAt) }}</td>
            <td class="px-3 py-3 text-right">
              <div class="flex justify-end gap-1">
                <Button
                  label="查看"
                  variant="ghost"
                  size="sm"
                  @click="openView(e)"
                />
                <Button
                  v-if="e.status === 'DRAFT' && mesCan('stock')"
                  label="过账"
                  color="iris"
                  size="sm"
                  :is-loading="posting"
                  @click="postEntry(e)"
                />
                <MesReturnControls
                  :record="e"
                  :store="store"
                  :can-manage="mesCan('stock')"
                />
              </div>
            </td>
          </tr>
          <tr v-if="!records.length">
            <td colspan="6" class="px-3 py-10 text-center text-n-slate-11">
              还没有领料单。
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
      title="新建生产领料单"
      description="选生产订单「按 BOM 推料」自动带出用料，从原料仓领出；过账即扣减库存。"
      :is-loading="saving"
      :disable-confirm-button="invalid"
      @confirm="submit"
    >
      <div class="flex flex-col gap-4">
        <div class="flex items-end gap-2">
          <div class="flex flex-col flex-1 gap-1">
            <label class="text-heading-3 text-n-slate-12">
              生产订单 <span class="text-n-ruby-11">*</span>
            </label>
            <Select
              :model-value="form.productionOrderId"
              :options="productionOrderOptions"
              @update:model-value="v => (form.productionOrderId = v)"
            />
          </div>
          <Button
            label="按 BOM 推料"
            type="button"
            color="slate"
            size="sm"
            @click="pushFromBom"
          />
        </div>

        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">领料仓库</label>
          <Select
            :model-value="form.warehouseId"
            :options="warehouseOptions"
            @update:model-value="v => (form.warehouseId = v)"
          />
        </div>

        <div class="flex items-center justify-between">
          <span class="text-heading-3 text-n-slate-12">
            领料明细 <span class="text-n-ruby-11">*</span>
          </span>
          <Button
            label="+ 加一行"
            type="button"
            variant="ghost"
            size="sm"
            @click="addRow"
          />
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
              placeholder="领用量"
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

    <MesViewDialog
      ref="viewDialogRef"
      :title="viewing ? `领料单 ${viewing.entryNo}` : '领料单明细'"
      :fields="viewFields"
      items-title="领料明细"
      :item-columns="VIEW_ITEM_COLS"
      :items="viewItems"
    />
  </div>
</template>
