<script setup>
/* global axios */
import { ref, computed, reactive, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesProductionOrdersStore } from 'dashboard/stores/mes/productionOrders';
import { useMesBomsStore } from 'dashboard/stores/mes/boms';
import { useMesRole } from 'dashboard/composables/useMesRole';
import { useCrmRole } from 'dashboard/composables/useCrmRole';
import { getActiveProductLine } from 'dashboard/composables/useMesProductLine';
import {
  SPEC_TEMPLATES,
  blankSpec,
} from 'dashboard/routes/dashboard/mes/pages/orderSpecFields';

import Button from 'dashboard/components-next/button/Button.vue';
import MesOrderSpecForm from 'dashboard/components-next/mes/MesOrderSpecForm.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';

const ITEMS_PER_PAGE = 15;

const { accountId } = useAccount();
const route = useRoute();
const { mesCan } = useMesRole();
const { isAdmin, isCrmDeputyAdmin } = useCrmRole();
const currentUserId = useMapGetter('getCurrentUserID');
const store = useMesProductionOrdersStore();

// 8 阶段（与后端 Mes::ProductionOrder::STAGES 顺序一致）。
const STAGES = [
  { value: 'SALES_CONFIRMED', label: '销售订单确定' },
  { value: 'BOM_READY', label: '工程/PMC BOM' },
  { value: 'PURCHASING', label: '采购原料' },
  { value: 'MATERIAL_INBOUND', label: '原料入库' },
  { value: 'PICKING', label: '生产领料' },
  { value: 'PRODUCTION', label: '生产' },
  { value: 'FG_INBOUND', label: '成品入库' },
  { value: 'SHIPPED', label: '销售出库' },
];
const STATUS_LABELS = {
  IN_PROGRESS: '进行中',
  COMPLETED: '已完成',
  STOPPED: '已终止',
  CANCELLED: '已取消',
};
const stageIndex = value => STAGES.findIndex(s => s.value === value);
const stageLabel = value => STAGES[stageIndex(value)]?.label || value;

const records = computed(() => store.getRecords);
const uiFlags = computed(() => store.getUIFlags);
const isFetching = computed(() => uiFlags.value.fetchingList);
const converting = computed(() => uiFlags.value.creatingItem);
const totalCount = computed(() => store.getMeta.count || 0);

const activeStage = ref('');
const activeStatus = ref('');
const searchQuery = ref(route.query.q ? String(route.query.q) : '');
const currentPage = ref(1);

const stageFilterOptions = [
  { value: '', label: '全部阶段' },
  ...STAGES.map(s => ({ value: s.value, label: s.label })),
];
const statusFilterOptions = [
  { value: '', label: '全部状态' },
  ...Object.entries(STATUS_LABELS).map(([value, label]) => ({ value, label })),
];

const fetchRecords = () =>
  store.get({
    page: currentPage.value,
    stage: activeStage.value || undefined,
    status: activeStatus.value || undefined,
    q: searchQuery.value.trim() || undefined,
  });

let searchTimer = null;
const onSearchInput = () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => {
    currentPage.value = 1;
    fetchRecords();
  }, 300);
};

// —— 详情面板 ——
const selected = ref(null);
const selectRow = row => {
  selected.value = selected.value?.id === row.id ? null : row;
};
// 各阶段到达时间（stage → 日期字符串）。
const stageTime = stageValue => {
  const ev = (selected.value?.stageEvents || []).find(
    e => e.stage === stageValue
  );
  return ev?.enteredAt ? new Date(ev.enteredAt).toLocaleDateString() : '';
};

const DAY = 86400000;
const STALL_DAYS = 3; // 当前阶段滞留超此天数即预警
const DUE_SOON_DAYS = 3; // 距交期内此天数算临近

