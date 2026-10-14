<script setup>
// 建档页不进 keep-alive（见 MesLayout 的 INTAKE_PAGES）：表单页被缓存就会留着
// 上一单的内容，再点别的单进来是旧数据。名字要显式声明，keep-alive 的 exclude 按名字匹配。
defineOptions({ name: 'MesPurchaseOrderIntakeIndex' });
/* global axios */
import { ref, computed, reactive, onMounted, onActivated, watch } from 'vue';
import { useRoute, useRouter, onBeforeRouteLeave } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesPurchaseOrdersStore } from 'dashboard/stores/mes/purchaseOrders';
import { useMesSuppliersStore } from 'dashboard/stores/mes/suppliers';
import MesPurchaseOrderAPI from 'dashboard/api/mes/purchaseOrders';
import camelcaseKeys from 'camelcase-keys';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import { useMesProductLine } from 'dashboard/composables/useMesProductLine';
import { useMesTabs } from 'dashboard/composables/useMesTabs';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import MesProductPicker from 'dashboard/components-next/mes/MesProductPicker.vue';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';
import { orderSearchText } from 'dashboard/routes/dashboard/mes/orderSearchText';
import MesStatusPill from 'dashboard/components-next/mes/MesStatusPill.vue';
import MesImageLightbox from 'dashboard/components-next/mes/MesImageLightbox.vue';

const { accountId, accountScopedRoute } = useAccount();
// 标签条：守卫要靠它区分「切标签」和「关标签」。
const { tabs } = useMesTabs();
const router = useRouter();

// 回列表。leaving 是离开拦截的放行开关：保存成功、或用户选了「不保存」之后置 true。
const backToList = () =>
  router.push(accountScopedRoute('mes_purchase_orders_index'));
let leaving = false;
const route = useRoute();
const store = useMesPurchaseOrdersStore();
const suppliersStore = useMesSuppliersStore();
const currentUserId = useMapGetter('getCurrentUserID');

const saving = computed(
  () => store.getUIFlags.creatingItem || store.getUIFlags.updatingItem
);

// 搜索：单号 / 供应商 / 归属人 / 生产订单 / 物料编码（后端跨字段 ILIKE）。
// 从站内通知「待审批采购」跳来时按生产订单号定位（route.query.q）。
const search = ref(route.query.q ? String(route.query.q) : '');
// 「只看我下的单」：按下单人(采购单 owner_id)筛，不是列表里的「归属人」（那是生产订单的业务员）。
// 两个采购员分主料/辅料建单，各自只想看自己那摊。
const onlyMine = ref(false);
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

const STATUS_LABELS = {
  DRAFT: '草稿',
  SUBMITTED: '已下单',
  PARTIAL_RECEIVED: '部分到货',
  RECEIVED: '已到货',
  CANCELLED: '已取消',
};

// 按供应商拆单导出 PDF：后端用公司原始 .xlsx 模板 1:1 填充（含公章，抬头/税口径按各自 bill_entity）
// → Gotenberg 转 PDF。单个供应商直接下 PDF；多个供应商打包 zip（每家一份 PDF）。

const productionOrders = ref([]);
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

const editingId = ref(null);
const removedItemIds = ref([]);
// 明细行：物料/成品统一从产品档案选（crmProductId）；供应商、含税/未税、实际到料时间都在行上。
const blankRow = () => ({
  itemType: 'MATERIAL',
  crmProductId: '',
  // 老单的行可能挂的是**物料档案**（mes_material_id）而不是产品档案：BOM 算料铺出来的料
  // 对不上产品档案时就是这样存的。编辑时必须原样带回去，否则这一行的料会被清掉。
  mesMaterialId: '',
  materialLabel: '', // 物料档案行的显示名（只读，产品档案里找不到它）
  lastPriceText: '', // 「上次 ¥21.00 · PU2609005」，只提示不参与提交
  mesSupplierId: '',
  arrivalDate: '',
  qty: '1',
  rate: '',
  amount: '', // 行金额：跟数量/单价双向联动（有的物料是报「多少数量多少钱」）
  orderedQty: 0, // 本单这个料已经下出去的量（算料时带出，用来只铺剩余量）
  priceTaxIncluded: false,
  suggestedQty: null, // 工程建议采购量（生产任务单算料带出，只读参考）
  auxAttributeName: '', // 辅助属性（算料时从任务单那行带出；导出给供应商的单子要印）
  remark: '',
  // 行内附图（只对内）：[{ signedId, url, name, id? }]。id 有值＝服务端已存的，
  // 没有＝本次刚传、还没保存。提交时整组回传 signedId，后端按这份列表替换。
  images: [],
});
// 产线：关联生产订单时从订单继承（Mes::PurchaseOrder#product_line_source），
// 独立的成品采购单没有父级，必须在表单里选，否则建完切到任何产线都看不见。
const { activeProductLine, formOptions: productLineOptions } =
  useMesProductLine();

