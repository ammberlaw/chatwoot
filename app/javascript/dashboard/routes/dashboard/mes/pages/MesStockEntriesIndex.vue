<script setup>
/* global axios */
import { ref, computed, reactive, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesStockEntriesStore } from 'dashboard/stores/mes/stockEntries';
import { fmtMoney } from 'dashboard/helper/erpMoney';
import MesStockEntryAPI from 'dashboard/api/mes/stockEntries';
import MesImageLightbox from 'dashboard/components-next/mes/MesImageLightbox.vue';
import { useMesWarehousesStore } from 'dashboard/stores/mes/warehouses';

import Button from 'dashboard/components-next/button/Button.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import MesBoardOwnerBar from 'dashboard/components-next/mes/MesBoardOwnerBar.vue';
import { useMesRole } from 'dashboard/composables/useMesRole';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import MesViewDialog from 'dashboard/components-next/mes/MesViewDialog.vue';
import MesStockEntryPrintSheet from 'dashboard/components-next/mes/MesStockEntryPrintSheet.vue';
import { useListDensity } from 'dashboard/composables/useListDensity';
import { printElement } from 'dashboard/helper/printHelper';
import MesReturnControls from 'dashboard/components-next/mes/MesReturnControls.vue';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';
import { useRouteQueryReentry } from 'dashboard/composables/useRouteQueryReentry';
import MesStatusPill from 'dashboard/components-next/mes/MesStatusPill.vue';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
const { accountId } = useAccount();
const route = useRoute();
const store = useMesStockEntriesStore();
const { mesCan } = useMesRole();
// 行高：宽松/紧凑一键切，记在本机（反馈：间距太长想自己拉短）
const { compact, toggleDensity } = useListDensity();

// 从生产订单「查看入库单」跳转带来的按订单筛选（只看该订单的原料入库单）。
const filterOrderId = ref(route.query.production_order_id || '');
const filterOrderNo = ref(route.query.order_no || '');
// 库存单一表多用：本板块=原料入库，只取 MATERIAL_RECEIPT（生产领料/成品入库各有独立板块）。
// 后端每页 15 条。不传 page 就永远只有最新 15 张，第 16 张往后谁都点不到
// （生产上 44 张入库单，29 张看不见）。
const ITEMS_PER_PAGE = 15;
const currentPage = ref(1);
const totalCount = computed(() => store.getMeta?.count || 0);
const fetchList = () =>
  store.get({
    purpose: 'MATERIAL_RECEIPT',
    page: currentPage.value,
    ...(filterOrderId.value
      ? { production_order_id: filterOrderId.value }
      : {}),
  });
watch(currentPage, fetchList);
// 换筛选要回第 1 页：在第 3 页筛一个只有 2 条结果的条件会看到空列表。
const resetToFirstPage = () => {
  if (currentPage.value === 1) fetchList();
  else currentPage.value = 1;
};
const clearOrderFilter = () => {
  filterOrderId.value = '';
  filterOrderNo.value = '';
  resetToFirstPage();
};
const warehousesStore = useMesWarehousesStore();

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const saving = computed(() => store.getUIFlags.creatingItem);
const posting = computed(() => store.getUIFlags.updatingItem);

const day = d => (d ? new Date(d).toLocaleDateString() : '—');
// 单价/金额是微元；没有值（无权或对不上采购行）留「—」，不要写成 0。
const money = micros => (micros ? fmtMoney(micros) : '—');

