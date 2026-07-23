<script setup>
/* global axios */
import { ref, computed, reactive, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesProductionRecordsStore } from 'dashboard/stores/mes/productionRecords';

import Button from 'dashboard/components-next/button/Button.vue';
import MesBoardOwnerBar from 'dashboard/components-next/mes/MesBoardOwnerBar.vue';
import { useMesRole } from 'dashboard/composables/useMesRole';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import MesViewDialog from 'dashboard/components-next/mes/MesViewDialog.vue';

const { accountId } = useAccount();
const store = useMesProductionRecordsStore();
const { mesCan } = useMesRole();

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const saving = computed(() => store.getUIFlags.creatingItem);
const time = d => (d ? new Date(d).toLocaleString() : '—');

// 只读查看
const viewDialogRef = ref(null);
const viewing = ref(null);
const openView = r => {
  viewing.value = r;
  viewDialogRef.value?.open();
};
const viewFields = computed(() => {
  const r = viewing.value || {};
  return [
    { label: '生产订单', value: r.productionOrderNo },
    { label: '归属人', value: r.productionOrderOwnerName },
    { label: '工序', value: r.operationName },
    { label: '完成数', value: r.qtyCompleted },
    { label: '退料数', value: r.qtyReturned },
    { label: '清尾数', value: r.qtyScrap },
    { label: '报工人', value: r.operatorName },
    { label: '报工时间', value: time(r.recordedAt) },
    { label: '备注', value: r.remark },
  ];
});

const productionOrders = ref([]);
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
  operationName: '',
  qtyCompleted: '',
  qtyReturned: '',
  qtyScrap: '',
  remark: '',
});
const selectedOrder = computed(() =>
  productionOrders.value.find(
    p => String(p.id) === String(form.productionOrderId)
  )
);
const invalid = computed(
  () => !form.productionOrderId || form.qtyCompleted === ''
);

const fetchOrders = async () => {
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/production_orders`
    );
    productionOrders.value = data?.payload || [];
  } catch {
    productionOrders.value = [];
  }
};

const openCreate = () => {
  Object.assign(form, {
    productionOrderId: '',
    operationName: '',
    qtyCompleted: '',
    qtyReturned: '',
    qtyScrap: '',
    remark: '',
  });
  dialogRef.value?.open();
};

const submit = async () => {
  if (invalid.value) return;
  const ok = await store.create({
    productionOrderId: Number(form.productionOrderId),
    operationName: form.operationName || null,
    qtyCompleted: Number(form.qtyCompleted) || 0,
    qtyReturned: Number(form.qtyReturned) || 0,
    qtyScrap: Number(form.qtyScrap) || 0,
    remark: form.remark,
  });
  if (ok) {
    useAlert('报工已录入');
    dialogRef.value?.close();
    store.get();
    fetchOrders();
  }
};

onMounted(() => {
  store.get();
  fetchOrders();
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between px-6 py-4">
      <h1 class="text-xl font-semibold text-n-slate-12">生产报工</h1>
      <Button
        v-if="mesCan('report')"
        label="报工"
        color="iris"
        size="sm"
        @click="openCreate"
      />
    </div>

    <MesBoardOwnerBar board-key="mes_production_records_index" />

    <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto">
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left text-n-slate-11 border-b border-n-weak">
            <th class="px-3 py-3 font-medium">生产订单</th>
            <th class="px-3 py-3 font-medium">归属人</th>
            <th class="px-3 py-3 font-medium">工序</th>
            <th class="px-3 py-3 font-medium">完成</th>
            <th class="px-3 py-3 font-medium">退料</th>
            <th class="px-3 py-3 font-medium">清尾</th>
            <th class="px-3 py-3 font-medium">报工人</th>
            <th class="px-3 py-3 font-medium">时间</th>
            <th class="px-3 py-3" />
          </tr>
        </thead>
        <tbody>
          <tr v-for="r in records" :key="r.id" class="border-b border-n-weak">
            <td class="px-3 py-3 font-medium text-n-slate-12">
              {{ r.productionOrderNo || '—' }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ r.productionOrderOwnerName || '—' }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ r.operationName || '—' }}
            </td>
            <td class="px-3 py-3 text-n-slate-12">{{ r.qtyCompleted }}</td>
            <td class="px-3 py-3 text-n-slate-11">{{ r.qtyReturned }}</td>
            <td class="px-3 py-3 text-n-slate-11">{{ r.qtyScrap }}</td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ r.operatorName || '—' }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">{{ time(r.recordedAt) }}</td>
            <td class="px-3 py-3 text-right">
              <Button
                label="查看"
                variant="ghost"
                size="sm"
                @click="openView(r)"
              />
            </td>
          </tr>
          <tr v-if="!records.length">
            <td colspan="9" class="px-3 py-10 text-center text-n-slate-11">
              还没有报工记录。
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <Dialog
      ref="dialogRef"
      width="lg"
      confirm-button-color="iris"
      title="生产报工"
      description="按数量批量报工：完成数量累加生产进度；退料/清尾按需记录。"
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
            @update:model-value="v => (form.productionOrderId = v)"
          />
          <span v-if="selectedOrder" class="text-xs text-n-slate-11">
            当前进度：{{ selectedOrder.produced_qty }} / {{ selectedOrder.qty }}
            {{ selectedOrder.unit }}
          </span>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">工序（可选）</label>
          <Input
            v-model="form.operationName"
            placeholder="组装 / 老化 / FQC / 包装"
          />
        </div>
        <div class="grid grid-cols-3 gap-3">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              完成数量 <span class="text-n-ruby-11">*</span>
            </label>
            <Input v-model="form.qtyCompleted" type="number" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">退料</label>
            <Input v-model="form.qtyReturned" type="number" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">清尾</label>
            <Input v-model="form.qtyScrap" type="number" />
          </div>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">备注</label>
          <Input v-model="form.remark" />
        </div>
      </div>
    </Dialog>

    <MesViewDialog ref="viewDialogRef" title="报工明细" :fields="viewFields" />
  </div>
</template>