const form = reactive({
  poNo: '', // 留空＝自动生成；两账并行期可填金蝶的号（仅新建可填）
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
const { isDirty, markPristine } = useDirtyGuard(() => form);

// 已经走过采购阶段、或已完结/取消的单不再出现在候选里——采购员反馈这些单
// 还挂在下拉里，每次都要从一长串里挑，容易给已经买完的单重复下单。
// 注意：**没有**按「有没有采购单」来筛——一张生产订单本来就可以开多张采购单
// （主料/辅料各一张、不同采购员各建），按那个筛会把正常用法堵死。
const DONE_PURCHASING_STAGES = [
  'MATERIAL_INBOUND',
  'PICKING',
  'PRODUCTION',
  'FG_INBOUND',
  'SHIPPED',
];
// 料已经全下满采购单的也不列（后端 purchasing_complete 按 BOM 需求量 vs 已下量算）。
// 否则选中了才弹「这张订单的料都已经下过采购单了」——该让它压根不出现在候选里。
const isSelectableOrder = p =>
  p.status === 'IN_PROGRESS' &&
  !DONE_PURCHASING_STAGES.includes(p.stage) &&
  !p.purchasing_complete;
const selectableOrders = computed(() =>
  productionOrders.value.filter(
    p =>
      // 编辑时本单已挂的那张要留着，否则下拉里显示不出当前值
      String(p.id) === String(form.productionOrderId) || isSelectableOrder(p)
  )
);
// 下拉右侧标注「这张单下过采购单没有」：料全下满的已经不显示了，但下了一部分的还得列出来
// （一单允许多张采购单，主料辅料分开买），看不出下过没有就容易重复下单。
const purchaseNote = p => {
  const ov = p.purchase_overview;
  if (!ov) return '';
  if (ov.no_bom) return '未挂生产任务单';
  if (!ov.po_count) return '还没下过采购单';
  const short = ov.short_lines ? ` · 还差 ${ov.short_lines} 项料` : '';
  return `已下 ${ov.po_count} 张采购单${short}`;
};
const productionOrderOptions = computed(() => [
  { value: '', label: '不关联销售订单' },
  ...selectableOrders.value.map(p => ({
    value: String(p.id),
    label: `${p.order_no} · ${p.product_name}`,
    note: purchaseNote(p),
    searchText: orderSearchText(p),
  })),
]);

// 「再关联一张」的候选：排掉主单和已挂过的，选完即追加，避免重复挂同一张。
const extraOrderOptions = computed(() => [
  { value: '', label: '选一张追加…' },
  ...productionOrders.value
    .filter(
      p =>
        String(p.id) !== String(form.productionOrderId) &&
        !form.extraProductionOrderIds.includes(String(p.id)) &&
        !p.purchasing_complete
    )
    .map(p => ({
      value: String(p.id),
      label: `${p.order_no} · ${p.product_name}`,
      note: purchaseNote(p),
    })),
]);
const orderLabel = id => {
  const hit = productionOrders.value.find(p => String(p.id) === String(id));
  return hit ? `${hit.order_no} · ${hit.product_name}` : `#${id}`;
};

// 生产任务单上逐行的「采购注意事项」：工程/PMC 针对某个料写给采购的
// （这颗只能用村田、这个壳要 20 号前到…）。只读展示、按关联订单实时取，
// **不写进采购单字段**——抄一份就会跟任务单改动脱节，而且抄进来的东西
// 迟早跟着导出件发给供应商。
const purchaseNotes = ref([]);
const loadPurchaseNotes = async () => {
  const ids = [form.productionOrderId, ...form.extraProductionOrderIds].filter(
    Boolean
  );
  if (!ids.length) {
    purchaseNotes.value = [];
    return;
  }
  const lists = await Promise.all(
    ids.map(id =>
      MesPurchaseOrderAPI.requirement(id)
        .then(({ data }) => ({ id, rows: data?.payload || [] }))
        .catch(() => ({ id, rows: [] }))
    )
  );
  purchaseNotes.value = lists.flatMap(({ id, rows }) =>
    rows
      .filter(r => r.purchase_note)
      .map(r => ({
        key: `${id}-${r.material_no || r.crm_product_id}`,
        order: orderLabel(id),
        material: [r.material_no, r.material_name].filter(Boolean).join(' '),
        note: r.purchase_note,
      }))
  );
};
watch(
  () => [form.productionOrderId, form.extraProductionOrderIds.join(',')],
  loadPurchaseNotes,
  { immediate: true }
);
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
    useAlert('先关联销售订单');
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

// 一行算填好了：有数量，且选了料——产品档案或物料档案任一即可。
// 原来只认产品档案，于是挂物料档案的老单一打开整张表单就恒为无效、保存按钮永远是灰的，
// 删行点保存毫无反应（用户反馈「点了X，再进去还在，怎么都删不掉」的真正原因）。
const rowIncomplete = r =>
  !Number(r.qty) || (!r.crmProductId && !r.mesMaterialId);
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

// 点中的那一行高亮：几十行明细对着纸质单核的时候，没有焦点行容易串行。
// 只是视觉焦点，不参与任何提交。
const activeRow = ref(null);

// 沿用上面最近一个填了供应商的行——不只看紧挨着的上一行，
// 否则中间插一行空的，底下几行就没得抄了。
const supplierAbove = i => {
  for (let k = i - 1; k >= 0; k -= 1) {
    if (form.rows[k]?.mesSupplierId) return form.rows[k].mesSupplierId;
  }
  return '';
};

// 同料同供应商上次下单多少钱：选完料和供应商就问一次。
// 采购原话「不然谁都记不住那么多物料单价」。只认审批通过的单（后端口径，见 Mes::LastPurchasePrice）。
// 单价已经填了就不覆盖——她手上可能拿着新报价，自动改掉就成事故了，只在下面提示上次多少。
// 把上次那张单的供应商和单价填进这一行。
// 已经填了的不覆盖——她手上可能拿着新报价、或者这次就是要换一家做，
// 自动改掉就成事故了；只在下面提示上次是谁、多少钱。
const applyLastPrice = (row, hit) => {
  const yuan = Number(hit.rate_micros) / 1e6;
  row.lastPriceText = `上次 ¥${yuan.toFixed(2)}${
    hit.price_tax_included ? '（含税）' : ''
  }${hit.supplier_name ? ` · ${hit.supplier_name}` : ''}${
    hit.po_no ? ` · ${hit.po_no}` : ''
  }`;
  // 供应商下拉建单时一次拉满（per_page 500，现有 331 家），带回来的 id 必在选项里。
  if (!row.mesSupplierId && hit.mes_supplier_id) {
    row.mesSupplierId = String(hit.mes_supplier_id);
  }
  if (!row.rate) {
    row.rate = String(yuan);
    row.priceTaxIncluded = !!hit.price_tax_included;
    syncAmount(row);
  }
};

const fetchLastPrice = async row => {
  const material = row.mesMaterialId || '';
  const product = row.crmProductId || '';
  if (!material && !product) {
    row.lastPriceText = '';
    return;
  }
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/purchase_orders/last_price`,
      {
        params: {
          // 没选供应商就不传：后端会按最近一张已审核的单，把供应商一起带回来。
          mes_supplier_id: row.mesSupplierId || undefined,
          crm_product_id: product || undefined,
          mes_material_id: material || undefined,
        },
      }
    );
    const hit = data?.payload;
    if (!hit) {
      row.lastPriceText = '';
      return;
    }
    applyLastPrice(row, hit);
  } catch {
    row.lastPriceText = '';
  }
};

const copySupplierFromAbove = i => {
  const id = supplierAbove(i);
  if (!id) return;
  form.rows[i].mesSupplierId = id;
  fetchLastPrice(form.rows[i]);
};

const addRow = () => form.rows.push(blankRow());
const removeRow = i => {
  const [r] = form.rows.splice(i, 1);
  if (r?.id) removedItemIds.value.push(r.id);
};

// 从关联的生产订单 BOM 算料，覆盖当前明细行。
// category='' 全部 / 'MACHINE' 只主料(整机料) / 'PACKAGING' 只辅料(包装料)——两个采购员分料建单。
const explode = async (category = '') => {
  if (!form.productionOrderId) {
    useAlert('请先选销售订单');
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
        category
          ? '该类别（整机物料/包装物料）无用料'
          : '该销售订单未挂生产任务单或无用料'
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
      auxAttributeName: r.aux_attribute_name || '',
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
  markPristine();
};
// 从工程/PMC BOM 的「新建成品采购单」跳来：首行直接切成外购成品。
const openProductCreate = () => {
  resetForm();
  form.rows[0].itemType = 'PRODUCT';
  markPristine();
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
      mesMaterialId: it.mesMaterialId ? String(it.mesMaterialId) : '',
      materialLabel: it.crmProductId
        ? ''
        : [it.materialName, it.materialNo && `（${it.materialNo}）`]
            .filter(Boolean)
            .join(''),
      mesSupplierId: it.mesSupplierId ? String(it.mesSupplierId) : '',
      arrivalDate: it.arrivalDate ? it.arrivalDate.slice(0, 10) : '',
      qty: String(it.qty),
      rate: it.rateMicros ? String(it.rateMicros / 1e6) : '',
      amount: it.rateMicros
        ? String(Number(((it.rateMicros / 1e6) * Number(it.qty)).toFixed(2)))
        : '',
      priceTaxIncluded: !!it.priceTaxIncluded,
      auxAttributeName: it.auxAttributeName || '',
      remark: it.remark || '',
      images: (it.images || []).map(img => ({
        id: img.id,
        name: img.filename,
        url: img.url,
        signedId: img.signed_id,
      })),
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
  markPristine();
};

// —— 明细行内部附图 ——
// 只给公司内部看：这颗料的样品照 / 来料照 / 跟供应商确认的截图。
// 导出给供应商的采购订单和供应商预览页都只认固定那几列，不读这里，漏不出去。
// 选了就先上传拿 signed_id（这时单可能还不存在），随明细一起提交。
const stagingRow = ref(null); // 正在上传的行下标，给那一行显示「上传中…」
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
        return MesPurchaseOrderAPI.stageBlob(fd).then(({ data }) => ({
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
// 删除只改本地列表，保存时整组替换生效（没点保存就离开＝没删掉，和改数量一个语义）。
const removeRowImage = (row, i) => row.images.splice(i, 1);

// 作废本单。走普通 update 把 status 置 CANCELLED——后端 before_save 会把它从
// 生产订单的齐套判定里摘掉（purchase_complete? 只数未作废的单）。不可逆，所以先问一句。
const cancelling = ref(false);
const cancelOrder = async () => {
  if (!editingId.value) return;
  const msg = `作废采购单 ${form.poNo || ''}？作废后不参与齐套判定，且无法撤回。`;
  // eslint-disable-next-line no-alert
  if (!window.confirm(msg)) return;

  cancelling.value = true;
  try {
    const ok = await store.update({ id: editingId.value, status: 'CANCELLED' });
    if (ok) {
      useAlert('采购单已作废');
      markPristine();
      leaving = true;
      backToList();
    }
  } finally {
    cancelling.value = false;
  }
};

const submit = async () => {
  if (invalid.value) return;
  const itemsAttributes = [
    ...form.rows.map(r => ({
      id: r.id || undefined,
      itemType: r.itemType,
      // 两种料各送各的 id。原来写死 mesMaterialId: null + Number('')=0，
      // 挂物料档案的行一存就被清成「产品 0 号」。
      mesMaterialId: r.mesMaterialId ? Number(r.mesMaterialId) : null,
      crmProductId: r.crmProductId ? Number(r.crmProductId) : null,
      mesSupplierId: r.mesSupplierId ? Number(r.mesSupplierId) : null,
      arrivalDate: r.arrivalDate || null,
      unit: productUnit(r.crmProductId) || undefined,
      qty: Number(r.qty),
      rateMicros: r.rate ? Math.round(Number(r.rate) * 1e6) : null,
      priceTaxIncluded: r.priceTaxIncluded,
      auxAttributeName: r.auxAttributeName || null,
      remark: r.remark || '',
      // 整组替换：每次给这一行当前应有的完整列表，删掉的不在列表里就没了
      images: (r.images || []).map(img => img.signedId),
    })),
    ...removedItemIds.value.map(id => ({ id, _destroy: true })),
  ];
  const payload = {
    // 单号只在新建时随表单提交；编辑时后端也不收，防止改已生效单据的号。
    poNo: editingId.value ? undefined : form.poNo.trim() || undefined,
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
    markPristine();
    leaving = true; // 已保存，离开时不用再问
    backToList();
  }
};

// 页面模式的进入点：带 ?id= 是编辑，带 ?new=product 是从 BOM 页「新建成品采购单」跳来。
const booting = ref(true);
const boot = async () => {
  booting.value = true;
  // 供应商下拉需全量，默认分页只出第一页会漏选。
  suppliersStore.get({ per_page: 500 });
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/production_orders`,
      // 不传 per_page 后端只给最新 15 条,早的单子在下拉里选不到。
      // with_purchasing_complete：让后端顺带算「料是否已下满」，下拉据此剔掉下完的单。
      { params: { per_page: 500, with_purchasing_complete: 1 } }
    );
    productionOrders.value = data?.payload || [];
  } catch {
    productionOrders.value = [];
  }

  const editId = route.query.id;
  if (editId) {
    try {
      const { data } = await MesPurchaseOrderAPI.show(editId);
      // 接口原样返回下划线键；openEdit 按驼峰读（列表页的数据是 store 转过的）。
      // 不转的话多词字段会全读成 undefined，表单看着像只回填了一半。
      openEdit(camelcaseKeys(data?.payload || data || {}, { deep: true }));
    } catch {
      useAlert('这张采购单打不开，可能已被删除');
      backToList();
    }
  } else if (route.query.new === 'product') {
    openProductCreate();
  } else {
    openCreate();
    // 从生产订单详情「接单后去建采购单」跳来：直接把那张订单挂上，
    // 采购不用在一长串候选里再找一遍。
    const preOrderId = route.query.production_order_id;
    if (
      preOrderId &&
      selectableOrders.value.some(o => String(o.id) === String(preOrderId))
    ) {
      form.productionOrderId = String(preOrderId);
      markPristine();
    }
  }
  booting.value = false;
};
onMounted(boot);

