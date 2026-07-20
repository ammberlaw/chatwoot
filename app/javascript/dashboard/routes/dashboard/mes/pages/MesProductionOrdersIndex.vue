<script setup>
/* global axios */
import { ref, computed, onMounted, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesProductionOrdersStore } from 'dashboard/stores/mes/productionOrders';
import { useMesBomsStore } from 'dashboard/stores/mes/boms';

import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';

const ITEMS_PER_PAGE = 15;

const { accountId } = useAccount();
const store = useMesProductionOrdersStore();

// 8 阶段（与后端 Mes::ProductionOrder::STAGES 顺序一致）。
const STAGES = [
  { value: 'SALES_CONFIRMED', label: '销售订单确定' },
  { value: 'BOM_READY', label: '工程BOM' },
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
const searchQuery = ref('');
const currentPage = ref(1);

const stageFilterOptions = [
  { value: '', label: '全部阶段' },
  ...STAGES.map(s => ({ value: s.value, label: s.label })),
];
const statusFilterOptions = [
  { value: '', label: '全部状态' },
  ...Object.entries(STATUS_LABELS).map(([value, label]) => ({ value, label })),
];

const fetchRecords = () => {
  store.get({
    page: currentPage.value,
    stage: activeStage.value || undefined,
    status: activeStatus.value || undefined,
    q: searchQuery.value.trim() || undefined,
  });
};

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
    if (p && !convertForm.value.productName) convertForm.value.productName = p.name;
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

// —— 挂 BOM（阶段 2 触点）——
const bomsStore = useMesBomsStore();
const bomDialogRef = ref(null);
const bomForm = ref({ bomId: '', plannedEndDate: '' });
const attaching = computed(() => bomsStore.getUIFlags.updatingItem || uiFlags.value.updatingItem);
const bomOptions = computed(() => [
  { value: '', label: '选择 BOM…' },
  ...(bomsStore.getRecords || []).map(b => ({
    value: String(b.id),
    label: `${b.bomNo}${b.productName ? ` · ${b.productName}` : ''}`,
  })),
]);
const openAttachBom = () => {
  bomForm.value = { bomId: '', plannedEndDate: '' };
  if (!bomsStore.getRecords?.length) bomsStore.get();
  bomDialogRef.value?.open();
};
const submitAttachBom = async () => {
  if (!bomForm.value.bomId || !selected.value) return;
  const ok = await store.attachBom({
    id: selected.value.id,
    bomId: Number(bomForm.value.bomId),
    plannedEndDate: bomForm.value.plannedEndDate || undefined,
  });
  if (ok) {
    useAlert('已挂 BOM，进入「工程BOM」阶段');
    selected.value = ok;
    bomDialogRef.value?.close();
    fetchRecords();
  }
};

onMounted(fetchRecords);
watch([activeStage, activeStatus, currentPage], fetchRecords);
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <!-- 头部 -->
    <div class="flex items-center justify-between gap-3 px-6 py-4">
      <h1 class="text-xl font-semibold text-n-slate-12">生产订单</h1>
      <Button label="从销售订单转入" color="iris" size="sm" @click="openConvert" />
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
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ po.salesOrderNo || '—' }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">{{ po.ownerName || '—' }}</td>
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
          <span class="font-semibold text-n-slate-12">{{ selected.orderNo }}</span>
          <span class="text-xs text-n-slate-11">
            {{ STATUS_LABELS[selected.status] }}
          </span>
        </div>
        <div class="mb-4 text-sm text-n-slate-11">
          {{ selected.productName }} · {{ selected.producedQty }}/{{ selected.qty }}
          {{ selected.unit }}
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
                class="w-px h-6"
                :class="
                  i < stageIndex(selected.stage) ? 'bg-n-iris-9' : 'bg-n-slate-4'
                "
              />
            </div>
            <span
              class="pt-0.5 text-sm"
              :class="
                i === stageIndex(selected.stage)
                  ? 'font-semibold text-n-slate-12'
                  : 'text-n-slate-11'
              "
            >
              {{ s.label }}
            </span>
          </div>
        </div>

        <div class="pt-4 mt-4 border-t border-n-weak">
          <div v-if="selected.bomNo" class="text-xs text-n-slate-11">
            工程 BOM：{{ selected.bomNo }}
          </div>
          <Button
            v-else-if="selected.stage === 'SALES_CONFIRMED'"
            label="挂工程 BOM"
            color="iris"
            size="sm"
            class="w-full"
            @click="openAttachBom"
          />
        </div>

        <div
          v-if="selected.deliveryDate"
          class="pt-3 mt-3 text-xs border-t text-n-slate-11 border-n-weak"
        >
          交期：{{ new Date(selected.deliveryDate).toLocaleDateString() }}
        </div>
      </div>
    </div>

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
          <Input v-model="convertForm.productName" placeholder="未选成品时手填" />
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
      title="挂工程 BOM"
      description="选择该成品的 BOM，按预估交期算出预估完工，生产订单进入「工程BOM」阶段。"
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
          <label class="text-heading-3 text-n-slate-12">
            预估完工（留空则按 BOM 交期天数自动算）
          </label>
          <Input v-model="bomForm.plannedEndDate" type="date" />
        </div>
      </div>
    </Dialog>
  </div>
</template>