// S3 主用原料入库；其余 purpose 留给后续切片。
const PURPOSE_LABELS = {
  MATERIAL_RECEIPT: '原料入库',
  MATERIAL_ISSUE: '生产领料',
  MATERIAL_RETURN: '退料',
  MANUFACTURE: '成品入库',
  SCRAP: '清尾报废',
};
const IN_PURPOSES = ['MATERIAL_RECEIPT', 'MATERIAL_RETURN', 'MANUFACTURE'];
const purposeLabel = p => PURPOSE_LABELS[p] || p;
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
    { label: '类型', value: purposeLabel(e.purpose) },
    { label: '采购单', value: e.purchaseOrderNo },
    // 供应商与对内备注原本只在采购单上，核料时要另开一张单比着看（反馈点名要补）。
    { label: '供应商', value: (e.supplierNames || []).join('、') },
    { label: '生产订单', value: e.productionOrderNo },
    { label: '归属人', value: e.productionOrderOwnerName },
    { label: '入库仓', value: whName(e.toWarehouseId) },
    { label: '状态', value: STATUS_LABELS[e.status] || e.status },
    { label: '过账时间', value: day(e.postedAt) },
    {
      label: '核对',
      value: e.isChecked ? `已核对 · ${e.checkedByName || ''}` : '未核对',
    },
    { label: '收货人', value: e.receivedByName },
    { label: '制单人', value: e.ownerName },
    { label: '备注', value: e.remark },
    { label: '对内备注', value: e.internalRemark },
  ];
});
// 单价/金额只给看得见成本的岗位（采购/财务/管理员/采购审批人）——
// 入库单仓管看得最多，不能顺手把成本漏出去。后端不下发时这两列直接不出。
// 打印用的票面数据（1:1 对标旧系统那张采购入库单）。
// 源单单号＝来源采购单号；仓库按行的入库仓，没有就落到单据的入库仓。
const printSheetRef = ref(null);
const printRows = computed(() =>
  (viewing.value?.stockEntryItems || []).map(it => ({
    sourceNo: viewing.value?.purchaseOrderNo,
    materialNo: it.materialNo,
    name: it.materialName || it.productName,
    spec: it.specification,
    warehouse: whName(it.warehouseId || viewing.value?.toWarehouseId),
    unit: it.unit,
    qty: it.qty,
    receivedQty: it.receivedQty ?? it.qty,
    remark: it.remark,
  }))
);
const printSupplier = computed(() =>
  (viewing.value?.supplierNames || []).join('、')
);
// 套打在 9.5×5.5 英寸三联复写纸上（针式打印机），所以纸张写死、也不加 Wintouch 字标——
// 加了会把版心顶下去，套打直接压到预印格线上。
const TRIPLICATE_PAGE = '@page{size:9.5in 5.5in landscape;margin:8mm}';
const printEntry = () =>
  printElement(
    printSheetRef.value?.$el || printSheetRef.value,
    `采购入库单 ${viewing.value?.entryNo || ''}`,
    { page: TRIPLICATE_PAGE, brandHeader: false }
  );

const VIEW_ITEM_COLS = computed(() => [
  { label: '物料/产品', key: 'name' },
  { label: '编码', key: 'materialNo' },
  { label: '规格型号', key: 'specification', wrap: true },
  { label: '供应商', key: 'supplierName', wrap: true },
  { label: '应收', key: 'qty', align: 'right' },
  { label: '实收', key: 'receivedQty', align: 'right' },
  { label: '单位', key: 'unit' },
  ...(viewing.value?.canViewAmount
    ? [
        { label: '单价', key: 'unitPrice', align: 'right' },
        { label: '金额', key: 'amount', align: 'right' },
      ]
    : []),
  { label: '备注', key: 'remark', wrap: true },
  // 附图跟着自己那一行走（同采购单），点开在页内放大；不进 Excel 导出。
  { label: '附图（仅内部）', key: 'images', type: 'images' },
]);
const viewItems = computed(() =>
  (viewing.value?.stockEntryItems || []).map(it => ({
    name: it.materialName || it.productName,
    materialNo: it.materialNo,
    specification: it.specification,
    supplierName: it.supplierName,
    qty: it.qty,
    receivedQty: it.receivedQty ?? it.qty,
    unit: it.unit,
    unitPrice: money(it.unitPriceMicros),
    amount: money(it.amountMicros),
    remark: it.remark,
    images: it.images || [],
  }))
);

