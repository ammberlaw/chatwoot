<script setup>
/* global axios */
// 采购退料：把料退回给供应商（换新的 / 不要了），换回来的登记返回。
//
// 两条线共用这一张单（2026-10-29 用户定）：
//   · 退回去换新的（REPLACE）→ 只从不良品仓扣货，采购单到货量和应付都不动，钱照付；
//   · 退掉不要了（REFUND）→ 连采购到货量和应付红字一起冲，必须挂采购单。
// 实现上不是两套流程，差别只在过账生成的那张 PURCHASE_RETURN 出库单带不带采购单号。
//
// 返修跟踪留着（这页本来的主角）：退出去多久、回来多少、还有几件在外面；
// **2026-10-29 起登记返回会真的把货入回库**，不再是只改数字的台账。
import { ref, reactive, computed, nextTick, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesRole } from 'dashboard/composables/useMesRole';
import { useMesSupplierReturnsStore } from 'dashboard/stores/mes/supplierReturns';
import MesSupplierAPI from 'dashboard/api/mes/suppliers';
import MesProductionOrderAPI from 'dashboard/api/mes/productionOrders';
import { STATUS_TONE } from 'dashboard/helper/statusTone';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import MesProductPicker from 'dashboard/components-next/mes/MesProductPicker.vue';
import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
import MesColumnFilter from 'dashboard/components-next/mes/MesColumnFilter.vue';
import MesSupplierReturnPrintSheet from 'dashboard/components-next/mes/MesSupplierReturnPrintSheet.vue';
import MesViewDialog from 'dashboard/components-next/mes/MesViewDialog.vue';
import { printElement } from 'dashboard/helper/printHelper';

const store = useMesSupplierReturnsStore();
const { t } = useI18n();
const { accountId } = useAccount();
const { mesCan } = useMesRole();
const canWrite = computed(() => mesCan('purchase') || mesCan('stock'));

const ITEMS_PER_PAGE = 20;
const STATUS_CLASS = {
  DRAFT: STATUS_TONE.idle,
  SENT: STATUS_TONE.busy,
  PARTIAL: STATUS_TONE.flow,
  RETURNED: STATUS_TONE.done,
  CLOSED: STATUS_TONE.idle,
};
const STATUS_FILTERS = [
  { value: '', label: '全部' },
  { value: 'SENT', label: '已退出' },
  { value: 'PARTIAL', label: '部分返回' },
  { value: 'RETURNED', label: '已返回' },
];

const records = computed(() => store.getRecords);
const totalCount = computed(() => Number(store.getMeta?.count || 0));
const isFetching = computed(() => store.getUIFlags.fetchingList);
const saving = computed(
  () => store.getUIFlags.creatingItem || store.getUIFlags.updatingItem
);

// 退法：只扣库存 / 连采购应付一起冲（口径见后端 Mes::SupplierReturn::RETURN_KINDS）。
const RETURN_KINDS = [
  { value: 'REPLACE', label: '退换' },
  { value: 'REFUND', label: '退货' },
];

const currentPage = ref(1);
const activeStatus = ref('');
const searchQuery = ref('');
// 建单日期区间：退料单按月攒，不按时间收口就只能一页页翻（参数名 from/to，与采购申请单、采购单同一套）。
const fromDate = ref('');
const toDate = ref('');
// 表头逐列筛选（后端口径见 SupplierReturnsController::COLUMN_LIKE_FILTERS）。
// 状态不放漏斗——上面那排页签就是它，两个入口筛同一件事只会打架。
const colFilters = reactive({
  col_no: '',
  col_supplier: '',
  return_kind: '',
  col_ref: '',
  col_reason: '',
  sent: { from: '', to: '' },
  returned: { from: '', to: '' },
});
const FILTERABLE = {
  no: { type: 'text', key: 'col_no', placeholder: '退料单号' },
  supplier: { type: 'text', key: 'col_supplier', placeholder: '供应商' },
  kind: {
    type: 'select',
    key: 'return_kind',
    options: [{ value: '', label: '全部退法' }, ...RETURN_KINDS],
  },
  ref: { type: 'text', key: 'col_ref', placeholder: '采购单号 / 入库单号' },
  reason: { type: 'text', key: 'col_reason', placeholder: '退料原因' },
  sent: { type: 'date', key: 'sent' },
  returned: { type: 'date', key: 'returned' },
};
const filterOf = key => FILTERABLE[key];

const fetchList = () =>
  store.get({
    page: currentPage.value,
    status: activeStatus.value || undefined,
    q: searchQuery.value.trim() || undefined,
    from: fromDate.value || undefined,
    to: toDate.value || undefined,
    return_kind: colFilters.return_kind || undefined,
    col_no: colFilters.col_no.trim() || undefined,
    col_supplier: colFilters.col_supplier.trim() || undefined,
    col_ref: colFilters.col_ref.trim() || undefined,
    col_reason: colFilters.col_reason.trim() || undefined,
    sent_from: colFilters.sent.from || undefined,
    sent_to: colFilters.sent.to || undefined,
    returned_from: colFilters.returned.from || undefined,
    returned_to: colFilters.returned.to || undefined,
  });

