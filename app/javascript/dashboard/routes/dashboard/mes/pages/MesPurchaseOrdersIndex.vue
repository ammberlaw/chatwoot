<script setup>
/* global axios */
import { ref, computed, reactive, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesPurchaseOrdersStore } from 'dashboard/stores/mes/purchaseOrders';
import { useMesSuppliersStore } from 'dashboard/stores/mes/suppliers';
import MesPurchaseOrderAPI from 'dashboard/api/mes/purchaseOrders';

import Button from 'dashboard/components-next/button/Button.vue';
import MesBoardOwnerBar from 'dashboard/components-next/mes/MesBoardOwnerBar.vue';
import { useMesRole } from 'dashboard/composables/useMesRole';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import { useMesProductLine } from 'dashboard/composables/useMesProductLine';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import MesProductPicker from 'dashboard/components-next/mes/MesProductPicker.vue';
import MesViewDialog from 'dashboard/components-next/mes/MesViewDialog.vue';
import MesSupplierSummary from 'dashboard/components-next/mes/MesSupplierSummary.vue';
import MesReturnControls from 'dashboard/components-next/mes/MesReturnControls.vue';

const { accountId } = useAccount();
const route = useRoute();
const store = useMesPurchaseOrdersStore();
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
const saving = computed(
  () => store.getUIFlags.creatingItem || store.getUIFlags.updatingItem
);

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
const statusOptions = Object.entries(STATUS_LABELS).map(([value, label]) => ({
  value,
  label,
}));

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

// 删草稿：后端 deletable? 才是准绳（这里只决定按钮露不露），删不掉会把后端的理由弹出来。
const canDelete = po =>
  mesCan('purchase') &&
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
const productionOrderOptions = computed(() => [
  { value: '', label: '不关联生产订单' },
  ...productionOrders.value.map(p => ({
    value: String(p.id),
    label: `${p.order_no} · ${p.product_name}`,
  })),
]);
const supplierOptions = computed(() =>
  (suppliersStore.getRecords || []).map(s => ({
    value: String(s.id),
    label: s.name,
  }))
);
// 采购行类型：物料（生产用料）/ 成品（外购贸易品，不经过生产部）。
const ITEM_TYPE_OPTIONS = [
  { value: 'MATERIAL', label: '物料' },
  { value: 'PRODUCT', label: '成品(外购)' },
];

// CRM 成品选项：服务端搜索（成品可能较多），并保留已选项的标签。
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
const productUnit = id =>
  productOptions.value.find(o => o.value === String(id))?.unit || '';
const productLabel = id =>
  productOptions.value.find(o => o.value === String(id))?.label || '';
// 规格型号取自所选产品档案（统一物料档案 = 产品档案）。
const productSpec = id =>
  productOptions.value.find(o => o.value === String(id))?.specification || '';
// 对应物料实时库存（产品搜索/算料时带回的跨仓合计），选料即显示。
const productOnHand = id => {
  const o = productOptions.value.find(x => x.value === String(id));
  return o && o.onHand != null ? o.onHand : null;
};
// MesProductPicker 选中：把该产品并入 productOptions，保证行内显示文本、规格、单位、实时库存都可查。
const onProductPicked = p =>
  mergeProductOptions([
    {
      value: String(p.id),
      label: `${p.name}${p.sku ? `（${p.sku}）` : ''}${
        p.specification ? ` · ${p.specification}` : ''
      }`,
      unit: p.unit || '',
      specification: p.specification || '',
      onHand: p.on_hand != null ? Number(p.on_hand) : null,
    },
  ]);

