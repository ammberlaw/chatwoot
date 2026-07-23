<script setup>
/* global axios */
import { ref, computed, reactive, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesPurchaseOrdersStore } from 'dashboard/stores/mes/purchaseOrders';
import { useMesSuppliersStore } from 'dashboard/stores/mes/suppliers';
import { useMesMaterialsStore } from 'dashboard/stores/mes/materials';
import MesPurchaseOrderAPI from 'dashboard/api/mes/purchaseOrders';

import Button from 'dashboard/components-next/button/Button.vue';
import MesBoardOwnerBar from 'dashboard/components-next/mes/MesBoardOwnerBar.vue';
import { useMesRole } from 'dashboard/composables/useMesRole';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import MesViewDialog from 'dashboard/components-next/mes/MesViewDialog.vue';

const { accountId } = useAccount();
const store = useMesPurchaseOrdersStore();
const { mesCan } = useMesRole();
const suppliersStore = useMesSuppliersStore();
const materialsStore = useMesMaterialsStore();

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const saving = computed(
  () => store.getUIFlags.creatingItem || store.getUIFlags.updatingItem
);

const day = d => (d ? new Date(d).toLocaleDateString() : '—');

const STATUS_LABELS = {
  DRAFT: '草稿',
  SUBMITTED: '已下单',
  PARTIAL_RECEIVED: '部分到货',
  RECEIVED: '已到货',
  CANCELLED: '已取消',
};
const statusOptions = Object.entries(STATUS_LABELS).map(([value, label]) => ({
  value,
  label,
}));

// 只读查看
const viewDialogRef = ref(null);
const viewing = ref(null);
const openView = po => {
  viewing.value = po;
  viewDialogRef.value?.open();
};
const viewFields = computed(() => {
  const p = viewing.value || {};
  return [
    { label: '采购单号', value: p.poNo },
    { label: '供应商', value: p.supplierName },
    { label: '生产订单', value: p.productionOrderNo },
    { label: '归属人', value: p.productionOrderOwnerName },
    { label: '状态', value: STATUS_LABELS[p.status] || p.status },
    { label: '回复交期', value: day(p.expectedDate) },
    { label: '跟进日期', value: day(p.followUpDate) },
    {
      label: '异常',
      value: p.hasException ? p.exceptionNote || '有异常' : '无',
    },
    { label: '制单人', value: p.ownerName },
    { label: '备注', value: p.remark },
  ];
});
const VIEW_ITEM_COLS = [
  { label: '类型', key: 'typeLabel' },
  { label: '编码', key: 'code' },
  { label: '名称', key: 'name' },
  { label: '采购量', key: 'qty', align: 'right' },
  { label: '已到料', key: 'receivedQty', align: 'right' },
  { label: '单位', key: 'unit' },
  { label: '备注', key: 'remark' },
];
const viewItems = computed(() =>
  (viewing.value?.purchaseItems || []).map(it => ({
    typeLabel: it.itemType === 'PRODUCT' ? '成品(外购)' : '物料',
    code: it.itemType === 'PRODUCT' ? it.productSku : it.materialNo,
    name: it.itemType === 'PRODUCT' ? it.productName : it.materialName,
    qty: it.qty,
    receivedQty: it.receivedQty,
    unit: it.unit,
    remark: it.remark,
  }))
);

const productionOrders = ref([]);
const productionOrderOptions = computed(() => [
  { value: '', label: '不关联生产订单' },
  ...productionOrders.value.map(p => ({
    value: String(p.id),
    label: `${p.order_no} · ${p.product_name}`,
  })),
]);
const supplierOptions = computed(() =>
  (suppliersStore.getRecords || []).map(s => ({
    value: String(s.id),
    label: s.name,
  }))
);
const materialOptions = computed(() =>
  (materialsStore.getRecords || []).map(m => ({
    value: String(m.id),
    label: `${m.name}（${m.unit}）`,
  }))
);

// 采购行类型：物料（生产用料）/ 成品（外购贸易品，不经过生产部）。
const ITEM_TYPE_OPTIONS = [
  { value: 'MATERIAL', label: '物料' },
  { value: 'PRODUCT', label: '成品(外购)' },
];

// CRM 成品选项：服务端搜索（成品可能较多），并保留已选项的标签。
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

const dialogRef = ref(null);
const editingId = ref(null);
const removedItemIds = ref([]);
const form = reactive({
  mesSupplierId: '',
  productionOrderId: '',
  status: 'DRAFT',
  expectedDate: '',
  followUpDate: '',
  hasException: false,
  exceptionNote: '',
  rows: [], // { id?, itemType, mesMaterialId, crmProductId, qty, remark }
});

