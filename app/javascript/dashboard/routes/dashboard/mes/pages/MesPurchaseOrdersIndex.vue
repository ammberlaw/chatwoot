<script setup>
/* global axios */
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useOrderableColumns } from 'dashboard/composables/useOrderableColumns';
import { useMesPurchaseOrdersStore } from 'dashboard/stores/mes/purchaseOrders';
import { useMesSuppliersStore } from 'dashboard/stores/mes/suppliers';
import MesPurchaseOrderAPI from 'dashboard/api/mes/purchaseOrders';

import Button from 'dashboard/components-next/button/Button.vue';
import MesBoardOwnerBar from 'dashboard/components-next/mes/MesBoardOwnerBar.vue';
import { useMesRole } from 'dashboard/composables/useMesRole';
import { useMesDocOwner } from 'dashboard/composables/useMesDocOwner';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import MesViewDialog from 'dashboard/components-next/mes/MesViewDialog.vue';
import MesSupplierSummary from 'dashboard/components-next/mes/MesSupplierSummary.vue';
import MesReturnControls from 'dashboard/components-next/mes/MesReturnControls.vue';
import { useRouteQueryReentry } from 'dashboard/composables/useRouteQueryReentry';

const { accountId, accountScopedRoute } = useAccount();
const route = useRoute();
const router = useRouter();
const store = useMesPurchaseOrdersStore();

// 新建/编辑都跳建档页（整页录入，弹窗装不下一个供应商几十行料）。
const goCreate = (query = {}) =>
  router.push(accountScopedRoute('mes_purchase_order_intake_index', {}, query));
const goEdit = po =>
  router.push(
    accountScopedRoute('mes_purchase_order_intake_index', {}, { id: po.id })
  );
const { mesCan } = useMesRole();
const suppliersStore = useMesSuppliersStore();
const currentUserId = useMapGetter('getCurrentUserID');
const currentUser = useMapGetter('getCurrentUser');
// 采购金额（含税单价/总额）+ 按供应商导出（含价格发供应商）：成本敏感，仅采购岗/财务/管理员可见。
// 其余岗位（如仓管）后端已不下发金额，前端再把导出按钮藏掉，避免误点 403。
const canViewAmount = computed(
  () => mesCan('purchase') || currentUser.value?.crm_finance
);

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);

// 搜索：单号 / 供应商 / 归属人 / 生产订单 / 物料编码（后端跨字段 ILIKE）。
// 从站内通知「待审批采购」跳来时按生产订单号定位（route.query.q）。
const search = ref(route.query.q ? String(route.query.q) : '');
// 「只看我下的单」：按下单人(采购单 owner_id)筛，不是列表里的「归属人」（那是生产订单的业务员）。
// 两个采购员分主料/辅料建单，各自只想看自己那摊。
const onlyMine = ref(false);
const totalCount = computed(() => store.getMeta?.count || 0);
const fetchList = () =>
  store.get({
    q: search.value.trim() || undefined,
    owner_id: onlyMine.value ? currentUserId.value : undefined,
  });
let searchTimer = null;
watch(search, () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(fetchList, 300);
});
watch(onlyMine, fetchList);

const day = d => (d ? new Date(d).toLocaleDateString() : '—');
// micros → ¥金额（两位小数），空值给「—」。采购模块内部可见价格，销售端不涉及。
const yuan = micros =>
  micros == null || micros === ''
    ? '—'
    : `¥${(micros / 1e6).toLocaleString('zh-CN', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })}`;

// 单号旁那个红色感叹号原来只有一句「采购异常」，看不出哪里异常——而采购员填的说明
// 就在单据里，直接带进悬停提示；没填说明的就把这个标记本身讲清楚。
const exceptionTip = p => {
  const note = (p.exceptionNote || '').trim();
  return note
    ? `采购异常：${note}`
    : '采购异常：采购员标记了这张单有问题（交期、价格、缺货等），但没填说明——可在「编辑」里补上';
};

const STATUS_LABELS = {
  DRAFT: '草稿',
  SUBMITTED: '已下单',
  PARTIAL_RECEIVED: '部分到货',
  RECEIVED: '已到货',
  CANCELLED: '已取消',
};

// 审批状态（总经理一级）：与收货状态正交。
const APPROVAL_LABELS = {
  DRAFT: '草稿',
  PENDING_GM: '待总经理审批',
  APPROVED: '已通过',
  REJECTED: '已驳回',
};
const APPROVAL_COLORS = {
  DRAFT: 'text-n-slate-11',
  PENDING_GM: 'text-n-amber-11',
  APPROVED: 'text-n-teal-11',
  REJECTED: 'text-n-ruby-11',
};

