<script setup>
import { ref, computed, onMounted, reactive, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import camelcaseKeys from 'camelcase-keys';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCrmRole } from 'dashboard/composables/useCrmRole';
import { toPng } from 'html-to-image';
import { printElement } from 'dashboard/helper/printHelper';
import CommissionSheetsAPI from 'dashboard/api/crm/commissionSheets';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import CrmForwardToTeamChatDialog from 'dashboard/components-next/CRM/CrmForwardToTeamChatDialog.vue';
import { fmtYuan } from 'dashboard/helper/crmMoney';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { accountId } = useAccount();
const { currentUser, isAdmin, isCrmDeputyAdmin, isCrmManager, isCrmFinance } =
  useCrmRole();

const sheet = ref(null);
const items = ref([]);
const rateMap = ref({}); // 品类 => 提成点(百分数)，用于逐行算提成基数/工资
const deleted = ref([]); // 已删除的既有行 id
const isLoading = ref(true);
const isBusy = ref(false);
const captureRef = ref(null); // 只读表容器，导出图片时截取

// 产品品类统一为两类，下拉固定选择，保证与提成点配置匹配。
const PRODUCT_CATEGORIES = ['平板电脑', '商显工控'];
const CURRENCIES = ['USD', 'CNY', 'EUR'];
// 对公可选税点（每行手选）。
const TAX_RATES = [13, 11];
// 关联销售订单状态 → 中文（与销售订单列表口径一致，只读展示）。
const ORDER_STATUS_LABEL = {
  PENDING_CONFIRMATION: '待确认',
  IN_PRODUCTION: '生产中',
  PENDING_SHIPMENT: '待出货',
  SHIPPED: '已出货',
  COMPLETED: '已完成',
  CANCELLED: '已取消',
};
const orderStatusText = s => ORDER_STATUS_LABEL[s] || '';
const yuanFromMicros = m =>
  m == null ? null : Math.round((m / 1_000_000) * 100) / 100;
const microsFromYuan = y =>
  y === '' || y == null || Number.isNaN(Number(y))
    ? null
    : Math.round(Number(y) * 1_000_000);
const dateOnly = v => (v ? String(v).slice(0, 10) : '');

const toLocal = it => ({
  id: it.id,
  position: it.position,
  productCategory: it.productCategory || '',
  country: it.country || '',
  customerName: it.customerName || '',
  orderNo: it.orderNo || '',
  crmSalesOrderId: it.crmSalesOrderId || null,
  orderAmount: yuanFromMicros(it.orderAmountMicros),
  currency: it.currency || 'USD',
  shipping: yuanFromMicros(it.shippingMicros),
  forwarderShipping: yuanFromMicros(it.forwarderShippingMicros),
  receivedAmount: yuanFromMicros(it.receivedAmountMicros),
  exchangeRate: it.exchangeRate != null ? Number(it.exchangeRate) : null,
  receivedRmb: yuanFromMicros(it.receivedRmbMicros),
  salesRmb: yuanFromMicros(it.salesRmbMicros),
  paymentChannel: it.paymentChannel || '',
  paymentDate: dateOnly(it.paymentDate),
  product: it.product || '',
  remark: it.remark || '',
  isPublicReceipt: !!it.isPublicReceipt,
  taxRate: it.taxRate ?? 13,
  orderStatus: it.orderStatus || '',
});

