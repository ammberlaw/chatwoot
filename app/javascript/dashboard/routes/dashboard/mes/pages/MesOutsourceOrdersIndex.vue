<script setup>
// 委外加工：自己的料发给加工厂，加工厂做好还回来，我们按件付加工费。
//
// 与「外购」(生产订单的 is_outsourced) 的分界：外购是整台买进来、料和过程都不是我们的；
// 委外是**料还是我们的**，只是换个地方加工，所以料要跟着单据在委外仓记一笔。
// 生产上四个委外仓压着真实的料，但 2026-10-07 期初之后一张进出单都没有——
// 不是没这个业务，是开不出单。
//
// 谁能安排委外＝**工程 / PMC**（用户 2026-11-02 定）：外发哪一单、给哪家厂、什么时候
// 要回来，是排产决策。单子仍然挂在生产订单上（销售订单→生产订单→委外加工→入库→发货
// 连成一条链），但**建单入口在这一页**——工程/PMC 来这儿建单、跟单、看进度，一处办完。
// 销售订单页上只显示「在 XX 厂加工中」的只读进度，不放操作入口。
import { ref, reactive, computed, onMounted, watch, nextTick } from 'vue';
import { useRoute } from 'vue-router';
import camelcaseKeys from 'camelcase-keys';
import { useAlert } from 'dashboard/composables';
import { useMesRole } from 'dashboard/composables/useMesRole';
import { useMesOutsourceOrdersStore } from 'dashboard/stores/mes/outsourceOrders';
import { useMesWarehousesStore } from 'dashboard/stores/mes/warehouses';
import MesOutsourceOrderAPI from 'dashboard/api/mes/outsourceOrders';
import MesStockEntryAPI from 'dashboard/api/mes/stockEntries';
import { fmtMoney } from 'dashboard/helper/erpMoney';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import MesStatusPill from 'dashboard/components-next/mes/MesStatusPill.vue';
import MesColumnFilter from 'dashboard/components-next/mes/MesColumnFilter.vue';
import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
import MesOutsourceOrderPrintSheet from 'dashboard/components-next/mes/MesOutsourceOrderPrintSheet.vue';
import MesOutsourceEntryPrintSheet from 'dashboard/components-next/mes/MesOutsourceEntryPrintSheet.vue';
import { printElement } from 'dashboard/helper/printHelper';
import { fetchAllRows } from 'dashboard/helper/erpExcel';
import { orderSearchText } from '../orderSearchText';
import MesProductionOrderAPI from 'dashboard/api/mes/productionOrders';
import MesSupplierAPI from 'dashboard/api/mes/suppliers';

const route = useRoute();
const store = useMesOutsourceOrdersStore();
const warehousesStore = useMesWarehousesStore();
const { mesCan } = useMesRole();

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const busy = ref(false);
// 对齐后端 Mes::OutsourceOrderPolicy：建单/确认/关闭＝工程 PMC（:bom），
// 发料/入库/退料＝仓管，工程 PMC 也放行（小批量常是一个人从头跟到尾）。
const canSchedule = computed(() => mesCan('bom'));
const canWrite = computed(() => mesCan('stock') || canSchedule.value);

const day = d => (d ? new Date(d).toLocaleDateString() : '—');
const money = micros => (micros ? fmtMoney(micros) : '—');
const num = n => Number(n || 0);

const STATUS_LABELS = {
  DRAFT: '草稿',
  CONFIRMED: '已确认',
  CLOSED: '已关闭',
  CANCELLED: '已取消',
};
const STATUS_FILTERS = [
  { value: '', label: '全部' },
  ...Object.entries(STATUS_LABELS).map(([value, label]) => ({ value, label })),
];
// 派生单据的用途文案。三张单都落在 mes_stock_entries 上（一表多用）。
const PURPOSE_LABELS = {
  OUTSOURCE_ISSUE: '发料',
  OUTSOURCE_RECEIPT: '产品入库',
  OUTSOURCE_RETURN: '退料',
};
const ENTRY_STATUS_LABELS = {
  DRAFT: '草稿',
  POSTED: '已过账',
  CANCELLED: '已作废',
};