// 提交审批：草稿/被驳回可提交（制单人操作）。
const submitForApproval = async po => {
  try {
    await MesPurchaseOrderAPI.submit(po.id);
    useAlert('已提交总经理审批');
    fetchList();
  } catch {
    useAlert('提交失败，请重试');
  }
};
// 总经理通过。
const approvePo = async po => {
  try {
    await MesPurchaseOrderAPI.approve(po.id);
    useAlert('已通过，库存已记在途');
    fetchList();
  } catch {
    useAlert('审批失败，请重试');
  }
};
// 总经理驳回（填原因）。
const rejectPo = async po => {
  // eslint-disable-next-line no-alert
  const reason = window.prompt('请填写驳回原因');
  if (reason === null) return;
  try {
    await MesPurchaseOrderAPI.reject(po.id, reason);
    useAlert('已驳回');
    fetchList();
  } catch {
    useAlert('驳回失败，请重试');
  }
};
// 我是本单当前审批人（总经理）吗？→ 显示通过/驳回。
const canApprove = po =>
  po.approvalStatus === 'PENDING_GM' &&
  po.currentApproverId === currentUserId.value;
// 我能提交本单审批吗？→ 制单人本人、草稿或被驳回。
const canSubmit = po =>
  mesCan('purchase') &&
  ['DRAFT', 'REJECTED'].includes(po.approvalStatus) &&
  po.ownerId === currentUserId.value;

// 按供应商拆单导出 PDF：后端用公司原始 .xlsx 模板 1:1 填充（含公章，抬头/税口径按各自 bill_entity）
// → Gotenberg 转 PDF。单个供应商直接下 PDF；多个供应商打包 zip（每家一份 PDF）。

// 只有审批通过的采购单才能预览/导出——这份 PDF 是直接发给供应商的。
const canExportRow = po => po.approvalStatus === 'APPROVED';

// —— 预览 / 导出 ——
//
// 预览直接显示后端生成的真 PDF（而不是另做一套 HTML 版式）：
// 预览和最终文件是同一份，公章、字体、线条不会两套口径。
// 采购员在预览里核对完，截图就能发供应商群——不用先导文件、再打开、再截图。
const previewDialogRef = ref(null);
const previewPo = ref(null);
const previewSuppliers = ref([]); // [{ id, name, itemCount, defaultEntity }]
const previewChecked = ref([]); // 勾选导出/预览的供应商 id
// 这次出单各家用哪个抬头：{ 供应商id: 'wintouch'|'liontek' }。默认取供应商档案，
// 这里改只影响这一次导出的单（比如对方临时要开公司票），不会写回档案。
const previewEntities = ref({});
const previewUrl = ref('');
const previewLoading = ref(false);
// 连续勾选会连发几次请求，先发的可能后回，把旧结果盖在新结果上
// （实测：勾 2 家却显示 3 页，且停下来也不会自己纠正）
// 每次请求发号，回来时只认最后一号。
let previewSeq = 0;

// 两个开票主体：对公=联迪（含税13%、带公章的采购合同），对私=联合触控（未税采购订单）。
const ENTITY_OPTIONS = [
  { value: 'wintouch', label: '深圳联合触控 · 未税' },
  { value: 'liontek', label: '东莞联迪 · 含税（公章）' },
];

const revokePreview = () => {
  if (previewUrl.value) URL.revokeObjectURL(previewUrl.value);
  previewUrl.value = '';
};

// 「未指定供应商」那组后端的 key 是 nil，这里统一用 0 表示。
const supplierKey = s => Number(s.id || 0);

// 导出/预览走 blob，422 的 JSON 也在 Blob 里，要读出来才知道后端为什么拒绝。
const extractExportError = async error => {
  const data = error?.response?.data;
  if (data instanceof Blob) {
    try {
      return JSON.parse(await data.text()).error;
    } catch {
      return null;
    }
  }
  return data?.error || null;
};

