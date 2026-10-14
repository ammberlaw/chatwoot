<script setup>
// 建档页不进 keep-alive（见 MesLayout 的 INTAKE_PAGES）：表单页被缓存就会留着
// 上一单的内容，再点别的单进来是旧数据。名字要显式声明，keep-alive 的 exclude 按名字匹配。
defineOptions({ name: 'MesBomIntakeIndex' });
/* global axios */
import {
  ref,
  computed,
  reactive,
  watch,
  nextTick,
  onMounted,
  onActivated,
  onBeforeUnmount,
} from 'vue';
import { useRoute, useRouter, onBeforeRouteLeave } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesBomsStore } from 'dashboard/stores/mes/boms';
import { useMesBomTemplatesStore } from 'dashboard/stores/mes/bomTemplates';
import MesHiddenLineHint from 'dashboard/components-next/mes/MesHiddenLineHint.vue';
import MesBomAPI from 'dashboard/api/mes/boms';
import camelcaseKeys from 'camelcase-keys';
import MesProductionOrderAPI from 'dashboard/api/mes/productionOrders';

import Button from 'dashboard/components-next/button/Button.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import { useResizableColumns } from 'dashboard/composables/useResizableColumns';
import { useOrderableColumns } from 'dashboard/composables/useOrderableColumns';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import MesProductPicker from 'dashboard/components-next/mes/MesProductPicker.vue';
import MesProductQuickPanel from 'dashboard/components-next/mes/MesProductQuickPanel.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { useMesProductLine } from 'dashboard/composables/useMesProductLine';
import { useMesTabs } from 'dashboard/composables/useMesTabs';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
const { accountId, accountScopedRoute } = useAccount();
// 标签条：守卫要靠它区分「切标签」和「关标签」。
const { tabs } = useMesTabs();
const router = useRouter();
const route = useRoute();
const rootStore = useStore();

// 回列表。leaving 是离开拦截的放行开关：保存成功、或用户选了「不保存」之后置 true。
const backToList = () => router.push(accountScopedRoute('mes_boms_index'));
let leaving = false;

const store = useMesBomsStore();
const tplStore = useMesBomTemplatesStore();

const saving = computed(
  () => store.getUIFlags.creatingItem || store.getUIFlags.updatingItem
);

// 按阶段预估天数（不含销售出库/物流）。
const LEAD_STAGES = [
  { key: 'purchasingDays', label: '采购原料' },
  { key: 'materialInboundDays', label: '原料入库' },
  { key: 'pickingDays', label: '生产领料' },
  { key: 'productionDays', label: '生产' },
  { key: 'fgInboundDays', label: '成品入库' },
];

const products = ref([]);
// 关联成品为选填：置顶「不关联成品」哨兵项，让用户可显式清除选择
// （ComboBox 仅支持再点选中项才清空，不够直观）。
const productOptions = computed(() => [
  { value: '', label: '不关联成品' },
  ...products.value.map(p => ({ value: String(p.id), label: p.name })),
]);

// —— 用料明细：物料从产品档案「金蝶式表格下拉」选择（MesProductPicker），
// 选中回填该行的编码/名称/规格/单位。 ——

// 订单归属业务员：只列真正的业务角色（可归属 CRM 订单）——业务员/部门负责人/
// 副管理员；排除 HR 与无 CRM 角色的普通成员。选填。
const SALES_CRM_ROLES = ['sales', 'manager', 'deputy_admin'];
const agents = useMapGetter('agents/getAgents');
const salesOwnerOptions = computed(() => [
  { value: '', label: '未指定业务员' },
  ...(agents.value || [])
    .filter(a => SALES_CRM_ROLES.includes(a.crm_role))
    .map(a => ({ value: String(a.id), label: a.name })),
]);

const editingId = ref(null);
const editingStatus = ref(null); // 编辑时的原状态：已下发则只显示「保存」
const changeReason = ref(''); // 已下发生产任务单改用料时填的变更原因（可选，进变更史+通知）
const removedItemIds = ref([]);

const blankLeadDays = () =>
  Object.fromEntries(LEAD_STAGES.map(s => [s.key, '']));
// 用料分类：整机生产物料 vs 包装物料（整机到齐即可开产，包装未到不挡生产）。
const CATEGORY_OPTIONS = [
  { value: 'MACHINE', label: '整机物料' },
  { value: 'PACKAGING', label: '包装物料' },
];

// 用料明细每行照生产任务单直接填。
const blankRow = () => ({
  productId: '',
  materialNo: '',
  materialName: '',
  specification: '',
  unit: '',
  qty: '',
  suggestedPurchaseQty: '', // 工程建议采购数量
  onHand: null, // 对应物料实时库存（只读展示，不入库）
  // 辅助属性：选完物料后从该物料的档案带出可选项，单选其一（如 喷码6000）。
  auxAttributeId: '',
  auxAttributeName: '',
  auxOptions: [],
  productRemark: '', // 产品档案上的备注（只读，跟本行自己的备注分开）
  remark: '',
  blockerKind: '', // 卡在哪（空=没卡住）
  blockerNote: '', // 卡点说明
  purchaseNote: '', // 给采购看：指定品牌/能否替代/到货节点（建采购单时按料带过去，不进给供应商的导出件）
  productionNote: '', // 只给公司内部生产部门看，不进任何对外单据
  category: 'MACHINE',
  // 用量是否被人手动改过。没改过的行跟着投单总数走（见 autoQty），
  // 改过的不再自动覆盖——工程会按单机实际用量调个别行（喇叭一台两只这种）。
  qtyTouched: false,
});
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
const {
  activeProductLine,
  formOptions: productLineOptions,
  productLineLabel,
} = useMesProductLine();
// 商显工控 BOM 不需要客户/项目名称、裸机颜色、皮套颜色（平板电脑保留）。
const showTabletHeaderFields = computed(
  () => activeProductLine.value !== 'COMMERCIAL_DISPLAY'
);

// 用料明细的列：宽度可拖（像 Excel / 金蝶那样），拖完记在本机。
// 序号和删除那两根固定宽，不给拖。规格型号默认给最宽——不放全就核不了料。
const REQUIRED_COLS = ['materialNo', 'materialName', 'qty'];
const BOM_COLS = [
  { key: 'idx', fixed: 28 },
  { key: 'category', label: '类别', fr: 1.6 },
  { key: 'materialNo', label: '物料编码', fr: 2 },
  { key: 'materialName', label: '物料名称', fr: 2 },
  { key: 'spec', label: '规格型号', fr: 3 },
  { key: 'aux', label: '辅助属性', fr: 1.6 },
  { key: 'unit', label: '单位', fr: 0.8 },
  { key: 'qty', label: '用量', fr: 1 },
  { key: 'suggest', label: '建议采购', fr: 1 },
  { key: 'onHand', label: '实时库存', fr: 1 },
  { key: 'remark', label: '备注', fr: 1 },
  { key: 'purchaseNote', label: '采购注意事项', fr: 1.6 },
  { key: 'productionNote', label: '生产备注', fr: 1.6 },
  // 卡点：这颗料为什么还没下采购单（等客户确认/等业务文件/等工程确认/打样中）。
  // 原来系统只认「下了单 / 没下单」，没下单的一律看着像采购在拖，
  // 实际上一大半责任人不在采购（用户 10.13 原话）。
  { key: 'blocker', label: '卡点', fr: 1.4 },
  { key: 'del', fixed: 24 },
];
// 列序可拖（和生产订单/任务单列表同一套），序号和删除两根钉死在首尾不参与。
// 单元格不重排 DOM——靠 CSS Grid 的显式列位（grid-column）落到新位置，
// 这样 13 个格子的模板结构一个字都不用动，改错的风险小得多。
// 卡点按「等谁」分类，不按「什么问题」——看的人第一反应是去找人。
const BLOCKER_OPTIONS = [
  { value: '', label: '未卡住' },
  { value: 'WAITING_CUSTOMER', label: '等客户确认' },
  { value: 'WAITING_FILE', label: '等业务文件' },
  { value: 'WAITING_ENGINEERING', label: '等工程确认' },
  { value: 'SAMPLING', label: '打样中' },
  { value: 'OTHER', label: '其它' },
];

const MOVABLE_COLS = BOM_COLS.filter(c => c.fixed == null);
const {
  orderedColumns: orderedMovableCols,
  isDragging: isBomColDragging,
  onColDragStart: onBomColDragStart,
  onColDrop: onBomColDrop,
  resetOrder: resetBomColOrder,
} = useOrderableColumns(MOVABLE_COLS, 'mes.bom.itemColOrder.v1');

const bomCols = computed(() => [
  BOM_COLS[0],
  ...orderedMovableCols.value,
  BOM_COLS[BOM_COLS.length - 1],
]);
// 某一列当前排第几（1 起），给单元格的 grid-column 用。
//
// 必须连 grid-row 一起钉死：格子在 DOM 里的顺序是固定的，列序一拖，
// 这些 grid-column 就不再是递增的，而 CSS Grid 默认的 sparse 排布永远不往回走——
// 列号比上一个小的那一格直接被挤到第二行去（反馈里「拖了以后列表是乱码」就是这个）。
const colPos = key => {
  const i = bomCols.value.findIndex(c => c.key === key);
  return i < 0 ? undefined : { gridColumn: i + 1, gridRow: 1 };
};

// 别的在产订单已经排掉了多少这颗料。实时库存写着 100 不代表 100 都能用——
// 工程照着库存决定不采购，到领料那天就缺货（用户点名要在实时库存旁边提示）。
const committedByNo = ref({});
const loadCommitments = async () => {
  try {
    const { data } = await MesBomAPI.materialCommitments(editingId.value);
    committedByNo.value = data?.payload || {};
  } catch {
    // 取不到就不提示，别挡住录单。
    committedByNo.value = {};
  }
};
const committedOf = row => {
  const v = Number(committedByNo.value[row.materialNo] || 0);
  return v > 0 ? v : 0;
};
// 可用 = 实时库存 − 别的单已排。为负就是已经排超了。
const availableOf = row =>
  row.onHand == null ? null : Number(row.onHand) - committedOf(row);
const commitmentTip = row =>
  `别的在产订单已排用 ${committedOf(row)}，实时库存 ${row.onHand ?? 0}，` +
  `可用 ${availableOf(row)}。这颗料不要只看实时库存就决定不采购。`;