const rowIncomplete = r =>
  !Number(r.qty) ||
  (r.itemType === 'PRODUCT' ? !r.crmProductId : !r.mesMaterialId);
const invalid = computed(
  () => !form.rows.length || form.rows.some(rowIncomplete)
);

const addRow = () =>
  form.rows.push({
    itemType: 'MATERIAL',
    mesMaterialId: '',
    crmProductId: '',
    qty: '1',
    remark: '',
  });
const removeRow = i => {
  const [r] = form.rows.splice(i, 1);
  if (r?.id) removedItemIds.value.push(r.id);
};

// 从关联的生产订单 BOM 算料，覆盖当前明细行。
const explode = async () => {
  if (!form.productionOrderId) {
    useAlert('请先选生产订单');
    return;
  }
  try {
    const { data } = await MesPurchaseOrderAPI.requirement(
      form.productionOrderId
    );
    const reqs = data?.payload || [];
    if (!reqs.length) {
      useAlert('该生产订单未挂 BOM 或无用料');
      return;
    }
    form.rows.forEach(r => r.id && removedItemIds.value.push(r.id));
    form.rows = reqs.map(r => ({
      itemType: 'MATERIAL',
      mesMaterialId: r.mes_material_id ? String(r.mes_material_id) : '',
      crmProductId: '',
      qty: String(r.qty),
      remark: [r.material_no, r.material_name, r.specification]
        .filter(Boolean)
        .join(' '),
    }));
  } catch {
    useAlert('算料失败');
  }
};

const resetForm = () => {
  editingId.value = null;
  removedItemIds.value = [];
  Object.assign(form, {
    mesSupplierId: '',
    productionOrderId: '',
    status: 'DRAFT',
    expectedDate: '',
    followUpDate: '',
    hasException: false,
    exceptionNote: '',
    rows: [
      {
        itemType: 'MATERIAL',
        mesMaterialId: '',
        crmProductId: '',
        qty: '1',
        remark: '',
      },
    ],
  });
};

const openCreate = () => {
  resetForm();
  dialogRef.value?.open();
};
const openEdit = po => {
  editingId.value = po.id;
  removedItemIds.value = [];
  Object.assign(form, {
    mesSupplierId: po.mesSupplierId ? String(po.mesSupplierId) : '',
    productionOrderId: po.productionOrderId ? String(po.productionOrderId) : '',
    status: po.status,
    expectedDate: po.expectedDate ? po.expectedDate.slice(0, 10) : '',
    followUpDate: po.followUpDate ? po.followUpDate.slice(0, 10) : '',
    hasException: !!po.hasException,
    exceptionNote: po.exceptionNote || '',
    rows: (po.purchaseItems || []).map(it => ({
      id: it.id,
      itemType: it.itemType || 'MATERIAL',
      mesMaterialId: it.mesMaterialId ? String(it.mesMaterialId) : '',
      crmProductId: it.crmProductId ? String(it.crmProductId) : '',
      qty: String(it.qty),
      remark: it.remark || '',
    })),
  });
  // 回填已选成品的标签，保证下拉能显示名称
  mergeProductOptions(
    (po.purchaseItems || [])
      .filter(it => it.crmProductId)
      .map(it => ({
        value: String(it.crmProductId),
        label: `${it.productName || ''}${it.productSku ? `（${it.productSku}）` : ''}`,
        unit: it.unit || '',
      }))
  );
  dialogRef.value?.open();
};

const submit = async () => {
  if (invalid.value) return;
  const itemsAttributes = [
    ...form.rows.map(r => ({
      id: r.id || undefined,
      itemType: r.itemType,
      mesMaterialId: r.itemType === 'PRODUCT' ? null : Number(r.mesMaterialId),
      crmProductId: r.itemType === 'PRODUCT' ? Number(r.crmProductId) : null,
      unit: r.itemType === 'PRODUCT' ? productUnit(r.crmProductId) : undefined,
      qty: Number(r.qty),
      remark: r.remark || '',
    })),
    ...removedItemIds.value.map(id => ({ id, _destroy: true })),
  ];
  const payload = {
    mesSupplierId: form.mesSupplierId || null,
    productionOrderId: form.productionOrderId || null,
    status: form.status,
    expectedDate: form.expectedDate || null,
    followUpDate: form.followUpDate || null,
    hasException: form.hasException,
    exceptionNote: form.exceptionNote,
    purchaseItemsAttributes: itemsAttributes,
  };
  const ok = editingId.value
    ? await store.update({ id: editingId.value, ...payload })
    : await store.create(payload);
  if (ok) {
    useAlert(editingId.value ? '采购单已更新' : `已新建 ${ok.poNo}`);
    dialogRef.value?.close();
  }
};