// 换筛选条件回第 1 页——否则在第 3 页筛出 2 条结果会看到空列表。
const onColFilterChange = () => {
  currentPage.value = 1;
  fetchList();
};
watch([fromDate, toDate], onColFilterChange);

const onPage = page => {
  currentPage.value = page;
  fetchList();
};
const onFilter = value => {
  activeStatus.value = value;
  currentPage.value = 1;
  fetchList();
};

// 供应商、生产订单下拉
const supplierOptions = ref([]);
const orderOptions = ref([]);
const warehouseOptions = ref([]);
const purchaseOrderOptions = ref([]);
// 来源单据 id → 这张单的原始数据（含 stock_entry_items），推料时按它铺行。
const sourceEntryRows = new Map();
const inboundEntryOptions = ref([]);
// 退给供应商的货基本都先进了不良品仓，建单时默认指到那儿（名字匹配不上就不预设，
// 不替用户瞎猜一个仓）。
const defectWarehouseId = computed(() => {
  const hit = warehouseOptions.value.find(w => w.label.includes('不良品'));
  return hit ? String(hit.value) : '';
});

const loadOptions = async () => {
  const [suppliers, orders] = await Promise.all([
    // 供应商实际 332 家，原来取 300 会漏掉 32 家（按 updated_at 排，老供应商先掉）。
    // 500 是后端 per_page 的硬上限（SuppliersController#per_page_param），传更大也会被压到 500；
    // 供应商总量稳定（不像客户上万），够用。真涨到 500 以上要改成远程搜索。
    MesSupplierAPI.get({ per_page: 500 }).catch(() => null),
    MesProductionOrderAPI.get({ per_page: 500 }).catch(() => null),
  ]);
  supplierOptions.value = (suppliers?.data?.payload || []).map(s => ({
    value: s.id,
    label: s.name,
  }));
  orderOptions.value = (orders?.data?.payload || []).map(o => ({
    value: o.id,
    label: `${o.order_no}${o.product_name ? ` · ${o.product_name}` : ''}`,
  }));
};

// 仓库 / 采购单 / 原料入库单——后两样是用户点名要的「关联单号」。
// ⚠️ 裸 axios 拿到的是 snake_case，别和走 store 的驼峰混用。
const loadRefs = async () => {
  const api = path =>
    axios
      .get(`/api/v1/accounts/${accountId.value}/mes/${path}`)
      .catch(() => null);
  // 来源单据两种都要：原料入库单（货当初是哪张单收的）+ 车间的生产退料单
  // （不良品是哪张退料单退进不良品仓的）。两者回答的是同一个问题「这批货哪来的」，
  // 所以共用 source_stock_entry_id 这一个外键，不另开字段。
  const [wh, po, se, mr] = await Promise.all([
    api('warehouses?per_page=100'),
    api('purchase_orders?per_page=300'),
    api('stock_entries?purpose=MATERIAL_RECEIPT&per_page=300'),
    api('stock_entries?purpose=MATERIAL_RETURN&per_page=300'),
  ]);
  // value 统一用字符串：默认值（defectWarehouseId / backWarehouseId）也是字符串，
  // 一边数字一边字符串 ComboBox 对不上，表现就是「默认仓没预选上」。
  warehouseOptions.value = (wh?.data?.payload || []).map(w => ({
    value: String(w.id),
    label: w.name,
  }));
  purchaseOrderOptions.value = (po?.data?.payload || []).map(p => ({
    value: String(p.id),
    // 接口给的是 supplier_names（复数，一张采购单常含好几家）
    label: `${p.po_no}${p.supplier_names ? ` · ${p.supplier_names}` : ''}`,
  }));
  // 推料要的是明细，options 只有 label——原始行单独留一份。
  // ⚠️ 裸 axios ＝ snake_case，别和走 store 的驼峰混用。
  [...(mr?.data?.payload || []), ...(se?.data?.payload || [])].forEach(e => {
    sourceEntryRows.set(String(e.id), e);
  });
  inboundEntryOptions.value = [
    ...(mr?.data?.payload || []).map(e => ({
      value: String(e.id),
      label: `${e.entry_no} · 车间退料${e.production_order_no ? `（${e.production_order_no}）` : ''}`,
      note: e.product_name || '',
    })),
    ...(se?.data?.payload || []).map(e => ({
      value: String(e.id),
      label: `${e.entry_no} · 原料入库${e.purchase_order_no ? `（${e.purchase_order_no}）` : ''}`,
      note: e.product_name || '',
    })),
  ];
};