const dialogRef = ref(null);
const editingId = ref(null);
const removedItemIds = ref([]);
// 明细行：物料/成品统一从产品档案选（crmProductId）；供应商、含税/未税、实际到料时间都在行上。
const blankRow = () => ({
  itemType: 'MATERIAL',
  crmProductId: '',
  mesSupplierId: '',
  arrivalDate: '',
  qty: '1',
  rate: '',
  amount: '', // 行金额：跟数量/单价双向联动（有的物料是报「多少数量多少钱」）
  orderedQty: 0, // 本单这个料已经下出去的量（算料时带出，用来只铺剩余量）
  priceTaxIncluded: false,
  suggestedQty: null, // 工程建议采购量（BOM 算料带出，只读参考）
  remark: '',
});
// 产线：关联生产订单时从订单继承（Mes::PurchaseOrder#product_line_source），
// 独立的成品采购单没有父级，必须在表单里选，否则建完切到任何产线都看不见。
const { activeProductLine, formOptions: productLineOptions } =
  useMesProductLine();

const form = reactive({
  productLine: '',
  productionOrderId: '',
  extraProductionOrderIds: [], // 同款物料多张生产订单共用一次采购时，额外挂上的订单
  internalRemark: '', // 只对内看，不进发给供应商的模板
  status: 'DRAFT',
  expectedDate: '',
  deliveryDate: '',
  hasException: false,
  exceptionNote: '',
  rows: [],
});

// 「再关联一张」的候选：排掉主单和已挂过的，选完即追加，避免重复挂同一张。
const extraOrderOptions = computed(() => [
  { value: '', label: '选一张追加…' },
  ...productionOrders.value
    .filter(
      p =>
        String(p.id) !== String(form.productionOrderId) &&
        !form.extraProductionOrderIds.includes(String(p.id))
    )
    .map(p => ({
      value: String(p.id),
      label: `${p.order_no} · ${p.product_name}`,
    })),
]);
const orderLabel = id => {
  const hit = productionOrders.value.find(p => String(p.id) === String(id));
  return hit ? `${hit.order_no} · ${hit.product_name}` : `#${id}`;
};
const addExtraOrder = v => {
  if (v) form.extraProductionOrderIds.push(String(v));
};
const removeExtraOrder = id => {
  form.extraProductionOrderIds = form.extraProductionOrderIds.filter(
    x => String(x) !== String(id)
  );
};
// 一键把关联的订单号写进对内备注（她在金蝶里就是这么记「哪几张单在用这批料」）。
const fillInternalRemark = () => {
  const ids = [form.productionOrderId, ...form.extraProductionOrderIds].filter(
    Boolean
  );
  if (!ids.length) {
    useAlert('先关联生产订单');
    return;
  }
  const lines = ids.map(orderLabel).join('\n');
  form.internalRemark = form.internalRemark
    ? `${form.internalRemark}\n${lines}`
    : lines;
};

// 含税一键全选：一张单常常整单同一个税口径，一行行勾太费事。
// 半选（部分行含税）时显示 indeterminate，点一下全部勾上。
const allTaxIncluded = computed(
  () => form.rows.length > 0 && form.rows.every(r => r.priceTaxIncluded)
);
const someTaxIncluded = computed(
  () => form.rows.some(r => r.priceTaxIncluded) && !allTaxIncluded.value
);
const toggleAllTaxIncluded = () => {
  const next = !allTaxIncluded.value;
  form.rows.forEach(r => {
    r.priceTaxIncluded = next;
  });
};

const rowIncomplete = r => !Number(r.qty) || !r.crmProductId;
// 供应商税率（%）：用于含税/未税提示。
const supplierTaxRate = id =>
  (suppliersStore.getRecords || []).find(s => String(s.id) === String(id))
    ?.taxRate || 0;
const invalid = computed(
  () =>
    !form.productLine || // 产线必填：漏了这单切到任何产线都看不见
    !form.rows.length ||
    form.rows.some(rowIncomplete)
);
// 采购单合计（元）= Σ 数量 × 单价，实时预览（保存后后端按 amount_micros 汇总总额）。
const orderTotal = computed(() =>
  form.rows.reduce((s, r) => s + Number(r.qty || 0) * Number(r.rate || 0), 0)
);