const applySheet = data => {
  const s = camelcaseKeys(data, { deep: true });
  sheet.value = s;
  items.value = (s.items || []).map(toLocal);
  // 品类名（中文）不走驼峰转换，直接用原始 map，避免键被改写。
  rateMap.value = data.commission_rates || {};
  deleted.value = [];
};

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await CommissionSheetsAPI.get(
      accountId.value,
      route.query.id
    );
    applySheet(data);
  } catch (e) {
    useAlert(e?.response?.data?.error || t('CRM.COMMISSION.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};
onMounted(load);

// ── 角色 / 状态 → 可做的操作 ──
const status = computed(() => sheet.value?.status);
const isOwner = computed(() => sheet.value?.ownerId === currentUser.value?.id);
// 财务复核时手动进入编辑（默认只读+可导出，点「编辑」才改，存完回只读）。
const financeEditing = ref(false);
// 常规草稿工作流可编辑：草稿/退回态 + 本人/管理员/副管。
const draftEditable = computed(
  () =>
    ['DRAFT', 'RETURNED'].includes(status.value) &&
    (isOwner.value || isAdmin.value || isCrmDeputyAdmin.value)
);
// 「可改单元格」态：常规草稿可编辑，或财务主动进入编辑（任意状态，含已通过，补汇率复核用）。
const editable = computed(
  () => draftEditable.value || (isCrmFinance.value && financeEditing.value)
);
// 财务「编辑」入口：已通过表且当前未在编辑时露出。
const canFinanceEdit = computed(
  () => isCrmFinance.value && status.value === 'APPROVED' && !editable.value
);
// 拉单/导单仅常规草稿工作流可用（财务补汇率不涉及）。
const canPullImport = computed(() => draftEditable.value);
const canSubmit = computed(
  () => draftEditable.value && (isOwner.value || isAdmin.value)
);
const canApprove = computed(
  () =>
    status.value === 'SUBMITTED' &&
    (isAdmin.value ||
      isCrmDeputyAdmin.value ||
      (isCrmManager.value && !isOwner.value))
);
const canExport = computed(
  () =>
    status.value === 'APPROVED' &&
    (isCrmFinance.value || isOwner.value || isAdmin.value)
);
// 财务发放：仅已通过表可标记已发放。
const canMarkPaid = computed(
  () => isCrmFinance.value && status.value === 'APPROVED'
);
// 财务/管理层退回：已通过但未发放时，核算发现有误可打回业务员重填（重走 提交→审批→发放）。
// 口径与后端 can_return? 对齐：管理员 / 副管理员 / 财务均可（isCrmFinance 已含管理员+财务，另补副管理员）。
const canFinanceReturn = computed(
  () =>
    (isCrmFinance.value || isCrmDeputyAdmin.value) &&
    status.value === 'APPROVED' &&
    !sheet.value?.paidAt
);

const title = computed(() => {
  if (!sheet.value) return t('CRM.COMMISSION.HEADER');
  const d = new Date(sheet.value.periodMonth);
  return `${sheet.value.ownerName || ''} · ${t('CRM.COMMISSION.DETAIL.MONTH_LABEL', { year: d.getFullYear(), month: d.getMonth() + 1 })}`;
});

// ── 编辑 ──
const addRow = () =>
  items.value.push(
    reactive({
      id: null,
      productCategory: '',
      country: '',
      customerName: '',
      orderNo: '',
      crmSalesOrderId: null,
      orderAmount: null,
      currency: 'USD',
      shipping: null,
      forwarderShipping: null,
      receivedAmount: null,
      exchangeRate: null,
      receivedRmb: null,
      salesRmb: null,
      paymentChannel: '',
      paymentDate: '',
      product: '',
      remark: '',
      isPublicReceipt: false,
      taxRate: 13,
      orderStatus: '',
    })
  );

const removeRow = idx => {
  const row = items.value[idx];
  if (row.id) deleted.value.push(row.id);
  items.value.splice(idx, 1);
};

// 按汇率折算 RMB：收款额RMB = 收款金额 × 汇率；销售额RMB =（收款金额 − 运费）× 汇率。
const fillRmb = () => {
  items.value.forEach(r => {
    const rate = Number(r.exchangeRate);
    if (!rate) return;
    const recv = Number(r.receivedAmount) || 0;
    const ship = Number(r.shipping) || 0;
    r.receivedRmb = Math.round(recv * rate * 100) / 100;
    // 未到款（收款额为空/0）时销售额记 0，不从零收款里倒扣运费变负数拉低合计。
    r.salesRmb = recv ? Math.round((recv - ship) * rate * 100) / 100 : 0;
  });
};

// 收款额/运费/汇率任一变化即实时折算 RMB，提成基数/工资/合计随之实时更新，
// 无需点「折算」或提交。只监听输入字段（不含 RMB/salary 结果，避免回环）。
watch(
  () =>
    items.value
      .map(
        r =>
          `${r.receivedAmount ?? ''}|${r.shipping ?? ''}|${r.exchangeRate ?? ''}`
      )
      .join(','),
  fillRmb
);

const buildPayload = () => {
  const attrs = items.value.map((r, i) => ({
    id: r.id || undefined,
    position: i + 1,
    product_category: r.productCategory || null,
    country: r.country || null,
    customer_name: r.customerName || null,
    order_no: r.orderNo || null,
    crm_sales_order_id: r.crmSalesOrderId || null,
    order_amount_micros: microsFromYuan(r.orderAmount),
    currency: r.currency || null,
    shipping_micros: microsFromYuan(r.shipping),
    forwarder_shipping_micros: microsFromYuan(r.forwarderShipping),
    received_amount_micros: microsFromYuan(r.receivedAmount),
    exchange_rate: r.exchangeRate === '' ? null : r.exchangeRate,
    received_rmb_micros: microsFromYuan(r.receivedRmb),
    sales_rmb_micros: microsFromYuan(r.salesRmb),
    payment_channel: r.paymentChannel || null,
    payment_date: r.paymentDate || null,
    product: r.product || null,
    remark: r.remark || null,
    is_public_receipt: !!r.isPublicReceipt,
    tax_rate: r.taxRate ?? 13,
  }));
  deleted.value.forEach(id => attrs.push({ id, _destroy: true }));
  return { remark: sheet.value.remark || '', items_attributes: attrs };
};

const save = async () => {
  isBusy.value = true;
  try {
    const { data } = await CommissionSheetsAPI.update(
      accountId.value,
      sheet.value.id,
      buildPayload()
    );
    applySheet(data);
    financeEditing.value = false;
    useAlert(t('CRM.COMMISSION.DETAIL.SAVED'));
  } catch (e) {
    useAlert(e?.response?.data?.error || t('CRM.COMMISSION.DETAIL.SAVE_ERROR'));
  } finally {
    isBusy.value = false;
  }
};

// 财务取消编辑：丢弃未存改动，重载回只读态。
const cancelFinanceEdit = () => {
  financeEditing.value = false;
  load();
};

const pull = async () => {
  isBusy.value = true;
  try {
    // 先保存当前编辑，避免带出后覆盖未保存内容。
    await CommissionSheetsAPI.update(
      accountId.value,
      sheet.value.id,
      buildPayload()
    );
    const { data } = await CommissionSheetsAPI.pullOrders(
      accountId.value,
      sheet.value.id
    );
    applySheet(data);
    const added = camelcaseKeys(data, { deep: true }).added || 0;
    useAlert(
      added
        ? t('CRM.COMMISSION.DETAIL.PULLED', { n: added })
        : t('CRM.COMMISSION.DETAIL.NO_NEW')
    );
  } catch (e) {
    useAlert(e?.response?.data?.error || t('CRM.COMMISSION.DETAIL.PULL_ERROR'));
  } finally {
    isBusy.value = false;
  }
};

// ── 选单导入：从该业务员的销售订单里勾选导入（含跨月订单）──
const showOrderPicker = ref(false);
const pickerOrders = ref([]);
const pickerSelected = ref([]);
const pickerSearch = ref('');
const pickerBusy = ref(false);
const pickerCategory = ref(PRODUCT_CATEGORIES[0]); // 导入时统一归的品类

const filteredPickerOrders = computed(() => {
  const kw = pickerSearch.value.trim().toLowerCase();
  if (!kw) return pickerOrders.value;
  return pickerOrders.value.filter(o =>
    `${o.orderNo || ''} ${o.customerName || ''} ${o.country || ''}`
      .toLowerCase()
      .includes(kw)
  );
});
const pickerYuan = m => (m == null ? '—' : fmtYuan(m));

const openOrderPicker = async () => {
  pickerBusy.value = true;
  showOrderPicker.value = true;
  pickerSelected.value = [];
  pickerSearch.value = '';
  try {
    const { data } = await CommissionSheetsAPI.selectableOrders(
      accountId.value,
      sheet.value.id
    );
    pickerOrders.value = camelcaseKeys(data.orders || [], { deep: true });
  } catch (e) {
    useAlert(e?.response?.data?.error || t('CRM.COMMISSION.LOAD_ERROR'));
  } finally {
    pickerBusy.value = false;
  }
};
const togglePick = id => {
  pickerSelected.value = pickerSelected.value.includes(id)
    ? pickerSelected.value.filter(x => x !== id)
    : [...pickerSelected.value, id];
};
const allPickerSelected = computed(
  () =>
    filteredPickerOrders.value.length > 0 &&
    filteredPickerOrders.value.every(o => pickerSelected.value.includes(o.id))
);
const togglePickAll = () => {
  pickerSelected.value = allPickerSelected.value
    ? []
    : filteredPickerOrders.value.map(o => o.id);
};

const importSelectedOrders = async () => {
  if (!pickerSelected.value.length) return;
  pickerBusy.value = true;
  try {
    // 先保存当前编辑，避免导入后覆盖未保存内容。
    await CommissionSheetsAPI.update(
      accountId.value,
      sheet.value.id,
      buildPayload()
    );
    const { data } = await CommissionSheetsAPI.importOrders(
      accountId.value,
      sheet.value.id,
      pickerSelected.value,
      pickerCategory.value
    );
    applySheet(data);
    const added = camelcaseKeys(data, { deep: true }).added || 0;
    useAlert(t('CRM.COMMISSION.DETAIL.PULLED', { n: added }));
    showOrderPicker.value = false;
  } catch (e) {
    useAlert(e?.response?.data?.error || t('CRM.COMMISSION.DETAIL.SAVE_ERROR'));
  } finally {
    pickerBusy.value = false;
  }
};

const submit = async () => {
  if (!window.confirm(t('CRM.COMMISSION.DETAIL.CONFIRM_SUBMIT'))) return;
  isBusy.value = true;
  try {
    await CommissionSheetsAPI.update(
      accountId.value,
      sheet.value.id,
      buildPayload()
    );
    const { data } = await CommissionSheetsAPI.submit(
      accountId.value,
      sheet.value.id
    );
    applySheet(data);
    useAlert(t('CRM.COMMISSION.DETAIL.SUBMITTED_OK'));
  } catch (e) {
    useAlert(
      e?.response?.data?.error || t('CRM.COMMISSION.DETAIL.SUBMIT_ERROR')
    );
  } finally {
    isBusy.value = false;
  }
};

const approve = async () => {
  isBusy.value = true;
  try {
    const { data } = await CommissionSheetsAPI.approve(
      accountId.value,
      sheet.value.id
    );
    applySheet(data);
    useAlert(t('CRM.COMMISSION.DETAIL.APPROVED_OK'));
  } catch (e) {
    useAlert(
      e?.response?.data?.error || t('CRM.COMMISSION.DETAIL.APPROVE_ERROR')
    );
  } finally {
    isBusy.value = false;
  }
};

const returnSheet = async () => {
  const reason = window.prompt(t('CRM.COMMISSION.DETAIL.RETURN_REASON'));
  if (reason == null) return;
  if (!reason.trim()) {
    useAlert(t('CRM.COMMISSION.DETAIL.RETURN_REASON'));
    return;
  }
  isBusy.value = true;
  try {
    const { data } = await CommissionSheetsAPI.returnSheet(
      accountId.value,
      sheet.value.id,
      reason.trim()
    );
    applySheet(data);
    useAlert(t('CRM.COMMISSION.DETAIL.RETURNED_OK'));
  } catch (e) {
    useAlert(
      e?.response?.data?.error || t('CRM.COMMISSION.DETAIL.RETURN_ERROR')
    );
  } finally {
    isBusy.value = false;
  }
};

// ── 财务发放：仅已通过(APPROVED)表可标记，须填实发提成金额 + 可选备注 ──
const payAmount = ref('');
const payNote = ref('');
const markPaid = async () => {
  isBusy.value = true;
  try {
    const payItems = [
      {
        id: sheet.value.id,
        paid_amount_micros:
          payAmount.value === ''
            ? null
            : Math.round(Number(payAmount.value) * 1_000_000),
        paid_note: payNote.value.trim(),
      },
    ];
    const { data } = await CommissionSheetsAPI.markPaid(
      accountId.value,
      payItems
    );
    await load();
    payAmount.value = '';
    payNote.value = '';
    useAlert(t('CRM.COMMISSION.PAYOUT.MARKED', { n: data?.count ?? 0 }));
  } catch (e) {
    useAlert(e?.response?.data?.error || t('CRM.COMMISSION.PAYOUT.ERROR'));
  } finally {
    isBusy.value = false;
  }
};
const unmarkPaid = async () => {
  if (!window.confirm(t('CRM.COMMISSION.PAYOUT.UNMARK_CONFIRM'))) return;
  isBusy.value = true;
  try {
    await CommissionSheetsAPI.unmarkPaid(accountId.value, [sheet.value.id]);
    await load();
    useAlert(t('CRM.COMMISSION.PAYOUT.UNMARKED'));
  } catch (e) {
    useAlert(e?.response?.data?.error || t('CRM.COMMISSION.PAYOUT.ERROR'));
  } finally {
    isBusy.value = false;
  }
};
const yuanText = m => (m == null ? '—' : `¥${fmtYuan(m)}`);
const fmtDate = v => (v ? new Date(v).toLocaleDateString() : '');

const exportXlsx = async () => {
  try {
    const { data } = await CommissionSheetsAPI.xlsx(
      accountId.value,
      sheet.value.id
    );
    const url = window.URL.createObjectURL(new Blob([data]));
    const a = document.createElement('a');
    a.href = url;
    const d = new Date(sheet.value.periodMonth);
    a.download = `${t('CRM.COMMISSION.HEADER')}-${sheet.value.ownerName || ''}-${d.getFullYear()}-${d.getMonth() + 1}.xlsx`;
    a.click();
    window.URL.revokeObjectURL(url);
  } catch (e) {
    useAlert(
      e?.response?.data?.error || t('CRM.COMMISSION.DETAIL.EXPORT_ERROR')
    );
  }
};

// 导出图片：把只读分组表（含标题/小计/总计）截成 PNG 下载，方便发群/存档。
const exportImage = async () => {
  if (!captureRef.value) return;
  try {
    const dataUrl = await toPng(captureRef.value, {
      backgroundColor: '#ffffff',
      pixelRatio: 2,
      fontEmbedCSS: '',
      cacheBust: true,
    });
    const a = document.createElement('a');
    a.href = dataUrl;
    const d = new Date(sheet.value.periodMonth);
    a.download = `${t('CRM.COMMISSION.HEADER')}-${sheet.value.ownerName || ''}-${d.getFullYear()}-${d.getMonth() + 1}.png`;
    a.click();
  } catch (e) {
    useAlert(t('CRM.COMMISSION.DETAIL.EXPORT_IMAGE_ERROR'));
  }
};

// 直接打印：把只读分组表（品类分组+小计+总计）交给浏览器打印对话框，可出纸或另存 PDF。
const printSheet = () => {
  if (!sheet.value) return;
  const d = new Date(sheet.value.periodMonth);
  const label = `${d.getFullYear()}-${d.getMonth() + 1}`;
  printElement(
    captureRef.value,
    `${t('CRM.COMMISSION.HEADER')}-${sheet.value.ownerName || ''}-${label}`
  );
};

const back = () => router.push({ name: 'crm_commission_sheets_index' });

// ── 只读分组视图（含小计/总计），镜像导出版式 ──
const fmtYuan2 = v =>
  v == null || v === ''
    ? '—'
    : Number(v).toLocaleString('zh-CN', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      });
const sum = (rows, key) =>
  rows.reduce((acc, r) => acc + (Number(r[key]) || 0), 0);
const sumBy = (rows, fn) => rows.reduce((acc, r) => acc + (fn(r) || 0), 0);

// 运费额RMB（不单独展示）= 向客户收的运费 × 汇率；运费差额 = 运费额RMB − 货代实收运费(付货代成本)。
const freightRmbOf = r =>
  Math.round((Number(r.shipping) || 0) * (Number(r.exchangeRate) || 0) * 100) /
  100;
const freightDiffOf = r =>
  Math.round((freightRmbOf(r) - (Number(r.forwarderShipping) || 0)) * 100) /
  100;

// 提成点(%)：按品类查表；提成基数：销售额RMB+运费差额，对公再整体÷(1+税点%)；提成工资=基数×点位/100。
const rateOf = r => Number(rateMap.value[r.productCategory]) || 0;
const baseOf = r => {
  if (r.salesRmb == null || r.salesRmb === '') return null;
  let s = Number(r.salesRmb) + freightDiffOf(r);
  if (r.isPublicReceipt) {
    const tax = Number(r.taxRate) || 13;
    s /= 1 + tax / 100;
  }
  return Math.round(s * 100) / 100;
};
const salaryOf = r => {
  const base = baseOf(r);
  const rate = rateOf(r);
  if (base == null || !rate) return null;
  return Math.round(((base * rate) / 100) * 100) / 100;
};
const sumSalary = rows => rows.reduce((acc, r) => acc + (salaryOf(r) || 0), 0);
const groups = computed(() => {
  const map = new Map();
  items.value.forEach(r => {
    const k = r.productCategory || t('CRM.COMMISSION.DETAIL.UNCATEGORIZED');
    if (!map.has(k)) map.set(k, []);
    map.get(k).push(r);
  });
  return [...map.entries()].map(([category, rows]) => ({ category, rows }));
});
const grand = computed(() => ({
  shipping: sum(items.value, 'shipping'),
  forwarderShipping: sum(items.value, 'forwarderShipping'),
  receivedRmb: sum(items.value, 'receivedRmb'),
  salesRmb: sum(items.value, 'salesRmb'),
  freightDiff: sumBy(items.value, freightDiffOf),
  salary: sumSalary(items.value),
}));

// 品类不匹配告警：明细里填了品类、但提成点配置里查无此品类名 → 提成点按 0 算(悄悄归零)。
// 列出这些「配置里没有」的品类，提示核对品类名/补配提成点，避免提成被静默算成 0。
const unmatchedCategories = computed(() => {
  const configured = rateMap.value || {};
  const bad = new Set();
  items.value.forEach(r => {
    const cat = (r.productCategory || '').trim();
    if (cat && !(cat in configured)) bad.add(cat);
  });
  return [...bad];
});

// 算不出提成的行：填了收款额、销售额RMB 却是空的。
// fillRmb 遇到空汇率直接 return，销售额RMB 就一直是空，提成基数跟着是空 —— 提成栏显示
// 空白，和「这行提成本来就是 0」长得一样，于是整行提成被静默漏掉（美金单最常中招）。
const rowsMissingBase = computed(() =>
  items.value
    .map((r, i) => ({ row: r, seq: i + 1 }))
    .filter(
      ({ row }) =>
        (Number(row.receivedAmount) || 0) > 0 &&
        (row.salesRmb == null || row.salesRmb === '')
    )
    .map(({ row, seq }) => row.orderNo || `第 ${seq} 行`)
);

// ── 转发到团队沟通：把本提成表的摘要 + 回跳链接（可选表图）发到某个团队沟通会话 ──
const forwardRef = ref(null);
// 现场把只读分组表截成 PNG File 当附件（复用导出图片的 captureRef/toPng）。
const makeSheetImage = async () => {
  if (!captureRef.value) return null;
  const dataUrl = await toPng(captureRef.value, {
    backgroundColor: '#ffffff',
    pixelRatio: 2,
    cacheBust: true,
  });
  const blob = await (await fetch(dataUrl)).blob();
  const d = new Date(sheet.value.periodMonth);
  const name = `${t('CRM.COMMISSION.HEADER')}-${sheet.value.ownerName || ''}-${d.getFullYear()}-${d.getMonth() + 1}.png`;
  return new File([blob], name, { type: 'image/png' });
};
const openForward = () => {
  if (!sheet.value) return;
  const link = `${window.location.origin}${
    router.resolve({
      name: 'crm_commission_sheet_detail',
      query: { id: sheet.value.id },
    }).href
  }`;
  const statusLabel = t(`CRM.COMMISSION.STATUS.${status.value}`);
  const text =
    `${title.value} 提成表\n` +
    `提成合计 ¥${fmtYuan2(grand.value.salary)} · ${statusLabel}\n` +
    `${link}`;
  // 截图容器仅只读态渲染；编辑态取不到就只发链接（不显示表图选项）。
  forwardRef.value?.open(
    text,
    captureRef.value ? { makeImage: makeSheetImage } : undefined
  );
};
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div
      class="flex flex-col md:flex-row md:items-center md:justify-between flex-shrink-0 gap-3 px-4 py-3 sm:px-6 sm:py-4 border-b border-n-weak"
    >
      <div class="flex items-center gap-3 min-w-0">
        <button
          class="h-8 px-3 text-sm rounded-lg shrink-0 text-n-slate-11 hover:bg-n-alpha-2"
          @click="back"
        >
          {{ t('CRM.COMMISSION.DETAIL.BACK') }}
        </button>
        <h1 class="text-lg font-medium truncate min-w-0 text-n-slate-12">
          {{ title }}
        </h1>
        <span
          v-if="sheet"
          class="inline-flex px-2 py-0.5 rounded-full text-xs shrink-0 bg-n-iris-3 text-n-iris-11"
        >
          {{ t(`CRM.COMMISSION.STATUS.${status}`) }}
        </span>
        <span
          v-if="sheet && sheet.paidAt"
          class="inline-flex px-2 py-0.5 rounded-full text-xs shrink-0 bg-n-teal-3 text-n-teal-11"
        >
          {{ t('CRM.COMMISSION.PAYOUT.PAID') }}
        </span>
      </div>
      <div class="flex flex-wrap items-center gap-2 md:shrink-0">
        <button
          v-if="sheet"
          class="inline-flex items-center gap-1.5 h-8 px-3 text-sm rounded-lg border border-n-iris-6 text-n-iris-11 hover:bg-n-iris-3"
          @click="openForward"
        >
          <Icon icon="i-lucide-send" class="size-4" />
          转发到团队沟通
        </button>
        <template v-if="editable">
          <button
            v-if="canPullImport"
            class="h-8 px-3 text-sm rounded-lg text-n-slate-11 hover:bg-n-alpha-2 disabled:opacity-50"
            :disabled="isBusy"
            @click="pull"
          >
            {{ t('CRM.COMMISSION.DETAIL.PULL') }}
          </button>
          <button
            v-if="canPullImport"
            class="h-8 px-3 text-sm rounded-lg text-n-slate-11 hover:bg-n-alpha-2 disabled:opacity-50"
            :disabled="isBusy"
            @click="openOrderPicker"
          >
            {{ t('CRM.COMMISSION.DETAIL.IMPORT_ORDERS') }}
          </button>
          <button
            class="h-8 px-3 text-sm rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
            @click="fillRmb"
          >
            {{ t('CRM.COMMISSION.DETAIL.FILL_RMB') }}
          </button>
          <button
            class="h-8 px-3 text-sm rounded-lg border border-n-weak text-n-slate-12 hover:bg-n-alpha-1 disabled:opacity-50"
            :disabled="isBusy"
            @click="save"
          >
            {{ t('CRM.COMMISSION.DETAIL.SAVE') }}
          </button>
          <button
            v-if="financeEditing"
            class="h-8 px-3 text-sm rounded-lg text-n-slate-11 hover:bg-n-alpha-2 disabled:opacity-50"
            :disabled="isBusy"
            @click="cancelFinanceEdit"
          >
            {{ t('CRM.COMMISSION.DETAIL.FINANCE_CANCEL') }}
          </button>
          <button
            v-if="canSubmit"
            class="h-8 px-4 text-sm font-medium text-white rounded-lg bg-gradient-to-br from-n-iris-9 to-n-accent-grad hover:brightness-105 disabled:opacity-50"
            :disabled="isBusy"
            @click="submit"
          >
            {{ t('CRM.COMMISSION.DETAIL.SUBMIT') }}
          </button>
        </template>
        <template v-if="canApprove">
          <button
            class="h-8 px-3 text-sm rounded-lg text-n-ruby-11 border border-n-ruby-6 hover:bg-n-ruby-3 disabled:opacity-50"
            :disabled="isBusy"
            @click="returnSheet"
          >
            {{ t('CRM.COMMISSION.DETAIL.RETURN') }}
          </button>
          <button
            class="h-8 px-4 text-sm font-medium text-white rounded-lg bg-n-teal-9 hover:bg-n-teal-10 disabled:opacity-50"
            :disabled="isBusy"
            @click="approve"
          >
            {{ t('CRM.COMMISSION.DETAIL.APPROVE') }}
          </button>
        </template>
        <button
          v-if="canFinanceEdit"
          class="h-8 px-4 text-sm font-medium rounded-lg border border-n-iris-6 text-n-iris-11 hover:bg-n-iris-3"
          @click="financeEditing = true"
        >
          {{ t('CRM.COMMISSION.DETAIL.FINANCE_EDIT') }}
        </button>
        <button
          v-if="canFinanceReturn"
          class="h-8 px-3 text-sm rounded-lg text-n-ruby-11 border border-n-ruby-6 hover:bg-n-ruby-3 disabled:opacity-50"
          :disabled="isBusy"
          @click="returnSheet"
        >
          {{ t('CRM.COMMISSION.DETAIL.RETURN_TO_OWNER') }}
        </button>
        <button
          v-if="!editable"
          class="h-8 px-4 text-sm font-medium rounded-lg border border-n-weak text-n-slate-12 hover:bg-n-alpha-1"
          @click="printSheet"
        >
          打印
        </button>
        <button
          v-if="canExport && !editable"
          class="h-8 px-4 text-sm font-medium rounded-lg border border-n-weak text-n-slate-12 hover:bg-n-alpha-1"
          @click="exportImage"
        >
          {{ t('CRM.COMMISSION.DETAIL.EXPORT_IMAGE') }}
        </button>
        <button
          v-if="canExport"
          class="h-8 px-4 text-sm font-medium rounded-lg border border-n-weak text-n-slate-12 hover:bg-n-alpha-1"
          @click="exportXlsx"
        >
          {{ t('CRM.COMMISSION.DETAIL.EXPORT') }}
        </button>
      </div>
    </div>

    <div v-if="isLoading" class="flex-1 p-8 text-center text-n-slate-11">
      {{ t('CRM.COMMISSION.LOADING') }}
    </div>
    <div v-else-if="sheet" class="flex-1 px-4 py-3 sm:px-6 sm:py-4">
      <!-- 退回原因提示 -->
      <div
        v-if="status === 'RETURNED' && sheet.returnReason"
        class="px-3 py-2 mb-3 text-sm rounded-lg bg-n-ruby-3 text-n-ruby-11"
      >
        {{ t('CRM.COMMISSION.DETAIL.RETURNED_PREFIX') }}{{ sheet.returnReason }}
      </div>

      <!-- 财务发放：已通过表标记实发提成（未发放时填金额；已发放显示信息） -->
      <div
        v-if="canMarkPaid && !sheet.paidAt"
        class="flex flex-wrap items-center gap-2 px-3 py-3 mb-3 border rounded-xl border-n-teal-6 bg-n-teal-2"
      >
        <span class="text-sm font-medium text-n-teal-11">
          {{ t('CRM.COMMISSION.PAYOUT.MARK_TITLE') }}
        </span>
        <div class="flex items-center gap-1">
          <span class="text-xs text-n-slate-10">¥</span>
          <input
            v-model="payAmount"
            type="number"
            min="0"
            step="0.01"
            :placeholder="t('CRM.COMMISSION.PAYOUT.AMOUNT_PLACEHOLDER')"
            class="h-8 px-2 text-sm text-right border rounded-lg reset-base w-32 border-n-weak bg-n-solid-1 text-n-slate-12"
          />
        </div>
        <input
          v-model="payNote"
          :placeholder="t('CRM.COMMISSION.PAYOUT.NOTE_PLACEHOLDER')"
          class="flex-1 h-8 px-2 text-sm border rounded-lg reset-base min-w-40 border-n-weak bg-n-solid-1 text-n-slate-12"
        />
        <button
          class="h-8 px-4 text-sm font-medium text-white rounded-lg bg-n-teal-9 hover:bg-n-teal-10 disabled:opacity-50"
          :disabled="isBusy"
          @click="markPaid"
        >
          {{ t('CRM.COMMISSION.PAYOUT.MARK_ONE') }}
        </button>
      </div>
      <div
        v-else-if="sheet.paidAt"
        class="flex flex-wrap items-center gap-2 px-3 py-2 mb-3 text-sm border rounded-xl border-n-teal-6 bg-n-teal-2 text-n-slate-12"
      >
        <span class="i-lucide-banknote size-4 shrink-0 text-n-teal-11" />
        <span class="font-medium text-n-teal-11">{{
          t('CRM.COMMISSION.PAYOUT.PAID_LABEL')
        }}</span>
        <span class="font-medium">{{ yuanText(sheet.paidAmountMicros) }}</span>
        <span class="text-xs text-n-slate-10"
          >（{{ sheet.paidByName || '' }} · {{ fmtDate(sheet.paidAt) }}）</span
        >
        <span v-if="sheet.paidNote" class="text-xs text-n-slate-11"
          >· {{ sheet.paidNote }}</span
        >
        <button
          v-if="isCrmFinance"
          class="h-7 px-2 ml-auto text-xs rounded-lg text-n-slate-10 hover:bg-n-alpha-2"
          :disabled="isBusy"
          @click="unmarkPaid"
        >
          {{ t('CRM.COMMISSION.PAYOUT.UNMARK') }}
        </button>
      </div>

      <!-- 品类不匹配告警：明细品类名与提成点配置对不上，提成点会被静默算成 0 -->
      <div
        v-if="unmatchedCategories.length"
        class="flex items-start gap-2 px-3 py-2 mb-2 text-xs rounded-xl bg-n-amber-3/60 text-n-amber-11 border border-n-amber-6"
      >
        <Icon icon="i-lucide-triangle-alert" class="size-3.5 mt-px shrink-0" />
        <span>{{
          t('CRM.COMMISSION.DETAIL.CATEGORY_MISMATCH', {
            list: unmatchedCategories.join('、'),
          })
        }}</span>
      </div>

      <div
        v-if="rowsMissingBase.length"
        class="flex items-start gap-2 px-3 py-2 mb-2 text-xs rounded-xl bg-n-amber-3/60 text-n-amber-11 border border-n-amber-6"
      >
        <Icon icon="i-lucide-triangle-alert" class="size-3.5 mt-px shrink-0" />
        <span>{{
          t('CRM.COMMISSION.DETAIL.MISSING_BASE', {
            count: rowsMissingBase.length,
            list: rowsMissingBase.join('、'),
          })
        }}</span>
      </div>

      <!-- 编辑态：可编辑网格 -->
      <div v-if="editable" class="overflow-x-auto">
        <table class="w-max text-xs border-collapse whitespace-nowrap">
          <colgroup>
            <col class="w-8" />
            <col class="w-24" />
            <col class="w-16" />
            <col class="w-40" />
            <col class="w-36" />
            <col class="w-20" />
            <col class="w-24" />
            <col class="w-16" />
            <col class="w-16" />
            <col class="w-20" />
            <col class="w-24" />
            <col class="w-20" />
            <col class="w-28" />
            <col class="w-28" />
            <col class="w-28" />
            <col class="w-28" />
            <col class="w-36" />
            <col class="w-40" />
            <col class="w-28" />
            <col class="w-12" />
            <col class="w-16" />
            <col class="w-28" />
            <col class="w-16" />
            <col class="w-28" />
            <col class="w-8" />
          </colgroup>
          <thead class="text-n-slate-11">
            <tr class="border-b border-n-weak">
              <th class="px-1 py-2 font-medium text-left">#</th>
              <th class="px-1 py-2 font-medium text-left">
                {{ t('CRM.COMMISSION.COLS.CATEGORY') }}
              </th>
              <th class="px-1 py-2 font-medium text-left">
                {{ t('CRM.COMMISSION.COLS.COUNTRY') }}
              </th>
              <th class="px-1 py-2 font-medium text-left">
                {{ t('CRM.COMMISSION.COLS.CUSTOMER') }}
              </th>
              <th class="px-1 py-2 font-medium text-left">
                {{ t('CRM.COMMISSION.COLS.ORDER_NO') }}
              </th>
              <th class="px-1 py-2 font-medium text-left">
                {{ t('CRM.COMMISSION.COLS.ORDER_STATUS') }}
              </th>
              <th class="py-2 pl-1 pr-2 font-medium text-right">
                {{ t('CRM.COMMISSION.COLS.ORDER_AMOUNT') }}
              </th>
              <th class="px-1 py-2 font-medium text-left">
                {{ t('CRM.COMMISSION.COLS.CURRENCY') }}
              </th>
              <th class="py-2 pl-1 pr-2 font-medium text-right">
                {{ t('CRM.COMMISSION.COLS.SHIPPING') }}
              </th>
              <th class="py-2 pl-1 pr-2 font-medium text-right">
                {{ t('CRM.COMMISSION.COLS.FORWARDER_SHIPPING') }}
              </th>
              <th class="py-2 pl-1 pr-2 font-medium text-right">
                {{ t('CRM.COMMISSION.COLS.RECEIVED') }}
              </th>
              <th class="py-2 pl-1 pr-2 font-medium text-right">
                {{ t('CRM.COMMISSION.COLS.RATE') }}
              </th>
              <th class="py-2 pl-1 pr-2 font-medium text-right">
                {{ t('CRM.COMMISSION.COLS.RECEIVED_RMB') }}
              </th>
              <th class="py-2 pl-1 pr-2 font-medium text-right">
                {{ t('CRM.COMMISSION.COLS.SALES_RMB') }}
              </th>
              <th class="py-2 pl-1 pr-2 font-medium text-right">
                {{ t('CRM.COMMISSION.COLS.FREIGHT_DIFF') }}
              </th>
              <th class="px-1 py-2 font-medium text-left">
                {{ t('CRM.COMMISSION.COLS.CHANNEL') }}
              </th>
              <th class="px-1 py-2 font-medium text-left">
                {{ t('CRM.COMMISSION.COLS.PAY_DATE') }}
              </th>
              <th class="px-1 py-2 font-medium text-left">
                {{ t('CRM.COMMISSION.COLS.PRODUCT') }}
              </th>
              <th class="px-1 py-2 font-medium text-left">
                {{ t('CRM.COMMISSION.COLS.REMARK') }}
              </th>
              <th class="px-1 py-2 font-medium text-center">
                {{ t('CRM.COMMISSION.COLS.IS_PUBLIC') }}
              </th>
              <th class="px-1 py-2 font-medium text-center">
                {{ t('CRM.COMMISSION.COLS.TAX_RATE') }}
              </th>
              <th class="py-2 pl-1 pr-2 font-medium text-right">
                {{ t('CRM.COMMISSION.COLS.COMM_BASE') }}
              </th>
              <th class="py-2 pl-1 pr-2 font-medium text-right">
                {{ t('CRM.COMMISSION.COLS.COMM_RATE') }}
              </th>
              <th class="py-2 pl-1 pr-2 font-medium text-right">
                {{ t('CRM.COMMISSION.COLS.COMM_SALARY') }}
              </th>
              <th class="px-1 py-2 w-8" />
            </tr>
          </thead>
          <tbody>
            <tr v-for="(r, i) in items" :key="i" class="border-b border-n-weak">
              <td class="px-1 py-1 text-n-slate-10">{{ i + 1 }}</td>
              <td class="px-1 py-1">
                <select
                  v-model="r.productCategory"
                  class="w-full h-8 px-1 py-0 mb-0 text-xs leading-8 border rounded reset-base border-n-weak bg-n-solid-1"
                >
                  <option value="">—</option>
                  <option v-for="c in PRODUCT_CATEGORIES" :key="c" :value="c">
                    {{ c }}
                  </option>
                </select>
              </td>
              <td class="px-1 py-1">
                <input
                  v-model="r.country"
                  class="w-full h-8 px-1 text-xs border rounded reset-base border-n-weak bg-n-solid-1"
                />
              </td>
              <td class="px-1 py-1">
                <input
                  v-model="r.customerName"
                  class="w-full h-8 px-1 text-xs border rounded reset-base border-n-weak bg-n-solid-1"
                />
              </td>
              <td class="px-1 py-1">
                <input
                  v-model="r.orderNo"
                  class="w-full h-8 px-1 text-xs border rounded reset-base border-n-weak bg-n-solid-1"
                />
              </td>
              <td class="px-1 py-1 text-n-slate-11">
                {{ orderStatusText(r.orderStatus) || '—' }}
              </td>
              <td class="px-1 py-1">
                <input
                  v-model.number="r.orderAmount"
                  type="number"
                  step="0.01"
                  class="w-full h-8 px-1 text-xs text-right border rounded reset-base border-n-weak bg-n-solid-1"
                />
              </td>
              <td class="px-1 py-1">
                <select
                  v-model="r.currency"
                  class="w-full h-8 px-1 py-0 mb-0 text-xs leading-8 border rounded reset-base border-n-weak bg-n-solid-1"
                >
                  <option v-for="c in CURRENCIES" :key="c" :value="c">
                    {{ c }}
                  </option>
                </select>
              </td>
              <td class="px-1 py-1">
                <input
                  v-model.number="r.shipping"
                  type="number"
                  step="0.01"
                  class="w-full h-8 px-1 text-xs text-right border rounded reset-base border-n-weak bg-n-solid-1"
                />
              </td>
              <td class="px-1 py-1">
                <input
                  v-model.number="r.forwarderShipping"
                  type="number"
                  step="0.01"
                  class="w-full h-8 px-1 text-xs text-right border rounded reset-base border-n-weak bg-n-solid-1"
                />
              </td>
              <td class="px-1 py-1">
                <input
                  v-model.number="r.receivedAmount"
                  type="number"
                  step="0.01"
                  class="w-full h-8 px-1 text-xs text-right border rounded reset-base border-n-weak bg-n-solid-1"
                />
              </td>
              <td class="px-1 py-1">
                <input
                  v-model.number="r.exchangeRate"
                  type="number"
                  step="0.0001"
                  class="w-full h-8 px-1 text-xs text-right border rounded reset-base border-n-weak bg-n-solid-1"
                />
              </td>
              <td class="px-1 py-1">
                <input
                  v-model.number="r.receivedRmb"
                  type="number"
                  step="0.01"
                  class="w-full h-8 px-1 text-xs text-right border rounded reset-base border-n-weak bg-n-solid-1"
                />
              </td>
              <td class="px-1 py-1">
                <input
                  v-model.number="r.salesRmb"
                  type="number"
                  step="0.01"
                  class="w-full h-8 px-1 text-xs text-right border rounded reset-base border-n-weak bg-n-solid-1"
                />
              </td>
              <td
                class="pl-1 pr-2 py-1 text-right tabular-nums text-n-slate-11"
              >
                {{ fmtYuan2(freightDiffOf(r)) }}
              </td>
              <td class="px-1 py-1">
                <input
                  v-model="r.paymentChannel"
                  class="w-full h-8 px-1 text-xs border rounded reset-base border-n-weak bg-n-solid-1"
                />
              </td>
              <td class="px-1 py-1">
                <input
                  v-model="r.paymentDate"
                  type="date"
                  class="w-full h-8 px-1 text-xs border rounded reset-base border-n-weak bg-n-solid-1"
                />
              </td>
              <td class="px-1 py-1">
                <input
                  v-model="r.product"
                  class="w-full h-8 px-1 text-xs border rounded reset-base border-n-weak bg-n-solid-1"
                />
              </td>
              <td class="px-1 py-1">
                <input
                  v-model="r.remark"
                  class="w-full h-8 px-1 text-xs border rounded reset-base border-n-weak bg-n-solid-1"
                />
              </td>
              <td class="px-1 py-1 text-center">
                <input
                  v-model="r.isPublicReceipt"
                  type="checkbox"
                  class="accent-n-iris-9"
                />
              </td>
              <td class="px-1 py-1">
                <select
                  v-model.number="r.taxRate"
                  :disabled="!r.isPublicReceipt"
                  class="w-full h-8 px-1 py-0 mb-0 text-xs leading-8 border rounded reset-base border-n-weak bg-n-solid-1 disabled:opacity-40"
                >
                  <option v-for="tr in TAX_RATES" :key="tr" :value="tr">
                    {{ tr }}%
                  </option>
                </select>
              </td>
              <td
                class="pl-1 pr-2 py-1 text-right tabular-nums text-n-slate-11"
              >
                {{ fmtYuan2(baseOf(r)) }}
              </td>
              <td
                class="pl-1 pr-2 py-1 text-right tabular-nums text-n-slate-11"
              >
                {{ rateOf(r) ? `${rateOf(r)}%` : '—' }}
              </td>
              <td
                class="pl-1 pr-2 py-1 text-right tabular-nums font-medium text-n-slate-12"
              >
                {{ fmtYuan2(salaryOf(r)) }}
              </td>
              <td class="px-1 py-1 text-center">
                <button
                  class="text-n-ruby-11 hover:text-n-ruby-10"
                  @click="removeRow(i)"
                >
                  <Icon icon="i-lucide-x" class="size-4" />
                </button>
              </td>
            </tr>
            <tr v-if="!items.length">
              <td colspan="25" class="px-3 py-6 text-center text-n-slate-10">
                {{ t('CRM.COMMISSION.DETAIL.NO_ITEMS_EDIT') }}
              </td>
            </tr>
          </tbody>
        </table>
        <button
          class="h-8 px-3 mt-3 text-sm rounded-lg border border-dashed border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
          @click="addRow"
        >
          {{ t('CRM.COMMISSION.DETAIL.ADD_ROW') }}
        </button>
      </div>

      <!-- 只读分组视图（按品类分组 + 小计 + 总计）：始终渲染供转发/导出截图；
           编辑态时移到屏幕外只作快照源（不能 display:none，否则 toPng 截不到）。-->
      <div
        class="overflow-x-auto"
        :class="
          editable ? 'absolute -left-[10000px] top-0 pointer-events-none' : ''
        "
      >
        <div
          ref="captureRef"
          class="inline-block min-w-full p-4 bg-n-solid-1 rounded-2xl border border-n-weak"
        >
          <div class="mb-2 text-sm font-semibold text-n-slate-12">
            {{ title }}
          </div>
          <table
            class="w-max min-w-full text-xs border-collapse whitespace-nowrap"
          >
            <thead class="text-n-slate-11">
              <tr class="border-b border-n-weak">
                <th class="px-2 py-2 font-medium text-left">
                  {{ t('CRM.COMMISSION.COLS.SEQ') }}
                </th>
                <th class="px-2 py-2 font-medium text-left">
                  {{ t('CRM.COMMISSION.COLS.CATEGORY') }}
                </th>
                <th class="px-2 py-2 font-medium text-left">
                  {{ t('CRM.COMMISSION.COLS.COUNTRY') }}
                </th>
                <th class="px-2 py-2 font-medium text-left">
                  {{ t('CRM.COMMISSION.COLS.CUSTOMER') }}
                </th>
                <th class="px-2 py-2 font-medium text-left">
                  {{ t('CRM.COMMISSION.COLS.ORDER_NO') }}
                </th>
                <th class="px-2 py-2 font-medium text-left">
                  {{ t('CRM.COMMISSION.COLS.ORDER_STATUS') }}
                </th>
                <th class="px-2 py-2 font-medium text-right">
                  {{ t('CRM.COMMISSION.COLS.ORDER_AMOUNT') }}
                </th>
                <th class="px-2 py-2 font-medium text-left">
                  {{ t('CRM.COMMISSION.COLS.CURRENCY') }}
                </th>
                <th class="px-2 py-2 font-medium text-right">
                  {{ t('CRM.COMMISSION.COLS.SHIPPING') }}
                </th>
                <th class="px-2 py-2 font-medium text-right">
                  {{ t('CRM.COMMISSION.COLS.FORWARDER_SHIPPING') }}
                </th>
                <th class="px-2 py-2 font-medium text-right">
                  {{ t('CRM.COMMISSION.COLS.RECEIVED') }}
                </th>
                <th class="px-2 py-2 font-medium text-right">
                  {{ t('CRM.COMMISSION.COLS.RATE') }}
                </th>
                <th class="px-2 py-2 font-medium text-right">
                  {{ t('CRM.COMMISSION.COLS.RECEIVED_RMB') }}
                </th>
                <th class="px-2 py-2 font-medium text-right">
                  {{ t('CRM.COMMISSION.COLS.SALES_RMB') }}
                </th>
                <th class="px-2 py-2 font-medium text-right">
                  {{ t('CRM.COMMISSION.COLS.FREIGHT_DIFF') }}
                </th>
                <th class="px-2 py-2 font-medium text-left">
                  {{ t('CRM.COMMISSION.COLS.CHANNEL') }}
                </th>
                <th class="px-2 py-2 font-medium text-left">
                  {{ t('CRM.COMMISSION.COLS.PAY_DATE') }}
                </th>
                <th class="px-2 py-2 font-medium text-left">
                  {{ t('CRM.COMMISSION.COLS.PRODUCT') }}
                </th>
                <th class="px-2 py-2 font-medium text-left">
                  {{ t('CRM.COMMISSION.COLS.REMARK') }}
                </th>
                <th class="px-2 py-2 font-medium text-center">
                  {{ t('CRM.COMMISSION.COLS.IS_PUBLIC') }}
                </th>
                <th class="px-2 py-2 font-medium text-center">
                  {{ t('CRM.COMMISSION.COLS.TAX_RATE') }}
                </th>
                <th class="px-2 py-2 font-medium text-right">
                  {{ t('CRM.COMMISSION.COLS.COMM_BASE') }}
                </th>
                <th class="px-2 py-2 font-medium text-right">
                  {{ t('CRM.COMMISSION.COLS.COMM_RATE') }}
                </th>
                <th class="px-2 py-2 font-medium text-right">
                  {{ t('CRM.COMMISSION.COLS.COMM_SALARY') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <template v-for="g in groups" :key="g.category">
                <tr
                  v-for="(r, i) in g.rows"
                  :key="`${g.category}-${i}`"
                  class="border-b border-n-weak"
                >
                  <td class="px-2 py-1.5 text-n-slate-10">{{ i + 1 }}</td>
                  <td class="px-2 py-1.5">
                    {{
                      r.productCategory ||
                      t('CRM.COMMISSION.DETAIL.UNCATEGORIZED')
                    }}
                  </td>
                  <td class="px-2 py-1.5">{{ r.country || '—' }}</td>
                  <td class="px-2 py-1.5 text-n-slate-12">
                    {{ r.customerName || '—' }}
                  </td>
                  <td class="px-2 py-1.5">{{ r.orderNo || '—' }}</td>
                  <td class="px-2 py-1.5 text-n-slate-11">
                    {{ orderStatusText(r.orderStatus) || '—' }}
                  </td>
                  <td class="px-2 py-1.5 text-right tabular-nums">
                    {{ fmtYuan2(r.orderAmount) }}
                  </td>
                  <td class="px-2 py-1.5">{{ r.currency || '—' }}</td>
                  <td class="px-2 py-1.5 text-right tabular-nums">
                    {{ fmtYuan2(r.shipping) }}
                  </td>
                  <td class="px-2 py-1.5 text-right tabular-nums">
                    {{ fmtYuan2(r.forwarderShipping) }}
                  </td>
                  <td class="px-2 py-1.5 text-right tabular-nums">
                    {{ fmtYuan2(r.receivedAmount) }}
                  </td>
                  <td class="px-2 py-1.5 text-right tabular-nums">
                    {{ r.exchangeRate ?? '—' }}
                  </td>
                  <td class="px-2 py-1.5 text-right tabular-nums">
                    {{ fmtYuan2(r.receivedRmb) }}
                  </td>
                  <td class="px-2 py-1.5 text-right tabular-nums">
                    {{ fmtYuan2(r.salesRmb) }}
                  </td>
                  <td class="px-2 py-1.5 text-right tabular-nums">
                    {{ fmtYuan2(freightDiffOf(r)) }}
                  </td>
                  <td class="px-2 py-1.5">{{ r.paymentChannel || '—' }}</td>
                  <td class="px-2 py-1.5">{{ r.paymentDate || '—' }}</td>
                  <td class="px-2 py-1.5">{{ r.product || '—' }}</td>
                  <td class="px-2 py-1.5">{{ r.remark || '—' }}</td>
                  <td class="px-2 py-1.5 text-center">
                    {{ r.isPublicReceipt ? '是' : '—' }}
                  </td>
                  <td class="px-2 py-1.5 text-center">
                    {{ r.isPublicReceipt ? `${r.taxRate}%` : '—' }}
                  </td>
                  <td class="px-2 py-1.5 text-right tabular-nums">
                    {{ fmtYuan2(baseOf(r)) }}
                  </td>
                  <td class="px-2 py-1.5 text-right tabular-nums">
                    {{ rateOf(r) ? `${rateOf(r)}%` : '—' }}
                  </td>
                  <td
                    class="px-2 py-1.5 text-right tabular-nums font-medium text-n-slate-12"
                  >
                    {{ fmtYuan2(salaryOf(r)) }}
                  </td>
                </tr>
                <tr class="border-b border-n-weak bg-n-alpha-1 font-medium">
                  <td class="px-2 py-1.5" colspan="2">
                    {{ g.category }}
                    {{ t('CRM.COMMISSION.DETAIL.SUBTOTAL_SUFFIX') }}
                  </td>
                  <td colspan="6" />
                  <td class="px-2 py-1.5 text-right tabular-nums">
                    {{ fmtYuan2(sum(g.rows, 'shipping')) }}
                  </td>
                  <td class="px-2 py-1.5 text-right tabular-nums">
                    {{ fmtYuan2(sum(g.rows, 'forwarderShipping')) }}
                  </td>
                  <td colspan="2" />
                  <td class="px-2 py-1.5 text-right tabular-nums">
                    {{ fmtYuan2(sum(g.rows, 'receivedRmb')) }}
                  </td>
                  <td class="px-2 py-1.5 text-right tabular-nums">
                    {{ fmtYuan2(sum(g.rows, 'salesRmb')) }}
                  </td>
                  <td class="px-2 py-1.5 text-right tabular-nums">
                    {{ fmtYuan2(sumBy(g.rows, freightDiffOf)) }}
                  </td>
                  <td colspan="8" />
                  <td class="px-2 py-1.5 text-right tabular-nums">
                    {{ fmtYuan2(sumSalary(g.rows)) }}
                  </td>
                </tr>
              </template>
              <tr v-if="!items.length">
                <td colspan="24" class="px-3 py-6 text-center text-n-slate-10">
                  {{ t('CRM.COMMISSION.DETAIL.NO_ITEMS') }}
                </td>
              </tr>
              <tr
                v-else
                class="border-b-2 border-n-strong bg-n-alpha-2 font-semibold"
              >
                <td class="px-2 py-2" colspan="2">
                  {{ t('CRM.COMMISSION.DETAIL.TOTAL') }}
                </td>
                <td colspan="6" />
                <td class="px-2 py-2 text-right tabular-nums">
                  {{ fmtYuan2(grand.shipping) }}
                </td>
                <td class="px-2 py-2 text-right tabular-nums">
                  {{ fmtYuan2(grand.forwarderShipping) }}
                </td>
                <td colspan="2" />
                <td class="px-2 py-2 text-right tabular-nums">
                  {{ fmtYuan2(grand.receivedRmb) }}
                </td>
                <td class="px-2 py-2 text-right tabular-nums">
                  {{ fmtYuan2(grand.salesRmb) }}
                </td>
                <td class="px-2 py-2 text-right tabular-nums">
                  {{ fmtYuan2(grand.freightDiff) }}
                </td>
                <td colspan="8" />
                <td class="px-2 py-2 text-right tabular-nums">
                  {{ fmtYuan2(grand.salary) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <!-- 选单导入弹窗：从该业务员的销售订单勾选导入 -->
    <div
      v-if="showOrderPicker"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40"
      @click.self="showOrderPicker = false"
    >
      <div
        class="flex flex-col w-full max-w-2xl overflow-hidden bg-n-solid-1 rounded-2xl shadow-xl max-h-[80vh]"
      >
        <div
          class="flex items-center justify-between px-5 py-3 border-b border-n-weak"
        >
          <h2 class="text-sm font-semibold text-n-slate-12">
            {{ t('CRM.COMMISSION.DETAIL.IMPORT_ORDERS') }}
          </h2>
          <button
            class="text-n-slate-10 hover:text-n-slate-12"
            @click="showOrderPicker = false"
          >
            <Icon icon="i-lucide-x" class="size-5" />
          </button>
        </div>
        <div class="px-5 py-3 border-b border-n-weak">
          <input
            v-model="pickerSearch"
            :placeholder="t('CRM.COMMISSION.DETAIL.PICKER_SEARCH')"
            class="w-full h-8 px-3 text-sm border rounded-lg reset-base border-n-weak bg-n-solid-1 text-n-slate-12"
          />
        </div>
        <div class="flex-1 overflow-y-auto">
          <table class="min-w-full text-xs">
            <thead
              class="sticky top-0 text-n-slate-11 bg-n-solid-1 border-b border-n-weak"
            >
              <tr>
                <th class="w-8 px-3 py-2">
                  <input
                    type="checkbox"
                    class="accent-n-iris-9"
                    :checked="allPickerSelected"
                    @change="togglePickAll"
                  />
                </th>
                <th class="px-2 py-2 font-medium text-left">
                  {{ t('CRM.COMMISSION.COLS.ORDER_NO') }}
                </th>
                <th class="px-2 py-2 font-medium text-left">
                  {{ t('CRM.COMMISSION.COLS.CUSTOMER') }}
                </th>
                <th class="px-2 py-2 font-medium text-left">
                  {{ t('CRM.COMMISSION.COLS.COUNTRY') }}
                </th>
                <th class="px-2 py-2 font-medium text-right">
                  {{ t('CRM.COMMISSION.COLS.ORDER_AMOUNT') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="o in filteredPickerOrders"
                :key="o.id"
                class="border-b cursor-pointer border-n-weak hover:bg-n-alpha-1"
                @click="togglePick(o.id)"
              >
                <td class="px-3 py-2" @click.stop>
                  <input
                    type="checkbox"
                    class="accent-n-iris-9"
                    :checked="pickerSelected.includes(o.id)"
                    @change="togglePick(o.id)"
                  />
                </td>
                <td class="px-2 py-1.5 text-n-slate-12">
                  {{ o.orderNo || '—' }}
                </td>
                <td class="px-2 py-1.5">{{ o.customerName || '—' }}</td>
                <td class="px-2 py-1.5">{{ o.country || '—' }}</td>
                <td class="px-2 py-1.5 text-right tabular-nums">
                  {{ o.currency }} {{ pickerYuan(o.amountMicros) }}
                </td>
              </tr>
              <tr v-if="!pickerBusy && !filteredPickerOrders.length">
                <td colspan="5" class="px-3 py-6 text-center text-n-slate-10">
                  {{ t('CRM.COMMISSION.DETAIL.PICKER_EMPTY') }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <div
          class="flex flex-wrap items-center justify-between px-5 py-3 gap-y-2 border-t border-n-weak"
        >
          <div class="flex items-center gap-2">
            <span class="text-xs whitespace-nowrap text-n-slate-10">
              {{
                t('CRM.COMMISSION.DETAIL.PICKER_SELECTED', {
                  n: pickerSelected.length,
                })
              }}
            </span>
            <span class="text-xs whitespace-nowrap text-n-slate-11">
              {{ t('CRM.COMMISSION.DETAIL.PICKER_AS_CATEGORY') }}
            </span>
            <select
              v-model="pickerCategory"
              class="h-8 py-0 px-6 mb-0 text-sm leading-8 text-center border rounded-lg reset-base w-32 border-n-weak bg-n-solid-1 text-n-slate-12"
            >
              <option v-for="c in PRODUCT_CATEGORIES" :key="c" :value="c">
                {{ c }}
              </option>
            </select>
          </div>
          <div class="flex items-center gap-2">
            <button
              class="h-8 px-3 text-sm rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
              @click="showOrderPicker = false"
            >
              {{ t('CRM.COMMISSION.DETAIL.CANCEL') }}
            </button>
            <button
              class="h-8 px-4 text-sm font-medium text-white rounded-lg bg-gradient-to-br from-n-iris-9 to-n-accent-grad hover:brightness-105 disabled:opacity-50"
              :disabled="pickerBusy || !pickerSelected.length"
              @click="importSelectedOrders"
            >
              {{ t('CRM.COMMISSION.DETAIL.IMPORT_CONFIRM') }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <CrmForwardToTeamChatDialog ref="forwardRef" />
  </div>
</template>