// ── 新建 ──
const formDialogRef = ref(null);
const blankRow = () => ({
  crmProductId: '',
  qty: '',
  unit: '',
  price: '',
  remark: '',
});
const form = reactive({
  mesSupplierId: '',
  productionOrderId: '',
  returnKind: 'REPLACE',
  warehouseId: '',
  purchaseOrderId: '',
  sourceStockEntryId: '',
  reason: '',
  remark: '',
  rows: [blankRow()],
});
const productLabels = reactive({});

// ── 选了来源单据就把料推出来，仓管勾选 ──────────────────────────
// 和车间的生产退料单同一套做法：原来这里选了入库单也什么都不推，
// 仓管还得照着入库单一行行把编码敲回去，敲错了要等过账才被拦。
//
// 可退量 = 这张入库单**收了多少** − 这张入库单**已经退掉多少**。
// 不按库存算：不良品仓里可能还堆着别的单退回来的同一颗料。
const pushedRows = ref([]);
const loadingRows = ref(false);
const pickedRows = computed(() => form.rows.filter(r => r.checked));
const allChecked = computed({
  get: () =>
    pushedRows.value.length > 0 &&
    pickedRows.value.length === form.rows.length,
  set: v => form.rows.forEach(r => { r.checked = v; }),
});

const rowError = row => {
  if (!row.checked) return '';
  const qty = Number(row.qty);
  if (!qty || qty <= 0) return '填数量';
  return qty > row.remain ? `最多 ${row.remain}` : '';
};