// 各阶段耗时：相邻事件时间差；当前(最后)阶段算「已 N 天」。
const stageDurationLabel = stageValue => {
  const evs = [...(selected.value?.stageEvents || [])].sort(
    (a, b) => new Date(a.enteredAt) - new Date(b.enteredAt)
  );
  const idx = evs.findIndex(e => e.stage === stageValue);
  if (idx === -1) return '';
  const start = new Date(evs[idx].enteredAt);
  const isCurrent = idx === evs.length - 1;
  const end = isCurrent ? Date.now() : new Date(evs[idx + 1].enteredAt);
  const days = Math.max(0, Math.round((end - start) / DAY));
  if (!isCurrent) return `耗时 ${days} 天`;
  return selected.value?.stage === 'SHIPPED' ? '' : `进行中 · 已 ${days} 天`;
};

// 当前阶段滞留天数（未出货才算）。
const stallDays = po => {
  if (!po || po.stage === 'SHIPPED') return 0;
  const ev = (po.stageEvents || []).find(e => e.stage === po.stage);
  if (!ev?.enteredAt) return 0;
  return Math.round((Date.now() - new Date(ev.enteredAt)) / DAY);
};
const isStalled = po => stallDays(po) >= STALL_DAYS;

// 交期状态：已出货不预警；逾期红 / 临近橙 / 正常灰。
const deliveryStatus = po => {
  if (!po?.deliveryDate || po.stage === 'SHIPPED') return null;
  const days = Math.round((new Date(po.deliveryDate) - Date.now()) / DAY);
  if (days < 0) return { level: 'overdue', label: `已逾期 ${-days} 天` };
  if (days <= DUE_SOON_DAYS)
    return { level: 'soon', label: `距交期 ${days} 天` };
  return { level: 'ok', label: `距交期 ${days} 天` };
};
const DUE_CLASS = {
  overdue: 'text-n-ruby-11',
  soon: 'text-n-amber-11',
  ok: 'text-n-slate-11',
};

// —— 转单弹窗 ——
const convertDialogRef = ref(null);
const salesOrders = ref([]);
const products = ref([]);
const convertForm = ref({
  crmSalesOrderId: '',
  crmProductId: '',
  productName: '',
  qty: '',
  unit: '',
});

const salesOrderOptions = computed(() => [
  { value: '', label: '选择销售订单…' },
  ...salesOrders.value.map(o => ({
    value: String(o.id),
    label: `${o.order_no}${o.customer_name ? ` · ${o.customer_name}` : ''}`,
  })),
]);
const productOptions = computed(() =>
  products.value.map(p => ({ value: String(p.id), label: p.name }))
);
const convertInvalid = computed(
  () => !convertForm.value.crmSalesOrderId || !Number(convertForm.value.qty)
);

const fetchPickerData = async () => {
  try {
    const [soRes, prodRes] = await Promise.all([
      axios.get(`/api/v1/accounts/${accountId.value}/crm/sales_orders`, {
        params: { per_page: 100 },
      }),
      axios.get(`/api/v1/accounts/${accountId.value}/crm/products`),
    ]);
    salesOrders.value = soRes.data?.payload || [];
    products.value = prodRes.data?.payload || prodRes.data || [];
  } catch {
    salesOrders.value = [];
    products.value = [];
  }
};

const openConvert = () => {
  convertForm.value = {
    crmSalesOrderId: '',
    crmProductId: '',
    productName: '',
    qty: '',
    unit: '',
  };
  if (!salesOrders.value.length) fetchPickerData();
  convertDialogRef.value?.open();
};

// 选成品时带出成品名默认值。
watch(
  () => convertForm.value.crmProductId,
  id => {
    const p = products.value.find(x => String(x.id) === String(id));
    if (p && !convertForm.value.productName)
      convertForm.value.productName = p.name;
  }
);

const submitConvert = async () => {
  if (convertInvalid.value) return;
  const ok = await store.convert({ ...convertForm.value });
  if (ok) {
    useAlert(`已生成生产订单 ${ok.orderNo}`);
    convertDialogRef.value?.close();
    fetchRecords();
  }
};