const fetchPreviewPdf = async () => {
  if (!previewPo.value || !previewChecked.value.length) {
    revokePreview();
    return;
  }
  previewSeq += 1;
  const seq = previewSeq;
  previewLoading.value = true;
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/purchase_orders/${previewPo.value.id}/export`,
      {
        responseType: 'blob',
        params: {
          supplier_ids: previewChecked.value,
          bill_entities: previewEntities.value,
        },
        // indexes:false → supplier_ids[]=1&supplier_ids[]=2（Rails 解析成数组）。
        // 用 null 会生成 supplier_ids=1&supplier_ids=2，Rails 只取最后一个，
        // 结果不管勾几家都只导出一家。
        paramsSerializer: { indexes: false },
      }
    );
    if (seq !== previewSeq) return; // 已有更新的请求在路上，丢弃这次结果
    revokePreview();
    previewUrl.value = URL.createObjectURL(data);
  } catch (error) {
    // 422 的原因（如「有物料未指定供应商」）走 blob，得先读出来再弹，否则只剩一句「失败」。
    const msg = await extractExportError(error);
    if (seq === previewSeq) useAlert(msg || '预览生成失败，请重试');
  } finally {
    if (seq === previewSeq) previewLoading.value = false;
  }
};

// 一张采购单挂多张生产订单时，列表只露前两张，免得把列撑开；全部挂 title 上。
const orderNosLabel = nos => {
  const list = nos || [];
  if (!list.length) return '—';
  return list.length <= 2
    ? list.join('、')
    : `${list.slice(0, 2).join('、')} 等 ${list.length} 张`;
};

const { isMyDoc } = useMesDocOwner();
// 谁制单谁改：非下单人不露编辑/删除（后端同样拦）。
const canEditRow = po => mesCan('purchase') && isMyDoc(po);
// 删草稿：后端 deletable? 才是准绳（这里只决定按钮露不露），删不掉会把后端的理由弹出来。
const canDelete = po =>
  mesCan('purchase') &&
  isMyDoc(po) &&
  po.status === 'DRAFT' &&
  ['DRAFT', 'REJECTED'].includes(po.approvalStatus);

const removeOrder = async po => {
  if (!window.confirm(`确定删除草稿采购单「${po.poNo}」？删了不可恢复。`))
    return;
  try {
    await store.delete(po.id);
    useAlert(`已删除 ${po.poNo}`);
    fetchList();
  } catch (error) {
    useAlert(error?.message || '删除失败');
  }
};

const openPreview = async po => {
  previewPo.value = po;
  previewSuppliers.value = [];
  previewChecked.value = [];
  previewEntities.value = {};
  revokePreview();
  previewDialogRef.value?.open();
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/purchase_orders/${po.id}/export_data`
    );
    previewSuppliers.value = (data?.payload?.suppliers || []).map(s => ({
      id: s.supplier_id || 0,
      name: s.name,
      itemCount: (s.items || []).length,
      defaultEntity: s.default_bill_entity || 'wintouch',
    }));
    previewEntities.value = Object.fromEntries(
      previewSuppliers.value.map(s => [supplierKey(s), s.defaultEntity])
    );
    // 默认全选：多数时候就是整单发出去，勾选是为了「只发某一家」。
    // 「未指定供应商」那组导不出来，默认不勾，剩下几家照常预览，不至于整个空白。
    previewChecked.value = previewSuppliers.value
      .filter(s => s.id)
      .map(supplierKey);
    await fetchPreviewPdf();
  } catch {
    useAlert('读取单据失败，请重试');
  }
};

const downloadPreview = async () => {
  if (!previewUrl.value || !previewPo.value) return;
  const a = document.createElement('a');
  a.href = previewUrl.value;
  const n = previewChecked.value.length;
  const one = previewSuppliers.value.find(
    s => supplierKey(s) === previewChecked.value[0]
  );
  a.download = `采购单-${previewPo.value.poNo}-${n === 1 ? one?.name : `${n}家供应商`}.pdf`;
  a.click();
  // 真导出了才计次——列表那列的数字就等于「这单传出去过几次」。记次失败不影响下载。
  try {
    await axios.post(
      `/api/v1/accounts/${accountId.value}/mes/purchase_orders/${previewPo.value.id}/mark_exported`
    );
    fetchList();
  } catch {
    // 忽略：计次只是辅助，文件已经下下来了
  }
};

// 只读查看
const viewDialogRef = ref(null);
const viewing = ref(null);
const openView = po => {
  viewing.value = po;
  viewDialogRef.value?.open();
};
const viewFields = computed(() => {
  const p = viewing.value || {};
  return [
    { label: '采购单号', value: p.poNo },
    { label: '供应商', value: (p.supplierNames || []).join('、') || '—' },
    { label: '生产订单', value: p.productionOrderNo },
    { label: '归属人', value: p.productionOrderOwnerName },
    { label: '收货状态', value: STATUS_LABELS[p.status] || p.status },
    { label: '采购总额', value: yuan(p.totalAmountMicros) },
    {
      label: '审批状态',
      value: APPROVAL_LABELS[p.approvalStatus] || '—',
    },
    { label: '审批总经理', value: p.gmName || '—' },
    { label: '审批意见', value: p.gmComment || '—' },
    { label: '回复交期', value: day(p.expectedDate) },
    { label: '交货时间', value: day(p.deliveryDate) },
    {
      label: '异常',
      value: p.hasException ? p.exceptionNote || '有异常' : '无',
    },
    { label: '下单人', value: p.ownerName },
    { label: '备注', value: p.remark },
  ];
});
// 列表两种看法：「按单」一行一张采购单（原样），「按明细」一行一条料——
// 对标金蝶采购订单的明细视图。用户原话：「只能看到供应商和采购单号，物料啥也看不出」。
const viewMode = ref('order'); // order | item
const VIEW_MODES = [
  { key: 'order', label: '按单' },
  { key: 'item', label: '按明细' },
];

