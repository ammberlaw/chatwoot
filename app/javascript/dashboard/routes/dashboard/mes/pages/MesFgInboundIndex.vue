<script setup>
/* global axios */
import { ref, computed, reactive, onMounted, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesStockEntriesStore } from 'dashboard/stores/mes/stockEntries';
import { useMesWarehousesStore } from 'dashboard/stores/mes/warehouses';

import Button from 'dashboard/components-next/button/Button.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import MesBoardOwnerBar from 'dashboard/components-next/mes/MesBoardOwnerBar.vue';
import { useMesRole } from 'dashboard/composables/useMesRole';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import MesViewDialog from 'dashboard/components-next/mes/MesViewDialog.vue';
import MesReturnControls from 'dashboard/components-next/mes/MesReturnControls.vue';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';
import { orderSearchText } from 'dashboard/routes/dashboard/mes/orderSearchText';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import MesStatusPill from 'dashboard/components-next/mes/MesStatusPill.vue';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
const { accountId } = useAccount();
const store = useMesStockEntriesStore();
const { mesCan } = useMesRole();
const warehousesStore = useMesWarehousesStore();

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const saving = computed(() => store.getUIFlags.creatingItem);
const posting = computed(() => store.getUIFlags.updatingItem);
const day = d => (d ? new Date(d).toLocaleDateString() : '—');
const STATUS_LABELS = { DRAFT: '草稿', POSTED: '已过账', CANCELLED: '已取消' };

// 只读查看
const whName = id =>
  (warehousesStore.getRecords || []).find(w => w.id === id)?.name || '—';
const viewDialogRef = ref(null);
const viewing = ref(null);
const openView = e => {
  viewing.value = e;
  viewDialogRef.value?.open();
};
const viewFields = computed(() => {
  const e = viewing.value || {};
  return [
    { label: '单号', value: e.entryNo },
    { label: '销售订单', value: e.productionOrderNo },
    { label: '归属人', value: e.productionOrderOwnerName },
    { label: '成品仓', value: whName(e.toWarehouseId) },
    { label: '颜色', value: e.color },
    { label: '实际入库日期', value: day(e.actualInboundDate) },
    { label: '交接', value: e.isChecked ? '已交接' : '未交接' },
    { label: '状态', value: STATUS_LABELS[e.status] || e.status },
    { label: '过账时间', value: day(e.postedAt) },
    { label: '收货人', value: e.receivedByName },
    { label: '制单人', value: e.ownerName },
    { label: '备注', value: e.remark },
  ];
});
const VIEW_ITEM_COLS = [
  { label: '成品', key: 'name' },
  { label: '数量', key: 'qty', align: 'right' },
  { label: '单位', key: 'unit' },
];
const viewItems = computed(() =>
  (viewing.value?.stockEntryItems || []).map(it => ({
    name: it.productName || it.materialName,
    qty: it.qty,
    unit: it.unit,
  }))
);

// 后端每页 15 条，不传 page 就只看得到最新 15 张（成品入库单现在 12 张还没撞上，但代码一样，迟早会）。
const ITEMS_PER_PAGE = 15;
const currentPage = ref(1);
const totalCount = computed(() => store.getMeta?.count || 0);
const fetchList = () =>
  store.get({ purpose: 'MANUFACTURE', page: currentPage.value });
watch(currentPage, fetchList);

const productionOrders = ref([]);
// 流程锁：成品入库只对「自制且已进入生产/成品入库阶段」的订单开单。
// 外购订单走采购收货入成品仓、未报工的订单不可越级入库——都不出现在可选项里。
const FG_ELIGIBLE_STAGES = ['PRODUCTION', 'FG_INBOUND'];
const eligibleOrders = computed(() =>
  productionOrders.value.filter(
    // 同领料：字段是 is_outsourced，写成驼峰等于没过滤（外购成品走采购收货直入成品仓）。
    p => !p.is_outsourced && FG_ELIGIBLE_STAGES.includes(p.stage)
  )
);
// 这张订单还差多少没入库。已入满＝0。
const remainingOf = p =>
  Math.max(Number(p?.qty || 0) - Number(p?.fg_inbound_qty || 0), 0);

