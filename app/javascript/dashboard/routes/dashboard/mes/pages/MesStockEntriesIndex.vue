<script setup>
/* global axios */
import { ref, computed, reactive, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesStockEntriesStore } from 'dashboard/stores/mes/stockEntries';
import { useMesWarehousesStore } from 'dashboard/stores/mes/warehouses';
import { useMesMaterialsStore } from 'dashboard/stores/mes/materials';

import Button from 'dashboard/components-next/button/Button.vue';
import MesBoardOwnerBar from 'dashboard/components-next/mes/MesBoardOwnerBar.vue';
import { useMesRole } from 'dashboard/composables/useMesRole';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import MesViewDialog from 'dashboard/components-next/mes/MesViewDialog.vue';

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

// S3 主用原料入库；其余 purpose 留给后续切片。
const PURPOSE_LABELS = {
  MATERIAL_RECEIPT: '原料入库',
  MATERIAL_ISSUE: '生产领料',
  MATERIAL_RETURN: '退料',
  MANUFACTURE: '成品入库',
  SCRAP: '清尾报废',
};
const IN_PURPOSES = ['MATERIAL_RECEIPT', 'MATERIAL_RETURN', 'MANUFACTURE'];
const purposeLabel = p => PURPOSE_LABELS[p] || p;
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
    { label: '类型', value: purposeLabel(e.purpose) },
    { label: '采购单', value: e.purchaseOrderNo },
    { label: '生产订单', value: e.productionOrderNo },
    { label: '归属人', value: e.productionOrderOwnerName },
    { label: '入库仓', value: whName(e.toWarehouseId) },
    { label: '状态', value: STATUS_LABELS[e.status] || e.status },
    { label: '过账时间', value: day(e.postedAt) },
    {
      label: '核对',
      value: e.isChecked ? `已核对 · ${e.checkedByName || ''}` : '未核对',
    },
    { label: '收货人', value: e.receivedByName },
    { label: '制单人', value: e.ownerName },
    { label: '备注', value: e.remark },
  ];
});
const VIEW_ITEM_COLS = [
  { label: '物料/产品', key: 'name' },
  { label: '编码', key: 'materialNo' },
  { label: '数量', key: 'qty', align: 'right' },
  { label: '单位', key: 'unit' },
  { label: '备注', key: 'remark' },
];
const viewItems = computed(() =>
  (viewing.value?.stockEntryItems || []).map(it => ({
    name: it.materialName || it.productName,
    materialNo: it.materialNo,
    qty: it.qty,
    unit: it.unit,
    remark: it.remark,
  }))
);

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