// 按单视图的列（可拖拽改顺序，顺序按人记在本机）。操作列固定在最后，不参与拖拽。
const ORDER_COLUMN_DEFS = [
  { key: 'idx', label: '#', tdClass: 'px-3 py-3 tabular-nums text-n-slate-10' },
  {
    key: 'poNo',
    label: '采购单号',
    tdClass: 'px-3 py-3 font-medium text-n-slate-12',
  },
  { key: 'suppliers', label: '供应商', tdClass: 'px-3 py-3 text-n-slate-11' },
  { key: 'order', label: '生产订单', tdClass: 'px-3 py-3 text-n-slate-11' },
  { key: 'owner', label: '归属人', tdClass: 'px-3 py-3 text-n-slate-11' },
  {
    key: 'creator',
    label: '下单人',
    tdClass: 'px-3 py-3 whitespace-nowrap text-n-slate-11',
  },
  { key: 'status', label: '收货状态', tdClass: 'px-3 py-3 text-n-slate-11' },
  {
    key: 'total',
    label: '总额',
    thClass: 'text-right',
    tdClass: 'px-3 py-3 text-right whitespace-nowrap text-n-slate-12',
  },
  {
    key: 'exports',
    label: '导出',
    thClass: 'text-center',
    tdClass: 'px-3 py-3 text-center tabular-nums whitespace-nowrap',
  },
  { key: 'approval', label: '审批', tdClass: 'px-3 py-3 whitespace-nowrap' },
  { key: 'expected', label: '回复交期', tdClass: 'px-3 py-3 text-n-slate-11' },
  { key: 'delivery', label: '交货时间', tdClass: 'px-3 py-3 text-n-slate-11' },
  // 对内备注：核对生产单时要看的就是这句，原来只能点进详情才看得到
  {
    key: 'internalRemark',
    label: '对内备注',
    tdClass: 'px-3 py-3 text-n-slate-11 max-w-[16rem] truncate',
  },
  {
    key: 'remark',
    label: '备注',
    tdClass: 'px-3 py-3 text-n-slate-11 max-w-[16rem] truncate',
  },
];
const {
  orderedColumns: orderCols,
  isDragging: isOrderColDragging,
  onColDragStart: onOrderColDragStart,
  onColDrop: onOrderColDrop,
  resetOrder: resetOrderCols,
} = useOrderableColumns(ORDER_COLUMN_DEFS, 'mes.poListCols.v1');

// 明细视图的列。
const ITEM_COLUMN_DEFS = [
  { key: 'idx', label: '#', tdClass: 'px-3 py-2 tabular-nums text-n-slate-10' },
  {
    key: 'poNo',
    label: '采购单号',
    tdClass: 'px-3 py-2 font-medium text-n-slate-12',
  },
  { key: 'supplier', label: '供应商', tdClass: 'px-3 py-2 text-n-slate-11' },
  { key: 'code', label: '物料编码', tdClass: 'px-3 py-2 text-n-slate-11' },
  { key: 'name', label: '名称', tdClass: 'px-3 py-2 text-n-slate-12' },
  {
    key: 'spec',
    label: '规格型号',
    tdClass: 'px-3 py-2 text-n-slate-11 max-w-[18rem] truncate',
  },
  { key: 'aux', label: '辅助属性', tdClass: 'px-3 py-2 text-n-slate-11' },
  {
    key: 'qty',
    label: '采购量',
    thClass: 'text-right',
    tdClass: 'px-3 py-2 text-right tabular-nums text-n-slate-12',
  },
  {
    key: 'received',
    label: '已到料',
    thClass: 'text-right',
    tdClass: 'px-3 py-2 text-right tabular-nums text-n-slate-11',
  },
  { key: 'unit', label: '单位', tdClass: 'px-3 py-2 text-n-slate-11' },
  {
    key: 'rate',
    label: '单价',
    thClass: 'text-right',
    tdClass: 'px-3 py-2 text-right tabular-nums text-n-slate-11',
  },
  {
    key: 'amount',
    label: '金额',
    thClass: 'text-right',
    tdClass: 'px-3 py-2 text-right tabular-nums text-n-slate-12',
  },
  { key: 'order', label: '生产订单', tdClass: 'px-3 py-2 text-n-slate-11' },
  { key: 'arrival', label: '实际到料', tdClass: 'px-3 py-2 text-n-slate-11' },
  {
    key: 'itemRemark',
    label: '备注',
    tdClass: 'px-3 py-2 text-n-slate-11 max-w-[16rem] truncate',
  },
];
const {
  orderedColumns: itemCols,
  isDragging: isItemColDragging,
  onColDragStart: onItemColDragStart,
  onColDrop: onItemColDrop,
  resetOrder: resetItemCols,
} = useOrderableColumns(ITEM_COLUMN_DEFS, 'mes.poItemCols.v1');

// 把当页采购单摊平成「一行一条料」。只摊当页，不额外请求——列表本来就带明细。
const itemRows = computed(() =>
  records.value.flatMap(po =>
    (po.purchaseItems || []).map(it => ({
      key: `${po.id}-${it.id}`,
      po,
      poNo: po.poNo,
      supplier: it.supplierName || '—',
      code: it.productSku || it.materialNo || '—',
      name: it.productName || it.materialName || '—',
      spec: it.specification || '—',
      aux: it.auxAttributeName || '—',
      qty: it.qty,
      received: it.receivedQty,
      unit: it.unit || '',
      rate: it.rateMicros,
      amount: it.amountMicros,
      arrival: it.arrivalDate,
      itemRemark: it.remark || '—',
    }))
  )
);

