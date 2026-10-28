<script setup>
/* global axios */
import { ref, reactive, computed, onMounted, watch, nextTick } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useOrderableColumns } from 'dashboard/composables/useOrderableColumns';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import { useMesPurchaseOrdersStore } from 'dashboard/stores/mes/purchaseOrders';
import { useMesSuppliersStore } from 'dashboard/stores/mes/suppliers';
import { emitter } from 'shared/helpers/mitt';
import MesPurchaseOrderAPI from 'dashboard/api/mes/purchaseOrders';
import { exportRowsToExcel, fetchAllRows } from 'dashboard/helper/erpExcel';
import { useListDensity } from 'dashboard/composables/useListDensity';

import Button from 'dashboard/components-next/button/Button.vue';
import MesBoardOwnerBar from 'dashboard/components-next/mes/MesBoardOwnerBar.vue';
import MesColumnFilter from 'dashboard/components-next/mes/MesColumnFilter.vue';
import { useMesRole } from 'dashboard/composables/useMesRole';
import { useMesDocOwner } from 'dashboard/composables/useMesDocOwner';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import MesViewDialog from 'dashboard/components-next/mes/MesViewDialog.vue';
import MesSupplierSummary from 'dashboard/components-next/mes/MesSupplierSummary.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import MesMultiNoCell from 'dashboard/components-next/mes/MesMultiNoCell.vue';
import ColResizeHandle from 'dashboard/components-next/table/ColResizeHandle.vue';
import MesReturnControls from 'dashboard/components-next/mes/MesReturnControls.vue';
import { useRouteQueryReentry } from 'dashboard/composables/useRouteQueryReentry';
import MesStatusPill from 'dashboard/components-next/mes/MesStatusPill.vue';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
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
// 行高：宽松/紧凑一键切，记在本机（反馈：间距太长想自己拉短）
const { compact, toggleDensity } = useListDensity();
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
// 后端每页 15 条。原来这里既不传页码、页面也没有翻页器，
// 结果「共 27 条」却只看得到前 15 张，第 16 张往后谁都点不到。
const ITEMS_PER_PAGE = 15;
const currentPage = ref(1);
// 同生产订单页：列表重拉＝刚办完事，顺带让侧栏重算 MES 待办角标。
// 下单状态 / 审批状态：两个字段互相独立（已下单≠已审批），所以分两个下拉。
// 选项表依赖下面的 STATUS_LABELS / APPROVAL_LABELS，放在它们之后（见文件下方）。
const statusFilter = ref('');
const approvalFilter = ref('');

// 表头漏斗（对标金蝶）。条件发后端算（见 Mes::PurchaseOrderFilter）：列表是分页的，
// 前端只过滤本页的话，第 2 页往后的命中全看不见——采购单常年几十上百张。
const colFilters = reactive({
  po_no: '',
  supplier: '',
  order_no: '',
  item_code: '',
  item_name: '',
  item_spec: '',
});
// 列 key → 筛哪个参数。两套列（按单 / 按明细）共用这张表，同名列筛的是同一件事。
const FILTERABLE = {
  poNo: { key: 'po_no', placeholder: '采购单号' },
  suppliers: { key: 'supplier', placeholder: '供应商' },
  supplier: { key: 'supplier', placeholder: '供应商' },
  order: { key: 'order_no', placeholder: '销售订单号' },
  code: { key: 'item_code', placeholder: '物料编码' },
  name: { key: 'item_name', placeholder: '物料名称' },
  spec: { key: 'item_spec', placeholder: '规格型号' },
};
const filterOf = col => FILTERABLE[col.key];

const fetchList = () => {
  emitter.emit('MES_TODO_MAY_CHANGE');
  return store.get({
    q: search.value.trim() || undefined,
    owner_id: onlyMine.value ? currentUserId.value : undefined,
    status: statusFilter.value || undefined,
    approval_status: approvalFilter.value || undefined,
    ...Object.fromEntries(
      Object.entries(colFilters).map(([k, v]) => [k, v.trim() || undefined])
    ),
    page: currentPage.value,
  });
};
watch(currentPage, fetchList);

// 换了筛选条件要回到第 1 页——否则在第 3 页搜一个只有 2 条结果的词会看到空列表。
const resetToFirstPage = () => {
  if (currentPage.value === 1) fetchList();
  else currentPage.value = 1;
};
// 改了列筛选要回第 1 页，理由同搜索框
const onColFilterChange = () => resetToFirstPage();
let searchTimer = null;
watch(search, () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(resetToFirstPage, 300);
});
watch(onlyMine, resetToFirstPage);

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
  CANCELLED: '已关闭',
};

// 审批状态（一级）：与收货状态正交。审批人按产品线配置（平板、商显各一位），
// 故文案一律说「审批」不说「总经理」——码值 PENDING_GM 是历史命名，不动。
const APPROVAL_LABELS = {
  DRAFT: '草稿',
  PENDING_GM: '待审批',
  APPROVED: '已通过',
  REJECTED: '已驳回',
};

// 64 张单摆一页，找「还没下单的」或「卡在审批的」只能靠眼睛扫，给两个下拉。
const STATUS_FILTER_OPTIONS = [
  { value: '', label: '全部下单状态' },
  ...Object.entries(STATUS_LABELS).map(([value, label]) => ({ value, label })),
];
const APPROVAL_FILTER_OPTIONS = [
  { value: '', label: '全部审批状态' },
  ...Object.entries(APPROVAL_LABELS).map(([value, label]) => ({
    value,
    label,
  })),
];
const APPROVAL_COLORS = {
  DRAFT: 'text-n-slate-11',
  PENDING_GM: 'text-n-amber-11',
  APPROVED: 'text-n-teal-11',
  REJECTED: 'text-n-ruby-11',
};

// 采购审批人按产品线配（本线没配回落「全部产线」，再回落绩效设置里的总经理）。
const APPROVER_BOARD = [
  {
    key: 'mes_purchase_approver',
    label: '采购审批人',
    single: true,
    hint: '该产品线的采购单提交后，由他审批（通过才能导出发供应商）。',
  },
];

