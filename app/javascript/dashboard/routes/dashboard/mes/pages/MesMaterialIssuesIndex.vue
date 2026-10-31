<script setup>
/* global axios */
import { ref, computed, reactive, onMounted, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesStockEntriesStore } from 'dashboard/stores/mes/stockEntries';
import { useMesWarehousesStore } from 'dashboard/stores/mes/warehouses';
import MesProductionOrderAPI from 'dashboard/api/mes/productionOrders';

import Button from 'dashboard/components-next/button/Button.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import MesBoardOwnerBar from 'dashboard/components-next/mes/MesBoardOwnerBar.vue';
import { useMesRole } from 'dashboard/composables/useMesRole';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import MesProductPicker from 'dashboard/components-next/mes/MesProductPicker.vue';
import MesViewDialog from 'dashboard/components-next/mes/MesViewDialog.vue';
import MesMaterialIssuePrintSheet from 'dashboard/components-next/mes/MesMaterialIssuePrintSheet.vue';
import { printElement } from 'dashboard/helper/printHelper';
import MesReturnControls from 'dashboard/components-next/mes/MesReturnControls.vue';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';
import { useMesDocOwner } from 'dashboard/composables/useMesDocOwner';
import { orderSearchText } from 'dashboard/routes/dashboard/mes/orderSearchText';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import MesStatusPill from 'dashboard/components-next/mes/MesStatusPill.vue';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
const { accountId } = useAccount();
const store = useMesStockEntriesStore();
const { mesCan } = useMesRole();
const { isMyDoc } = useMesDocOwner();
// 建领料单生产岗也能做：生产提领料、仓管过账发料——后端
// Mes::StockEntryPolicy#create? 就是 `stock || report`，前端这里原来只判 stock，
// 于是生产岗（能力只有 report/quality）在这页看不到任何按钮，后端却是放行的。
// ⚠️ 这页其余按钮（过账/退单）是仓储动作，后端只给 stock，别跟着一起放开。
const canCreateIssue = computed(() => mesCan('stock') || mesCan('report'));

// 删单/作废两档：
// · 仓管：草稿硬删，已过账走「作废」冲销退库存。
// · 生产岗：只能删**自己开的草稿**。开错一张要去求仓管删，车间等不起（2026-10-28 反馈）。
//   口径和后端一致：ensure_can_delete! 卡制单人（owner_id 就是制单人），
//   destroy 再挡住已过账的单——前端放宽一点就会出现「按钮点了吃 403」。
const canRemoveIssue = e =>
  e.status !== 'CANCELLED' &&
  (mesCan('stock') || (e.status === 'DRAFT' && isMyDoc(e)));
const warehousesStore = useMesWarehousesStore();

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const saving = computed(() => store.getUIFlags.creatingItem);
const posting = computed(() => store.getUIFlags.updatingItem);
const day = d => (d ? new Date(d).toLocaleDateString() : '—');
const STATUS_LABELS = { DRAFT: '草稿', POSTED: '已过账', CANCELLED: '已作废' };

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
    { label: '型号', value: e.productName },
    { label: '归属人', value: e.productionOrderOwnerName },
    { label: '领料仓', value: whName(e.fromWarehouseId) },
    { label: '状态', value: STATUS_LABELS[e.status] || e.status },
    { label: '过账时间', value: day(e.postedAt) },
    { label: '制单人', value: e.ownerName },
    { label: '备注', value: e.remark },
  ];
});
// 领料单票面（1:1 对标旧系统那张）：A4 纵向激光打印，不是三联纸，也不加 Wintouch 字标。
const printSheetRef = ref(null);
const printRows = computed(() =>
  (viewing.value?.stockEntryItems || []).map(it => ({
    materialNo: it.materialNo,
    name: it.materialName || it.productName,
    spec: it.specification,
    qty: it.receivedQty ?? it.qty,
    unit: it.unit,
    warehouse: whName(it.warehouseId || viewing.value?.fromWarehouseId),
    remark: it.remark,
  }))
);
const printIssue = () =>
  printElement(
    printSheetRef.value?.$el || printSheetRef.value,
    `生产领料单 ${viewing.value?.entryNo || ''}`,
    { page: '@page{size:A4;margin:12mm}', brandHeader: false }
  );