// —— 定制生产订单：按产品线模板填规格（新建 / 编辑规格）——
const orderDialogRef = ref(null);
const editingOrderId = ref(null);
const orderTemplate = ref('TABLET');
const templateOptions = Object.entries(SPEC_TEMPLATES).map(([value, t]) => ({
  value,
  label: t.label,
}));
const orderBase = reactive({
  productName: '',
  qty: '',
  unit: '台',
  deliveryDate: '',
});
const orderSpec = ref(blankSpec('TABLET'));
const orderInvalid = computed(
  () => !orderBase.productName.trim() || !Number(orderBase.qty)
);
const defaultTemplate = () => {
  const line = getActiveProductLine();
  return ['TABLET', 'DISPLAY'].includes(line) ? line : 'TABLET';
};
const setTemplate = t => {
  orderTemplate.value = t;
  orderSpec.value = blankSpec(t); // 换模板重置规格
};
const openNewOrder = () => {
  editingOrderId.value = null;
  orderTemplate.value = defaultTemplate();
  Object.assign(orderBase, {
    productName: '',
    qty: '',
    unit: '台',
    deliveryDate: '',
  });
  orderSpec.value = blankSpec(orderTemplate.value);
  orderDialogRef.value?.open();
};
const openEditSpec = order => {
  editingOrderId.value = order.id;
  orderTemplate.value =
    order.spec?.template ||
    (['TABLET', 'DISPLAY'].includes(order.productLine)
      ? order.productLine
      : 'TABLET');
  Object.assign(orderBase, {
    productName: order.productName || '',
    qty: String(order.qty ?? ''),
    unit: order.unit || '台',
    deliveryDate: order.deliveryDate
      ? String(order.deliveryDate).slice(0, 10)
      : '',
  });
  orderSpec.value = {
    ...blankSpec(orderTemplate.value),
    ...(order.spec || {}),
    template: orderTemplate.value,
  };
  orderDialogRef.value?.open();
};
const submitOrder = async () => {
  if (orderInvalid.value) return;
  const payload = {
    productName: orderBase.productName.trim(),
    qty: Number(orderBase.qty),
    unit: orderBase.unit,
    deliveryDate: orderBase.deliveryDate || undefined,
    productLine: orderTemplate.value,
    spec: orderSpec.value,
  };
  const ok = editingOrderId.value
    ? await store.update({ id: editingOrderId.value, ...payload })
    : await store.create(payload);
  if (ok) {
    useAlert(editingOrderId.value ? '订单已更新' : `已建单 ${ok.orderNo}`);
    if (editingOrderId.value) selected.value = ok;
    orderDialogRef.value?.close();
    fetchRecords();
  }
};

// —— 挂 BOM（阶段 2 触点）——
const bomsStore = useMesBomsStore();
const bomDialogRef = ref(null);
const bomForm = ref({ bomId: '', deliveryDate: '' });
const attaching = computed(
  () => bomsStore.getUIFlags.updatingItem || uiFlags.value.updatingItem
);
const bomOptions = computed(() => [
  { value: '', label: '选择 BOM…' },
  // 只列已下发的 BOM，草稿不可挂。
  ...(bomsStore.getRecords || [])
    .filter(b => b.status === 'RELEASED')
    .map(b => ({
      value: String(b.id),
      label: `${b.bomNo}${b.productName ? ` · ${b.productName}` : ''}`,
    })),
]);
const openAttachBom = () => {
  // 期望交期预填订单现有交期，工程/PMC 可在此确认或调整。
  bomForm.value = {
    bomId: '',
    deliveryDate: selected.value?.deliveryDate
      ? String(selected.value.deliveryDate).slice(0, 10)
      : '',
  };
  if (!bomsStore.getRecords?.length) bomsStore.get();
  bomDialogRef.value?.open();
};
const submitAttachBom = async () => {
  if (!bomForm.value.bomId || !selected.value) return;
  const ok = await store.attachBom({
    id: selected.value.id,
    bomId: Number(bomForm.value.bomId),
    deliveryDate: bomForm.value.deliveryDate || undefined,
  });
  if (ok) {
    useAlert('已挂 BOM，进入「工程/PMC BOM」阶段');
    selected.value = ok;
    bomDialogRef.value?.close();
    fetchRecords();
  }
};

