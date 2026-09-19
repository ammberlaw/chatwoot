<script setup>
import { ref, reactive, computed, nextTick } from 'vue';
import { useAlert } from 'dashboard/composables';
import SalesOrdersAPI from 'dashboard/api/crm/salesOrders';
import MesProductAPI from 'dashboard/api/mes/products';
import MesWarehouseAPI from 'dashboard/api/mes/warehouses';
import MesProductionOrderAPI from 'dashboard/api/mes/productionOrders';
import MesShipmentAPI from 'dashboard/api/mes/shipments';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

// 销售订单一键转下游单据。业务员录一次订单，不用去 MES 再敲一遍客户/产品/数量。
//   定制单 → 生产订单（有 :order 能力直接生效，业务员转的进审批链）
//   库存单 → 现货出库单（提交即预占成品库存，走主管审核）
// 销售订单明细是自由文本（PI 识别填的），下游要产品档案 ID 才能扣库存/带 BOM，
// 所以这里按名称匹配一次，匹配不上的行让业务员选一次。
const emit = defineEmits(['converted']);

const dialogRef = ref(null);
const order = ref(null);
const kind = ref('');
const submitting = ref(false);
const products = ref([]);
const warehouses = ref([]);
const warehouseId = ref('');
// [{ name, qty, unit, productId }]
const rows = reactive([]);

const KIND_OPTIONS = [
  { value: 'CUSTOM', label: '定制单 → 生产订单' },
  { value: 'STOCK', label: '库存单 → 现货出库单' },
];

const productOptions = computed(() =>
  products.value.map(p => ({
    value: p.id,
    label: p.sku ? `${p.name}（${p.sku}）` : p.name,
  }))
);

// 产品档案上千条，不预载——下拉按关键词远程搜，选中的那条并进选项里保持回显。
const searchProducts = async q => {
  const { data } = await MesProductAPI.get({ q, per_page: 30 });
  const found = data?.payload || [];
  const picked = rows.map(r => r.product).filter(Boolean);
  const merged = [...found];
  picked.forEach(p => {
    if (!merged.some(m => m.id === p.id)) merged.push(p);
  });
  products.value = merged;
};

const unmatchedCount = computed(() => rows.filter(r => !r.productId).length);
const canSubmit = computed(
  () =>
    !!kind.value &&
    rows.length > 0 &&
    rows.every(r => r.productId && Number(r.qty) > 0) &&
    (kind.value !== 'STOCK' || !!warehouseId.value)
);

const open = async record => {
  order.value = record;
  kind.value = record.orderKind || '';
  warehouseId.value = '';
  rows.splice(0, rows.length);
  dialogRef.value?.open();

  // 明细→产品档案的匹配放后端（SQL 比前端拉一页回来匹配准得多）。
  const [previewRes, whRes] = await Promise.all([
    SalesOrdersAPI.convertPreview(record.id),
    MesWarehouseAPI.get(),
  ]);
  warehouses.value = whRes.data?.payload || [];
  if (warehouses.value.length === 1) warehouseId.value = warehouses.value[0].id;

  (previewRes.data?.payload || []).forEach(li => {
    const product = li.crm_product_id
      ? { id: li.crm_product_id, name: li.product_name, sku: li.product_sku }
      : null;
    rows.push({
      name: li.name || '',
      qty: li.quantity ?? '',
      unit: li.unit || '',
      productId: li.crm_product_id || '',
      product,
    });
  });
  // 已匹配到的产品先进选项，下拉不搜也能回显名字。
  products.value = rows.map(r => r.product).filter(Boolean);
  // 明细为空的订单（老单/没填明细）给一行空的，手动选产品填数量也能转。
  if (!rows.length)
    rows.push({ name: '', qty: '', unit: '', productId: '', product: null });
  await nextTick();
};

const addRow = () =>
  rows.push({ name: '', qty: '', unit: '', productId: '', product: null });
const removeRow = i => rows.splice(i, 1);

const submitCustom = async () => {
  // 生产订单一单一成品：多行明细时取第一行，其余提示业务员另开单（生产脊柱按成品走）。
  const first = rows[0];
  const { data } = await MesProductionOrderAPI.convert({
    crm_sales_order_id: order.value.id,
    crm_product_id: first.productId,
    qty: first.qty,
    unit: first.unit || undefined,
  });
  return `已生成生产订单 ${data.order_no || ''}`.trim();
};

