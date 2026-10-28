<script setup>
/* global axios */
import { ref, computed, reactive, watch, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesProductionRecordsStore } from 'dashboard/stores/mes/productionRecords';

import Button from 'dashboard/components-next/button/Button.vue';
import MesBoardOwnerBar from 'dashboard/components-next/mes/MesBoardOwnerBar.vue';
import { useMesRole } from 'dashboard/composables/useMesRole';
import { useMesDocOwner } from 'dashboard/composables/useMesDocOwner';
import Input from 'dashboard/components-next/input/Input.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import MesViewDialog from 'dashboard/components-next/mes/MesViewDialog.vue';
import MesReturnControls from 'dashboard/components-next/mes/MesReturnControls.vue';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';
import { orderSearchText } from 'dashboard/routes/dashboard/mes/orderSearchText';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
const { accountId } = useAccount();
const store = useMesProductionRecordsStore();

// 列表搜索：工单号 / 成品名 / 工序 / 备注。车间翻记录基本就靠这几样。
const searchQuery = ref('');
const fetchList = () => store.get({ q: searchQuery.value.trim() || undefined });
const onSearch = () => fetchList();
const { mesCan } = useMesRole();
const { isMyDoc } = useMesDocOwner();
// 报工的制单人是报工人本人（operatorId），别人删不了。
const canDeleteRecord = r => mesCan('report') && isMyDoc(r, 'operatorId');

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
    { label: '销售订单', value: r.productionOrderNo },
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
// 流程锁：报工只对「自制且已完成领料（进入生产领料/生产及以后）」的订单开单。
// 外购订单不报工、未领料的订单不可越级报工——都不出现在可选项里。
const RECORD_ELIGIBLE_STAGES = ['PICKING', 'PRODUCTION', 'FG_INBOUND'];
const eligibleOrders = computed(() =>
  productionOrders.value.filter(
    p => !p.is_outsourced && RECORD_ELIGIBLE_STAGES.includes(p.stage)
  )
);
const productionOrderOptions = computed(() => [
  { value: '', label: '选择销售订单…' },
  ...eligibleOrders.value.map(p => ({
    value: String(p.id),
    label: `${p.order_no} · ${p.product_name}`,
    searchText: orderSearchText(p),
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
const { isDirty, markPristine } = useDirtyGuard(() => form);
const selectedOrder = computed(() =>
  productionOrders.value.find(
    p => String(p.id) === String(form.productionOrderId)
  )
);
// 订单剩余可报数量 = 订单数量 − 已产（下限 0）；报满则不能再报，挡重复/超量报工。
const remainingQty = computed(() => {
  const o = selectedOrder.value;
  if (!o || o.qty == null) return null;
  return Math.max(Number(o.qty) - Number(o.produced_qty || 0), 0);
});
const overReport = computed(
  () =>
    remainingQty.value != null &&
    Number(form.qtyCompleted || 0) > remainingQty.value
);
const invalid = computed(
  () => !form.productionOrderId || form.qtyCompleted === '' || overReport.value
);
// 选订单后把完成数默认成剩余可报数量，避免手滑重复报满。
watch(
  () => form.productionOrderId,
  () => {
    if (remainingQty.value != null)
      form.qtyCompleted = String(remainingQty.value);
  }
);

const fetchOrders = async () => {
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/production_orders`,
      { params: { per_page: 500 } }
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
  markPristine();
  dialogRef.value?.open();
};

const submit = async () => {
  if (invalid.value) return;
  try {
    await store.create({
      productionOrderId: Number(form.productionOrderId),
      operationName: form.operationName || null,
      qtyCompleted: Number(form.qtyCompleted) || 0,
      qtyReturned: Number(form.qtyReturned) || 0,
      qtyScrap: Number(form.qtyScrap) || 0,
      remark: form.remark,
    });
    useAlert('报工已录入');
    dialogRef.value?.close();
    fetchList();
    fetchOrders();
  } catch (e) {
    useAlert(e?.message || '报工失败，请重试');
  }
};

// 删除报工（清理重复/错误报工）：删除后端会回退生产订单已产数量。
const deleteDialogRef = ref(null);
const pendingDelete = ref(null);
const askDelete = r => {
  pendingDelete.value = r;
  deleteDialogRef.value?.open();
};
const confirmDelete = async () => {
  try {
    await store.delete(pendingDelete.value.id);
    useAlert('报工已删除，已回退该订单的已产数量');
    deleteDialogRef.value?.close();
    fetchOrders();
  } catch (e) {
    useAlert(e?.message || '删除失败，请重试');
  }
};

onMounted(() => {
  fetchList();
  fetchOrders();
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div
      class="flex items-center justify-between px-4 py-3 sm:px-6 sm:py-4 [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:sm:!px-8"
    >
      <h1
        class="text-xl font-semibold text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8"
      >
        生产报工
      </h1>
      <div class="w-64 ms-auto me-2">
        <Input
          v-model="searchQuery"
          size="sm"
          placeholder="搜工单号 / 成品 / 工序"
          @keyup.enter="onSearch"
        />
      </div>
      <Button
        v-if="mesCan('report')"
        label="报工"
        color="iris"
        size="sm"
        @click="openCreate"
      />
    </div>

    <MesBoardOwnerBar board-key="mes_production_records_index" />

    <HScrollButtons />
    <div
      class="flex-1 min-h-0 px-4 pb-4 overflow-auto sm:px-6 sm:pb-6 [.theme-classic_&]:sm:!px-8"
    >
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <template v-else>
        <!-- 手机卡片 -->
        <div class="flex flex-col gap-2 md:hidden">
          <div
            v-for="r in records"
            :key="r.id"
            class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl active:bg-n-alpha-1"
            @click="openView(r)"
          >
            <div class="flex items-center gap-2">
              <span class="font-medium truncate text-n-slate-12">
                {{ r.productionOrderNo || '—' }}
              </span>
              <span class="flex-1" />
              <div class="shrink-0 inline-flex items-center gap-1" @click.stop>
                <Button
                  label="查看"
                  variant="ghost"
                  size="sm"
                  @click="openView(r)"
                />
                <MesReturnControls
                  :record="r"
                  :store="store"
                  :can-manage="mesCan('report')"
                />
                <Button
                  v-if="canDeleteRecord(r)"
                  label="删除"
                  variant="ghost"
                  color="ruby"
                  size="sm"
                  @click="askDelete(r)"
                />
              </div>
            </div>
            <div v-if="r.productName" class="mt-1 text-xs text-n-slate-11">
              {{ r.productName }}
            </div>
            <div v-if="r.productSku" class="text-xs text-n-slate-10">
              商品编码 {{ r.productSku }}
            </div>
            <div class="flex flex-wrap gap-3 mt-1 text-xs text-n-slate-11">
              <span>归属人：{{ r.productionOrderOwnerName || '—' }}</span>
              <span>工序：{{ r.operationName || '—' }}</span>
              <span>报工人：{{ r.operatorName || '—' }}</span>
            </div>
            <div class="flex flex-wrap gap-3 mt-1 text-xs text-n-slate-11">
              <span>完成：{{ r.qtyCompleted }}</span>
              <span>退料：{{ r.qtyReturned }}</span>
              <span>清尾：{{ r.qtyScrap }}</span>
            </div>
            <div class="mt-1 text-xs text-n-slate-11">
              时间：{{ time(r.recordedAt) }}
            </div>
          </div>
          <div v-if="!records.length" class="py-10 text-center text-n-slate-11">
            还没有报工记录。
          </div>
        </div>

        <!-- 桌面表格 -->
        <table class="hidden w-full text-sm md:table">
          <thead>
            <tr class="text-left text-n-slate-11 border-b border-n-weak">
              <th class="px-3 py-3 font-medium whitespace-nowrap">销售订单</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">归属人</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">工序</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">完成</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">退料</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">清尾</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">报工人</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">时间</th>
              <th class="px-3 py-3" />
            </tr>
          </thead>
          <tbody>
            <tr v-for="r in records" :key="r.id" class="border-b border-n-weak">
              <td class="px-3 py-3 font-medium text-n-slate-12">
                <div>{{ r.productionOrderNo || '—' }}</div>
                <div
                  v-if="r.productName"
                  class="text-xs font-normal text-n-slate-11"
                >
                  {{ r.productName }}
                </div>
                <div
                  v-if="r.productSku"
                  class="text-xs font-normal text-n-slate-10"
                >
                  商品编码 {{ r.productSku }}
                </div>
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
              <td class="px-3 py-3 text-n-slate-11">
                {{ time(r.recordedAt) }}
              </td>
              <td class="px-3 py-3 text-right">
                <div class="inline-flex items-center justify-end gap-1">
                  <Button
                    label="查看"
                    variant="ghost"
                    size="sm"
                    @click="openView(r)"
                  />
                  <MesReturnControls
                    :record="r"
                    :store="store"
                    :can-manage="mesCan('report')"
                  />
                  <Button
                    v-if="canDeleteRecord(r)"
                    label="删除"
                    variant="ghost"
                    color="ruby"
                    size="sm"
                    @click="askDelete(r)"
                  />
                </div>
              </td>
            </tr>
            <tr v-if="!records.length">
              <td colspan="9" class="px-3 py-10 text-center text-n-slate-11">
                还没有报工记录。
              </td>
            </tr>
          </tbody>
        </table>
      </template>
    </div>

    <Dialog
      ref="dialogRef"
      :dismissible="false"
      width="lg"
      confirm-button-color="iris"
      title="生产报工"
      description="完成数量累加生产进度"
      :is-loading="saving"
      :disable-confirm-button="invalid"
      :dirty="isDirty"
      dirty-save-label="保存"
      @confirm="submit"
      @close="markPristine"
      @save="submit"
    >
      <div class="flex flex-col gap-4">
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">
            生产订单 <span class="text-n-ruby-11">*</span>
          </label>
          <ComboBox
            :model-value="form.productionOrderId"
            :options="productionOrderOptions"
            placeholder="选择销售订单…"
            search-placeholder="搜 MO 号 / 产品 / 销售订单 / 客户"
            empty-state="没有可报工的生产订单"
            @update:model-value="v => (form.productionOrderId = v)"
          />
          <span
            v-if="!eligibleOrders.length"
            class="text-xs text-n-amber-11 leading-snug"
          >
            暂无可报工订单：报工需订单已进入「生产领料」阶段，请先在「生产 →
            生产领料」把对应领料单点「过账」。
          </span>
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
            <span
              v-if="remainingQty != null"
              class="text-xs"
              :class="overReport ? 'text-n-ruby-11' : 'text-n-slate-10'"
            >
              <template v-if="remainingQty === 0">
                该订单已报满（已产 {{ selectedOrder.produced_qty }}/{{
                  selectedOrder.qty
                }}），不能再报
              </template>
              <template v-else-if="overReport">
                超过剩余可报 {{ remainingQty }}，请勿重复/超量报工
              </template>
              <template v-else>剩余可报 {{ remainingQty }}</template>
            </span>
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

    <!-- 删除报工确认：删除会回退该订单的已产数量 -->
    <Dialog
      ref="deleteDialogRef"
      type="alert"
      title="删除报工"
      description="删除后会从该生产订单的已产数量中扣回本次报工数量，且不可恢复。确认删除？"
      confirm-button-label="删除"
      confirm-button-color="ruby"
      @confirm="confirmDelete"
    />
  </div>
</template>