const {
  template: bomColTemplate,
  startResize: startColResize,
  resetWidths: resetColWidths,
} = useResizableColumns(bomCols, 'mes.bom.itemCols.v1');

// 明细区顶部的横向滚动条（对标金蝶）：几十行料时真正的滚动条在最底下，
// 想横着看一眼得先滚到底。
//
// 这条是**自己画的**，不是镜像一个原生滚动条——macOS 用的是悬浮滚动条，
// 不占布局空间、不滚就不显示，`scrollbar-width` 之类怎么调都没法让它常驻。
const itemsScrollRef = ref(null);
const trackRef = ref(null);
const itemsScrollWidth = ref(0);
const itemsClientWidth = ref(0);
const itemsScrollLeft = ref(0);
const itemsOverflow = computed(
  () => itemsScrollWidth.value > itemsClientWidth.value + 1
);
// 滑块按「可视宽/总宽」取比例，位置按「已滚距离/总宽」；用百分比就不用关心轨道有多宽。
const thumbStyle = computed(() => {
  const total = itemsScrollWidth.value || 1;
  return {
    width: `${Math.max((itemsClientWidth.value / total) * 100, 6)}%`,
    left: `${(itemsScrollLeft.value / total) * 100}%`,
  };
});
const measureItemsWidth = () => {
  const el = itemsScrollRef.value;
  if (!el) return;
  itemsScrollWidth.value = el.scrollWidth;
  itemsClientWidth.value = el.clientWidth;
  itemsScrollLeft.value = el.scrollLeft;
};
const onItemsScroll = () => {
  itemsScrollLeft.value = itemsScrollRef.value?.scrollLeft || 0;
};
// 拖滑块：鼠标走过的像素按「总宽/轨道宽」放大成明细区要滚的距离。
let dragStart = null;
const onThumbDown = e => {
  dragStart = {
    x: e.clientX,
    scrollLeft: itemsScrollRef.value?.scrollLeft || 0,
    trackWidth: trackRef.value?.clientWidth || 1,
  };
  e.currentTarget.setPointerCapture?.(e.pointerId);
};
const onThumbMove = e => {
  if (!dragStart || !itemsScrollRef.value) return;
  const ratio = itemsScrollWidth.value / dragStart.trackWidth;
  itemsScrollRef.value.scrollLeft =
    dragStart.scrollLeft + (e.clientX - dragStart.x) * ratio;
};
const onThumbUp = e => {
  dragStart = null;
  e.currentTarget.releasePointerCapture?.(e.pointerId);
};
// 点轨道空白处：把那个位置挪到可视区中间。
const onTrackDown = e => {
  if (e.target !== trackRef.value || !itemsScrollRef.value) return;
  const rect = trackRef.value.getBoundingClientRect();
  const ratio = (e.clientX - rect.left) / rect.width;
  itemsScrollRef.value.scrollLeft =
    ratio * itemsScrollWidth.value - itemsClientWidth.value / 2;
};

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

const totalLeadDays = computed(() =>
  LEAD_STAGES.reduce((sum, s) => sum + (Number(form[s.key]) || 0), 0)
);

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

const pickMaterial = (row, p) => {
  if (!p) return;
  row.productId = String(p.id);
  row.materialNo = p.sku || '';
  row.materialName = p.name || '';
  if (p.specification) row.specification = p.specification;
  if (p.unit) row.unit = p.unit;
  // 选中即带出该物料的实时库存（产品搜索接口已附 on_hand，跨仓合计）。
  row.onHand = p.on_hand != null ? Number(p.on_hand) : null;
  // 选完物料，用量直接按投单总数带出来，不用一行行手输。
  if (!row.qtyTouched && autoQty.value) row.qty = autoQty.value;
  // 辅助属性跟着物料走：换了物料，上一个物料的属性必须清掉，
  // 否则会把「A电池的喷码6000」挂到 B 电池上。
  // 选料器直接用 axios 取数，键是下划线（同函数里 p.on_hand 亦然），不是驼峰。
  row.auxOptions = p.aux_attributes || [];
  row.auxAttributeId = '';
  row.auxAttributeName = '';
  // 档案备注（工程写在产品上的工艺要求，如「外露线长90mm」）跟着带出来，录单和车间都得看见。
  row.productRemark = p.remark || '';
};

// 投单数量填了就同步到基准产量——同一个数不该输两遍。
// 手动改过基准产量（或在编辑已存 BOM）就不再覆盖。
const baseQtyTouched = ref(false);
// 这单的用料是不是刚套的模版（只有这种情况才自动折算，见 applyTemplate）。
const fromTemplate = ref(false);

// 选定产成品：代码取档案 SKU，型号取档案里的产品名（A80 / K705 这种），省一次手输。
// 型号已经手填过就不覆盖，避免把人家写的「K13plus 10.1寸P30版/客户定制」抹掉。
const pickFinishedProduct = p => {
  form.productId = String(p.id);
  // crmProductId 才是真正存进 crm_product_id 的那个。原来这里只写 productId，
  // 提交时只发了 productCode 文本、id 被丢掉——生产上 17 张任务单全是「有编码、无关联」，
  // 下游库存/成本按 id 对不上。两个字段同时写，彻底消掉这个岔路。
  form.crmProductId = String(p.id);
  form.productCode = p.sku || '';
  if (!form.model.trim()) form.model = p.name || '';
};

watch(autoQty, v => {
  if (!v) return;
  form.rows.forEach(r => {
    if (!r.qtyTouched && hasMaterial(r)) r.qty = v;
  });
});

// 下拉选项：带一个「不选」，因为辅助属性是选填的（不是每个物料都有变体）。
const auxOptionsOf = row => [
  { value: '', label: '不选' },
  ...row.auxOptions.map(o => ({ value: String(o.id), label: o.name })),
];

// 选中即同时记下名字：提交只送 id，但界面和「载入已有 BOM」都要显示名字。
const pickAuxAttribute = (row, value) => {
  row.auxAttributeId = value || '';
  row.auxAttributeName =
    row.auxOptions.find(o => String(o.id) === String(value))?.name || '';
};

// 按投单数量等比缩放：套模版或改单量时，用料是按原单数量算的（模版 3500 台的料
// 拿来做 1000 台），几十行一行行改太蠢。按 数量/基准产量 等比折算，
// 同时把基准产量对齐到新数量——外箱 10 个/箱、泡棉 3 片/台这些比例原样保住。
const scaleTargetQty = computed(() => {
  const n = Number(form.orderQty);
  return Number.isFinite(n) && n > 0 ? n : null;
});

const scalableRows = computed(() =>
  form.rows.filter(r => hasMaterial(r) && Number(r.qty) > 0)
);

const canScaleQty = computed(() => {
  const base = Number(form.baseQty);
  if (!scaleTargetQty.value || !Number.isFinite(base) || base <= 0)
    return false;
  return base !== scaleTargetQty.value && scalableRows.value.length > 0;
});

// 禁用时按钮是灰的，光看界面不知道为什么点不动，补个悬浮说明。
const scaleHint = computed(() => {
  const base = Number(form.baseQty);
  if (!scaleTargetQty.value) return '先在投单信息里填「数量」';
  if (!Number.isFinite(base) || base <= 0) return '先填基准产量';
  if (base === scaleTargetQty.value) return '数量与基准产量已一致，无需缩放';
  if (!scalableRows.value.length) return '用料明细里还没有填了用量的行';
  return `把 ${scalableRows.value.length} 行用量按 ${base} → ${scaleTargetQty.value} 等比折算，基准产量一并改成 ${scaleTargetQty.value}`;
});

const scaleRowsToOrderQty = () => {
  if (!canScaleQty.value) return;
  const target = scaleTargetQty.value;
  const base = Number(form.baseQty);
  let fractional = 0;
  const rows = scalableRows.value;
  rows.forEach(r => {
    // 先乘后除，别先算比例——0.342857… 这种比例乘回去会把整数搞成 119.99999
    const scaled = Math.round(((Number(r.qty) * target) / base) * 1000) / 1000;
    r.qty = String(scaled);
    r.qtyTouched = true;
    if (!Number.isInteger(scaled)) fractional += 1;
  });
  form.baseQty = String(target);
  baseQtyTouched.value = true;
  useAlert(
    fractional
      ? `已按 ${target} 折算 ${rows.length} 行用量；其中 ${fractional} 行算出小数，按箱装的（外箱/珍珠棉这类）自己核一下`
      : `已按 ${target} 折算 ${rows.length} 行用量`
  );
};

// 套模版后改「数量」：基准产量和每行用量自动跟着折算，不用再一行行手改。
// 防抖 600ms——边敲「1000」边算会在 1 / 10 / 100 上各折算一次。
let scaleTimer = null;
const autoScaleOnQtyChange = () => {
  if (!fromTemplate.value) return;
  clearTimeout(scaleTimer);
  scaleTimer = setTimeout(() => {
    if (canScaleQty.value) scaleRowsToOrderQty();
  }, 600);
};

watch(
  () => form.orderQty,
  v => {
    const n = Number(v);
    if (!Number.isFinite(n) || n <= 0) return;
    if (!baseQtyTouched.value) {
      form.baseQty = String(n);
      return;
    }
    // 套了模版又改数量时自动按比例折算，逻辑在下面 autoScaleOnQtyChange
    // （它依赖 canScaleQty / scaleRowsToOrderQty，定义在后面）。
    autoScaleOnQtyChange();
  }
);

// 手动改过用量的行打标记，之后总数再变也不覆盖它。
const setRowQty = (row, v) => {
  row.qty = v;
  row.qtyTouched = true;
};

// 完全空行（默认铺的 10 行里没填的）：保存时忽略、不参与校验。
const isRowEmpty = r =>
  !r.materialNo.trim() &&
  !r.materialName.trim() &&
  !r.specification.trim() &&
  !r.unit.trim() &&
  !r.remark.trim() &&
  !r.purchaseNote.trim() &&
  !r.productionNote.trim() &&
  !Number(r.qty);
const isRowComplete = r =>
  !!r.materialNo.trim() && !!r.materialName.trim() && !!Number(r.qty);