// 提交审批：草稿/被驳回可提交（制单人操作）。
const submitForApproval = async po => {
  try {
    await MesPurchaseOrderAPI.submit(po.id);
    useAlert('已提交审批');
    fetchList();
  } catch {
    useAlert('提交失败，请重试');
  }
};
// 审批通过。
const approvePo = async po => {
  try {
    await MesPurchaseOrderAPI.approve(po.id);
    useAlert('已通过，库存已记在途');
    fetchList();
  } catch {
    useAlert('审批失败，请重试');
  }
};
// 审批驳回（填原因）。
// 我是本单当前审批人吗？→ 显示通过/驳回。（审批人按产品线分，逐单看 currentApproverId）
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

// 「只看这家 / 看全部」：一张采购单常挂十几家供应商，预览默认全勾，
// 想核某一家的那张纸就得把其余的逐个取消——这两颗按钮是一步到位的入口。
const onlyThisSupplier = s => {
  previewChecked.value = [Number(s.id || 0)];
  fetchPreviewPdf();
};
const isOnlyChecked = s =>
  previewChecked.value.length === 1 &&
  Number(previewChecked.value[0]) === Number(s.id || 0);
const checkAllSuppliers = () => {
  previewChecked.value = previewSuppliers.value
    .filter(x => x.id)
    .map(x => Number(x.id));
  fetchPreviewPdf();
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
// 删单：口径只留后端一处（未提审的草稿，或已关闭且没到过货的单），这里照着 deletable 露按钮。
const canDelete = po => mesCan('purchase') && isMyDoc(po) && po.deletable;
// 关闭 / 启用：一对可逆动作，收过货的单不给关（后端也拦）。
const canClose = po => mesCan('purchase') && isMyDoc(po) && !po.closed;
const canReopen = po => mesCan('purchase') && isMyDoc(po) && po.closed;

const closeOrder = async po => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      `关闭采购单「${po.poNo}」？关闭后不参与齐套判定，需要时可以再启用。`
    )
  )
    return;
  try {
    await store.closeOrder(po.id);
    useAlert(`${po.poNo} 已关闭`);
  } catch (error) {
    useAlert(error?.message || '关闭失败');
  }
};

const reopenOrder = async po => {
  try {
    await store.reopenOrder(po.id);
    useAlert(`${po.poNo} 已启用`);
  } catch (error) {
    useAlert(error?.message || '启用失败');
  }
};