// 列表「入库量」摘要：项数 · 实收合计（一单多料时汇总）。
const entryQtySummary = e => {
  const items = e.stockEntryItems || [];
  if (!items.length) return '—';
  const total = items.reduce(
    (s, it) => s + Number(it.receivedQty ?? it.qty ?? 0),
    0
  );
  return `${items.length}项·${total}`;
};

const warehouseOptions = computed(() =>
  (warehousesStore.getRecords || []).map(w => ({
    value: String(w.id),
    label: w.name,
  }))
);
// 收货行类型：物料（生产用料）/ 成品（外购贸易品到货，入成品库）。
const ITEM_TYPE_OPTIONS = [
  { value: 'MATERIAL', label: '物料' },
  { value: 'PRODUCT', label: '成品(外购)' },
];
const productOptions = ref([]);
const mergeProductOptions = list => {
  const seen = new Set(productOptions.value.map(o => o.value));
  list.forEach(o => {
    if (!seen.has(o.value)) {
      productOptions.value.push(o);
      seen.add(o.value);
    }
  });
};
const loadProducts = async (q = '') => {
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/products`,
      // 产品档案近 5000 条,靠 q 搜索收窄;per_page 取后端上限 100,
      // 否则命中多于 15 条时后面的直接看不到。
      { params: { filter: 'active', q, per_page: 100 } }
    );
    mergeProductOptions(
      (data?.payload || []).map(p => ({
        value: String(p.id),
        label: `${p.name}${p.sku ? `（${p.sku}）` : ''}`,
        unit: p.unit || '',
      }))
    );
  } catch {
    // 忽略：搜索失败保留现有选项
  }
};
const productUnit = id =>
  productOptions.value.find(o => o.value === String(id))?.unit || '';
const finishedWarehouseId = () =>
  (warehousesStore.getRecords || []).find(w => w.kind === 'FINISHED')?.id;

const purchaseOrders = ref([]);
const purchaseOrderOptions = computed(() => [
  { value: '', label: '不关联采购单' },
  ...purchaseOrders.value.map(p => ({
    value: String(p.id),
    label: `${p.po_no}${p.supplier_name ? ` · ${p.supplier_name}` : ''}`,
    searchText: [p.supplier_name, p.production_order_no]
      .filter(Boolean)
      .join(' '),
  })),
]);

const dialogRef = ref(null);
const form = reactive({
  purpose: 'MATERIAL_RECEIPT',
  warehouseId: '',
  purchaseOrderId: '',
  productionOrderId: '',
  isChecked: false,
  rows: [], // { itemType, mesMaterialId, qty, receivedQty }
});
const { isDirty, markPristine } = useDirtyGuard(() => form);
// 物料/成品统一从产品档案(crm_products)选（mes_materials 已弃用），故都校验 crmProductId。
const rowIncomplete = r => !Number(r.qty) || !r.crmProductId;

const invalid = computed(
  () => !form.warehouseId || !form.rows.length || form.rows.some(rowIncomplete)
);

const addRow = () =>
  form.rows.push({
    itemType: 'MATERIAL',
    crmProductId: '',
    qty: '1',
    receivedQty: '',
    remark: '',
  });
const removeRow = i => form.rows.splice(i, 1);

// 选采购单 → 按其明细预填收货行，实收默认等于采购数量。
const prefillFromPO = async () => {
  if (!form.purchaseOrderId) return;
  const po = purchaseOrders.value.find(
    p => String(p.id) === String(form.purchaseOrderId)
  );
  const items = po?.purchase_items || [];
  if (items.length) {
    form.productionOrderId = po.production_order_id
      ? String(po.production_order_id)
      : '';
    form.rows = items.map(it => ({
      itemType: it.item_type || 'MATERIAL',
      crmProductId: it.crm_product_id ? String(it.crm_product_id) : '',
      qty: String(it.qty),
      receivedQty: String(it.received_qty ? it.qty - it.received_qty : it.qty),
      remark: '',
    }));
    // 物料/成品都从产品档案选，把所有行的产品并入下拉，保证行内直接显示、可改。
    mergeProductOptions(
      items
        .filter(it => it.crm_product_id)
        .map(it => ({
          value: String(it.crm_product_id),
          label: `${it.product_name || ''}${it.product_sku ? `（${it.product_sku}）` : ''}`,
          unit: it.unit || '',
        }))
    );
    // 有外购成品则默认入成品库。
    if (items.some(it => it.item_type === 'PRODUCT')) {
      const fin = finishedWarehouseId();
      if (fin) form.warehouseId = String(fin);
    }
  }
};

const openCreate = () => {
  const raw = (warehousesStore.getRecords || []).find(w => w.kind === 'RAW');
  Object.assign(form, {
    purpose: 'MATERIAL_RECEIPT',
    warehouseId: raw ? String(raw.id) : '',
    purchaseOrderId: '',
    productionOrderId: '',
    isChecked: false,
    rows: [
      {
        itemType: 'MATERIAL',
        crmProductId: '',
        qty: '1',
        receivedQty: '',
        remark: '',
        images: [], // 行内附图（只对内）：收货时拍的实物照/破损照
      },
    ],
  });
  markPristine();
  dialogRef.value?.open();
};

// —— 明细行内部附图 ——
// 收货时对着这颗料拍的实物照/破损照，只给公司内部看。选了就先上传拿 signed_id，
// 随明细一起提交（后端 images= 整组替换）。
const stagingRow = ref(null);
// 点缩略图在页内放大，不另开浏览器标签页
const lightboxRef = ref(null);
const pickRowImages = async (event, row, index) => {
  const list = Array.from(event.target.files || []);
  event.target.value = '';
  if (!list.length) return;

  stagingRow.value = index;
  try {
    const staged = await Promise.all(
      list.map(file => {
        const fd = new FormData();
        fd.append('file', file);
        return MesStockEntryAPI.stageBlob(fd).then(({ data }) => ({
          name: data.filename,
          signedId: data.signed_id,
          url: URL.createObjectURL(file),
        }));
      })
    );
    row.images = [...(row.images || []), ...staged];
  } catch (e) {
    useAlert(
      `上传失败：${e?.response?.data?.error || e?.message || '未知错误'}`
    );
  } finally {
    stagingRow.value = null;
  }
};
const removeRowImage = (row, i) => row.images.splice(i, 1);

const submit = async () => {
  if (invalid.value) return;
  const inbound = IN_PURPOSES.includes(form.purpose);
  const payload = {
    purpose: form.purpose,
    purchaseOrderId: form.purchaseOrderId || null,
    productionOrderId: form.productionOrderId || null,
    toWarehouseId: inbound ? Number(form.warehouseId) : null,
    fromWarehouseId: inbound ? null : Number(form.warehouseId),
    isChecked: form.isChecked,
    stockEntryItemsAttributes: form.rows.map(r => ({
      itemType: r.itemType,
      mesMaterialId: null,
      crmProductId: Number(r.crmProductId),
      unit: productUnit(r.crmProductId) || undefined,
      qty: Number(r.qty),
      receivedQty: Number(r.receivedQty) || Number(r.qty),
      warehouseId: Number(form.warehouseId),
      remark: r.remark || '',
      // 整组替换：给这一行当前应有的完整列表（同采购明细）
      images: (r.images || []).map(img => img.signedId),
    })),
  };
  const ok = await store.create(payload);
  if (ok) {
    useAlert(`已建 ${ok.entryNo}，待过账`);
    dialogRef.value?.close();
  }
};

const postEntry = async entry => {
  const ok = await store.post(entry.id);
  if (!ok) return;
  useAlert(`${ok.entryNo} 已过账，库存已更新`);
  // 应付没同步要单独说——只看到「已过账」，财务那边却少一笔欠款。
  if (ok.erpPayableWarning) useAlert(ok.erpPayableWarning);
};

// 删单：草稿直接删；已过账走「作废」冲销（退回库存，保留单据可追溯）。
// 仓管可删别人建的草稿——重复单往往是仓管清点时才发现的，只许制单人删就成了死锁。
const removeEntry = async e => {
  const posted = e.status === 'POSTED';
  const text = posted
    ? `确定作废入库单 ${e.entryNo}？已入库的数量会从结存冲回。`
    : `确定删除入库单 ${e.entryNo}？删除后不可恢复。`;
  // eslint-disable-next-line no-alert
  if (!window.confirm(text)) return;
  try {
    const ok = posted ? await store.cancel(e.id) : await store.delete(e.id);
    if (ok) useAlert(posted ? '已作废' : '已删除');
  } catch (error) {
    useAlert(error.message || (posted ? '作废失败' : '删除失败'));
  }
};

onMounted(async () => {
  fetchList();
  warehousesStore.get();
  loadProducts('');
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/purchase_orders`,
      // 同上:采购单下拉要能选到全部,不能只给最新 15 张。
      { params: { per_page: 500 } }
    );
    purchaseOrders.value = data?.payload || [];
  } catch {
    purchaseOrders.value = [];
  }
});