// 工程/PMC 制单后一键下发到采购阶段。
const releasePurchasing = async () => {
  if (!selected.value) return;
  const ok = await store.releasePurchasing(selected.value.id);
  if (ok) {
    useAlert('已下发到采购阶段');
    selected.value = ok;
    fetchRecords();
  }
};

// —— 接单确认（P1）——
// 只有本阶段负责人本人或管理员能接单/拒收。
const canHandleStage = computed(() => {
  const po = selected.value;
  if (!po || po.stage === 'SHIPPED' || po.status !== 'IN_PROGRESS')
    return false;
  return (
    isAdmin.value ||
    isCrmDeputyAdmin.value ||
    (po.stageOwnerIds || []).includes(currentUserId.value)
  );
});
const fmtDateTime = d =>
  d ? new Date(d).toLocaleString(undefined, { hour12: false }) : '';

const acknowledge = async () => {
  if (!selected.value) return;
  const ok = await store.acknowledge(selected.value.id);
  if (ok) {
    useAlert('已接单');
    selected.value = ok;
  }
};

const rejectDialogRef = ref(null);
const rejectReason = ref('');
const openReject = () => {
  rejectReason.value = '';
  rejectDialogRef.value?.open();
};
const confirmReject = async () => {
  if (!selected.value || !rejectReason.value.trim()) return;
  const ok = await store.reject({
    id: selected.value.id,
    reason: rejectReason.value.trim(),
  });
  if (ok) {
    useAlert('已退回上一阶段');
    selected.value = ok;
    rejectDialogRef.value?.close();
    fetchRecords();
  }
};