const filledRows = computed(() => form.rows.filter(r => !isRowEmpty(r)));

// 复制成金蝶「生产任务单 → 材料信息 → 快速贴粘」能直接吃的格式。
// 金蝶那个粘贴框按列顺序读制表符分隔的文本，所以这里严格按它材料明细的列序出：
//   物料编码 → 物料名称 → 规格型号 → 用量
// 只出填了物料编码的行（默认空行、没选料的行不带过去）。
const kingdeeCell = v =>
  String(v ?? '')
    .replace(/[\t\r\n]+/g, ' ')
    .trim();

const copyForKingdee = async () => {
  const rows = form.rows.filter(r => r.materialNo?.trim() && !isRowEmpty(r));
  if (!rows.length) {
    useAlert('还没有填了物料编码的明细行，没有可复制的内容。');
    return;
  }
  const tsv = rows
    .map(r =>
      [r.materialNo, r.materialName, r.specification, r.qty]
        .map(kingdeeCell)
        .join('\t')
    )
    .join('\n');
  try {
    await copyTextToClipboard(tsv);
    useAlert(
      `已复制 ${rows.length} 行，到金蝶「生产任务单 → 材料信息 → 快速贴粘」里粘贴即可。`
    );
  } catch {
    useAlert('复制失败，请检查浏览器剪贴板权限。');
  }
};

const invalid = computed(
  () =>
    !form.productLine || // 产线必填：漏了这条单子切到任何产线都看不见
    !form.crmProductId || // 产成品必须选自产品档案：只填文本等于没关联，下游按 id 对不上
    filledRows.value.length === 0 || // 至少一条实质用料
    filledRows.value.some(r => !isRowComplete(r)) // 已填的行必须完整
);

// ── 未保存提醒 ──────────────────────────────────────────────
// BOM 经常要填几十行料，填到一半点了「取消」就全没了。拦截 UI 在 Dialog 里，
// 这里只负责判脏：onHand / qtyTouched 是选料时服务端带回来的实时库存和交互标记，
// 不算用户改动，算进去会让刚打开的单子就被判成「已修改」。
const { isDirty, markPristine } = useDirtyGuard(() => form, {
  ignore: ['onHand', 'qtyTouched'],
});

// —— 批量粘贴代码（对标金蝶）：从电子投单单复制一整列编码，一次全部匹配进明细 ——
// 支持「编码」或「编码<tab>用量」（Excel 复制多列就是 tab 分隔）；
// 匹配不上的照样留一行并标出来，让人手动补选，不至于整批白贴。
const pasteDialogRef = ref(null);
const pasteText = ref('');
const pasteRows = ref([]);
const pasteBusy = ref(false);

const openPaste = () => {
  pasteText.value = '';
  pasteRows.value = [];
  pasteDialogRef.value?.open();
};

const parsePasteLines = text =>
  text
    .split(/\r?\n/)
    .map(l => l.trim())
    .filter(Boolean)
    .map(line => {
      const [code, qty] = line
        .split(/[\t,;，]+|\s{2,}/)
        .map(x => (x || '').trim());
      return { code, qty: Number(qty) > 0 ? String(Number(qty)) : '' };
    })
    .filter(r => r.code);

const previewPaste = async () => {
  const parsed = parsePasteLines(pasteText.value);
  if (!parsed.length) {
    useAlert('没读到编码，一行一个');
    return;
  }
  pasteBusy.value = true;
  try {
    const { data } = await axios.post(
      `/api/v1/accounts/${accountId.value}/mes/products/lookup`,
      { codes: parsed.map(r => r.code) }
    );
    const hits = data?.payload || [];
    pasteRows.value = parsed.map((r, i) => ({
      ...r,
      product: hits[i]?.product || null,
    }));
  } catch {
    useAlert('查编码失败，请重试');
  } finally {
    pasteBusy.value = false;
  }
};

const pasteMatched = computed(
  () => pasteRows.value.filter(r => r.product).length
);

const applyPaste = () => {
  if (!pasteRows.value.length) return;
  // 先把默认铺的空行清掉，再按粘贴顺序追加。
  form.rows = form.rows.filter(r => !isRowEmpty(r));
  pasteRows.value.forEach(r => {
    const row = blankRow();
    if (r.product) {
      row.productId = String(r.product.id);
      row.materialNo = r.product.sku || r.code;
      row.materialName = r.product.name || '';
      row.specification = r.product.specification || '';
      row.unit = r.product.unit || '';
      row.auxOptions = r.product.aux_attributes || [];
      row.productRemark = r.product.remark || '';
    } else {
      // 没匹配上的也留一行：编码填上、名称留空，人工补选比重贴一遍省事。
      row.materialNo = r.code;
      row.remark = '编码未匹配到产品档案，请手动选料';
    }
    row.qty = r.qty || autoQty.value || '';
    row.qtyTouched = Boolean(r.qty);
    form.rows.push(row);
  });
  if (!form.rows.length) form.rows.push(blankRow());
  const miss = pasteRows.value.length - pasteMatched.value;
  useAlert(
    miss
      ? `已填入 ${pasteRows.value.length} 行，其中 ${miss} 行没匹配上`
      : `已填入 ${pasteRows.value.length} 行`
  );
  pasteDialogRef.value?.close();
};

// 用料明细里点中的那一行（只做视觉焦点，不参与提交）。
const activeRow = ref(null);

const addRow = () => form.rows.push(blankRow());
const removeRow = i => {
  const [removed] = form.rows.splice(i, 1);
  if (removed?.id) removedItemIds.value.push(removed.id);
};

// 关联生产订单（选填，仅新建）：「保存并下发」时自动挂接到该订单（进 BOM_READY）。
// 列表取停在「销售订单确定」的待挂 BOM 订单。
const attachOrderId = ref('');
const attachableOrders = ref([]);
const attachOrderOptions = computed(() => [
  { value: '', label: '不关联（仅建生产任务单，不挂到订单）' },
  ...attachableOrders.value.map(o => ({
    value: String(o.id),
    label: `${o.order_no} · ${o.product_name} × ${o.qty} · ${o.owner_name || ''}`,
  })),
]);
const loadAttachableOrders = async () => {
  try {
    const { data } = await MesProductionOrderAPI.get({
      stage: 'SALES_CONFIRMED',
      status: 'IN_PROGRESS',
      per_page: 200,
    });
    attachableOrders.value = data.payload || [];
  } catch {
    attachableOrders.value = [];
  }
};

// 选了关联生产订单就把订单上的信息带过来：投单单号直接取工单号——这是「全链一个单号」
// 的落点，纸质单从下发到采购到生产认的就是它。其余字段（型号/数量/客户/产成品代码）
// 订单上本来就有，不带出来等于让人照着订单再手敲一遍，还容易敲错。
// 只填空位，不覆盖已经手动改过的内容。
watch(attachOrderId, id => {
  if (!id) return;
  const o = attachableOrders.value.find(x => String(x.id) === String(id));
  if (!o) return;
  if (!form.docNo) form.docNo = o.order_no || '';
  if (!form.model) form.model = o.product_name || '';
  if (!form.orderQty) form.orderQty = o.qty ?? '';
  if (!form.customerName) form.customerName = o.customer_name || '';
  if (!form.productCode) form.productCode = o.product_sku || '';
  if (!form.productId && o.crm_product_id) {
    form.productId = String(o.crm_product_id);
    form.crmProductId = String(o.crm_product_id);
  }
  // 归属业务员：订单的 owner 对「按单生产」就是归属业务员，但建单人也可能是工程/PMC。
  // 下拉只列业务角色，带一个不在候选里的人进去会显示成空白，所以先确认它在候选里。
  const oid = o.owner_id ? String(o.owner_id) : '';
  if (
    !form.salesOwnerId &&
    oid &&
    salesOwnerOptions.value.some(x => x.value === oid)
  )
    form.salesOwnerId = oid;
});

// —— 图片 / 附件 ——
// 新增文件选择即暂存为 blob（拿 signed_id），保存时随 payload 追加挂载（append，不覆盖）。
// 编辑态的既有附件单独展示，删除即时调 detach 接口。
const pendingImages = ref([]); // [{ name, signedId, previewUrl }]
const pendingFiles = ref([]);
// logo 单独一桶：客户要印在产品上的标，和结构图/样品图不是一回事，混在一起分不清。
const pendingLogos = ref([]);
const existingImages = ref([]); // 编辑态既有：[{ id, filename, url }]
const existingFiles = ref([]);
const existingLogos = ref([]);
const staging = ref(false);
const PENDING_BUCKETS = {
  images: pendingImages,
  files: pendingFiles,
  logos: pendingLogos,
};
const EXISTING_BUCKETS = {
  images: existingImages,
  files: existingFiles,
  logos: existingLogos,
};
const pendingFor = kind => PENDING_BUCKETS[kind];
const pickAttachment = async (event, kind) => {
  const list = Array.from(event.target.files || []);
  event.target.value = '';
  if (!list.length) return;
  const isImage = kind !== 'files';
  staging.value = true;
  try {
    const staged = await Promise.all(
      list.map(file => {
        const fd = new FormData();
        fd.append('file', file);
        return MesBomAPI.stageBlob(fd).then(({ data }) => ({
          name: data.filename,
          signedId: data.signed_id,
          previewUrl: isImage ? URL.createObjectURL(file) : '',
        }));
      })
    );
    pendingFor(kind).value.push(...staged);
  } catch (e) {
    useAlert(
      `上传失败：${e?.response?.data?.error || e?.message || '未知错误'}`
    );
  } finally {
    staging.value = false;
  }
};
const removePending = (kind, i) => pendingFor(kind).value.splice(i, 1);
// 编辑态删除既有附件：即时生效。
const removeExisting = async (kind, att) => {
  try {
    await MesBomAPI.detachFile(editingId.value, att.id, kind);
    const list = EXISTING_BUCKETS[kind];
    list.value = list.value.filter(f => f.id !== att.id);
  } catch {
    useAlert('删除附件失败');
  }
};
const resetAttachments = () => {
  pendingImages.value = [];
  pendingFiles.value = [];
  pendingLogos.value = [];
  existingImages.value = [];
  existingFiles.value = [];
  existingLogos.value = [];
};