const VIEW_ITEM_COLS = [
  { label: '物料编码', key: 'materialNo' },
  { label: '物料名称', key: 'name' },
  { label: '领用量', key: 'qty', align: 'right' },
  { label: '单位', key: 'unit' },
];
const viewItems = computed(() =>
  (viewing.value?.stockEntryItems || []).map(it => ({
    materialNo: it.materialNo,
    name: it.materialName || it.productName,
    qty: it.qty,
    unit: it.unit,
  }))
);

// 后端每页 15 条，不传 page 就只看得到最新 15 张（生产上 20 张领料单，5 张看不见）。
const ITEMS_PER_PAGE = 15;
const currentPage = ref(1);
const totalCount = computed(() => store.getMeta?.count || 0);
// 一个框搜多处（后端 Mes 入库单那套 SEARCH_SQL）：领料单号 / 工单号 / 成品名 / 物料编码 / 品名。
const searchQuery = ref('');
const fetchList = () =>
  store.get({
    purpose: 'MATERIAL_ISSUE',
    page: currentPage.value,
    q: searchQuery.value.trim() || undefined,
  });
const onSearch = () => {
  currentPage.value = 1;
  fetchList();
};
watch(currentPage, fetchList);

const productionOrders = ref([]);
// 流程锁：生产领料只对「自制且原料已入库（进入原料入库/领料/生产及以后）」的订单开单。
// 外购订单不领料、原料未入库的订单不可越级领料——都不出现在可选项里。
const ISSUE_ELIGIBLE_STAGES = [
  'MATERIAL_INBOUND',
  'PICKING',
  'PRODUCTION',
  'FG_INBOUND',
];
const eligibleOrders = computed(() =>
  productionOrders.value.filter(
    // 字段是 is_outsourced（裸 axios 取数，不走 camelcaseKeys）。
    // 原先写成 p.isOutsourced 恒为 undefined，「委外不领料」这条过滤从来没生效，
    // 生产上 6 张可选订单里 4 张是委外单。
    p => !p.is_outsourced && ISSUE_ELIGIBLE_STAGES.includes(p.stage)
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
const warehouseOptions = computed(() =>
  (warehousesStore.getRecords || []).map(w => ({
    value: String(w.id),
    label: w.name,
  }))
);
// 领料物料从「产品档案」(crm_products) 搜索选（不允许手输，防料号打错）；保留已选项标签。
const productOptions = ref([]);
const mergeProductOptions = list => {
  const seen = new Set(productOptions.value.map(o => o.value));
  list.forEach(o => {
    if (o.value && !seen.has(o.value)) {
      productOptions.value.push(o);
      seen.add(o.value);
    }
  });
};
const productLabel = id =>
  productOptions.value.find(o => o.value === String(id))?.label || '';
const onProductPicked = p =>
  mergeProductOptions([
    {
      value: String(p.id),
      label: `${p.name}${p.sku ? `（${p.sku}）` : ''}`,
      unit: p.unit || '',
    },
  ]);

const dialogRef = ref(null);
const form = reactive({
  productionOrderId: '',
  warehouseId: '',
  rows: [], // { crmProductId, qty }
});
const { isDirty, markPristine } = useDirtyGuard(() => form);
const invalid = computed(
  () =>
    !form.warehouseId ||
    !form.rows.length ||
    form.rows.some(r => !r.crmProductId || !Number(r.qty))
);

const blankIssueRow = () => ({
  crmProductId: '',
  materialNo: '',
  onHand: null,
  issuedQty: null,
  pendingQty: null,
  qty: '1',
});
const addRow = () => form.rows.push(blankIssueRow());
const removeRow = i => form.rows.splice(i, 1);

// 按选中生产订单的 BOM 推料 + 带出每行「物料编码 / 实时库存 / 已领 / 待领」。
// BOM 折算口径：订单量 / 基准量 = 倍数。
// 基准量和明细用量口径填拧了（基准量 3、明细按整单 300 填），倍数会变成 100，
// 推出来的数看着像真的——2026-10-14 就推出过一台机器要 100 片屏、整单 30000。
// 所以把倍数和每台用量直接摆在界面上，填错一眼看得见。
const planMeta = ref(null);
const SCALE_WARNING =
  '　倍数不是 1，先回 BOM 核对「基准产量」和每行用量是不是同一个口径，否则领料量会整体放大。';
const scaleNote = computed(() => {
  const m = planMeta.value;
  if (!m || !m.factor) return '';
  const factor = Number(m.factor);
  const tidy = Number.isInteger(factor) ? factor : factor.toFixed(3);
  return `${m.bom_no || 'BOM'} 基准 ${m.bom_base_qty} → 本单 ${m.order_qty}，用量按 ×${tidy} 折算`;
});
// 倍数不是 1 就提醒核对：正常情况下 BOM 基准量就按本单数量做，倍数应当是 1。
const scaleSuspicious = computed(() => {
  const f = Number(planMeta.value?.factor);
  return Number.isFinite(f) && f !== 1;
});

const pushFromBom = async () => {
  if (!form.productionOrderId) {
    useAlert('请先选销售订单');
    return;
  }
  try {
    const { data } = await MesProductionOrderAPI.issuePlan(
      form.productionOrderId,
      form.warehouseId || undefined
    );
    const reqs = data?.payload || [];
    planMeta.value = data?.meta || null;
    if (!reqs.length) {
      useAlert('该销售订单未挂生产任务单或无用料');
      return;
    }
    // 已匹配产品的行并入显示标签(料名·料号)，让选择器显示已带出的产品；未匹配的留空待人工搜选。
    mergeProductOptions(
      reqs
        .filter(r => r.crm_product_id)
        .map(r => ({
          value: String(r.crm_product_id),
          label: `${r.material_name || ''}${r.material_no ? `（${r.material_no}）` : ''}`,
          unit: r.unit || '',
        }))
    );
    // 待领量预填领料量（不足库存时人工调整）；同时记编码/实时库存/已领供行内展示。
    form.rows = reqs.map(r => ({
      crmProductId: r.crm_product_id ? String(r.crm_product_id) : '',
      materialNo: r.material_no || '',
      onHand: Number(r.on_hand || 0),
      issuedQty: Number(r.issued_qty || 0),
      pendingQty: Number(r.pending_qty || 0),
      perUnitQty: r.per_unit_qty == null ? null : Number(r.per_unit_qty),
      qty: String(r.pending_qty ?? r.qty),
    }));
    const unmatched = reqs.filter(r => !r.crm_product_id).length;
    if (unmatched) {
      useAlert(`已推料；${unmatched} 项料号在产品档案未匹配，请手动搜索选择`);
    }
  } catch {
    useAlert('推料失败');
  }
};

// 编辑复用同一个弹窗：editId 为空＝新建，有值＝改这张草稿。
// 只有草稿能改——已过账的单写了不可改的库存流水，要撤得走「作废」冲销。
const editId = ref(null);

const openCreate = () => {
  const raw = (warehousesStore.getRecords || []).find(w => w.kind === 'RAW');
  editId.value = null;
  planMeta.value = null;
  Object.assign(form, {
    productionOrderId: '',
    warehouseId: raw ? String(raw.id) : '',
    rows: [blankIssueRow()],
  });
  markPristine();
  dialogRef.value?.open();
};

const openEdit = e => {
  editId.value = e.id;
  planMeta.value = null;
  const items = e.stockEntryItems || [];
  // 下拉要能显示已选中的料名，先把行上的商品并进选项池（同推料那条路）。
  mergeProductOptions(
    items
      .filter(it => it.crmProductId)
      .map(it => ({
        value: String(it.crmProductId),
        label: `${it.materialName || it.productName || ''}${
          it.materialNo ? `（${it.materialNo}）` : ''
        }`,
        unit: it.unit || '',
      }))
  );
  Object.assign(form, {
    productionOrderId: e.productionOrderId ? String(e.productionOrderId) : '',
    warehouseId: String(e.fromWarehouseId || ''),
    rows: items.length
      ? items.map(it => ({
          // 带上行 id，后端按 id 更新而不是整组重建（重建会丢掉行内附图）。
          id: it.id,
          crmProductId: it.crmProductId ? String(it.crmProductId) : '',
          materialNo: it.materialNo || '',
          onHand: 0,
          issuedQty: 0,
          pendingQty: 0,
          perUnitQty: null,
          qty: String(it.qty ?? ''),
        }))
      : [blankIssueRow()],
  });
  markPristine();
  dialogRef.value?.open();
};

const submit = async () => {
  if (invalid.value) return;
  const payload = {
    purpose: 'MATERIAL_ISSUE',
    productionOrderId: form.productionOrderId || null,
    fromWarehouseId: Number(form.warehouseId),
    stockEntryItemsAttributes: form.rows.map(r => ({
      // 改单时带上行 id：后端 accepts_nested_attributes_for 按 id 更新，不带就是新增一行。
      ...(r.id ? { id: r.id } : {}),
      // 领料领的是原料仓的采购件，与「采购收货入库」记的是同一批结存，
      // item_type 必须同为 MATERIAL；记成 PRODUCT 会另起一个结存桶导致过账查不到库存。
      itemType: 'MATERIAL',
      crmProductId: Number(r.crmProductId),
      qty: Number(r.qty),
      warehouseId: Number(form.warehouseId),
    })),
  };
  try {
    if (editId.value) {
      const ok = await store.update({ id: editId.value, ...payload });
      if (ok) {
        useAlert(`领料单 ${ok.entryNo} 已保存`);
        dialogRef.value?.close();
      }
      return;
    }
    const ok = await store.create(payload);
    if (ok) {
      useAlert(`已建领料单 ${ok.entryNo}，待过账`);
      dialogRef.value?.close();
    }
  } catch (error) {
    useAlert(error.message || (editId.value ? '保存失败' : '建单失败'));
  }
};

const postEntry = async entry => {
  try {
    const ok = await store.post(entry.id);
    if (ok) useAlert(`${ok.entryNo} 已过账，库存已扣减`);
  } catch (error) {
    useAlert(error.message || '过账失败');
  }
};

// 删单：草稿直接删除；已过账走「作废」冲销（退回已扣库存、按需回退生产订单阶段，保留单据可追溯）。
const removeEntry = async e => {
  if (e.status === 'POSTED') {
    // eslint-disable-next-line no-alert
    if (
      !window.confirm(
        `确定作废领料单 ${e.entryNo}？已领出的物料会退回库存，生产订单阶段按需回退。`
      )
    ) {
      return;
    }
    try {
      const ok = await store.cancel(e.id);
      if (ok) useAlert(`${e.entryNo} 已作废，库存已退回`);
    } catch (error) {
      useAlert(error.message || '作废失败');
    }
  } else {
    // eslint-disable-next-line no-alert
    if (!window.confirm(`确定删除领料单 ${e.entryNo}？删除后不可恢复。`))
      return;
    try {
      const ok = await store.delete(e.id);
      if (ok) useAlert('已删除');
    } catch (error) {
      useAlert(error.message || '删除失败');
    }
  }
};

onMounted(async () => {
  fetchList();
  warehousesStore.get();
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/production_orders`,
      // 同上:不传 per_page 只给最新 15 条,早的单子选不到。
      { params: { per_page: 500 } }
    );
    productionOrders.value = data?.payload || [];
  } catch {
    productionOrders.value = [];
  }
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
        生产领料
      </h1>
      <div class="w-64 ms-auto me-2">
        <Input
          v-model="searchQuery"
          size="sm"
          placeholder="搜领料单号 / 工单号 / 物料编码"
          @keyup.enter="onSearch"
        />
      </div>
      <Button
        v-if="canCreateIssue"
        label="新建领料单"
        color="iris"
        size="sm"
        @click="openCreate"
      />
    </div>

    <MesBoardOwnerBar board-key="mes_material_issues_index" />

    <HScrollButtons />
    <div
      class="flex-1 min-h-0 px-4 overflow-auto sm:px-6 [.theme-classic_&]:sm:!px-8"
    >
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
              <span class="font-medium truncate text-n-slate-12">
                {{ e.entryNo }}
              </span>
              <MesStatusPill
                class="shrink-0"
                :label="STATUS_LABELS[e.status]"
              />
              <span class="flex-1" />
              <div class="flex items-center gap-1 shrink-0">
                <!-- 能不能动这张单由后端逐条下发（canOperate）：仓管全线通吃，
                     本产线本板块的负责人也算。按 mesCan('stock') 藏按钮的话，
                     平板车间的杨义建得出单却看不到「过账」，单子永远停在草稿。 -->
                <Button
                  v-if="e.status === 'DRAFT' && e.canOperate"
                  label="编辑"
                  variant="faded"
                  size="sm"
                  @click.stop="openEdit(e)"
                />
                <Button
                  v-if="e.status === 'DRAFT' && e.canOperate"
                  label="过账"
                  color="iris"
                  size="sm"
                  :is-loading="posting"
                  @click.stop="postEntry(e)"
                />
                <MesReturnControls
                  :record="e"
                  :store="store"
                  :can-manage="e.canOperate"
                  @click.stop
                />
                <Button
                  v-if="canRemoveIssue(e)"
                  :label="e.status === 'POSTED' ? '作废' : '删单'"
                  color="ruby"
                  variant="ghost"
                  size="sm"
                  :is-loading="posting"
                  @click.stop="removeEntry(e)"
                />
              </div>
            </div>
            <div class="mt-1 text-xs text-n-slate-11">
              生产订单：{{ e.productionOrderNo || '—' }}
            </div>
            <div class="mt-1 text-xs text-n-slate-11">
              型号：{{ e.productName || '—' }}
            </div>
            <div class="flex gap-3 mt-1 text-xs text-n-slate-11">
              <span>归属人：{{ e.productionOrderOwnerName || '—' }}</span>
              <span>过账时间：{{ day(e.postedAt) }}</span>
            </div>
          </div>
          <div v-if="!records.length" class="py-10 text-center text-n-slate-11">
            还没有领料单。
          </div>
        </div>
        <table class="hidden w-full text-sm md:table">
          <thead>
            <tr class="text-left text-n-slate-11 border-b border-n-weak">
              <th class="px-3 py-3 font-medium whitespace-nowrap">单号</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">销售订单</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">型号</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">归属人</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">状态</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">过账时间</th>
              <th class="px-3 py-3" />
            </tr>
          </thead>
          <tbody>
            <tr v-for="e in records" :key="e.id" class="border-b border-n-weak">
              <td class="px-3 py-3 font-medium text-n-slate-12">
                {{ e.entryNo }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ e.productionOrderNo || '—' }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ e.productName || '—' }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ e.productionOrderOwnerName || '—' }}
              </td>
              <td class="px-3 py-3">
                <MesStatusPill :label="STATUS_LABELS[e.status]" />
              </td>
              <td class="px-3 py-3 text-n-slate-11">{{ day(e.postedAt) }}</td>
              <td class="px-3 py-3 text-right">
                <div class="flex justify-end gap-1">
                  <Button
                    label="查看"
                    variant="ghost"
                    size="sm"
                    @click="openView(e)"
                  />
                  <!-- 和手机卡片同口径：能不能动这张单看后端逐条下发的 canOperate，
                       不是 mesCan('stock')。卡仓管权限的话，平板车间的杨义建得出单
                       却看不到「编辑」和「过账」，单子永远停在草稿（2026-10-29 反馈）。 -->
                  <Button
                    v-if="e.status === 'DRAFT' && e.canOperate"
                    label="编辑"
                    variant="faded"
                    size="sm"
                    @click="openEdit(e)"
                  />
                  <Button
                    v-if="e.status === 'DRAFT' && e.canOperate"
                    label="过账"
                    color="iris"
                    size="sm"
                    :is-loading="posting"
                    @click="postEntry(e)"
                  />
                  <MesReturnControls
                    :record="e"
                    :store="store"
                    :can-manage="e.canOperate"
                  />
                  <Button
                    v-if="canRemoveIssue(e)"
                    :label="e.status === 'POSTED' ? '作废' : '删单'"
                    color="ruby"
                    variant="ghost"
                    size="sm"
                    :is-loading="posting"
                    @click="removeEntry(e)"
                  />
                </div>
              </td>
            </tr>
            <tr v-if="!records.length">
              <td colspan="6" class="px-3 py-10 text-center text-n-slate-11">
                还没有领料单。
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
      width="5xl"
      overflow-y-auto
      confirm-button-color="iris"
      :title="editId ? '编辑生产领料单' : '新建生产领料单'"
      description="过账后扣减原料仓库存"
      :is-loading="saving"
      :disable-confirm-button="invalid"
      :dirty="isDirty"
      dirty-save-label="保存"
      @confirm="submit"
      @close="markPristine"
      @save="submit"
    >
      <div class="flex flex-col gap-4">
        <div class="flex items-end gap-2">
          <div class="flex flex-col flex-1 gap-1">
            <label class="text-heading-3 text-n-slate-12">
              生产订单 <span class="text-n-ruby-11">*</span>
            </label>
            <ComboBox
              :model-value="form.productionOrderId"
              :options="productionOrderOptions"
              placeholder="选择销售订单…"
              search-placeholder="搜 MO 号 / 产品 / 销售订单 / 客户"
              empty-state="没有可领料的生产订单"
              @update:model-value="v => (form.productionOrderId = v)"
            />
          </div>
          <Button
            label="按生产任务单推料"
            type="button"
            color="slate"
            size="sm"
            class="!h-9"
            @click="pushFromBom"
          />
        </div>

        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">领料仓库</label>
          <SelectCard
            block
            :model-value="form.warehouseId"
            :options="warehouseOptions"
            @update:model-value="v => (form.warehouseId = v)"
          />
        </div>

        <!-- 折算口径：正常 BOM 基准量就按本单数量做，倍数应当是 1。
             不是 1 就说明基准量和明细用量的口径对不上，推出来的量会整体放大/缩小。 -->
        <div
          v-if="scaleNote"
          class="flex items-start gap-1.5 px-3 py-2 text-xs rounded-lg"
          :class="
            scaleSuspicious
              ? 'text-n-ruby-12 bg-n-ruby-3'
              : 'text-n-slate-11 bg-n-alpha-1'
          "
        >
          <span
            class="mt-0.5 shrink-0 size-3.5"
            :class="
              scaleSuspicious ? 'i-lucide-triangle-alert' : 'i-lucide-info'
            "
          />
          <span class="leading-relaxed">
            {{ scaleNote }}
            <span v-if="scaleSuspicious">{{ SCALE_WARNING }}</span>
          </span>
        </div>

        <div class="flex items-center justify-between">
          <span class="text-heading-2 text-n-slate-12">
            领料明细 <span class="text-n-ruby-11">*</span>
          </span>
          <Button
            label="+ 加一行"
            type="button"
            variant="ghost"
            size="sm"
            @click="addRow"
          />
        </div>
        <div class="flex flex-col gap-2">
          <div
            v-for="(row, i) in form.rows"
            :key="i"
            class="flex flex-col gap-1 p-2 border rounded-lg border-n-weak"
          >
            <div class="grid items-center grid-cols-12 gap-2">
              <div class="col-span-8">
                <MesProductPicker
                  materials-only
                  :account-id="accountId"
                  :model-value="row.crmProductId"
                  :display-text="productLabel(row.crmProductId)"
                  placeholder="选择物料"
                  @update:model-value="v => (row.crmProductId = v)"
                  @select="onProductPicked"
                />
              </div>
              <Input
                v-model="row.qty"
                type="number"
                placeholder="领用量"
                class="col-span-3"
              />
              <button
                type="button"
                class="col-span-1 text-n-slate-10 hover:text-n-ruby-11"
                @click="removeRow(i)"
              >
                ✕
              </button>
            </div>
            <!-- 按 BOM 推料后每行带出：物料编码 / 实时库存 / 已领 / 待领 -->
            <div
              v-if="row.materialNo || row.onHand !== null"
              class="flex flex-wrap gap-x-4 gap-y-0.5 pl-1 text-xs text-n-slate-10"
            >
              <span v-if="row.materialNo">编码：{{ row.materialNo }}</span>
              <span>
                实时库存：
                <span
                  :class="
                    Number(row.qty) > Number(row.onHand || 0)
                      ? 'text-n-ruby-11 font-medium'
                      : 'text-n-slate-11'
                  "
                >
                  {{ row.onHand ?? '—' }}
                </span>
              </span>
              <span>已领：{{ row.issuedQty ?? '—' }}</span>
              <span>待领：{{ row.pendingQty ?? '—' }}</span>
              <!-- 每台用量：口径填拧了（一台机器 100 片屏）在这一眼就看得出来 -->
              <span v-if="row.perUnitQty != null">
                每台：{{ row.perUnitQty }}
              </span>
              <span
                v-if="
                  row.onHand !== null && Number(row.qty) > Number(row.onHand)
                "
                class="text-n-ruby-11"
              >
                ⚠ 领用量超过库存
              </span>
            </div>
          </div>
        </div>
      </div>
    </Dialog>

    <MesViewDialog
      ref="viewDialogRef"
      :title="viewing ? `领料单 ${viewing.entryNo}` : '领料单明细'"
      hide-print
      :fields="viewFields"
      items-title="领料明细"
      :item-columns="VIEW_ITEM_COLS"
      :items="viewItems"
    >
      <template #headerActions>
        <Button
          label="打印领料单"
          variant="outline"
          color="slate"
          size="sm"
          @click="printIssue"
        />
      </template>
    </MesViewDialog>

    <!-- 领料单票面：只在打印时用，平时不占版面（printElement 克隆它去打印）。 -->
    <div
      v-if="viewing"
      aria-hidden="true"
      class="fixed -left-[9999px] top-0 w-[760px]"
    >
      <MesMaterialIssuePrintSheet
        ref="printSheetRef"
        :entry="viewing"
        :items="printRows"
      />
    </div>
  </div>
</template>