const loadReturnable = async entryId => {
  pushedRows.value = [];
  if (!entryId) return;

  const entry = sourceEntryRows.get(String(entryId));
  if (!entry) return;

  loadingRows.value = true;
  try {
    // 这张入库单已经退给供应商多少（按料汇总）。
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/supplier_returns`,
      { params: { source_stock_entry_id: entryId, per_page: 200 } }
    );
    const returned = new Map();
    (data?.payload || []).forEach(ret => {
      (ret.items || []).forEach(it => {
        if (!it.crm_product_id) return;
        returned.set(
          it.crm_product_id,
          (returned.get(it.crm_product_id) || 0) + (Number(it.qty) || 0)
        );
      });
    });

    pushedRows.value = (entry.stock_entry_items || [])
      .filter(it => it.crm_product_id)
      .map(it => {
        const received = Number(it.received_qty ?? it.qty) || 0;
        return {
          crmProductId: it.crm_product_id,
          materialNo: it.material_no || '',
          name: it.material_name || it.product_name || '',
          spec: it.specification || '',
          unit: it.unit || '',
          price: it.unit_price_micros
            ? String(it.unit_price_micros / 1_000_000)
            : '',
          remain: received - (returned.get(it.crm_product_id) || 0),
        };
      })
      .filter(r => r.remain > 0);
  } finally {
    loadingRows.value = false;
  }
};

watch(
  () => form.sourceStockEntryId,
  async id => {
    await loadReturnable(id);
    // 没选来源单（或这张单没剩可退的）就回到手敲模式，别把人卡死。
    form.rows = pushedRows.value.length
      ? pushedRows.value.map(r => ({ ...r, checked: false, qty: '', remark: '' }))
      : [blankRow()];
  }
);
const onProductPicked = (row, product) => {
  if (!product) return;
  productLabels[product.id] =
    `${product.sku || ''} ${product.name || ''}`.trim();
  row.unit = row.unit || product.unit || '';
};

const invalid = computed(
  () =>
    !form.mesSupplierId ||
    !form.warehouseId ||
    // 退掉不要了必须挂采购单，否则到货量和应付都冲不了（后端也校验，这里先拦住省一次往返）
    (form.returnKind === 'REFUND' && !form.purchaseOrderId) ||
    // 推料模式：至少勾一行，且勾了的都要填对数量（不超可退量）
    (pushedRows.value.length
      ? !pickedRows.value.length || form.rows.some(r => rowError(r))
      : !form.rows.some(r => r.crmProductId && Number(r.qty) > 0))
);

const openCreate = () => {
  Object.assign(form, {
    mesSupplierId: '',
    productionOrderId: '',
    returnKind: 'REPLACE',
    // 退给供应商的货基本都先进了不良品仓，默认就指到那儿，省得每次翻 15 个仓。
    warehouseId: defectWarehouseId.value,
    purchaseOrderId: '',
    sourceStockEntryId: '',
    reason: '',
    remark: '',
    rows: [blankRow()],
  });
  pushedRows.value = [];
  formDialogRef.value?.open();
};
const addRow = () => form.rows.push(blankRow());
const removeRow = i => form.rows.splice(i, 1);

const submit = async () => {
  if (invalid.value) return;
  try {
    await store.create({
      mes_supplier_id: form.mesSupplierId,
      production_order_id: form.productionOrderId || null,
      reason: form.reason.trim() || null,
      remark: form.remark.trim() || null,
      return_kind: form.returnKind,
      warehouse_id: Number(form.warehouseId),
      mes_purchase_order_id: form.purchaseOrderId || null,
      source_stock_entry_id: form.sourceStockEntryId || null,
      // 推料模式下只提交勾选的；手敲模式没有 checked 字段，照原样按填没填判断。
      items_attributes: form.rows
        .filter(r => (pushedRows.value.length ? r.checked : true))
        .filter(r => r.crmProductId && Number(r.qty) > 0)
        .map(r => ({
          crm_product_id: r.crmProductId,
          qty: Number(r.qty),
          unit: r.unit || null,
          // 价格界面按元填，库里存 micros（全站金额统一口径）
          unit_price_micros: Math.round((Number(r.price) || 0) * 1e6),
          remark: r.remark || null,
        })),
    });
    useAlert('退料单已建好，退出去时点「退出」记日期');
    formDialogRef.value?.close();
    fetchList();
  } catch (error) {
    useAlert(error?.message || '保存失败');
  }
};

// ── 退出 ──
const sendOut = async record => {
  try {
    await store.sendOut(record.id);
    useAlert(`${record.returnNo} 已记为今天退出`);
  } catch (error) {
    useAlert(error?.message || '操作失败');
  }
};

// ── 登记返回 ──
const backDialogRef = ref(null);
const backing = ref(null);
const backRows = ref([]);
const backDate = ref('');
const backWarehouseId = ref('');
const openReceive = record => {
  backing.value = record;
  backDate.value = new Date().toISOString().slice(0, 10);
  // 换回来的是好货，默认进原料仓；匹配不上就回退料那个仓，不替用户瞎猜。
  const raw = warehouseOptions.value.find(w => w.label.includes('原料'));
  backWarehouseId.value = String(raw?.value || record.warehouseId || '');
  backRows.value = (record.items || []).map(it => ({
    id: it.id,
    label: `${it.productSku || ''} ${it.productName || ''}`.trim() || '—',
    outstanding: Number(it.outstandingQty || 0),
    qty: '',
  }));
  backDialogRef.value?.open();
};
const submitReceive = async () => {
  const rows = backRows.value
    .filter(r => Number(r.qty) > 0)
    .map(r => ({ id: r.id, returned_qty: Number(r.qty) }));
  if (!rows.length) return;
  try {
    await store.receiveBack(
      backing.value.id,
      rows,
      backDate.value,
      Number(backWarehouseId.value) || null
    );
    useAlert(`${backing.value.returnNo} 已登记返回，货已入库`);
    backDialogRef.value?.close();
  } catch (error) {
    useAlert(error?.message || '登记失败');
  }
};

const removeRecord = async record => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`删除退料单「${record.returnNo}」？`)) return;
  try {
    await store.delete(record.id);
    useAlert('已删除');
    fetchList();
  } catch (error) {
    useAlert(error?.message || '删除失败');
  }
};

// 列表已经带完整物料明细，只读查看不触发退出或登记返回。
const viewDialogRef = ref(null);
const viewing = ref(null);
const detailLabel = key => t(`CRM.SUPPLIER_RETURN_DETAILS.${key}`);
const formatDetailQty = value =>
  Number(value || 0).toLocaleString('zh-CN', { maximumFractionDigits: 3 });
const formatDetailAmount = value =>
  (Number(value || 0) / 1e6).toLocaleString('zh-CN', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 6,
  });
const openView = record => {
  viewing.value = record;
  viewDialogRef.value?.open();
};
const viewFields = computed(() => {
  const r = viewing.value;
  if (!r) return [];
  return [
    ['SUPPLIER', r.supplierName],
    ['STATUS', r.statusLabel],
    ['RETURN_KIND', r.returnKindLabel],
    ['WAREHOUSE', r.warehouseName],
    ['PURCHASE_ORDER', r.purchaseOrderNo],
    ['SOURCE_ENTRY', r.sourceEntryNo],
    ['OUT_ENTRY', r.outEntryNo],
    ['PRODUCTION_ORDER', r.productionOrderNo],
    ['SENT_ON', r.sentOn],
    ['RETURNED_ON', r.returnedOn],
    ['OWNER', r.ownerName],
    ['TOTAL_AMOUNT', formatDetailAmount(r.totalAmountMicros)],
    ['REASON', r.reason],
    ['REMARK', r.remark],
  ].map(([key, value]) => ({ label: detailLabel(key), value }));
});
const viewColumns = computed(() =>
  [
    ['MATERIAL_CODE', 'productSku'],
    ['MATERIAL_NAME', 'productName'],
    ['SPECIFICATION', 'specification', 'wrap'],
    ['QTY', 'qty', 'right'],
    ['RETURNED_QTY', 'returnedQty', 'right'],
    ['OUTSTANDING_QTY', 'outstandingQty', 'right'],
    ['UNIT', 'unit'],
    ['UNIT_PRICE', 'unitPrice', 'right'],
    ['AMOUNT', 'amount', 'right'],
    ['REMARK', 'remark', 'wrap'],
  ].map(([label, key, layout]) => ({
    label: detailLabel(label),
    key,
    align: layout === 'right' ? 'right' : undefined,
    wrap: layout === 'wrap',
  }))
);
const viewItems = computed(() =>
  (viewing.value?.items || []).map(item => ({
    ...item,
    qty: formatDetailQty(item.qty),
    returnedQty:
      viewing.value.returnKind === 'REFUND'
        ? detailLabel('NOT_APPLICABLE')
        : formatDetailQty(item.returnedQty),
    outstandingQty:
      viewing.value.returnKind === 'REFUND'
        ? detailLabel('NOT_APPLICABLE')
        : formatDetailQty(item.outstandingQty),
    unitPrice: formatDetailAmount(item.unitPriceMicros),
    amount: formatDetailAmount(item.amountMicros),
  }))
);

// ── 打印 ──
// 供应商那边要一张纸跟着货走（退了什么、多少钱、对应哪张采购单），仓管和财务各留一份。
const printing = ref(null);
const printSheetRef = ref(null);
const printRows = computed(() =>
  (printing.value?.items || []).map(it => ({
    materialNo: it.productSku,
    name: it.productName,
    spec: it.specification,
    qty: it.qty,
    unit: it.unit,
    price: (it.unitPriceMicros || 0) / 1e6,
    amount: (it.amountMicros || 0) / 1e6,
    remark: it.remark,
  }))
);
const printReturn = async record => {
  printing.value = record;
  // 等票面渲染出来再克隆去打印，否则印出来是空的。
  await nextTick();
  printElement(
    printSheetRef.value?.$el || printSheetRef.value,
    `采购退料单 ${record.returnNo || ''}`,
    { page: '@page{size:A4;margin:12mm}', brandHeader: false }
  );
};

onMounted(() => {
  fetchList();
  loadOptions();
  loadRefs();
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div
      class="flex items-center justify-between px-4 py-3 sm:px-6 sm:py-4 [.theme-classic_&]:sm:!px-8"
    >
      <h1 class="text-xl font-semibold text-n-slate-12">采购退料</h1>
      <Button
        v-if="canWrite"
        label="新建退料单"
        color="iris"
        size="sm"
        @click="openCreate"
      />
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
        @click="onFilter(f.value)"
      >
        {{ f.label }}
      </button>
      <div class="flex items-center gap-2 ms-auto">
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
            placeholder="搜索单号、原因"
            @keyup.enter="onPage(1)"
          />
        </div>
      </div>
    </div>

    <HScrollButtons />
    <div
      class="flex-1 min-h-0 px-4 pb-4 overflow-auto sm:px-6 sm:pb-6 [.theme-classic_&]:sm:!px-8"
    >
      <!-- 宽表写法同采购单/原料入库/销售出库：表格按内容撑开、容器横滚，
           单元格一律 nowrap，自由文本 truncate，表头 sticky、操作列右侧冻结。
           写成 w-full 的话 11 列会被压进容器宽度，中文没空格只能逐字折行——
           供应商名会变成竖着排的一列字，一行撑到 300px 高。 -->
      <!-- w-max：按内容撑开，中文才不会被逐字折行（写 w-full 的话供应商名会竖着排一列字）。
           min-w-full：至少铺满容器，别在数据少时缩成窄窄一条。
           没有冻结列：砍掉两列空列后 9 列装得下，而冻结在「只溢出几十像素」时
           反而会被 sticky 往左拉、盖掉相邻列（实测盖了状态列 54px）。 -->
      <table class="w-max min-w-full text-sm">
        <thead class="text-xs text-n-slate-11">
          <tr
            class="border-b border-n-weak [&>th]:sticky [&>th]:top-0 [&>th]:z-10 [&>th]:bg-n-solid-1 [&>th]:whitespace-nowrap"
          >
            <th class="px-3 py-2 font-medium text-left">
              单号
              <MesColumnFilter
                v-model="colFilters[filterOf('no').key]"
                :placeholder="filterOf('no').placeholder"
                @change="onColFilterChange"
              />
            </th>
            <th class="px-3 py-2 font-medium text-left">
              供应商
              <MesColumnFilter
                v-model="colFilters[filterOf('supplier').key]"
                :placeholder="filterOf('supplier').placeholder"
                @change="onColFilterChange"
              />
            </th>
            <th class="px-3 py-2 font-medium text-left">
              退料方式
              <MesColumnFilter
                v-model="colFilters[filterOf('kind').key]"
                type="select"
                :options="filterOf('kind').options"
                @change="onColFilterChange"
              />
            </th>
            <th class="px-3 py-2 font-medium text-left">
              关联单号
              <MesColumnFilter
                v-model="colFilters[filterOf('ref').key]"
                :placeholder="filterOf('ref').placeholder"
                @change="onColFilterChange"
              />
            </th>
            <th class="px-3 py-2 font-medium text-left">
              退料原因
              <MesColumnFilter
                v-model="colFilters[filterOf('reason').key]"
                :placeholder="filterOf('reason').placeholder"
                @change="onColFilterChange"
              />
            </th>
            <th class="px-3 py-2 font-medium text-left">
              退出
              <MesColumnFilter
                v-model="colFilters[filterOf('sent').key]"
                type="date"
                @change="onColFilterChange"
              />
            </th>
            <th class="px-3 py-2 font-medium text-left">
              返回
              <MesColumnFilter
                v-model="colFilters[filterOf('returned').key]"
                type="date"
                @change="onColFilterChange"
              />
            </th>
            <th class="px-3 py-2 font-medium text-right">在外天数</th>
            <th class="px-3 py-2 font-medium text-left">状态</th>
            <th class="px-3 py-2 font-medium text-right">操作</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="r in records"
            :key="r.id"
            class="border-b border-n-weak/60 hover:bg-n-alpha-1"
          >
            <td class="px-3 py-2 whitespace-nowrap text-n-slate-12">
              <button
                type="button"
                class="reset-base rounded-sm text-left hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-slate-9"
                @click="openView(r)"
              >
                {{ r.returnNo }}
              </button>
            </td>
            <td
              class="px-3 py-2 max-w-[13rem] truncate text-n-slate-11"
              :title="r.supplierName"
            >
              {{ r.supplierName || '—' }}
            </td>
            <!-- 换新的 / 不要了。财务看这一列就知道这笔钱该不该收回来。 -->
            <td class="px-3 py-2 whitespace-nowrap">
              <span
                :class="
                  r.returnKind === 'REFUND'
                    ? 'text-n-ruby-11'
                    : 'text-n-slate-11'
                "
              >
                {{ r.returnKind === 'REFUND' ? '退货' : '退换' }}
              </span>
            </td>
            <!-- 关联单号：采购单 / 收这批货的入库单 / 退出去生成的出库单 -->
            <td
              class="px-3 py-2 text-xs leading-5 whitespace-nowrap text-n-slate-11"
            >
              <div v-if="r.purchaseOrderNo">采购 {{ r.purchaseOrderNo }}</div>
              <div v-if="r.sourceEntryNo">
                {{
                  r.sourceEntryKind === 'MATERIAL_RETURN' ? '车间退料' : '入库'
                }}
                {{ r.sourceEntryNo }}
              </div>
              <div v-if="r.outEntryNo">出库 {{ r.outEntryNo }}</div>
              <span v-if="!r.purchaseOrderNo && !r.outEntryNo">—</span>
            </td>
            <td
              class="px-3 py-2 max-w-[14rem] truncate whitespace-nowrap text-n-slate-11"
              :title="r.reason"
            >
              {{ r.reason || '—' }}
            </td>
            <td class="px-3 py-2 whitespace-nowrap text-n-slate-11">
              {{ r.sentOn || '—' }}
            </td>
            <td class="px-3 py-2 whitespace-nowrap text-n-slate-11">
              {{ r.returnedOn || '—' }}
            </td>
            <!-- 还没回来的标琥珀：这列就是用户要盯的「退出去多久了」 -->
            <td
              class="px-3 py-2 text-right tabular-nums whitespace-nowrap"
              :class="r.out ? 'text-n-amber-11' : 'text-n-slate-11'"
            >
              {{ r.daysOut == null ? '—' : `${r.daysOut} 天` }}
            </td>
            <td class="px-3 py-2 whitespace-nowrap">
              <span
                class="inline-block px-2 py-0.5 text-xs rounded whitespace-nowrap"
                :class="STATUS_CLASS[r.status]"
              >
                {{ r.statusLabel }}
              </span>
            </td>
            <td class="px-3 py-2">
              <div
                class="flex items-center justify-end gap-1 whitespace-nowrap"
              >
                <Button
                  :label="detailLabel('VIEW')"
                  variant="ghost"
                  color="slate"
                  size="xs"
                  @click="openView(r)"
                />
                <Button
                  v-if="canWrite && !r.sentOn"
                  label="退出"
                  color="iris"
                  size="xs"
                  :is-loading="saving"
                  @click="sendOut(r)"
                />
                <!-- 「退掉不要了」的货不会回来，这个按钮对它没意义（后端也拦） -->
                <Button
                  v-if="
                    canWrite &&
                    r.sentOn &&
                    r.status !== 'RETURNED' &&
                    r.returnKind !== 'REFUND'
                  "
                  label="登记返回"
                  variant="faded"
                  color="slate"
                  size="xs"
                  @click="openReceive(r)"
                />
                <Button
                  label="打印"
                  variant="ghost"
                  color="slate"
                  size="xs"
                  @click="printReturn(r)"
                />
                <button
                  v-if="canWrite && !r.sentOn"
                  type="button"
                  title="删除"
                  class="i-lucide-trash-2 size-4 text-n-slate-10 hover:text-n-ruby-11"
                  @click="removeRecord(r)"
                />
              </div>
            </td>
          </tr>
          <tr v-if="!records.length && !isFetching">
            <td colspan="9" class="px-3 py-10 text-center text-n-slate-11">
              暂无退料单
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <PaginationFooter
      :current-page="currentPage"
      :total-items="totalCount"
      :items-per-page="ITEMS_PER_PAGE"
      @update:current-page="onPage"
    />

    <MesViewDialog
      ref="viewDialogRef"
      width="full"
      :title="
        t('CRM.SUPPLIER_RETURN_DETAILS.TITLE', {
          no: viewing?.returnNo || '',
        })
      "
      :fields="viewFields"
      :items-title="detailLabel('ITEMS')"
      :item-columns="viewColumns"
      :items="viewItems"
      hide-print
      :brand-header="false"
    >
      <template #headerActions>
        <Button
          v-if="viewing"
          :label="detailLabel('PRINT')"
          variant="outline"
          color="slate"
          size="sm"
          @click="printReturn(viewing)"
        />
      </template>
    </MesViewDialog>

    <!-- 新建 -->
    <Dialog
      ref="formDialogRef"
      width="3xl"
      overflow-y-auto
      title="新建退料单"
      confirm-button-label="保存"
      :disable-confirm-button="invalid"
      :is-loading="saving"
      @confirm="submit"
    >
      <div class="flex flex-col gap-3">
        <div class="grid grid-cols-2 gap-3">
          <div class="flex flex-col gap-1">
            <label class="text-label text-n-slate-12">
              供应商 <span class="text-n-ruby-11">*</span>
            </label>
            <ComboBox
              v-model="form.mesSupplierId"
              :options="supplierOptions"
              placeholder="选择"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-label text-n-slate-12">生产订单</label>
            <ComboBox
              v-model="form.productionOrderId"
              :options="orderOptions"
              placeholder="选择"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-label text-n-slate-12">
              退料方式 <span class="text-n-ruby-11">*</span>
            </label>
            <SelectCard
              v-model="form.returnKind"
              :options="RETURN_KINDS"
              block
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-label text-n-slate-12">
              退料仓库 <span class="text-n-ruby-11">*</span>
            </label>
            <ComboBox
              v-model="form.warehouseId"
              :options="warehouseOptions"
              placeholder="选择"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-label text-n-slate-12">
              采购单
              <span v-if="form.returnKind === 'REFUND'" class="text-n-ruby-11">
                *
              </span>
            </label>
            <ComboBox
              v-model="form.purchaseOrderId"
              :options="purchaseOrderOptions"
              placeholder="选择"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-label text-n-slate-12">来源单据</label>
            <ComboBox
              v-model="form.sourceStockEntryId"
              :options="inboundEntryOptions"
              placeholder="选择"
            />
          </div>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-label text-n-slate-12">退料原因</label>
          <Input v-model="form.reason" size="sm" />
        </div>

        <div class="flex items-center justify-between">
          <span class="text-heading-3 text-n-slate-12">退料明细</span>
          <span v-if="pickedRows.length" class="text-label-small text-n-slate-11">
            已选 {{ pickedRows.length }} / {{ form.rows.length }}
          </span>
          <Button
            v-if="!pushedRows.length"
            label="加一行"
            icon="i-lucide-plus"
            color="slate"
            variant="faded"
            size="xs"
            @click="addRow"
          />
        </div>

        <!-- 选了来源单据就把那张单收的料推出来，仓管勾要退的那几行。
             可退量 = 这张单收了多少 − 已经退掉多少。 -->
        <div v-if="loadingRows" class="py-6 text-center text-n-slate-11">
          正在取料…
        </div>
        <table v-else-if="pushedRows.length" class="w-full text-sm">
          <thead>
            <tr class="text-left text-n-slate-11 border-b border-n-weak">
              <th class="px-2 py-1 w-8">
                <input v-model="allChecked" type="checkbox" class="size-4" />
              </th>
              <th class="px-2 py-1 font-medium whitespace-nowrap">物料编码</th>
              <th class="px-2 py-1 font-medium">物料名称</th>
              <th class="px-2 py-1 font-medium whitespace-nowrap">规格型号</th>
              <th class="px-2 py-1 font-medium text-right whitespace-nowrap">可退</th>
              <th class="px-2 py-1 font-medium whitespace-nowrap w-28">退料数量</th>
              <th class="px-2 py-1 font-medium whitespace-nowrap w-24">单价</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="(row, i) in form.rows"
              :key="row.crmProductId || i"
              class="border-b border-n-weak"
            >
              <td class="px-2 py-1">
                <input v-model="row.checked" type="checkbox" class="size-4" />
              </td>
              <td class="px-2 py-1 font-mono whitespace-nowrap text-n-slate-12">
                {{ row.materialNo || '—' }}
              </td>
              <td class="px-2 py-1 truncate max-w-[12rem]" :title="row.name">
                {{ row.name || '—' }}
              </td>
              <td
                class="px-2 py-1 truncate max-w-[10rem] text-n-slate-11"
                :title="row.spec"
              >
                {{ row.spec || '—' }}
              </td>
              <td class="px-2 py-1 text-right tabular-nums whitespace-nowrap">
                {{ row.remain }}{{ row.unit || '' }}
              </td>
              <td class="px-2 py-1">
                <Input
                  v-model="row.qty"
                  size="sm"
                  type="number"
                  :disabled="!row.checked"
                  :message="rowError(row)"
                  :message-type="rowError(row) ? 'error' : 'info'"
                />
              </td>
              <td class="px-2 py-1">
                <Input
                  v-model="row.price"
                  size="sm"
                  type="number"
                  :disabled="!row.checked"
                />
              </td>
            </tr>
          </tbody>
        </table>

        <div
          v-for="(row, i) in pushedRows.length ? [] : form.rows"
          :key="i"
          class="flex items-center gap-2 p-2 border rounded-lg border-n-weak"
        >
          <span class="w-5 text-xs text-center shrink-0 text-n-slate-10">
            {{ i + 1 }}
          </span>
          <div class="flex-1 min-w-0">
            <MesProductPicker
              materials-only
              :account-id="accountId"
              :model-value="row.crmProductId"
              :display-text="productLabels[row.crmProductId] || ''"
              placeholder="选择"
              @update:model-value="v => (row.crmProductId = v)"
              @select="pd => onProductPicked(row, pd)"
            />
          </div>
          <div class="w-24 shrink-0">
            <Input
              v-model="row.qty"
              size="sm"
              type="number"
              placeholder="数量"
            />
          </div>
          <div class="w-20 shrink-0">
            <Input v-model="row.unit" size="sm" placeholder="单位" />
          </div>
          <div class="w-24 shrink-0">
            <Input
              v-model="row.price"
              size="sm"
              type="number"
              placeholder="单价"
            />
          </div>
          <button
            type="button"
            class="shrink-0 i-lucide-x size-4 text-n-slate-10 hover:text-n-ruby-11"
            :disabled="form.rows.length <= 1"
            @click="removeRow(i)"
          />
        </div>

        <div class="flex flex-col gap-1">
          <label class="text-label text-n-slate-12">备注</label>
          <Input v-model="form.remark" size="sm" />
        </div>
      </div>
    </Dialog>

    <!-- 登记返回 -->
    <Dialog
      ref="backDialogRef"
      width="xl"
      title="登记返回"
      confirm-button-label="确认"
      @confirm="submitReceive"
    >
      <div class="flex flex-col gap-3">
        <div class="flex flex-wrap items-center gap-2">
          <span class="text-label text-n-slate-12">返回日期</span>
          <div class="w-44">
            <DatePicker v-model="backDate" />
          </div>
          <span class="ml-2 text-label text-n-slate-12">入库仓库</span>
          <div class="w-48">
            <ComboBox
              v-model="backWarehouseId"
              :options="warehouseOptions"
              placeholder="选择"
            />
          </div>
        </div>
        <div
          v-for="row in backRows"
          :key="row.id"
          class="flex items-center gap-2 text-sm"
        >
          <span class="flex-1 min-w-0 truncate text-n-slate-12">
            {{ row.label }}
          </span>
          <span class="text-xs shrink-0 text-n-slate-10">
            还差 {{ row.outstanding }}
          </span>
          <div class="w-24 shrink-0">
            <Input
              v-model="row.qty"
              size="sm"
              type="number"
              placeholder="回来多少"
            />
          </div>
        </div>
        <p class="text-xs text-n-slate-10">
          只记台账，不自动入库——要不要重新入库 / 质检还没定，定了再接。
        </p>
      </div>
    </Dialog>

    <!-- 退料单票面：只在打印时用，平时不占版面（printElement 克隆它去打印）。 -->
    <div
      v-if="printing"
      aria-hidden="true"
      class="fixed -left-[9999px] top-0 w-[760px]"
    >
      <MesSupplierReturnPrintSheet
        ref="printSheetRef"
        :record="printing"
        :items="printRows"
      />
    </div>
  </div>
</template>