// 数量 × 单价 ⇄ 金额 双向联动：供应商常按「这批多少钱」报价，允许直接填金额反推单价。
// 单价保留 6 位小数（存 micros），避免 3000 件 4.8 元这种被四舍五入成整数。
const syncAmount = row => {
  const q = Number(row.qty || 0);
  const r = Number(row.rate || 0);
  row.amount = q > 0 && r > 0 ? String(Number((q * r).toFixed(2))) : '';
};
const setRowQty = (row, v) => {
  row.qty = v;
  syncAmount(row);
};
const setRowRate = (row, v) => {
  row.rate = v;
  syncAmount(row);
};
const setRowAmount = (row, v) => {
  row.amount = v;
  const q = Number(row.qty || 0);
  const amt = Number(v);
  if (q > 0 && Number.isFinite(amt) && amt > 0) {
    row.rate = String(Number((amt / q).toFixed(6)));
  }
};

// 算料时是否连「已经下满的料」一起铺出来（默认不铺）。
const includeOrdered = ref(false);

const addRow = () => form.rows.push(blankRow());
const removeRow = i => {
  const [r] = form.rows.splice(i, 1);
  if (r?.id) removedItemIds.value.push(r.id);
};

// 从关联的生产订单 BOM 算料，覆盖当前明细行。
// category='' 全部 / 'MACHINE' 只主料(整机料) / 'PACKAGING' 只辅料(包装料)——两个采购员分料建单。
const explode = async (category = '') => {
  if (!form.productionOrderId) {
    useAlert('请先选生产订单');
    return;
  }
  try {
    const { data } = await MesPurchaseOrderAPI.requirement(
      form.productionOrderId,
      category
    );
    const all = data?.payload || [];
    if (!all.length) {
      useAlert(
        category ? '该类别（主料/辅料）无用料' : '该生产订单未挂 BOM 或无用料'
      );
      return;
    }
    // 这张生产订单已经下满量的料默认不再铺出来——否则每次重进都是整屏物料，
    // 看不出到底哪些还没下单。勾上「含已下单物料」可以把它们调回来。
    const reqs = includeOrdered.value
      ? all
      : all.filter(r => Number(r.ordered_qty || 0) < Number(r.qty || 0));
    const hidden = all.length - reqs.length;
    if (!reqs.length) {
      useAlert(`这张生产订单的料都已经下过采购单了（${all.length} 项）`);
      return;
    }
    form.rows.forEach(r => r.id && removedItemIds.value.push(r.id));
    // 料号能对上产品档案 SKU 的自动带出产品；对不上的留空让采购手动选（并把料号信息放备注提示）。
    mergeProductOptions(
      reqs
        .filter(r => r.crm_product_id)
        .map(r => ({
          value: String(r.crm_product_id),
          label: `${r.material_name || ''}${r.material_no ? `（${r.material_no}）` : ''}${
            r.specification ? ` · ${r.specification}` : ''
          }`,
          unit: r.unit || '',
          specification: r.specification || '',
          onHand: r.on_hand != null ? Number(r.on_hand) : null,
        }))
    );
    form.rows = reqs.map(r => ({
      ...blankRow(),
      crmProductId: r.crm_product_id ? String(r.crm_product_id) : '',
      mesSupplierId: r.mes_supplier_id ? String(r.mes_supplier_id) : '',
      qty: String(r.qty),
      suggestedQty:
        r.suggested_purchase_qty != null
          ? Number(r.suggested_purchase_qty)
          : null,
      // 部分下过的料只带剩余量，采购不用自己减。
      orderedQty: Number(r.ordered_qty || 0),
      // 料号对不上产品档案时把料号/名称/规格留备注，方便采购手动补选。
      remark: r.crm_product_id
        ? ''
        : [r.material_no, r.material_name, r.specification]
            .filter(Boolean)
            .join(' '),
    }));
    form.rows.forEach(r => {
      if (r.orderedQty > 0) {
        r.qty = String(Number((Number(r.qty) - r.orderedQty).toFixed(3)));
      }
      syncAmount(r);
    });
    if (hidden > 0) useAlert(`已下满的 ${hidden} 项没有列出`);
  } catch {
    useAlert('算料失败');
  }
};

