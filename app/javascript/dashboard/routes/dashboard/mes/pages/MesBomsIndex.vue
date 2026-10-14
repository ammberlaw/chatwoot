<script setup>
/* global axios */
import { ref, computed, reactive, watch, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesBomsStore } from 'dashboard/stores/mes/boms';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import ColResizeHandle from 'dashboard/components-next/table/ColResizeHandle.vue';
import { useListDensity } from 'dashboard/composables/useListDensity';
import MesBomAPI from 'dashboard/api/mes/boms';
import MesProductionOrderAPI from 'dashboard/api/mes/productionOrders';

import Button from 'dashboard/components-next/button/Button.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import {
  exportNodeToJpg,
  exportDataToExcel,
  printNode,
} from 'dashboard/helper/mesExport';
import MesBoardOwnerBar from 'dashboard/components-next/mes/MesBoardOwnerBar.vue';
import MesHiddenLineHint from 'dashboard/components-next/mes/MesHiddenLineHint.vue';
import { useMesRole } from 'dashboard/composables/useMesRole';
import { useOrderableColumns } from 'dashboard/composables/useOrderableColumns';
import { useMesDocOwner } from 'dashboard/composables/useMesDocOwner';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import MesColumnFilter from 'dashboard/components-next/mes/MesColumnFilter.vue';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
const { accountId, accountScopedRoute } = useAccount();
const router = useRouter();
const route = useRoute();
const rootStore = useStore();

// 外购成品不经过生产：直接跳采购单页，自动进「成品(外购)」建单模式。
const goProductPurchase = () =>
  router.push(
    accountScopedRoute('mes_purchase_orders_index', {}, { new: 'product' })
  );
const store = useMesBomsStore();

// 新建/编辑都跳建档页（整页录入，弹窗装不下几十行用料明细）。
const goCreate = (query = {}) =>
  router.push(accountScopedRoute('mes_bom_intake_index', {}, query));
const goEdit = bom =>
  router.push(accountScopedRoute('mes_bom_intake_index', {}, { id: bom.id }));
// 后端 BomsController 固定每页 15 条且不认 per_page，这里必须对齐，否则页码算错。
const ITEMS_PER_PAGE = 15;
const currentPage = ref(1);
const { mesCan } = useMesRole();
// 行高：宽松/紧凑一键切，记在本机（反馈：间距太长想自己拉短）
const { compact, toggleDensity } = useListDensity();
const { isMyDoc } = useMesDocOwner();
// 谁制单谁改：非建单人不露编辑（后端 ensure_owner_or_admin! 同样拦）。
const canEditRow = b => mesCan('bom') && isMyDoc(b);

// 单号以「投单单号」为准——那是纸质单从下发到采购到生产全程认的号。
// 没填才回落系统自动号。原来列表显示自动号、明细显示投单单号，同一张单两个号。
const bomNoOf = b => b.docNo || b.bomNo;

// 中间列可拖拽重排，顺序按人记在本机。首列「#」和末列操作按钮固定，拖它们没意义。
// 所有单元格一律 whitespace-nowrap：列一多就被挤成「WT-/RUG100」「已下/发」这种断行，
// 一屏看下来全是参差（用户反馈「显得页面很不整洁」）。宁可横向滚，不折行。
const COLUMN_DEFS = [
  {
    key: 'no',
    label: '生产任务单号',
    tdClass: 'px-3 py-3 font-medium whitespace-nowrap text-n-slate-12',
  },
  {
    key: 'model',
    label: '型号 / 成品',
    tdClass: 'px-3 py-3 whitespace-nowrap',
  },
  {
    key: 'owner',
    label: '负责人',
    tdClass: 'px-3 py-3 whitespace-nowrap text-n-slate-11',
  },
  {
    key: 'salesOwner',
    label: '归属业务员',
    tdClass: 'px-3 py-3 whitespace-nowrap text-n-slate-11',
  },
  // 对标纸质投单：日期和产成品代码是核单时最先对的两样，原来要点开查看才看得到
  {
    key: 'customerName',
    label: '客户 / 项目',
    tdClass: 'px-3 py-3 whitespace-nowrap text-n-slate-11',
  },
  {
    key: 'submitDate',
    label: '投单日期',
    tdClass: 'px-3 py-3 whitespace-nowrap text-n-slate-11',
  },
  {
    key: 'productCode',
    label: '产成品代码',
    tdClass: 'px-3 py-3 tabular-nums whitespace-nowrap text-n-slate-11',
  },
  {
    key: 'baseQty',
    label: '基准产量',
    tdClass: 'px-3 py-3 whitespace-nowrap text-n-slate-11',
  },
  {
    key: 'items',
    label: '用料项',
    tdClass: 'px-3 py-3 whitespace-nowrap text-n-slate-11',
  },
  {
    key: 'leadDays',
    label: '预估周期(天)',
    tdClass: 'px-3 py-3 whitespace-nowrap text-n-slate-11',
  },
  { key: 'status', label: '状态', tdClass: 'px-3 py-3 whitespace-nowrap' },
];
const {
  orderedColumns,
  isDragging,
  onColDragStart,
  onColDrop,
  resetOrder,
  colStyle,
  isResizing,
  startResize,
  autoFitColumn,
} = useOrderableColumns(COLUMN_DEFS, 'mes.bomCols.v1');

// 列表里就地看用料明细：PMC 核对一张单的料，原先得点「查看」开弹窗、关掉再开下一张。
// 不直接把明细摊成多行——一张任务单二十几项料，五张单的列表就变成上百行，没法看了。
const expandedIds = ref(new Set());
const toggleItems = bom => {
  const next = new Set(expandedIds.value);
  if (next.has(bom.id)) next.delete(bom.id);
  else next.add(bom.id);
  expandedIds.value = next;
};
// 展开行要横跨整张表：序号列 + 中间可拖拽的那些列 + 末尾操作列。
const totalColSpan = computed(() => orderedColumns.value.length + 2);