const VIEW_ITEM_COLS = [
  { label: '类型', key: 'typeLabel' },
  { label: '编码', key: 'code' },
  { label: '名称', key: 'name' },
  { label: '规格型号', key: 'spec' },
  { label: '供应商', key: 'supplierName' },
  { label: '采购量', key: 'qty', align: 'right' },
  { label: '已到料', key: 'receivedQty', align: 'right' },
  { label: '单位', key: 'unit' },
  { label: '单价', key: 'rate', align: 'right' },
  { label: '税率', key: 'taxRate', align: 'right' },
  { label: '金额', key: 'amount', align: 'right' },
  { label: '实际到料时间', key: 'arrival' },
  { label: '备注', key: 'remark' },
];
// 查看明细按供应商归堆：一张单挂十几家供应商时，混排根本看不出哪几行是同一家的
// （预览页就是按供应商分页的，这里对齐同一口径）。
const viewItems = computed(() =>
  [...(viewing.value?.purchaseItems || [])]
    .sort((a, b) =>
      (a.supplierName || 'zzz').localeCompare(b.supplierName || 'zzz', 'zh')
    )
    .map(it => ({
      typeLabel: it.itemType === 'PRODUCT' ? '成品(外购)' : '物料',
      code: it.productSku || it.materialNo || '—',
      name: it.productName || it.materialName || '—',
      spec: it.specification || '—',
      supplierName: it.supplierName || '—',
      qty: it.qty,
      receivedQty: it.receivedQty,
      unit: it.unit,
      rate: it.rateMicros
        ? `${yuan(it.rateMicros)}${it.priceTaxIncluded ? '(含税)' : ''}`
        : '—',
      taxRate: it.supplierTaxRate ? `${it.supplierTaxRate}%` : '—',
      amount: yuan(it.amountMicros),
      arrival: day(it.arrivalDate),
      remark: it.remark,
    }))
);

const productionOrders = ref([]);