const submitStock = async () => {
  const { data } = await MesShipmentAPI.convert({
    crm_sales_order_id: order.value.id,
    warehouse_id: warehouseId.value,
    items: rows.map(r => ({
      crm_product_id: r.productId,
      qty: r.qty,
      unit: r.unit || undefined,
    })),
  });
  return `已生成出库单 ${data.shipment_no || ''}，等待主管审核`.trim();
};

const submit = async () => {
  if (!canSubmit.value || submitting.value) return;
  submitting.value = true;
  try {
    const msg =
      kind.value === 'STOCK' ? await submitStock() : await submitCustom();
    useAlert(msg);
    dialogRef.value?.close();
    emit('converted');
  } catch (e) {
    useAlert(e?.response?.data?.error || '转单失败');
  } finally {
    submitting.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="3xl"
    title="转单"
    :show-confirm-button="false"
    :show-cancel-button="false"
  >
    <div v-if="order" class="flex flex-col gap-4">
      <div class="text-sm text-n-slate-11">
        销售订单
        <span class="font-medium text-n-slate-12">{{ order.orderNo }}</span>
        · {{ order.customerName || '未指定客户' }}
      </div>

      <div class="grid grid-cols-2 gap-4">
        <div class="flex flex-col min-w-0 gap-1">
          <label class="text-heading-3 text-n-slate-12">转成什么单</label>
          <SelectCard v-model="kind" block :options="KIND_OPTIONS" />
        </div>
        <div v-if="kind === 'STOCK'" class="flex flex-col min-w-0 gap-1">
          <label class="text-heading-3 text-n-slate-12">出库仓库</label>
          <SelectCard
            v-model="warehouseId"
            block
            :options="warehouses.map(w => ({ value: w.id, label: w.name }))"
          />
        </div>
      </div>
      <span v-if="!order.orderKind" class="-mt-2 text-xs text-n-amber-11">
        这张订单还没标订单类型，这次选的类型不会写回订单；建议回订单里补上，以后转单就自动分流。
      </span>

      <div class="flex flex-col gap-2">
        <div class="flex items-center justify-between">
          <span class="text-heading-3 text-n-slate-12">
            明细
            <span v-if="unmatchedCount" class="text-n-amber-11">
              （有 {{ unmatchedCount }} 行没匹配到产品档案，请手动选）
            </span>
          </span>
          <button
            type="button"
            class="h-8 px-3 text-sm border rounded-lg border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
            @click="addRow"
          >
            加一行
          </button>
        </div>
        <div class="flex items-center gap-2 px-1 text-xs text-n-slate-10">
          <span class="flex-[3]">订单上的品名</span>
          <span class="flex-[3]">对应产品档案</span>
          <span class="flex-1">数量</span>
          <span class="flex-1">单位</span>
          <span class="w-6 shrink-0" />
        </div>
        <div
          v-for="(row, index) in rows"
          :key="index"
          class="flex items-center gap-2"
        >
          <span class="flex-[3] text-sm truncate text-n-slate-11">
            {{ row.name || '—' }}
          </span>
          <ComboBox
            v-model="row.productId"
            class="flex-[3]"
            :options="productOptions"
            placeholder="搜索产品名称 / SKU"
            use-api-results
            @search="searchProducts"
          />
          <Input v-model="row.qty" type="number" class="flex-1" />
          <Input v-model="row.unit" class="flex-1" />
          <button
            type="button"
            class="flex items-center justify-center w-6 shrink-0 text-n-slate-10 hover:text-n-ruby-11"
            @click="removeRow(index)"
          >
            <span class="i-lucide-x size-4" />
          </button>
        </div>
      </div>

      <span
        v-if="kind === 'CUSTOM' && rows.length > 1"
        class="text-xs text-n-amber-11"
      >
        生产订单一单一个成品，只会用第一行；其余品项请在 MES 里另开生产订单。
      </span>

      <div class="flex justify-end gap-2 pt-1">
        <button
          type="button"
          class="h-9 px-4 text-sm font-medium border rounded-lg border-n-weak text-n-slate-12 hover:bg-n-alpha-1"
          @click="dialogRef?.close()"
        >
          取消
        </button>
        <button
          type="button"
          class="h-9 px-4 text-sm font-medium text-white rounded-lg bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-50"
          :disabled="!canSubmit || submitting"
          @click="submit"
        >
          {{ submitting ? '转单中…' : '确认转单' }}
        </button>
      </div>
    </div>
  </Dialog>
</template>