const resetForm = () => {
  editingId.value = null;
  removedItemIds.value = [];
  Object.assign(form, {
    productLine: activeProductLine.value || '',
    productionOrderId: '',
    extraProductionOrderIds: [],
    internalRemark: '',
    status: 'DRAFT',
    expectedDate: '',
    deliveryDate: '',
    hasException: false,
    exceptionNote: '',
    rows: [blankRow()],
  });
};

const openCreate = () => {
  resetForm();
  dialogRef.value?.open();
};
// 从工程/PMC BOM 的「新建成品采购单」跳来：首行直接切成外购成品。
const openProductCreate = () => {
  resetForm();
  form.rows[0].itemType = 'PRODUCT';
  dialogRef.value?.open();
};
const openEdit = po => {
  editingId.value = po.id;
  removedItemIds.value = [];
  Object.assign(form, {
    productLine: po.productLine || '',
    productionOrderId: po.productionOrderId ? String(po.productionOrderId) : '',
    extraProductionOrderIds: (po.extraProductionOrderIds || []).map(String),
    internalRemark: po.internalRemark || '',
    status: po.status,
    expectedDate: po.expectedDate ? po.expectedDate.slice(0, 10) : '',
    deliveryDate: po.deliveryDate ? po.deliveryDate.slice(0, 10) : '',
    hasException: !!po.hasException,
    exceptionNote: po.exceptionNote || '',
    rows: (po.purchaseItems || []).map(it => ({
      id: it.id,
      itemType: it.itemType || 'MATERIAL',
      crmProductId: it.crmProductId ? String(it.crmProductId) : '',
      mesSupplierId: it.mesSupplierId ? String(it.mesSupplierId) : '',
      arrivalDate: it.arrivalDate ? it.arrivalDate.slice(0, 10) : '',
      qty: String(it.qty),
      rate: it.rateMicros ? String(it.rateMicros / 1e6) : '',
      amount: it.rateMicros
        ? String(Number(((it.rateMicros / 1e6) * Number(it.qty)).toFixed(2)))
        : '',
      priceTaxIncluded: !!it.priceTaxIncluded,
      remark: it.remark || '',
    })),
  });
  // 回填已选产品的标签/规格，保证下拉能显示名称
  mergeProductOptions(
    (po.purchaseItems || [])
      .filter(it => it.crmProductId)
      .map(it => ({
        value: String(it.crmProductId),
        label: `${it.productName || ''}${it.productSku ? `（${it.productSku}）` : ''}`,
        unit: it.unit || '',
        specification: it.specification || '',
      }))
  );
  dialogRef.value?.open();
};