// preOrder：从生产订单页「去建 BOM」带来的预关联订单对象（自动选中「关联生产订单」）。
const openCreate = async (preOrder = null) => {
  editingId.value = null;
  editingStatus.value = null;
  baseQtyTouched.value = false; // 新建：基准产量跟着投单数量走
  changeReason.value = '';
  removedItemIds.value = [];
  attachOrderId.value = '';
  resetAttachments();
  Object.assign(form, {
    productLine: activeProductLine.value || '',
    crmProductId: '',
    salesOwnerId: '',
    baseQty: '1',
    unit: '台',
    remark: '',
    ...blankHeader(),
    ...blankLeadDays(),
    // 新建默认铺 10 个空行，方便批量录入用料（不够可继续「加一行」）。
    rows: Array.from({ length: 10 }, () => blankRow()),
  });
  await loadAttachableOrders();
  // 从生产订单页「去建 BOM」带来的预关联订单：若可挂列表里没有（状态/分页原因），
  // 用带来的订单信息补一条，确保「关联生产订单」一定能预选到本单。
  const pid = preOrder?.id ? String(preOrder.id) : '';
  if (pid) {
    if (
      !attachableOrders.value.some(o => String(o.id) === pid) &&
      preOrder.order_no
    ) {
      attachableOrders.value = [
        {
          id: preOrder.id,
          order_no: preOrder.order_no,
          product_name: preOrder.product_name,
          qty: preOrder.qty,
          owner_name: preOrder.owner_name,
        },
        ...attachableOrders.value,
      ];
    }
    if (attachableOrders.value.some(o => String(o.id) === pid)) {
      attachOrderId.value = pid;
    }
  }
  markPristine();
};
const openEdit = bom => {
  editingId.value = bom.id;
  editingStatus.value = bom.status;
  baseQtyTouched.value = true; // 编辑已存生产任务单：存下来的基准产量不许被投单数量冲掉
  changeReason.value = '';
  removedItemIds.value = [];
  resetAttachments();
  existingImages.value = [...(bom.images || [])];
  existingFiles.value = [...(bom.files || [])];
  existingLogos.value = [...(bom.logos || [])];
  Object.assign(form, {
    productLine: bom.productLine || '',
    crmProductId: bom.crmProductId ? String(bom.crmProductId) : '',
    salesOwnerId: bom.salesOwnerId ? String(bom.salesOwnerId) : '',
    baseQty: String(bom.baseQty ?? '1'),
    unit: bom.unit || '',
    remark: bom.remark || '',
    submitDate: bom.submitDate || '',
    docNo: bom.docNo || '',
    customerName: bom.customerName || '',
    model: bom.model || '',
    productCode: bom.productCode || '',
    productId: bom.crmProductId ? String(bom.crmProductId) : '',
    orderQty: bom.orderQty ?? '',
    bareColor: bom.bareColor || '',
    caseColor: bom.caseColor || '',
    ...Object.fromEntries(LEAD_STAGES.map(s => [s.key, bom[s.key] ?? ''])),
    rows: (bom.bomItems || []).map(it => ({
      id: it.id,
      productId: '',
      materialNo: it.materialNo || '',
      materialName: it.materialName || '',
      specification: it.specification || '',
      unit: it.unit || '',
      qty: String(it.qty ?? ''),
      suggestedPurchaseQty:
        it.suggestedPurchaseQty != null ? String(it.suggestedPurchaseQty) : '',
      onHand: it.onHand != null ? Number(it.onHand) : null,
      auxAttributeId: it.crmProductAuxAttributeId
        ? String(it.crmProductAuxAttributeId)
        : '',
      auxAttributeName: it.auxAttributeName || '',
      // 选项现在由后端按料号从产品档案带回（以前这里是空数组，重开编辑下拉就空了、
      // 已选属性显示成「—」）。
      auxOptions: it.auxOptions || [],
      productRemark: it.productRemark || '',
      remark: it.remark || '',
      purchaseNote: it.purchaseNote || '',
      blockerKind: it.blockerKind || '',
      blockerNote: it.blockerNote || '',
      productionNote: it.productionNote || '',
      category: it.category || 'MACHINE',
      qtyTouched: it.qty != null && it.qty !== '',
    })),
  });
  markPristine();
};

// targetStatus：'DRAFT' 存草稿 / 'RELEASED' 下发。
const submit = async targetStatus => {
  if (invalid.value) return;
  const itemsAttributes = [
    ...filledRows.value.map(r => ({
      id: r.id || undefined,
      materialNo: r.materialNo.trim(),
      materialName: r.materialName.trim(),
      specification: r.specification.trim(),
      unit: r.unit.trim(),
      qty: Number(r.qty),
      suggestedPurchaseQty:
        r.suggestedPurchaseQty !== '' ? Number(r.suggestedPurchaseQty) : null,
      crmProductAuxAttributeId: r.auxAttributeId || null,
      remark: r.remark.trim(),
      purchaseNote: r.purchaseNote.trim() || null,
      blockerKind: r.blockerKind || null,
      blockerNote: r.blockerNote?.trim() || null,
      productionNote: r.productionNote.trim() || null,
      category: r.category || 'MACHINE',
    })),
    ...removedItemIds.value.map(id => ({ id, _destroy: true })),
  ];
  const payload = {
    crmProductId: form.crmProductId || null,
    salesOwnerId: form.salesOwnerId || null,
    productLine: form.productLine || null,
    baseQty: Number(form.baseQty) || 1,
    unit: form.unit,
    remark: form.remark.trim() || null,
    submitDate: form.submitDate || null,
    docNo: form.docNo.trim() || null,
    customerName: form.customerName.trim() || null,
    model: form.model.trim() || null,
    productCode: form.productCode.trim() || null,
    orderQty: Number(form.orderQty) || null,
    bareColor: form.bareColor.trim() || null,
    caseColor: form.caseColor.trim() || null,
    status: targetStatus,
    // 已下发 BOM 改用料时带上变更原因（后端据此记变更史 + 通知已参与部门）。
    changeReason:
      editingId.value && editingStatus.value === 'RELEASED'
        ? changeReason.value.trim() || null
        : undefined,
    productionOrderId: editingId.value
      ? undefined
      : attachOrderId.value || null,
    images: pendingImages.value.map(p => p.signedId),
    files: pendingFiles.value.map(p => p.signedId),
    logos: pendingLogos.value.map(p => p.signedId),
    ...Object.fromEntries(
      LEAD_STAGES.map(s => [s.key, Number(form[s.key]) || null])
    ),
    bomItemsAttributes: itemsAttributes,
  };
  const ok = editingId.value
    ? await store.update({ id: editingId.value, ...payload })
    : await store.create(payload);
  if (ok) {
    const attached =
      !editingId.value && attachOrderId.value && targetStatus === 'RELEASED';
    const verb = targetStatus === 'RELEASED' ? '已下发' : '已存草稿';
    let msg;
    if (attached) msg = `已下发 ${ok.bomNo} 并挂接到订单，待业务员确认`;
    else if (editingId.value && editingStatus.value === 'RELEASED')
      msg = '生产任务单已保存，用料变更已通知相关采购/领料/库存';
    else if (editingId.value) msg = `生产任务单 ${verb}`;
    else msg = `${verb} ${ok.bomNo}`;
    useAlert(msg);
    markPristine();
    leaving = true; // 已保存，离开时不用再问
    backToList();
  }
};

// —— BOM 模版：把常用成品的十几二十行用料存成模版，建 BOM 时一键套用 ——
const templates = computed(() => tplStore.getRecords);
const tplHiddenNoLine = computed(() => tplStore.getMeta.hiddenNoLine || 0);
const tplFetching = computed(() => tplStore.getUIFlags.fetchingList);
const tplSaving = computed(() => tplStore.getUIFlags.creatingItem);
const templateDialogRef = ref(null);
const saveTplDialogRef = ref(null);
const templateName = ref('');
const confirmingDeleteId = ref(null);
const tplDeletingId = ref(null);
const tplQuery = ref('');

// 模版攒到几十份后平铺列表翻不动了。模版是一次全取的，直接前端过滤，
// 搜名字也搜备注（备注里有产成品代码、来源单号、来源文件名）。
const filteredTemplates = computed(() => {
  const q = tplQuery.value.trim().toLowerCase();
  if (!q) return templates.value;
  return templates.value.filter(t =>
    [t.name, t.remark, productLineLabel(t.productLine)].some(v =>
      String(v || '')
        .toLowerCase()
        .includes(q)
    )
  );
});

const openTemplates = () => {
  confirmingDeleteId.value = null;
  tplQuery.value = '';
  tplStore.get();
  templateDialogRef.value?.open();
};

// 套模版后按编码回查产品档案，把物料名称/规格型号换成**系统里的**写法。
// 模版是从电子生产单导进来的，同一颗料在 Excel 里和档案里措辞常常不一样
// （用户：以系统为准，不要用电子单的文字）。查不到的编码原样保留，不乱改。
const alignTemplateRowsToCatalog = async () => {
  const codes = form.rows.map(r => r.materialNo).filter(Boolean);
  if (!codes.length) return;
  try {
    const { data } = await axios.post(
      `/api/v1/accounts/${accountId.value}/mes/products/lookup`,
      { codes }
    );
    const byCode = new Map(
      (data?.payload || [])
        .filter(x => x.product)
        .map(x => [String(x.code), x.product])
    );
    let aligned = 0;
    form.rows.forEach(r => {
      const hit = byCode.get(String(r.materialNo));
      if (!hit) return;
      const name = hit.name || '';
      const spec = hit.specification || '';
      if (
        (name && name !== r.materialName) ||
        (spec && spec !== r.specification)
      ) {
        aligned += 1;
      }
      if (name) r.materialName = name;
      if (spec) r.specification = spec;
      if (hit.id) r.crmProductId = String(hit.id);
    });
    if (aligned) {
      useAlert(`已按产品档案校正 ${aligned} 行的物料名称/规格`);
      markPristine();
    }
  } catch {
    // 查不到就用模版原文，不打断套用流程
  }
};

