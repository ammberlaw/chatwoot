<script setup>
/* global axios */
import { ref, computed, reactive, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesShipmentsStore } from 'dashboard/stores/mes/shipments';
import { useMesWarehousesStore } from 'dashboard/stores/mes/warehouses';

import Button from 'dashboard/components-next/button/Button.vue';
import MesBoardOwnerBar from 'dashboard/components-next/mes/MesBoardOwnerBar.vue';
import { useMesRole } from 'dashboard/composables/useMesRole';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const { accountId } = useAccount();
const store = useMesShipmentsStore();
const { mesCan } = useMesRole();
const warehousesStore = useMesWarehousesStore();

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const saving = computed(() => store.getUIFlags.creatingItem);
const acting = computed(() => store.getUIFlags.updatingItem);
const time = d => (d ? new Date(d).toLocaleString() : '—');
const STATUS_LABELS = { DRAFT: '草稿', SHIPPED: '已出库', CANCELLED: '已取消' };

const productionOrders = ref([]);
const salesOrders = ref([]);
const productionOrderOptions = computed(() => [
  { value: '', label: '选择生产订单…' },
  ...productionOrders.value.map(p => ({
    value: String(p.id),
    label: `${p.order_no} · ${p.product_name}`,
  })),
]);

const dialogRef = ref(null);
const form = reactive({
  productionOrderId: '',
  crmSalesOrderId: '',
  crmCustomerId: '',
  warehouseId: '',
  crmProductId: '',
  productName: '',
  qty: '',
  unit: '',
});
const invalid = computed(() => !form.crmProductId || !Number(form.qty));

// 选生产订单 → 带出销售订单、客户、成品、已产数量。
const onPickOrder = v => {
  form.productionOrderId = v;
  const po = productionOrders.value.find(p => String(p.id) === String(v));
  if (!po) return;
  form.crmSalesOrderId = po.crm_sales_order_id ? String(po.crm_sales_order_id) : '';
  form.crmProductId = po.crm_product_id ? String(po.crm_product_id) : '';
  form.productName = po.product_name || '';
  form.qty = String(po.produced_qty || po.qty || '');
  form.unit = po.unit || '';
  const so = salesOrders.value.find(
    s => String(s.id) === String(po.crm_sales_order_id)
  );
  form.crmCustomerId = so?.crm_customer_id ? String(so.crm_customer_id) : '';
};

const openCreate = () => {
  const fin = (warehousesStore.getRecords || []).find(w => w.kind === 'FINISHED');
  Object.assign(form, {
    productionOrderId: '',
    crmSalesOrderId: '',
    crmCustomerId: '',
    warehouseId: fin ? String(fin.id) : '',
    crmProductId: '',
    productName: '',
    qty: '',
    unit: '',
  });
  dialogRef.value?.open();
};

const submit = async () => {
  if (invalid.value) return;
  const ok = await store.create({
    productionOrderId: form.productionOrderId || null,
    crmSalesOrderId: form.crmSalesOrderId || null,
    crmCustomerId: form.crmCustomerId || null,
    warehouseId: form.warehouseId ? Number(form.warehouseId) : null,
    shipmentItemsAttributes: [
      {
        crmProductId: Number(form.crmProductId),
        qty: Number(form.qty),
        unit: form.unit,
      },
    ],
  });
  if (ok) {
    useAlert(`已建出库单 ${ok.shipmentNo}`);
    dialogRef.value?.close();
  }
};

const notify = async s => {
  const ok = await store.notify(s.id);
  if (ok) useAlert('已通知出库');
};
const ship = async s => {
  const ok = await store.ship(s.id);
  if (ok) useAlert(`${ok.shipmentNo} 已出库，销售订单已回写「已出货」`);
};

onMounted(() => {
  store.get();
  warehousesStore.get();
  const base = `/api/v1/accounts/${accountId.value}`;
  axios
    .get(`${base}/mes/production_orders`)
    .then(({ data }) => {
      productionOrders.value = data?.payload || [];
    })
    .catch(() => {});
  axios
    .get(`${base}/crm/sales_orders`, { params: { per_page: 100 } })
    .then(({ data }) => {
      salesOrders.value = data?.payload || [];
    })
    .catch(() => {});
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between px-6 py-4">
      <h1 class="text-xl font-semibold text-n-slate-12">销售出库</h1>
      <Button v-if="mesCan('shipment')" label="新建出库单" color="iris" size="sm" @click="openCreate" />
    </div>

    <MesBoardOwnerBar board-key="mes_shipments_index" />

    <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto">
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">加载中…</div>
      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left text-n-slate-11 border-b border-n-weak">
            <th class="px-3 py-3 font-medium">出库单号</th>
            <th class="px-3 py-3 font-medium">销售订单</th>
            <th class="px-3 py-3 font-medium">客户</th>
            <th class="px-3 py-3 font-medium">状态</th>
            <th class="px-3 py-3 font-medium">通知/出库</th>
            <th class="px-3 py-3" />
          </tr>
        </thead>
        <tbody>
          <tr v-for="s in records" :key="s.id" class="border-b border-n-weak">
            <td class="px-3 py-3 font-medium text-n-slate-12">
              {{ s.shipmentNo }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">{{ s.salesOrderNo || '—' }}</td>
            <td class="px-3 py-3 text-n-slate-11">{{ s.customerName || '—' }}</td>
            <td class="px-3 py-3 text-n-slate-11">{{ STATUS_LABELS[s.status] }}</td>
            <td class="px-3 py-3 text-xs text-n-slate-11">
              {{ s.notifiedAt ? '已通知' : '—' }} / {{ time(s.shippedAt) }}
            </td>
            <td class="px-3 py-3 text-right">
              <div v-if="s.status === 'DRAFT' && mesCan('shipment')" class="flex justify-end gap-2">
                <Button
                  v-if="!s.notifiedAt"
                  label="通知出库"
                  variant="ghost"
                  size="sm"
                  :is-loading="acting"
                  @click="notify(s)"
                />
                <Button
                  label="出库"
                  color="iris"
                  size="sm"
                  :is-loading="acting"
                  @click="ship(s)"
                />
              </div>
            </td>
          </tr>
          <tr v-if="!records.length">
            <td colspan="6" class="px-3 py-10 text-center text-n-slate-11">
              还没有出库单。
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <Dialog
      ref="dialogRef"
      width="lg"
      confirm-button-color="iris"
      title="新建销售出库单"
      description="选生产订单带出客户与成品，生成出库清单；出库后自动扣成品库存并回写销售订单「已出货」。"
      :is-loading="saving"
      :disable-confirm-button="invalid"
      @confirm="submit"
    >
      <div class="flex flex-col gap-4">
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">生产订单</label>
          <Select
            :model-value="form.productionOrderId"
            :options="productionOrderOptions"
            @update:model-value="onPickOrder"
          />
        </div>
        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              出库成品 <span class="text-n-ruby-11">*</span>
            </label>
            <Input v-model="form.productName" disabled />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              出库数量 <span class="text-n-ruby-11">*</span>
            </label>
            <Input v-model="form.qty" type="number" />
          </div>
        </div>
        <p class="text-xs text-n-slate-11">
          出库清单：{{ form.productName || '（未选）' }} × {{ form.qty || 0 }}
          {{ form.unit }}
        </p>
      </div>
    </Dialog>
  </div>
</template>