const submit = async () => {
  if (invalid.value) return;
  const itemsAttributes = [
    ...form.rows.map(r => ({
      id: r.id || undefined,
      itemType: r.itemType,
      mesMaterialId: null,
      crmProductId: Number(r.crmProductId),
      mesSupplierId: r.mesSupplierId ? Number(r.mesSupplierId) : null,
      arrivalDate: r.arrivalDate || null,
      unit: productUnit(r.crmProductId) || undefined,
      qty: Number(r.qty),
      rateMicros: r.rate ? Math.round(Number(r.rate) * 1e6) : null,
      priceTaxIncluded: r.priceTaxIncluded,
      remark: r.remark || '',
    })),
    ...removedItemIds.value.map(id => ({ id, _destroy: true })),
  ];
  const payload = {
    productLine: form.productLine || null,
    productionOrderId: form.productionOrderId || null,
    extraProductionOrderIds: form.extraProductionOrderIds,
    internalRemark: form.internalRemark,
    status: form.status,
    expectedDate: form.expectedDate || null,
    deliveryDate: form.deliveryDate || null,
    hasException: form.hasException,
    exceptionNote: form.exceptionNote,
    purchaseItemsAttributes: itemsAttributes,
  };
  const ok = editingId.value
    ? await store.update({ id: editingId.value, ...payload })
    : await store.create(payload);
  if (ok) {
    useAlert(editingId.value ? '采购单已更新' : `已新建 ${ok.poNo}`);
    dialogRef.value?.close();
  }
};

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
  if (route.query.new === 'product' && mesCan('purchase')) openProductCreate();
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between px-4 py-3 sm:px-6 sm:py-4">
      <h1 class="text-xl font-semibold text-n-slate-12">采购单</h1>
      <Button
        v-if="mesCan('purchase')"
        label="新建采购单"
        color="iris"
        size="sm"
        @click="openCreate"
      />
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
                  color="teal"
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
                  v-if="mesCan('purchase')"
                  label="编辑"
                  variant="ghost"
                  size="sm"
                  @click="openEdit(p)"
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
        <table class="hidden w-full text-sm whitespace-nowrap md:table">
          <thead>
            <tr class="text-left text-n-slate-11 border-b border-n-weak">
              <th class="px-3 py-3 font-medium w-12">#</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">采购单号</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">供应商</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">生产订单</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">归属人</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">下单人</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">收货状态</th>
              <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
                总额
              </th>
              <th
                class="px-3 py-3 font-medium text-center whitespace-nowrap"
                title="导出过几次——一个供应商几十张单时，用来看哪张还没传出去"
              >
                导出
              </th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">审批</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">回复交期</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">交货时间</th>
              <th class="px-3 py-3" />
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="(p, i) in records"
              :key="p.id"
              class="border-b border-n-weak"
            >
              <td class="px-3 py-3 tabular-nums text-n-slate-10">
                {{ i + 1 }}
              </td>
              <td class="px-3 py-3 font-medium text-n-slate-12">
                {{ p.poNo }}
                <span
                  v-if="p.hasException"
                  v-tooltip.top="exceptionTip(p)"
                  class="ml-1 text-xs cursor-help text-n-ruby-11"
                >
                  ⚠
                </span>
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                <MesSupplierSummary :names="p.supplierNames || []" />
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                <span :title="(p.relatedProductionOrderNos || []).join('、')">
                  {{ orderNosLabel(p.relatedProductionOrderNos) }}
                </span>
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ p.productionOrderOwnerName || '—' }}
              </td>
              <td class="px-3 py-3 whitespace-nowrap text-n-slate-11">
                {{ p.ownerName || '—' }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ STATUS_LABELS[p.status] }}
              </td>
              <td
                class="px-3 py-3 text-right whitespace-nowrap text-n-slate-12"
              >
                {{ yuan(p.totalAmountMicros) }}
              </td>
              <td class="px-3 py-3 text-center tabular-nums whitespace-nowrap">
                <span
                  v-if="p.exportCount"
                  class="px-1.5 py-0.5 text-xs rounded-md bg-n-teal-3 text-n-teal-11"
                  :title="`最近一次 ${day(p.lastExportedAt) || '—'}`"
                >
                  {{ p.exportCount }}
                </span>
                <span v-else class="text-xs text-n-slate-10">未导出</span>
              </td>
              <td class="px-3 py-3 whitespace-nowrap">
                <span :class="APPROVAL_COLORS[p.approvalStatus]">
                  {{ APPROVAL_LABELS[p.approvalStatus] || '—' }}
                </span>
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ day(p.expectedDate) }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ day(p.deliveryDate) }}
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
                    color="teal"
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
                    v-if="mesCan('purchase')"
                    label="编辑"
                    variant="ghost"
                    size="sm"
                    @click="openEdit(p)"
                  />
                  <Button
                    v-if="canViewAmount"
                    label="预览 / 导出"
                    variant="ghost"
                    size="sm"
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
              <td colspan="13" class="px-3 py-10 text-center text-n-slate-11">
                还没有采购单。
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
      width="5xl"
      :show-confirm-button="false"
      cancel-button-label="关闭"
      :title="previewPo ? `采购单 ${previewPo.poNo} · 预览` : '采购单预览'"
      @close="revokePreview"
    >
      <div class="flex flex-col gap-3">
        <p class="text-xs text-n-slate-11">
          抬头默认按各供应商档案选（对公「东莞市联迪科技」含税带公章，对私「深圳联合触控」未税），
          这里改只影响这次导出的单，不会写回供应商档案。核对无误可直接截图发群，也可导出
          PDF。
        </p>

        <div
          v-if="previewSuppliers.length"
          class="flex flex-col gap-1 p-2 rounded-lg bg-n-alpha-1"
        >
          <div
            v-for="s in previewSuppliers"
            :key="s.id"
            class="flex items-center gap-2 text-xs text-n-slate-11"
          >
            <label class="flex items-center gap-1.5 cursor-pointer min-w-52">
              <input
                v-if="previewSuppliers.length > 1"
                v-model="previewChecked"
                type="checkbox"
                :value="Number(s.id || 0)"
                @change="fetchPreviewPdf"
              />
              <span class="text-n-slate-12">{{ s.name }}</span>
              <span class="text-n-slate-10">{{ s.itemCount }} 项</span>
            </label>
            <!-- 未指定供应商的那组不能导（会被凑成一份发错家），直接在这儿说清楚 -->
            <span v-if="!s.id" class="text-n-ruby-11">
              这几项还没指定供应商，导不出——请回「编辑」里逐行选供应商
            </span>
            <select
              v-model="previewEntities[Number(s.id || 0)]"
              class="!w-auto !h-7 !mb-0 !py-0.5 !text-xs ltr:!pl-2"
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

        <div
          class="h-[62vh] overflow-hidden rounded-lg border border-n-weak bg-n-solid-2"
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
            :src="previewUrl"
            class="w-full h-full"
            title="采购单预览"
          />
        </div>

        <div class="flex justify-end">
          <Button
            label="下载 PDF"
            color="iris"
            size="sm"
            :disabled="!previewUrl || previewLoading"
            @click="downloadPreview"
          />
        </div>
      </div>
    </Dialog>

    <Dialog
      ref="dialogRef"
      :dismissible="false"
      width="5xl"
      overflow-y-auto
      confirm-button-color="iris"
      :title="editingId ? '编辑采购单' : '新建采购单'"
      :is-loading="saving"
      :disable-confirm-button="invalid"
      @confirm="submit"
    >
      <div class="flex flex-col gap-4">
        <div class="flex flex-col items-stretch gap-2 sm:flex-row sm:items-end">
          <div class="flex flex-col gap-1 sm:w-40">
            <label class="text-heading-3 text-n-slate-12">
              产品线<span class="text-n-ruby-11">*</span>
            </label>
            <SelectCard
              size="form"
              :model-value="form.productLine"
              :options="productLineOptions"
              @update:model-value="v => (form.productLine = v)"
            />
          </div>
          <div class="flex flex-col flex-1 gap-1">
            <label class="text-heading-3 text-n-slate-12">关联生产订单</label>
            <SelectCard
              size="form"
              :model-value="form.productionOrderId"
              :options="productionOrderOptions"
              @update:model-value="v => (form.productionOrderId = v)"
            />
          </div>
          <!-- 同款物料多张生产订单在用时，一张采购单挂多张订单，只传一次给供应商 -->
          <div class="flex flex-col flex-1 gap-1">
            <label class="text-heading-3 text-n-slate-12">
              还有哪些订单在用（选填）
            </label>
            <SelectCard
              size="form"
              model-value=""
              :options="extraOrderOptions"
              @update:model-value="addExtraOrder"
            />
            <div
              v-if="form.extraProductionOrderIds.length"
              class="flex flex-wrap items-center gap-1 mt-1"
            >
              <span
                v-for="id in form.extraProductionOrderIds"
                :key="id"
                class="inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded-md bg-n-iris-3 text-n-iris-11"
              >
                {{ orderLabel(id) }}
                <button
                  type="button"
                  class="i-lucide-x size-3 hover:opacity-70"
                  @click="removeExtraOrder(id)"
                />
              </span>
            </div>
          </div>
          <div class="flex flex-wrap items-center gap-1">
            <label
              class="flex items-center gap-1.5 text-xs cursor-pointer text-n-slate-11"
              title="默认只铺这张生产订单还没下满的料"
            >
              <input v-model="includeOrdered" type="checkbox" />
              含已下单物料
            </label>
            <Button
              label="算全部料"
              type="button"
              color="slate"
              size="sm"
              @click="explode('')"
            />
            <Button
              label="只算主料"
              type="button"
              variant="outline"
              color="slate"
              size="sm"
              @click="explode('MACHINE')"
            />
            <Button
              label="只算辅料"
              type="button"
              variant="outline"
              color="slate"
              size="sm"
              @click="explode('PACKAGING')"
            />
          </div>
        </div>
        <p class="-mt-2 text-xs text-n-slate-10">
          一张生产订单可开多张采购单（如主料、辅料各一张，不同采购员各建各的）。
        </p>

        <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">状态</label>
            <SelectCard
              size="form"
              :model-value="form.status"
              :options="statusOptions"
              @update:model-value="v => (form.status = v)"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">回复采购时间</label>
            <DatePicker v-model="form.expectedDate" block />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">交货时间</label>
            <DatePicker v-model="form.deliveryDate" block />
            <span class="text-xs text-n-slate-10">
              导出合同"三、交货时间"用
            </span>
          </div>
        </div>

        <!-- 对内备注：只在系统里看，导出给供应商的采购订单上不会出现 -->
        <div class="flex flex-col gap-1">
          <div class="flex items-center justify-between">
            <label class="text-heading-3 text-n-slate-12">对内备注</label>
            <button
              type="button"
              class="text-xs text-n-iris-11 hover:underline"
              @click="fillInternalRemark"
            >
              填入关联订单号
            </button>
          </div>
          <textarea
            v-model="form.internalRemark"
            rows="3"
            class="w-full px-3 py-2 text-sm border rounded-lg resize-y border-n-weak bg-n-alpha-1 text-n-slate-12 focus:outline-none"
            placeholder="例：WT20260723-01 型号 KROCO 2500&#10;WT20260723-05 型号 NAZA 2500"
          />
          <span class="text-xs text-n-slate-10">
            只对内看，不会出现在发给供应商的采购订单上
          </span>
        </div>

        <div class="flex flex-col gap-1">
          <label class="flex items-center gap-2 text-heading-3 text-n-slate-12">
            <input v-model="form.hasException" type="checkbox" />
            采购异常
          </label>
          <Input
            v-if="form.hasException"
            v-model="form.exceptionNote"
            placeholder="异常说明"
          />
        </div>

        <div class="flex items-center justify-between">
          <span class="text-heading-3 text-n-slate-12">
            采购明细 <span class="text-n-ruby-11">*</span>
          </span>
          <div class="flex items-center gap-3">
            <label
              v-if="form.rows.length"
              class="flex items-center gap-1.5 text-xs cursor-pointer text-n-slate-11"
            >
              <input
                type="checkbox"
                :checked="allTaxIncluded"
                :indeterminate.prop="someTaxIncluded"
                @change="toggleAllTaxIncluded"
              />
              全部含税
            </label>
            <Button
              label="+ 加一行"
              type="button"
              variant="ghost"
              size="sm"
              @click="addRow"
            />
          </div>
        </div>
        <div class="flex flex-col gap-2.5">
          <div
            v-for="(row, i) in form.rows"
            :key="i"
            class="flex flex-col gap-2.5 p-3 border rounded-lg border-n-weak"
          >
            <!-- 主控件行：类型 / 物料 / 供应商 / 数量 / 单价 / 删除 -->
            <div
              class="grid items-center grid-cols-1 gap-2 md:grid-cols-[1.6fr_3fr_2fr_1.2fr_1.6fr_1.6fr_24px]"
            >
              <div>
                <SelectCard
                  size="form"
                  :model-value="row.itemType"
                  :options="ITEM_TYPE_OPTIONS"
                  @update:model-value="v => (row.itemType = v)"
                />
              </div>
              <div>
                <MesProductPicker
                  :account-id="accountId"
                  :model-value="row.crmProductId"
                  :display-text="productLabel(row.crmProductId)"
                  placeholder="选择物料（产品档案·编码/名称/规格）"
                  @update:model-value="v => (row.crmProductId = v)"
                  @select="onProductPicked"
                />
              </div>
              <div>
                <ComboBox
                  v-model="row.mesSupplierId"
                  :options="supplierOptions"
                  placeholder="选择供应商"
                />
              </div>
              <Input
                :model-value="row.qty"
                type="number"
                placeholder="数量"
                @update:model-value="v => setRowQty(row, v)"
              />
              <Input
                :model-value="row.rate"
                type="number"
                :placeholder="row.priceTaxIncluded ? '含税单价' : '未税单价'"
                @update:model-value="v => setRowRate(row, v)"
              />
              <!-- 金额：填了就按数量反推单价（供应商常报「这批多少钱」） -->
              <Input
                :model-value="row.amount"
                type="number"
                :placeholder="row.priceTaxIncluded ? '含税金额' : '未税金额'"
                title="填金额会按数量反推单价"
                @update:model-value="v => setRowAmount(row, v)"
              />
              <button
                type="button"
                class="justify-self-end text-n-slate-10 hover:text-n-ruby-11"
                @click="removeRow(i)"
              >
                ✕
              </button>
            </div>
            <!-- 次要控件行：含税 / 实际到料 / 备注 -->
            <div class="grid items-center grid-cols-1 gap-2 md:grid-cols-12">
              <label
                class="flex items-center gap-1.5 text-xs md:col-span-3 text-n-slate-11"
              >
                <input v-model="row.priceTaxIncluded" type="checkbox" />
                <span class="shrink-0">单价含税</span>
                <span
                  v-if="row.mesSupplierId && supplierTaxRate(row.mesSupplierId)"
                  class="text-n-slate-10"
                >
                  （税率{{ supplierTaxRate(row.mesSupplierId) }}%）
                </span>
              </label>
              <div class="flex items-center gap-2 md:col-span-4">
                <label class="text-xs shrink-0 text-n-slate-11">实际到料</label>
                <div class="flex-1">
                  <DatePicker v-model="row.arrivalDate" block />
                </div>
              </div>
              <Input
                v-model="row.remark"
                placeholder="备注"
                class="md:col-span-5"
              />
            </div>
            <!-- 只读信息：规格 · 实时库存 · 工程建议采购 -->
            <div
              class="flex flex-wrap gap-x-5 gap-y-1 pt-0.5 text-xs border-t border-n-weak/60"
            >
              <span class="inline-flex gap-1.5">
                <span class="text-n-slate-9">规格</span>
                <span class="text-n-slate-11">
                  {{ productSpec(row.crmProductId) || '—' }}
                </span>
              </span>
              <span class="inline-flex gap-1.5">
                <span class="text-n-slate-9">实时库存</span>
                <span class="text-n-slate-11">
                  {{
                    productOnHand(row.crmProductId) == null
                      ? '选料后显示'
                      : productOnHand(row.crmProductId)
                  }}
                </span>
              </span>
              <span class="inline-flex gap-1.5">
                <span class="text-n-slate-9">工程建议采购</span>
                <span class="text-n-slate-11">
                  {{ row.suggestedQty == null ? '—' : row.suggestedQty }}
                </span>
              </span>
            </div>
          </div>
        </div>
        <div
          v-if="orderTotal > 0"
          class="flex justify-end text-heading-3 text-n-slate-12"
        >
          合计：¥{{
            orderTotal.toLocaleString('zh-CN', {
              minimumFractionDigits: 2,
              maximumFractionDigits: 2,
            })
          }}
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