onMounted(async () => {
  fetchList();
  // 供应商下拉需全量，默认分页只出第一页会漏选。
  suppliersStore.get({ per_page: 500 });
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/production_orders`,
      // 不传 per_page 后端只给最新 15 条,早的单子在下拉里选不到。
      { params: { per_page: 500 } }
    );
    productionOrders.value = data?.payload || [];
  } catch {
    productionOrders.value = [];
  }
  // 从 BOM 页「新建成品采购单」跳来：转到建档页，参数原样带过去。
  if (route.query.new === 'product' && mesCan('purchase')) {
    router.replace({ query: {} });
    goCreate({ new: 'product' });
  }
});

// 从站内通知带着新单号再次进来：本页在 keep-alive 里缓存着，onMounted 不会再跑，
// 不补这一道的话搜索框还是上次的值、列表也不重拉。
useRouteQueryReentry(query => {
  search.value = query.q ? String(query.q) : '';
  fetchList();
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between px-4 py-3 sm:px-6 sm:py-4">
      <h1 class="text-xl font-semibold text-n-slate-12">采购单</h1>
      <div class="flex items-center gap-2">
        <!-- 按单 / 按明细：核对物料时要的是明细那一屏（对标金蝶） -->
        <div class="flex items-center h-8 gap-1 px-1 rounded-lg bg-n-alpha-1">
          <button
            v-for="m in VIEW_MODES"
            :key="m.key"
            type="button"
            class="h-6 px-2.5 text-xs transition-colors rounded-md whitespace-nowrap"
            :class="
              viewMode === m.key
                ? 'bg-n-solid-1 text-n-slate-12 font-medium shadow-sm'
                : 'text-n-slate-11 hover:text-n-slate-12'
            "
            @click="viewMode = m.key"
          >
            {{ m.label }}
          </button>
        </div>
        <button
          type="button"
          class="text-xs text-n-slate-10 hover:text-n-iris-11"
          title="把表头顺序恢复成默认"
          @click="viewMode === 'order' ? resetOrderCols() : resetItemCols()"
        >
          恢复默认列序
        </button>
        <Button
          v-if="mesCan('purchase')"
          label="新建采购单"
          color="iris"
          size="sm"
          @click="goCreate()"
        />
      </div>
    </div>

    <MesBoardOwnerBar board-key="mes_purchase_orders_index" />

    <!-- 搜索：单号/供应商/归属人/生产订单/物料编码 -->
    <div class="flex items-center gap-2 px-4 pt-1 pb-2 sm:px-6">
      <input
        v-model="search"
        type="text"
        placeholder="搜索单号 / 供应商 / 归属人 / 生产订单 / 物料编码"
        class="w-80 h-9 px-3 mb-0 text-sm rounded-lg reset-base outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-9 hover:outline-n-brand focus:outline-n-brand"
      />
      <label
        class="flex items-center gap-1.5 text-sm cursor-pointer select-none text-n-slate-11"
      >
        <input v-model="onlyMine" type="checkbox" class="reset-base w-3.5" />
        只看我下的单
      </label>
      <span class="text-sm text-n-slate-11">共 {{ totalCount }} 条</span>
    </div>

    <div class="flex-1 min-h-0 px-4 pb-4 overflow-auto sm:px-6 sm:pb-6">
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <template v-else>
        <div class="flex flex-col gap-2 md:hidden">
          <div
            v-for="p in records"
            :key="p.id"
            class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl active:bg-n-alpha-1"
            @click="openView(p)"
          >
            <div class="flex items-center gap-2">
              <span class="font-medium truncate text-n-slate-12">
                {{ p.poNo }}
              </span>
              <span
                v-if="p.hasException"
                v-tooltip.top="exceptionTip(p)"
                class="text-xs cursor-help shrink-0 text-n-ruby-11"
              >
                ⚠
              </span>
              <span class="text-xs shrink-0 text-n-slate-11">
                {{ STATUS_LABELS[p.status] }}
              </span>
              <span
                class="text-xs shrink-0"
                :class="APPROVAL_COLORS[p.approvalStatus]"
              >
                {{ APPROVAL_LABELS[p.approvalStatus] || '' }}
              </span>
              <span class="flex-1" />
              <div class="flex gap-1 shrink-0" @click.stop>
                <Button
                  v-if="canSubmit(p)"
                  label="提交审批"
                  color="iris"
                  size="sm"
                  @click="submitForApproval(p)"
                />
                <Button
                  v-if="canApprove(p)"
                  label="通过"
                  color="iris"
                  size="sm"
                  @click="approvePo(p)"
                />
                <Button
                  v-if="canApprove(p)"
                  label="驳回"
                  color="ruby"
                  variant="outline"
                  size="sm"
                  @click="rejectPo(p)"
                />
                <Button
                  v-if="canEditRow(p)"
                  label="编辑"
                  variant="ghost"
                  size="sm"
                  @click="goEdit(p)"
                />
                <MesReturnControls
                  :record="p"
                  :store="store"
                  :can-manage="mesCan('purchase')"
                />
              </div>
            </div>
            <div class="mt-1 text-xs text-n-slate-11">
              <MesSupplierSummary :names="p.supplierNames || []" />
            </div>
            <div class="flex flex-wrap mt-1 gap-3 text-xs text-n-slate-11">
              <span>生产订单：{{ p.productionOrderNo || '—' }}</span>
              <span>归属人：{{ p.productionOrderOwnerName || '—' }}</span>
              <span>下单人：{{ p.ownerName || '—' }}</span>
            </div>
            <div class="flex flex-wrap mt-1 gap-3 text-xs text-n-slate-11">
              <span>回复交期：{{ day(p.expectedDate) }}</span>
              <span>交货：{{ day(p.deliveryDate) }}</span>
              <span>总额：{{ yuan(p.totalAmountMicros) }}</span>
            </div>
          </div>
          <div v-if="!records.length" class="py-10 text-center text-n-slate-11">
            还没有采购单。
          </div>
        </div>
        <!-- 按单视图：列可拖拽改顺序（顺序按人记在本机），操作列固定在最后 -->
        <table
          v-if="viewMode === 'order'"
          class="hidden w-full text-sm whitespace-nowrap md:table"
        >
          <thead>
            <tr class="text-left text-n-slate-11 border-b border-n-weak">
              <th
                v-for="col in orderCols"
                :key="col.key"
                draggable="true"
                class="px-3 py-3 font-medium transition-colors cursor-move select-none whitespace-nowrap"
                :class="[
                  col.thClass,
                  isOrderColDragging(col.key) ? 'opacity-40' : '',
                ]"
                title="拖动可调整列顺序"
                @dragstart="onOrderColDragStart(col.key)"
                @dragover.prevent
                @drop="onOrderColDrop(col.key)"
              >
                {{ col.label }}
              </th>
              <th class="px-3 py-3" />
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="(p, i) in records"
              :key="p.id"
              class="border-b border-n-weak"
            >
              <td v-for="col in orderCols" :key="col.key" :class="col.tdClass">
                <template v-if="col.key === 'idx'">{{ i + 1 }}</template>
                <template v-else-if="col.key === 'poNo'">
                  {{ p.poNo }}
                  <span
                    v-if="p.hasException"
                    v-tooltip.top="exceptionTip(p)"
                    class="ml-1 text-xs cursor-help text-n-ruby-11"
                  >
                    ⚠
                  </span>
                </template>
                <template v-else-if="col.key === 'suppliers'">
                  <MesSupplierSummary :names="p.supplierNames || []" />
                </template>
                <template v-else-if="col.key === 'order'">
                  <span :title="(p.relatedProductionOrderNos || []).join('、')">
                    {{ orderNosLabel(p.relatedProductionOrderNos) }}
                  </span>
                </template>
                <template v-else-if="col.key === 'owner'">
                  {{ p.productionOrderOwnerName || '—' }}
                </template>
                <template v-else-if="col.key === 'creator'">
                  {{ p.ownerName || '—' }}
                </template>
                <template v-else-if="col.key === 'status'">
                  {{ STATUS_LABELS[p.status] }}
                </template>
                <template v-else-if="col.key === 'total'">
                  {{ yuan(p.totalAmountMicros) }}
                </template>
                <template v-else-if="col.key === 'exports'">
                  <span
                    v-if="p.exportCount"
                    class="px-1.5 py-0.5 text-xs rounded-md bg-n-teal-3 text-n-teal-11"
                    :title="`最近一次 ${day(p.lastExportedAt) || '—'}`"
                  >
                    {{ p.exportCount }}
                  </span>
                  <span v-else class="text-xs text-n-slate-10">未导出</span>
                </template>
                <template v-else-if="col.key === 'approval'">
                  <span :class="APPROVAL_COLORS[p.approvalStatus]">
                    {{ APPROVAL_LABELS[p.approvalStatus] || '—' }}
                  </span>
                </template>
                <template v-else-if="col.key === 'expected'">
                  {{ day(p.expectedDate) }}
                </template>
                <template v-else-if="col.key === 'delivery'">
                  {{ day(p.deliveryDate) }}
                </template>
                <template v-else-if="col.key === 'internalRemark'">
                  <span :title="p.internalRemark || ''">
                    {{ p.internalRemark || '—' }}
                  </span>
                </template>
                <template v-else-if="col.key === 'remark'">
                  <span :title="p.remark || ''">{{ p.remark || '—' }}</span>
                </template>
              </td>
              <td class="px-3 py-3 text-right whitespace-nowrap">
                <div
                  class="flex flex-nowrap justify-end gap-1 [&>button]:shrink-0"
                >
                  <Button
                    label="查看"
                    variant="ghost"
                    size="sm"
                    @click="openView(p)"
                  />
                  <Button
                    v-if="canSubmit(p)"
                    label="提交审批"
                    color="iris"
                    size="sm"
                    @click="submitForApproval(p)"
                  />
                  <Button
                    v-if="canApprove(p)"
                    label="通过"
                    color="iris"
                    size="sm"
                    @click="approvePo(p)"
                  />
                  <Button
                    v-if="canApprove(p)"
                    label="驳回"
                    color="ruby"
                    variant="outline"
                    size="sm"
                    @click="rejectPo(p)"
                  />
                  <Button
                    v-if="canEditRow(p)"
                    label="编辑"
                    variant="ghost"
                    size="sm"
                    @click="goEdit(p)"
                  />
                  <!-- 没过审不给预览/导出：这是发给供应商的那份文件，审批没过就能发出去
                       等于审批形同虚设。后端也拦（ensure_approved_before_export!），
                       这里灰掉只是让人不用点了才知道。 -->
                  <Button
                    v-if="canViewAmount"
                    label="预览 / 导出"
                    variant="ghost"
                    size="sm"
                    :disabled="!canExportRow(p)"
                    :title="canExportRow(p) ? '' : '审批通过后才能预览/导出'"
                    @click="openPreview(p)"
                  />
                  <MesReturnControls
                    :record="p"
                    :store="store"
                    :can-manage="mesCan('purchase')"
                  />
                  <!-- 废稿清理：只有未提审、未到过货的草稿能删，其余走「退回」留痕。
                       操作列已经很挤，这里只放图标。 -->
                  <button
                    v-if="canDelete(p)"
                    type="button"
                    title="删除草稿"
                    class="i-lucide-trash-2 size-4 shrink-0 text-n-slate-10 hover:text-n-ruby-11"
                    @click="removeOrder(p)"
                  />
                </div>
              </td>
            </tr>
            <tr v-if="!records.length">
              <td
                :colspan="orderCols.length + 1"
                class="px-3 py-10 text-center text-n-slate-11"
              >
                还没有采购单。
              </td>
            </tr>
          </tbody>
        </table>

        <!-- 明细视图：一行一条料（对标金蝶采购订单明细）。数据来自当页采购单自带的
             明细，不额外请求；列同样可拖拽。 -->
        <table v-else class="hidden w-full text-sm whitespace-nowrap md:table">
          <thead>
            <tr class="text-left text-n-slate-11 border-b border-n-weak">
              <th
                v-for="col in itemCols"
                :key="col.key"
                draggable="true"
                class="px-3 py-2 font-medium transition-colors cursor-move select-none whitespace-nowrap"
                :class="[
                  col.thClass,
                  isItemColDragging(col.key) ? 'opacity-40' : '',
                ]"
                title="拖动可调整列顺序"
                @dragstart="onItemColDragStart(col.key)"
                @dragover.prevent
                @drop="onItemColDrop(col.key)"
              >
                {{ col.label }}
              </th>
              <th class="px-3 py-2" />
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="(r, i) in itemRows"
              :key="r.key"
              class="border-b border-n-weak [&:hover>td]:bg-n-alpha-1"
            >
              <td v-for="col in itemCols" :key="col.key" :class="col.tdClass">
                <template v-if="col.key === 'idx'">{{ i + 1 }}</template>
                <template v-else-if="col.key === 'poNo'">{{ r.poNo }}</template>
                <template v-else-if="col.key === 'supplier'">
                  {{ r.supplier }}
                </template>
                <template v-else-if="col.key === 'code'">{{ r.code }}</template>
                <template v-else-if="col.key === 'name'">{{ r.name }}</template>
                <template v-else-if="col.key === 'spec'">
                  <span :title="r.spec">{{ r.spec }}</span>
                </template>
                <template v-else-if="col.key === 'aux'">{{ r.aux }}</template>
                <template v-else-if="col.key === 'qty'">{{ r.qty }}</template>
                <template v-else-if="col.key === 'received'">
                  {{ r.received ?? '—' }}
                </template>
                <template v-else-if="col.key === 'unit'">{{ r.unit }}</template>
                <template v-else-if="col.key === 'rate'">
                  {{ canViewAmount ? yuan(r.rate) : '—' }}
                </template>
                <template v-else-if="col.key === 'amount'">
                  {{ canViewAmount ? yuan(r.amount) : '—' }}
                </template>
                <template v-else-if="col.key === 'order'">
                  {{ orderNosLabel(r.po.relatedProductionOrderNos) }}
                </template>
                <template v-else-if="col.key === 'arrival'">
                  {{ day(r.arrival) }}
                </template>
                <template v-else-if="col.key === 'itemRemark'">
                  <span :title="r.itemRemark">{{ r.itemRemark }}</span>
                </template>
              </td>
              <td class="px-3 py-2 text-right whitespace-nowrap">
                <Button
                  label="查看"
                  variant="ghost"
                  size="sm"
                  @click="openView(r.po)"
                />
              </td>
            </tr>
            <tr v-if="!itemRows.length">
              <td
                :colspan="itemCols.length + 1"
                class="px-3 py-10 text-center text-n-slate-11"
              >
                这一页的采购单还没有明细。
              </td>
            </tr>
          </tbody>
        </table>
      </template>
    </div>

    <!-- 预览 / 导出：直接显示后端生成的真 PDF，勾谁导谁，多家合成一份 -->
    <Dialog
      ref="previewDialogRef"
      :dismissible="false"
      width="6xl"
      :show-confirm-button="false"
      cancel-button-label="关闭"
      :title="previewPo ? `采购单 ${previewPo.poNo} · 预览` : '采购单预览'"
      @close="revokePreview"
    >
      <!-- 左右布局：供应商勾选在左边窄栏，预览占右边大块。
           原来是上下堆叠，预览只剩 62vh 又被说明文字挤，字小得看不清。 -->
      <div class="flex flex-col gap-3 lg:flex-row lg:h-[76vh]">
        <div class="flex flex-col gap-2 lg:w-72 shrink-0 lg:overflow-y-auto">
          <p class="text-xs leading-relaxed text-n-slate-11">
            抬头默认按各供应商档案选（对公「东莞市联迪科技」含税带公章，对私「深圳联合触控」未税），
            这里改只影响这次导出的单，不会写回供应商档案。
          </p>

          <div
            v-if="previewSuppliers.length"
            class="flex flex-col gap-2 p-2 rounded-lg bg-n-alpha-1"
          >
            <div
              v-for="s in previewSuppliers"
              :key="s.id"
              class="flex flex-col gap-1 text-xs text-n-slate-11"
            >
              <label class="flex items-center gap-1.5 cursor-pointer">
                <input
                  v-if="previewSuppliers.length > 1"
                  v-model="previewChecked"
                  type="checkbox"
                  :value="Number(s.id || 0)"
                  @change="fetchPreviewPdf"
                />
                <span class="font-medium truncate text-n-slate-12">
                  {{ s.name }}
                </span>
                <span class="shrink-0 text-n-slate-10"
                  >{{ s.itemCount }} 项</span
                >
              </label>
              <!-- 未指定供应商的那组不能导（会被凑成一份发错家），直接在这儿说清楚 -->
              <span v-if="!s.id" class="text-n-ruby-11">
                这几项还没指定供应商，导不出——请回「编辑」里逐行选供应商
              </span>
              <select
                v-model="previewEntities[Number(s.id || 0)]"
                class="!h-7 !mb-0 !py-0.5 !text-xs ltr:!pl-2"
                @change="fetchPreviewPdf"
              >
                <option
                  v-for="o in ENTITY_OPTIONS"
                  :key="o.value"
                  :value="o.value"
                >
                  {{ o.label }}
                </option>
              </select>
              <span
                v-if="previewEntities[Number(s.id || 0)] !== s.defaultEntity"
                class="text-n-amber-11"
              >
                已改抬头（仅本次）
              </span>
            </div>
          </div>

          <Button
            label="下载 PDF"
            color="iris"
            size="sm"
            class="mt-auto"
            :disabled="!previewUrl || previewLoading"
            @click="downloadPreview"
          />
        </div>

        <div
          class="flex-1 min-w-0 h-[62vh] lg:h-full overflow-hidden border rounded-lg border-n-weak bg-n-solid-2"
        >
          <p
            v-if="previewLoading"
            class="p-6 text-sm text-center text-n-slate-11"
          >
            正在生成预览…
          </p>
          <p
            v-else-if="!previewChecked.length"
            class="p-6 text-sm text-center text-n-slate-11"
          >
            请至少勾选一家供应商。
          </p>
          <iframe
            v-else-if="previewUrl"
            :src="`${previewUrl}#view=Fit&toolbar=1`"
            class="w-full h-full"
            title="采购单预览"
          />
        </div>
      </div>
    </Dialog>

    <MesViewDialog
      ref="viewDialogRef"
      width="5xl"
      :title="viewing ? `采购单 ${viewing.poNo}` : '采购单明细'"
      :fields="viewFields"
      items-title="采购明细"
      :item-columns="VIEW_ITEM_COLS"
      :items="viewItems"
    />
  </div>
</template>
