<script setup>
/* global axios */
import { ref, computed, reactive, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesInspectionsStore } from 'dashboard/stores/mes/inspections';
import { useMesMaterialsStore } from 'dashboard/stores/mes/materials';
import { useMesRole } from 'dashboard/composables/useMesRole';

import Button from 'dashboard/components-next/button/Button.vue';
import MesBoardOwnerBar from 'dashboard/components-next/mes/MesBoardOwnerBar.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const { accountId } = useAccount();
const { mesCan } = useMesRole();
const store = useMesInspectionsStore();
const materialsStore = useMesMaterialsStore();

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const saving = computed(() => store.getUIFlags.creatingItem);
const day = d => (d ? new Date(d).toLocaleDateString() : '—');

const KIND_LABELS = {
  IQC: '来料检验',
  IPQC: '过程检验',
  FQC: '成品检验',
  AGING: '老化测试',
};
const kindOptions = Object.entries(KIND_LABELS).map(([value, label]) => ({ value, label }));
const kindLabel = k => KIND_LABELS[k] || k;
const RESULT = {
  PASS: { label: '合格', cls: 'bg-n-teal-3 text-n-teal-11' },
  FAIL: { label: '不合格', cls: 'bg-n-ruby-3 text-n-ruby-11' },
  CONDITIONAL: { label: '让步接收', cls: 'bg-n-amber-3 text-n-amber-11' },
};

const productionOrders = ref([]);
const productionOrderOptions = computed(() => [
  { value: '', label: '关联生产订单…' },
  ...productionOrders.value.map(p => ({
    value: String(p.id),
    label: `${p.order_no} · ${p.product_name}`,
  })),
]);
const materialOptions = computed(() =>
  (materialsStore.getRecords || []).map(m => ({
    value: String(m.id),
    label: `${m.name}（${m.unit}）`,
  }))
);

const dialogRef = ref(null);
const form = reactive({
  kind: 'FQC',
  productionOrderId: '',
  mesMaterialId: '',
  inspectedQty: '',
  passedQty: '',
  failedQty: '',
  defectReason: '',
  needRework: false,
  remark: '',
});
const isIqc = computed(() => form.kind === 'IQC');
const invalid = computed(() => !Number(form.inspectedQty));

const openCreate = () => {
  Object.assign(form, {
    kind: 'FQC',
    productionOrderId: '',
    mesMaterialId: '',
    inspectedQty: '',
    passedQty: '',
    failedQty: '',
    defectReason: '',
    needRework: false,
    remark: '',
  });
  dialogRef.value?.open();
};

const submit = async () => {
  if (invalid.value) return;
  const po = productionOrders.value.find(
    p => String(p.id) === String(form.productionOrderId)
  );
  const ok = await store.create({
    kind: form.kind,
    itemType: isIqc.value ? 'MATERIAL' : 'PRODUCT',
    mesMaterialId: isIqc.value ? Number(form.mesMaterialId) || null : null,
    crmProductId: !isIqc.value ? po?.crm_product_id || null : null,
    productionOrderId: !isIqc.value ? form.productionOrderId || null : null,
    inspectedQty: Number(form.inspectedQty) || 0,
    passedQty: Number(form.passedQty) || 0,
    failedQty: Number(form.failedQty) || 0,
    defectReason: form.defectReason,
    needRework: form.needRework,
    remark: form.remark,
  });
  if (ok) {
    useAlert('检验记录已录入');
    dialogRef.value?.close();
    store.get();
  }
};

onMounted(() => {
  store.get();
  materialsStore.get();
  axios
    .get(`/api/v1/accounts/${accountId.value}/mes/production_orders`)
    .then(({ data }) => {
      productionOrders.value = data?.payload || [];
    })
    .catch(() => {});
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between px-6 py-4">
      <h1 class="text-xl font-semibold text-n-slate-12">质量检验</h1>
      <Button
        v-if="mesCan('quality')"
        label="新增检验"
        color="iris"
        size="sm"
        @click="openCreate"
      />
    </div>

    <MesBoardOwnerBar board-key="mes_inspections_index" />

    <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto">
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">加载中…</div>
      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left text-n-slate-11 border-b border-n-weak">
            <th class="px-3 py-3 font-medium">类型</th>
            <th class="px-3 py-3 font-medium">对象</th>
            <th class="px-3 py-3 font-medium">归属人</th>
            <th class="px-3 py-3 font-medium">检验/合格/不良</th>
            <th class="px-3 py-3 font-medium">结果</th>
            <th class="px-3 py-3 font-medium">不良原因</th>
            <th class="px-3 py-3 font-medium">检验员</th>
            <th class="px-3 py-3 font-medium">日期</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="r in records" :key="r.id" class="border-b border-n-weak">
            <td class="px-3 py-3 text-n-slate-12">{{ kindLabel(r.kind) }}</td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ r.productionOrderNo || r.materialName || r.productName || '—' }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ r.productionOrderOwnerName || '—' }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ r.inspectedQty }} / {{ r.passedQty }} /
              <span :class="r.failedQty > 0 ? 'text-n-ruby-11' : ''">{{ r.failedQty }}</span>
            </td>
            <td class="px-3 py-3">
              <span
                v-if="RESULT[r.result]"
                class="inline-flex px-2 py-0.5 text-xs rounded-full"
                :class="RESULT[r.result].cls"
              >
                {{ RESULT[r.result].label }}
              </span>
            </td>
            <td class="px-3 py-3 text-n-slate-11">{{ r.defectReason || '—' }}</td>
            <td class="px-3 py-3 text-n-slate-11">{{ r.inspectorName || '—' }}</td>
            <td class="px-3 py-3 text-n-slate-11">{{ day(r.inspectedAt) }}</td>
          </tr>
          <tr v-if="!records.length">
            <td colspan="8" class="px-3 py-10 text-center text-n-slate-11">
              还没有检验记录。
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <Dialog
      ref="dialogRef"
      width="lg"
      confirm-button-color="iris"
      title="新增质量检验"
      description="按数量记录合格/不良；结果留空则按不良数自动判定。"
      :is-loading="saving"
      :disable-confirm-button="invalid"
      @confirm="submit"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">检验类型</label>
            <Select
              :model-value="form.kind"
              :options="kindOptions"
              @update:model-value="v => (form.kind = v)"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              {{ isIqc ? '来料物料' : '关联生产订单' }}
            </label>
            <ComboBox
              v-if="isIqc"
              v-model="form.mesMaterialId"
              :options="materialOptions"
              placeholder="选择物料"
            />
            <Select
              v-else
              :model-value="form.productionOrderId"
              :options="productionOrderOptions"
              @update:model-value="v => (form.productionOrderId = v)"
            />
          </div>
        </div>
        <div class="grid grid-cols-3 gap-3">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              检验数 <span class="text-n-ruby-11">*</span>
            </label>
            <Input v-model="form.inspectedQty" type="number" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">合格数</label>
            <Input v-model="form.passedQty" type="number" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">不良数</label>
            <Input v-model="form.failedQty" type="number" />
          </div>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">不良原因</label>
          <Input v-model="form.defectReason" placeholder="如：触摸失灵 / 玻璃划伤" />
        </div>
        <label class="flex items-center gap-2 text-heading-3 text-n-slate-12">
          <input v-model="form.needRework" type="checkbox" />
          需返修
        </label>
      </div>
    </Dialog>
  </div>
</template>