// 下拉里直接把「还差多少」写出来，入满的标出来并禁选。
// 原来只按阶段过滤，一张早已入满的订单会一直摆在下拉里、选中还自动把数量填成全量——
// 等于引着车间建重复单，而重复单要到几天后仓管点确认时才会报错（生产上积了 6 张）。
const productionOrderOptions = computed(() => [
  { value: '', label: '选择销售订单…' },
  ...eligibleOrders.value.map(p => {
    const left = remainingOf(p);
    return {
      value: String(p.id),
      label: left
        ? `${p.order_no} · ${p.product_name}（还差 ${left}）`
        : `${p.order_no} · ${p.product_name}（已入满）`,
      disabled: left <= 0,
      searchText: orderSearchText(p),
    };
  }),
]);
const warehouseOptions = computed(() =>
  (warehousesStore.getRecords || []).map(w => ({
    value: String(w.id),
    label: w.name,
  }))
);

const dialogRef = ref(null);
const form = reactive({
  productionOrderId: '',
  warehouseId: '',
  qty: '',
  color: '',
  actualInboundDate: '',
  remark: '',
  isChecked: false,
});
const { isDirty, markPristine } = useDirtyGuard(() => form);
const today = () => new Date().toISOString().slice(0, 10);
const selectedOrder = computed(() =>
  productionOrders.value.find(
    p => String(p.id) === String(form.productionOrderId)
  )
);
const overRemaining = computed(
  () =>
    !!selectedOrder.value && Number(form.qty) > remainingOf(selectedOrder.value)
);
const invalid = computed(
  () =>
    !form.productionOrderId ||
    !form.warehouseId ||
    !Number(form.qty) ||
    overRemaining.value
);

// 选生产订单 → 数量默认填**还差的量**（不是全量）：已入过一部分的订单
// 再按全量填就会超，而超量要到仓管过账时才报。
const onPickOrder = v => {
  form.productionOrderId = v;
  const po = productionOrders.value.find(p => String(p.id) === String(v));
  if (!po) return;

  const left = remainingOf(po);
  const produced = Number(po.produced_qty || 0);
  form.qty = String(left ? Math.min(produced || left, left) : '');
};

const openCreate = () => {
  const fin = (warehousesStore.getRecords || []).find(
    w => w.kind === 'FINISHED'
  );
  Object.assign(form, {
    productionOrderId: '',
    warehouseId: fin ? String(fin.id) : '',
    qty: '',
    color: '',
    actualInboundDate: today(),
    remark: '',
    isChecked: false,
  });
  markPristine();
  dialogRef.value?.open();
};

const submit = async () => {
  if (invalid.value) return;
  const po = selectedOrder.value;
  const ok = await store.create({
    purpose: 'MANUFACTURE',
    productionOrderId: Number(form.productionOrderId),
    toWarehouseId: Number(form.warehouseId),
    color: form.color.trim() || null,
    actualInboundDate: form.actualInboundDate || null,
    remark: form.remark.trim() || null,
    isChecked: form.isChecked,
    stockEntryItemsAttributes: [
      {
        itemType: 'PRODUCT',
        crmProductId: po?.crm_product_id || null,
        qty: Number(form.qty),
        warehouseId: Number(form.warehouseId),
      },
    ],
  });
  if (ok) {
    useAlert(`已建成品入库单 ${ok.entryNo}，待过账`);
    dialogRef.value?.close();
  }
};

// 流程：车间（report）开单交接 → 仓库（stock）清点数量确认，确认即过账入库。
const confirmWarehouse = async entry => {
  const ok = await store.confirmWarehouse(entry.id);
  if (ok) useAlert(`${ok.entryNo} 已清点确认，成品入库`);
};

// 删单：草稿直接删；已过账走「作废」冲销（退回库存，保留单据可追溯）。
// 仓管可删别人建的草稿——重复单往往是仓管清点时才发现的，只许制单人删就成了死锁。
const removeEntry = async e => {
  const posted = e.status === 'POSTED';
  const text = posted
    ? `确定作废成品入库单 ${e.entryNo}？已入库的数量会从结存冲回。`
    : `确定删除成品入库单 ${e.entryNo}？删除后不可恢复。`;
  // eslint-disable-next-line no-alert
  if (!window.confirm(text)) return;
  try {
    const ok = posted ? await store.cancel(e.id) : await store.delete(e.id);
    if (ok) useAlert(posted ? '已作废' : '已删除');
  } catch (error) {
    useAlert(error.message || (posted ? '作废失败' : '删除失败'));
  }
};