onMounted(async () => {
  await fetchRecords();
  // 从看板交期预警跳转过来：按订单号自动打开详情面板。
  const q = route.query.q ? String(route.query.q) : '';
  if (q) {
    const match = records.value.find(r => r.orderNo === q);
    if (match) selected.value = match;
  }
});
watch([activeStage, activeStatus, currentPage], fetchRecords);
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <!-- 头部 -->
    <div class="flex items-center justify-between gap-3 px-6 py-4">
      <h1 class="text-xl font-semibold text-n-slate-12">生产订单</h1>
      <div class="flex gap-2">
        <Button
          v-if="mesCan('order')"
          label="新建生产订单"
          color="iris"
          size="sm"
          @click="openNewOrder"
        />
        <Button
          v-if="mesCan('order')"
          label="从销售订单转入"
          variant="outline"
          color="slate"
          size="sm"
          @click="openConvert"
        />
      </div>
    </div>

    <!-- 筛选 -->
    <div class="flex flex-wrap items-center gap-3 px-6 pb-3">
      <Select
        :model-value="activeStage"
        :options="stageFilterOptions"
        @update:model-value="v => (activeStage = v)"
      />
      <Select
        :model-value="activeStatus"
        :options="statusFilterOptions"
        @update:model-value="v => (activeStatus = v)"
      />
      <input
        v-model="searchQuery"
        type="text"
        placeholder="搜索 工单号 / 成品名…"
        class="h-9 px-3 text-sm border rounded-lg outline-none w-60 border-n-weak bg-n-alpha-black1 text-n-slate-12"
        @input="onSearchInput"
      />
    </div>

    <div class="flex flex-1 min-h-0 gap-4 px-6 pb-6">
      <!-- 列表 -->
      <div class="flex-1 min-w-0 overflow-auto">
        <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
          加载中…
        </div>
        <table v-else class="w-full text-sm">
          <thead>
            <tr class="text-left text-n-slate-11 border-b border-n-weak">
              <th class="px-3 py-3 font-medium">工单号</th>
              <th class="px-3 py-3 font-medium">成品</th>
              <th class="px-3 py-3 font-medium">数量</th>
              <th class="px-3 py-3 font-medium">阶段</th>
              <th class="px-3 py-3 font-medium">交期</th>
              <th class="px-3 py-3 font-medium">来源销售单</th>
              <th class="px-3 py-3 font-medium">负责人</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="po in records"
              :key="po.id"
              class="border-b cursor-pointer border-n-weak hover:bg-n-alpha-1"
              :class="{ 'bg-n-alpha-1': selected && selected.id === po.id }"
              @click="selectRow(po)"
            >
              <td class="px-3 py-3 font-medium text-n-slate-12">
                {{ po.orderNo }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">{{ po.productName }}</td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ po.producedQty }} / {{ po.qty }} {{ po.unit }}
              </td>
              <td class="px-3 py-3">
                <span
                  class="inline-flex items-center px-2 py-0.5 text-xs rounded-full bg-n-iris-3 text-n-iris-11"
                >
                  {{ stageLabel(po.stage) }}
                </span>
                <span
                  v-if="isStalled(po)"
                  v-tooltip.top="`本阶段已滞留 ${stallDays(po)} 天`"
                  class="ml-1 text-xs text-n-amber-11"
                >
                  ⚠
                </span>
              </td>
              <td class="px-3 py-3 text-xs">
                <span
                  v-if="deliveryStatus(po)"
                  :class="DUE_CLASS[deliveryStatus(po).level]"
                >
                  {{ deliveryStatus(po).label }}
                </span>
                <span v-else class="text-n-slate-10">—</span>
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ po.salesOrderNo || '—' }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ po.ownerName || '—' }}
              </td>
            </tr>
            <tr v-if="!records.length">
              <td colspan="6" class="px-3 py-10 text-center text-n-slate-11">
                还没有生产订单。点右上角「从销售订单转入」开始。
              </td>
            </tr>
          </tbody>
        </table>

        <PaginationFooter
          v-if="totalCount > ITEMS_PER_PAGE"
          :current-page="currentPage"
          :total-items="totalCount"
          :items-per-page="ITEMS_PER_PAGE"
          @update:current-page="currentPage = $event"
        />
      </div>

      <!-- 详情：8 阶段进度条 -->
      <div
        v-if="selected"
        class="flex flex-col p-5 overflow-auto w-80 shrink-0 rounded-xl bg-n-alpha-black1 border border-n-weak"
      >
        <div class="flex items-center justify-between mb-1">
          <span class="font-semibold text-n-slate-12">{{
            selected.orderNo
          }}</span>
          <span class="text-xs text-n-slate-11">
            {{ STATUS_LABELS[selected.status] }}
          </span>
        </div>
        <div class="mb-4 text-sm text-n-slate-11">
          {{ selected.productName }} · {{ selected.producedQty }}/{{
            selected.qty
          }}
          {{ selected.unit }}
        </div>

        <!-- 接单确认（P1）：当前阶段负责人 + 接单状态 + 接单/拒收。
             建单阶段（SALES_CONFIRMED）由业务自建、不入接单机制，不展示。 -->
        <div
          v-if="
            selected.stage !== 'SALES_CONFIRMED' &&
            selected.stage !== 'SHIPPED' &&
            selected.status === 'IN_PROGRESS'
          "
          class="flex flex-col gap-2 p-3 mb-4 rounded-lg bg-n-alpha-black1 border border-n-weak"
        >
          <div class="flex flex-wrap items-center gap-1.5 text-xs">
            <span class="text-n-slate-11">本阶段负责人</span>
            <template v-if="(selected.stageOwnerNames || []).length">
              <span
                v-for="n in selected.stageOwnerNames"
                :key="n"
                class="px-1.5 py-0.5 rounded-full bg-n-iris-3 text-n-iris-12"
              >
                {{ n }}
              </span>
            </template>
            <span v-else class="text-n-amber-11">未设置负责人</span>
          </div>
          <div class="text-xs">
            <span v-if="selected.stageAckAt" class="text-n-teal-11">
              ✅ 已接单 · {{ selected.stageAckByName }}
            </span>
            <span v-else-if="selected.ackOverdue" class="text-n-ruby-11">
              🔴 未接单超时（截止 {{ fmtDateTime(selected.ackDeadline) }}）
            </span>
            <span v-else-if="selected.awaitingAck" class="text-n-amber-11">
              ⏳ 待接单 · 截止 {{ fmtDateTime(selected.ackDeadline) }}
            </span>
          </div>
          <div v-if="canHandleStage" class="flex gap-2">
            <Button
              v-if="selected.awaitingAck"
              label="接单"
              color="teal"
              size="sm"
              :is-loading="uiFlags.updatingItem"
              @click="acknowledge"
            />
            <Button
              v-if="selected.stage !== 'SALES_CONFIRMED'"
              label="拒收打回"
              variant="outline"
              color="ruby"
              size="sm"
              @click="openReject"
            />
          </div>
        </div>

        <div class="flex flex-col gap-0">
          <div
            v-for="(s, i) in STAGES"
            :key="s.value"
            class="flex items-start gap-3"
          >
            <div class="flex flex-col items-center">
              <span
                class="flex items-center justify-center w-6 h-6 text-xs rounded-full shrink-0"
                :class="
                  i <= stageIndex(selected.stage)
                    ? 'bg-n-iris-9 text-white'
                    : 'bg-n-slate-4 text-n-slate-11'
                "
              >
                {{ i + 1 }}
              </span>
              <span
                v-if="i < STAGES.length - 1"
                class="w-px h-8"
                :class="
                  i < stageIndex(selected.stage)
                    ? 'bg-n-iris-9'
                    : 'bg-n-slate-4'
                "
              />
            </div>
            <div class="pt-0.5 pb-2">
              <span
                class="text-sm"
                :class="
                  i === stageIndex(selected.stage)
                    ? 'font-semibold text-n-slate-12'
                    : 'text-n-slate-11'
                "
              >
                {{ s.label }}
              </span>
              <div v-if="stageTime(s.value)" class="text-xs text-n-slate-10">
                {{ stageTime(s.value) }} 到达
                <span
                  v-if="stageDurationLabel(s.value)"
                  :class="
                    i === stageIndex(selected.stage) && isStalled(selected)
                      ? 'text-n-amber-11'
                      : 'text-n-slate-10'
                  "
                >
                  · {{ stageDurationLabel(s.value) }}
                </span>
              </div>
            </div>
          </div>
        </div>

        <div class="pt-4 mt-4 border-t border-n-weak">
          <template v-if="selected.bomNo">
            <div class="text-xs text-n-slate-11">
              工程/PMC BOM：{{ selected.bomNo }}
            </div>
            <Button
              v-if="
                selected.stage === 'BOM_READY' &&
                (mesCan('bom') || mesCan('order'))
              "
              label="下发到采购"
              color="iris"
              size="sm"
              class="w-full mt-2"
              :is-loading="uiFlags.updatingItem"
              @click="releasePurchasing"
            />
          </template>
          <Button
            v-else-if="
              selected.stage === 'SALES_CONFIRMED' &&
              (mesCan('order') || mesCan('bom'))
            "
            label="挂工程/PMC BOM"
            color="iris"
            size="sm"
            class="w-full"
            @click="openAttachBom"
          />
        </div>

        <!-- 定制规格（生产订单单据内容） -->
        <div
          v-if="selected.spec && selected.spec.template"
          class="pt-3 mt-3 border-t border-n-weak"
        >
          <div class="flex items-center justify-between mb-2">
            <span class="text-xs font-medium text-n-slate-11">
              定制规格 ·
              {{ (SPEC_TEMPLATES[selected.spec.template] || {}).label }}
            </span>
            <Button
              v-if="mesCan('order')"
              label="编辑规格"
              variant="ghost"
              size="xs"
              @click="openEditSpec(selected)"
            />
          </div>
          <MesOrderSpecForm
            :template="selected.spec.template"
            :spec="selected.spec"
            readonly
          />
        </div>

        <div
          v-if="selected.deliveryDate"
          class="flex items-center justify-between pt-3 mt-3 text-xs border-t text-n-slate-11 border-n-weak"
        >
          <span>交期：{{
              new Date(selected.deliveryDate).toLocaleDateString()
            }}</span>
          <span
            v-if="deliveryStatus(selected)"
            class="font-medium"
            :class="DUE_CLASS[deliveryStatus(selected).level]"
          >
            {{ deliveryStatus(selected).label }}
          </span>
        </div>
      </div>
    </div>

    <!-- 新建 / 编辑定制生产订单 -->
    <Dialog
      ref="orderDialogRef"
      width="2xl"
      overflow-y-auto
      confirm-button-color="iris"
      :title="editingOrderId ? '编辑生产订单' : '新建生产订单'"
      :is-loading="converting"
      :disable-confirm-button="orderInvalid"
      @confirm="submitOrder"
    >
      <div class="flex flex-col gap-4">
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">产品线 / 模板</label>
          <Select
            :model-value="orderTemplate"
            :options="templateOptions"
            :disabled="!!editingOrderId"
            @update:model-value="setTemplate"
          />
        </div>
        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              成品名称 <span class="text-n-ruby-11">*</span>
            </label>
            <Input
              v-model="orderBase.productName"
              placeholder="如：商显一体机 43寸"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">期望交期</label>
            <Input v-model="orderBase.deliveryDate" type="date" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              数量 <span class="text-n-ruby-11">*</span>
            </label>
            <Input v-model="orderBase.qty" type="number" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">单位</label>
            <Input v-model="orderBase.unit" placeholder="台 / 片 / pcs" />
          </div>
        </div>

        <div class="pt-2 border-t border-n-weak">
          <MesOrderSpecForm
            v-model:spec="orderSpec"
            :template="orderTemplate"
          />
        </div>
      </div>
    </Dialog>

    <!-- 转单弹窗 -->
    <Dialog
      ref="convertDialogRef"
      width="lg"
      confirm-button-color="iris"
      title="从销售订单转生产订单"
      description="选择销售订单与成品，生成生产订单；来源订单将自动进入「生产中」。"
      :is-loading="converting"
      :disable-confirm-button="convertInvalid"
      @confirm="submitConvert"
    >
      <div class="flex flex-col gap-4">
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">
            销售订单 <span class="text-n-ruby-11">*</span>
          </label>
          <Select
            :model-value="convertForm.crmSalesOrderId"
            :options="salesOrderOptions"
            @update:model-value="v => (convertForm.crmSalesOrderId = v)"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">成品</label>
          <ComboBox
            v-model="convertForm.crmProductId"
            :options="productOptions"
            placeholder="选择成品（可选）"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">
            成品名称 <span class="text-n-ruby-11">*</span>
          </label>
          <Input
            v-model="convertForm.productName"
            placeholder="未选成品时手填"
          />
        </div>
        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              生产数量 <span class="text-n-ruby-11">*</span>
            </label>
            <Input v-model="convertForm.qty" type="number" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">单位</label>
            <Input v-model="convertForm.unit" placeholder="台 / 片 / pcs" />
          </div>
        </div>
      </div>
    </Dialog>

    <!-- 挂 BOM 弹窗 -->
    <Dialog
      ref="bomDialogRef"
      width="lg"
      confirm-button-color="iris"
      title="挂工程/PMC BOM"
      description="选择该成品的已下发 BOM，填期望交期，生产订单进入「工程/PMC BOM」阶段。"
      :is-loading="attaching"
      :disable-confirm-button="!bomForm.bomId"
      @confirm="submitAttachBom"
    >
      <div class="flex flex-col gap-4">
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">
            BOM <span class="text-n-ruby-11">*</span>
          </label>
          <Select
            :model-value="bomForm.bomId"
            :options="bomOptions"
            @update:model-value="v => (bomForm.bomId = v)"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">期望交期</label>
          <Input v-model="bomForm.deliveryDate" type="date" />
        </div>
      </div>
    </Dialog>

    <Dialog
      ref="rejectDialogRef"
      confirm-button-color="ruby"
      title="拒收打回上一阶段"
      description="退回后责任明确回上游，上一阶段重新计时、需重新接单。"
      :is-loading="uiFlags.updatingItem"
      :disable-confirm-button="!rejectReason.trim()"
      @confirm="confirmReject"
    >
      <div class="flex flex-col gap-1">
        <label class="text-heading-3 text-n-slate-12">
          退回原因 <span class="text-n-ruby-11">*</span>
        </label>
        <Input
          v-model="rejectReason"
          placeholder="如：BOM 漏了主板 / 来料规格不对"
        />
      </div>
    </Dialog>
  </div>
</template>