// 本页在 MesLayout 的 keep-alive 里按 query 缓存：切去产品档案/供应商档案查完料
// 再切回来，填了一半的单子原样还在，不重跑 boot。但如果上次是「保存 / 作废 /
// 不保存」这类明确离开（leaving=true），缓存里那份已经没用了，重新进来要给张新单。
onActivated(() => {
  if (!leaving) return;
  leaving = false;
  boot();
});

// ── 离开页面前的未保存拦截 ──────────────────────────────────
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
  await submit();
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
  pendingLeave = () => next();
  leaveDialogRef.value?.open();
});
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <!-- 操作条冻结在顶部：一个供应商几十行料时不用滚到底才点得到保存（反馈 A45） -->
    <div
      class="sticky top-0 z-20 flex flex-wrap items-center justify-between flex-shrink-0 gap-2 px-4 py-3 border-b bg-n-solid-1/80 backdrop-blur-xl border-n-weak sm:px-6 sm:py-4 [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:sm:!px-8"
    >
      <h1
        class="text-lg font-medium min-w-0 truncate text-n-slate-12 sm:text-xl [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8"
      >
        {{ editingId ? '编辑采购单' : '新建采购单' }}
      </h1>
      <div class="flex flex-wrap items-center gap-2">
        <Button
          label="取消"
          variant="ghost"
          color="slate"
          size="sm"
          @click="requestLeave"
        />
        <!-- 作废：原先唯一的入口是状态下拉里的「已取消」，下拉改只读后要给它一条明路。
             作废后后端会把这张单从生产订单的齐套判定里摘出去（已作废的不参与）。 -->
        <Button
          v-if="editingId && form.status !== 'CANCELLED'"
          label="作废本单"
          variant="outline"
          color="ruby"
          size="sm"
          :is-loading="cancelling"
          @click="cancelOrder"
        />
        <Button
          label="保存"
          color="iris"
          size="sm"
          :is-loading="saving"
          :disabled="invalid"
          @click="submit"
        />
      </div>
    </div>

    <div class="flex flex-col w-full gap-4 px-4 py-4 sm:px-6 sm:py-5 [.theme-classic_&]:sm:!px-8">
      <div class="flex flex-col gap-4">
        <!-- 栅格排版：列宽由栅格统一分，控件一律撑满本列（SelectCard 默认按内容宽，
             不加 block 就会「列很宽、控件很窄」，一行看下来全是豁口）。 -->
        <div class="grid items-end gap-x-4 gap-y-3 sm:grid-cols-12">
          <!-- 单号留空＝自动生成；两账并行期可直接填金蝶的号。编辑态隐藏，改已生效单据的号会让下游全对不上。 -->
          <div v-if="!editingId" class="flex flex-col gap-1 sm:col-span-2">
            <label class="text-heading-3 text-n-slate-12">采购单号</label>
            <Input
              v-model="form.poNo"
              placeholder="留空自动生成"
              class="no-margin !h-9"
            />
          </div>
          <div class="flex flex-col gap-1 sm:col-span-2">
            <label class="text-heading-3 text-n-slate-12">
              产品线<span class="text-n-ruby-11">*</span>
            </label>
            <SelectCard
              block
              size="form"
              :model-value="form.productLine"
              :options="productLineOptions"
              @update:model-value="v => (form.productLine = v)"
            />
          </div>
          <div class="flex flex-col gap-1 sm:col-span-4">
            <label class="text-heading-3 text-n-slate-12">关联生产订单</label>
            <ComboBox
              :model-value="form.productionOrderId"
              :options="productionOrderOptions"
              placeholder="不关联销售订单"
              search-placeholder="搜 MO 号 / 产品 / 销售订单 / 客户"
              empty-state="没有匹配的生产订单"
              @update:model-value="v => (form.productionOrderId = v)"
            />
          </div>
          <!-- 同款物料多张生产订单在用时，一张采购单挂多张订单，只传一次给供应商。
               已选的订单标签不放这一列——整行是底部对齐，标签垫在下拉底下会把这一列
               的下拉顶上去，一行就歪了。标签挪到整行下面单独一排。 -->
          <div class="flex flex-col gap-1 sm:col-span-4">
            <label class="text-heading-3 whitespace-nowrap text-n-slate-12">
              追加关联订单（选填）
            </label>
            <SelectCard
              block
              size="form"
              model-value=""
              :options="extraOrderOptions"
              @update:model-value="addExtraOrder"
            />
          </div>
        </div>

        <!-- 算料动作跟说明同一排：它不是表单字段，挤进上面那行只会把列宽压乱 -->
        <div class="flex flex-wrap items-center justify-between gap-2 -mt-1">
          <p class="text-xs text-n-slate-10">
            一张生产订单可开多张采购单（如主料、辅料各一张，不同采购员各建各的）。
          </p>
          <div class="flex items-center gap-1 shrink-0">
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
              label="只算整机物料"
              type="button"
              variant="outline"
              color="slate"
              size="sm"
              @click="explode('MACHINE')"
            />
            <Button
              label="只算包装物料"
              type="button"
              variant="outline"
              color="slate"
              size="sm"
              @click="explode('PACKAGING')"
            />
          </div>
        </div>
        <!-- 已追加的订单：单独一排，长单号不会把上面那行挤歪 -->
        <div
          v-if="form.extraProductionOrderIds.length"
          class="flex flex-wrap items-center gap-1 -mt-2"
        >
          <span class="text-label-small text-n-slate-11">已追加：</span>
          <span
            v-for="id in form.extraProductionOrderIds"
            :key="id"
            class="inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded-md whitespace-nowrap bg-n-iris-3 text-n-iris-11"
          >
            {{ orderLabel(id) }}
            <button
              type="button"
              class="i-lucide-x size-3 hover:opacity-70"
              @click="removeExtraOrder(id)"
            />
          </span>
        </div>

        <!-- 第二行沿用同一套栅格，列边跟上一行对齐 -->
        <div class="grid items-start gap-x-4 gap-y-3 sm:grid-cols-12">
          <!-- 收货状态是**算出来的**，不是选出来的：原料入库单一过账，后端按
               「已到料量 vs 订购量」自动改成 部分到货 / 已到货（见
               Mes::PurchaseOrder#recompute_receipt_status!）。以前这里放了个下拉，
               采购员以为自己得选对才能往下走（实际留在草稿完全不影响审批、导出、
               收货和齐套），反而把人搞糊涂了。改成只读显示；要作废走右上角按钮。 -->
          <div class="flex flex-col gap-1 sm:col-span-2">
            <label class="text-heading-3 text-n-slate-12">收货状态</label>
            <div class="flex items-center h-9">
              <MesStatusPill :label="STATUS_LABELS[form.status]" />
            </div>
            <span class="text-xs text-n-slate-10">收货后自动更新</span>
          </div>
          <div class="flex flex-col gap-1 sm:col-span-2">
            <label class="text-heading-3 text-n-slate-12">回复采购时间</label>
            <DatePicker v-model="form.expectedDate" block />
          </div>
          <div class="flex flex-col gap-1 sm:col-span-2">
            <label class="text-heading-3 text-n-slate-12">交货时间</label>
            <DatePicker v-model="form.deliveryDate" block />
            <span class="text-xs text-n-slate-10">
              导出合同"三、交货时间"用
            </span>
          </div>
        </div>

        <!-- 生产任务单带过来的采购注意事项：只读，不进导出件 -->
        <div v-if="purchaseNotes.length" class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">
            采购注意事项（来自生产任务单）
          </label>
          <div
            class="flex flex-col gap-2 p-3 border rounded-lg border-n-amber-6 bg-n-amber-3"
          >
            <div v-for="n in purchaseNotes" :key="n.key" class="flex flex-col">
              <span class="text-label-small text-n-slate-11">
                {{ n.material }} · {{ n.order }}
              </span>
              <p class="text-sm whitespace-pre-wrap text-n-slate-12">
                {{ n.note }}
              </p>
            </div>
          </div>
          <span class="text-xs text-n-slate-10">
            工程 / PMC 写给采购看的，不会出现在发给供应商的采购订单上
          </span>
        </div>

        <!-- 公司内部备注：只在系统里看，导出给供应商的采购订单上不会出现 -->
        <div class="flex flex-col gap-1">
          <div class="flex items-center gap-3">
            <label class="text-heading-3 text-n-slate-12">公司内部备注</label>
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
          />
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
          <span class="text-heading-2 text-n-slate-12">
            采购明细 <span class="text-n-ruby-11">*</span>
          </span>
          <Button
            label="+ 加一行"
            type="button"
            variant="ghost"
            size="sm"
            @click="addRow"
          />
        </div>
        <!-- 「全部含税」是一次勾上下面每行的「单价含税」，所以压在那一列正上方；
             放回标题栏跟「+ 加一行」并排会把开关和动作混在一起。 -->
        <label
          v-if="form.rows.length"
          class="flex items-center gap-1.5 -mt-1 text-xs cursor-pointer w-max text-n-slate-11"
          title="一次勾上/取消下面每一行的「单价含税」"
        >
          <input
            type="checkbox"
            :checked="allTaxIncluded"
            :indeterminate.prop="someTaxIncluded"
            @change="toggleAllTaxIncluded"
          />
          全部含税
        </label>
        <div class="flex flex-col gap-2.5">
          <div
            v-for="(row, i) in form.rows"
            :key="i"
            class="flex flex-col gap-2.5 p-3 border rounded-lg"
            :class="
              activeRow === i
                ? 'border-n-iris-8 bg-n-iris-3'
                : 'border-n-weak hover:border-n-slate-6'
            "
            @click="activeRow = i"
          >
            <!-- 主控件行：序号 / 类型 / 物料 / 供应商 / 数量 / 单价 / 删除
                 序号：一个供应商常要下好几行料，没有行号对不上纸质单。 -->
            <div
              class="grid items-center grid-cols-1 gap-2 md:grid-cols-[28px_1.6fr_3fr_2fr_1.2fr_1.6fr_1.6fr_24px]"
            >
              <span
                class="text-xs tabular-nums text-n-slate-10 md:text-center"
                :class="activeRow === i ? 'font-semibold text-n-iris-11' : ''"
              >
                {{ i + 1 }}
              </span>
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
                  :display-text="
                    productLabel(row.crmProductId) || row.materialLabel
                  "
                  placeholder="选择物料（产品档案·编码/名称/规格）"
                  @update:model-value="
                    v => {
                      row.crmProductId = v;
                      // 改选产品档案即顶掉原来的物料档案，一行只认一个料
                      if (v) {
                        row.mesMaterialId = '';
                        row.materialLabel = '';
                      }
                      fetchLastPrice(row);
                    }
                  "
                  @select="onProductPicked"
                />
              </div>
              <div class="flex items-center gap-1 min-w-0">
                <ComboBox
                  :model-value="row.mesSupplierId"
                  :options="supplierOptions"
                  placeholder="选择供应商"
                  class="flex-1 min-w-0"
                  @update:model-value="
                    v => {
                      row.mesSupplierId = v;
                      fetchLastPrice(row);
                    }
                  "
                />
                <!-- 同上：一个供应商常要下好几行料，逐行重选太慢 -->
                <button
                  v-if="supplierAbove(i)"
                  type="button"
                  class="px-1.5 h-7 text-xs rounded shrink-0 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-iris-11"
                  title="沿用上一行的供应商"
                  @click.stop="copySupplierFromAbove(i)"
                >
                  同上
                </button>
              </div>
              <Input
                :model-value="row.qty"
                type="number"
                placeholder="数量"
                @update:model-value="v => setRowQty(row, v)"
              />
              <div class="flex flex-col gap-0.5 min-w-0">
                <Input
                  :model-value="row.rate"
                  type="number"
                  :placeholder="row.priceTaxIncluded ? '含税单价' : '未税单价'"
                  @update:model-value="v => setRowRate(row, v)"
                />
                <!-- 上次这家供应商这颗料多少钱。单价空着就直接填进去，已填只提示不覆盖。 -->
                <span
                  v-if="row.lastPriceText"
                  class="text-[11px] leading-tight truncate text-n-slate-10"
                  :title="row.lastPriceText"
                >
                  {{ row.lastPriceText }}
                </span>
              </div>
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
            <!-- 次要控件行：含税 / 实际到料 / 备注 / 行内附图。
                 附图占右端 3 格，缩略图直接摆在这儿（不另起一排）；其余三项各收到 3 格
                 给它让位。以前图标躲在行尾 24px 里、缩略图另起一排在左下，一行拆成两处看。 -->
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
              <div class="flex items-center gap-2 md:col-span-3">
                <label class="text-heading-3 shrink-0 text-n-slate-12"
                  >实际到料</label
                >
                <div class="flex-1">
                  <DatePicker v-model="row.arrivalDate" block />
                </div>
              </div>
              <Input
                v-model="row.remark"
                placeholder="备注"
                class="md:col-span-3"
              />
              <!-- 行内附图（只对内）：缩略图 + 加图按钮，一起靠右。
                   不会出现在发给供应商的采购订单/预览页上（那两处只渲染固定几列）。 -->
              <div
                class="flex flex-wrap items-center justify-end gap-1.5 md:col-span-3"
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
                    title="移除这张图（保存后生效）"
                    @click="removeRowImage(row, k)"
                  >
                    <span class="i-lucide-x size-2.5" />
                  </button>
                </div>
                <span v-if="stagingRow === i" class="text-xs text-n-amber-11">
                  上传中…
                </span>
                <label
                  class="inline-flex items-center justify-center border border-dashed rounded cursor-pointer size-9 shrink-0 border-n-weak text-n-slate-10 hover:text-n-slate-12 hover:border-n-slate-8"
                  title="加附图（只公司内部看，不会出现在发给供应商的采购订单上）"
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
    </div>

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
            label="保存"
            color="iris"
            :is-loading="saving"
            :disabled="invalid"
            @click="saveThenLeave"
          />
        </div>
      </template>
    </Dialog>

    <!-- 看图层：就地渲染，跟弹窗一起在顶层，点缩略图放大看 -->
    <MesImageLightbox ref="lightboxRef" />
  </div>
</template>