const records = computed(() => store.getRecords);
const totalCount = computed(() => store.getMeta.count || 0);
const hiddenNoLine = computed(() => store.getMeta.hiddenNoLine || 0);
// 顶部筛选条。条件发给后端，不在前端过滤本页——列表分页，本页过滤只会在第 1 页里挑，
// 后面的命中全看不见。（原来做成表头漏斗，二十几个列头上挂一排小图标太碎，改回顶部一条。）
const colFilters = reactive({
  no: '',
  model: '',
  product_code: '',
  customer_name: '',
  owner_id: '',
  sales_owner_id: '',
  status: '',
  submitDate: { from: '', to: '' },
});
// 列 key → 这一列筛什么（对标金蝶表头上的漏斗）。条件发后端算：列表是分页的，
// 前端只过滤本页的话，第 2 页往后的命中全看不见。
const FILTERABLE = {
  no: { type: 'text', key: 'no', placeholder: '单号 / 投单单号' },
  model: { type: 'text', key: 'model', placeholder: '型号 / 成品名' },
  productCode: { type: 'text', key: 'product_code', placeholder: '产成品代码' },
  customerName: {
    type: 'text',
    key: 'customer_name',
    placeholder: '客户 / 项目',
  },
  submitDate: { type: 'date', key: 'submitDate' },
};
const filterOf = col => FILTERABLE[col.key];

const STATUS_FILTER_OPTIONS = [
  { value: '', label: '全部状态' },
  { value: 'RELEASED', label: '已下发' },
  { value: 'DRAFT', label: '草稿' },
];
// 负责人/归属业务员的候选从当前这页的数据里取：不额外拉一份全员名单，
// 列表里没出现过的人选了也是空结果。
// 「全部」那项要写明是哪一个——两个下拉并排都显示「全部」，分不清哪个是哪个。
// 这页的单本来就没人挂负责人时，下拉里只剩「全部」一项，点开什么都没有：
// 这种情况整个下拉不显示（见模板里的 v-if），别摆一个点了没反应的控件。
const peopleOptions = (idKey, nameKey, allLabel) => [
  { value: '', label: allLabel },
  ...Array.from(
    new Map(
      records.value
        .filter(row => row[idKey])
        .map(row => [String(row[idKey]), row[nameKey] || '—'])
    )
  ).map(([value, label]) => ({ value, label })),
];
const ownerOptions = computed(() =>
  peopleOptions('ownerId', 'ownerName', '全部负责人')
);
const salesOwnerOptions = computed(() =>
  peopleOptions('salesOwnerId', 'salesOwnerName', '全部业务员')
);
const activeFilterCount = computed(
  () =>
    Object.entries(colFilters).filter(([k, v]) =>
      k === 'submitDate' ? v.from || v.to : v
    ).length
);
// 列表取数统一走这里：翻页只改 currentPage，由 watch 触发重拉。
const load = () =>
  store.get({
    page: currentPage.value,
    no: colFilters.no || undefined,
    model: colFilters.model || undefined,
    product_code: colFilters.product_code || undefined,
    customer_name: colFilters.customer_name || undefined,
    owner_id: colFilters.owner_id || undefined,
    sales_owner_id: colFilters.sales_owner_id || undefined,
    status: colFilters.status || undefined,
    submit_from: colFilters.submitDate.from || undefined,
    submit_to: colFilters.submitDate.to || undefined,
  });
const isFetching = computed(() => store.getUIFlags.fetchingList);

const onFilterChange = () => {
  // 筛完回第 1 页：在第 3 页筛一个只有 2 条结果的条件会看到空列表。
  if (currentPage.value !== 1) currentPage.value = 1;
  else load();
};
const clearFilters = () => {
  Object.keys(colFilters).forEach(k => {
    colFilters[k] = k === 'submitDate' ? { from: '', to: '' } : '';
  });
  onFilterChange();
};

// 按阶段预估天数（不含销售出库/物流）。
const LEAD_STAGES = [
  { key: 'purchasingDays', label: '采购原料' },
  { key: 'materialInboundDays', label: '原料入库' },
  { key: 'pickingDays', label: '生产领料' },
  { key: 'productionDays', label: '生产' },
  { key: 'fgInboundDays', label: '成品入库' },
];

const products = ref([]);

// —— 用料明细：物料从产品档案「金蝶式表格下拉」选择（MesProductPicker），
// 选中回填该行的编码/名称/规格/单位。 ——

const agents = useMapGetter('agents/getAgents');

const releasingId = ref(null);

// 只读查看：点行直接看完整明细，无需进编辑态（车间/采购等无编辑权者也能看）。
const viewDialogRef = ref(null);
const viewing = ref(null);

// ── 成本（仅财务/管理员/采购）──────────────────────────────
// 口径在后端 AccountUser#can_view_material_cost?；没权限时序列化里
// 单价/金额这些键根本不下发，这里再拦一道，表头也不出。
const currentUserForCost = useMapGetter('getCurrentUser');
const showCost = computed(
  () => currentUserForCost.value?.can_view_material_cost === true
);
const cost = computed(() => viewing.value?.cost || {});

