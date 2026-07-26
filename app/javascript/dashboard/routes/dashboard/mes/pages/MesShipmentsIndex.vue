<script setup>
/* global axios */
import { ref, computed, reactive, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { useMesShipmentsStore } from 'dashboard/stores/mes/shipments';
import { useMesWarehousesStore } from 'dashboard/stores/mes/warehouses';

import Button from 'dashboard/components-next/button/Button.vue';
import MesBoardOwnerBar from 'dashboard/components-next/mes/MesBoardOwnerBar.vue';
import { useMesRole } from 'dashboard/composables/useMesRole';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import MesViewDialog from 'dashboard/components-next/mes/MesViewDialog.vue';

const { accountId } = useAccount();
const store = useMesShipmentsStore();
const { mesCan } = useMesRole();
const warehousesStore = useMesWarehousesStore();

const currentUserId = useMapGetter('getCurrentUserID');
const currentRole = useMapGetter('getCurrentRole');
const currentUser = useMapGetter('getCurrentUser');
const crmRole = computed(() => currentUser.value?.crm_role);
const isAdmin = computed(() => currentRole.value === 'administrator');
const isAdminLike = computed(
  () => isAdmin.value || crmRole.value === 'deputy_admin'
);
// 主管审核：CRM 部门主管 / 副管理员 / 管理员。
const canApprove = computed(
  () => isAdminLike.value || crmRole.value === 'manager'
);
// 仓库出库能力。
const canShip = computed(() => mesCan('shipment'));
// 现货出库开单：CRM 业务条线（业务员/主管/副管理员）或管理员。
const BUSINESS_ROLES = ['sales', 'manager', 'deputy_admin'];
const canOpenStock = computed(
  () => isAdmin.value || BUSINESS_ROLES.includes(crmRole.value)
);

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const saving = computed(() => store.getUIFlags.creatingItem);
const acting = computed(() => store.getUIFlags.updatingItem);
const time = d => (d ? new Date(d).toLocaleString() : '—');
const STATUS_LABELS = {
  DRAFT: '草稿',
  PENDING_APPROVAL: '待审核',
  APPROVED: '待出库',
  REJECTED: '已驳回',
  SHIPPED: '已出库',
  CANCELLED: '已取消',
};
const KIND_LABELS = { PRODUCTION: '生产出库', STOCK: '现货出库' };

// 单据可执行的动作判定（按类型/状态/角色）。
const canApproveRow = s =>
  s.kind === 'STOCK' &&
  s.status === 'PENDING_APPROVAL' &&
  canApprove.value &&
  (isAdminLike.value || s.managerId === currentUserId.value);
const canResubmitRow = s =>
  s.kind === 'STOCK' &&
  s.status === 'REJECTED' &&
  (s.ownerId === currentUserId.value || isAdminLike.value);
const canShipRow = s =>
  canShip.value &&
  ((s.kind === 'STOCK' && s.status === 'APPROVED') ||
    (s.kind === 'PRODUCTION' && s.status === 'DRAFT'));

// 只读查看
const viewDialogRef = ref(null);
const viewing = ref(null);
const openView = s => {
  viewing.value = s;
  viewDialogRef.value?.open();
};
const viewFields = computed(() => {
  const s = viewing.value || {};
  return [
    { label: '出库单号', value: s.shipmentNo },
    { label: '类型', value: KIND_LABELS[s.kind] || s.kind },
    { label: '销售订单', value: s.salesOrderNo },
    { label: '客户', value: s.customerName },
    { label: '生产订单', value: s.productionOrderNo },
    { label: '归属人', value: s.productionOrderOwnerName || s.ownerName },
    { label: '状态', value: STATUS_LABELS[s.status] || s.status },
    { label: '审核人', value: s.managerName },
    { label: '审核时间', value: time(s.approvedAt) },
    { label: '驳回原因', value: s.rejectReason },
    { label: '通知时间', value: time(s.notifiedAt) },
    { label: '出库时间', value: time(s.shippedAt) },
    { label: '制单人', value: s.ownerName },
    { label: '备注', value: s.remark },
  ];
});
const VIEW_ITEM_COLS = [
  { label: '成品', key: 'productName' },
  { label: '数量', key: 'qty', align: 'right' },
  { label: '单位', key: 'unit' },
];

const productionOrders = ref([]);
const salesOrders = ref([]);
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

// ── CRM 成品 / 客户 服务端搜索选项 ──
const productOptions = ref([]);
const mergeOptions = (target, list) => {
  const seen = new Set(target.value.map(o => o.value));
  list.forEach(o => {
    if (!seen.has(o.value)) {
      target.value.push(o);
      seen.add(o.value);
    }
  });
};
const loadProducts = async (q = '') => {
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/products`,
      { params: { filter: 'active', q } }
    );
    mergeOptions(
      productOptions,
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

const customerOptions = ref([]);
const loadCustomers = async (q = '') => {
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/crm/customers`,
      { params: { q, per_page: 30 } }
    );
    mergeOptions(
      customerOptions,
      (data?.payload || []).map(c => ({ value: String(c.id), label: c.name }))
    );
  } catch {
    // 忽略
  }
};