// 模版行的备注拆回两列。
// 65 份模版是从电子生产单 Excel 导进来的，当时模版表没有「采购注意事项」这一列，
// 于是「供应商：振高 / 正常下单」这类**写给采购的**内容被一起塞进了备注；套用后就全挤在
// 备注列里（用户：框1 的内容应该显示在框2）。这里按导入时的写法拆回去：
// 以「供应商：」开头的整句归采购注意事项，其余留在备注。
const SUPPLIER_NOTE_RE = /^\s*供应商\s*[:：]/;
const splitTemplateRemark = raw => {
  const text = String(raw || '').trim();
  if (!text) return { remark: '', purchaseNote: '' };
  return SUPPLIER_NOTE_RE.test(text)
    ? { remark: '', purchaseNote: text }
    : { remark: text, purchaseNote: '' };
};

// 页内查改产品档案：做任务单时要核对/顺手改某颗料的档案，原来必须存草稿退出去再回来。
const productPanelRef = ref(null);
const openProductPanel = row => {
  if (!row.productId && !row.materialNo) {
    useAlert('这一行还没选物料');
    return;
  }
  // 存盘的 BOM 行只有编码文本，没有产品 id，所以优先用 id、没有就按编码查。
  productPanelRef.value?.show({ id: row.productId, code: row.materialNo });
};
// 档案改完即时回写到用料明细的对应行（同一颗料可能在多行里出现）。
const onProductSaved = saved => {
  form.rows.forEach(r => {
    const same =
      (r.productId && String(r.productId) === String(saved.id)) ||
      (r.materialNo && saved.sku && r.materialNo === saved.sku);
    if (!same) return;
    if (saved.name) r.materialName = saved.name;
    if (saved.specification != null) r.specification = saved.specification;
    if (saved.unit) r.unit = saved.unit;
    r.productRemark = saved.remark ?? r.productRemark;
  });
};

// 套用模版：预填新建 BOM 表单（模版不含成品，仍需选成品再保存）。
const applyTemplate = t => {
  editingId.value = null;
  editingStatus.value = null;
  removedItemIds.value = [];
  // 模版自带的基准产量就是它那批用料的口径（如 3500 台的料），
  // 必须按住不让「数量」的联动把它冲成新数量——冲掉了就算不出缩放比例。
  baseQtyTouched.value = true;
  // 这批料来自模版：填「数量」时自动按比例折算（见 watch(form.orderQty)）。
  // 已存盘的单不走这条——那上面的用量是人调过的，不能被数量一改就冲掉。
  fromTemplate.value = true;
  Object.assign(form, {
    crmProductId: '',
    baseQty: String(t.baseQty ?? '1'),
    unit: t.unit || '台',
    remark: '',
    ...blankHeader(),
    ...Object.fromEntries(LEAD_STAGES.map(s => [s.key, t[s.key] ?? ''])),
    // 必须从 blankRow() 铺底：模版只存了几个字段，少铺 auxOptions / purchaseNote 这些，
    // 套用后渲染 `row.auxOptions` 直接 undefined.length 整页白屏（套用模版点下去就崩）。
    rows: (t.bomTemplateItems || []).map(it => ({
      ...blankRow(),
      materialNo: it.materialNo || '',
      materialName: it.materialName || '',
      specification: it.specification || '',
      unit: it.unit || '',
      qty: String(it.qty ?? ''),
      ...splitTemplateRemark(it.remark),
      category: it.category || 'MACHINE',
      qtyTouched: it.qty != null && it.qty !== '',
    })),
  });
  if (!form.rows.length) form.rows.push(blankRow());
  markPristine();
  templateDialogRef.value?.close();
  alignTemplateRowsToCatalog();
};

const removeTemplate = async t => {
  tplDeletingId.value = t.id;
  try {
    await tplStore.delete(t.id);
    useAlert('模版已删除');
  } catch {
    useAlert('删除失败');
  } finally {
    tplDeletingId.value = null;
    confirmingDeleteId.value = null;
  }
};

// 列宽拖动、加减行、窗口缩放都会改变明细区的总宽度，影子滚动条跟着重算。
watch([bomColTemplate, () => form.rows.length], () =>
  nextTick(measureItemsWidth)
);
onMounted(() => {
  nextTick(measureItemsWidth);
  window.addEventListener('resize', measureItemsWidth);
});
onBeforeUnmount(() => window.removeEventListener('resize', measureItemsWidth));

// 从当前 BOM 表单存为模版（用料明细 + 各阶段天数，不含成品）。
const openSaveTemplate = () => {
  if (invalid.value) return;
  templateName.value = form.crmProductId
    ? productOptions.value.find(p => p.value === form.crmProductId)?.label || ''
    : '';
  saveTplDialogRef.value?.open();
};
const saveTemplate = async () => {
  const name = templateName.value.trim();
  if (!name) return;
  const payload = {
    name,
    baseQty: Number(form.baseQty) || 1,
    unit: form.unit,
    ...Object.fromEntries(
      LEAD_STAGES.map(s => [s.key, Number(form[s.key]) || null])
    ),
    bomTemplateItemsAttributes: form.rows
      .filter(r => r.materialName.trim() && Number(r.qty))
      .map(r => ({
        materialNo: r.materialNo.trim(),
        materialName: r.materialName.trim(),
        specification: r.specification.trim(),
        unit: r.unit.trim(),
        qty: Number(r.qty),
        remark: r.remark.trim(),
      })),
  };
  const ok = await tplStore.create(payload);
  if (ok) {
    useAlert(`已存为模版「${ok.name}」`);
    saveTplDialogRef.value?.close();
  }
};