// 成本导出：默认当月。文件名由后端给（Content-Disposition 里是中文，
// 这里按同样规则本地拼一份，省得去解析响应头）。
const exportingCost = ref(false);
// 不传 bomId＝当月全量；传了＝只导这一张任务单（后端同一个 service，两份格式一样）。
const exportCost = async (bomId = null) => {
  if (exportingCost.value) return;
  exportingCost.value = true;
  const month = new Date().toISOString().slice(0, 7);
  const name = bomId
    ? `生产任务单成本_${bomNoOf(viewing.value) || bomId}.xlsx`
    : `生产任务单成本_${month}.xlsx`;
  try {
    const { data } = await MesProductionOrderAPI.costExport(
      bomId ? { bom_id: bomId } : { month }
    );
    const url = URL.createObjectURL(data);
    const a = document.createElement('a');
    a.href = url;
    a.download = name;
    a.click();
    URL.revokeObjectURL(url);
  } catch (e) {
    useAlert(e?.response?.data?.error || '导出失败');
  } finally {
    exportingCost.value = false;
  }
};
const money = micros =>
  micros === null || micros === undefined
    ? '—'
    : `¥${(micros / 1_000_000).toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
// 单台成本 = 材料 ÷ 基准产量 + 加工费 + 制造费用（后两者本就是「每台多少」）。
const unitCostText = computed(() => {
  const c = cost.value;
  const qty = Number(viewing.value?.baseQty || 0);
  if (!c.totalMicros && !c.materialMicros) return '—';
  const perUnitMaterial = qty > 0 ? c.materialMicros / qty : 0;
  return money(
    Math.round(
      perUnitMaterial + (c.processMicros || 0) + (c.overheadMicros || 0)
    )
  );
});
const openView = bom => {
  viewing.value = bom;
  viewDialogRef.value?.open();
};

// 变更记录展示助手：一行 diff 文案 / 徽标配色 / 时间格式化。
const diffLabel = c => {
  const name = c.materialName || c.materialNo || '物料';
  if (c.kind === 'added') return `+${name} ${c.toQty}${c.unit || ''}`;
  if (c.kind === 'removed') return `-${name}`;
  return `${name} ${c.fromQty}→${c.toQty}${c.unit || ''}`;
};
const diffChipClass = kind => {
  if (kind === 'added') return 'bg-n-teal-3 text-n-teal-11';
  if (kind === 'removed') return 'bg-n-ruby-3 text-n-ruby-11';
  return 'bg-n-amber-3 text-n-amber-11';
};
const fmtRevTime = iso => {
  if (!iso) return '';
  const d = new Date(iso);
  const p = n => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
};
const viewHeaderFields = computed(() => {
  const v = viewing.value || {};
  return [
    { label: '投单日期', value: v.submitDate },
    { label: '投单单号', value: v.docNo },
    { label: '数量', value: v.orderQty },
    { label: '客户 / 项目', value: v.customerName },
    { label: '型号', value: v.model },
    { label: '产成品代码', value: v.productCode },
    { label: '关联成品', value: v.productName },
    {
      label: '基准产量',
      value: v.baseQty == null ? '' : `${v.baseQty} ${v.unit || ''}`.trim(),
    },
    { label: '裸机颜色', value: v.bareColor },
    { label: '皮套颜色', value: v.caseColor },
    { label: '状态', value: v.status === 'RELEASED' ? '已下发' : '草稿' },
  ];
});
const blankLeadDays = () =>
  Object.fromEntries(LEAD_STAGES.map(s => [s.key, '']));
// 用料分类：整机生产物料 vs 包装物料（整机到齐即可开产，包装未到不挡生产）。
const CATEGORY_OPTIONS = [
  { value: 'MACHINE', label: '整机物料' },
  { value: 'PACKAGING', label: '包装物料' },
];
// 「多单价不一」的悬停说明：逐张生产订单列出这颗料当时买的价。
const priceBreakdownTip = item => {
  const rows = item.priceBreakdown || [];
  if (!rows.length) return '';
  // store 会把后端的 order_no / price_micros 驼峰化；直接走接口取数的地方还是下划线，两种都认。
  return `本任务单下各生产订单的采购价：\n${rows
    .map(
      r =>
        `${r.orderNo || r.order_no || '—'}  ${money(r.priceMicros ?? r.price_micros)}`
    )
    .join('\n')}\n单价栏取的是最近一张`;
};

const categoryLabel = c =>
  CATEGORY_OPTIONS.find(o => o.value === c)?.label || '整机物料';

// 导出（Excel / 图片）
const viewContentRef = ref(null);
const bomExportData = () => {
  const v = viewing.value || {};
  return {
    title: bomNoOf(v) ? `生产任务单 ${bomNoOf(v)}` : '生产任务单',
    fields: [
      { label: '负责人', value: v.ownerName },
      { label: '归属业务员', value: v.salesOwnerName },
      ...viewHeaderFields.value,
      { label: '整单备注', value: v.remark },
      { label: '采购注意事项', value: v.purchaseNote },
      { label: '生产备注（内部）', value: v.productionNote },
    ],
    itemColumns: [
      { label: '类别', key: 'category' },
      { label: '物料编码', key: 'materialNo' },
      { label: '物料名称', key: 'materialName' },
      { label: '规格型号', key: 'specification' },
      { label: '单位', key: 'unit' },
      { label: '用量', key: 'qty', align: 'right' },
      { label: '建议采购', key: 'suggestedPurchaseQty', align: 'right' },
      { label: '实时库存', key: 'onHand', align: 'right' },
      { label: '备注', key: 'remark' },
      { label: '采购注意事项', key: 'purchaseNote' },
      { label: '生产备注', key: 'productionNote' },
    ],
    items: (v.bomItems || []).map(it => ({
      ...it,
      category: categoryLabel(it.category),
      suggestedPurchaseQty: it.suggestedPurchaseQty ?? '—',
      onHand: it.onHand ?? '—',
    })),
  };
};
const exportBomExcel = () => {
  const d = bomExportData();
  exportDataToExcel(d, d.title);
};
const exportBomJpg = () =>
  exportNodeToJpg(viewContentRef.value, bomExportData().title);
const printBom = () => printNode(viewContentRef.value, bomExportData().title);

// 投单信息（照 PMC 纸质 BOM 抬头）：日期/单号/客户/型号/产成品代码/数量/颜色。
const blankHeader = () => ({
  submitDate: '',
  docNo: '',
  customerName: '',
  model: '',
  productCode: '',
  productId: '', // 产成品在产品档案里的 id（选择器用；代码/型号都从档案回填）
  orderQty: '',
  bareColor: '',
  caseColor: '',
});

const form = reactive({
  // 产品线随表单提交：新建 BOM 不一定选成品（选了才能从成品带出产线），
  // 没有这个字段就只能靠「当前切到哪条线」兜底，在「全部」视图下会写空。
  productLine: '',
  crmProductId: '',
  salesOwnerId: '', // 订单归属业务员
  baseQty: '1',
  unit: '台',
  remark: '', // 整单备注（区别于每行的备注）
  ...blankHeader(),
  ...blankLeadDays(),
  rows: [], // { id?, materialNo, materialName, specification, unit, qty, remark }
});

// 投单总数：优先「数量」，没填就用「基准产量」。
// 用料明细的用量绝大多数就等于这个数（一台机用一片屏、一个壳），
// 以前要一行行手输几十遍；现在前面任一处填了总数，后面自动带出来。
const autoQty = computed(() => {
  const n = Number(form.orderQty) || Number(form.baseQty);
  return Number.isFinite(n) && n > 0 ? String(n) : '';
});

// 只给「已经选了物料」的行带用量——默认铺的 10 个空行不碰，
// 否则它们带上数字就不再被 isRowEmpty 判为空行，保存时会触发物料编码必填。
const hasMaterial = r =>
  Boolean(r.materialNo?.trim() || r.materialName?.trim());

// 投单数量填了就同步到基准产量——同一个数不该输两遍。
// 手动改过基准产量（或在编辑已存 BOM）就不再覆盖。
const baseQtyTouched = ref(false);
watch(
  () => form.orderQty,
  v => {
    const n = Number(v);
    if (!Number.isFinite(n) || n <= 0 || baseQtyTouched.value) return;
    form.baseQty = String(n);
  }
);

watch(autoQty, v => {
  if (!v) return;
  form.rows.forEach(r => {
    if (!r.qtyTouched && hasMaterial(r)) r.qty = v;
  });
});

// ── 未保存提醒 ──────────────────────────────────────────────
// BOM 经常要填几十行料，填到一半点了「取消」就全没了。拦截 UI 在 Dialog 里，
// 这里只负责判脏：onHand / qtyTouched 是选料时服务端带回来的实时库存和交互标记，
// 不算用户改动，算进去会让刚打开的单子就被判成「已修改」。

// 列表里把草稿一键下发。
const release = async bom => {
  releasingId.value = bom.id;
  try {
    await MesBomAPI.release(bom.id);
    await load();
    useAlert(`已下发 ${bomNoOf(bom)}`);
  } catch {
    useAlert('下发失败');
  } finally {
    releasingId.value = null;
  }
};

watch(currentPage, load);

onMounted(async () => {
  load();
  if (!agents.value?.length) rootStore.dispatch('agents/get');
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/products`
    );
    products.value = data?.payload || data || [];
  } catch {
    products.value = [];
  }
  // 从生产订单页「去建 BOM」跳来：自动打开新建 BOM 并预关联该订单。
  // 从生产订单页「去建 BOM」跳来：直接转到建档页，参数原样带过去。
  if (route.query.new_for_order) {
    const { ...q } = route.query;
    router.replace({ query: {} });
    goCreate(q);
  }
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div
      class="flex flex-wrap items-center justify-between gap-2 px-4 py-3 sm:px-6 sm:py-4 [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:sm:!px-8"
    >
      <div class="flex items-baseline gap-2">
        <h1
          class="text-xl font-semibold text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8"
        >
          工程/PMC 生产任务单
        </h1>
        <span class="text-sm text-n-slate-11">共 {{ totalCount }} 条</span>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <!-- 列顺序是本机记忆，拖乱了要有路回来 -->
        <Button
          v-if="activeFilterCount"
          :label="`清空筛选 (${activeFilterCount})`"
          variant="ghost"
          color="ruby"
          size="sm"
          @click="clearFilters"
        />
        <Button
          :label="compact ? '宽松行高' : '紧凑行高'"
          variant="ghost"
          color="slate"
          size="sm"
          @click="toggleDensity"
        />
        <Button
          label="恢复默认列序"
          variant="ghost"
          color="slate"
          size="sm"
          @click="resetOrder"
        />
        <Button
          v-if="mesCan('purchase')"
          label="新建成品采购单"
          variant="outline"
          color="slate"
          size="sm"
          class="btn-ink"
          @click="goProductPurchase"
        />
        <!-- 模版挑单：模版弹窗本身在建档页，这里带个参数过去直接把它弹出来，
             省得人先点「新建」再找「套用模版」（她第一反应就是来列表页找模版）。 -->
        <Button
          v-if="mesCan('bom')"
          label="模版"
          variant="outline"
          color="slate"
          size="sm"
          class="btn-ink"
          @click="goCreate({ templates: 1 })"
        />
        <!-- 财务月度核算底稿：一次导全月，汇总页 + 用料明细页。
             只给能看成本的人（财务/管理员/采购）。 -->
        <Button
          v-if="showCost"
          label="成本导出"
          variant="outline"
          color="slate"
          size="sm"
          class="btn-ink"
          icon="i-lucide-file-spreadsheet"
          :is-loading="exportingCost"
          @click="exportCost"
        />
        <Button
          v-if="mesCan('bom')"
          label="新建生产任务单"
          color="iris"
          size="sm"
          @click="goCreate()"
        />
      </div>
    </div>

    <!-- 单号/型号/产成品代码/投单日期都挪进表头漏斗了（对标金蝶），这里只留
         「一个关键字框 + 两个归属下拉 + 状态」，筛选条从两行收成一行。 -->
    <div
      class="flex flex-wrap items-center gap-3 px-4 pb-3 sm:px-6 [.theme-classic_&]:sm:!px-8"
    >
      <!-- reset-base：不加的话全局 $form-input-selector 会给它套上 field-base 的
           w-full + mb-4，搜索框撑满整行。高度跟 SelectCard 对齐用 h-9。 -->
      <input
        v-model="colFilters.no"
        type="text"
        placeholder="搜索 单号 / 投单单号…"
        class="reset-base h-9 px-3 text-sm rounded-lg outline-none w-52 border border-n-weak bg-n-solid-1 text-n-slate-12"
        @keyup.enter="onFilterChange"
      />
      <SelectCard
        v-if="ownerOptions.length > 1"
        v-model="colFilters.owner_id"
        :options="ownerOptions"
        @update:model-value="onFilterChange"
      />
      <SelectCard
        v-if="salesOwnerOptions.length > 1"
        v-model="colFilters.sales_owner_id"
        :options="salesOwnerOptions"
        @update:model-value="onFilterChange"
      />
      <SelectCard
        v-model="colFilters.status"
        :options="STATUS_FILTER_OPTIONS"
        @update:model-value="onFilterChange"
      />
      <Button label="查询" color="slate" size="sm" @click="onFilterChange" />
    </div>

    <MesBoardOwnerBar board-key="mes_boms_index" />

    <MesHiddenLineHint
      v-if="hiddenNoLine"
      :count="hiddenNoLine"
      class="mx-4 sm:mx-6"
    />

    <HScrollButtons />
    <div
      class="flex-1 min-h-0 px-4 pb-4 overflow-auto sm:px-6 sm:pb-6 [.theme-classic_&]:sm:!px-8"
    >
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <template v-else>
        <!-- 手机端卡片列表 -->
        <div class="flex flex-col gap-2 md:hidden">
          <div
            v-for="b in records"
            :key="`card-${b.id}`"
            class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl active:bg-n-alpha-1"
            @click="openView(b)"
          >
            <div class="flex items-center gap-2">
              <span class="font-medium truncate text-n-slate-12">{{
                bomNoOf(b)
              }}</span>
              <span
                class="px-2 py-0.5 text-xs rounded-full shrink-0"
                :class="
                  b.status === 'RELEASED'
                    ? 'bg-n-teal-3 text-n-teal-12'
                    : 'bg-n-slate-4 text-n-slate-11'
                "
              >
                {{ b.status === 'RELEASED' ? '已下发' : '草稿' }}
              </span>
              <span class="flex-1" />
              <Button
                v-if="mesCan('bom') && b.status !== 'RELEASED'"
                label="下发"
                color="iris"
                size="sm"
                class="shrink-0"
                :is-loading="releasingId === b.id"
                @click.stop="release(b)"
              />
              <Button
                v-if="canEditRow(b)"
                label="编辑"
                variant="ghost"
                size="sm"
                class="shrink-0"
                @click.stop="goEdit(b)"
              />
            </div>
            <div class="mt-1 text-xs text-n-slate-11">
              型号 / 成品：{{ b.model || b.productName || '—' }}
            </div>
            <div
              v-if="b.productCode || b.customerName"
              class="text-xs text-n-slate-11"
            >
              {{ [b.productCode, b.customerName].filter(Boolean).join(' · ') }}
            </div>
            <div class="flex flex-wrap gap-3 mt-1 text-xs text-n-slate-11">
              <span>负责人：{{ b.ownerName || '—' }}</span>
              <span>业务员：{{ b.salesOwnerName || '—' }}</span>
            </div>
            <div class="flex flex-wrap gap-3 mt-1 text-xs text-n-slate-11">
              <span>基准产量：{{ b.baseQty }} {{ b.unit }}</span>
              <span>用料项：{{ (b.bomItems || []).length }} 项</span>
              <span>预估周期：{{ b.totalLeadDays || '—' }} 天</span>
            </div>
          </div>
          <div v-if="!records.length" class="py-10 text-center text-n-slate-11">
            还没有生产任务单。
          </div>
        </div>

        <table class="hidden w-full text-sm md:table">
          <thead>
            <tr
              class="text-left text-n-slate-11 [&>th]:sticky [&>th]:top-0 [&>th]:z-10 [&>th]:bg-n-solid-1 [&>th]:border-b [&>th]:border-n-weak"
            >
              <th class="px-3 py-3 font-medium w-12 whitespace-nowrap">#</th>
              <!-- 拖列头即可改顺序，按人记在本机 -->
              <th
                v-for="col in orderedColumns"
                :key="col.key"
                draggable="true"
                class="relative px-3 py-3 font-medium transition-colors cursor-move select-none whitespace-nowrap"
                :class="isDragging(col.key) ? 'opacity-40' : ''"
                :style="colStyle(col.key)"
                title="拖动可调整列顺序"
                @dragstart="onColDragStart(col.key)"
                @dragover.prevent
                @drop="onColDrop(col.key)"
              >
                <ColResizeHandle
                  :column-key="col.key"
                  :active="isResizing(col.key)"
                  @resize-start="(e, th) => startResize(col.key, e, th)"
                  @auto-fit="autoFitColumn"
                />
                <span class="inline-flex items-center gap-1">
                  {{ col.label }}
                  <MesColumnFilter
                    v-if="filterOf(col)"
                    v-model="colFilters[filterOf(col).key]"
                    :type="filterOf(col).type"
                    :placeholder="filterOf(col).placeholder || '输入关键字'"
                    @change="onFilterChange"
                  />
                </span>
              </th>
              <th class="px-3 py-3" />
            </tr>
          </thead>
          <tbody>
            <!-- 一条任务单渲染两行：主行 + 展开的用料明细行，所以 v-for 挂在 template 上 -->
            <template v-for="(b, i) in records" :key="b.id">
              <tr class="border-b border-n-weak">
                <td class="px-3 py-3 tabular-nums text-n-slate-10">
                  {{ (currentPage - 1) * ITEMS_PER_PAGE + i + 1 }}
                </td>
                <!-- 中间列按 orderedColumns 渲染，顺序随表头拖拽实时变化 -->
                <td
                  v-for="col in orderedColumns"
                  :key="col.key"
                  :class="[col.tdClass, colStyle(col.key).width && 'truncate']"
                  :style="colStyle(col.key)"
                >
                  <template v-if="col.key === 'no'">
                    {{ bomNoOf(b) }}
                    <!-- 填了投单单号时，把系统自动号作为副号附在下面，便于跟历史单据对照 -->
                    <div v-if="b.docNo" class="text-[11px] text-n-slate-10">
                      {{ b.bomNo }}
                    </div>
                  </template>
                  <template v-else-if="col.key === 'model'">
                    <div class="text-n-slate-12">
                      {{ b.model || b.productName || '—' }}
                    </div>
                    <div
                      v-if="b.productCode || b.customerName"
                      class="text-xs text-n-slate-10"
                    >
                      {{
                        [b.productCode, b.customerName]
                          .filter(Boolean)
                          .join(' · ')
                      }}
                    </div>
                  </template>
                  <template v-else-if="col.key === 'owner'">
                    {{ b.ownerName || '—' }}
                  </template>
                  <template v-else-if="col.key === 'salesOwner'">
                    {{ b.salesOwnerName || '—' }}
                  </template>
                  <template v-else-if="col.key === 'customerName'">
                    {{ b.customerName || '—' }}
                  </template>
                  <template v-else-if="col.key === 'submitDate'">
                    {{ b.submitDate || '—' }}
                  </template>
                  <template v-else-if="col.key === 'productCode'">
                    {{ b.productCode || '—' }}
                  </template>
                  <template v-else-if="col.key === 'baseQty'">
                    {{ b.baseQty }} {{ b.unit }}
                  </template>
                  <template v-else-if="col.key === 'items'">
                    <!-- 点一下就地展开该单的用料明细，不用开弹窗 -->
                    <button
                      v-if="(b.bomItems || []).length"
                      type="button"
                      class="inline-flex items-center gap-1 reset-base text-n-iris-11 hover:text-n-iris-12"
                      :aria-expanded="expandedIds.has(b.id)"
                      @click="toggleItems(b)"
                    >
                      <span
                        class="size-4"
                        :class="
                          expandedIds.has(b.id)
                            ? 'i-lucide-chevron-down'
                            : 'i-lucide-chevron-right'
                        "
                      />
                      {{ b.bomItems.length }} 项
                    </button>
                    <span v-else>—</span>
                  </template>
                  <template v-else-if="col.key === 'leadDays'">
                    {{ b.totalLeadDays || '—' }}
                  </template>
                  <template v-else-if="col.key === 'status'">
                    <span
                      class="px-2 py-0.5 text-xs rounded-full"
                      :class="
                        b.status === 'RELEASED'
                          ? 'bg-n-teal-3 text-n-teal-12'
                          : 'bg-n-slate-4 text-n-slate-11'
                      "
                    >
                      {{ b.status === 'RELEASED' ? '已下发' : '草稿' }}
                    </span>
                  </template>
                </td>
                <td class="px-3 py-3 text-right">
                  <div class="flex justify-end gap-1">
                    <Button
                      v-if="mesCan('bom') && b.status !== 'RELEASED'"
                      label="下发"
                      color="iris"
                      size="sm"
                      :is-loading="releasingId === b.id"
                      @click="release(b)"
                    />
                    <Button
                      label="查看"
                      variant="ghost"
                      size="sm"
                      @click="openView(b)"
                    />
                    <Button
                      v-if="canEditRow(b)"
                      label="编辑"
                      variant="ghost"
                      size="sm"
                      @click="goEdit(b)"
                    />
                  </div>
                </td>
              </tr>
              <!-- 展开的用料明细：只出类别/物料编码/物料名称/规格型号/用量这几样，
                 够 PMC 核料；单价、采购注意事项这些仍在「查看」里，列表不塞。 -->
              <tr v-if="expandedIds.has(b.id)">
                <td :colspan="totalColSpan" class="px-3 py-3 bg-n-alpha-1">
                  <table class="w-full text-xs">
                    <thead>
                      <tr class="text-left text-n-slate-11">
                        <th class="w-10 px-2 py-1 font-medium">#</th>
                        <th class="px-2 py-1 font-medium whitespace-nowrap">
                          类别
                        </th>
                        <th class="px-2 py-1 font-medium whitespace-nowrap">
                          物料编码
                        </th>
                        <th
                          class="px-2 py-1 font-medium whitespace-nowrap w-1/3"
                        >
                          物料名称
                        </th>
                        <th
                          class="px-2 py-1 font-medium whitespace-nowrap w-1/3"
                        >
                          规格型号
                        </th>
                        <th
                          class="px-2 py-1 font-medium text-right whitespace-nowrap"
                        >
                          用量
                        </th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr
                        v-for="(it, idx) in b.bomItems"
                        :key="it.id || idx"
                        class="border-t border-n-weak"
                      >
                        <td class="px-2 py-1 tabular-nums text-n-slate-10">
                          {{ idx + 1 }}
                        </td>
                        <td class="px-2 py-1 whitespace-nowrap">
                          <span
                            class="px-2 py-0.5 rounded-full"
                            :class="
                              it.category === 'PACKAGING'
                                ? 'bg-n-amber-3 text-n-amber-12'
                                : 'bg-n-iris-3 text-n-iris-12'
                            "
                          >
                            {{ categoryLabel(it.category) }}
                          </span>
                        </td>
                        <td class="px-2 py-1 whitespace-nowrap text-n-slate-12">
                          {{ it.materialNo || '—' }}
                        </td>
                        <td class="px-2 py-1 text-n-slate-12">
                          {{ it.materialName || '—' }}
                        </td>
                        <td class="px-2 py-1 text-n-slate-11">
                          {{ it.specification || '—' }}
                        </td>
                        <td
                          class="px-2 py-1 text-right whitespace-nowrap text-n-slate-11"
                        >
                          {{ it.qty }} {{ it.unit || '' }}
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </td>
              </tr>
            </template>
            <tr v-if="!records.length">
              <td
                :colspan="totalColSpan"
                class="px-3 py-10 text-center text-n-slate-11"
              >
                <template v-if="activeFilterCount">
                  没有符合筛选条件的生产任务单。点右上角「清空筛选」回到全部。
                </template>
                <template v-else>还没有生产任务单。</template>
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
        class="mt-3 !bg-transparent before:!hidden"
        @update:current-page="currentPage = $event"
      />
    </div>

    <!-- 只读查看：完整明细，无需进编辑态 -->

    <Dialog
      ref="viewDialogRef"
      :dismissible="false"
      width="6xl"
      overflow-y-auto
      :show-confirm-button="false"
      cancel-button-label="关闭"
      :title="viewing ? `生产任务单 ${bomNoOf(viewing)}` : '生产任务单明细'"
    >
      <template #title>
        <span class="inline-flex items-center gap-2">
          {{ viewing ? `生产任务单 ${bomNoOf(viewing)}` : '生产任务单明细' }}
          <span
            v-if="viewing"
            class="px-2 py-0.5 text-xs font-normal rounded-full"
            :class="
              viewing.status === 'RELEASED'
                ? 'bg-n-teal-3 text-n-teal-12'
                : 'bg-n-slate-4 text-n-slate-11'
            "
          >
            {{ viewing.status === 'RELEASED' ? '已下发' : '草稿' }}
          </span>
        </span>
      </template>
      <!-- 导出/打印挂到标题行右侧：原来单起一行右对齐，左边空一大片。 -->
      <template #headerActions>
        <div v-if="viewing" class="flex gap-2 shrink-0">
          <!-- 单张成本表：任务单和采购单一下出去，财务当天就要这一单的料本对账，
               不用等月底导全月再从几百张里翻。只给看得见成本的人（财务/采购/副管）。 -->
          <Button
            v-if="showCost"
            label="下载成本表"
            variant="outline"
            color="iris"
            size="sm"
            :is-loading="exportingCost"
            @click="exportCost(viewing.id)"
          />
          <Button
            label="导出 Excel"
            variant="outline"
            color="slate"
            size="sm"
            @click="exportBomExcel"
          />
          <Button
            label="导出图片"
            variant="outline"
            color="slate"
            size="sm"
            @click="exportBomJpg"
          />
          <Button
            label="打印"
            variant="outline"
            color="slate"
            size="sm"
            @click="printBom"
          />
        </div>
      </template>
      <div v-if="viewing" class="flex flex-col gap-4 text-sm">
        <div
          ref="viewContentRef"
          class="flex flex-col gap-4 p-4 bg-white rounded-lg"
        >
          <!-- 客户 logo：单子一打开就该看见印什么标，所以顶在抬头上方 -->
          <div v-if="(viewing.logos || []).length" class="flex flex-wrap gap-2">
            <a
              v-for="lg in viewing.logos"
              :key="lg.id"
              :href="lg.url"
              target="_blank"
              rel="noopener noreferrer"
            >
              <img
                :src="lg.url"
                :alt="lg.filename"
                class="object-contain object-left h-20 w-52"
              />
            </a>
          </div>

          <div class="flex items-center gap-2">
            <span class="text-n-slate-11">
              负责人：{{ viewing.ownerName || '—' }} · 归属业务员：{{
                viewing.salesOwnerName || '—'
              }}
            </span>
          </div>

          <div class="text-heading-2 text-n-slate-12">投单信息</div>
          <div class="grid grid-cols-3 gap-x-4 gap-y-3">
            <div
              v-for="f in viewHeaderFields"
              :key="f.label"
              class="flex flex-col"
            >
              <span class="text-xs text-n-slate-10">{{ f.label }}</span>
              <span class="text-n-slate-12">{{ f.value || '—' }}</span>
            </div>
          </div>

          <div class="pt-2 border-t border-n-weak">
            <div
              class="mb-2 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
            >
              用料明细（{{ (viewing.bomItems || []).length }} 项）
            </div>
            <!-- 十三列在弹窗里放不下：原来 w-full 硬压，物料名称、规格型号被折成两三行，
                 一屏看不了几条。改成按内容宽度 + 横向滚动，用左右箭头翻屏（同整页表格那套）。 -->
            <HScrollButtons />
            <div class="relative overflow-x-auto">
              <table class="w-full text-sm min-w-max">
                <thead>
                  <tr class="text-left text-n-slate-11 border-b border-n-weak">
                    <th class="w-10 px-2 py-2 font-medium">#</th>
                    <th class="px-2 py-2 font-medium whitespace-nowrap">
                      类别
                    </th>
                    <th class="px-2 py-2 font-medium whitespace-nowrap">
                      物料编码
                    </th>
                    <th class="px-2 py-2 font-medium whitespace-nowrap">
                      物料名称
                    </th>
                    <th class="px-2 py-2 font-medium whitespace-nowrap">
                      规格型号
                    </th>
                    <th class="px-2 py-2 font-medium whitespace-nowrap">
                      辅助属性
                    </th>
                    <th class="px-2 py-2 font-medium whitespace-nowrap">
                      单位
                    </th>
                    <th
                      class="px-2 py-2 font-medium text-right whitespace-nowrap"
                    >
                      用量
                    </th>
                    <!-- 单价/金额/价源只给财务/管理员/采购；没权限时后端不下发这几个键 -->
                    <template v-if="showCost">
                      <th
                        class="px-2 py-2 font-medium text-right whitespace-nowrap"
                      >
                        单价
                      </th>
                      <th
                        class="px-2 py-2 font-medium text-right whitespace-nowrap"
                      >
                        金额
                      </th>
                      <th class="px-2 py-2 font-medium whitespace-nowrap">
                        价源
                      </th>
                    </template>
                    <th class="px-2 py-2 font-medium whitespace-nowrap">
                      备注
                    </th>
                    <th class="px-2 py-2 font-medium whitespace-nowrap">
                      采购注意事项
                    </th>
                    <th class="px-2 py-2 font-medium whitespace-nowrap">
                      生产备注
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    v-for="(it, i) in viewing.bomItems"
                    :key="i"
                    class="border-b border-n-weak"
                  >
                    <td class="px-2 py-2 tabular-nums text-n-slate-10">
                      {{ i + 1 }}
                    </td>
                    <td class="px-2 py-2">
                      <span
                        class="px-2 py-0.5 text-xs rounded-full"
                        :class="
                          it.category === 'PACKAGING'
                            ? 'bg-n-amber-3 text-n-amber-12'
                            : 'bg-n-iris-3 text-n-iris-12'
                        "
                      >
                        {{ categoryLabel(it.category) }}
                      </span>
                    </td>
                    <td class="px-2 py-2 text-n-slate-12">
                      {{ it.materialNo || '—' }}
                    </td>
                    <td class="px-2 py-2 text-n-slate-12">
                      {{ it.materialName }}
                    </td>
                    <td class="px-2 py-2 text-n-slate-11">
                      {{ it.specification || '—' }}
                    </td>
                    <td class="px-2 py-2 text-n-slate-11">
                      {{ it.auxAttributeName || '—' }}
                    </td>
                    <td class="px-2 py-2 text-n-slate-11">
                      {{ it.unit || '—' }}
                    </td>
                    <td class="px-2 py-2 text-right text-n-slate-12">
                      {{ it.qty }}
                    </td>
                    <template v-if="showCost">
                      <td
                        class="px-2 py-2 text-right tabular-nums text-n-slate-12"
                      >
                        {{ money(it.unitPriceMicros) }}
                      </td>
                      <td
                        class="px-2 py-2 text-right tabular-nums text-n-slate-12"
                      >
                        {{ money(it.amountMicros) }}
                      </td>
                      <td class="px-2 py-2">
                        <!-- 「多单价不一」＝这颗料在本任务单的几张生产订单里买价不同（备货期涨跌价）。
                           这时单价那一栏取的是最近一张，没有唯一正确值，所以标出来并把每张单
                           各是多少挂在悬停提示里——只给一个数会让人当成确定的成本。 -->
                        <span
                          v-if="it.priceSourceLabel"
                          class="px-2 py-0.5 text-xs rounded-full"
                          :class="
                            it.priceBreakdown?.length
                              ? 'bg-n-amber-3 text-n-amber-11 cursor-help'
                              : 'bg-n-slate-3 text-n-slate-11'
                          "
                          :title="priceBreakdownTip(it)"
                        >
                          {{ it.priceSourceLabel }}
                        </span>
                        <span v-else class="text-xs text-n-ruby-11">
                          无单价
                        </span>
                      </td>
                    </template>
                    <!-- 本行没写备注就显产品档案上的（工程写的工艺要求）。
                       不加「档案：」前缀——这栏是要发给供应商/车间看的，前缀是内部说法。
                       来源仍留在 title 里，鼠标移上去看得到。 -->
                    <td class="px-2 py-2 text-n-slate-11">
                      <span v-if="it.remark">{{ it.remark }}</span>
                      <span
                        v-else-if="it.productRemark"
                        class="text-n-slate-10"
                        :title="`产品档案备注：${it.productRemark}`"
                      >
                        {{ it.productRemark }}
                      </span>
                      <span v-else>—</span>
                    </td>
                    <td class="px-2 py-2 text-n-slate-11">
                      {{ it.purchaseNote || '—' }}
                    </td>
                    <td class="px-2 py-2 text-n-slate-11">
                      {{ it.productionNote || '—' }}
                    </td>
                  </tr>
                  <tr v-if="!(viewing.bomItems || []).length">
                    <td
                      :colspan="showCost ? 14 : 11"
                      class="px-2 py-6 text-center text-n-slate-11"
                    >
                      无用料明细
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <!-- 成本小结。缺价行数必须露出来：覆盖不到 100% 时，一个不标缺口的
                 合计会被当成完整成本用（财务按它算产品单价）。 -->
            <div
              v-if="showCost"
              class="flex flex-wrap items-center gap-x-6 gap-y-1 px-2 py-3 mt-2 text-sm border rounded-lg border-n-weak bg-n-alpha-1"
            >
              <span class="text-n-slate-11">
                材料合计
                <b class="ml-1 text-n-slate-12">{{
                  money(cost.materialMicros)
                }}</b>
              </span>
              <span class="text-n-slate-11">
                生产人工
                <b class="ml-1 text-n-slate-12">{{
                  money(cost.processMicros)
                }}</b>
              </span>
              <span class="text-n-slate-11">
                制造费用
                <b class="ml-1 text-n-slate-12">{{
                  money(cost.overheadMicros)
                }}</b>
              </span>
              <span class="text-n-slate-11">
                单台成本
                <b class="ml-1 text-n-slate-12">{{ unitCostText }}</b>
              </span>
              <span v-if="cost.unpricedLines" class="text-n-ruby-11">
                {{ cost.unpricedLines }} 行无单价，合计为不完全值
              </span>
            </div>
          </div>

          <div class="pt-2 border-t border-n-weak">
            <div
              class="mb-2 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
            >
              各阶段预估天数（合计 {{ viewing.totalLeadDays || 0 }} 天）
            </div>
            <div class="flex flex-wrap gap-x-6 gap-y-1 text-n-slate-11">
              <span v-for="s in LEAD_STAGES" :key="s.key">
                {{ s.label }}：<span class="text-n-slate-12">{{
                  viewing[s.key] || '—'
                }}</span>
              </span>
            </div>
          </div>

          <div v-if="viewing.remark" class="pt-2 border-t border-n-weak">
            <div
              class="mb-1 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
            >
              整单备注
            </div>
            <p class="whitespace-pre-wrap text-n-slate-12">
              {{ viewing.remark }}
            </p>
          </div>

          <div v-if="viewing.purchaseNote" class="pt-2 border-t border-n-weak">
            <div
              class="mb-1 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
            >
              采购注意事项
            </div>
            <p class="whitespace-pre-wrap text-n-slate-12">
              {{ viewing.purchaseNote }}
            </p>
          </div>

          <div
            v-if="viewing.productionNote"
            class="pt-2 border-t border-n-weak"
          >
            <div
              class="mb-1 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
            >
              生产备注（内部）
            </div>
            <p class="whitespace-pre-wrap text-n-slate-12">
              {{ viewing.productionNote }}
            </p>
          </div>

          <div
            v-if="(viewing.images || []).length"
            class="pt-2 border-t border-n-weak"
          >
            <div
              class="mb-2 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
            >
              结构图 / 样品图
            </div>
            <div class="flex flex-wrap gap-2">
              <a
                v-for="img in viewing.images"
                :key="img.id"
                :href="img.url"
                target="_blank"
                rel="noopener noreferrer"
              >
                <img
                  :src="img.url"
                  :alt="img.filename"
                  class="object-cover w-20 h-20 border rounded-lg border-n-weak"
                />
              </a>
            </div>
          </div>

          <div
            v-if="(viewing.files || []).length"
            class="pt-2 border-t border-n-weak"
          >
            <div
              class="mb-1 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
            >
              附件
            </div>
            <ul class="flex flex-col gap-1">
              <li v-for="f in viewing.files" :key="f.id">
                <a
                  :href="f.url"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-xs text-n-iris-11 hover:underline"
                >
                  {{ f.filename }}
                </a>
              </li>
            </ul>
          </div>

          <!-- BOM 变更记录：已下发后每次改用料的留痕（谁/何时/改了什么/为什么）-->
          <div
            v-if="(viewing.revisions || []).length"
            class="pt-2 border-t border-n-weak"
          >
            <div
              class="mb-1 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
            >
              变更记录（{{ viewing.revisions.length }} 次）
            </div>
            <ul class="flex flex-col gap-2">
              <li
                v-for="rev in viewing.revisions"
                :key="rev.id"
                class="p-2 text-xs border rounded-lg border-n-weak bg-n-alpha-1"
              >
                <div class="flex items-center gap-2 mb-1 text-n-slate-11">
                  <span class="font-semibold text-n-slate-12">
                    v{{ rev.revNo }}
                  </span>
                  <span>{{ rev.changedByName || '—' }}</span>
                  <span>{{ fmtRevTime(rev.createdAt) }}</span>
                </div>
                <div class="flex flex-wrap gap-1">
                  <span
                    v-for="(c, ci) in rev.diff"
                    :key="ci"
                    class="px-1.5 py-0.5 rounded"
                    :class="diffChipClass(c.kind)"
                  >
                    {{ diffLabel(c) }}
                  </span>
                </div>
                <div v-if="rev.reason" class="mt-1 text-n-slate-11">
                  原因：{{ rev.reason }}
                </div>
              </li>
            </ul>
          </div>
        </div>
      </div>
    </Dialog>
  </div>
</template>
