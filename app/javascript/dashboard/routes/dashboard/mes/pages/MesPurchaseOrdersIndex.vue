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
import { useMesRole } from 'dashboard/composables/useMesRole';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

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

const yuan = micros => (micros ? (micros / 1e6).toFixed(2) : '0.00');
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
  rows: [], // { id?, mesMaterialId, qty, rateMicros }
});

const rowAmount = row => (Number(row.qty) || 0) * (Number(row.rateMicros) || 0);
const totalMicros = computed(() =>
  form.rows.reduce((s, r) => s + rowAmount(r), 0)
);
const invalid = computed(
  () =>
    !form.rows.length || form.rows.some(r => !r.mesMaterialId || !Number(r.qty))
);

const addRow = () =>
  form.rows.push({ mesMaterialId: '', qty: '1', rateMicros: '' });
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
    const { data } = await MesPurchaseOrderAPI.requirement(form.productionOrderId);
    const reqs = data?.payload || [];
    if (!reqs.length) {
      useAlert('该生产订单未挂 BOM 或无用料');
      return;
    }
    form.rows.forEach(r => r.id && removedItemIds.value.push(r.id));
    form.rows = reqs.map(r => ({
      mesMaterialId: String(r.mes_material_id),
      qty: String(r.qty),
      rateMicros: r.rate_micros ?? '',
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
    rows: [{ mesMaterialId: '', qty: '1', rateMicros: '' }],
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
      mesMaterialId: String(it.mesMaterialId),
      qty: String(it.qty),
      rateMicros: it.rateMicros ?? '',
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
      rateMicros: Number(r.rateMicros) || 0,
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
      <Button v-if="mesCan('purchase')" label="新建采购单" color="iris" size="sm" @click="openCreate" />
    </div>

    <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto">
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">加载中…</div>
      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left text-n-slate-11 border-b border-n-weak">
            <th class="px-3 py-3 font-medium">采购单号</th>
            <th class="px-3 py-3 font-medium">供应商</th>
            <th class="px-3 py-3 font-medium">生产订单</th>
            <th class="px-3 py-3 font-medium">状态</th>
            <th class="px-3 py-3 font-medium">回复交期</th>
            <th class="px-3 py-3 font-medium">跟进</th>
            <th class="px-3 py-3 font-medium">金额</th>
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
            <td class="px-3 py-3 text-n-slate-11">{{ p.supplierName || '—' }}</td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ p.productionOrderNo || '—' }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ STATUS_LABELS[p.status] }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">{{ day(p.expectedDate) }}</td>
            <td class="px-3 py-3 text-n-slate-11">{{ day(p.followUpDate) }}</td>
            <td class="px-3 py-3 text-n-slate-11">
              ¥{{ yuan(p.totalAmountMicros) }}
            </td>
            <td class="px-3 py-3 text-right">
              <Button v-if="mesCan('purchase')" label="编辑" variant="ghost" size="sm" @click="openEdit(p)" />
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
            <div class="col-span-5">
              <ComboBox
                v-model="row.mesMaterialId"
                :options="materialOptions"
                placeholder="选择物料"
              />
            </div>
            <Input v-model="row.qty" type="number" placeholder="数量" class="col-span-2" />
            <Input
              v-model="row.rateMicros"
              type="number"
              placeholder="单价(微分)"
              class="col-span-3"
            />
            <span class="col-span-1 text-xs text-right text-n-slate-11">
              ¥{{ yuan(rowAmount(row)) }}
            </span>
            <button
              type="button"
              class="col-span-1 text-n-slate-10 hover:text-n-ruby-11"
              @click="removeRow(i)"
            >
              ✕
            </button>
          </div>
        </div>
        <div
          class="flex justify-end pt-2 text-sm font-medium border-t text-n-slate-12 border-n-weak"
        >
          采购金额合计：¥{{ yuan(totalMicros) }}
        </div>
      </div>
    </Dialog>
  </div>
</template>