const removeOrder = async po => {
  if (!window.confirm(`确定删除采购单「${po.poNo}」？删了不可恢复。`)) return;
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
const rejecting = ref(false); // 弹窗内「驳回」展开原因输入
const rejectReason = ref('');
const acting = ref(false);
const openView = (po, { reject = false } = {}) => {
  viewing.value = po;
  rejecting.value = reject;
  rejectReason.value = '';
  viewDialogRef.value?.open();
};

// 列表上点「驳回」＝打开详情弹窗并直接展开原因输入：原先弹的是浏览器原生 prompt，
// 跟全站紫玻璃弹窗两个画风，而且看不到明细就得盲填理由。
const rejectPo = po => openView(po, { reject: true });

// 弹窗内审批：看完明细当场批，不用关掉弹窗回列表找按钮。
const approveFromView = async () => {
  acting.value = true;
  try {
    await MesPurchaseOrderAPI.approve(viewing.value.id);
    useAlert('已通过，库存已记在途');
    viewDialogRef.value?.close();
    fetchList();
  } catch (e) {
    useAlert(e?.response?.data?.error || '审批失败，请重试');
  } finally {
    acting.value = false;
  }
};
const confirmRejectFromView = async () => {
  const reason = rejectReason.value.trim();
  if (!reason) return useAlert('请填写驳回原因');
  acting.value = true;
  try {
    await MesPurchaseOrderAPI.reject(viewing.value.id, reason);
    useAlert('已驳回');
    viewDialogRef.value?.close();
    fetchList();
  } catch (e) {
    useAlert(e?.response?.data?.error || '驳回失败，请重试');
  } finally {
    acting.value = false;
  }
  return undefined;
};
const viewFields = computed(() => {
  const p = viewing.value || {};
  return [
    { label: '采购单号', value: p.poNo },
    { label: '供应商', value: (p.supplierNames || []).join('、') || '—' },
    { label: '销售订单', value: p.productionOrderNo },
    { label: '归属人', value: p.productionOrderOwnerName },
    { label: '收货状态', value: STATUS_LABELS[p.status] || p.status },
    { label: '采购总额', value: yuan(p.totalAmountMicros) },
    {
      label: '审批状态',
      value: APPROVAL_LABELS[p.approvalStatus] || '—',
    },
    { label: '审批人', value: p.gmName || '—' },
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
// 列表两种看法：「按单」一行一张采购单，「按明细」一行一条料——对标金蝶采购订单的
// 明细视图。用户原话：「只能看到供应商和采购单号，物料啥也看不出」。
const viewMode = ref('order'); // order | item
const VIEW_MODES = [
  { key: 'order', label: '按单' },
  { key: 'item', label: '按明细' },
];

// 按单视图的列（可拖拽改顺序、可收起，按人记在本机）。操作列固定在最后，不参与拖拽与收起。
const ORDER_COLUMN_DEFS = [
  { key: 'idx', label: '#', tdClass: 'px-3 py-3 tabular-nums text-n-slate-10' },
  // 单据日期＝下单那天（对标金蝶）。原来只有交货时间/回复交期，排不出单子的先后。
  { key: 'docDate', label: '单据日期', tdClass: 'px-3 py-3 text-n-slate-11' },
  {
    key: 'poNo',
    label: '采购单号',
    tdClass: 'px-3 py-3 font-medium text-n-slate-12',
  },
  { key: 'suppliers', label: '供应商', tdClass: 'px-3 py-3 text-n-slate-11' },
  { key: 'order', label: '销售订单', tdClass: 'px-3 py-3 text-n-slate-11' },
  // 上游两条备注紧挨着「销售订单」列：采购要在自己这页看到业务和工程交代了什么，
  // 不用来回切单（问题点 B3/B4）。**位置是这条需求的一半**——上一版把它们追加在
  // 列数组末尾，这张表 17 列、不横拉到底根本看不见，用户照样反馈「未改」。
  {
    key: 'salesOrderRemark',
    label: '销售订单备注',
    tdClass: 'px-3 py-3 text-n-slate-11 max-w-[16rem] truncate',
  },
  {
    key: 'bomRemark',
    label: '生产任务单备注',
    tdClass: 'px-3 py-3 text-n-slate-11 max-w-[16rem] truncate',
  },
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
  visibleColumns: visibleOrderCols,
  hiddenKeys: hiddenOrderColKeys,
  isHidden: isOrderColHidden,
  toggleColumn: toggleOrderCol,
  showAllColumns: showAllOrderCols,
  isDragging: isOrderColDragging,
  onColDragStart: onOrderColDragStart,
  onColDrop: onOrderColDrop,
  resetOrder: resetOrderCols,
  colStyle: orderColStyle,
  isResizing: isOrderColResizing,
  startResize: startOrderColResize,
  autoFitColumn: autoFitOrderCol,
} = useOrderableColumns(ORDER_COLUMN_DEFS, 'mes.poListCols.v2');

// 明细视图的列。两套列各记各的（本机键不同），互不干扰。
const ITEM_COLUMN_DEFS = [
  { key: 'idx', label: '#', tdClass: 'px-3 py-2 tabular-nums text-n-slate-10' },
  { key: 'docDate', label: '单据日期', tdClass: 'px-3 py-2 text-n-slate-11' },
  {
    key: 'poNo',
    label: '采购单号',
    tdClass: 'px-3 py-2 font-medium text-n-slate-12',
  },
  { key: 'supplier', label: '供应商', tdClass: 'px-3 py-2 text-n-slate-11' },
  // 这家供应商在本单下的子流水号——仓库收料、财务对账都认它
  {
    key: 'supplierNo',
    label: '供应商单号',
    tdClass: 'px-3 py-2 font-mono text-n-slate-11 whitespace-nowrap',
  },
  { key: 'code', label: '物料编码', tdClass: 'px-3 py-2 text-n-slate-11' },
  { key: 'name', label: '名称', tdClass: 'px-3 py-2 text-n-slate-12' },
  {
    key: 'spec',
    label: '规格型号',
    tdClass: 'px-3 py-2 text-n-slate-11 max-w-[18rem] truncate',
  },
  { key: 'aux', label: '辅助属性', tdClass: 'px-3 py-2 text-n-slate-11' },
  {
    key: 'productRemark',
    label: '档案备注',
    tdClass: 'px-3 py-2 text-n-slate-11 max-w-[16rem] truncate',
  },
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
  // 单价/金额按行的录入口径存（price_tax_included 按行不同），只摆一个数看不出是
  // 含税还是未税，跟供应商对账就对不上——两种各摆一列，列名写死口径。
  {
    key: 'untaxedRate',
    label: '未税单价',
    thClass: 'text-right',
    tdClass: 'px-3 py-2 text-right tabular-nums text-n-slate-11',
  },
  {
    key: 'taxedRate',
    label: '含税单价',
    thClass: 'text-right',
    tdClass: 'px-3 py-2 text-right tabular-nums text-n-slate-11',
  },
  // 税率：对账时「单价×数量对不上价税合计」十有八九是税点不同，列表上看不到就只能一张张点开。
  {
    key: 'taxRate',
    label: '税率',
    thClass: 'text-right',
    tdClass: 'px-3 py-2 text-right tabular-nums text-n-slate-11',
  },
  {
    key: 'untaxedAmount',
    label: '未税合计',
    thClass: 'text-right',
    tdClass: 'px-3 py-2 text-right tabular-nums text-n-slate-12',
  },
  {
    key: 'taxedAmount',
    label: '含税合计',
    thClass: 'text-right',
    tdClass: 'px-3 py-2 text-right tabular-nums text-n-slate-12',
  },
  { key: 'order', label: '销售订单', tdClass: 'px-3 py-2 text-n-slate-11' },
  { key: 'arrival', label: '实际到料', tdClass: 'px-3 py-2 text-n-slate-11' },
  {
    key: 'itemRemark',
    label: '备注',
    tdClass: 'px-3 py-2 text-n-slate-11 max-w-[16rem] truncate',
  },
  // 对内备注：核对生产单时看的就是这句。按单视图早有这列，按明细视图原来没有，
  // 切过去就得再切回来看一眼，反馈点名要补。
  {
    key: 'internalRemark',
    label: '对内备注',
    tdClass: 'px-3 py-2 text-n-slate-11 max-w-[16rem] truncate',
  },
];
const {
  orderedColumns: itemCols,
  visibleColumns: visibleItemCols,
  hiddenKeys: hiddenItemColKeys,
  isHidden: isItemColHidden,
  toggleColumn: toggleItemCol,
  showAllColumns: showAllItemCols,
  isDragging: isItemColDragging,
  onColDragStart: onItemColDragStart,
  onColDrop: onItemColDrop,
  resetOrder: resetItemCols,
  colStyle: itemColStyle,
  isResizing: isItemColResizing,
  startResize: startItemColResize,
  autoFitColumn: autoFitItemCol,
} = useOrderableColumns(ITEM_COLUMN_DEFS, 'mes.poItemCols.v2');

// 明细视图的行级过滤。后端的列筛选筛的是**单**：一张采购单只要有一行对上就整张留下。
// 按单看没问题（供应商那列本来就列全部几家），摊成明细后这张单里其他供应商、其他物料的行
// 也跟着铺出来，看着就是「筛了没反应」——采购单一单多家供应商是常态，这里比入库单更明显
// （同 10.19 原料入库那条）。所以明细视图再按同一个关键字把行过一遍。
// 只过行上真有的那几列——单号、销售订单号是单据级的，不参与。
const ROW_FILTER_FIELDS = {
  supplier: 'supplier',
  item_code: 'code',
  item_name: 'name',
  item_spec: 'spec',
};
const matchesRowFilters = row =>
  Object.entries(ROW_FILTER_FIELDS).every(([key, field]) => {
    const v = (colFilters[key] || '').trim().toLowerCase();
    return (
      !v ||
      String(row[field] || '')
        .toLowerCase()
        .includes(v)
    );
  });

// 把当页采购单摊平成「一行一条料」。只摊当页、不额外请求——列表本来就带明细。
const itemRows = computed(() =>
  records.value
    .flatMap(po =>
      (po.purchaseItems || []).map(it => ({
        key: `${po.id}-${it.id}`,
        po,
        poNo: po.poNo,
        // 这家供应商在本单下的子流水号（PU-xxxx-01 / -02 …）。按单视图展开供应商时有，
        // 按明细这边原来没有——仓库查物料、财务对账单都是认这个号的，看不到就对不上账
        // （10.19 反馈：「这些流水号要显示到按明细那边去啊」）。
        supplierNo:
          (po.suppliers || []).find(
            sp => String(sp.id || '') === String(it.mesSupplierId || '')
          )?.no || '',
        docDate: po.docDate,
        supplier: it.supplierName || '—',
        code: it.productSku || it.materialNo || '—',
        name: it.productName || it.materialName || '—',
        spec: it.specification || '—',
        aux: it.auxAttributeName || '—',
        productRemark: it.productRemark || '—',
        qty: it.qty,
        received: it.receivedQty,
        unit: it.unit || '',
        taxRate: it.supplierTaxRate,
        untaxedRate: it.untaxedRateMicros,
        taxedRate: it.taxedRateMicros,
        untaxedAmount: it.untaxedAmountMicros,
        taxedAmount: it.taxedAmountMicros,
        arrival: it.arrivalDate,
        itemRemark: it.remark || '—',
        internalRemark: po.internalRemark || '—',
      }))
    )
    .filter(matchesRowFilters)
);

// 同一张采购单的连续行标记成一组：单号只在组首显示，组尾加一条分隔线。
//
// 一张生产订单本来就能开好几张采购单（主料一张、辅料一张、不同采购员各建各的），
// 所以按明细里同一张生产单下会连着出现 PU-…-06 / -07 / -08。原来每行都重复印单号，
// 看着像「同一批料的单号对不上」（10.17 反馈 B6：「这个订单号好像不是一个」）。
// 归组之后哪几行属于同一张单一目了然，数据本身不动。
const groupedItemRows = computed(() =>
  itemRows.value.map((r, i, arr) => ({
    ...r,
    firstOfPo: i === 0 || arr[i - 1].poNo !== r.poNo,
    lastOfPo: i === arr.length - 1 || arr[i + 1].poNo !== r.poNo,
  }))
);

// 列多撑得比屏幕宽，只能拖底下那根细横条，鼠标很难受。
// 跟生产订单一样：把平时不看的列收起来，按人记在本机。
// ⚠️「列」面板和「恢复默认列序」必须跟着当前视图走：两个视图列集完全不同，
// 若恒指向按单那套，切到明细后点「列」勾的是看不见的那张表的列（点了没反应）。
const showColumnPanel = ref(false);
const isItemView = computed(() => viewMode.value === 'item');
const activeCols = computed(() =>
  isItemView.value ? itemCols.value : orderCols.value
);
const activeIsHidden = key =>
  isItemView.value ? isItemColHidden(key) : isOrderColHidden(key);
const activeToggleCol = key =>
  isItemView.value ? toggleItemCol(key) : toggleOrderCol(key);
const activeShowAllCols = () =>
  isItemView.value ? showAllItemCols() : showAllOrderCols();
const activeResetCols = () =>
  isItemView.value ? resetItemCols() : resetOrderCols();
const hiddenCols = computed(
  () =>
    (isItemView.value ? hiddenItemColKeys.value : hiddenOrderColKeys.value)
      .length
);

// 导出 Excel：跟着当前视图走——「按单」导单据级，「按明细」一行料一行。
// 金额列只给看得见金额的岗位（采购/财务/管理员）；其余岗位后端压根不下发金额，
// 列留着就是一整列空，不如不出。
// ⚠️ 全量：列表一页 15 张，导出重新向后端分页要完，不是导屏幕这一页。
// 注意这里走接口直拉，字段是未驼峰化的原始 payload（下划线）。
const exporting = ref(false);
const exportList = async () => {
  exporting.value = true;
  try {
    const pos = await fetchAllRows(params => MesPurchaseOrderAPI.get(params), {
      q: search.value.trim() || undefined,
      owner_id: onlyMine.value ? currentUserId.value : undefined,
    });
    const moneyCols = canViewAmount.value;
    const config = isItemView.value
      ? {
          title: '采购单明细',
          columns: [
            { label: '采购单号', key: 'po_no' },
            { label: '供应商', key: 'supplier_name' },
            { label: '物料编码', key: 'code' },
            { label: '名称', key: 'name' },
            { label: '规格型号', key: 'specification' },
            { label: '辅助属性', key: 'aux_attribute_name' },
            { label: '档案备注', key: 'product_remark' },
            { label: '采购量', key: 'qty', num: true },
            { label: '已到料', key: 'received_qty', num: true },
            { label: '单位', key: 'unit' },
            ...(moneyCols
              ? [
                  {
                    label: '未税单价',
                    key: 'untaxed_rate_micros',
                    money: true,
                  },
                  { label: '含税单价', key: 'taxed_rate_micros', money: true },
                  { label: '税率(%)', key: 'supplier_tax_rate', num: true },
                  {
                    label: '未税合计',
                    key: 'untaxed_amount_micros',
                    money: true,
                  },
                  {
                    label: '含税合计',
                    key: 'taxed_amount_micros',
                    money: true,
                  },
                ]
              : []),
            { label: '销售订单', key: 'production_order_no' },
            { label: '实际到料', key: 'arrival_date' },
            { label: '备注', key: 'remark' },
            { label: '对内备注', key: 'internal_remark' },
          ],
          rows: pos.flatMap(po =>
            (po.purchase_items || []).map(item => ({
              po_no: po.po_no,
              production_order_no: po.production_order_no,
              supplier_name: item.supplier_name,
              code: item.product_sku || item.material_no,
              name: item.product_name || item.material_name,
              specification: item.specification,
              aux_attribute_name: item.aux_attribute_name,
              product_remark: item.product_remark,
              qty: item.qty,
              received_qty: item.received_qty,
              unit: item.unit,
              rate_micros: item.rate_micros,
              supplier_tax_rate: item.supplier_tax_rate,
              amount_micros: item.amount_micros,
              arrival_date: item.arrival_date,
              remark: item.remark,
              internal_remark: po.internal_remark,
            }))
          ),
        }
      : {
          title: '采购单',
          columns: [
            { label: '采购单号', key: 'po_no' },
            { label: '供应商', key: 'suppliers' },
            { label: '销售订单', key: 'production_order_no' },
            { label: '归属人', key: 'production_order_owner_name' },
            { label: '下单人', key: 'owner_name' },
            { label: '收货状态', key: 'status' },
            ...(moneyCols
              ? [{ label: '总额', key: 'total_amount_micros', money: true }]
              : []),
            { label: '审批', key: 'approval_status' },
            { label: '回复交期', key: 'expected_date' },
            { label: '交货时间', key: 'delivery_date' },
            { label: '对内备注', key: 'internal_remark' },
            { label: '备注', key: 'remark' },
          ],
          rows: pos.map(po => ({
            ...po,
            suppliers: (po.supplier_names || []).join('、'),
          })),
        };
    exportRowsToExcel(
      {
        ...config,
        meta: [
          {
            label: '导出时间',
            value: new Date().toLocaleString('sv').slice(0, 16),
          },
          { label: '关键字', value: search.value.trim() || '（无）' },
          { label: '范围', value: onlyMine.value ? '只看我下的单' : '全部' },
          { label: '采购单数', value: pos.length },
          { label: '行数', value: config.rows.length },
        ],
      },
      `${config.title}_${new Date().toLocaleDateString('sv')}`
    );
  } catch (error) {
    useAlert('导出失败，请重试');
  } finally {
    exporting.value = false;
  }
};

// 查看弹窗里的明细列（不是列表的列）。

const VIEW_ITEM_COLS = [
  { label: '类型', key: 'typeLabel' },
  { label: '编码', key: 'code' },
  { label: '名称', key: 'name' },
  { label: '规格型号', key: 'spec', wrap: true },
  // 辅助属性 + 产品档案上工程写的备注：金蝶会自动带到生产单和采购单，
  // 这两样都是要发给供应商看的，原来查看页上没有（反馈提了两次）。
  { label: '辅助属性', key: 'auxAttributeName' },
  { label: '档案备注', key: 'productRemark', wrap: true },
  { label: '供应商', key: 'supplierName', wrap: true },
  { label: '采购量', key: 'qty', align: 'right' },
  { label: '已到料', key: 'receivedQty', align: 'right' },
  { label: '单位', key: 'unit' },
  { label: '未税单价', key: 'untaxedRate', align: 'right' },
  { label: '含税单价', key: 'taxedRate', align: 'right' },
  { label: '税率', key: 'taxRate', align: 'right' },
  { label: '未税合计', key: 'untaxedAmount', align: 'right' },
  { label: '含税合计', key: 'taxedAmount', align: 'right' },
  { label: '实际到料时间', key: 'arrival' },
  { label: '备注', key: 'remark', wrap: true },
  // 附图摆在明细行自己那一行的最右边（原来另起一块按行分组列在表下面，
  // 要在两处之间来回对「这是第几行的图」）。type:'images' 由 MesViewDialog 渲染缩略图，
  // 点开在页内放大；这列不进 Excel 导出。
  { label: '附图（仅内部）', key: 'images', type: 'images' },
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
      auxAttributeName: it.auxAttributeName || '—',
      productRemark: it.productRemark || '—',
      supplierName: it.supplierName || '—',
      qty: it.qty,
      receivedQty: it.receivedQty,
      unit: it.unit,
      taxRate: it.supplierTaxRate ? `${it.supplierTaxRate}%` : '—',
      untaxedRate: yuan(it.untaxedRateMicros),
      taxedRate: yuan(it.taxedRateMicros),
      untaxedAmount: yuan(it.untaxedAmountMicros),
      taxedAmount: yuan(it.taxedAmountMicros),
      arrival: day(it.arrivalDate),
      remark: it.remark,
      images: it.images || [],
    }))
);

const productionOrders = ref([]);

// 从站内通知点「待审批采购单」进来：落地后直接把那张单的详情弹窗打开，
// 明细和「通过/驳回」都在弹窗里——否则人跳过来还得横向滑到最右才点得到按钮。
// 只对「待我审批」的单自动开，普通按单号定位（如查进度）不打扰。
// 采购单号常要贴进聊天/邮件里问供应商，手抄容易错一位。
const copyNo = async no => {
  if (!no) return;
  await copyTextToClipboard(String(no));
  useAlert(`已复制 ${no}`);
};

const autoOpenApproval = async poNo => {
  if (!poNo) return;
  await nextTick();
  const hit = records.value.find(p => p.poNo === poNo);
  if (hit && canApprove(hit)) openView(hit);
};

onMounted(async () => {
  await fetchList();
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
  if (route.query.q) autoOpenApproval(String(route.query.q));
});

// 从站内通知带着新单号再次进来：本页在 keep-alive 里缓存着，onMounted 不会再跑，
// 不补这一道的话搜索框还是上次的值、列表也不重拉。
useRouteQueryReentry(async query => {
  search.value = query.q ? String(query.q) : '';
  await fetchList();
  autoOpenApproval(search.value);
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
        采购单
      </h1>
      <div class="flex items-center gap-2">
        <!-- h-8 和同排的按钮等高：不给高度它就只有一行文字那么高（24px），
             和旁边 32px 的控件一比就是没对齐。 -->
        <button
          type="button"
          class="inline-flex items-center h-8 px-1 text-xs text-n-slate-10 hover:text-n-iris-11"
          title="把当前视图的表头顺序恢复成默认，并放出收起的列"
          @click="activeResetCols"
        >
          恢复默认列序
        </button>
        <!-- 按单 / 按明细：核对物料时要的是明细那一屏（对标金蝶）。
             走全站页面级 Tab 的统一标记（data-tabbar + aria-selected，样式在
             _next-colors.scss），别再自己写灰槽白条。 -->
        <!-- 这条 tab 和按钮并排在工具栏里，得压到同样 32px 高：全局 [data-tabbar] 规则
             给了 margin-block 和更大的内边距（别处它自己占一行，38px 正好），
             属性选择器特指度比 my-0 高，所以这里要带 ! 才盖得住。 -->
        <div data-tabbar="page" class="!my-0 [&>button]:!h-[26px]">
          <button
            v-for="m in VIEW_MODES"
            :key="m.key"
            :aria-selected="viewMode === m.key"
            @click="viewMode = m.key"
          >
            {{ m.label }}
          </button>
        </div>
        <!-- 收起用不到的列：列少了就不用横着拖滚动条（同生产订单） -->
        <div class="relative">
          <Button
            :label="hiddenCols ? `列（收起 ${hiddenCols}）` : '列'"
            variant="outline"
            color="slate"
            size="sm"
            class="btn-ink"
            icon="i-lucide-columns-3"
            @click="showColumnPanel = !showColumnPanel"
          />
          <!-- 透明兜底层：点面板外面收起来，省掉一个全局 click 监听 -->
          <div
            v-if="showColumnPanel"
            class="fixed inset-0 z-10"
            @click="showColumnPanel = false"
          />
          <div
            v-if="showColumnPanel"
            class="absolute right-0 z-20 flex flex-col gap-1 p-2 mt-1 border shadow-lg top-full w-52 rounded-xl border-n-weak bg-n-solid-1"
          >
            <label
              v-for="col in activeCols"
              :key="`vis-${col.key}`"
              class="flex items-center gap-2 px-2 py-1 rounded cursor-pointer text-label-small hover:bg-n-alpha-1"
            >
              <input
                type="checkbox"
                :checked="!activeIsHidden(col.key)"
                @change="activeToggleCol(col.key)"
              />
              {{ col.label }}
            </label>
            <button
              class="px-2 py-1 mt-1 text-left border-t text-label-small text-n-slate-11 border-n-weak hover:text-n-slate-12"
              @click="activeShowAllCols"
            >
              全部显示
            </button>
          </div>
        </div>
        <Button
          :label="compact ? '宽松行高' : '紧凑行高'"
          variant="ghost"
          color="slate"
          size="sm"
          @click="toggleDensity"
        />
        <!-- 导出是只读动作，不挂采购写权限；金额列按 canViewAmount 决定出不出 -->
        <Button
          label="导出 Excel"
          color="slate"
          variant="faded"
          size="sm"
          :is-loading="exporting"
          @click="exportList"
        />
        <Button
          v-if="mesCan('purchase')"
          label="新建采购单"
          color="iris"
          size="sm"
          @click="goCreate()"
        />
      </div>
    </div>

    <MesBoardOwnerBar
      board-key="mes_purchase_orders_index"
      :extra-boards="APPROVER_BOARD"
    />

    <!-- 搜索：单号/供应商/归属人/生产订单/物料编码 -->
    <div
      class="flex items-center gap-2 px-4 pt-1 pb-2 sm:px-6 [.theme-classic_&]:sm:!px-8"
    >
      <input
        v-model="search"
        type="text"
        placeholder="搜索单号 / 供应商 / 归属人 / 销售订单 / 物料编码"
        class="w-80 h-9 px-3 mb-0 text-sm rounded-lg reset-base outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-9 hover:outline-n-brand focus:outline-n-brand"
      />
      <SelectCard
        v-model="statusFilter"
        :options="STATUS_FILTER_OPTIONS"
        @update:model-value="resetToFirstPage"
      />
      <SelectCard
        v-model="approvalFilter"
        :options="APPROVAL_FILTER_OPTIONS"
        @update:model-value="resetToFirstPage"
      />
      <label
        class="flex items-center gap-1.5 text-sm cursor-pointer select-none text-n-slate-11"
      >
        <input v-model="onlyMine" type="checkbox" class="reset-base w-3.5" />
        只看我下的单
      </label>
      <span class="text-sm text-n-slate-11">共 {{ totalCount }} 条</span>
    </div>

    <HScrollButtons />
    <div
      class="flex-1 min-h-0 px-4 pb-4 overflow-auto sm:px-6 sm:pb-6 [.theme-classic_&]:sm:!px-8"
    >
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
              <MesStatusPill
                class="shrink-0"
                :label="STATUS_LABELS[p.status]"
              />
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
              <MesSupplierSummary
                :names="p.supplierNames || []"
                :suppliers="p.suppliers || []"
              />
            </div>
            <div class="flex flex-wrap mt-1 gap-3 text-xs text-n-slate-11">
              <span>销售订单：{{ p.productionOrderNo || '—' }}</span>
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
        <!-- 列可拖拽改顺序、可在「列」里收起，顺序与显隐都按人记在本机；操作列固定在最后 -->
        <table
          v-if="viewMode === 'order'"
          class="hidden w-full text-sm whitespace-nowrap md:table"
        >
          <thead>
            <tr
              class="text-left text-n-slate-11 [&>th]:sticky [&>th]:top-0 [&>th]:z-10 [&>th]:bg-n-solid-1 [&>th]:border-b [&>th]:border-n-weak"
            >
              <th
                v-for="col in visibleOrderCols"
                :key="col.key"
                draggable="true"
                class="relative px-3 py-3 font-medium transition-colors cursor-move select-none whitespace-nowrap"
                :class="[
                  col.thClass,
                  isOrderColDragging(col.key) ? 'opacity-40' : '',
                ]"
                :style="orderColStyle(col.key)"
                title="拖动可调整列顺序"
                @dragstart="onOrderColDragStart(col.key)"
                @dragover.prevent
                @drop="onOrderColDrop(col.key)"
              >
                <span class="inline-flex items-center gap-1">
                  {{ col.label }}
                  <MesColumnFilter
                    v-if="filterOf(col)"
                    v-model="colFilters[filterOf(col).key]"
                    type="text"
                    :placeholder="filterOf(col).placeholder"
                    @change="onColFilterChange"
                  />
                </span>
                <ColResizeHandle
                  :column-key="col.key"
                  :active="isOrderColResizing(col.key)"
                  @resize-start="(e, th) => startOrderColResize(col.key, e, th)"
                  @auto-fit="autoFitOrderCol"
                />
              </th>
              <th
                class="px-3 py-3 sticky right-0 z-10 bg-n-solid-1 border-l border-n-weak after:absolute after:inset-y-0 after:left-full after:w-8 after:bg-n-solid-1 after:content-['']"
              />
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="(p, i) in records"
              :key="p.id"
              class="border-b group/row border-n-weak"
            >
              <td
                v-for="col in visibleOrderCols"
                :key="col.key"
                :class="[
                  col.tdClass,
                  orderColStyle(col.key).width && 'truncate',
                ]"
                :style="orderColStyle(col.key)"
              >
                <template v-if="col.key === 'idx'">{{ i + 1 }}</template>
                <template v-else-if="col.key === 'poNo'">
                  <span
                    class="inline-flex items-center gap-1 whitespace-nowrap"
                  >
                    <MesMultiNoCell :value="p.poNo" />
                    <button
                      v-if="p.poNo"
                      v-tooltip.top="'复制采购单号'"
                      type="button"
                      class="transition-opacity opacity-0 i-lucide-copy size-3.5 shrink-0 text-n-slate-10 hover:text-n-iris-11 group-hover/row:opacity-100"
                      @click.stop="copyNo(p.poNo)"
                    />
                  </span>
                  <span
                    v-if="p.hasException"
                    v-tooltip.top="exceptionTip(p)"
                    class="ml-1 text-xs cursor-help text-n-ruby-11"
                  >
                    ⚠
                  </span>
                </template>
                <template v-else-if="col.key === 'suppliers'">
                  <MesSupplierSummary
                    :names="p.supplierNames || []"
                    :suppliers="p.suppliers || []"
                  />
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
                  <MesStatusPill :label="STATUS_LABELS[p.status]" />
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
                <template v-else-if="col.key === 'docDate'">
                  {{ day(p.docDate) }}
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
                <template v-else-if="col.key === 'salesOrderRemark'">
                  <span :title="p.salesOrderRemark || ''">
                    {{ p.salesOrderRemark || '—' }}
                  </span>
                </template>
                <template v-else-if="col.key === 'bomRemark'">
                  <span :title="p.bomRemark || ''">
                    {{ p.bomRemark || '—' }}
                  </span>
                </template>
              </td>
              <td
                class="px-3 py-3 text-right whitespace-nowrap sticky right-0 z-10 bg-n-solid-1 border-l border-n-weak after:absolute after:inset-y-0 after:left-full after:w-8 after:bg-n-solid-1 after:content-['']"
              >
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
                  <!-- 关闭 / 启用 / 删除。操作列已经很挤，三个都只放图标。
                       外面这层固定占位：只有部分行多出图标的话，整行按钮会被往左顶，
                       跟上下行对不齐（用户反馈「UI 没对齐」）。 -->
                  <span class="inline-flex justify-center size-4 shrink-0">
                    <button
                      v-if="canClose(p)"
                      type="button"
                      title="关闭本单（之后可再启用）"
                      class="i-lucide-circle-slash size-4 text-n-slate-10 hover:text-n-amber-11"
                      @click="closeOrder(p)"
                    />
                    <button
                      v-else-if="canReopen(p)"
                      type="button"
                      title="重新启用"
                      class="i-lucide-rotate-ccw size-4 text-n-slate-10 hover:text-n-teal-11"
                      @click="reopenOrder(p)"
                    />
                  </span>
                  <span class="inline-flex justify-center size-4 shrink-0">
                    <button
                      v-if="canDelete(p)"
                      type="button"
                      title="删除本单"
                      class="i-lucide-trash-2 size-4 text-n-slate-10 hover:text-n-ruby-11"
                      @click="removeOrder(p)"
                    />
                  </span>
                </div>
              </td>
            </tr>
            <tr v-if="!records.length">
              <td
                :colspan="visibleOrderCols.length + 1"
                class="px-3 py-10 text-center text-n-slate-11"
              >
                还没有采购单。
              </td>
            </tr>
          </tbody>
        </table>

        <!-- 明细视图：一行一条料（对标金蝶采购订单明细）。数据来自当页采购单自带的
             明细，不额外请求；列同样可拖拽、可在「列」里收起。 -->
        <table
          v-else
          class="hidden w-full text-sm border-separate border-spacing-0 whitespace-nowrap md:table"
        >
          <thead>
            <tr
              class="text-left text-n-slate-11 [&>th]:sticky [&>th]:top-0 [&>th]:z-10 [&>th]:bg-n-solid-1 [&>th]:border-b [&>th]:border-n-weak"
            >
              <th
                v-for="col in visibleItemCols"
                :key="col.key"
                draggable="true"
                class="relative px-3 py-2 font-medium transition-colors cursor-move select-none whitespace-nowrap"
                :class="[
                  col.thClass,
                  isItemColDragging(col.key) ? 'opacity-40' : '',
                ]"
                :style="itemColStyle(col.key)"
                title="拖动可调整列顺序"
                @dragstart="onItemColDragStart(col.key)"
                @dragover.prevent
                @drop="onItemColDrop(col.key)"
              >
                <span class="inline-flex items-center gap-1">
                  {{ col.label }}
                  <MesColumnFilter
                    v-if="filterOf(col)"
                    v-model="colFilters[filterOf(col).key]"
                    type="text"
                    :placeholder="filterOf(col).placeholder"
                    @change="onColFilterChange"
                  />
                </span>
                <ColResizeHandle
                  :column-key="col.key"
                  :active="isItemColResizing(col.key)"
                  @resize-start="(e, th) => startItemColResize(col.key, e, th)"
                  @auto-fit="autoFitItemCol"
                />
              </th>
              <th
                class="sticky right-0 z-10 bg-n-solid-1 border-l border-n-weak after:absolute after:inset-y-0 after:left-full after:w-8 after:bg-n-solid-1 after:content-[''] px-3 py-2"
              />
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="(r, i) in groupedItemRows"
              :key="r.key"
              class="[&>td]:border-b [&:hover>td:not(.sticky)]:bg-n-alpha-1"
              :class="
                r.lastOfPo
                  ? '[&>td]:border-n-strong'
                  : '[&>td]:border-n-weak/40'
              "
            >
              <td
                v-for="col in visibleItemCols"
                :key="col.key"
                :class="[
                  col.tdClass,
                  itemColStyle(col.key).width && 'truncate',
                ]"
                :style="itemColStyle(col.key)"
              >
                <template v-if="col.key === 'idx'">{{ i + 1 }}</template>
                <template v-else-if="col.key === 'poNo'">
                  <!-- 单号只在这组第一行印一次：一张生产单下常有好几张采购单，
                       每行都重复印反而让人以为单号对不上 -->
                  <MesMultiNoCell v-if="r.firstOfPo" :value="r.poNo" />
                  <span v-else class="text-n-slate-9">〃</span>
                </template>
                <template v-else-if="col.key === 'supplier'">
                  {{ r.supplier }}
                </template>
                <template v-else-if="col.key === 'supplierNo'">
                  {{ r.supplierNo || '—' }}
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
                <template v-else-if="col.key === 'untaxedRate'">
                  {{ canViewAmount ? yuan(r.untaxedRate) : '—' }}
                </template>
                <template v-else-if="col.key === 'taxedRate'">
                  {{ canViewAmount ? yuan(r.taxedRate) : '—' }}
                </template>
                <template v-else-if="col.key === 'productRemark'">
                  <span :title="r.productRemark">{{ r.productRemark }}</span>
                </template>
                <template v-else-if="col.key === 'taxRate'">
                  {{ r.taxRate == null ? '—' : `${r.taxRate}%` }}
                </template>
                <template v-else-if="col.key === 'untaxedAmount'">
                  {{ canViewAmount ? yuan(r.untaxedAmount) : '—' }}
                </template>
                <template v-else-if="col.key === 'taxedAmount'">
                  {{ canViewAmount ? yuan(r.taxedAmount) : '—' }}
                </template>
                <template v-else-if="col.key === 'order'">
                  {{ orderNosLabel(r.po.relatedProductionOrderNos) }}
                </template>
                <template v-else-if="col.key === 'docDate'">
                  {{ day(r.docDate) }}
                </template>
                <template v-else-if="col.key === 'arrival'">
                  {{ day(r.arrival) }}
                </template>
                <template v-else-if="col.key === 'itemRemark'">
                  <span :title="r.itemRemark">{{ r.itemRemark }}</span>
                </template>
                <template v-else-if="col.key === 'internalRemark'">
                  <span :title="r.internalRemark">{{ r.internalRemark }}</span>
                </template>
              </td>
              <td
                class="sticky right-0 z-10 px-3 py-2 text-right border-l bg-n-solid-1 border-n-weak whitespace-nowrap after:absolute after:inset-y-0 after:left-full after:w-8 after:bg-n-solid-1 after:content-['']"
              >
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
                :colspan="visibleItemCols.length + 1"
                class="px-3 py-10 text-center text-n-slate-11"
              >
                这一页的采购单还没有明细。
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
              <div class="flex items-center gap-1.5">
                <label class="flex items-center min-w-0 gap-1.5 cursor-pointer">
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
                <!-- 一张单挂十几家时，想单看一家得把其余十几个勾一个个取消——
                     给个一步到位的（10.19 反馈「不能单独选择某家查看」）。 -->
                <button
                  v-if="previewSuppliers.length > 1 && s.id"
                  type="button"
                  class="shrink-0 text-xs text-n-iris-11 hover:underline"
                  @click="onlyThisSupplier(s)"
                >
                  只看这家
                </button>
                <span class="flex-1" />
                <button
                  v-if="previewSuppliers.length > 1 && isOnlyChecked(s)"
                  type="button"
                  class="shrink-0 text-xs text-n-slate-11 hover:underline"
                  @click="checkAllSuppliers"
                >
                  看全部
                </button>
              </div>
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

    <!-- 采购明细 16 列（编码/名称/规格/辅助属性/档案备注/供应商/采购量/已到料/单位/
         未税单价/含税单价/税率/未税合计…），6xl 挤成一团，用 full 按视口铺开。 -->
    <MesViewDialog
      ref="viewDialogRef"
      width="full"
      :title="viewing ? `采购单 ${viewing.poNo}` : '采购单明细'"
      :fields="viewFields"
      items-title="采购明细"
      :item-columns="VIEW_ITEM_COLS"
      :items="viewItems"
    >
      <!-- 待我审批的单：明细下面直接给「通过 / 驳回」 -->
      <template v-if="viewing && canApprove(viewing)" #actions>
        <template v-if="rejecting">
          <Input
            v-model="rejectReason"
            size="sm"
            placeholder="驳回原因"
            class="w-72"
            @keyup.enter="confirmRejectFromView"
          />
          <Button
            label="取消"
            variant="ghost"
            color="slate"
            size="sm"
            @click="rejecting = false"
          />
          <Button
            label="确认驳回"
            color="ruby"
            size="sm"
            :is-loading="acting"
            @click="confirmRejectFromView"
          />
        </template>
        <template v-else>
          <Button
            label="驳回"
            variant="outline"
            color="ruby"
            size="sm"
            @click="rejecting = true"
          />
          <Button
            label="通过"
            color="amber"
            size="sm"
            :is-loading="acting"
            @click="approveFromView"
          />
        </template>
      </template>
    </MesViewDialog>
  </div>
</template>