onMounted(() => {
  fetchList();
  warehousesStore.get();
  axios
    .get(`/api/v1/accounts/${accountId.value}/mes/production_orders`, {
      // 下拉要能选到所有在产订单:不传 per_page 后端只给最新 15 条(RESULTS_PER_PAGE),
      // 早一点的单子在下拉里根本找不到。封顶 500。
      params: { per_page: 500 },
    })
    .then(({ data }) => {
      productionOrders.value = data?.payload || [];
    })
    .catch(() => {
      productionOrders.value = [];
    });
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between px-4 py-3 sm:px-6 sm:py-4 [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:sm:!px-8">
      <h1 class="text-xl font-semibold text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8">成品入库</h1>
      <!-- 车间(report)开单、仓管(stock)清点是常态，但仓管自己也常要补开这张单
           （他是成品入库这一阶段的负责人）。后端 StockEntryPolicy#create? 本来就是
           stock || report，这里原先只认 report，比后端还严——仓管看得到「清点确认入库」
           却看不到「新建」。与后端对齐。 -->
      <Button
        v-if="mesCan('report') || mesCan('stock')"
        label="新建成品入库单"
        color="iris"
        size="sm"
        @click="openCreate"
      />
    </div>

    <MesBoardOwnerBar board-key="mes_fg_inbound_index" />

    <HScrollButtons />
    <div class="flex-1 min-h-0 px-4 sm:px-6 overflow-auto [.theme-classic_&]:sm:!px-8">
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <template v-else>
        <div class="flex flex-col gap-2 md:hidden">
          <div
            v-for="e in records"
            :key="e.id"
            class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl active:bg-n-alpha-1"
            @click="openView(e)"
          >
            <div class="flex items-center gap-2">
              <span class="font-medium text-n-slate-12 truncate">
                {{ e.entryNo }}
              </span>
              <MesStatusPill
                class="shrink-0"
                :label="STATUS_LABELS[e.status]"
              />
              <span class="flex-1" />
              <Button
                v-if="e.status === 'DRAFT' && mesCan('stock')"
                label="清点确认入库"
                color="iris"
                size="sm"
                class="shrink-0"
                :is-loading="posting"
                @click.stop="confirmWarehouse(e)"
              />
            </div>
            <div
              class="mt-1 flex flex-wrap gap-x-3 gap-y-1 text-xs text-n-slate-11"
            >
              <span>生产订单：{{ e.productionOrderNo || '—' }}</span>
              <span v-if="e.productName">{{ e.productName }}</span>
              <span v-if="e.productSku">编码 {{ e.productSku }}</span>
              <span>颜色：{{ e.color || '—' }}</span>
              <span>归属人：{{ e.productionOrderOwnerName || '—' }}</span>
            </div>
            <div
              class="mt-1 flex flex-wrap gap-x-3 gap-y-1 text-xs text-n-slate-11"
            >
              <span>
                仓库清点：
                <span
                  v-if="e.warehouseConfirmedAt"
                  class="whitespace-nowrap text-n-teal-11"
                >
                  ✓ {{ e.warehouseConfirmedByName || '' }}
                </span>
                <span v-else-if="e.status === 'DRAFT'" class="text-n-slate-10">
                  待清点
                </span>
                <span v-else class="text-n-slate-10">—</span>
              </span>
              <span>过账时间：{{ day(e.postedAt) }}</span>
            </div>
            <div class="mt-2 flex flex-wrap gap-1" @click.stop>
              <MesReturnControls
                :record="e"
                :store="store"
                :can-manage="mesCan('stock')"
              />
            </div>
          </div>
          <div v-if="!records.length" class="py-10 text-center text-n-slate-11">
            还没有成品入库单。
          </div>
        </div>
        <table class="hidden md:table w-full text-sm">
          <thead>
            <tr class="text-left text-n-slate-11 border-b border-n-weak">
              <th class="px-3 py-3 font-medium whitespace-nowrap">单号</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap min-w-[160px]">
                销售订单
              </th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">颜色</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap min-w-[112px]">
                归属人
              </th>
              <th class="px-3 py-3 font-medium whitespace-nowrap min-w-[112px]">
                仓库清点
              </th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">状态</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">过账时间</th>
              <th class="px-3 py-3" />
            </tr>
          </thead>
          <tbody>
            <tr v-for="e in records" :key="e.id" class="border-b border-n-weak">
              <td
                class="px-3 py-3 font-medium whitespace-nowrap text-n-slate-12"
              >
                {{ e.entryNo }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                <div class="whitespace-nowrap">
                  {{ e.productionOrderNo || '—' }}
                </div>
                <div v-if="e.productName" class="text-xs text-n-slate-12">
                  {{ e.productName }}
                </div>
                <div v-if="e.productSku" class="text-xs text-n-slate-10">
                  商品编码 {{ e.productSku }}
                </div>
              </td>
              <td class="px-3 py-3 text-n-slate-11">{{ e.color || '—' }}</td>
              <td class="px-3 py-3 whitespace-nowrap text-n-slate-11">
                {{ e.productionOrderOwnerName || '—' }}
              </td>
              <td class="px-3 py-3 text-xs">
                <span v-if="e.warehouseConfirmedAt" class="text-n-teal-11">
                  ✓ {{ e.warehouseConfirmedByName || '' }}
                </span>
                <span v-else-if="e.status === 'DRAFT'" class="text-n-slate-10">
                  待清点
                </span>
                <span v-else class="text-n-slate-10">—</span>
              </td>
              <td class="px-3 py-3">
                <MesStatusPill :label="STATUS_LABELS[e.status]" />
              </td>
              <td class="px-3 py-3 whitespace-nowrap text-n-slate-11">
                {{ day(e.postedAt) }}
              </td>
              <td class="px-3 py-3 text-right">
                <div class="flex justify-end gap-1">
                  <Button
                    label="查看"
                    variant="ghost"
                    size="sm"
                    @click="openView(e)"
                  />
                  <Button
                    v-if="e.status === 'DRAFT' && mesCan('stock')"
                    label="清点确认入库"
                    color="iris"
                    size="sm"
                    :is-loading="posting"
                    @click="confirmWarehouse(e)"
                  />
                  <Button
                    v-if="mesCan('stock') && e.status !== 'CANCELLED'"
                    :label="e.status === 'POSTED' ? '作废' : '删单'"
                    color="ruby"
                    variant="ghost"
                    size="sm"
                    :is-loading="posting"
                    @click="removeEntry(e)"
                  />
                  <MesReturnControls
                    :record="e"
                    :store="store"
                    :can-manage="mesCan('stock')"
                  />
                </div>
              </td>
            </tr>
            <tr v-if="!records.length">
              <td colspan="8" class="px-3 py-10 text-center text-n-slate-11">
                还没有成品入库单。
              </td>
            </tr>
          </tbody>
        </table>
      </template>

      <PaginationFooter
        v-if="totalCount > ITEMS_PER_PAGE"
        :current-page="currentPage"
        :total-items="totalCount"
        :items-per-page="ITEMS_PER_PAGE"
        class="sticky bottom-0 z-10"
        @update:current-page="currentPage = $event"
      />
    </div>

    <Dialog
      ref="dialogRef"
      :dismissible="false"
      width="lg"
      confirm-button-color="iris"
      title="新建成品入库单"
      description="车间完工后开单交接（选生产订单带出已产数量）；仓库清点数量确认后自动过账入库。"
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
            empty-state="没有可入库的生产订单"
            @update:model-value="onPickOrder"
          />
          <span v-if="selectedOrder" class="text-xs text-n-slate-11">
            {{ selectedOrder.product_name }} · 已产
            {{ selectedOrder.produced_qty }} / {{ selectedOrder.qty }} · 已入库
            {{ selectedOrder.fg_inbound_qty }}，还差
            <span class="text-n-slate-12">{{
              remainingOf(selectedOrder)
            }}</span>
          </span>
        </div>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              入库数量 <span class="text-n-ruby-11">*</span>
            </label>
            <Input v-model="form.qty" type="number" />
            <span v-if="overRemaining" class="text-xs text-n-ruby-11">
              超出订单剩余 {{ remainingOf(selectedOrder) }}，不能超量入库
            </span>
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">入库仓库</label>
            <SelectCard
              size="form"
              :model-value="form.warehouseId"
              :options="warehouseOptions"
              @update:model-value="v => (form.warehouseId = v)"
            />
          </div>
        </div>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">颜色</label>
            <Input v-model="form.color" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">实际入库日期</label>
            <Input v-model="form.actualInboundDate" type="date" />
          </div>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">备注</label>
          <Input v-model="form.remark" placeholder="选填" />
        </div>
        <label class="flex items-center gap-2 text-heading-3 text-n-slate-12">
          <input v-model="form.isChecked" type="checkbox" />
          已完成入库交接
        </label>
      </div>
    </Dialog>

    <MesViewDialog
      ref="viewDialogRef"
      :title="viewing ? `成品入库单 ${viewing.entryNo}` : '成品入库明细'"
      :fields="viewFields"
      items-title="成品明细"
      :item-columns="VIEW_ITEM_COLS"
      :items="viewItems"
    />
  </div>
</template>