// 成品现货结存（供开单时参考）。
const stockBalances = ref([]);
const loadStock = async () => {
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/stock_balances`,
      { params: { item_type: 'PRODUCT' } }
    );
    stockBalances.value = data?.payload || [];
  } catch {
    stockBalances.value = [];
  }
};
// 可用现货 = 物理结存 − 其他待出库单预占（后端返回 available_qty）。
const stockFor = (productId, warehouseId) => {
  if (!productId) return 0;
  const rows = stockBalances.value.filter(
    b => String(b.crm_product_id) === String(productId)
  );
  const scoped = warehouseId
    ? rows.filter(b => String(b.warehouse_id) === String(warehouseId))
    : rows;
  return scoped.reduce(
    (sum, b) => sum + Number(b.available_qty ?? b.qty ?? 0),
    0
  );
};

// ── 生产出库（原样，仓库从生产订单开单）──
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

const onPickOrder = v => {
  form.productionOrderId = v;
  const po = productionOrders.value.find(p => String(p.id) === String(v));
  if (!po) return;
  form.crmSalesOrderId = po.crm_sales_order_id
    ? String(po.crm_sales_order_id)
    : '';
  form.crmProductId = po.crm_product_id ? String(po.crm_product_id) : '';
  form.productName = po.product_name || '';
  form.qty = String(po.produced_qty || po.qty || '');
  form.unit = po.unit || '';
  const so = salesOrders.value.find(
    s => String(s.id) === String(po.crm_sales_order_id)
  );
  form.crmCustomerId = so?.crm_customer_id ? String(so.crm_customer_id) : '';
};

const finishedWarehouseId = () =>
  (warehousesStore.getRecords || []).find(w => w.kind === 'FINISHED')?.id;

const openCreate = () => {
  const fin = finishedWarehouseId();
  Object.assign(form, {
    productionOrderId: '',
    crmSalesOrderId: '',
    crmCustomerId: '',
    warehouseId: fin ? String(fin) : '',
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
    kind: 'PRODUCTION',
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

// ── 现货出库（业务员开单 → 主管审核 → 仓库出库）──
const stockDialogRef = ref(null);
const stockForm = reactive({
  crmCustomerId: '',
  crmSalesOrderId: '',
  warehouseId: '',
  rows: [], // { crmProductId, qty }
});
const stockSalesOrderOptions = computed(() => [
  { value: '', label: '不关联销售订单' },
  ...salesOrders.value
    .filter(
      s =>
        !stockForm.crmCustomerId ||
        String(s.crm_customer_id) === String(stockForm.crmCustomerId)
    )
    .map(s => ({ value: String(s.id), label: s.order_no })),
]);
const stockInvalid = computed(
  () =>
    !stockForm.crmCustomerId ||
    !stockForm.warehouseId ||
    !stockForm.rows.length ||
    stockForm.rows.some(r => !r.crmProductId || !Number(r.qty))
);
const addStockRow = () => stockForm.rows.push({ crmProductId: '', qty: '1' });
const removeStockRow = i => stockForm.rows.splice(i, 1);

const openStockCreate = () => {
  const fin = finishedWarehouseId();
  Object.assign(stockForm, {
    crmCustomerId: '',
    crmSalesOrderId: '',
    warehouseId: fin ? String(fin) : '',
    rows: [{ crmProductId: '', qty: '1' }],
  });
  loadCustomers('');
  loadProducts('');
  loadStock();
  stockDialogRef.value?.open();
};

const submitStock = async () => {
  if (stockInvalid.value) return;
  const ok = await store.create({
    kind: 'STOCK',
    crmCustomerId: Number(stockForm.crmCustomerId),
    crmSalesOrderId: stockForm.crmSalesOrderId || null,
    warehouseId: Number(stockForm.warehouseId),
    shipmentItemsAttributes: stockForm.rows.map(r => ({
      crmProductId: Number(r.crmProductId),
      qty: Number(r.qty),
      unit: productUnit(r.crmProductId),
    })),
  });
  if (ok) {
    useAlert(`已开现货出库单 ${ok.shipmentNo}，待主管审核`);
    stockDialogRef.value?.close();
  }
};

// ── 动作 ──
const notify = async s => {
  const ok = await store.notify(s.id);
  if (ok) useAlert('已通知出库');
};
const ship = async s => {
  const ok = await store.ship(s.id);
  if (ok) useAlert(`${ok.shipmentNo} 已出库，销售订单已回写「已出货」`);
};
const approve = async s => {
  const ok = await store.approve(s.id);
  if (ok) useAlert(`${ok.shipmentNo} 已审核通过，已推仓库`);
};
const resubmit = async s => {
  const ok = await store.submitApproval(s.id);
  if (ok) useAlert(`${ok.shipmentNo} 已重新提交审核`);
};

// 驳回
const rejectDialogRef = ref(null);
const rejecting = ref(null);
const rejectReason = ref('');
const openReject = s => {
  rejecting.value = s;
  rejectReason.value = '';
  rejectDialogRef.value?.open();
};
const submitReject = async () => {
  if (!rejectReason.value.trim()) return;
  const ok = await store.reject(rejecting.value.id, rejectReason.value.trim());
  if (ok) {
    useAlert(`${ok.shipmentNo} 已驳回`);
    rejectDialogRef.value?.close();
  }
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
      <div class="flex gap-2">
        <Button
          v-if="canOpenStock"
          label="新建现货出库"
          color="teal"
          size="sm"
          @click="openStockCreate"
        />
        <Button
          v-if="canShip"
          label="新建生产出库"
          color="iris"
          size="sm"
          @click="openCreate"
        />
      </div>
    </div>

    <MesBoardOwnerBar board-key="mes_shipments_index" />

    <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto">
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left text-n-slate-11 border-b border-n-weak">
            <th class="px-3 py-3 font-medium">出库单号</th>
            <th class="px-3 py-3 font-medium">类型</th>
            <th class="px-3 py-3 font-medium">销售订单</th>
            <th class="px-3 py-3 font-medium">客户</th>
            <th class="px-3 py-3 font-medium">归属人</th>
            <th class="px-3 py-3 font-medium">状态</th>
            <th class="px-3 py-3" />
          </tr>
        </thead>
        <tbody>
          <tr v-for="s in records" :key="s.id" class="border-b border-n-weak">
            <td class="px-3 py-3 font-medium text-n-slate-12">
              {{ s.shipmentNo }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">
              <span
                class="px-2 py-0.5 rounded text-xs"
                :class="
                  s.kind === 'STOCK'
                    ? 'bg-n-teal-3 text-n-teal-11'
                    : 'bg-n-iris-3 text-n-iris-11'
                "
              >
                {{ KIND_LABELS[s.kind] || s.kind }}
              </span>
            </td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ s.salesOrderNo || '—' }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ s.customerName || '—' }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ s.productionOrderOwnerName || s.ownerName || '—' }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ STATUS_LABELS[s.status] }}
            </td>
            <td class="px-3 py-3 text-right">
              <div class="flex justify-end gap-1">
                <Button
                  label="查看"
                  variant="ghost"
                  size="sm"
                  @click="openView(s)"
                />
                <template v-if="canApproveRow(s)">
                  <Button
                    label="审核通过"
                    color="teal"
                    size="sm"
                    :is-loading="acting"
                    @click="approve(s)"
                  />
                  <Button
                    label="驳回"
                    variant="ghost"
                    size="sm"
                    @click="openReject(s)"
                  />
                </template>
                <Button
                  v-if="canResubmitRow(s)"
                  label="重新提交"
                  color="amber"
                  size="sm"
                  :is-loading="acting"
                  @click="resubmit(s)"
                />
                <Button
                  v-if="
                    s.kind === 'PRODUCTION' &&
                    s.status === 'DRAFT' &&
                    canShip &&
                    !s.notifiedAt
                  "
                  label="通知出库"
                  variant="ghost"
                  size="sm"
                  :is-loading="acting"
                  @click="notify(s)"
                />
                <Button
                  v-if="canShipRow(s)"
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
            <td colspan="7" class="px-3 py-10 text-center text-n-slate-11">
              还没有出库单。
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- 生产出库（仓库从生产订单开单，原样）-->
    <Dialog
      ref="dialogRef"
      width="lg"
      confirm-button-color="iris"
      title="新建生产出库单"
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

    <!-- 现货出库（业务员开单 → 主管审核 → 仓库出库）-->
    <Dialog
      ref="stockDialogRef"
      width="3xl"
      overflow-y-auto
      confirm-button-color="teal"
      title="新建现货出库单"
      description="从成品库存直接出货：选客户与成品（显示现货结存），提交后经部门主管审核，通过即推仓库出库。"
      :is-loading="saving"
      :disable-confirm-button="stockInvalid"
      @confirm="submitStock"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              客户 <span class="text-n-ruby-11">*</span>
            </label>
            <ComboBox
              v-model="stockForm.crmCustomerId"
              :options="customerOptions"
              use-api-results
              placeholder="搜索客户"
              @search="loadCustomers"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">销售订单</label>
            <Select
              :model-value="stockForm.crmSalesOrderId"
              :options="stockSalesOrderOptions"
              @update:model-value="v => (stockForm.crmSalesOrderId = v)"
            />
          </div>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">
            出库成品仓 <span class="text-n-ruby-11">*</span>
          </label>
          <Select
            :model-value="stockForm.warehouseId"
            :options="warehouseOptions"
            @update:model-value="v => (stockForm.warehouseId = v)"
          />
        </div>

        <div class="flex items-center justify-between">
          <span class="text-heading-3 text-n-slate-12">
            出库清单 <span class="text-n-ruby-11">*</span>
          </span>
          <Button
            label="+ 加一行"
            type="button"
            variant="ghost"
            size="sm"
            @click="addStockRow"
          />
        </div>
        <div class="grid grid-cols-12 gap-2 text-xs text-n-slate-10">
          <span class="col-span-6">成品</span>
          <span class="col-span-2">数量</span>
          <span class="col-span-3">可用现货</span>
        </div>
        <div class="flex flex-col gap-2">
          <div
            v-for="(row, i) in stockForm.rows"
            :key="i"
            class="grid items-center grid-cols-12 gap-2"
          >
            <div class="col-span-6">
              <ComboBox
                v-model="row.crmProductId"
                :options="productOptions"
                use-api-results
                placeholder="搜索成品"
                @search="loadProducts"
              />
            </div>
            <Input v-model="row.qty" type="number" class="col-span-2" />
            <span
              class="col-span-3 text-sm"
              :class="
                stockFor(row.crmProductId, stockForm.warehouseId) <
                Number(row.qty || 0)
                  ? 'text-n-ruby-11'
                  : 'text-n-slate-11'
              "
            >
              {{ stockFor(row.crmProductId, stockForm.warehouseId) }}
            </span>
            <button
              type="button"
              class="col-span-1 text-n-slate-10 hover:text-n-ruby-11"
              @click="removeStockRow(i)"
            >
              ✕
            </button>
          </div>
        </div>
        <p class="text-xs text-n-slate-11">
          「可用现货」= 结存 −
          其他待出库单预占；低于出库量的行标红。提交后即预占这批数量，别人看到的可用现货相应减少；驳回或出库后自动释放。
        </p>
      </div>
    </Dialog>

    <!-- 驳回原因 -->
    <Dialog
      ref="rejectDialogRef"
      width="md"
      confirm-button-color="ruby"
      title="驳回现货出库单"
      :disable-confirm-button="!rejectReason.trim()"
      @confirm="submitReject"
    >
      <div class="flex flex-col gap-2">
        <label class="text-heading-3 text-n-slate-12">
          驳回原因 <span class="text-n-ruby-11">*</span>
        </label>
        <Input
          v-model="rejectReason"
          placeholder="请填写驳回原因，退回业务员修改"
        />
      </div>
    </Dialog>

    <MesViewDialog
      ref="viewDialogRef"
      :title="viewing ? `出库单 ${viewing.shipmentNo}` : '出库单明细'"
      :fields="viewFields"
      items-title="出库成品"
      :item-columns="VIEW_ITEM_COLS"
      :items="viewing?.shipmentItems || []"
    />
  </div>
</template>