onMounted(async () => {
  store.get();
  suppliersStore.get();
  materialsStore.get();
  loadProducts('');
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
      <h1 class="text-xl font-semibold text-n-slate-12">采购单</h1>
      <Button
        v-if="mesCan('purchase')"
        label="新建采购单"
        color="iris"
        size="sm"
        @click="openCreate"
      />
    </div>

    <MesBoardOwnerBar board-key="mes_purchase_orders_index" />

    <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto">
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left text-n-slate-11 border-b border-n-weak">
            <th class="px-3 py-3 font-medium">采购单号</th>
            <th class="px-3 py-3 font-medium">供应商</th>
            <th class="px-3 py-3 font-medium">生产订单</th>
            <th class="px-3 py-3 font-medium">归属人</th>
            <th class="px-3 py-3 font-medium">状态</th>
            <th class="px-3 py-3 font-medium">回复交期</th>
            <th class="px-3 py-3 font-medium">跟进</th>
            <th class="px-3 py-3" />
          </tr>
        </thead>
        <tbody>
          <tr v-for="p in records" :key="p.id" class="border-b border-n-weak">
            <td class="px-3 py-3 font-medium text-n-slate-12">
              {{ p.poNo }}
              <span
                v-if="p.hasException"
                class="ml-1 text-xs text-n-ruby-11"
                title="采购异常"
              >
                ⚠
              </span>
            </td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ p.supplierName || '—' }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ p.productionOrderNo || '—' }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ p.productionOrderOwnerName || '—' }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ STATUS_LABELS[p.status] }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">{{ day(p.expectedDate) }}</td>
            <td class="px-3 py-3 text-n-slate-11">{{ day(p.followUpDate) }}</td>
            <td class="px-3 py-3 text-right">
              <div class="flex justify-end gap-1">
                <Button
                  label="查看"
                  variant="ghost"
                  size="sm"
                  @click="openView(p)"
                />
                <Button
                  v-if="mesCan('purchase')"
                  label="编辑"
                  variant="ghost"
                  size="sm"
                  @click="openEdit(p)"
                />
              </div>
            </td>
          </tr>
          <tr v-if="!records.length">
            <td colspan="8" class="px-3 py-10 text-center text-n-slate-11">
              还没有采购单。
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
      :title="editingId ? '编辑采购单' : '新建采购单'"
      :is-loading="saving"
      :disable-confirm-button="invalid"
      @confirm="submit"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">供应商</label>
            <ComboBox
              v-model="form.mesSupplierId"
              :options="supplierOptions"
              placeholder="选择供应商"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">状态</label>
            <Select
              :model-value="form.status"
              :options="statusOptions"
              @update:model-value="v => (form.status = v)"
            />
          </div>
        </div>

        <div class="flex items-end gap-2">
          <div class="flex flex-col flex-1 gap-1">
            <label class="text-heading-3 text-n-slate-12">关联生产订单</label>
            <Select
              :model-value="form.productionOrderId"
              :options="productionOrderOptions"
              @update:model-value="v => (form.productionOrderId = v)"
            />
          </div>
          <Button label="BOM 算料" color="slate" size="sm" @click="explode" />
        </div>

        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">回复采购时间</label>
            <Input v-model="form.expectedDate" type="date" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">跟进采购时间</label>
            <Input v-model="form.followUpDate" type="date" />
          </div>
        </div>

        <div class="flex flex-col gap-1">
          <label class="flex items-center gap-2 text-heading-3 text-n-slate-12">
            <input v-model="form.hasException" type="checkbox" />
            采购异常
          </label>
          <Input
            v-if="form.hasException"
            v-model="form.exceptionNote"
            placeholder="异常说明"
          />
        </div>

        <div class="flex items-center justify-between">
          <span class="text-heading-3 text-n-slate-12">
            采购明细 <span class="text-n-ruby-11">*</span>
          </span>
          <Button label="+ 加一行" variant="ghost" size="sm" @click="addRow" />
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
            <Input
              v-model="row.qty"
              type="number"
              placeholder="数量"
              class="col-span-2"
            />
            <Input v-model="row.remark" placeholder="备注" class="col-span-3" />
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
      :title="viewing ? `采购单 ${viewing.poNo}` : '采购单明细'"
      :fields="viewFields"
      items-title="采购明细"
      :item-columns="VIEW_ITEM_COLS"
      :items="viewItems"
    />
  </div>
</template>
