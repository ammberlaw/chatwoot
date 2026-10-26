<script setup>
/* global axios */
import { ref, computed, reactive, watch, nextTick, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import camelcaseKeys from 'camelcase-keys';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import MesShipmentAPI from 'dashboard/api/mes/shipments';
import { useMesShipmentsStore } from 'dashboard/stores/mes/shipments';
import { useMesWarehousesStore } from 'dashboard/stores/mes/warehouses';

import Button from 'dashboard/components-next/button/Button.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import MesBoardOwnerBar from 'dashboard/components-next/mes/MesBoardOwnerBar.vue';
import { useMesRole } from 'dashboard/composables/useMesRole';
import { useMesDocOwner } from 'dashboard/composables/useMesDocOwner';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import MesViewDialog from 'dashboard/components-next/mes/MesViewDialog.vue';
import MesShipmentPrintSheet from 'dashboard/components-next/mes/MesShipmentPrintSheet.vue';
import { printElement } from 'dashboard/helper/printHelper';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';
import { orderSearchText } from 'dashboard/routes/dashboard/mes/orderSearchText';
import MesStatusPill from 'dashboard/components-next/mes/MesStatusPill.vue';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
const { accountId } = useAccount();
const store = useMesShipmentsStore();
const { mesCan } = useMesRole();
const warehousesStore = useMesWarehousesStore();

const currentUserId = useMapGetter('getCurrentUserID');
const currentRole = useMapGetter('getCurrentRole');
const currentUser = useMapGetter('getCurrentUser');
const crmRole = computed(() => currentUser.value?.crm_role);
const isAdmin = computed(() => currentRole.value === 'administrator');
const isAdminLike = computed(
  () => isAdmin.value || crmRole.value === 'deputy_admin'
);
const { isMyDoc } = useMesDocOwner();
// 财务审核「款收齐没有」：财务 / 副管理员 / 管理员（用户给的金蝶流程）。
// 「谁能审这张单」不再在前端算：财务始终能审，小额单仓库自己也能批，后端按单下发
// can_approve（Mes::Shipment#approver_for?）。原来这里按角色一刀切，判不了金额。
// 仓库出库能力。
const canShip = computed(() => mesCan('shipment'));
// 现货出库开单：CRM 业务条线（业务员/主管/副管理员）或管理员。
const BUSINESS_ROLES = ['sales', 'manager', 'deputy_admin'];
const canOpenStock = computed(
  () => isAdmin.value || BUSINESS_ROLES.includes(crmRole.value)
);

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const saving = computed(() => store.getUIFlags.creatingItem);
const acting = computed(() => store.getUIFlags.updatingItem);
const time = d => (d ? new Date(d).toLocaleString() : '—');
const STATUS_LABELS = {
  DRAFT: '草稿',
  PENDING_APPROVAL: '待审核',
  APPROVED: '待出库',
  REJECTED: '已驳回',
  SHIPPED: '已出库',
  CANCELLED: '已作废',
};
const KIND_LABELS = { PRODUCTION: '生产出库', STOCK: '现货出库' };

// 单据可执行的动作判定（按状态/角色）。
// 两种出库都走财务审核——过账都会打 ERP（成本归集+凭证+订单完结），
// 原先只有现货走审核、生产出库建完直接出（见 Mes::Shipment#submit_for_approval!）。
//
// 审核人不再是提交时解析出的那一个主管，而是「财务这组人谁看到谁批」，
// 所以这里不再比 managerId——真正的把关在后端 Mes::Shipment.approver?。
// 能不能批这张单由后端按单给（财务始终能批；小额单仓库自己批，见
// Mes::Shipment#approver_for?）——不是看角色，所以不能在前端拿 canApprove 一刀切。
const canApproveRow = s => s.status === 'PENDING_APPROVAL' && s.canApprove;
const canResubmitRow = s =>
  s.status === 'REJECTED' &&
  (s.ownerId === currentUserId.value || isAdminLike.value);
const canShipRow = s => canShip.value && s.status === 'APPROVED';
// 编辑：仅生产出库草稿，且只有开单人本人（系统管理员可代改）。
// 原来有出库能力的人都能改别人的单，出了问题查不到人。
const canEditRow = s =>
  s.kind === 'PRODUCTION' && s.status === 'DRAFT' && isMyDoc(s);
// 删单：只针对草稿/被驳回单（已审核的占着成品预占、已出库的要走冲销）。
// 门槛比编辑松——重复草稿常常是仓管准备出库时才发现的，只许开单人删
// 就会一直挂在列表里（生产上 SO-20260916-06 挂了两张谁都删不掉）。
const canDeleteRow = s =>
  ['DRAFT', 'REJECTED'].includes(s.status) && (canShip.value || isMyDoc(s));

const removeShipment = async s => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`确定删除出库单 ${s.shipmentNo}？删除后不可恢复。`))
    return;
  try {
    const ok = await store.delete(s.id);
    if (ok) useAlert('已删除');
  } catch (error) {
    useAlert(error.message || '删除失败');
  }
};

// 只读查看
const viewDialogRef = ref(null);
const viewing = ref(null);
const openView = s => {
  viewing.value = s;
  viewDialogRef.value?.open();
};

// 从 ERP 的销售订单详情点出货单号跳来时带 ?focus=<id>：加载后自动展开那张单（只开一次）。
// 当前页里没有这一单（翻页/筛选）时按 id 取回来打开，否则点过来只会停在整个列表上。
const route = useRoute();
const focusOpened = ref(false);
const openFocusShipment = async list => {
  const focus = route.query.focus;
  if (focusOpened.value || !focus) return;

  const rec = list.find(r => String(r.id) === String(focus));
  if (rec) {
    focusOpened.value = true;
    openView(rec);
    return;
  }
  if (!list.length) return; // 还没加载完，等下一轮

  focusOpened.value = true;
  try {
    const { data } = await MesShipmentAPI.show(focus);
    openView(camelcaseKeys(data?.payload || data || {}, { deep: true }));
  } catch {
    useAlert('这张出库单可能已被删除或无权查看');
  }
};
watch(records, list => openFocusShipment(list), { immediate: true });
const viewFields = computed(() => {
  const s = viewing.value || {};
  return [
    { label: '出库单号', value: s.shipmentNo },
    { label: '类型', value: KIND_LABELS[s.kind] || s.kind },
    { label: '销售订单', value: s.salesOrderNo },
    { label: '客户', value: s.customerName },
    { label: '交货方式', value: s.deliveryMethodLabel },
    { label: '销售订单', value: s.productionOrderNo },
    { label: '归属人', value: s.productionOrderOwnerName || s.ownerName },
    { label: '状态', value: STATUS_LABELS[s.status] || s.status },
    { label: '审核人', value: s.managerName },
    { label: '审核时间', value: time(s.approvedAt) },
    { label: '驳回原因', value: s.rejectReason },
    { label: '通知时间', value: time(s.notifiedAt) },
    { label: '出库时间', value: time(s.shippedAt) },
    { label: '制单人', value: s.ownerName },
    { label: '备注', value: s.remark },
  ];
});
// 销售出库单票面（1:1 对标旧系统那张）：套打在 9.5×5.5 英寸三联复写纸上（针式打印机），
// 纸张写死、不加 Wintouch 字标——加了会把版心顶下去，套打压到预印格线上。
const printSheetRef = ref(null);
const printRows = computed(() =>
  (viewing.value?.shipmentItems || []).map(it => ({
    sku: it.productSku,
    name: it.productName,
    spec: it.specification,
    warehouse: viewing.value?.warehouseName,
    unit: it.unit,
    qty: it.qty,
    unitPrice: it.unitPrice,
    amount: it.amount,
    remark: it.remark,
  }))
);
const printShipment = () =>
  printElement(
    printSheetRef.value?.$el || printSheetRef.value,
    `销售出库单 ${viewing.value?.shipmentNo || ''}`,
    // 方向由打印对话框自己选（同采购入库单）；混写 landscape 浏览器也不认。
    { page: '@page{size:9.5in 5.5in;margin:8mm}', brandHeader: false }
  );