const ITEMS_PER_PAGE = 15;
const currentPage = ref(1);
const totalCount = computed(() => store.getMeta?.count || 0);
const activeStatus = ref('');
const searchQuery = ref('');
const fromDate = ref('');
const toDate = ref('');
// 表头逐列筛选（后端口径见 OutsourceOrdersController::COLUMN_LIKE_FILTERS）。
// 状态不放漏斗——上面那排页签就是它。
const colFilters = reactive({
  col_no: '',
  col_supplier: '',
  col_product: '',
  col_mo: '',
});
const FILTERABLE = {
  no: { key: 'col_no', placeholder: '委外单号' },
  supplier: { key: 'col_supplier', placeholder: '加工厂' },
  product: { key: 'col_product', placeholder: '产出品名 / 编码' },
  mo: { key: 'col_mo', placeholder: '生产订单号' },
};
const filterOf = key => FILTERABLE[key];

const fetchList = () =>
  store.get({
    page: currentPage.value,
    per_page: ITEMS_PER_PAGE,
    status: activeStatus.value || undefined,
    q: searchQuery.value.trim() || undefined,
    from: fromDate.value || undefined,
    to: toDate.value || undefined,
    col_no: colFilters.col_no.trim() || undefined,
    col_supplier: colFilters.col_supplier.trim() || undefined,
    col_product: colFilters.col_product.trim() || undefined,
    col_mo: colFilters.col_mo.trim() || undefined,
  });

// 换筛选条件回第 1 页——否则在第 3 页筛出 2 条结果会看到空列表。
const onFilterChange = () => {
  currentPage.value = 1;
  fetchList();
};
watch(currentPage, fetchList);
watch([fromDate, toDate], onFilterChange);
const onStatus = value => {
  activeStatus.value = value;
  onFilterChange();
};

const warehouseOptions = computed(() =>
  (warehousesStore.getRecords || []).map(w => ({
    value: String(w.id),
    label: w.name,
  }))
);

// ── 明细 ──
const viewDialogRef = ref(null);
const viewing = ref(null);
// 发完料/入完库之后数字会变，重新取这一张而不是整页重拉。
const refreshViewing = async () => {
  if (!viewing.value) return;
  const { data } = await MesOutsourceOrderAPI.show(viewing.value.id);
  // ⚠️ 裸 axios 取数拿到的是 snake_case，列表走 store 是驼峰——混用的话
  // 明细里加工厂、用料全是空的（2026-10-07 委外单那次同款坑，这次又踩了一遍）。
  if (data?.payload) {
    viewing.value = camelcaseKeys(data.payload, { deep: true });
  }
};
const openView = async record => {
  viewing.value = record;
  viewDialogRef.value?.open();
  await refreshViewing();
};

const act = async (fn, okText) => {
  busy.value = true;
  try {
    await fn();
    useAlert(okText);
    await refreshViewing();
    await fetchList();
  } catch (e) {
    useAlert(e?.response?.data?.error || e?.message || '操作失败，请重试');
  } finally {
    busy.value = false;
  }
};

const confirmOrder = record =>
  act(() => MesOutsourceOrderAPI.confirm(record.id), '已确认，可以发料了');
const closeOrder = record =>
  act(() => MesOutsourceOrderAPI.close(record.id), '已关闭');
const issueAll = record =>
  act(
    () => MesOutsourceOrderAPI.issue(record.id),
    '发料单已生成（草稿），在下方「单据」里过账'
  );
const generateFee = record =>
  act(() => MesOutsourceOrderAPI.generateFee(record.id), '加工费已挂到应付');

// ── 产品入库 ──
const receiptDialogRef = ref(null);
const receiptForm = reactive({ qty: '', warehouseId: '' });
const openReceipt = () => {
  receiptForm.qty = String(num(viewing.value?.remainingQty) || '');
  receiptForm.warehouseId = String(viewing.value?.toWarehouseId || '');
  receiptDialogRef.value?.open();
};
const submitReceipt = () =>
  act(async () => {
    await MesOutsourceOrderAPI.receipt(
      viewing.value.id,
      receiptForm.qty,
      receiptForm.warehouseId
    );
    receiptDialogRef.value?.close();
  }, '入库单已生成（草稿），在下方「单据」里过账');

