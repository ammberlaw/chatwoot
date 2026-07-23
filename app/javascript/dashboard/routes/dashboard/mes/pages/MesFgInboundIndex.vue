<script setup>
/* global axios */
import { ref, computed, reactive, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesStockEntriesStore } from 'dashboard/stores/mes/stockEntries';
import { useMesWarehousesStore } from 'dashboard/stores/mes/warehouses';

import Button from 'dashboard/components-next/button/Button.vue';
import MesBoardOwnerBar from 'dashboard/components-next/mes/MesBoardOwnerBar.vue';
import { useMesRole } from 'dashboard/composables/useMesRole';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import MesViewDialog from 'dashboard/components-next/mes/MesViewDialog.vue';

const { accountId } = useAccount();
const store = useMesStockEntriesStore();
const { mesCan } = useMesRole();
const warehousesStore = useMesWarehousesStore();

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
    { label: '成品仓', value: whName(e.toWarehouseId) },
    { label: '交接', value: e.isChecked ? '已交接' : '未交接' },
    { label: '状态', value: STATUS_LABELS[e.status] || e.status },
    { label: '过账时间', value: day(e.postedAt) },
    { label: '收货人', value: e.receivedByName },
    { label: '制单人', value: e.ownerName },
    { label: '备注', value: e.remark },
  ];
});
const VIEW_ITEM_COLS = [
  { label: '成品', key: 'name' },
  { label: '数量', key: 'qty', align: 'right' },
  { label: '单位', key: 'unit' },
];
const viewItems = computed(() =>
  (viewing.value?.stockEntryItems || []).map(it => ({
    name: it.productName || it.materialName,
    qty: it.qty,
    unit: it.unit,
  }))
);

const fetchList = () => store.get({ purpose: 'MANUFACTURE' });

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

const dialogRef = ref(null);
const form = reactive({
  productionOrderId: '',
  warehouseId: '',
  qty: '',
  isChecked: false,
});
const selectedOrder = computed(() =>
  productionOrders.value.find(p => String(p.id) === String(form.productionOrderId))
);
const invalid = computed(
  () => !form.productionOrderId || !form.warehouseId || !Number(form.qty)
);

// 选生产订单 → 带出已产数量作入库数量默认。
const onPickOrder = v => {
  form.productionOrderId = v;
  const po = productionOrders.value.find(p => String(p.id) === String(v));
  if (po) form.qty = String(po.produced_qty || po.qty || '');
};

const openCreate = () => {
  const fin = (warehousesStore.getRecords || []).find(w => w.kind === 'FINISHED');
  Object.assign(form, {
    productionOrderId: '',
    warehouseId: fin ? String(fin.id) : '',
    qty: '',
    isChecked: false,
  });
  dialogRef.value?.open();
};

const submit = async () => {
  if (invalid.value) return;
  const po = selectedOrder.value;
  const ok = await store.create({
    purpose: 'MANUFACTURE',
    productionOrderId: Number(form.productionOrderId),
    toWarehouseId: Number(form.warehouseId),
    isChecked: form.isChecked,
    stockEntryItemsAttributes: [
      {
        itemType: 'PRODUCT',
        crmProductId: po?.crm_product_id || null,
        qty: Number(form.qty),
        warehouseId: Number(form.warehouseId),
      },
    ],
  });
  if (ok) {
    useAlert(`已建成品入库单 ${ok.entryNo}，待过账`);
    dialogRef.value?.close();
  }
};

const postEntry = async entry => {
  const ok = await store.post(entry.id);
  if (ok) useAlert(`${ok.entryNo} 已过账，成品入库`);
};

onMounted(() => {
  fetchList();
  warehousesStore.get();
  axios
    .get(`/api/v1/accounts/${accountId.value}/mes/production_orders`)
    .then(({ data }) => {
      productionOrders.value = data?.payload || [];
    })
    .catch(() => {
      productionOrders.value = [];
    });
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between px-6 py-4">
      <h1 class="text-xl font-semibold text-n-slate-12">成品入库</h1>
      <Button v-if="mesCan('stock')" label="新建成品入库单" color="iris" size="sm" @click="openCreate" />
    </div>

    <MesBoardOwnerBar board-key="mes_fg_inbound_index" />

    <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto">
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">加载中…</div>
      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left text-n-slate-11 border-b border-n-weak">
            <th class="px-3 py-3 font-medium">单号</th>
            <th class="px-3 py-3 font-medium">生产订单</th>
            <th class="px-3 py-3 font-medium">归属人</th>
            <th class="px-3 py-3 font-medium">交接</th>
            <th class="px-3 py-3 font-medium">状态</th>
            <th class="px-3 py-3 font-medium">过账时间</th>
            <th class="px-3 py-3" />
          </tr>
        </thead>
        <tbody>
          <tr v-for="e in records" :key="e.id" class="border-b border-n-weak">
            <td class="px-3 py-3 font-medium text-n-slate-12">{{ e.entryNo }}</td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ e.productionOrderNo || '—' }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ e.productionOrderOwnerName || '—' }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ e.isChecked ? '已交接' : '—' }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">{{ STATUS_LABELS[e.status] }}</td>
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
              </div>
            </td>
          </tr>
          <tr v-if="!records.length">
            <td colspan="7" class="px-3 py-10 text-center text-n-slate-11">
              还没有成品入库单。
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <Dialog
      ref="dialogRef"
      width="lg"
      confirm-button-color="iris"
      title="新建成品入库单"
      description="选生产订单带出已产数量，入成品仓；确认入库交接后过账刷新库存。"
      :is-loading="saving"
      :disable-confirm-button="invalid"
      @confirm="submit"
    >
      <div class="flex flex-col gap-4">
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">
            生产订单 <span class="text-n-ruby-11">*</span>
          </label>
          <Select
            :model-value="form.productionOrderId"
            :options="productionOrderOptions"
            @update:model-value="onPickOrder"
          />
          <span v-if="selectedOrder" class="text-xs text-n-slate-11">
            {{ selectedOrder.product_name }} · 已产
            {{ selectedOrder.produced_qty }} / {{ selectedOrder.qty }}
          </span>
        </div>
        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              入库数量 <span class="text-n-ruby-11">*</span>
            </label>
            <Input v-model="form.qty" type="number" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">入库仓库</label>
            <Select
              :model-value="form.warehouseId"
              :options="warehouseOptions"
              @update:model-value="v => (form.warehouseId = v)"
            />
          </div>
        </div>
        <label class="flex items-center gap-2 text-heading-3 text-n-slate-12">
          <input v-model="form.isChecked" type="checkbox" />
          已完成入库交接
        </label>
      </div>
    </Dialog>

    <MesViewDialog
      ref="viewDialogRef"
      :title="viewing ? `成品入库单 ${viewing.entryNo}` : '成品入库明细'"
      :fields="viewFields"
      items-title="成品明细"
      :item-columns="VIEW_ITEM_COLS"
      :items="viewItems"
    />
  </div>
</template>
