<script setup>
/* global axios */
import { ref, computed, reactive, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesRole } from 'dashboard/composables/useMesRole';
import MesSerialNumberAPI from 'dashboard/api/mes/serialNumbers';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const { accountId } = useAccount();
const { mesCan } = useMesRole();

const STATUS_LABELS = { IN_STOCK: '在库', SHIPPED: '已出货', RMA: '售后' };
const records = ref([]);
const loading = ref(false);
const day = d => (d ? new Date(d).toLocaleDateString() : '—');

const fetchList = async () => {
  loading.value = true;
  try {
    const { data } = await MesSerialNumberAPI.get();
    records.value = data?.payload || [];
  } finally {
    loading.value = false;
  }
};

// —— 追溯查询 ——
const query = ref('');
const trace = ref(null);
const traceError = ref('');
const tracing = ref(false);
const doTrace = async () => {
  if (!query.value.trim()) return;
  tracing.value = true;
  trace.value = null;
  traceError.value = '';
  try {
    const { data } = await MesSerialNumberAPI.trace(query.value.trim());
    trace.value = data?.payload;
  } catch (e) {
    traceError.value = e?.response?.data?.error || '未找到该序列号';
  } finally {
    tracing.value = false;
  }
};

// —— 登记 SN ——
const productionOrders = ref([]);
const productionOrderOptions = computed(() => [
  { value: '', label: '选择生产订单…' },
  ...productionOrders.value.map(p => ({
    value: String(p.id),
    label: `${p.order_no} · ${p.product_name}`,
  })),
]);
const dialogRef = ref(null);
const registering = ref(false);
const form = reactive({ productionOrderId: '', count: '' });
const invalid = computed(() => !form.productionOrderId || !Number(form.count));

const openRegister = () => {
  Object.assign(form, { productionOrderId: '', count: '' });
  dialogRef.value?.open();
};
const submit = async () => {
  if (invalid.value) return;
  registering.value = true;
  try {
    const { data } = await MesSerialNumberAPI.register({
      production_order_id: Number(form.productionOrderId),
      count: Number(form.count),
    });
    useAlert(`已登记 ${data.registered} 个序列号`);
    dialogRef.value?.close();
    fetchList();
  } catch (e) {
    useAlert(e?.response?.data?.error || '登记失败');
  } finally {
    registering.value = false;
  }
};

onMounted(() => {
  fetchList();
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
      <h1 class="text-xl font-semibold text-n-slate-12">SN 追溯</h1>
      <Button
        v-if="mesCan('stock')"
        label="登记序列号"
        color="iris"
        size="sm"
        @click="openRegister"
      />
    </div>

    <!-- 追溯查询 -->
    <div class="px-6 pb-4">
      <div class="flex gap-2">
        <input
          v-model="query"
          type="text"
          placeholder="输入序列号查询追溯…"
          class="flex-1 h-9 px-3 text-sm border rounded-lg outline-none border-n-weak bg-n-alpha-black1 text-n-slate-12"
          @keyup.enter="doTrace"
        />
        <Button label="追溯" color="iris" size="sm" :is-loading="tracing" @click="doTrace" />
      </div>

      <div v-if="traceError" class="mt-3 text-sm text-n-ruby-11">{{ traceError }}</div>
      <div
        v-else-if="trace"
        class="p-5 mt-3 rounded-xl bg-n-alpha-black1 border border-n-weak"
      >
        <div class="flex items-center justify-between mb-3">
          <span class="font-semibold text-n-slate-12">{{ trace.sn }}</span>
          <span class="text-xs text-n-slate-11">{{ STATUS_LABELS[trace.status] }}</span>
        </div>
        <dl class="grid grid-cols-2 gap-y-2 text-sm">
          <dt class="text-n-slate-11">成品</dt>
          <dd class="text-n-slate-12">{{ trace.product_name || '—' }}</dd>
          <dt class="text-n-slate-11">生产订单</dt>
          <dd class="text-n-slate-12">
            {{ trace.production_order?.order_no || '—' }}
          </dd>
          <dt class="text-n-slate-11">工程/PMC BOM</dt>
          <dd class="text-n-slate-12">{{ trace.bom?.bom_no || '—' }}</dd>
          <dt class="text-n-slate-11">用料</dt>
          <dd class="text-n-slate-12">
            {{ (trace.bom?.materials || []).join('、') || '—' }}
          </dd>
          <dt class="text-n-slate-11">销售订单</dt>
          <dd class="text-n-slate-12">{{ trace.sales_order_no || '—' }}</dd>
          <dt class="text-n-slate-11">客户</dt>
          <dd class="text-n-slate-12">{{ trace.customer_name || '—' }}</dd>
          <dt class="text-n-slate-11">出库单</dt>
          <dd class="text-n-slate-12">
            {{ trace.shipment?.shipment_no || '—' }}
            {{ trace.shipment?.shipped_at ? `（${day(trace.shipment.shipped_at)}）` : '' }}
          </dd>
        </dl>
      </div>
    </div>

    <!-- SN 列表 -->
    <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto">
      <div v-if="loading" class="py-10 text-center text-n-slate-11">加载中…</div>
      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left text-n-slate-11 border-b border-n-weak">
            <th class="px-3 py-3 font-medium">序列号</th>
            <th class="px-3 py-3 font-medium">成品</th>
            <th class="px-3 py-3 font-medium">生产订单</th>
            <th class="px-3 py-3 font-medium">状态</th>
            <th class="px-3 py-3 font-medium">登记时间</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="s in records" :key="s.id" class="border-b border-n-weak">
            <td class="px-3 py-3 font-medium text-n-slate-12">{{ s.sn }}</td>
            <td class="px-3 py-3 text-n-slate-11">{{ s.product_name || '—' }}</td>
            <td class="px-3 py-3 text-n-slate-11">{{ s.production_order_no || '—' }}</td>
            <td class="px-3 py-3 text-n-slate-11">{{ STATUS_LABELS[s.status] }}</td>
            <td class="px-3 py-3 text-n-slate-11">{{ day(s.created_at) }}</td>
          </tr>
          <tr v-if="!records.length">
            <td colspan="5" class="px-3 py-10 text-center text-n-slate-11">
              还没有登记序列号。
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <Dialog
      ref="dialogRef"
      width="lg"
      confirm-button-color="iris"
      title="按工单登记序列号"
      description="选生产订单 + 数量，自动生成「工单号-序号」的 SN。"
      :is-loading="registering"
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
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">
            数量 <span class="text-n-ruby-11">*</span>
          </label>
          <Input v-model="form.count" type="number" placeholder="生成多少个 SN" />
        </div>
      </div>
    </Dialog>
  </div>
</template>