// ── 退料 ──
const returnDialogRef = ref(null);
const returnForm = reactive({ warehouseId: '', rows: [] });
const openReturn = () => {
  returnForm.warehouseId = '';
  // 只列「加工厂手上还剩得下」的料：已发 − 已耗 − 已退。
  returnForm.rows = (viewing.value?.outsourceMaterials || [])
    .filter(m => num(m.returnableQty) > 0)
    .map(m => ({
      materialId: m.id,
      name: m.itemName,
      unit: m.unit,
      max: num(m.returnableQty),
      qty: '',
    }));
  returnDialogRef.value?.open();
};
const returnPayload = computed(() =>
  returnForm.rows
    .filter(r => num(r.qty) > 0)
    .map(r => ({ material_id: r.materialId, qty: r.qty }))
);
// 没选仓 / 一行数量都没填就别放行——后端会拒，但让人点完才报错是白走一趟。
const returnInvalid = computed(
  () => !returnForm.warehouseId || !returnPayload.value.length
);
const receiptInvalid = computed(
  () => !(num(receiptForm.qty) > 0) || !receiptForm.warehouseId
);
const submitReturn = () =>
  act(async () => {
    await MesOutsourceOrderAPI.returnMaterials(
      viewing.value.id,
      returnPayload.value,
      returnForm.warehouseId
    );
    returnDialogRef.value?.close();
  }, '退料单已生成（草稿），在下方「单据」里过账');

// ── 新建委外加工单（工程 / PMC）──
//
// 单子仍然挂在生产订单上（用料从那张单的 BOM 带），所以第一步是选一张生产订单。
// 只列**挂了生产任务单、还没发货、不是外购**的单：没 BOM 转过去只会建出一张没有
// 用料行的空单；外购单的料和过程都不是我们的，没有自己的料可发。
const createDialogRef = ref(null);
const moOptions = ref([]);
const supplierOptions = ref([]);
const wwWarehouseOptions = ref([]);
const loadingOptions = ref(false);
const form = reactive({
  productionOrderId: '',
  supplierId: '',
  warehouseId: '',
  toWarehouseId: '',
  feeRate: '',
  taxRate: '13',
});
// 从生产任务单跳过来时带的 bom_id：把生产订单下拉收敛到这张任务单名下的订单。
const fromBomId = ref(null);
const createInvalid = computed(
  () => !form.productionOrderId || !form.supplierId || !form.warehouseId
);

// 下拉一律取全量：per_page 有硬天花板，超了会静默吞掉、搜不出来。
const loadOptions = async () => {
  if (moOptions.value.length) return;
  // moOptions 在 openCreate 里按 bom 清过，这里不再另设缓存键。
  loadingOptions.value = true;
  try {
    const [orders, suppliers] = await Promise.all([
      fetchAllRows(params => MesProductionOrderAPI.get(params)),
      fetchAllRows(params => MesSupplierAPI.get(params)),
    ]);
    moOptions.value = (orders || [])
      .map(o => camelcaseKeys(o, { deep: true }))
      .filter(o => o.bomId && !o.isOutsourced && o.stage !== 'SHIPPED')
      .filter(o => !fromBomId.value || Number(o.bomId) === fromBomId.value)
      .map(o => ({
        value: String(o.id),
        label: `${o.orderNo} · ${o.productName || o.model || ''}`,
        searchText: orderSearchText(o),
      }));
    supplierOptions.value = (suppliers || []).map(x => ({
      value: String(x.id),
      label: x.name,
    }));
    wwWarehouseOptions.value = (warehousesStore.getRecords || []).map(w => ({
      value: String(w.id),
      label: w.name,
    }));
  } catch (e) {
    useAlert('选项加载失败，请重试');
  } finally {
    loadingOptions.value = false;
  }
};

const openCreate = async (bomId = null) => {
  fromBomId.value = bomId ? Number(bomId) : null;
  moOptions.value = [];
  Object.assign(form, {
    productionOrderId: '',
    supplierId: '',
    warehouseId: '',
    toWarehouseId: '',
    feeRate: '',
    taxRate: '13',
  });
  createDialogRef.value?.open();
  await loadOptions();
};

const submitCreate = async () => {
  if (createInvalid.value || busy.value) return;
  busy.value = true;
  try {
    const { data } = await MesOutsourceOrderAPI.createFromProductionOrder(
      Number(form.productionOrderId),
      {
        mes_supplier_id: Number(form.supplierId),
        mes_warehouse_id: Number(form.warehouseId),
        to_warehouse_id: form.toWarehouseId
          ? Number(form.toWarehouseId)
          : undefined,
        // 录的是含税加工费单价（跟加工厂谈的就是含税价）
        fee_rate_micros: Math.round(Number(form.feeRate || 0) * 1e6),
        fee_tax_included: true,
        tax_rate: Number(form.taxRate || 0),
      }
    );
    createDialogRef.value?.close();
    useAlert(`已建单：${data?.payload?.order_no || ''}`);
    fetchList();
  } catch (e) {
    useAlert(e?.response?.data?.error || '建单失败，请重试');
  } finally {
    busy.value = false;
  }
};