// 收货行类型：物料（生产用料）/ 成品（外购贸易品到货，入成品库）。
const ITEM_TYPE_OPTIONS = [
  { value: 'MATERIAL', label: '物料' },
  { value: 'PRODUCT', label: '成品(外购)' },
];
const productOptions = ref([]);
const mergeProductOptions = list => {
  const seen = new Set(productOptions.value.map(o => o.value));
  list.forEach(o => {
    if (!seen.has(o.value)) {
      productOptions.value.push(o);
      seen.add(o.value);
    }
  });
};
const loadProducts = async (q = '') => {
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/crm/products`,
      { params: { filter: 'active', q } }
    );
    mergeProductOptions(
      (data?.payload || []).map(p => ({
        value: String(p.id),
        label: `${p.name}${p.sku ? `（${p.sku}）` : ''}`,
        unit: p.unit || '',
      }))
    );
  } catch {
    // 忽略：搜索失败保留现有选项
  }
};
const productUnit = id =>
  productOptions.value.find(o => o.value === String(id))?.unit || '';
const finishedWarehouseId = () =>
  (warehousesStore.getRecords || []).find(w => w.kind === 'FINISHED')?.id;

const purchaseOrders = ref([]);
const purchaseOrderOptions = computed(() => [
  { value: '', label: '不关联采购单' },
  ...purchaseOrders.value.map(p => ({
    value: String(p.id),
    label: `${p.po_no}${p.supplier_name ? ` · ${p.supplier_name}` : ''}`,
  })),
]);

const dialogRef = ref(null);
const form = reactive({
  purpose: 'MATERIAL_RECEIPT',
  warehouseId: '',
  purchaseOrderId: '',
  productionOrderId: '',
  isChecked: false,
  rows: [], // { itemType, mesMaterialId, qty, receivedQty }
});
const rowIncomplete = r =>
  !Number(r.qty) ||
  (r.itemType === 'PRODUCT' ? !r.crmProductId : !r.mesMaterialId);
const invalid = computed(
  () => !form.warehouseId || !form.rows.length || form.rows.some(rowIncomplete)
);

const addRow = () =>
  form.rows.push({
    itemType: 'MATERIAL',
    mesMaterialId: '',
    crmProductId: '',
    qty: '1',
    receivedQty: '',
  });
const removeRow = i => form.rows.splice(i, 1);

// 选采购单 → 按其明细预填收货行，实收默认等于采购数量。
const prefillFromPO = async () => {
  if (!form.purchaseOrderId) return;
  const po = purchaseOrders.value.find(
    p => String(p.id) === String(form.purchaseOrderId)
  );
  const items = po?.purchase_items || [];
  if (items.length) {
    form.productionOrderId = po.production_order_id
      ? String(po.production_order_id)
      : '';
    form.rows = items.map(it => ({
      itemType: it.item_type || 'MATERIAL',
      mesMaterialId: it.mes_material_id ? String(it.mes_material_id) : '',
      crmProductId: it.crm_product_id ? String(it.crm_product_id) : '',
      qty: String(it.qty),
      receivedQty: String(it.received_qty ? it.qty - it.received_qty : it.qty),
    }));
    // 外购成品到货默认入成品库；把成品标签并入下拉便于查看/改。
    const products = items.filter(it => it.item_type === 'PRODUCT');
    if (products.length) {
      const fin = finishedWarehouseId();
      if (fin) form.warehouseId = String(fin);
      mergeProductOptions(
        products.map(it => ({
          value: String(it.crm_product_id),
          label: `${it.product_name || ''}${it.product_sku ? `（${it.product_sku}）` : ''}`,
          unit: it.unit || '',
        }))
      );
    }
  }
};

const openCreate = () => {
  const raw = (warehousesStore.getRecords || []).find(w => w.kind === 'RAW');
  Object.assign(form, {
    purpose: 'MATERIAL_RECEIPT',
    warehouseId: raw ? String(raw.id) : '',
    purchaseOrderId: '',
    productionOrderId: '',
    isChecked: false,
    rows: [
      {
        itemType: 'MATERIAL',
        mesMaterialId: '',
        crmProductId: '',
        qty: '1',
        receivedQty: '',
      },
    ],
  });
  dialogRef.value?.open();
};

const submit = async () => {
  if (invalid.value) return;
  const inbound = IN_PURPOSES.includes(form.purpose);
  const payload = {
    purpose: form.purpose,
    purchaseOrderId: form.purchaseOrderId || null,
    productionOrderId: form.productionOrderId || null,
    toWarehouseId: inbound ? Number(form.warehouseId) : null,
    fromWarehouseId: inbound ? null : Number(form.warehouseId),
    isChecked: form.isChecked,
    stockEntryItemsAttributes: form.rows.map(r => ({
      itemType: r.itemType,
      mesMaterialId: r.itemType === 'PRODUCT' ? null : Number(r.mesMaterialId),
      crmProductId: r.itemType === 'PRODUCT' ? Number(r.crmProductId) : null,
      unit: r.itemType === 'PRODUCT' ? productUnit(r.crmProductId) : undefined,
      qty: Number(r.qty),
      receivedQty: Number(r.receivedQty) || Number(r.qty),
      warehouseId: Number(form.warehouseId),
    })),
  };
  const ok = await store.create(payload);
  if (ok) {
    useAlert(`已建 ${ok.entryNo}，待过账`);
    dialogRef.value?.close();
  }
};

const postEntry = async entry => {
  const ok = await store.post(entry.id);
  if (ok) useAlert(`${ok.entryNo} 已过账，库存已更新`);
};

onMounted(async () => {
  store.get();
  warehousesStore.get();
  materialsStore.get();
  loadProducts('');
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/purchase_orders`
    );
    purchaseOrders.value = data?.payload || [];
  } catch {
    purchaseOrders.value = [];
  }
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between px-6 py-4">
      <h1 class="text-xl font-semibold text-n-slate-12">原料入库</h1>
      <Button
        v-if="mesCan('stock')"
        label="新建入库单"
        color="iris"
        size="sm"
        @click="openCreate"
      />
    </div>

    <MesBoardOwnerBar board-key="mes_stock_entries_index" />

    <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto">
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left text-n-slate-11 border-b border-n-weak">
            <th class="px-3 py-3 font-medium">单号</th>
            <th class="px-3 py-3 font-medium">类型</th>
            <th class="px-3 py-3 font-medium">采购单</th>
            <th class="px-3 py-3 font-medium">归属人</th>
            <th class="px-3 py-3 font-medium">核对</th>
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
              {{ purposeLabel(e.purpose) }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ e.purchaseOrderNo || '—' }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ e.productionOrderOwnerName || '—' }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ e.isChecked ? '已核对' : '—' }}
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
              </div>
            </td>
          </tr>
          <tr v-if="!records.length">
            <td colspan="8" class="px-3 py-10 text-center text-n-slate-11">
              还没有入库单。
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
      title="新建原料入库单"
      description="可从采购单预填收货明细，核对实收数量后保存，再「过账」刷新库存。"
      :is-loading="saving"
      :disable-confirm-button="invalid"
      @confirm="submit"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">入库仓库</label>
            <Select
              :model-value="form.warehouseId"
              :options="warehouseOptions"
              @update:model-value="v => (form.warehouseId = v)"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              <input v-model="form.isChecked" type="checkbox" class="mr-1" />
              已核对物料齐整度
            </label>
          </div>
        </div>

        <div class="flex items-end gap-2">
          <div class="flex flex-col flex-1 gap-1">
            <label class="text-heading-3 text-n-slate-12">关联采购单</label>
            <Select
              :model-value="form.purchaseOrderId"
              :options="purchaseOrderOptions"
              @update:model-value="v => (form.purchaseOrderId = v)"
            />
          </div>
          <Button
            label="按采购单收货"
            color="slate"
            size="sm"
            @click="prefillFromPO"
          />
        </div>

        <div class="flex items-center justify-between">
          <span class="text-heading-3 text-n-slate-12">
            收货明细 <span class="text-n-ruby-11">*</span>
          </span>
          <Button label="+ 加一行" variant="ghost" size="sm" @click="addRow" />
        </div>
        <div class="grid grid-cols-12 gap-2 text-xs text-n-slate-10">
          <span class="col-span-2">类型</span>
          <span class="col-span-4">物料/成品</span>
          <span class="col-span-2">应收</span>
          <span class="col-span-3">实收(核对)</span>
        </div>
        <div class="flex flex-col gap-2">
          <div
            v-for="(row, i) in form.rows"
            :key="i"
            class="grid items-center grid-cols-12 gap-2"
          >
            <div class="col-span-2">
              <Select
                :model-value="row.itemType"
                :options="ITEM_TYPE_OPTIONS"
                @update:model-value="v => (row.itemType = v)"
              />
            </div>
            <div class="col-span-4">
              <ComboBox
                v-if="row.itemType === 'PRODUCT'"
                v-model="row.crmProductId"
                :options="productOptions"
                use-api-results
                placeholder="选择外购成品"
                @search="loadProducts"
              />
              <ComboBox
                v-else
                v-model="row.mesMaterialId"
                :options="materialOptions"
                placeholder="选择物料"
              />
            </div>
            <Input v-model="row.qty" type="number" class="col-span-2" />
            <Input
              v-model="row.receivedQty"
              type="number"
              placeholder="默认=应收"
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
      :title="viewing ? `入库单 ${viewing.entryNo}` : '入库单明细'"
      :fields="viewFields"
      items-title="收货明细"
      :item-columns="VIEW_ITEM_COLS"
      :items="viewItems"
    />
  </div>
</template>