// 页面模式的进入点：带 ?id= 就是编辑，带 ?new_for_order= 是从生产订单页「去建 BOM」跳来，
// 都不带就是普通新建。编辑态要先把这张单取回来——列表页的数据不一定还在 store 里
// （直接贴链接/刷新页面进来时就是空的）。
const booting = ref(true);
const boot = async () => {
  booting.value = true;
  if (!agents.value?.length) rootStore.dispatch('agents/get');
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/products`
    );
    products.value = data?.payload || data || [];
  } catch {
    products.value = [];
  }

  const editId = route.query.id;
  if (editId) {
    try {
      const { data } = await MesBomAPI.show(editId);
      // 接口原样返回下划线键；列表页的数据是 store 转过的驼峰，openEdit 按驼峰读。
      // 不转的话 submitDate/productCode/bomItems 这些多词字段会全部读成 undefined，
      // 表单看着像「只回填了一半」。
      openEdit(camelcaseKeys(data?.payload || data || {}, { deep: true }));
    } catch {
      useAlert('这张生产任务单打不开，可能已被删除');
      backToList();
    }
  } else if (route.query.new_for_order) {
    await openCreate({
      id: route.query.new_for_order,
      order_no: route.query.nfo_no,
      product_name: route.query.nfo_product,
      qty: route.query.nfo_qty,
      owner_name: route.query.nfo_owner,
    });
  } else {
    await openCreate();
    // 从列表页「套用模版」过来：建完空单直接把模版弹窗推到脸上。
    if (route.query.templates) openTemplates();
  }
  booting.value = false;
  loadCommitments();
};
onMounted(boot);

// 本页在 MesLayout 的 keep-alive 里按 query 缓存：切去产品档案/供应商档案查完料
// 再切回来，填了一半的单子原样还在，不重跑 boot。但如果上次是「保存 / 不保存」
// 这类明确离开（leaving=true），缓存里那份已经没用了，重新进来要给张新单。
onActivated(() => {
  if (!leaving) return;
  leaving = false;
  boot();
});

// ── 离开页面前的未保存拦截 ──────────────────────────────────
// 整页没有「关弹窗」这个动作，拦截点改成路由离开。leaving 是放行开关：
// 保存成功、或用户选了「不保存」之后，再次触发离开就直接走。
const leaveDialogRef = ref(null);
let pendingLeave = null;

const requestLeave = () => {
  if (!isDirty.value) {
    leaving = true;
    backToList();
    return;
  }
  leaveDialogRef.value?.open();
};
const cancelLeave = () => {
  pendingLeave = null;
  leaveDialogRef.value?.close();
};
const confirmLeave = () => {
  leaving = true;
  leaveDialogRef.value?.close();
  if (pendingLeave) {
    const go = pendingLeave;
    pendingLeave = null;
    go();
  } else {
    backToList();
  }
};
const saveThenLeave = async () => {
  leaveDialogRef.value?.close();
  await submit(editingStatus.value === 'RELEASED' ? 'RELEASED' : 'DRAFT');
};

onBeforeRouteLeave((to, from, next) => {
  // 切去另一个 MES 标签时本页不销毁（keep-alive 留着），内容不会丢，不该拦。
  // 关标签（✕）要拦：MesTabBar 是先 closeTab 再跳转，所以此刻自己已不在标签条里。
  const switchingTab =
    String(to.name || '').startsWith('mes_') &&
    tabs.value.some(t => t.name === from.name);

  if (leaving || switchingTab || !isDirty.value || booting.value) {
    next();
    return;
  }
  // 拦下这次跳转，等用户在提醒里选完再决定放不放行。
  pendingLeave = () => next();
  leaveDialogRef.value?.open();
});
</script>

<template>
  <HScrollButtons />
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <!-- 操作条冻结在顶部：明细几十行时不用滚到底才点得到保存（反馈 A45） -->
    <div
      class="sticky top-0 z-20 flex flex-wrap items-center justify-between flex-shrink-0 gap-2 px-4 py-3 border-b bg-n-solid-1/80 backdrop-blur-xl border-n-weak sm:px-6 sm:py-4 [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:sm:!px-8"
    >
      <div class="flex items-center min-w-0 gap-3">
        <h1
          class="text-lg font-medium min-w-0 truncate text-n-slate-12 sm:text-xl [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8"
        >
          {{ editingId ? '编辑生产任务单' : '新建生产任务单' }}
        </h1>
        <span
          v-if="editingStatus === 'RELEASED'"
          class="px-2 py-0.5 rounded-full text-xs bg-n-teal-3 text-n-teal-11"
          >已下发</span
        >
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <Button
          label="套用模版"
          variant="outline"
          color="slate"
          size="sm"
          class="btn-ink"
          @click="openTemplates"
        />
        <Button
          label="存为模版"
          variant="outline"
          color="slate"
          size="sm"
          class="btn-ink"
          :disabled="invalid"
          @click="openSaveTemplate"
        />
        <Button
          label="取消"
          variant="ghost"
          color="slate"
          size="sm"
          @click="requestLeave"
        />
        <!-- 已下发的编辑：只保留「保存修改」，保持已下发状态（非重新下发/非草稿） -->
        <Button
          v-if="editingId && editingStatus === 'RELEASED'"
          label="保存修改（保持下发）"
          color="iris"
          size="sm"
          :is-loading="saving"
          :disabled="invalid"
          @click="submit('RELEASED')"
        />
        <template v-else>
          <Button
            label="存草稿"
            variant="outline"
            color="slate"
            size="sm"
            class="btn-ink"
            :is-loading="saving"
            :disabled="invalid"
            @click="submit('DRAFT')"
          />
          <Button
            label="下发"
            color="iris"
            size="sm"
            :is-loading="saving"
            :disabled="invalid"
            @click="submit('RELEASED')"
          />
        </template>
      </div>
    </div>

    <div class="flex flex-col w-full gap-4 px-4 py-4 sm:px-6 sm:py-5 [.theme-classic_&]:sm:!px-8">
      <div class="flex flex-col gap-4">
        <!-- 关联生产订单（仅新建）：下发即自动挂接、通知业务员确认 -->
        <div v-if="!editingId" class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12"
            >关联生产订单（选填）</label
          >
          <SelectCard
            v-model="attachOrderId"
            :options="attachOrderOptions"
            block
          />
          <p class="text-xs text-n-slate-10">
            选择后「保存并下发」将直接挂接到该订单，并提醒工程/PMC
            下发采购；存草稿不挂接。
          </p>
        </div>
        <!-- 投单信息（照 PMC 纸质 BOM 抬头） -->
        <div class="text-heading-2 text-n-slate-12">投单信息</div>
        <!-- 按内容定宽，不再一律三等分：日期/数量这种只要一点宽度，
             三等分会在后面拖出一大片空白；型号、客户名这种才需要长。 -->
        <div class="flex flex-wrap gap-3">
          <div class="flex flex-col w-40 gap-1">
            <label class="text-heading-3 text-n-slate-12">投单日期</label>
            <Input v-model="form.submitDate" type="date" />
          </div>
          <div class="flex flex-col w-48 gap-1">
            <label class="text-heading-3 text-n-slate-12">投单单号</label>
            <Input v-model="form.docNo" />
          </div>
          <div class="flex flex-col w-28 gap-1">
            <label class="text-heading-3 text-n-slate-12">数量</label>
            <Input v-model="form.orderQty" type="number" placeholder="800" />
          </div>
          <div class="flex flex-col w-56 gap-1">
            <label class="text-heading-3 text-n-slate-12"
              >产成品代码 <span class="text-n-ruby-11">*</span></label
            >
            <!-- 只能从产品档案选/搜，或在下拉里就地新建；不接受手打文本。 -->
            <!-- 换成产品档案选择器：输 01.033 就能搜到 P.01.033，不用连 P 一起打；
             选中后型号（档案里的产品名，如 K705）自动填上面那格，不用再手输一遍。 -->
            <MesProductPicker
              :model-value="form.productId"
              :account-id="accountId"
              :display-text="form.productCode"
              placeholder="输代码搜"
              @select="pickFinishedProduct"
            />
          </div>
          <div class="flex flex-col flex-1 min-w-[22rem] gap-1">
            <label class="text-heading-3 text-n-slate-12">型号</label>
            <Input v-model="form.model" />
          </div>
          <div v-if="showTabletHeaderFields" class="flex flex-col w-80 gap-1">
            <label class="text-heading-3 text-n-slate-12"
              >客户 / 项目名称</label
            >
            <Input v-model="form.customerName" />
          </div>
          <div v-if="showTabletHeaderFields" class="flex flex-col w-44 gap-1">
            <label class="text-heading-3 text-n-slate-12">裸机颜色</label>
            <Input v-model="form.bareColor" />
          </div>
          <div v-if="showTabletHeaderFields" class="flex flex-col w-56 gap-1">
            <label class="text-heading-3 text-n-slate-12">皮套颜色</label>
            <Input v-model="form.caseColor" />
          </div>
          <!-- 客户 Logo：要印在机器/皮套上的标，跟颜色一起看才对得上，所以放投单信息里，
               不塞到下面的结构图里（那是生产看图纸的地方）。 -->
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              Logo / 图片
              <span v-if="staging" class="ml-1 text-xs text-n-amber-11">
                上传中…
              </span>
            </label>
            <div class="flex flex-wrap items-center gap-2">
              <div
                v-for="lg in existingLogos"
                :key="`exl-${lg.id}`"
                class="relative w-20 h-10 group"
              >
                <a :href="lg.url" target="_blank" rel="noopener noreferrer">
                  <img
                    :src="lg.url"
                    :alt="lg.filename"
                    class="object-contain w-20 h-10"
                  />
                </a>
                <button
                  type="button"
                  class="absolute items-center justify-center hidden w-4 h-4 text-white rounded-full -top-1 -right-1 text-xxs bg-n-slate-12/70 group-hover:flex"
                  @click="removeExisting('logos', lg)"
                >
                  ✕
                </button>
              </div>
              <div
                v-for="(f, i) in pendingLogos"
                :key="`pnl-${i}`"
                class="relative w-20 h-10 group"
              >
                <img :src="f.previewUrl" class="object-contain w-20 h-10" />
                <button
                  type="button"
                  class="absolute items-center justify-center hidden w-4 h-4 text-white rounded-full -top-1 -right-1 text-xxs bg-n-slate-12/70 group-hover:flex"
                  @click="removePending('logos', i)"
                >
                  ✕
                </button>
              </div>
              <label
                class="flex items-center h-10 gap-1 px-3 border border-dashed rounded-lg cursor-pointer text-label-small border-n-weak text-n-slate-11 hover:text-n-slate-12"
              >
                <span class="i-lucide-image-plus size-4" />
                插入图片
                <input
                  type="file"
                  accept="image/*"
                  multiple
                  class="hidden"
                  @change="e => pickAttachment(e, 'logos')"
                />
              </label>
            </div>
          </div>
        </div>

        <div class="flex flex-wrap gap-4 pt-2 border-t border-n-weak">
          <div class="flex flex-col w-40 gap-1">
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
          <div class="flex flex-col w-56 gap-1">
            <label class="text-heading-3 text-n-slate-12"
              >订单归属业务员（选填）</label
            >
            <ComboBox
              v-model="form.salesOwnerId"
              :options="salesOwnerOptions"
              placeholder="选择业务员"
            />
          </div>
          <!-- 基准产量常是 1000、10000 这种四五位数，w-20 只装得下三位（用户：这个框要放大一点） -->
          <div class="flex flex-col gap-1 w-60">
            <label class="text-heading-3 text-n-slate-12"
              >基准产量 / 单位</label
            >
            <div class="flex gap-2">
              <Input
                v-model="form.baseQty"
                type="number"
                class="flex-1 min-w-0"
                @input="baseQtyTouched = true"
              />
              <Input v-model="form.unit" placeholder="台" class="w-16" />
            </div>
          </div>
        </div>

        <div class="flex flex-col gap-2">
          <div class="flex items-center justify-between">
            <span class="text-heading-2 text-n-slate-12">各阶段预估天数</span>
            <span class="text-xs text-n-slate-11">
              预估周期合计：<span class="font-medium text-n-slate-12">{{
                totalLeadDays
              }}</span>
              天
            </span>
          </div>
          <div class="grid grid-cols-5 gap-2">
            <div
              v-for="s in LEAD_STAGES"
              :key="s.key"
              class="flex flex-col gap-1"
            >
              <label class="text-heading-3 text-n-slate-12">{{
                s.label
              }}</label>
              <Input v-model="form[s.key]" type="number" placeholder="天" />
            </div>
          </div>
        </div>

        <div
          class="flex items-center justify-between pt-2 border-t border-n-weak"
        >
          <span class="text-heading-2 text-n-slate-12">
            用料明细 <span class="text-n-ruby-11">*</span>
          </span>
          <span class="flex gap-2 items-center">
            <Button
              label="批量粘贴代码"
              variant="ghost"
              size="sm"
              @click="openPaste"
            />
            <Button
              label="复制到金蝶"
              variant="ghost"
              size="sm"
              @click="copyForKingdee"
            />
            <Button
              label="恢复默认列宽"
              variant="ghost"
              size="sm"
              @click="resetColWidths"
            />
            <Button
              label="恢复默认列序"
              variant="ghost"
              size="sm"
              @click="resetBomColOrder"
            />
            <Button
              label="按投单数量等比缩放"
              variant="ghost"
              size="sm"
              :disabled="!canScaleQty"
              :title="scaleHint"
              @click="scaleRowsToOrderQty"
            />
            <Button
              label="+ 加一行"
              variant="ghost"
              size="sm"
              @click="addRow"
            />
          </span>
        </div>

        <MesProductQuickPanel ref="productPanelRef" @saved="onProductSaved" />

        <!-- 顶部横向滚动条：自绘，常驻可见，可拖可点，不用滚到底才能横着看。 -->
        <div
          v-show="itemsOverflow"
          ref="trackRef"
          class="relative h-2 rounded-full cursor-pointer bg-n-slate-4"
          @pointerdown="onTrackDown"
        >
          <div
            class="absolute top-0 h-2 transition-colors rounded-full cursor-grab bg-n-slate-8 hover:bg-n-slate-9 active:cursor-grabbing"
            :style="thumbStyle"
            @pointerdown.stop="onThumbDown"
            @pointermove="onThumbMove"
            @pointerup="onThumbUp"
            @pointercancel="onThumbUp"
          />
        </div>

        <!-- 明细区单独横向滚动：13 列挤在页面宽度里，拉宽「物料名称」就把「规格型号」
         压没了。给一个最小宽度后不够宽就横着滚，各列保持看得清。 -->
        <!-- 明细区自己做滚动容器（纵向限高 + 横向滚动），表头才能真正冻住：
             只写 overflow-x-auto 的话 CSS 会把纵向也变成滚动容器，sticky 表头粘的是它、
             而不是页面，往下滚就跟着跑了（实测滚动后表头 top 变成 -94）。 -->
        <HScrollButtons />
        <div
          ref="itemsScrollRef"
          class="flex flex-col gap-2 overflow-auto max-h-[60vh]"
          @scroll="onItemsScroll"
        >
          <!-- 表头：每列右边一根可拖的竖线（像 Excel），拖完的宽度记在本机。
               sticky 冻结在明细区顶部——几十行料往下填时还看得见这一列是什么
               （z-10 + 不透明底色，否则下面的行会透上来压住表头）。 -->
          <div
            class="sticky top-0 z-10 grid gap-2 px-1 py-1 text-xs min-w-[1460px] text-n-slate-11 bg-n-solid-1 border-b border-n-weak"
            :style="{ gridTemplateColumns: bomColTemplate }"
          >
            <span
              v-for="c in bomCols"
              :key="c.key"
              class="relative min-w-0"
              :class="[
                c.fixed == null ? 'cursor-move' : '',
                isBomColDragging(c.key) ? 'opacity-40' : '',
              ]"
              :draggable="c.fixed == null"
              :title="
                c.fixed == null ? `${c.label}（可拖动调整列顺序）` : c.label
              "
              @dragstart="onBomColDragStart(c.key)"
              @dragover.prevent
              @drop="onBomColDrop(c.key)"
            >
              <!-- 标签单独一层：truncate 是 overflow:hidden，
               把手放在这层里会被裁掉，鼠标点不到。 -->
              <span class="block truncate">
                <template v-if="c.key === 'idx'">#</template>
                <template v-else-if="c.label">
                  {{ c.label }}
                  <span
                    v-if="REQUIRED_COLS.includes(c.key)"
                    class="text-n-ruby-11"
                  >
                    *
                  </span>
                </template>
              </span>
              <span
                v-if="c.fixed == null"
                class="absolute z-10 flex justify-center w-3 h-6 -right-2 -top-1 cursor-col-resize group/grip"
                title="拖动调整列宽（像 Excel 那样）"
                @mousedown.prevent="startColResize(c.key, $event)"
              >
                <span
                  class="w-px h-full bg-n-weak group-hover/grip:bg-n-brand group-hover/grip:w-0.5"
                />
              </span>
            </span>
          </div>
          <!-- 点中的那一行高亮：几十行料对着纸质单核的时候，没有焦点行容易串行。
               只是视觉焦点，不参与任何提交。 -->
          <div
            v-for="(row, i) in form.rows"
            :key="i"
            class="pb-2 border-b border-dashed border-n-weak last:border-0"
            :class="activeRow === i ? 'bg-n-iris-3 rounded-md' : ''"
            @click="activeRow = i"
          >
            <div
              class="grid items-center gap-2 min-w-[1460px]"
              :style="{ gridTemplateColumns: bomColTemplate }"
            >
              <span
                class="text-xs tabular-nums"
                :style="colPos('idx')"
                :class="
                  activeRow === i
                    ? 'font-semibold text-n-iris-11'
                    : 'text-n-slate-10'
                "
              >
                {{ i + 1 }}
              </span>
              <div :style="colPos('category')">
                <SelectCard
                  v-model="row.category"
                  :options="CATEGORY_OPTIONS"
                  block
                />
              </div>
              <div
                :style="colPos('materialNo')"
                class="flex items-center gap-1 min-w-0"
              >
                <MesProductPicker
                  class="flex-1 min-w-0"
                  :model-value="row.productId"
                  :account-id="accountId"
                  :display-text="
                    row.materialNo
                      ? `${row.materialNo}${row.materialName ? ` · ${row.materialName}` : ''}`
                      : ''
                  "
                  placeholder="选物料"
                  trigger-class=""
                  @select="p => pickMaterial(row, p)"
                />
                <!-- 页内查改这颗料的档案，不用离开本页 -->
                <button
                  v-if="row.productId || row.materialNo"
                  type="button"
                  class="grid rounded shrink-0 size-6 place-items-center text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-iris-11"
                  title="查看 / 修改这颗料的产品档案"
                  @click.stop="openProductPanel(row)"
                >
                  <span class="i-lucide-file-pen-line size-3.5" />
                </button>
              </div>
              <Input
                :style="colPos('materialName')"
                :model-value="row.materialName"
                placeholder="选编码自动带出"
                disabled
              />
              <Input
                v-model="row.specification"
                :style="colPos('spec')"
                placeholder="规格型号"
                :title="row.specification"
              />
              <!-- 辅助属性：只列该物料档案里启用中的，单选。没维护过就显示「—」。 -->
              <SelectCard
                v-if="row.auxOptions.length"
                :style="colPos('aux')"
                :model-value="row.auxAttributeId"
                :options="auxOptionsOf(row)"
                block
                @update:model-value="v => pickAuxAttribute(row, v)"
              />
              <span
                v-else
                :style="colPos('aux')"
                class="px-1 text-xs truncate text-n-slate-10"
                :title="row.auxAttributeName || '该物料未维护辅助属性'"
              >
                {{ row.auxAttributeName || '—' }}
              </span>
              <Input
                v-model="row.unit"
                placeholder="台"
                :title="row.unit"
                :style="colPos('unit')"
              />
              <Input
                :style="colPos('qty')"
                :model-value="row.qty"
                type="number"
                placeholder="用量"
                @update:model-value="v => setRowQty(row, v)"
              />
              <Input
                v-model="row.suggestedPurchaseQty"
                :style="colPos('suggest')"
                :title="row.suggestedPurchaseQty"
                type="number"
                placeholder="选填"
              />
              <!-- 实时库存：这格原来漏了 grid-column，于是拖动列序后它自动流到下一个空位，
                   把后面所有格子整体顶歪——就是反馈里「拖了以后列表是乱码」的那个现象。 -->
              <span
                class="flex items-center gap-1 px-1 text-xs min-w-0"
                :style="colPos('onHand')"
                :class="
                  row.onHand == null ? 'text-n-slate-10' : 'text-n-slate-12'
                "
                :title="row.onHand == null ? '选料后显示' : String(row.onHand)"
              >
                <span class="truncate">
                  {{ row.onHand == null ? '—' : row.onHand }}
                </span>
                <!-- 被别的单排掉了：库存数旁边挂个感叹号，悬停说清楚还剩多少能用。 -->
                <span
                  v-if="row.onHand != null && committedOf(row) > 0"
                  v-tooltip.top="commitmentTip(row)"
                  class="shrink-0 size-3.5 cursor-help i-lucide-circle-alert"
                  :class="
                    availableOf(row) < 0 ? 'text-n-ruby-11' : 'text-n-amber-11'
                  "
                />
              </span>
              <!-- 本行备注空着时，先把产品档案上的备注（工程写的工艺要求）显出来当占位，
               一旦本行自己填了就盖掉；完整内容挂 title。 -->
              <Input
                v-model="row.remark"
                :style="colPos('remark')"
                :placeholder="row.productRemark || '备注'"
                :title="
                  row.remark ||
                  (row.productRemark
                    ? `产品档案备注：${row.productRemark}`
                    : '')
                "
              />
              <!-- 采购注意事项：写给采购的，建采购单时按这一行的料带过去；
               给供应商的导出件里不会出现。 -->
              <Input
                v-model="row.purchaseNote"
                :style="colPos('purchaseNote')"
                placeholder="采购注意事项"
                :title="
                  row.purchaseNote ||
                  '写给采购看，如「只能用村田」：指定品牌、能否用替代料、到货节点等。不会出现在发给供应商的采购单上。'
                "
              />
              <!-- 生产备注：只给公司内部生产部门看，不进任何对外单据。 -->
              <Input
                v-model="row.productionNote"
                :style="colPos('productionNote')"
                placeholder="生产备注"
                :title="
                  row.productionNote ||
                  '只给公司内部生产部门看，如「装壳前理排线」。不进任何对外单据。'
                "
              />
              <!-- 卡点：选了就在订单上汇总显示「N 项等业务文件 · 已卡 X 天」，
                   让别人一眼看出这张单卡在谁手里，不是采购在拖。 -->
              <div
                :style="colPos('blocker')"
                class="flex items-center gap-1 min-w-0"
              >
                <SelectCard
                  size="form"
                  :model-value="row.blockerKind"
                  :options="BLOCKER_OPTIONS"
                  class="flex-1 min-w-0"
                  @update:model-value="v => (row.blockerKind = v)"
                />
                <Input
                  v-if="row.blockerKind"
                  v-model="row.blockerNote"
                  placeholder="说明"
                  class="flex-1 min-w-0"
                  :title="
                    row.blockerNote || '卡点说明，如「印刷文件业务还没发」'
                  "
                />
              </div>
              <button
                type="button"
                :style="colPos('del')"
                class="text-n-slate-10 hover:text-n-ruby-11"
                @click="removeRow(i)"
              >
                ✕
              </button>
            </div>
          </div>
        </div>

        <div class="flex flex-col gap-1 pt-2 border-t border-n-weak">
          <label class="text-heading-3 text-n-slate-12">整单备注</label>
          <TextArea
            v-model="form.remark"
            placeholder="整份生产任务单的说明（不同于每行的备注）"
            :max-length="500"
            auto-height
          />
        </div>

        <!-- 结构图 / 样品图（选择即上传） -->
        <div class="flex flex-col gap-2 pt-2 border-t border-n-weak">
          <label class="text-heading-3 text-n-slate-12">
            结构图 / 样品图
            <span v-if="staging" class="ml-1 text-xs text-n-amber-11">
              上传中…
            </span>
          </label>
          <div class="flex flex-wrap items-center gap-2">
            <div
              v-for="img in existingImages"
              :key="`ex-${img.id}`"
              class="relative w-20 h-20 group"
            >
              <a :href="img.url" target="_blank" rel="noopener noreferrer">
                <img
                  :src="img.url"
                  :alt="img.filename"
                  class="object-contain w-20 h-20 border rounded-lg border-n-weak bg-n-alpha-1"
                />
              </a>
              <button
                type="button"
                class="absolute items-center justify-center hidden w-5 h-5 text-xs text-white rounded-full top-1 right-1 bg-n-slate-12/70 group-hover:flex"
                @click="removeExisting('images', img)"
              >
                ✕
              </button>
            </div>
            <div
              v-for="(f, i) in pendingImages"
              :key="`pn-${i}`"
              class="relative w-20 h-20 group"
            >
              <img
                :src="f.previewUrl"
                class="object-contain w-20 h-20 border rounded-lg border-n-weak bg-n-alpha-1"
              />
              <button
                type="button"
                class="absolute items-center justify-center hidden w-5 h-5 text-xs text-white rounded-full top-1 right-1 bg-n-slate-12/70 group-hover:flex"
                @click="removePending('images', i)"
              >
                ✕
              </button>
            </div>
            <label
              class="flex items-center justify-center w-20 h-20 border border-dashed rounded-lg cursor-pointer text-label-small border-n-weak text-n-slate-11 hover:text-n-slate-12"
            >
              + 图片
              <input
                type="file"
                accept="image/*"
                multiple
                class="hidden"
                @change="e => pickAttachment(e, 'images')"
              />
            </label>
          </div>
        </div>

        <!-- 附件（工艺文档/图纸等） -->
        <div class="flex flex-col gap-2 pt-2 border-t border-n-weak">
          <label class="text-heading-3 text-n-slate-12">附件</label>
          <div class="flex flex-col gap-1">
            <div
              v-for="f in existingFiles"
              :key="`exf-${f.id}`"
              class="flex items-center justify-between text-xs"
            >
              <a
                :href="f.url"
                target="_blank"
                rel="noopener noreferrer"
                class="truncate text-n-iris-11 hover:underline"
              >
                {{ f.filename }}
              </a>
              <button
                type="button"
                class="ml-2 text-n-slate-10 hover:text-n-ruby-11"
                @click="removeExisting('files', f)"
              >
                ✕
              </button>
            </div>
            <div
              v-for="(f, i) in pendingFiles"
              :key="`pnf-${i}`"
              class="flex items-center justify-between text-xs"
            >
              <span class="truncate text-n-slate-12">{{ f.name }}</span>
              <button
                type="button"
                class="ml-2 text-n-slate-10 hover:text-n-ruby-11"
                @click="removePending('files', i)"
              >
                ✕
              </button>
            </div>
            <label
              class="cursor-pointer text-label-small text-n-iris-11 hover:underline w-max"
            >
              + 上传附件
              <input
                type="file"
                multiple
                class="hidden"
                @change="e => pickAttachment(e, 'files')"
              />
            </label>
          </div>
        </div>
      </div>

      <!-- 已下发 BOM 改用料：填变更原因，保存后自动记变更史并通知相关部门 -->
      <div
        v-if="editingId && editingStatus === 'RELEASED'"
        class="flex flex-col gap-1 p-3 mt-1 border rounded-xl border-n-amber-6 bg-n-amber-2"
      >
        <label class="text-label text-n-slate-12"> 变更原因（选填） </label>
        <textarea
          v-model="changeReason"
          rows="2"
          class="px-3 py-2 text-sm border rounded-lg resize-none reset-base border-white/70 bg-n-solid-1/70 text-n-slate-12"
        />
      </div>
    </div>

    <!-- BOM 模版管理：套用 / 删除 -->
    <Dialog
      ref="templateDialogRef"
      :dismissible="false"
      width="2xl"
      overflow-y-auto
      :show-confirm-button="false"
      show-cancel-button
      cancel-button-label="关闭"
      title="生产任务单模版"
    >
      <div class="flex flex-col gap-2">
        <p class="text-xs text-n-slate-11">
          套用模版会把用料明细与各阶段天数带入新建生产任务单，你只需再选成品即可保存。想新增模版？在新建/编辑生产任务单时点「存为模版」。
        </p>
        <div class="flex items-center gap-3">
          <div class="flex-1 min-w-0">
            <Input
              v-model="tplQuery"
              size="sm"
              placeholder="搜索模版名 / 产成品代码 / 投单单号"
            />
          </div>
          <span class="flex-shrink-0 text-xs text-n-slate-11">
            <template v-if="tplQuery.trim()">
              匹配 {{ filteredTemplates.length }} / {{ templates.length }} 份
            </template>
            <template v-else>共 {{ templates.length }} 份</template>
          </span>
        </div>
        <MesHiddenLineHint
          v-if="tplHiddenNoLine"
          :count="tplHiddenNoLine"
          unit="份"
        />
        <div v-if="tplFetching" class="py-8 text-center text-n-slate-11">
          加载中…
        </div>
        <div
          v-else-if="!templates.length"
          class="py-8 text-center text-n-slate-11"
        >
          还没有模版。
        </div>
        <div
          v-else-if="!filteredTemplates.length"
          class="py-8 text-center text-n-slate-11"
        >
          没有匹配「{{ tplQuery.trim() }}」的模版。
        </div>
        <div
          v-for="t in tplFetching ? [] : filteredTemplates"
          :key="t.id"
          class="flex items-center justify-between gap-3 px-3 py-2 border rounded-lg border-n-weak"
        >
          <div class="flex flex-col min-w-0">
            <span class="font-medium truncate text-n-slate-12">{{
              t.name
            }}</span>
            <span class="text-xs text-n-slate-11">
              {{ (t.bomTemplateItems || []).length }} 项用料 · 基准
              {{ Number(t.baseQty) }} {{ t.unit
              }}<template v-if="productLineLabel(t.productLine)">
                · {{ productLineLabel(t.productLine) }}</template
              >
            </span>
          </div>
          <div class="flex items-center flex-shrink-0 gap-1">
            <template v-if="confirmingDeleteId === t.id">
              <Button
                label="确认删除"
                color="ruby"
                size="sm"
                :is-loading="tplDeletingId === t.id"
                @click="removeTemplate(t)"
              />
              <Button
                label="取消"
                variant="ghost"
                color="slate"
                size="sm"
                @click="confirmingDeleteId = null"
              />
            </template>
            <template v-else>
              <Button
                label="套用"
                color="iris"
                size="sm"
                @click="applyTemplate(t)"
              />
              <Button
                label="删除"
                variant="ghost"
                color="slate"
                size="sm"
                @click="confirmingDeleteId = t.id"
              />
            </template>
          </div>
        </div>
      </div>
    </Dialog>

    <!-- 存为模版：命名 -->
    <Dialog
      ref="saveTplDialogRef"
      :dismissible="false"
      width="sm"
      title="存为模版"
      confirm-button-label="保存模版"
      confirm-button-color="iris"
      :is-loading="tplSaving"
      :disable-confirm-button="!templateName.trim()"
      @confirm="saveTemplate"
    >
      <div class="flex flex-col gap-1">
        <label class="text-heading-3 text-n-slate-12">模版名称</label>
        <Input v-model="templateName" @keyup.enter="saveTemplate" />
        <span class="text-xs text-n-slate-11"
          >将保存当前
          {{ form.rows.length }} 行用料与各阶段天数（不含成品）。</span
        >
      </div>
    </Dialog>
    <!-- 批量粘贴代码：从电子投单单复制一整列编码贴进来，一次匹配进明细 -->
    <Dialog
      ref="pasteDialogRef"
      :dismissible="false"
      width="3xl"
      overflow-y-auto
      title="批量粘贴代码"
      description="从电子投单单复制一整列商品编码贴进来，一行一个；带用量的写成「编码 用量」或从 Excel 直接复制两列。"
      :show-confirm-button="pasteRows.length > 0"
      :confirm-button-label="`填入 ${pasteRows.length} 行`"
      confirm-button-color="iris"
      @confirm="applyPaste"
    >
      <div class="flex flex-col gap-3">
        <TextArea
          v-model="pasteText"
          :rows="8"
          placeholder="P.01.033&#10;P.03.200&#10;P.04.809	1000"
        />
        <div class="flex items-center gap-2">
          <Button
            label="匹配产品档案"
            color="slate"
            size="sm"
            :is-loading="pasteBusy"
            @click="previewPaste"
          />
          <span v-if="pasteRows.length" class="text-xs text-n-slate-11">
            共 {{ pasteRows.length }} 行，匹配上 {{ pasteMatched }} 行
          </span>
        </div>
        <div v-if="pasteRows.length" class="overflow-y-auto max-h-80">
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left text-n-slate-11 border-b border-n-weak">
                <th class="w-10 px-2 py-2 font-medium whitespace-nowrap">#</th>
                <th class="px-2 py-2 font-medium whitespace-nowrap">
                  粘贴的编码
                </th>
                <th class="px-2 py-2 font-medium whitespace-nowrap">匹配到</th>
                <th class="px-2 py-2 font-medium text-right whitespace-nowrap">
                  用量
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(r, i) in pasteRows"
                :key="i"
                class="border-b border-n-weak"
              >
                <td class="px-2 py-1.5 tabular-nums text-n-slate-10">
                  {{ i + 1 }}
                </td>
                <td class="px-2 py-1.5 text-n-slate-12">{{ r.code }}</td>
                <td class="px-2 py-1.5">
                  <span v-if="r.product" class="text-n-slate-12">
                    {{ r.product.sku }} · {{ r.product.name }}
                  </span>
                  <span v-else class="text-n-ruby-11">未匹配，需手动选料</span>
                </td>
                <td class="px-2 py-1.5 text-right text-n-slate-11">
                  {{ r.qty || '—' }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </Dialog>

    <!-- 离开页面前的未保存提醒（整页没有弹窗的关闭入口，这里自己兜一道） -->
    <Dialog
      ref="leaveDialogRef"
      :dismissible="false"
      width="sm"
      :show-confirm-button="false"
      :show-cancel-button="false"
      :title="$t('DIALOG.UNSAVED.TITLE')"
    >
      <p class="mb-0 text-sm text-n-slate-11">
        {{ $t('DIALOG.UNSAVED.DESCRIPTION') }}
      </p>
      <template #footer>
        <div class="flex justify-end w-full gap-2">
          <Button
            :label="$t('DIALOG.UNSAVED.KEEP_EDITING')"
            variant="faded"
            color="slate"
            @click="cancelLeave"
          />
          <Button
            :label="$t('DIALOG.UNSAVED.DISCARD')"
            variant="outline"
            color="ruby"
            @click="confirmLeave"
          />
          <Button
            :label="editingStatus === 'RELEASED' ? '保存修改' : '存草稿'"
            color="iris"
            :is-loading="saving"
            :disabled="invalid"
            @click="saveThenLeave"
          />
        </div>
      </template>
    </Dialog>
  </div>
</template>