// ── 派生单据：过账 / 作废 ──
const postEntry = entry =>
  act(() => MesStockEntryAPI.post(entry.id), '已过账，库存已更新');
const cancelEntry = entry =>
  act(() => MesStockEntryAPI.cancel(entry.id), '已作废，库存已冲回');

// ── 打印 ──
// 加工单给加工厂的那一份；发料/退料/入库三张给仓管和加工厂签收用。
// 三张派生单的明细不在列表接口里（列表只带数量和行数，带全了会撑爆），打印时现取。
const printingOrder = ref(null);
const printingEntry = ref(null);
const printEntryItems = ref([]);
const orderSheetRef = ref(null);
const entrySheetRef = ref(null);

const warehouseName = id =>
  (warehousesStore.getRecords || []).find(w => String(w.id) === String(id))
    ?.name || '';

const printOrder = async record => {
  printingOrder.value = record;
  // 等票面渲染出来再克隆去打印，否则印出来是空的。
  await nextTick();
  printElement(
    orderSheetRef.value?.$el || orderSheetRef.value,
    `委外加工单 ${record.orderNo || ''}`,
    { page: '@page{size:A4;margin:12mm}', brandHeader: false }
  );
};

// 计划量：发料单对这颗料的标准用量；产品入库单对整单应产出数量。退料没有计划量。
const plannedQtyFor = (entry, item) => {
  if (entry.purpose === 'OUTSOURCE_RECEIPT') return viewing.value?.qty;
  if (entry.purpose !== 'OUTSOURCE_ISSUE') return null;
  const m = (viewing.value?.outsourceMaterials || []).find(
    x =>
      (item.mesMaterialId && x.mesMaterialId === item.mesMaterialId) ||
      (item.crmProductId && x.crmProductId === item.crmProductId)
  );
  return m?.stdQty;
};

const ENTRY_TITLES = {
  OUTSOURCE_ISSUE: '委外发料单',
  OUTSOURCE_RECEIPT: '委外产品入库单',
  OUTSOURCE_RETURN: '委外退料单',
};
const printEntry = async entry => {
  busy.value = true;
  try {
    const { data } = await MesStockEntryAPI.show(entry.id);
    const full = camelcaseKeys(data?.payload || data || {}, { deep: true });
    printEntryItems.value = (full.stockEntryItems || []).map(it => ({
      materialNo: it.materialNo,
      name: it.materialName || it.productName,
      unit: it.unit,
      qty: it.qty,
      // 「应发/应收」＝计划量：发料对标准用量，入库对整单产出量。
      plannedQty: plannedQtyFor(entry, it),
    }));
    printingEntry.value = { ...entry, remark: full.remark };
    await nextTick();
    printElement(
      entrySheetRef.value?.$el || entrySheetRef.value,
      `${ENTRY_TITLES[entry.purpose] || ''} ${entry.entryNo || ''}`,
      { page: '@page{size:A4;margin:12mm}', brandHeader: false }
    );
  } catch (e) {
    useAlert(e?.response?.data?.error || '取单据明细失败，无法打印');
  } finally {
    busy.value = false;
  }
};