// 从生产订单详情「查看入库单」再次进来：本页在 keep-alive 里缓存着，
// onMounted 不会再跑，不补这一道筛选条件就还是上一张订单的。
useRouteQueryReentry(query => {
  filterOrderId.value = query.production_order_id || '';
  filterOrderNo.value = query.order_no || '';
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between px-4 py-3 sm:px-6 sm:py-4 [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:sm:!px-8">
      <h1 class="text-xl font-semibold text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8">原料入库</h1>
      <div class="flex items-center gap-2">
        <Button
          :label="compact ? '宽松行高' : '紧凑行高'"
          variant="ghost"
          color="slate"
          size="sm"
          @click="toggleDensity"
        />
        <Button
          v-if="mesCan('stock')"
          label="新建入库单"
          color="iris"
          size="sm"
          @click="openCreate"
        />
      </div>
    </div>

    <MesBoardOwnerBar board-key="mes_stock_entries_index" />

    <!-- 外购成品收货说明：外购成品到货也在本板块收货入库（选对应采购单会自动入「成品仓」）。 -->
    <div class="px-4 mb-1 sm:px-6 [.theme-classic_&]:sm:!px-8">
      <div
        class="flex items-start gap-2 px-3 py-2 text-xs rounded-lg text-n-iris-12 bg-n-iris-3/70"
      >
        <span class="mt-0.5 shrink-0 i-lucide-info size-3.5 text-n-iris-11" />
        <span class="leading-relaxed">
          <b>外购成品</b>到货也在这里收货：新建入库单 →
          选对应<b>采购单</b>（含「成品(外购)」行）→ 系统自动把入库仓切为<b
            >成品仓</b
          >
          → 过账后即成成品库存，可直接销售出库，无需再开成品入库单。
        </span>
      </div>
    </div>

    <!-- 从生产订单跳来的按订单筛选提示 -->
    <div v-if="filterOrderId" class="flex items-center gap-2 px-4 mb-1 sm:px-6 [.theme-classic_&]:sm:!px-8">
      <span
        class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-full bg-n-iris-3 text-n-iris-11"
      >
        仅显示生产订单 {{ filterOrderNo || filterOrderId }} 的入库单
        <button
          type="button"
          class="i-lucide-x size-3.5 hover:text-n-iris-12"
          @click="clearOrderFilter"
        />
      </span>
    </div>

    <HScrollButtons />
    <div class="flex-1 min-h-0 px-4 pb-4 overflow-auto sm:px-6 sm:pb-6 [.theme-classic_&]:sm:!px-8">
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
              <Button
                v-if="e.status === 'DRAFT' && mesCan('stock')"
                label="过账"
                color="iris"
                size="sm"
                :is-loading="posting"
                @click.stop="postEntry(e)"
              />
            </div>
            <div class="flex flex-wrap gap-3 mt-2 text-xs text-n-slate-11">
              <span>类型：{{ purposeLabel(e.purpose) }}</span>
              <span>采购单：{{ e.purchaseOrderNo || '—' }}</span>
              <span>入库量：{{ entryQtySummary(e) }}</span>
            </div>
            <div class="flex flex-wrap gap-3 mt-1 text-xs text-n-slate-11">
              <span>归属人：{{ e.productionOrderOwnerName || '—' }}</span>
              <span>核对：{{ e.isChecked ? '已核对' : '—' }}</span>
            </div>
            <div class="flex flex-wrap gap-3 mt-1 text-xs text-n-slate-11">
              <span>过账时间：{{ day(e.postedAt) }}</span>
            </div>
            <div class="mt-2" @click.stop>
              <MesReturnControls
                :record="e"
                :store="store"
                :can-manage="mesCan('stock')"
              />
            </div>
          </div>
          <div v-if="!records.length" class="py-10 text-center text-n-slate-11">
            还没有入库单。
          </div>
        </div>
        <table class="hidden w-full text-sm md:table">
          <thead>
            <tr class="text-left text-n-slate-11 border-b border-n-weak">
              <th class="px-3 py-3 font-medium whitespace-nowrap">单号</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">类型</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">采购单</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">入库量</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">归属人</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">核对</th>
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
                {{ purposeLabel(e.purpose) }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ e.purchaseOrderNo || '—' }}
              </td>
              <td class="px-3 py-3 text-n-slate-11 tabular-nums">
                {{ entryQtySummary(e) }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ e.productionOrderOwnerName || '—' }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ e.isChecked ? '已核对' : '—' }}
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
                  <Button
                    v-if="e.status === 'DRAFT' && mesCan('stock')"
                    label="过账"
                    color="iris"
                    size="sm"
                    :is-loading="posting"
                    @click="postEntry(e)"
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
                还没有入库单。
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
        class="!bg-transparent before:!hidden"
        @update:current-page="currentPage = $event"
      />
    </div>

    <Dialog
      ref="dialogRef"
      :dismissible="false"
      width="6xl"
      overflow-y-auto
      confirm-button-color="iris"
      title="新建原料入库单"
      description="原料/外购成品到货收货：可从采购单预填明细（含外购成品，自动入成品仓），核对实收数量后保存，再「过账」刷新库存。"
      :is-loading="saving"
      :disable-confirm-button="invalid"
      :dirty="isDirty"
      dirty-save-label="保存"
      @confirm="submit"
      @close="markPristine"
      @save="submit"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">入库仓库</label>
            <SelectCard
              size="form"
              :model-value="form.warehouseId"
              :options="warehouseOptions"
              @update:model-value="v => (form.warehouseId = v)"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">关联采购单</label>
            <ComboBox
              :model-value="form.purchaseOrderId"
              :options="purchaseOrderOptions"
              placeholder="不关联采购单"
              search-placeholder="搜采购单号 / 供应商"
              empty-state="没有匹配的采购单"
              @update:model-value="v => (form.purchaseOrderId = v)"
            />
            <Button
              v-if="form.purchaseOrderId"
              label="按此采购单预填收货明细"
              type="button"
              color="iris"
              size="sm"
              icon="i-lucide-list-plus"
              class="self-start mt-1 po-prefill-btn"
              @click="prefillFromPO"
            />
          </div>
        </div>

        <label
          class="inline-flex items-center gap-2 cursor-pointer text-heading-3 text-n-slate-12"
        >
          <input v-model="form.isChecked" type="checkbox" class="size-4" />
          已核对物料齐整度
        </label>

        <div class="flex items-center justify-between">
          <span class="text-heading-2 text-n-slate-12">
            收货明细 <span class="text-n-ruby-11">*</span>
          </span>
          <Button
            label="+ 加一行"
            type="button"
            variant="ghost"
            size="sm"
            @click="addRow"
          />
        </div>
        <div class="grid grid-cols-12 gap-2 text-xs text-n-slate-10">
          <span class="col-span-2">类型</span>
          <span class="col-span-3">物料/成品</span>
          <span class="col-span-1">应收</span>
          <span class="col-span-1">实收</span>
          <span class="col-span-2">备注（收货单据号）</span>
          <span class="col-span-2 text-right">附图（仅内部）</span>
        </div>
        <div class="flex flex-col gap-2">
          <div
            v-for="(row, i) in form.rows"
            :key="i"
            class="grid items-center grid-cols-12 gap-2"
          >
            <div class="col-span-2">
              <SelectCard
                size="form"
                :model-value="row.itemType"
                :options="ITEM_TYPE_OPTIONS"
                @update:model-value="v => (row.itemType = v)"
              />
            </div>
            <div class="col-span-3">
              <ComboBox
                v-model="row.crmProductId"
                :options="productOptions"
                use-api-results
                :placeholder="
                  row.itemType === 'PRODUCT' ? '选择外购成品' : '选择物料'
                "
                @search="loadProducts"
              />
            </div>
            <Input v-model="row.qty" type="number" class="col-span-1" />
            <Input
              v-model="row.receivedQty"
              type="number"
              placeholder="同应收"
              class="col-span-1"
            />
            <Input
              v-model="row.remark"
              placeholder="收货单据号/备注"
              class="col-span-2"
            />
            <!-- 行内附图（只对内）：缩略图 + 加图按钮一起靠右，不另起一排。
                 收货时拍的实物照/破损照，对着这颗料存。 -->
            <div
              class="flex flex-wrap items-center justify-end col-span-2 gap-1"
            >
              <div
                v-for="(img, k) in row.images"
                :key="img.signedId"
                class="relative size-9 shrink-0 group"
              >
                <button
                  type="button"
                  :title="img.name"
                  @click="lightboxRef?.open(row.images, k)"
                >
                  <img
                    :src="img.url"
                    :alt="img.name"
                    class="object-contain border rounded size-9 border-n-weak bg-n-alpha-1 hover:opacity-80"
                  />
                </button>
                <button
                  type="button"
                  class="absolute items-center justify-center hidden text-white rounded-full size-4 -top-1 -right-1 bg-n-slate-12/80 group-hover:flex"
                  title="移除这张图"
                  @click="removeRowImage(row, k)"
                >
                  <span class="i-lucide-x size-2.5" />
                </button>
              </div>
              <span v-if="stagingRow === i" class="text-xs text-n-amber-11">
                传中…
              </span>
              <label
                class="inline-flex items-center justify-center border border-dashed rounded cursor-pointer size-9 shrink-0 border-n-weak text-n-slate-10 hover:text-n-slate-12 hover:border-n-slate-8"
                title="加附图（只公司内部看）"
              >
                <span class="i-lucide-image-plus size-4" />
                <input
                  type="file"
                  accept="image/*"
                  multiple
                  class="hidden"
                  @change="e => pickRowImages(e, row, i)"
                />
              </label>
            </div>
            <button
              type="button"
              class="col-span-1 text-n-slate-10 hover:text-n-ruby-11"
              @click="removeRow(i)"
            >
              ✕
            </button>
          </div>
        </div>
      </div>
    </Dialog>

    <MesViewDialog
      ref="viewDialogRef"
      width="7xl"
      hide-print
      :title="viewing ? `入库单 ${viewing.entryNo}` : '入库单明细'"
      :fields="viewFields"
      items-title="收货明细"
      :item-columns="VIEW_ITEM_COLS"
      :items="viewItems"
    >
      <template #headerActions>
        <Button
          label="打印入库单"
          variant="outline"
          color="slate"
          size="sm"
          @click="printEntry"
        />
      </template>
    </MesViewDialog>

    <!-- 入库单票面：只在打印时用，平时不占版面（printElement 克隆它去打印）。 -->
    <div
      v-if="viewing"
      aria-hidden="true"
      class="fixed -left-[9999px] top-0 w-[1000px]"
    >
      <MesStockEntryPrintSheet
        ref="printSheetRef"
        :entry="viewing"
        :items="printRows"
        :supplier="printSupplier"
      />
    </div>

    <!-- 看图层：就地渲染，跟弹窗一起在顶层，点缩略图放大看 -->
    <MesImageLightbox ref="lightboxRef" />
  </div>
</template>