const VIEW_ITEM_COLS = [
  { label: '成品', key: 'productName' },
  { label: '数量', key: 'qty', align: 'right' },
  { label: '单位', key: 'unit' },
];

const productionOrders = ref([]);
const salesOrders = ref([]);
const productionOrderOptions = computed(() => [
  { value: '', label: '选择销售订单…' },
  // 标签里带上销售订单号：仓管找的是「这张销售订单的货」，只给 MO 号等于让人对不上。
  ...productionOrders.value.map(p => ({
    value: String(p.id),
    label: `${p.order_no} · ${p.product_name}${p.sales_order_no ? ` · ${p.sales_order_no}` : ''}`,
    searchText: orderSearchText(p),
  })),
]);
const warehouseOptions = computed(() =>
  (warehousesStore.getRecords || []).map(w => ({
    value: String(w.id),
    label: w.name,
  }))
);

// ── CRM 成品 / 客户 服务端搜索选项 ──
const productOptions = ref([]);
const mergeOptions = (target, list) => {
  const seen = new Set(target.value.map(o => o.value));
  list.forEach(o => {
    if (!seen.has(o.value)) {
      target.value.push(o);
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
    mergeOptions(
      productOptions,
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

const customerOptions = ref([]);
const loadCustomers = async (q = '') => {
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/crm/customers`,
      { params: { q, per_page: 30 } }
    );
    mergeOptions(
      customerOptions,
      (data?.payload || []).map(c => ({ value: String(c.id), label: c.name }))
    );
  } catch {
    // 忽略
  }
};

// 成品现货结存（供开单时参考）。
const stockBalances = ref([]);
const loadStock = async () => {
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/stock_balances`,
      { params: { item_type: 'PRODUCT' } }
    );
    stockBalances.value = data?.payload || [];
  } catch {
    stockBalances.value = [];
  }
};
// 可用现货 = 物理结存 − 其他待出库单预占（后端返回 available_qty）。
const stockFor = (productId, warehouseId) => {
  if (!productId) return 0;
  const rows = stockBalances.value.filter(
    b => String(b.crm_product_id) === String(productId)
  );
  const scoped = warehouseId
    ? rows.filter(b => String(b.warehouse_id) === String(warehouseId))
    : rows;
  return scoped.reduce(
    (sum, b) => sum + Number(b.available_qty ?? b.qty ?? 0),
    0
  );
};

// 这个编码在**原料账**上的存货。出库只扣成品账（ensure_stock_sufficient! 写死
// item_type='PRODUCT'），而买来的屏这类货常常既是原料又是成品——有时装机，有时
// 直接转手卖。成品账是 0、原料仓却堆着货时必须把这句话说出来：人在库存结存页
// 明明看到原料仓有 160 片，这里只写「可用 0」，只会以为系统算错了
// （2026-10-23 就为这个连开了两张出不掉的单）。
const materialStock = ref([]);
const loadMaterialStock = async productId => {
  materialStock.value = [];
  if (!productId) return;

  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/stock_balances`,
      { params: { item_type: 'MATERIAL', crm_product_id: productId } }
    );
    materialStock.value = data?.payload || [];
  } catch {
    materialStock.value = [];
  }
};
// ── 生产出库（仓库从生产订单开单；草稿可编辑）──
const dialogRef = ref(null);
const editingId = ref(null); // 非空=编辑现有草稿出库单
const editingItemId = ref(null); // 编辑时保留原明细行 id，避免重复建行
const form = reactive({
  productionOrderId: '',
  crmSalesOrderId: '',
  crmCustomerId: '',
  warehouseId: '',
  crmProductId: '',
  productName: '',
  qty: '',
  unit: '',
});
const { isDirty, markPristine } = useDirtyGuard(() => form);
// 商品编码可空（建单时选填）：只要选了生产订单 + 有数量即可提交，
// 缺编码时后端按成品名兜底建/关联商品编码再扣库存。
const invalid = computed(() => !form.productionOrderId || !Number(form.qty));

const onPickOrder = v => {
  form.productionOrderId = v;
  const po = productionOrders.value.find(p => String(p.id) === String(v));
  if (!po) return;
  form.crmSalesOrderId = po.crm_sales_order_id
    ? String(po.crm_sales_order_id)
    : '';
  form.crmProductId = po.crm_product_id ? String(po.crm_product_id) : '';
  form.productName = po.product_name || '';
  loadMaterialStock(form.crmProductId);
  // 默认出库数量 = 该成品可用现货（物理结存，真实可发货量），无现货数据时退回订单数量。
  // 不用 produced_qty——报工可能重复/超报被灌大（曾出现订单 104、produced_qty 却 304）。
  const avail = form.crmProductId
    ? stockFor(form.crmProductId, finishedWarehouseId())
    : 0;
  form.qty = String(avail > 0 ? avail : po.qty || '');
  form.unit = po.unit || '';
  const so = salesOrders.value.find(
    s => String(s.id) === String(po.crm_sales_order_id)
  );
  form.crmCustomerId = so?.crm_customer_id ? String(so.crm_customer_id) : '';
};

const finishedWarehouseId = () =>
  (warehousesStore.getRecords || []).find(w => w.kind === 'FINISHED')?.id;

// 当前仓 + 当前成品的可用现货，换仓库时跟着变——否则人要等到点「出库」才知道这仓没货。
const availableInWarehouse = computed(() =>
  form.crmProductId && form.warehouseId
    ? stockFor(form.crmProductId, form.warehouseId)
    : 0
);
const overAvailable = computed(
  () => Number(form.qty) > Number(availableInWarehouse.value)
);
// 只在「成品确实没有」时提示，有货时不添乱。
const materialHint = computed(() => {
  if (!form.crmProductId || Number(availableInWarehouse.value) > 0) return '';

  const rows = materialStock.value.filter(b => Number(b.qty) > 0);
  if (!rows.length) return '';

  const where = rows
    .map(b => `${b.warehouse_name || '原料仓'} ${Number(b.qty)}`)
    .join('、');
  // 指路到人不到页面：转换是仓管的动作（mes_can?(:stock)），开出库单的业务员点进去也转不了。
  return `· 原料账有货（${where}），需仓管先在「原料成品转换」里转成成品才能出货`;
});
// 换仓库时把数量重置成该仓的可用量，省得人工算。
const onPickWarehouse = value => {
  form.warehouseId = value;
  const avail = form.crmProductId ? stockFor(form.crmProductId, value) : 0;
  if (avail > 0) form.qty = String(avail);
};

const openCreate = () => {
  const fin = finishedWarehouseId();
  editingId.value = null;
  editingItemId.value = null;
  Object.assign(form, {
    productionOrderId: '',
    crmSalesOrderId: '',
    crmCustomerId: '',
    warehouseId: fin ? String(fin) : '',
    crmProductId: '',
    productName: '',
    qty: '',
    unit: '',
  });
  markPristine();
  dialogRef.value?.open();
};

// 编辑草稿出库单：回填生产订单/仓库/成品/数量，提交走 update。
const openEdit = s => {
  editingId.value = s.id;
  const item = (s.shipmentItems || [])[0] || {};
  editingItemId.value = item.id || null;
  Object.assign(form, {
    productionOrderId: s.productionOrderId ? String(s.productionOrderId) : '',
    crmSalesOrderId: s.crmSalesOrderId ? String(s.crmSalesOrderId) : '',
    crmCustomerId: s.crmCustomerId ? String(s.crmCustomerId) : '',
    warehouseId: s.warehouseId ? String(s.warehouseId) : '',
    crmProductId: item.crmProductId ? String(item.crmProductId) : '',
    productName: item.productName || '',
    qty: item.qty != null ? String(item.qty) : '',
    unit: item.unit || '',
  });
  markPristine();
  dialogRef.value?.open();
};

const submit = async () => {
  if (invalid.value) return;
  const payload = {
    kind: 'PRODUCTION',
    productionOrderId: form.productionOrderId || null,
    crmSalesOrderId: form.crmSalesOrderId || null,
    crmCustomerId: form.crmCustomerId || null,
    warehouseId: form.warehouseId ? Number(form.warehouseId) : null,
    shipmentItemsAttributes: [
      {
        id: editingItemId.value || undefined,
        crmProductId: form.crmProductId ? Number(form.crmProductId) : null,
        qty: Number(form.qty),
        unit: form.unit,
      },
    ],
  };
  const ok = editingId.value
    ? await store.update({ id: editingId.value, ...payload })
    : await store.create(payload);
  if (ok) {
    useAlert(editingId.value ? '出库单已更新' : `已建出库单 ${ok.shipmentNo}`);
    dialogRef.value?.close();
  }
};

// ── 现货出库（业务员开单 → 主管审核 → 仓库出库）──
const stockDialogRef = ref(null);
const stockForm = reactive({
  crmCustomerId: '',
  crmSalesOrderId: '',
  warehouseId: '',
  rows: [], // { crmProductId, qty }
});
const { isDirty: isStockDirty, markPristine: markStockPristine } =
  useDirtyGuard(() => stockForm);
const stockSalesOrderOptions = computed(() => [
  { value: '', label: '不关联销售订单' },
  ...salesOrders.value
    .filter(
      s =>
        !stockForm.crmCustomerId ||
        String(s.crm_customer_id) === String(stockForm.crmCustomerId)
    )
    .map(s => ({ value: String(s.id), label: s.order_no })),
]);
const stockInvalid = computed(
  () =>
    !stockForm.crmCustomerId ||
    !stockForm.warehouseId ||
    !stockForm.rows.length ||
    stockForm.rows.some(r => !r.crmProductId || !Number(r.qty))
);
const addStockRow = () => stockForm.rows.push({ crmProductId: '', qty: '1' });
const removeStockRow = i => stockForm.rows.splice(i, 1);

const openStockCreate = () => {
  const fin = finishedWarehouseId();
  Object.assign(stockForm, {
    crmCustomerId: '',
    crmSalesOrderId: '',
    warehouseId: fin ? String(fin) : '',
    rows: [{ crmProductId: '', qty: '1' }],
  });
  loadCustomers('');
  loadProducts('');
  loadStock();
  markStockPristine();
  stockDialogRef.value?.open();
};

const submitStock = async () => {
  if (stockInvalid.value) return;
  const ok = await store.create({
    kind: 'STOCK',
    crmCustomerId: Number(stockForm.crmCustomerId),
    crmSalesOrderId: stockForm.crmSalesOrderId || null,
    warehouseId: Number(stockForm.warehouseId),
    shipmentItemsAttributes: stockForm.rows.map(r => ({
      crmProductId: Number(r.crmProductId),
      qty: Number(r.qty),
      unit: productUnit(r.crmProductId),
    })),
  });
  if (ok) {
    useAlert(`已开现货出库单 ${ok.shipmentNo}，待主管审核`);
    stockDialogRef.value?.close();
  }
};

// ── 动作 ──
const notify = async s => {
  try {
    await store.notify(s.id);
    useAlert('已通知出库，已提醒对应业务员');
  } catch (e) {
    useAlert(e.message || '通知失败');
  }
};
const ship = async s => {
  try {
    const ok = await store.ship(s.id);
    useAlert(`${ok.shipmentNo} 已出库，销售订单已回写「已出货」`);
  } catch (e) {
    useAlert(e.message || '出库失败');
  }
};
// 财务审核：先把这张单的收款情况摆出来（应收/已收/还差），别让财务自己去翻应收台账。
// 款没收齐也能放行（老客户赊账、老板特批是真实存在的），但要写理由，留痕。
// 金额是 micros（百万分之一），带千分位摆出来——外贸的数动辄六七位。
const fmtAmount = micros =>
  (Number(micros || 0) / 1e6).toLocaleString('zh-CN', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
/* ---------------- 「这张单为什么卡着」自助诊断 ---------------- */
// 入口不挂在报错旁边：用户卡住最常见的形态是「按钮根本不在」「提交完没动静」，
// 那些场景一条报错都没有。所以在流程还没走完的行上常驻一个入口，有没有报错都问得了。
// 后端只读（Mes::ShipmentDiagnosis），不改数据、不发通知。
//
// 已出库 / 已作废的不挂：这两种是终点，没有「卡着」可言。原先每行无条件常驻，
// 一屏十几行里十来行都是已出库，入口反而被当成噪音（2026-10-26 反馈：
// 「这是什么」——整列都是它，看不出是干嘛的）。
const DIAGNOSABLE = ['DRAFT', 'PENDING_APPROVAL', 'APPROVED', 'REJECTED'];
const canDiagnose = s => DIAGNOSABLE.includes(s.status);
const diagDialogRef = ref(null);
const diagRow = ref(null);
const diagResults = ref([]);
const diagLoading = ref(false);

const openDiagnose = async s => {
  diagRow.value = s;
  diagResults.value = [];
  diagLoading.value = true;
  diagDialogRef.value?.open();
  try {
    const list = await Promise.all(
      ['submit', 'approve', 'ship'].map(a =>
        MesShipmentAPI.diagnose(s.id, a).then(r =>
          camelcaseKeys(r.data?.payload || {}, { deep: true })
        )
      )
    );
    diagResults.value = list;
  } catch (error) {
    useAlert(error?.response?.data?.error || '查不出来，请稍后再试');
    diagDialogRef.value?.close();
  } finally {
    diagLoading.value = false;
  }
};

// 三次诊断问的是同一张单，所以「等谁」「通知到没到」只摆一次。
const diagSummary = computed(
  () => diagResults.value.find(r => r.waitingOn) || {}
);
const diagHours = computed(() => {
  const since = diagSummary.value?.waitingOn?.since;
  if (!since) return null;
  return Math.round((Date.now() - new Date(since).getTime()) / 36e5);
});

const approveDialogRef = ref(null);
const approving = ref(null);
const approveNote = ref('');
const approveState = ref(null);
const approveLoading = ref(false);
const openApprove = async s => {
  approving.value = s;
  approveNote.value = '';
  approveState.value = null;
  approveLoading.value = true;
  approveDialogRef.value?.open();
  try {
    // 列表行不带收款情况（逐行算回款进度是 N+1），点开时单独拉一次详情。
    approveState.value = await store.show(s.id);
  } catch {
    approveState.value = null;
  } finally {
    approveLoading.value = false;
  }
};
const approveUnpaid = computed(
  () => approveState.value && approveState.value.fully_paid === false
);
const submitApprove = async () => {
  if (approveUnpaid.value && !approveNote.value.trim()) return;
  try {
    const ok = await store.approve(
      approving.value.id,
      approveNote.value.trim() || undefined
    );
    useAlert(`${ok.shipmentNo} 已审核通过，已推仓库`);
    approveDialogRef.value?.close();
  } catch (e) {
    useAlert(e.message || '审核失败');
  }
};
const resubmit = async s => {
  try {
    const ok = await store.submitApproval(s.id);
    useAlert(`${ok.shipmentNo} 已重新提交审核`);
  } catch (e) {
    useAlert(e.message || '提交失败');
  }
};

// 驳回
const rejectDialogRef = ref(null);
const rejecting = ref(null);
const rejectReason = ref('');
const openReject = s => {
  rejecting.value = s;
  rejectReason.value = '';
  rejectDialogRef.value?.open();
};
const submitReject = async () => {
  if (!rejectReason.value.trim()) return;
  const ok = await store.reject(rejecting.value.id, rejectReason.value.trim());
  if (ok) {
    useAlert(`${ok.shipmentNo} 已驳回`);
    rejectDialogRef.value?.close();
  }
};

// 后端每页 15 条，不传 page 就只看得到最新 15 张。
const ITEMS_PER_PAGE = 15;
const currentPage = ref(1);
const totalCount = computed(() => store.getMeta?.count || 0);
// 搜索 / 状态筛选：一个月几十张单，原先这页只能翻页找（2026-10-21 仓库提的）。
// 都走服务端——列表是分页的，前端筛只能筛到当前这 15 条。
const keyword = ref('');
const statusFilter = ref('');
const STATUS_OPTIONS = [
  { value: '', label: '全部状态' },
  ...Object.entries(STATUS_LABELS).map(([value, label]) => ({ value, label })),
];
const fetchList = () =>
  store.get({
    page: currentPage.value,
    q: keyword.value.trim() || undefined,
    status: statusFilter.value || undefined,
  });
watch(currentPage, fetchList);

// 做错了要重来：待审核 / 待出库 / 已驳回的单可以退回草稿改，或整张作废。
// 已出库的不在此列（动了库存和凭证，要撤得走退货）。草稿直接删就行，不给作废。
const REVERTIBLE = ['PENDING_APPROVAL', 'APPROVED', 'REJECTED'];
const canRevertRow = s =>
  REVERTIBLE.includes(s.status) &&
  (canShip.value || isMyDoc(s) || isAdminLike.value);

const revertToDraft = async s => {
  const tip = `把 ${s.shipmentNo} 退回草稿？退回后可以改，改完要重新提交审核。`;
  // eslint-disable-next-line no-alert
  if (!window.confirm(tip)) return;
  acting.value = true;
  try {
    await MesShipmentAPI.revertToDraft(s.id);
    useAlert(`${s.shipmentNo} 已退回草稿`);
    await fetchList();
  } catch (error) {
    useAlert(error?.response?.data?.error || '退回失败');
  } finally {
    acting.value = false;
  }
};

const voidDialogRef = ref(null);
const voiding = ref(null);
const voidReason = ref('');
const openVoid = s => {
  voiding.value = s;
  voidReason.value = '';
  voidDialogRef.value?.open();
};
const submitVoid = async () => {
  if (!voidReason.value.trim()) return;
  acting.value = true;
  try {
    await MesShipmentAPI.void(voiding.value.id, voidReason.value.trim());
    useAlert(`${voiding.value.shipmentNo} 已作废，这张销售订单可以重新转单了`);
    voidDialogRef.value?.close();
    await fetchList();
  } catch (error) {
    useAlert(error?.response?.data?.error || '作废失败');
  } finally {
    acting.value = false;
  }
};

// ── 批量打印 ──
// 仓库每月把整叠出库单打出来给财务核对（2026-10-21）。一张一张点进详情再打，
// 几十张单根本没法做。勾完一次打，打完各记一次打印次数。
const selectedIds = ref([]);
const isSelected = id => selectedIds.value.includes(id);
const toggleSelect = id => {
  selectedIds.value = isSelected(id)
    ? selectedIds.value.filter(x => x !== id)
    : [...selectedIds.value, id];
};
const allSelected = computed(
  () => records.value.length > 0 && records.value.every(s => isSelected(s.id))
);
const toggleSelectAll = () => {
  const ids = records.value.map(s => s.id);
  selectedIds.value = allSelected.value
    ? selectedIds.value.filter(id => !ids.includes(id))
    : [...new Set([...selectedIds.value, ...ids])];
};
// 换页/换筛选条件后，选中的单已经不在屏幕上了，留着只会让「打印选中 N 张」对不上。
watch(records, () => {
  selectedIds.value = [];
});

const printAreaRef = ref(null);
const printSheets = ref([]);
const printing = ref(false);
const sheetRows = s =>
  (s.shipmentItems || []).map(it => ({
    sku: it.productSku,
    name: it.productName,
    spec: it.specification,
    warehouse: s.warehouseName,
    unit: it.unit,
    qty: it.qty,
    unitPrice: it.unitPrice,
    amount: it.amount,
    remark: it.remark,
  }));
const printSelected = async () => {
  const rows = records.value.filter(s => isSelected(s.id));
  if (!rows.length) return;
  printing.value = true;
  try {
    printSheets.value = rows;
    await nextTick();
    printElement(printAreaRef.value, `销售出库单 ${rows.length} 张`, {
      page: '@page{size:9.5in 5.5in;margin:8mm}',
      brandHeader: false,
    });
    // 打印对话框是浏览器自己弹的，点没点「打印」我们收不到——以「送去打印」记一次。
    await MesShipmentAPI.markPrinted(rows.map(s => s.id));
    await fetchList();
  } catch (error) {
    useAlert('打印失败，请重试');
  } finally {
    printing.value = false;
  }
};
// 换条件要回到第 1 页：筛完还停在第 3 页，看到的是空的。
const reload = () => {
  if (currentPage.value !== 1) currentPage.value = 1;
  else fetchList();
};
watch(statusFilter, reload);

// 列表上的「名称 / 数量」：一张出库单常常不止一行，第一行品名 + 「等 N 项」，
// 数量给合计——财务核的是这一车总共出了多少。
const itemSummary = s => {
  const items = s.shipmentItems || [];
  if (!items.length) return '—';
  const first = items[0].productName || '—';
  return items.length > 1 ? `${first} 等 ${items.length} 项` : first;
};
const itemQty = s =>
  (s.shipmentItems || []).reduce((acc, it) => acc + Number(it.qty || 0), 0);

onMounted(() => {
  fetchList();
  warehousesStore.get();
  const base = `/api/v1/accounts/${accountId.value}`;
  axios
    // 下拉要能选到所有在产订单：不传 per_page 后端只给最新 15 条(RESULTS_PER_PAGE)，
    // 早一点的单子在下拉里根本找不到（同 MES 其余 8 个下拉，这里一直漏了）。封顶 500。
    .get(`${base}/mes/production_orders`, { params: { per_page: 500 } })
    .then(({ data }) => {
      productionOrders.value = data?.payload || [];
    })
    .catch(() => {});
  axios
    .get(`${base}/crm/sales_orders`, { params: { per_page: 100 } })
    .then(({ data }) => {
      salesOrders.value = data?.payload || [];
    })
    .catch(() => {});
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
        销售出库
      </h1>
      <div class="flex flex-wrap items-center justify-end gap-2">
        <Input
          v-model="keyword"
          size="sm"
          placeholder="搜单号 / 订单 / 客户 / 信保单号 / 产品"
          custom-input-class="w-60"
          @keyup.enter="reload"
        />
        <SelectCard
          :model-value="statusFilter"
          :options="STATUS_OPTIONS"
          trigger-class="w-28 h-8"
          @update:model-value="v => (statusFilter = v)"
        />
        <Button label="查询" color="slate" size="sm" @click="reload" />
        <Button
          v-if="selectedIds.length"
          :label="`打印选中 ${selectedIds.length} 张`"
          color="slate"
          variant="faded"
          size="sm"
          :is-loading="printing"
          @click="printSelected"
        />
        <Button
          v-if="canOpenStock"
          label="新建现货出库"
          color="teal"
          size="sm"
          @click="openStockCreate"
        />
        <Button
          v-if="canShip"
          label="新建生产出库"
          color="iris"
          size="sm"
          @click="openCreate"
        />
      </div>
    </div>

    <MesBoardOwnerBar board-key="mes_shipments_index" />

    <HScrollButtons />
    <div
      class="flex-1 min-h-0 px-4 pb-6 overflow-auto sm:px-6 [.theme-classic_&]:sm:!px-8"
    >
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <template v-else>
        <!-- 手机卡片 -->
        <div class="flex flex-col gap-2 md:hidden">
          <div
            v-for="s in records"
            :key="s.id"
            class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl active:bg-n-alpha-1"
            @click="openView(s)"
          >
            <div class="flex items-center gap-2">
              <span class="font-medium truncate text-n-slate-12">
                {{ s.shipmentNo }}
              </span>
              <span
                class="px-2 py-0.5 rounded text-xs shrink-0"
                :class="
                  s.kind === 'STOCK'
                    ? 'bg-n-teal-3 text-n-teal-11'
                    : 'bg-n-iris-3 text-n-iris-11'
                "
              >
                {{ KIND_LABELS[s.kind] || s.kind }}
              </span>
              <span class="flex-1" />
              <MesStatusPill
                class="shrink-0"
                :label="STATUS_LABELS[s.status]"
              />
            </div>
            <div
              class="mt-2 flex flex-wrap gap-x-3 gap-y-1 text-xs text-n-slate-11"
            >
              <span>销售订单：{{ s.salesOrderNo || '—' }}</span>
              <span>客户：{{ s.customerName || '—' }}</span>
              <span>
                归属人：{{ s.productionOrderOwnerName || s.ownerName || '—' }}
              </span>
            </div>
            <div class="mt-2 flex flex-wrap justify-end gap-1">
              <Button
                label="查看"
                variant="ghost"
                size="sm"
                @click.stop="openView(s)"
              />
              <Button
                v-if="canEditRow(s)"
                label="编辑"
                variant="ghost"
                size="sm"
                @click.stop="openEdit(s)"
              />
              <template v-if="canApproveRow(s)">
                <Button
                  label="审核通过"
                  color="iris"
                  size="sm"
                  :is-loading="acting"
                  @click.stop="openApprove(s)"
                />
                <Button
                  label="驳回"
                  variant="ghost"
                  size="sm"
                  @click.stop="openReject(s)"
                />
              </template>
              <Button
                v-if="canResubmitRow(s)"
                label="重新提交"
                color="amber"
                size="sm"
                :is-loading="acting"
                @click.stop="resubmit(s)"
              />
              <Button
                v-if="
                  s.kind === 'PRODUCTION' &&
                  s.status === 'DRAFT' &&
                  canShip &&
                  !s.notifiedAt
                "
                label="通知出库"
                variant="ghost"
                size="sm"
                :is-loading="acting"
                @click.stop="notify(s)"
              />
              <Button
                v-if="canDiagnose(s)"
                label="为什么卡着"
                variant="ghost"
                color="slate"
                size="sm"
                @click.stop="openDiagnose(s)"
              />
              <Button
                v-if="canShipRow(s)"
                label="出库"
                color="iris"
                size="sm"
                :is-loading="acting"
                @click.stop="ship(s)"
              />
              <Button
                v-if="canRevertRow(s)"
                label="退回草稿"
                variant="ghost"
                color="slate"
                size="sm"
                :is-loading="acting"
                @click.stop="revertToDraft(s)"
              />
              <Button
                v-if="canRevertRow(s)"
                label="作废"
                color="ruby"
                variant="ghost"
                size="sm"
                @click.stop="openVoid(s)"
              />
              <Button
                v-if="canDeleteRow(s)"
                label="删单"
                color="ruby"
                variant="ghost"
                size="sm"
                :is-loading="acting"
                @click.stop="removeShipment(s)"
              />
            </div>
          </div>
          <div v-if="!records.length" class="py-10 text-center text-n-slate-11">
            还没有出库单。
          </div>
        </div>

        <table class="hidden w-full text-sm md:table">
          <thead>
            <tr class="text-left text-n-slate-11 border-b border-n-weak">
              <th class="px-3 py-3 w-9">
                <input
                  type="checkbox"
                  class="align-middle"
                  :checked="allSelected"
                  :disabled="!records.length"
                  @change="toggleSelectAll"
                />
              </th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">出库单号</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">类型</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">销售订单</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">客户</th>
              <th class="px-3 py-3 font-medium">名称</th>
              <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
                数量
              </th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">归属人</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">状态</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">信保单号</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">打印</th>
              <th class="px-3 py-3" />
            </tr>
          </thead>
          <tbody>
            <tr v-for="s in records" :key="s.id" class="border-b border-n-weak">
              <td class="px-3 py-3">
                <input
                  type="checkbox"
                  class="align-middle"
                  :checked="isSelected(s.id)"
                  @change="toggleSelect(s.id)"
                />
              </td>
              <td class="px-3 py-3 font-medium text-n-slate-12">
                {{ s.shipmentNo }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                <span
                  class="px-2 py-0.5 rounded text-xs"
                  :class="
                    s.kind === 'STOCK'
                      ? 'bg-n-teal-3 text-n-teal-11'
                      : 'bg-n-iris-3 text-n-iris-11'
                  "
                >
                  {{ KIND_LABELS[s.kind] || s.kind }}
                </span>
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ s.salesOrderNo || '—' }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ s.customerName || '—' }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">{{ itemSummary(s) }}</td>
              <td
                class="px-3 py-3 text-right tabular-nums whitespace-nowrap text-n-slate-11"
              >
                {{ itemQty(s) || '—' }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ s.productionOrderOwnerName || s.ownerName || '—' }}
              </td>
              <td class="px-3 py-3">
                <MesStatusPill :label="STATUS_LABELS[s.status]" />
              </td>
              <td class="px-3 py-3 whitespace-nowrap text-n-slate-11">
                {{ s.insuranceOrderNo || '—' }}
              </td>
              <!-- 打过的标次数，没打过的留一道「未打印」——仓库核对时一眼扫得出漏了哪张 -->
              <td class="px-3 py-3 whitespace-nowrap">
                <span v-if="s.printCount > 0" class="text-n-teal-11">
                  已打 {{ s.printCount }} 次
                </span>
                <span v-else class="text-n-slate-10">未打印</span>
              </td>
              <td class="px-3 py-3 text-right">
                <div class="flex justify-end gap-1">
                  <Button
                    label="查看"
                    variant="ghost"
                    size="sm"
                    @click="openView(s)"
                  />
                  <Button
                    v-if="canEditRow(s)"
                    label="编辑"
                    variant="ghost"
                    size="sm"
                    @click="openEdit(s)"
                  />
                  <template v-if="canApproveRow(s)">
                    <Button
                      label="审核通过"
                      color="iris"
                      size="sm"
                      :is-loading="acting"
                      @click="openApprove(s)"
                    />
                    <Button
                      label="驳回"
                      variant="ghost"
                      size="sm"
                      @click="openReject(s)"
                    />
                  </template>
                  <Button
                    v-if="canResubmitRow(s)"
                    label="重新提交"
                    color="amber"
                    size="sm"
                    :is-loading="acting"
                    @click="resubmit(s)"
                  />
                  <Button
                    v-if="
                      s.kind === 'PRODUCTION' &&
                      s.status === 'DRAFT' &&
                      canShip &&
                      !s.notifiedAt
                    "
                    label="通知出库"
                    variant="ghost"
                    size="sm"
                    :is-loading="acting"
                    @click="notify(s)"
                  />
                  <Button
                    v-if="canDiagnose(s)"
                    label="为什么卡着"
                    variant="ghost"
                    color="slate"
                    size="sm"
                    @click="openDiagnose(s)"
                  />
                  <Button
                    v-if="canShipRow(s)"
                    label="出库"
                    color="iris"
                    size="sm"
                    :is-loading="acting"
                    @click="ship(s)"
                  />
                  <Button
                    v-if="canRevertRow(s)"
                    label="退回草稿"
                    variant="ghost"
                    color="slate"
                    size="sm"
                    :is-loading="acting"
                    @click="revertToDraft(s)"
                  />
                  <Button
                    v-if="canRevertRow(s)"
                    label="作废"
                    color="ruby"
                    variant="ghost"
                    size="sm"
                    @click="openVoid(s)"
                  />
                  <Button
                    v-if="canDeleteRow(s)"
                    label="删单"
                    color="ruby"
                    variant="ghost"
                    size="sm"
                    :is-loading="acting"
                    @click="removeShipment(s)"
                  />
                </div>
              </td>
            </tr>
            <tr v-if="!records.length">
              <td colspan="12" class="px-3 py-10 text-center text-n-slate-11">
                还没有出库单。
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

    <!-- 生产出库（仓库从生产订单开单，原样）-->
    <Dialog
      ref="dialogRef"
      :dismissible="false"
      width="lg"
      confirm-button-color="iris"
      :title="editingId ? '编辑生产出库单' : '新建生产出库单'"
      description="选生产订单带出客户与成品，生成出库清单；出库后自动扣成品库存并回写销售订单「已出货」。"
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
          <label class="text-heading-3 text-n-slate-12">销售订单</label>
          <ComboBox
            :model-value="form.productionOrderId"
            :options="productionOrderOptions"
            placeholder="选择销售订单…"
            search-placeholder="搜 MO 号 / 销售订单 / 产品 / 客户"
            empty-state="没有匹配的生产订单"
            @update:model-value="onPickOrder"
          />
        </div>
        <div class="grid grid-cols-3 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              出库成品 <span class="text-n-ruby-11">*</span>
            </label>
            <Input v-model="form.productName" disabled />
          </div>
          <!-- 出库仓库可选：外购成品常被收进原料仓，写死成品仓就会「有货却出不了」。 -->
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              出库仓库 <span class="text-n-ruby-11">*</span>
            </label>
            <SelectCard
              size="form"
              :model-value="form.warehouseId"
              :options="warehouseOptions"
              @update:model-value="onPickWarehouse"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              出库数量 <span class="text-n-ruby-11">*</span>
            </label>
            <Input v-model="form.qty" type="number" />
          </div>
        </div>
        <p class="text-xs text-n-slate-11">
          出库清单：{{ form.productName || '（未选）' }} × {{ form.qty || 0 }}
          {{ form.unit }}
          <span
            v-if="form.crmProductId && form.warehouseId"
            :class="overAvailable ? 'text-n-ruby-11' : 'text-n-slate-10'"
          >
            · 该仓成品可用 {{ availableInWarehouse }}
          </span>
          <span v-if="materialHint" class="text-n-amber-11">{{
            materialHint
          }}</span>
        </p>
      </div>
    </Dialog>

    <!-- 现货出库（业务员开单 → 主管审核 → 仓库出库）-->
    <Dialog
      ref="stockDialogRef"
      :dismissible="false"
      width="3xl"
      overflow-y-auto
      confirm-button-color="teal"
      title="新建现货出库单"
      description="从成品库存直接出货：选客户与成品（显示现货结存），提交后经部门主管审核，通过即推仓库出库。"
      :is-loading="saving"
      :disable-confirm-button="stockInvalid"
      :dirty="isStockDirty"
      dirty-save-label="保存"
      @confirm="submitStock"
      @close="markStockPristine"
      @save="submitStock"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              客户 <span class="text-n-ruby-11">*</span>
            </label>
            <ComboBox
              v-model="stockForm.crmCustomerId"
              :options="customerOptions"
              use-api-results
              placeholder="搜索客户"
              @search="loadCustomers"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">销售订单</label>
            <SelectCard
              size="form"
              :model-value="stockForm.crmSalesOrderId"
              :options="stockSalesOrderOptions"
              @update:model-value="v => (stockForm.crmSalesOrderId = v)"
            />
          </div>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">
            出库成品仓 <span class="text-n-ruby-11">*</span>
          </label>
          <SelectCard
            size="form"
            :model-value="stockForm.warehouseId"
            :options="warehouseOptions"
            @update:model-value="v => (stockForm.warehouseId = v)"
          />
        </div>

        <div class="flex items-center justify-between">
          <span class="text-heading-2 text-n-slate-12">
            出库清单 <span class="text-n-ruby-11">*</span>
          </span>
          <Button
            label="+ 加一行"
            type="button"
            variant="ghost"
            size="sm"
            @click="addStockRow"
          />
        </div>
        <div class="grid grid-cols-12 gap-2 text-xs text-n-slate-10">
          <span class="col-span-6">成品</span>
          <span class="col-span-2">数量</span>
          <span class="col-span-3">可用现货</span>
        </div>
        <div class="flex flex-col gap-2">
          <div
            v-for="(row, i) in stockForm.rows"
            :key="i"
            class="grid items-center grid-cols-12 gap-2"
          >
            <div class="col-span-6">
              <ComboBox
                v-model="row.crmProductId"
                :options="productOptions"
                use-api-results
                placeholder="搜索成品"
                @search="loadProducts"
              />
            </div>
            <Input v-model="row.qty" type="number" class="col-span-2" />
            <span
              class="col-span-3 text-sm"
              :class="
                stockFor(row.crmProductId, stockForm.warehouseId) <
                Number(row.qty || 0)
                  ? 'text-n-ruby-11'
                  : 'text-n-slate-11'
              "
            >
              {{ stockFor(row.crmProductId, stockForm.warehouseId) }}
            </span>
            <button
              type="button"
              class="col-span-1 text-n-slate-10 hover:text-n-ruby-11"
              @click="removeStockRow(i)"
            >
              ✕
            </button>
          </div>
        </div>
        <p class="text-xs text-n-slate-11">
          「可用现货」= 结存 −
          其他待出库单预占；低于出库量的行标红。提交后即预占这批数量，别人看到的可用现货相应减少；驳回或出库后自动释放。
        </p>
      </div>
    </Dialog>

    <!-- 驳回原因 -->
    <Dialog
      ref="rejectDialogRef"
      :dismissible="false"
      width="md"
      confirm-button-color="ruby"
      title="驳回现货出库单"
      :disable-confirm-button="!rejectReason.trim()"
      @confirm="submitReject"
    >
      <div class="flex flex-col gap-2">
        <label class="text-heading-3 text-n-slate-12">
          驳回原因 <span class="text-n-ruby-11">*</span>
        </label>
        <Input
          v-model="rejectReason"
          placeholder="请填写驳回原因，退回业务员修改"
        />
      </div>
    </Dialog>

    <!-- 「这张单为什么卡着」：只读诊断，不改任何东西 -->
    <Dialog
      ref="diagDialogRef"
      width="2xl"
      :title="`${diagRow?.shipmentNo || ''} 为什么卡着`"
      description="下面是系统现在查到的实情。它只是查，不会动这张单。"
      :show-confirm-button="false"
      cancel-button-label="知道了"
    >
      <div v-if="diagLoading" class="py-6 text-center text-n-slate-11">
        正在查…
      </div>
      <div v-else class="flex flex-col gap-4">
        <div
          v-if="diagSummary.waitingOn"
          class="p-3 rounded-lg bg-n-alpha-1 border border-n-weak"
        >
          <div class="text-heading-3 text-n-slate-12">
            {{ diagSummary.waitingOn.label
            }}{{
              diagSummary.waitingOn.names.length
                ? ` — ${diagSummary.waitingOn.names.join('、')}`
                : ''
            }}
          </div>
          <div
            v-if="diagHours !== null"
            class="text-label-small text-n-slate-11"
          >
            已经等了 {{ diagHours }} 小时
          </div>
          <div
            v-if="diagSummary.notice"
            class="mt-2 text-label-small"
            :class="
              diagSummary.notice.level === 'warn'
                ? 'text-n-amber-11'
                : 'text-n-slate-11'
            "
          >
            {{ diagSummary.notice.text }}
            <span v-if="diagSummary.notice.fix" class="text-n-slate-11">
              → {{ diagSummary.notice.fix }}
            </span>
          </div>
        </div>

        <div class="flex flex-col gap-3">
          <div
            v-for="r in diagResults"
            :key="r.action"
            class="flex flex-col gap-1"
          >
            <div class="flex items-center gap-2">
              <span class="text-heading-3 text-n-slate-12">
                {{ r.actionLabel }}
              </span>
              <span
                class="text-label-small"
                :class="r.blocked ? 'text-n-ruby-11' : 'text-n-teal-11'"
              >
                {{ r.blocked ? '现在干不了' : '现在可以做' }}
              </span>
            </div>
            <div
              v-for="(b, i) in r.blockers"
              :key="i"
              class="pl-3 border-l-2 border-n-weak"
            >
              <div class="text-sm text-n-slate-12">{{ b.text }}</div>
              <div v-if="b.fix" class="text-label-small text-n-slate-11">
                → {{ b.fix }}
              </div>
            </div>
          </div>
        </div>
      </div>
    </Dialog>

    <!-- 财务审核：先看这张单的款收齐没有，再决定放不放行 -->
    <Dialog
      ref="approveDialogRef"
      :dismissible="false"
      width="md"
      title="财务审核 · 核对收款"
      confirm-button-label="审核通过"
      :disable-confirm-button="approveUnpaid && !approveNote.trim()"
      @confirm="submitApprove"
    >
      <div class="flex flex-col gap-3">
        <div
          v-if="approveLoading"
          class="py-4 text-sm text-center text-n-slate-10"
        >
          正在取收款情况…
        </div>
        <template v-else-if="approveState && approveState.receivable_state">
          <div
            class="flex flex-col gap-1 p-3 text-sm rounded-lg"
            :class="approveUnpaid ? 'bg-n-amber-2' : 'bg-n-teal-2'"
          >
            <div class="flex justify-between">
              <span class="text-n-slate-11">应收</span>
              <span class="font-medium tabular-nums text-n-slate-12">
                {{ approveState.receivable_state.currency }}
                {{ fmtAmount(approveState.receivable_state.total_micros) }}
              </span>
            </div>
            <div class="flex justify-between">
              <span class="text-n-slate-11">已收</span>
              <span class="font-medium tabular-nums text-n-slate-12">
                {{ approveState.receivable_state.currency }}
                {{ fmtAmount(approveState.receivable_state.received_micros) }}
              </span>
            </div>
            <div class="flex justify-between pt-1 border-t border-n-weak">
              <span
                :class="approveUnpaid ? 'text-n-amber-11' : 'text-n-teal-11'"
              >
                {{ approveUnpaid ? '还差' : '已收齐' }}
              </span>
              <span
                class="font-semibold tabular-nums"
                :class="approveUnpaid ? 'text-n-amber-11' : 'text-n-teal-11'"
              >
                {{ approveState.receivable_state.currency }}
                {{
                  fmtAmount(approveState.receivable_state.outstanding_micros)
                }}
              </span>
            </div>
          </div>
        </template>
        <div v-else class="p-3 text-sm rounded-lg text-n-slate-11 bg-n-alpha-1">
          这张单没挂销售订单，或财务还没给它建账——系统查不到收款情况，请自行核对后再放行。
        </div>

        <!-- 款没收齐仍可放行（赊账/特批），但必须写明理由 -->
        <div v-if="approveUnpaid" class="flex flex-col gap-2">
          <label class="text-heading-3 text-n-slate-12">
            款没收齐，放行理由 <span class="text-n-ruby-11">*</span>
          </label>
          <Input
            v-model="approveNote"
            placeholder="例：老客户赊账，已报老板同意；或 尾款已汇在途"
          />
        </div>
      </div>
    </Dialog>

    <MesViewDialog
      ref="viewDialogRef"
      :title="viewing ? `出库单 ${viewing.shipmentNo}` : '出库单明细'"
      hide-print
      :fields="viewFields"
      items-title="出库成品"
      :item-columns="VIEW_ITEM_COLS"
      :items="viewing?.shipmentItems || []"
    >
      <template #headerActions>
        <Button
          label="打印出库单"
          variant="outline"
          color="slate"
          size="sm"
          @click="printShipment"
        />
      </template>
    </MesViewDialog>

    <!-- 作废：整张单不要了。必须写原因——「这张单怎么废的」事后一定会被问到。 -->
    <Dialog
      ref="voidDialogRef"
      :dismissible="false"
      width="md"
      confirm-button-color="ruby"
      title="作废出库单"
      confirm-button-label="确认作废"
      :disable-confirm-button="!voidReason.trim()"
      @confirm="submitVoid"
    >
      <div v-if="voiding" class="flex flex-col gap-3">
        <p class="text-sm text-n-slate-11">
          {{ voiding.shipmentNo }} · {{ voiding.customerName || '—' }}
        </p>
        <div class="flex flex-col gap-2">
          <label class="text-heading-3 text-n-slate-12">
            作废原因 <span class="text-n-ruby-11">*</span>
          </label>
          <Input v-model="voidReason" placeholder="例：开错客户，重新开一张" />
        </div>
        <p class="text-xs text-n-slate-11">
          作废后这张单留在列表里可查，销售订单可以重新转单。
        </p>
      </div>
    </Dialog>

    <!-- 出库单票面：只在打印时用，平时不占版面（printElement 克隆它去打印）。 -->
    <div
      v-if="viewing"
      aria-hidden="true"
      class="fixed -left-[9999px] top-0 w-[920px]"
    >
      <MesShipmentPrintSheet
        ref="printSheetRef"
        :shipment="viewing"
        :items="printRows"
      />
    </div>

    <!-- 批量打印用的票面：勾中几张就渲染几张，printElement 把整块送去打印。 -->
    <div aria-hidden="true" class="fixed -left-[9999px] top-0 w-[920px]">
      <div ref="printAreaRef">
        <MesShipmentPrintSheet
          v-for="sheet in printSheets"
          :key="sheet.id"
          :shipment="sheet"
          :items="sheetRows(sheet)"
        />
      </div>
    </div>
  </div>
</template>