onMounted(() => {
  fetchList();
  warehousesStore.get();
  // 生产任务单页「转委外」跳过来：直接开建单窗，订单下拉已收敛到那张任务单。
  if (route.query.bom_id) openCreate(route.query.bom_id);
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div
      class="flex items-center justify-between px-4 py-3 sm:px-6 sm:py-4 [.theme-classic_&]:sm:!px-8"
    >
      <h1
        class="text-xl font-semibold text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8"
      >
        委外加工
      </h1>
      <div class="flex items-center gap-2">
        <DatePicker
          v-model="fromDate"
          placeholder="建单日起"
          trigger-class="w-32 !h-8"
        />
        <span class="text-sm text-n-slate-10">至</span>
        <DatePicker
          v-model="toDate"
          placeholder="建单日止"
          trigger-class="w-32 !h-8"
        />
        <div class="w-56">
          <Input
            v-model="searchQuery"
            size="sm"
            placeholder="搜索单号、加工厂、产品"
            @keyup.enter="onFilterChange"
          />
        </div>
        <Button
          v-if="canSchedule"
          label="新建"
          size="sm"
          class="shrink-0"
          @click="openCreate()"
        />
      </div>
    </div>

    <div
      class="flex items-center gap-2 px-4 pb-3 sm:px-6 [.theme-classic_&]:sm:!px-8"
    >
      <button
        v-for="f in STATUS_FILTERS"
        :key="f.value"
        type="button"
        class="px-3 py-1 text-sm rounded-md reset-base"
        :class="
          activeStatus === f.value
            ? 'bg-n-slate-12 text-n-slate-1'
            : 'text-n-slate-11 hover:bg-n-alpha-1'
        "
        @click="onStatus(f.value)"
      >
        {{ f.label }}
      </button>
      <span class="ml-auto text-sm text-n-slate-11"
        >共 {{ totalCount }} 条</span
      >
    </div>

    <HScrollButtons />
    <div
      class="flex-1 min-h-0 px-4 overflow-auto sm:px-6 [.theme-classic_&]:sm:!px-8"
    >
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <table v-else class="w-max min-w-full text-sm">
        <thead
          class="text-left text-n-slate-11 [&>tr>th]:sticky [&>tr>th]:top-0 [&>tr>th]:z-10 [&>tr>th]:bg-n-solid-1 [&>tr>th]:border-b [&>tr>th]:border-n-weak"
        >
          <tr>
            <th class="px-3 py-2 font-medium whitespace-nowrap">
              单号
              <MesColumnFilter
                v-model="colFilters[filterOf('no').key]"
                :placeholder="filterOf('no').placeholder"
                @change="onFilterChange"
              />
            </th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">
              加工厂
              <MesColumnFilter
                v-model="colFilters[filterOf('supplier').key]"
                :placeholder="filterOf('supplier').placeholder"
                @change="onFilterChange"
              />
            </th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">
              产出
              <MesColumnFilter
                v-model="colFilters[filterOf('product').key]"
                :placeholder="filterOf('product').placeholder"
                @change="onFilterChange"
              />
            </th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">
              生产订单
              <MesColumnFilter
                v-model="colFilters[filterOf('mo').key]"
                :placeholder="filterOf('mo').placeholder"
                @change="onFilterChange"
              />
            </th>
            <th class="px-3 py-2 font-medium text-right whitespace-nowrap">
              已收 / 应收
            </th>
            <th class="px-3 py-2 font-medium text-right whitespace-nowrap">
              加工费（含税）
            </th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">委外仓</th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">交期</th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">状态</th>
            <th class="px-3 py-2 font-medium text-right whitespace-nowrap">
              操作
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="o in records"
            :key="o.id"
            class="border-b border-n-weak hover:bg-n-alpha-1"
          >
            <td class="px-3 py-3 font-mono whitespace-nowrap text-n-slate-12">
              {{ o.orderNo }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">{{ o.supplierName }}</td>
            <td class="px-3 py-3">
              <div class="text-n-slate-12">{{ o.productName }}</div>
              <div v-if="o.productSku" class="text-xs text-n-slate-10">
                {{ o.productSku }}
              </div>
            </td>
            <td class="px-3 py-3 whitespace-nowrap text-n-slate-11">
              {{ o.productionOrderNo || '—' }}
            </td>
            <td class="px-3 py-3 text-right tabular-nums whitespace-nowrap">
              <span
                :class="
                  num(o.receivedQty) >= num(o.qty)
                    ? 'text-n-teal-11'
                    : 'text-n-slate-12'
                "
              >
                {{ num(o.receivedQty) }}
              </span>
              <span class="text-n-slate-10"> / {{ num(o.qty) }}</span>
              <span class="ml-1 text-xs text-n-slate-10">{{ o.unit }}</span>
            </td>
            <td class="px-3 py-3 text-right tabular-nums whitespace-nowrap">
              {{ money(o.feeRateTaxedMicros) }}
              <span class="text-xs text-n-slate-10">/{{ o.unit || '件' }}</span>
            </td>
            <td class="px-3 py-3 whitespace-nowrap text-n-slate-11">
              {{ o.outsourceWarehouseName || '未指定' }}
            </td>
            <td class="px-3 py-3 whitespace-nowrap text-n-slate-11">
              {{ day(o.deliveryDate) }}
            </td>
            <td class="px-3 py-3">
              <MesStatusPill :label="STATUS_LABELS[o.status]" />
            </td>
            <td class="px-3 py-3 text-right whitespace-nowrap">
              <div class="flex justify-end gap-1">
                <Button
                  label="查看"
                  variant="ghost"
                  size="sm"
                  @click="openView(o)"
                />
                <Button
                  v-if="canSchedule && o.status === 'DRAFT'"
                  label="确认"
                  color="iris"
                  size="sm"
                  :is-loading="busy"
                  @click="confirmOrder(o)"
                />
              </div>
            </td>
          </tr>
          <tr v-if="!records.length">
            <td colspan="10" class="px-3 py-10 text-center text-n-slate-11">
              还没有委外加工单。到生产订单上点「转委外」开单。
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <PaginationFooter
      v-model="currentPage"
      class="sticky bottom-0 z-10"
      :current-page="currentPage"
      :total-items="totalCount"
      :items-per-page="ITEMS_PER_PAGE"
    />

    <!-- 明细：基本信息 + 用料（含已发/已耗/已退/可退）+ 派生单据 -->
    <!-- 新建委外加工单：选一张生产订单，用料从它的 BOM 带出来 -->
    <Dialog
      ref="createDialogRef"
      overflow-y-auto
      :dismissible="false"
      width="2xl"
      confirm-button-color="iris"
      title="新建委外加工单"
      confirm-button-label="建单"
      :is-loading="busy"
      :disable-confirm-button="createInvalid"
      @confirm="submitCreate"
    >
      <div class="flex flex-col gap-4">
        <div>
          <label class="text-label text-n-slate-12">生产订单 *</label>
          <ComboBox
            v-model="form.productionOrderId"
            class="mt-1"
            :options="moOptions"
            :is-loading="loadingOptions"
            placeholder="选择生产订单"
          />
        </div>
        <div>
          <label class="text-label text-n-slate-12">加工厂 *</label>
          <SelectCard
            v-model="form.supplierId"
            class="mt-1"
            :options="supplierOptions"
            placeholder="选择加工厂"
          />
        </div>
        <div class="grid grid-cols-2 gap-4">
          <div>
            <label class="text-label text-n-slate-12">委外仓 *</label>
            <SelectCard
              v-model="form.warehouseId"
              class="mt-1"
              :options="wwWarehouseOptions"
              placeholder="选择委外仓"
            />
          </div>
          <div>
            <label class="text-label text-n-slate-12">产出入库仓</label>
            <SelectCard
              v-model="form.toWarehouseId"
              class="mt-1"
              :options="wwWarehouseOptions"
              placeholder="选择仓库"
            />
          </div>
        </div>
        <div class="grid grid-cols-2 gap-4">
          <div>
            <label class="text-label text-n-slate-12">
              加工费单价（含税）
            </label>
            <Input v-model="form.feeRate" class="mt-1" type="number" />
          </div>
          <div>
            <label class="text-label text-n-slate-12">税率 %</label>
            <Input v-model="form.taxRate" class="mt-1" type="number" />
          </div>
        </div>
      </div>
    </Dialog>

    <Dialog
      ref="viewDialogRef"
      :title="`委外加工单 ${viewing?.orderNo || ''}`"
      width="4xl"
      overflow-y-auto
      :show-confirm-button="false"
      :show-cancel-button="false"
    >
      <div v-if="viewing" class="flex flex-col gap-4">
        <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <div
            v-for="f in [
              { label: '加工厂', value: viewing.supplierName },
              { label: '产出', value: viewing.productName },
              {
                label: '应收 / 已收',
                value: `${num(viewing.qty)} / ${num(viewing.receivedQty)} ${viewing.unit || ''}`,
              },
              {
                label: '加工费（含税）',
                value: money(viewing.feeRateTaxedMicros),
              },
              {
                label: '委外仓',
                value: viewing.outsourceWarehouseName || '未指定',
              },
              {
                label: '产出入库仓',
                value: viewing.toWarehouseName || '未指定',
              },
              { label: '生产订单', value: viewing.productionOrderNo || '—' },
              { label: '交期', value: day(viewing.deliveryDate) },
            ]"
            :key="f.label"
          >
            <div class="text-xs text-n-slate-10">{{ f.label }}</div>
            <div class="text-n-slate-12">{{ f.value }}</div>
          </div>
        </div>

        <div class="flex flex-wrap gap-2">
          <Button
            v-if="canWrite && viewing.status === 'CONFIRMED'"
            label="发料"
            color="iris"
            size="sm"
            :is-loading="busy"
            @click="issueAll(viewing)"
          />
          <Button
            v-if="canWrite && viewing.status === 'CONFIRMED'"
            label="产品入库"
            color="iris"
            size="sm"
            @click="openReceipt"
          />
          <Button
            v-if="canWrite && viewing.status === 'CONFIRMED'"
            label="退料"
            variant="outline"
            size="sm"
            @click="openReturn"
          />
          <Button
            label="生成加工费"
            variant="outline"
            size="sm"
            :is-loading="busy"
            @click="generateFee(viewing)"
          />
          <Button
            label="打印加工单"
            variant="outline"
            size="sm"
            @click="printOrder(viewing)"
          />
          <Button
            v-if="canSchedule && viewing.status !== 'CLOSED'"
            label="关闭"
            color="ruby"
            variant="ghost"
            size="sm"
            :is-loading="busy"
            @click="closeOrder(viewing)"
          />
        </div>

        <div>
          <div class="mb-1 text-heading-3 text-n-slate-12">用料</div>
          <div class="overflow-x-auto border rounded-lg border-n-weak">
            <table class="w-max min-w-full text-sm">
              <thead class="text-left text-n-slate-11 bg-n-alpha-1">
                <tr>
                  <th class="px-3 py-2 font-medium whitespace-nowrap">物料</th>
                  <th class="px-3 py-2 font-medium whitespace-nowrap">单位</th>
                  <th
                    class="px-3 py-2 font-medium text-right whitespace-nowrap"
                  >
                    标准用量
                  </th>
                  <th
                    class="px-3 py-2 font-medium text-right whitespace-nowrap"
                  >
                    已发
                  </th>
                  <th
                    class="px-3 py-2 font-medium text-right whitespace-nowrap"
                  >
                    已耗
                  </th>
                  <th
                    class="px-3 py-2 font-medium text-right whitespace-nowrap"
                  >
                    已退
                  </th>
                  <th
                    class="px-3 py-2 font-medium text-right whitespace-nowrap"
                  >
                    还能退
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="m in viewing.outsourceMaterials || []"
                  :key="m.id"
                  class="border-t border-n-weak"
                >
                  <td class="px-3 py-2">
                    <div class="text-n-slate-12">{{ m.itemName }}</div>
                    <div v-if="m.itemCode" class="text-xs text-n-slate-10">
                      {{ m.itemCode }}
                    </div>
                  </td>
                  <td class="px-3 py-2 text-n-slate-11">{{ m.unit }}</td>
                  <td class="px-3 py-2 text-right tabular-nums">
                    {{ num(m.stdQty) }}
                  </td>
                  <td class="px-3 py-2 text-right tabular-nums text-n-slate-11">
                    {{ num(m.issuedQty) }}
                  </td>
                  <td class="px-3 py-2 text-right tabular-nums text-n-slate-11">
                    {{ num(m.backflushedQty) }}
                  </td>
                  <td class="px-3 py-2 text-right tabular-nums text-n-slate-11">
                    {{ num(m.returnedQty) }}
                  </td>
                  <td class="px-3 py-2 text-right tabular-nums text-n-slate-12">
                    {{ num(m.returnableQty) }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div>
          <div class="mb-1 text-heading-3 text-n-slate-12">单据</div>
          <div class="overflow-x-auto border rounded-lg border-n-weak">
            <table class="w-max min-w-full text-sm">
              <thead class="text-left text-n-slate-11 bg-n-alpha-1">
                <tr>
                  <th class="px-3 py-2 font-medium whitespace-nowrap">类型</th>
                  <th class="px-3 py-2 font-medium whitespace-nowrap">单号</th>
                  <th
                    class="px-3 py-2 font-medium text-right whitespace-nowrap"
                  >
                    数量
                  </th>
                  <th class="px-3 py-2 font-medium whitespace-nowrap">状态</th>
                  <th class="px-3 py-2 font-medium whitespace-nowrap">
                    过账时间
                  </th>
                  <th
                    class="px-3 py-2 font-medium text-right whitespace-nowrap"
                  >
                    操作
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="e in viewing.stockEntries || []"
                  :key="e.id"
                  class="border-t border-n-weak"
                >
                  <td class="px-3 py-2 whitespace-nowrap text-n-slate-12">
                    {{ PURPOSE_LABELS[e.purpose] || e.purpose }}
                  </td>
                  <td class="px-3 py-2 font-mono whitespace-nowrap">
                    {{ e.entryNo }}
                  </td>
                  <td class="px-3 py-2 text-right tabular-nums text-n-slate-11">
                    {{ num(e.totalQty) }}
                    <span class="text-xs text-n-slate-10">
                      {{
                        e.backflushLineCount
                          ? `(倒冲 ${e.backflushLineCount} 行)`
                          : `(${e.lineCount} 行)`
                      }}
                    </span>
                  </td>
                  <td class="px-3 py-2 whitespace-nowrap">
                    <MesStatusPill :label="ENTRY_STATUS_LABELS[e.status]" />
                  </td>
                  <td class="px-3 py-2 whitespace-nowrap text-n-slate-11">
                    {{ day(e.postedAt) }}
                  </td>
                  <td class="px-3 py-2 text-right whitespace-nowrap">
                    <Button
                      v-if="canWrite && e.status === 'DRAFT'"
                      label="过账"
                      color="iris"
                      size="xs"
                      :is-loading="busy"
                      @click="postEntry(e)"
                    />
                    <Button
                      label="打印"
                      variant="ghost"
                      size="xs"
                      :is-loading="busy"
                      @click="printEntry(e)"
                    />
                    <Button
                      v-if="canWrite && e.status === 'POSTED'"
                      label="作废"
                      color="ruby"
                      variant="ghost"
                      size="xs"
                      :is-loading="busy"
                      @click="cancelEntry(e)"
                    />
                  </td>
                </tr>
                <tr v-if="!(viewing.stockEntries || []).length">
                  <td colspan="6" class="px-3 py-6 text-center text-n-slate-11">
                    还没有发料/入库/退料单
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </Dialog>

    <!-- 票面：只在打印时渲染，平时不占版面（printElement 克隆它去打印）。 -->
    <div
      v-if="printingOrder"
      aria-hidden="true"
      class="fixed -left-[9999px] top-0 w-[760px]"
    >
      <MesOutsourceOrderPrintSheet
        ref="orderSheetRef"
        :record="printingOrder"
        :materials="printingOrder.outsourceMaterials || []"
      />
    </div>
    <div
      v-if="printingEntry && viewing"
      aria-hidden="true"
      class="fixed -left-[9999px] top-0 w-[760px]"
    >
      <MesOutsourceEntryPrintSheet
        ref="entrySheetRef"
        :entry="printingEntry"
        :order="viewing"
        :items="printEntryItems"
        :warehouse-name="warehouseName"
      />
    </div>

    <!-- 产品入库：填这次实收多少台，后端按它倒冲委外仓的料 -->
    <Dialog
      ref="receiptDialogRef"
      overflow-y-auto
      title="委外产品入库"
      confirm-button-label="生成入库单"
      :is-loading="busy"
      :disable-confirm-button="receiptInvalid"
      @confirm="submitReceipt"
    >
      <div class="flex flex-col gap-3">
        <div>
          <label class="block mb-1 text-label text-n-slate-12">
            入库数量（还差 {{ num(viewing?.remainingQty) }}）
          </label>
          <Input v-model="receiptForm.qty" type="number" />
        </div>
        <div>
          <label class="block mb-1 text-label text-n-slate-12">入哪个仓</label>
          <SelectCard
            v-model="receiptForm.warehouseId"
            :options="warehouseOptions"
          />
        </div>
      </div>
    </Dialog>

    <!-- 退料：只列加工厂手上还剩得下的料（已发 − 已耗 − 已退） -->
    <Dialog
      ref="returnDialogRef"
      overflow-y-auto
      title="委外退料"
      confirm-button-label="生成退料单"
      :is-loading="busy"
      :disable-confirm-button="returnInvalid"
      @confirm="submitReturn"
    >
      <div class="flex flex-col gap-3">
        <div>
          <label class="block mb-1 text-label text-n-slate-12"
            >退回哪个仓</label
          >
          <SelectCard
            v-model="returnForm.warehouseId"
            :options="warehouseOptions"
          />
        </div>
        <div
          v-for="row in returnForm.rows"
          :key="row.materialId"
          class="flex items-center gap-2"
        >
          <span class="flex-1 text-sm truncate text-n-slate-12">
            {{ row.name }}
          </span>
          <span class="text-xs text-n-slate-10 whitespace-nowrap">
            最多 {{ row.max }} {{ row.unit }}
          </span>
          <div class="w-28">
            <Input v-model="row.qty" type="number" size="sm" />
          </div>
        </div>
        <div
          v-if="!returnForm.rows.length"
          class="py-4 text-sm text-center text-n-slate-11"
        >
          加工厂手上没有可退的料了
        </div>
      </div>
    </Dialog>
  </div>
</template>
