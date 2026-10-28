<script setup>
import { ref, reactive, computed, watch, nextTick, onMounted } from 'vue';
import { STATUS_TONE, STATUS_VOID } from 'dashboard/helper/statusTone';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useErpVouchersStore } from 'dashboard/stores/erp/vouchers';
import { useErpLedgerAccountsStore } from 'dashboard/stores/erp/ledgerAccounts';
import { useErpRole } from 'dashboard/composables/useErpRole';
import ErpVoucherAPI from 'dashboard/api/erp/vouchers';
import TableHeaderFilter from 'dashboard/components-next/tablefilter/TableHeaderFilter.vue';
import { exportRowsToExcel, fetchAllRows } from 'dashboard/helper/erpExcel';
import ErpAutoVoucherRuleAPI from 'dashboard/api/erp/autoVoucherRules';
import ErpReportAPI from 'dashboard/api/erp/reports';
import ErpVoucherTemplateAPI from 'dashboard/api/erp/voucherTemplates';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import MonthPicker from 'dashboard/components-next/monthpicker/MonthPicker.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import ErpDimensionFields from 'dashboard/components-next/erp/ErpDimensionFields.vue';
import ErpAmountCells from 'dashboard/components-next/erp/ErpAmountCells.vue';
import ErpVoucherPrintSheet from 'dashboard/components-next/erp/ErpVoucherPrintSheet.vue';
import { printElement } from 'dashboard/helper/printHelper';
import { downloadBlob } from 'dashboard/helper/erpDownload';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
// 记账凭证：手工凭证录入 + 过账 / 红冲 / 作废。
// 硬规则在后端（借贷本位币必平才能过账；已记账不可改删只能红冲），前端只做录入体验与显隐。
const store = useErpVouchersStore();
const accountStore = useErpLedgerAccountsStore();
const { erpCan } = useErpRole();
const canWrite = computed(() => erpCan('voucher'));

const ITEMS_PER_PAGE = 15;
const records = computed(() => store.getRecords);
const totalCount = computed(() => Number(store.getMeta?.count || 0));
const isFetching = computed(() => store.getUIFlags.fetchingList);
const saving = computed(
  () => store.getUIFlags.creatingItem || store.getUIFlags.updatingItem
);

const STATUS_OPTIONS = [
  { value: '', label: '全部状态' },
  { value: 'DRAFT', label: '待过账' },
  { value: 'POSTED', label: '已记账' },
  { value: 'VOID', label: '已作废' },
];
const STATUS_CLASS = {
  DRAFT: STATUS_TONE.idle,
  POSTED: STATUS_TONE.done,
  VOID: STATUS_VOID,
};
// 金额格的位名表头，跟 ErpAmountCells 的格子一一对齐。
const AMOUNT_UNITS = [
  '兆',
  '千',
  '百',
  '十',
  '亿',
  '千',
  '百',
  '十',
  '万',
  '千',
  '百',
  '十',
  '元',
  '角',
  '分',
];
const CURRENCIES = [
  { value: 'CNY', label: '人民币 CNY' },
  { value: 'USD', label: '美元 USD' },
  { value: 'EUR', label: '欧元 EUR' },
];

const money = micros =>
  micros == null
    ? '—'
    : (micros / 1_000_000).toLocaleString('zh-CN', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      });
const toMicros = value => Math.round(Number(value || 0) * 1_000_000);

const period = ref('');
const statusFilter = ref('');
const keyword = ref('');
const currentPage = ref(1);

// 表头漏斗筛选（对标金蝶）：{ 列名: { op, value } }，在服务端按列筛。
// 不在前端筛当前这一页——列表是分页的，筛 50 行说「没有」，翻到第二页它又在。
// 期间和状态不进表头：工具栏已经有那两个下拉，同一个条件两个入口只会让人以为坏了。
const colFilters = ref({});
// axios 默认序列化器把嵌套对象拍成 "[object Object]"，所以自己展开成
// cf[列][op] / cf[列][value]——Rails 按方括号解回嵌套 params（同应付台账）。
const colFilterParams = () => {
  const out = {};
  Object.entries(colFilters.value).forEach(([key, f]) => {
    if (!f?.op) return;
    out[`cf[${key}][op]`] = f.op;
    out[`cf[${key}][value]`] = f.value ?? '';
  });
  return out;
};

// 「刚生成的那张在哪」：自动凭证的凭证日期取来源单据的日期，今天给上个月的入库单
// 生成凭证，按凭证日期排它就沉到第五六页去了（用户原话：「一共有12页，他生成了，
// 我不知道他在第几页，找半天找不到」）。所以给两个出口：
//   showCreatedToday —— 只看今天生成的，一键到位
//   sortByCreated    —— 整个列表改按生成时间排
const showCreatedToday = ref(false);
const sortByCreated = ref(false);

const fetchList = () =>
  store.get({
    page: currentPage.value,
    period: period.value,
    status: statusFilter.value,
    q: keyword.value.trim(),
    ...(showCreatedToday.value ? { created_today: 1 } : {}),
    ...(sortByCreated.value ? { sort: 'created' } : {}),
    ...colFilterParams(),
  });

watch(currentPage, fetchList);
const resetAndFetch = () => {
  currentPage.value = 1;
  fetchList();
};

const toggleCreatedToday = () => {
  showCreatedToday.value = !showCreatedToday.value;
  // 看「今天生成的」时自然要按生成时间排，否则还是按凭证日期乱序摆着。
  sortByCreated.value = showCreatedToday.value || sortByCreated.value;
  resetAndFetch();
};

const toggleSortByCreated = () => {
  sortByCreated.value = !sortByCreated.value;
  resetAndFetch();
};
const activeColFilterCount = computed(
  () => Object.values(colFilters.value).filter(f => f?.op).length
);
const clearColFilters = () => {
  colFilters.value = {};
  resetAndFetch();
};

// 科目下拉：只给启用中的末级科目（分类科目不能记账，后端也会拦）。
const leafAccounts = computed(() =>
  accountStore.getRecords.filter(a => !a.isGroup && a.isActive)
);
const accountOptions = computed(() =>
  leafAccounts.value.map(a => ({ value: a.id, label: `${a.code} ${a.name}` }))
);
const accountById = id => leafAccounts.value.find(a => a.id === id);
// 自动凭证规则里的科目下拉：允许留空＝交给系统按科目类型/国标编码自动找。
const ruleAccountOptions = computed(() => [
  // 标签要短：十来个下拉并排，长文案每一个都被截成「自动（按科目类型 …」，一眼看过去全是省略号。
  { value: '', label: '自动匹配' },
  ...accountOptions.value,
]);

// 新建凭证默认几行。原来 2 行，财务要 8 行——一张单据十几笔分录是常态，
// 每次点七八下「加一行」很烦。空行在保存时会被剔掉（见 payload 的 filter），
// 不会因为摆了 8 行就逼着人填满。
const DEFAULT_LINE_COUNT = 8;
const blankLines = () => Array.from({ length: DEFAULT_LINE_COUNT }, () => blankLine());

const blankLine = () => ({
  id: null,
  ledgerAccountId: '',
  summary: '',
  debit: '',
  credit: '',
  currency: 'CNY',
  exchangeRate: 1,
  crmCustomerId: '',
  mesSupplierId: '',
  crmSalesOrderId: '',
  departmentId: '',
  memberId: '',
  cashFlowItem: '',
});

// 现金流量项目：只有货币资金科目的分录才要，留空＝现金流量表按对方科目自动判定。
const CASH_TYPES = ['CASH', 'BANK'];
const cashFlowItemOptions = ref([]);
const isCashLine = line =>
  CASH_TYPES.includes(accountById(line.ledgerAccountId)?.accountType);
const loadCashFlowItems = async () => {
  const { data } = await ErpReportAPI.cashFlowItems();
  cashFlowItemOptions.value = (data?.payload || []).map(item => ({
    value: item.code,
    label: `${item.section_label.slice(2, 4)}·${item.label}`,
  }));
};

/* 常用摘要：从已录分录的摘要里按使用频次取，绑到摘要输入框的 datalist 上 */
const summaryOptions = ref([]);
const loadSummaries = async () => {
  const { data } = await ErpVoucherAPI.summaries();
  summaryOptions.value = data?.payload || [];
};

/* 凭证模板：每月重复的分录存一份，新建时一键带出 */
const templates = ref([]);
const templateOptions = computed(() => [
  { value: '', label: '不用模板' },
  ...templates.value.map(t => ({
    value: t.id,
    label: `${t.name}（${t.line_count} 行）`,
  })),
]);
const selectedTemplateId = ref('');
const loadTemplates = async () => {
  const { data } = await ErpVoucherTemplateAPI.get();
  templates.value = data?.payload || [];
};

const dialogRef = ref(null);
const editing = ref(null);
const form = reactive({
  voucherDate: new Date().toISOString().slice(0, 10),
  summary: '',
  attachmentCount: 0,
  remark: '',
  lines: blankLines(),
});
const { isDirty, markPristine } = useDirtyGuard(() => form);

const lineBase = line => {
  const amount = Number(line.debit || line.credit || 0);
  return amount * Number(line.exchangeRate || 1);
};
const totalDebit = computed(() =>
  form.lines.reduce((sum, l) => sum + (l.debit ? lineBase(l) : 0), 0)
);
const totalCredit = computed(() =>
  form.lines.reduce((sum, l) => sum + (l.credit ? lineBase(l) : 0), 0)
);
const difference = computed(() => totalDebit.value - totalCredit.value);
const balanced = computed(
  () => Math.abs(difference.value) < 0.005 && totalDebit.value > 0
);
const invalid = computed(
  () =>
    !form.voucherDate ||
    form.lines.filter(l => l.ledgerAccountId && (l.debit || l.credit)).length <
      2
);

// 一行只能是借或贷，填一边自动清另一边。
const onDebitInput = line => {
  if (line.debit) line.credit = '';
};
const onCreditInput = line => {
  if (line.credit) line.debit = '';
};
// 这行有没有东西要在表格下面展开：外币、辅助核算维度、现金流量项目。
const lineNeedsExtra = line =>
  line.currency !== 'CNY' ||
  isCashLine(line) ||
  (accountById(line.ledgerAccountId)?.dimensions || []).length > 0;

// 选到外币科目时自动跟随科目币种（后端会校验币种须一致）。
const onAccountChange = line => {
  const account = accountById(line.ledgerAccountId);
  if (account?.currency) line.currency = account.currency;
  else line.currency = 'CNY';
  if (line.currency === 'CNY') line.exchangeRate = 1;
};

// ── 原始单据影像 ──
// 「附单据(张)」原来只是个数字（照纸质凭证的习惯填张数），发票/水单实际传不上来。
// 新建时没有凭证 id，先把文件暂存成 blob 拿 signed_id，保存时一并挂上（同 PI、质检那套）；
// 编辑已存在的凭证则直接走 attach / detach。
const docInputRef = ref(null);
const stagedDocs = ref([]); // 新建/本次新选的：{ name, signedId }
const savedDocs = ref([]); // 已挂在凭证上的：{ id, filename, url }
const uploadingDoc = ref(false);

const triggerDocPick = () => docInputRef.value?.click();

const onDocPick = async e => {
  const files = [...(e.target.files || [])];
  e.target.value = '';
  if (!files.length) return;
  uploadingDoc.value = true;
  try {
    // 逐个顺序传：一批里有一个失败，已成功的那些不该跟着丢。
    await files.reduce(
      (chain, file) =>
        chain.then(async () => {
          const { data } = await ErpVoucherAPI.stageBlob(file);
          stagedDocs.value.push({
            name: data.filename,
            signedId: data.signed_id,
          });
        }),
      Promise.resolve()
    );
    // 张数跟着附件走，省得两处对不上（人工还能再改）。
    form.attachmentCount = savedDocs.value.length + stagedDocs.value.length;
  } catch (error) {
    useAlert(error?.message || '上传失败');
  } finally {
    uploadingDoc.value = false;
  }
};

const removeStagedDoc = i => {
  stagedDocs.value.splice(i, 1);
  form.attachmentCount = savedDocs.value.length + stagedDocs.value.length;
};

const removeSavedDoc = async doc => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`删除附件「${doc.filename}」？`)) return;
  try {
    await ErpVoucherAPI.detach(editing.value.id, doc.id);
    savedDocs.value = savedDocs.value.filter(d => d.id !== doc.id);
    form.attachmentCount = savedDocs.value.length + stagedDocs.value.length;
  } catch (error) {
    useAlert(error?.message || '删除失败');
  }
};

const openCreate = () => {
  stagedDocs.value = [];
  savedDocs.value = [];
  editing.value = null;
  selectedTemplateId.value = '';
  Object.assign(form, {
    voucherDate: new Date().toISOString().slice(0, 10),
    summary: '',
    attachmentCount: 0,
    remark: '',
    lines: blankLines(),
  });
  markPristine();
  dialogRef.value?.open();
};

// 套模板：只带科目/方向/摘要/维度，金额留空等着填（每月金额本来就不一样）。
const applyTemplate = id => {
  const template = templates.value.find(t => t.id === id);
  if (!template) return;
  form.summary = template.summary || form.summary;
  form.lines = template.lines.map(line => ({
    ...blankLine(),
    ledgerAccountId: line.ledger_account_id,
    summary: line.summary || '',
    debit:
      line.direction === 'DEBIT' && line.amount_micros
        ? line.amount_micros / 1_000_000
        : '',
    credit:
      line.direction === 'CREDIT' && line.amount_micros
        ? line.amount_micros / 1_000_000
        : '',
    currency: line.currency || 'CNY',
    exchangeRate: Number(line.exchange_rate || 1),
    crmCustomerId: line.crm_customer_id || '',
    mesSupplierId: line.mes_supplier_id || '',
    crmSalesOrderId: line.crm_sales_order_id || '',
    departmentId: line.department_id || '',
    memberId: line.member_id || '',
    cashFlowItem: line.cash_flow_item || '',
  }));
};

const saveAsTemplate = async () => {
  // eslint-disable-next-line no-alert
  const name = window.prompt('模板名称', form.summary || '');
  if (!name) return;
  try {
    await ErpVoucherTemplateAPI.create({
      template: {
        name,
        summary: form.summary,
        lines: form.lines
          .filter(l => l.ledgerAccountId)
          .map(l => ({
            ledger_account_id: l.ledgerAccountId,
            direction: l.debit ? 'DEBIT' : 'CREDIT',
            summary: l.summary,
            currency: l.currency,
            exchange_rate: l.exchangeRate,
            crm_customer_id: l.crmCustomerId || null,
            mes_supplier_id: l.mesSupplierId || null,
            crm_sales_order_id: l.crmSalesOrderId || null,
            department_id: l.departmentId || null,
            member_id: l.memberId || null,
            cash_flow_item: l.cashFlowItem || null,
          })),
      },
    });
    useAlert(`模板「${name}」已保存`);
    loadTemplates();
  } catch (error) {
    useAlert(
      error?.response?.data?.errors?.join('；') ||
        error?.response?.data?.error ||
        '模板保存失败'
    );
  }
};

/* CSV 批量导入：整组要么全进要么全不进，进来的一律是待过账凭证 */
const importDialogRef = ref(null);
const importFileRef = ref(null);
const importing = ref(false);
const importResult = ref(null);
const downloadImportTemplate = async () => {
  const { data } = await ErpVoucherAPI.importTemplate();
  downloadBlob(data, '凭证导入模板.csv');
};
const openImport = () => {
  importResult.value = null;
  importDialogRef.value?.open();
};
const onImportPicked = async event => {
  const file = event.target.files?.[0];
  event.target.value = '';
  if (!file) return;
  importing.value = true;
  try {
    const { data } = await ErpVoucherAPI.import(file);
    importResult.value = data;
    resetAndFetch();
  } catch (error) {
    useAlert(error?.response?.data?.error || '导入失败');
  } finally {
    importing.value = false;
  }
};

const openEdit = async voucher => {
  const { data } = await ErpVoucherAPI.show(voucher.id);
  editing.value = data;
  stagedDocs.value = [];
  savedDocs.value = data.documents || [];
  Object.assign(form, {
    voucherDate: data.voucher_date,
    summary: data.summary || '',
    attachmentCount: data.attachment_count || 0,
    remark: data.remark || '',
    lines: data.lines.map(l => ({
      id: l.id,
      ledgerAccountId: l.ledger_account_id,
      summary: l.summary || '',
      debit: l.direction === 'DEBIT' ? l.amount_micros / 1_000_000 : '',
      credit: l.direction === 'CREDIT' ? l.amount_micros / 1_000_000 : '',
      currency: l.currency,
      exchangeRate: Number(l.exchange_rate),
      crmCustomerId: l.crm_customer_id || '',
      crmCustomerName: l.crm_customer_name || '',
      mesSupplierId: l.mes_supplier_id || '',
      mesSupplierName: l.mes_supplier_name || '',
      crmSalesOrderId: l.crm_sales_order_id || '',
      crmSalesOrderNo: l.crm_sales_order_no || '',
      departmentId: l.department_id || '',
      memberId: l.member_id || '',
      cashFlowItem: l.cash_flow_item || '',
    })),
  });
  markPristine();
  dialogRef.value?.open();
};

const addLine = () => form.lines.push(blankLine());
const removeLine = index => {
  if (form.lines.length <= 2) return;
  form.lines.splice(index, 1);
};

const buildPayload = () => ({
  voucherDate: form.voucherDate,
  summary: form.summary,
  attachmentCount: Number(form.attachmentCount || 0),
  documents: stagedDocs.value.map(d => d.signedId),
  remark: form.remark,
  linesAttributes: form.lines
    .filter(l => l.ledgerAccountId && (l.debit || l.credit))
    .map((l, index) => ({
      id: l.id || undefined,
      ledgerAccountId: l.ledgerAccountId,
      direction: l.debit ? 'DEBIT' : 'CREDIT',
      summary: l.summary,
      amountMicros: toMicros(l.debit || l.credit),
      currency: l.currency,
      exchangeRate: l.exchangeRate,
      position: index,
      crmCustomerId: l.crmCustomerId || null,
      mesSupplierId: l.mesSupplierId || null,
      crmSalesOrderId: l.crmSalesOrderId || null,
      departmentId: l.departmentId || null,
      memberId: l.memberId || null,
      cashFlowItem: l.cashFlowItem || null,
    })),
});

const submit = async (andPost = false) => {
  if (invalid.value) return;
  const payload = buildPayload();
  const saved = editing.value
    ? await store.update({ id: editing.value.id, ...payload })
    : await store.create(payload);
  if (!saved) return;
  if (andPost) {
    try {
      await ErpVoucherAPI.postVoucher(saved.id);
      useAlert(`凭证 ${saved.voucherNo} 已记账`);
    } catch (error) {
      useAlert(error?.response?.data?.error || '过账失败');
    }
  } else {
    useAlert(`凭证 ${saved.voucherNo} 已保存为待过账`);
  }
  dialogRef.value?.close();
  fetchList();
};

// 打印：把选中的凭证渲染进屏幕外的打印区，再交给 printHelper（提成表/考核表同款）。
// 多张时每张一页（打印版式自带 page-break-after）。
const printAreaRef = ref(null);
const printSheets = ref([]);
const printing = ref(false);
const selectedIds = ref([]);

const allSelected = computed(
  () =>
    records.value.length > 0 &&
    selectedIds.value.length === records.value.length
);
const toggleSelectAll = () => {
  selectedIds.value = allSelected.value ? [] : records.value.map(v => v.id);
};
const toggleSelect = id => {
  const index = selectedIds.value.indexOf(id);
  if (index === -1) selectedIds.value.push(id);
  else selectedIds.value.splice(index, 1);
};

// 列表接口不带分录行，打印前逐张取详情（凭证张数有限，直接并发取）。
const printVouchers = async (ids, title) => {
  if (!ids.length) return;
  printing.value = true;
  try {
    const results = await Promise.all(ids.map(id => ErpVoucherAPI.show(id)));
    printSheets.value = results.map(r => r.data);
    await nextTick();
    printElement(printAreaRef.value, title);
  } finally {
    printing.value = false;
  }
};

const printOne = voucher =>
  printVouchers(
    [voucher.id],
    `凭证 ${voucher.voucherNo || voucher.voucher_no}`
  );
const printSelected = () =>
  printVouchers(selectedIds.value, `记账凭证 ${selectedIds.value.length} 张`);

/* 自动凭证规则：收款/付款/划转落库时自动生成待过账凭证，可按事件停用。 */
const rulesRef = ref(null);
const rules = ref([]);
const openRules = async () => {
  const { data } = await ErpAutoVoucherRuleAPI.get();
  rules.value = data.payload;
  rulesRef.value?.open();
};
const toggleRule = async rule => {
  await ErpAutoVoucherRuleAPI.toggle(rule.id, !rule.is_active);
  rule.is_active = !rule.is_active;
  useAlert(`${rule.name} 已${rule.is_active ? '启用' : '停用'}`);
};

// 科目映射：留空＝按科目类型/国标编码自动找（备用金默认 1221、差旅费 660104…），
// 配了就以配的为准。改完即存，不用再点保存。
const savingRuleId = ref(null);
const setRuleAccount = async (rule, key, value) => {
  const config = { ...(rule.config || {}), [key]: value || undefined };
  savingRuleId.value = rule.id;
  try {
    const { data } = await ErpAutoVoucherRuleAPI.saveConfig(rule.id, config);
    rule.config = data.config || config;
    useAlert('科目已更新');
  } catch (e) {
    useAlert(e?.response?.data?.error || '保存失败，请重试');
  } finally {
    savingRuleId.value = null;
  }
};

const viewRef = ref(null);
const viewing = ref(null);

/* 原始单据影像：发票 / 水单扫描件，已过账凭证也能补传 */
const fileInputRef = ref(null);
const uploading = ref(false);
const pickFiles = () => fileInputRef.value?.click();
const onFilesPicked = async event => {
  const files = Array.from(event.target.files || []);
  event.target.value = '';
  if (!files.length || !viewing.value) return;
  uploading.value = true;
  try {
    const { data } = await ErpVoucherAPI.attach(viewing.value.id, files);
    viewing.value = data;
    store.get({ page: currentPage.value });
  } catch (error) {
    useAlert(error?.response?.data?.error || '上传失败');
  } finally {
    uploading.value = false;
  }
};
const removeDocument = async doc => {
  try {
    const { data } = await ErpVoucherAPI.detach(viewing.value.id, doc.id);
    viewing.value = data;
    store.get({ page: currentPage.value });
  } catch (error) {
    useAlert(error?.response?.data?.error || '删除失败');
  }
};
const fileSize = bytes =>
  bytes > 1024 * 1024
    ? `${(bytes / 1024 / 1024).toFixed(1)} MB`
    : `${Math.max(1, Math.round(bytes / 1024))} KB`;

const openView = async voucher => {
  const { data } = await ErpVoucherAPI.show(voucher.id);
  viewing.value = data;
  viewRef.value?.open();
};

const runAction = async (voucher, action, successText) => {
  try {
    await ErpVoucherAPI[action](voucher.id);
    useAlert(successText);
    fetchList();
    viewRef.value?.close();
  } catch (error) {
    useAlert(error?.response?.data?.error || '操作失败');
  }
};
const postVoucher = v =>
  runAction(v, 'postVoucher', `凭证 ${v.voucherNo} 已记账`);
const reverseVoucher = v =>
  runAction(v, 'reverse', `已生成 ${v.voucherNo} 的红冲凭证`);
const voidVoucher = v => runAction(v, 'void', `凭证 ${v.voucherNo} 已作废`);

// ── 批量过账 ──
// 自动凭证天天在产，一张一张点是「凭证天天生成、报表永远空」的最后一道人力卡口。
// 选中的里面只有待过账的能过，已过账/已作废的不算进按钮计数，免得点下去发现「过了 25 张」对不上。
const selectedDraftIds = computed(() =>
  records.value
    .filter(v => v.status === 'DRAFT' && selectedIds.value.includes(v.id))
    .map(v => v.id)
);
const bulkPostRef = ref(null);
const bulkPosting = ref(false);
const askBulkPost = () => bulkPostRef.value?.open();
const doBulkPost = async () => {
  bulkPosting.value = true;
  try {
    const { data } = await ErpVoucherAPI.bulkPost(selectedDraftIds.value);
    const { posted, failed = [], skipped = 0 } = data.payload || {};
    // 失败的要点名到凭证号——财务得照着去改，只报个「3 张失败」等于没报。
    const parts = [`已过账 ${posted} 张`];
    if (skipped) parts.push(`${skipped} 张已不是待过账状态，跳过`);
    if (failed.length) {
      parts.push(
        `${failed.length} 张没过：${failed
          .map(f => `${f.voucher_no}（${f.error}）`)
          .join('；')}`
      );
    }
    useAlert(parts.join('，'));
    selectedIds.value = [];
    fetchList();
  } catch (error) {
    useAlert(error?.response?.data?.error || '批量过账失败');
  } finally {
    bulkPosting.value = false;
  }
};

// ── 批量作废 ──
// 与批量过账同一批选中、同一套口径：只有待过账的能作废，已记账的一律不碰（错账走红冲）。
// 作废不是删除——凭证号留着不断号，审计看得见这张作废过。
const bulkVoidRef = ref(null);
const bulkVoiding = ref(false);
const askBulkVoid = () => bulkVoidRef.value?.open();
const doBulkVoid = async () => {
  bulkVoiding.value = true;
  try {
    const { data } = await ErpVoucherAPI.bulkVoid(selectedDraftIds.value);
    const { voided, failed = [], skipped = 0 } = data.payload || {};
    const parts = [`已作废 ${voided} 张`];
    if (skipped) parts.push(`${skipped} 张已不是待过账状态，跳过`);
    if (failed.length) {
      parts.push(
        `${failed.length} 张没作废：${failed
          .map(f => `${f.voucher_no}（${f.error}）`)
          .join('；')}`
      );
    }
    useAlert(parts.join('，'));
    selectedIds.value = [];
    fetchList();
  } catch (error) {
    useAlert(error?.response?.data?.error || '批量作废失败');
  } finally {
    bulkVoiding.value = false;
  }
};

const confirmRef = ref(null);
const deleting = ref(null);
const askDelete = voucher => {
  deleting.value = voucher;
  confirmRef.value?.open();
};
const doDelete = async () => {
  const ok = await store.delete(deleting.value.id);
  if (ok) {
    useAlert('凭证已删除');
    fetchList();
  }
};

const route = useRoute();

/* ---------------- 导出 Excel ---------------- */
// 导当前筛选下的凭证清单（凭证级）。分录级的明细在「账簿」页导——
// 列表接口不下发分录，这里逐张去取就是几百次请求。
// ⚠️ 全量：列表一页 15 张，导出重新向后端分页要完。
const exporting = ref(false);
const exportList = async () => {
  exporting.value = true;
  try {
    const rows = await fetchAllRows(params => ErpVoucherAPI.get(params), {
      period: period.value,
      status: statusFilter.value,
      q: keyword.value.trim(),
    });
    exportRowsToExcel(
      {
        title: '记账凭证清单',
        meta: [
          {
            label: '导出时间',
            value: new Date().toLocaleString('sv').slice(0, 16),
          },
          { label: '期间', value: period.value || '全部期间' },
          { label: '状态', value: statusFilter.value || '全部状态' },
          { label: '关键字', value: keyword.value.trim() || '（无）' },
          { label: '凭证张数', value: rows.length },
        ],
        columns: [
          { label: '凭证字号', key: 'voucher_no' },
          { label: '日期', key: 'voucher_date' },
          { label: '会计期间', key: 'period' },
          { label: '摘要', key: 'summary' },
          { label: '借方合计', key: 'total_debit_micros', money: true },
          { label: '贷方合计', key: 'total_credit_micros', money: true },
          { label: '状态', key: 'status_label' },
          { label: '制单', key: 'prepared_by_name' },
          { label: '记账', key: 'posted_by_name' },
          { label: '附件(张)', key: 'document_count', num: true },
          { label: '红冲自', key: 'reversal_of_no' },
          { label: '已被红冲', key: 'reversed_by_no' },
        ],
        rows,
      },
      `记账凭证清单_${new Date().toLocaleDateString('sv')}`
    );
  } catch (error) {
    useAlert('导出失败，请重试');
  } finally {
    exporting.value = false;
  }
};

onMounted(() => {
  // 从账簿明细账点凭证号跳过来时带 ?q=字号，直接过滤到那张凭证。
  if (route.query.q) keyword.value = String(route.query.q);
  fetchList();
  if (!accountStore.getRecords.length) accountStore.get({});
  loadCashFlowItems();
  loadSummaries();
  loadTemplates();
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div
      class="flex items-center justify-between gap-3 px-6 py-4 [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8"
    >
      <div class="flex items-center gap-2">
        <div class="i-lucide-book-text size-5 text-n-iris-9" />
        <h1
          class="text-xl font-semibold text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8"
        >
          记账凭证
        </h1>
        <span class="text-sm text-n-slate-11">共 {{ totalCount }} 张</span>
      </div>
      <div class="flex items-center gap-2">
        <Input
          v-model="keyword"
          size="sm"
          placeholder="搜字号 / 摘要"
          custom-input-class="w-48"
          @keyup.enter="resetAndFetch"
        />
        <!-- 漏斗筛了几列就显示几，点一下全清——逐列点回「重置」太费事（同应付台账） -->
        <Button
          v-if="activeColFilterCount"
          :label="`清除筛选 (${activeColFilterCount})`"
          variant="ghost"
          color="ruby"
          size="sm"
          @click="clearColFilters"
        />
        <Button label="查询" color="slate" size="sm" @click="resetAndFetch" />
        <!-- 刚生成的凭证按「凭证日期」排会沉到后面几页，这两个按钮是找它的出口。 -->
        <Button
          :label="showCreatedToday ? '只看今天生成 ✓' : '今天生成'"
          :color="showCreatedToday ? 'iris' : 'slate'"
          :variant="showCreatedToday ? 'solid' : 'faded'"
          size="sm"
          @click="toggleCreatedToday"
        />
        <Button
          :label="sortByCreated ? '按生成时间排 ✓' : '按生成时间排'"
          :color="sortByCreated ? 'iris' : 'slate'"
          :variant="sortByCreated ? 'solid' : 'faded'"
          size="sm"
          @click="toggleSortByCreated"
        />
        <!-- 导出是只读动作，不挂写权限 -->
        <Button
          label="导出 Excel"
          color="slate"
          variant="faded"
          size="sm"
          :is-loading="exporting"
          @click="exportList"
        />
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
          v-if="canWrite && selectedDraftIds.length"
          :label="`批量过账 ${selectedDraftIds.length} 张`"
          color="iris"
          variant="faded"
          size="sm"
          :is-loading="bulkPosting"
          @click="askBulkPost"
        />
        <Button
          v-if="canWrite && selectedDraftIds.length"
          :label="`批量作废 ${selectedDraftIds.length} 张`"
          color="ruby"
          variant="faded"
          size="sm"
          :is-loading="bulkVoiding"
          @click="askBulkVoid"
        />
        <Button
          v-if="canWrite"
          label="批量导入"
          icon="i-lucide-upload"
          color="slate"
          variant="faded"
          size="sm"
          @click="openImport"
        />
        <Button
          v-if="canWrite"
          label="自动凭证规则"
          color="slate"
          variant="faded"
          size="sm"
          @click="openRules"
        />
        <Button
          v-if="canWrite"
          label="新建凭证"
          color="iris"
          size="sm"
          @click="openCreate"
        />
      </div>
    </div>

    <div
      class="flex items-center gap-2 px-6 pb-3 [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8"
    >
      <MonthPicker
        v-model="period"
        placeholder="全部期间"
        trigger-class="w-36 h-9"
        @update:model-value="resetAndFetch"
      />
      <SelectCard
        v-model="statusFilter"
        :options="STATUS_OPTIONS"
        @update:model-value="resetAndFetch"
      />
    </div>

    <HScrollButtons />
    <div
      class="flex-1 min-h-0 px-6 pb-6 overflow-auto [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8"
    >
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <template v-else>
        <!-- 除摘要外各列都是 nowrap，窗口一窄就只能挤摘要（挤成几行窄条）。
             给表格设最小宽度并单独包一层横向滚动：宽度不够就往右拉，摘要不再被压。
             滚动只包表格、不包分页条，否则往右拉时分页也跟着跑出去。 -->
        <HScrollButtons />
        <div class="overflow-x-auto">
          <table class="w-full min-w-[1200px] text-sm">
            <thead>
              <tr class="text-left text-n-slate-11 border-b border-n-weak">
                <th class="px-3 py-3 font-medium w-9 whitespace-nowrap">
                  <input
                    type="checkbox"
                    class="w-4 h-4"
                    :checked="allSelected"
                    @change="toggleSelectAll"
                  />
                </th>
                <th class="px-3 py-3 font-medium whitespace-nowrap">
                  <span class="inline-flex items-center gap-1">
                    凭证字号
                    <TableHeaderFilter
                      v-model="colFilters.voucher_no"
                      @change="resetAndFetch"
                    />
                  </span>
                </th>
                <th class="px-3 py-3 font-medium whitespace-nowrap">日期</th>
                <th class="px-3 py-3 font-medium whitespace-nowrap">
                  <span class="inline-flex items-center gap-1">
                    摘要
                    <TableHeaderFilter
                      v-model="colFilters.summary"
                      @change="resetAndFetch"
                    />
                  </span>
                </th>
                <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
                  借方合计
                </th>
                <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
                  贷方合计
                </th>
                <th class="px-3 py-3 font-medium whitespace-nowrap">状态</th>
                <th class="px-3 py-3 font-medium whitespace-nowrap">
                  <!-- 一列两个人名，所以两个漏斗，各自紧跟在自己那个词后面。
                       两个挨在一起（制单 / 记账 ∨∨）谁也分不清哪个筛哪个。 -->
                  <span class="inline-flex items-center gap-1">
                    制单
                    <TableHeaderFilter
                      v-model="colFilters.prepared_by"
                      @change="resetAndFetch"
                    />
                    <span class="text-n-slate-10">/</span>
                    记账
                    <TableHeaderFilter
                      v-model="colFilters.posted_by"
                      @change="resetAndFetch"
                    />
                  </span>
                </th>
                <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
                  操作
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="v in records"
                :key="v.id"
                class="border-b cursor-pointer border-n-weak hover:bg-n-alpha-1"
                @click="openView(v)"
              >
                <td class="px-3 py-2" @click.stop>
                  <input
                    type="checkbox"
                    class="w-4 h-4"
                    :checked="selectedIds.includes(v.id)"
                    @change="toggleSelect(v.id)"
                  />
                </td>
                <td
                  class="px-3 py-2 font-mono whitespace-nowrap text-n-slate-12"
                >
                  {{ v.voucherNo }}
                  <span v-if="v.reversalOfNo" class="text-xs text-n-ruby-11">
                    红冲 {{ v.reversalOfNo }}
                  </span>
                  <span
                    v-else-if="v.reversedByNo"
                    class="text-xs text-n-slate-10"
                  >
                    已被 {{ v.reversedByNo }} 红冲
                  </span>
                </td>
                <td class="px-3 py-2 whitespace-nowrap text-n-slate-11">
                  {{ v.voucherDate }}
                </td>
                <td class="px-3 py-2 text-n-slate-12">
                  <!-- 下限撑住不被挤扁，上限截断防超长摘要把表拉到几屏宽；全文走 title 悬浮看。 -->
                  <div class="flex items-center gap-1 min-w-56 max-w-96">
                    <span class="truncate" :title="v.summary || ''">
                      {{ v.summary || '—' }}
                    </span>
                    <span
                      v-if="v.documentCount"
                      class="inline-flex items-center gap-0.5 text-xs shrink-0 text-n-slate-10"
                      title="已附原始单据影像"
                    >
                      <span class="i-lucide-paperclip size-3" />
                      {{ v.documentCount }}
                    </span>
                  </div>
                </td>
                <td class="px-3 py-2 font-mono text-right text-n-slate-12">
                  {{ money(v.totalDebitMicros) }}
                </td>
                <td class="px-3 py-2 font-mono text-right text-n-slate-12">
                  {{ money(v.totalCreditMicros) }}
                </td>
                <td class="px-3 py-2">
                  <span
                    class="inline-block px-2 py-0.5 text-xs rounded whitespace-nowrap"
                    :class="STATUS_CLASS[v.status]"
                  >
                    {{ v.statusLabel }}
                  </span>
                </td>
                <td class="px-3 py-2 whitespace-nowrap text-n-slate-11">
                  {{ v.preparedByName || '—' }} / {{ v.postedByName || '—' }}
                </td>
                <td class="px-3 py-2" @click.stop>
                  <div class="flex items-center justify-end gap-1">
                    <Button
                      label="打印"
                      color="slate"
                      variant="ghost"
                      size="xs"
                      @click="printOne(v)"
                    />
                    <!-- 已作废的也能删：作废只对草稿开放，所以 VOID 那张从没进过账，
                         删了不影响任何余额。已记账(POSTED)永远只能红冲。 -->
                    <Button
                      v-if="canWrite && v.status === 'VOID'"
                      label="删除"
                      color="ruby"
                      variant="ghost"
                      size="xs"
                      @click="askDelete(v)"
                    />
                    <template v-if="canWrite && v.status === 'DRAFT'">
                      <Button
                        label="过账"
                        color="teal"
                        variant="ghost"
                        size="xs"
                        @click="postVoucher(v)"
                      />
                      <Button
                        label="编辑"
                        color="slate"
                        variant="ghost"
                        size="xs"
                        @click="openEdit(v)"
                      />
                      <Button
                        label="作废"
                        color="slate"
                        variant="ghost"
                        size="xs"
                        @click="voidVoucher(v)"
                      />
                      <Button
                        label="删除"
                        color="ruby"
                        variant="ghost"
                        size="xs"
                        @click="askDelete(v)"
                      />
                    </template>
                    <!-- 已记账：红冲和删除并列，两个都给。
                         红冲是常用的更正方式（留痕、凭证号不断），不能被删除挤掉；
                         删除是财务要求补的，后端还会按「期间已结账 / 已被红冲 /
                         自己是红冲单」三种情况拦住并给出具体理由（见 Voucher#delete_blocker）。 -->
                    <template v-if="canWrite && v.status === 'POSTED'">
                      <Button
                        v-if="!v.reversedByNo"
                        label="红冲"
                        color="ruby"
                        variant="ghost"
                        size="xs"
                        @click="reverseVoucher(v)"
                      />
                      <Button
                        v-if="!v.reversedByNo && !v.reversalOfNo"
                        label="删除"
                        color="ruby"
                        variant="ghost"
                        size="xs"
                        @click="askDelete(v)"
                      />
                    </template>
                  </div>
                </td>
              </tr>
              <tr v-if="!records.length">
                <td colspan="9" class="px-3 py-10 text-center text-n-slate-11">
                  该期间还没有凭证。点右上角「新建凭证」开始记账。
                </td>
              </tr>
            </tbody>
          </table>
        </div>

      </template>
    </div>

    <!-- 与应收/应付台账同一口径：翻页器放滚动区外面常驻，条数 >0 就画。
         放里面它会跟着表格一起滚走＝用户眼里「没有页码」。 -->
    <PaginationFooter
      v-if="!isFetching && totalCount > 0"
      :current-page="currentPage"
      :total-items="totalCount"
      :items-per-page="ITEMS_PER_PAGE"
      class="shrink-0 !bg-transparent before:!hidden"
      @update:current-page="currentPage = $event"
    />

    <!-- 录入 / 编辑 -->
    <Dialog
      ref="dialogRef"
      width="5xl"
      :title="editing ? `编辑凭证 ${editing.voucher_no}` : '新建记账凭证'"
      :show-confirm-button="false"
      :show-cancel-button="false"
      :dirty="isDirty"
      dirty-save-label="存草稿"
      :disable-confirm-button="invalid"
      @close="markPristine"
      @save="submit(false)"
    >
      <div class="flex flex-col gap-4">
        <!-- 常用摘要联想：摘要输入框靠 list 属性接这里 -->
        <datalist id="erp-summary-options">
          <option v-for="item in summaryOptions" :key="item" :value="item" />
        </datalist>

        <div class="flex flex-wrap items-end gap-4">
          <div v-if="!editing" class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">套用模板</label>
            <SelectCard
              v-model="selectedTemplateId"
              :options="templateOptions"
              @update:model-value="applyTemplate"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">凭证日期</label>
            <DatePicker v-model="form.voucherDate" :clearable="false" />
          </div>
          <div class="flex flex-col flex-1 gap-1 min-w-52">
            <label class="text-heading-3 text-n-slate-12">凭证事由</label>
            <Input
              v-model="form.summary"
              size="sm"
              custom-input-class="!h-9"
              list="erp-summary-options"
            />
          </div>
          <div class="flex flex-col gap-1 w-28">
            <label class="text-heading-3 text-n-slate-12">附单据(张)</label>
            <Input
              v-model="form.attachmentCount"
              size="sm"
              type="number"
              custom-input-class="!h-9"
            />
          </div>
        </div>

        <!-- 原始单据影像：张数那栏只是个数字（照纸质凭证的习惯填），发票/水单传这里。
             新建时文件先暂存，保存凭证时一并挂上；编辑时点「×」直接从凭证上摘掉。 -->
        <div class="flex flex-wrap items-center gap-2">
          <span class="text-heading-3 text-n-slate-12">原始单据</span>
          <Button
            label="上传发票 / 水单"
            icon="i-lucide-paperclip"
            color="slate"
            variant="faded"
            size="xs"
            :is-loading="uploadingDoc"
            @click="triggerDocPick"
          />
          <input
            ref="docInputRef"
            type="file"
            multiple
            class="hidden"
            accept="image/*,.pdf"
            @change="onDocPick"
          />
          <a
            v-for="doc in savedDocs"
            :key="`saved-${doc.id}`"
            :href="doc.url"
            target="_blank"
            rel="noopener noreferrer"
            class="inline-flex items-center gap-1 px-2 py-1 text-xs rounded bg-n-alpha-1 text-n-slate-11 hover:text-n-slate-12"
          >
            <span class="max-w-[12rem] truncate">{{ doc.filename }}</span>
            <button
              type="button"
              class="shrink-0 i-lucide-x size-3 hover:text-n-ruby-11"
              @click.prevent.stop="removeSavedDoc(doc)"
            />
          </a>
          <span
            v-for="(doc, i) in stagedDocs"
            :key="`staged-${i}`"
            class="inline-flex items-center gap-1 px-2 py-1 text-xs rounded bg-n-amber-2 text-n-amber-11"
          >
            <span class="max-w-[12rem] truncate">{{ doc.name }}</span>
            <button
              type="button"
              class="shrink-0 i-lucide-x size-3 hover:text-n-ruby-11"
              @click="removeStagedDoc(i)"
            />
          </span>
          <span
            v-if="!savedDocs.length && !stagedDocs.length"
            class="text-xs text-n-slate-10"
          >
            还没传单据
          </span>
        </div>

        <!-- 记账凭证表格：序号 | 摘要 | 科目 | 借方 | 贷方，金额按位分格（同金蝶/用友）。
             辅助核算（客户/供应商/订单）、外币汇率、现金流量项目不占主表的列——
             哪行需要就在那行下面展开一小条，主表保持财务看惯的样子。 -->
        <div class="flex flex-col gap-2">
          <div class="overflow-x-auto">
            <table class="w-full min-w-[920px] border-collapse">
              <thead>
                <tr class="text-xs text-n-slate-11">
                  <th
                    rowspan="2"
                    class="w-10 p-1 font-medium border border-n-weak bg-n-alpha-1"
                  >
                    序号
                  </th>
                  <th
                    rowspan="2"
                    class="p-1 font-medium border w-52 border-n-weak bg-n-alpha-1"
                  >
                    摘要
                  </th>
                  <th
                    rowspan="2"
                    class="p-1 font-medium border w-60 border-n-weak bg-n-alpha-1"
                  >
                    科目
                  </th>
                  <th class="p-1 font-medium border border-n-weak bg-n-alpha-1">
                    借方
                  </th>
                  <th class="p-1 font-medium border border-n-weak bg-n-alpha-1">
                    贷方
                  </th>
                  <th
                    rowspan="2"
                    class="w-8 p-1 border border-n-weak bg-n-alpha-1"
                  />
                </tr>
                <tr class="text-[10px] text-n-slate-10">
                  <th class="p-0 font-normal border border-n-weak bg-n-alpha-1">
                    <div class="flex">
                      <span
                        v-for="(u, i) in AMOUNT_UNITS"
                        :key="`d${i}`"
                        class="flex-1 min-w-0 py-0.5 border-r border-n-weak last:border-r-0"
                      >
                        {{ u }}
                      </span>
                    </div>
                  </th>
                  <th class="p-0 font-normal border border-n-weak bg-n-alpha-1">
                    <div class="flex">
                      <span
                        v-for="(u, i) in AMOUNT_UNITS"
                        :key="`c${i}`"
                        class="flex-1 min-w-0 py-0.5 border-r border-n-weak last:border-r-0"
                      >
                        {{ u }}
                      </span>
                    </div>
                  </th>
                </tr>
              </thead>
              <tbody>
                <template v-for="(line, index) in form.lines" :key="index">
                  <tr>
                    <td
                      class="p-1 text-xs text-center border text-n-slate-11 border-n-weak"
                    >
                      {{ index + 1 }}
                    </td>
                    <td class="p-1 border border-n-weak">
                      <Input
                        v-model="line.summary"
                        size="sm"
                        placeholder="摘要"
                        list="erp-summary-options"
                      />
                    </td>
                    <td class="p-1 border border-n-weak">
                      <ComboBox
                        v-model="line.ledgerAccountId"
                        :options="accountOptions"
                        placeholder="选会计科目"
                        @update:model-value="onAccountChange(line)"
                      />
                    </td>
                    <td class="p-0 border border-n-weak">
                      <ErpAmountCells
                        v-model="line.debit"
                        @input="onDebitInput(line)"
                      />
                    </td>
                    <td class="p-0 border border-n-weak">
                      <ErpAmountCells
                        v-model="line.credit"
                        @input="onCreditInput(line)"
                      />
                    </td>
                    <td class="p-0 text-center border border-n-weak">
                      <button
                        class="flex items-center justify-center mx-auto size-7 text-n-slate-11 hover:text-n-ruby-11 disabled:opacity-40"
                        :disabled="form.lines.length <= 2"
                        @click="removeLine(index)"
                      >
                        <div class="i-lucide-trash-2 size-3.5" />
                      </button>
                    </td>
                  </tr>

                  <!-- 该行的辅助核算 / 外币 / 现金流量：只在需要时出现，不占主表的列 -->
                  <tr v-if="lineNeedsExtra(line)">
                    <td class="border border-n-weak bg-n-alpha-1/40" />
                    <td
                      colspan="5"
                      class="p-2 border border-n-weak bg-n-alpha-1/40"
                    >
                      <div class="flex flex-col gap-2">
                        <div
                          v-if="line.currency !== 'CNY'"
                          class="flex items-center gap-2 text-xs text-n-slate-11"
                        >
                          <span>币种</span>
                          <div class="w-32">
                            <SelectCard
                              v-model="line.currency"
                              :options="CURRENCIES"
                              block
                            />
                          </div>
                          <span>汇率</span>
                          <div class="w-24">
                            <Input
                              v-model="line.exchangeRate"
                              size="sm"
                              type="number"
                            />
                          </div>
                          <span>
                            折本位币
                            {{
                              money(
                                toMicros(
                                  Number(line.debit || line.credit || 0) *
                                    Number(line.exchangeRate || 1)
                                )
                              )
                            }}
                          </span>
                        </div>

                        <ErpDimensionFields
                          v-model="form.lines[index]"
                          :dimensions="
                            accountById(line.ledgerAccountId)?.dimensions || []
                          "
                          :required-dimension="
                            { RECEIVABLE: 'customer', PAYABLE: 'supplier' }[
                              accountById(line.ledgerAccountId)?.accountType
                            ] || ''
                          "
                        />

                        <div
                          v-if="isCashLine(line)"
                          class="flex items-center gap-1.5"
                        >
                          <span
                            class="text-xs whitespace-nowrap text-n-slate-11"
                          >
                            现金流量项目
                          </span>
                          <div class="w-72">
                            <ComboBox
                              v-model="line.cashFlowItem"
                              :options="cashFlowItemOptions"
                              placeholder="自动判定"
                            />
                          </div>
                        </div>
                      </div>
                    </td>
                  </tr>
                </template>
              </tbody>
              <tfoot>
                <tr class="text-xs">
                  <td
                    colspan="3"
                    class="p-1 font-medium text-right border border-n-weak bg-n-alpha-1"
                  >
                    合计
                  </td>
                  <td class="p-0 font-medium border border-n-weak bg-n-alpha-1">
                    <ErpAmountCells :model-value="totalDebit" disabled />
                  </td>
                  <td class="p-0 font-medium border border-n-weak bg-n-alpha-1">
                    <ErpAmountCells :model-value="totalCredit" disabled />
                  </td>
                  <td class="border border-n-weak bg-n-alpha-1" />
                </tr>
              </tfoot>
            </table>
          </div>

          <div class="flex items-center justify-between">
            <Button
              label="添加分录行"
              icon="i-lucide-plus"
              color="slate"
              variant="faded"
              size="sm"
              @click="addLine"
            />
            <div class="flex items-center gap-4 text-sm">
              <span v-if="!balanced" class="font-medium text-n-ruby-11">
                差额 {{ money(toMicros(difference)) }}
              </span>
              <span v-else class="font-medium text-n-teal-11">借贷平衡</span>
            </div>
          </div>
        </div>

        <div
          class="flex items-center justify-end gap-2 pt-2 border-t border-n-weak"
        >
          <Button
            label="存为模板"
            icon="i-lucide-bookmark"
            color="slate"
            variant="faded"
            size="sm"
            :disabled="invalid"
            @click="saveAsTemplate"
          />
          <Button
            label="取消"
            color="slate"
            variant="faded"
            size="sm"
            @click="dialogRef?.close()"
          />
          <Button
            label="保存草稿"
            color="slate"
            size="sm"
            :is-loading="saving"
            :disabled="invalid"
            @click="submit(false)"
          />
          <Button
            label="保存并过账"
            color="iris"
            size="sm"
            :is-loading="saving"
            :disabled="invalid || !balanced"
            @click="submit(true)"
          />
        </div>
      </div>
    </Dialog>

    <!-- 查看 -->
    <Dialog
      ref="viewRef"
      width="3xl"
      :title="`凭证 ${viewing?.voucher_no || ''}`"
      :show-confirm-button="false"
      cancel-button-label="关闭"
    >
      <div v-if="viewing" class="flex flex-col gap-3">
        <div class="flex flex-wrap items-center gap-4 text-sm text-n-slate-11">
          <span>日期 {{ viewing.voucher_date }}</span>
          <span>期间 {{ viewing.period }}</span>
          <span>状态 {{ viewing.status_label }}</span>
          <span>附单据 {{ viewing.attachment_count }} 张</span>
          <span>制单 {{ viewing.prepared_by_name || '—' }}</span>
          <span>记账 {{ viewing.posted_by_name || '—' }}</span>
        </div>
        <div v-if="viewing.summary" class="text-sm text-n-slate-12">
          事由：{{ viewing.summary }}
        </div>

        <table class="w-full text-sm">
          <thead>
            <tr class="text-left text-n-slate-11 border-b border-n-weak">
              <th class="px-2 py-2 font-medium whitespace-nowrap">摘要</th>
              <th class="px-2 py-2 font-medium whitespace-nowrap">会计科目</th>
              <th class="px-2 py-2 font-medium whitespace-nowrap">核算维度</th>
              <th class="px-2 py-2 font-medium text-right whitespace-nowrap">
                借方
              </th>
              <th class="px-2 py-2 font-medium text-right whitespace-nowrap">
                贷方
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="line in viewing.lines"
              :key="line.id"
              class="border-b border-n-weak"
            >
              <td class="px-2 py-2 text-n-slate-11">
                {{ line.summary || '—' }}
              </td>
              <td class="px-2 py-2 text-n-slate-12">
                {{ line.ledger_account_code }} {{ line.ledger_account_name }}
                <span
                  v-if="line.currency !== 'CNY'"
                  class="text-xs text-n-slate-10"
                >
                  {{ line.currency }} × {{ Number(line.exchange_rate) }}
                </span>
              </td>
              <!-- 客户维度照常记进库（应收账款是往来科目，账簿「按客户查应收明细账」、
                   客户对账单都靠它），只是票面上不再列出来：一行里客户名 + 业务员挤在
                   一起会折行，财务看凭证认的是业务员。见打印票面的 dimensionText。 -->
              <td class="px-2 py-2 text-xs text-n-slate-11">
                <span v-if="line.mes_supplier_name">
                  供应商 {{ line.mes_supplier_name }}
                </span>
                <span v-if="line.crm_sales_order_no">
                  订单 {{ line.crm_sales_order_no }}
                </span>
                <span v-if="line.department_name">
                  部门 {{ line.department_name }}
                </span>
                <span v-if="line.member_name">
                  业务员 {{ line.member_name }}
                </span>
              </td>
              <td class="px-2 py-2 font-mono text-right text-n-slate-12">
                {{
                  line.direction === 'DEBIT'
                    ? money(line.base_amount_micros)
                    : ''
                }}
              </td>
              <td class="px-2 py-2 font-mono text-right text-n-slate-12">
                {{
                  line.direction === 'CREDIT'
                    ? money(line.base_amount_micros)
                    : ''
                }}
              </td>
            </tr>
            <tr class="font-medium">
              <td class="px-2 py-2 text-n-slate-11" colspan="3">合计</td>
              <td class="px-2 py-2 font-mono text-right text-n-slate-12">
                {{ money(viewing.total_debit_micros) }}
              </td>
              <td class="px-2 py-2 font-mono text-right text-n-slate-12">
                {{ money(viewing.total_credit_micros) }}
              </td>
            </tr>
          </tbody>
        </table>

        <div v-if="viewing.reversal_of_no" class="text-sm text-n-ruby-11">
          本张是 {{ viewing.reversal_of_no }} 的红冲凭证
        </div>
        <div v-else-if="viewing.reversed_by_no" class="text-sm text-n-slate-11">
          本张已被 {{ viewing.reversed_by_no }} 红冲
        </div>

        <div class="pt-2 border-t border-n-weak">
          <div class="flex items-center gap-2 mb-2">
            <span class="text-sm font-medium text-n-slate-12">
              原始单据影像
            </span>
            <span class="text-xs text-n-slate-10">
              发票 / 水单扫描件，已记账凭证也可补传
            </span>
            <Button
              v-if="canWrite"
              label="上传"
              icon="i-lucide-paperclip"
              color="slate"
              variant="faded"
              size="xs"
              :is-loading="uploading"
              @click="pickFiles"
            />
            <input
              ref="fileInputRef"
              type="file"
              multiple
              class="hidden"
              @change="onFilesPicked"
            />
          </div>
          <div v-if="viewing.documents?.length" class="flex flex-wrap gap-2">
            <div
              v-for="doc in viewing.documents"
              :key="doc.id"
              class="flex items-center gap-2 px-2 py-1 text-xs rounded-lg bg-n-alpha-1"
            >
              <a
                :href="doc.url"
                target="_blank"
                rel="noopener noreferrer"
                class="text-n-iris-11 hover:underline"
              >
                {{ doc.filename }}
              </a>
              <span class="text-n-slate-10">{{ fileSize(doc.byte_size) }}</span>
              <button
                v-if="canWrite"
                class="i-lucide-x size-3 text-n-slate-10 hover:text-n-ruby-11"
                @click="removeDocument(doc)"
              />
            </div>
          </div>
          <p v-else class="text-xs text-n-slate-10">还没有上传原始单据。</p>
        </div>

        <div class="flex items-center justify-end pt-2 border-t border-n-weak">
          <Button
            label="打印本张"
            icon="i-lucide-printer"
            color="slate"
            size="sm"
            :is-loading="printing"
            @click="printOne(viewing)"
          />
        </div>
      </div>
    </Dialog>

    <!-- 批量导入 -->
    <Dialog
      ref="importDialogRef"
      width="2xl"
      title="批量导入凭证"
      :show-confirm-button="false"
      cancel-button-label="关闭"
    >
      <div class="flex flex-col gap-3">
        <p class="text-sm text-n-slate-11">
          CSV 表头：组号 / 日期 / 事由 / 摘要 / 科目编码 / 借方金额 / 贷方金额 /
          币种 / 汇率 / 客户 / 供应商。
          <span class="text-n-slate-12">组号相同的行合成一张凭证</span>；
          一张凭证里有一行不合格，这张就整张不导入，其余照常。
          导进来的都是待过账凭证，仍要逐张审过账。
        </p>
        <div class="flex items-center gap-2">
          <Button
            label="下载 CSV 模板"
            icon="i-lucide-download"
            color="slate"
            variant="faded"
            size="sm"
            @click="downloadImportTemplate"
          />
          <Button
            label="选择 CSV 文件"
            icon="i-lucide-upload"
            color="iris"
            size="sm"
            :is-loading="importing"
            @click="importFileRef?.click()"
          />
          <input
            ref="importFileRef"
            type="file"
            accept=".csv,text/csv"
            class="hidden"
            @change="onImportPicked"
          />
        </div>

        <div v-if="importResult" class="flex flex-col gap-2 text-sm">
          <div class="text-n-slate-12">
            共 {{ importResult.total_groups }} 张，成功
            <span class="text-n-teal-11">
              {{ importResult.created.length }}
            </span>
            张，失败
            <span class="text-n-ruby-11">
              {{ importResult.failed.length }}
            </span>
            张
          </div>
          <div
            v-if="importResult.created.length"
            class="text-xs text-n-slate-11"
          >
            已生成：{{ importResult.created.join('、') }}
          </div>
          <div
            v-for="fail in importResult.failed"
            :key="fail.group"
            class="text-xs text-n-ruby-11"
          >
            组 {{ fail.group }}：{{ fail.errors.join('；') }}
          </div>
        </div>
      </div>
    </Dialog>

    <!-- 自动凭证规则 -->
    <Dialog
      ref="rulesRef"
      width="2xl"
      title="自动凭证规则"
      :show-confirm-button="false"
      cancel-button-label="关闭"
    >
      <div class="flex flex-col gap-2">
        <p class="text-sm text-n-slate-11">
          业务单据落库时按规则自动生成「待过账」凭证，财务审一眼点过账即可——不会自动记账。
        </p>
        <div
          v-for="rule in rules"
          :key="rule.id"
          class="flex flex-col gap-2 px-3 py-2 border rounded-lg border-n-weak"
        >
          <div class="flex items-center justify-between gap-3">
            <div class="flex flex-col min-w-0">
              <span class="text-sm truncate text-n-slate-12">
                {{ rule.name }}
              </span>
              <span class="font-mono text-xs text-n-slate-10">{{
                rule.event_key
              }}</span>
            </div>
            <label
              class="flex items-center gap-2 text-sm shrink-0 text-n-slate-11"
            >
              <input
                type="checkbox"
                class="w-4 h-4"
                :checked="rule.is_active"
                @change="toggleRule(rule)"
              />
              启用
            </label>
          </div>
          <!-- 科目映射：留空＝按科目类型/国标编码自动找，配了以配的为准。改完即存。 -->
          <div
            v-if="rule.config_slots && rule.config_slots.length"
            class="grid grid-cols-1 gap-2 pt-2 border-t sm:grid-cols-2 border-n-weak"
          >
            <div
              v-for="slot in rule.config_slots"
              :key="slot.key"
              class="flex items-center gap-2"
            >
              <span class="text-xs shrink-0 w-28 text-n-slate-11">
                {{ slot.label }}
              </span>
              <!-- block：不加的话 SelectCard 按内容宽，会撑破栅格把右边一列顶掉 -->
              <div class="flex-1 min-w-0">
                <SelectCard
                  block
                  :model-value="(rule.config || {})[slot.key] || ''"
                  :options="ruleAccountOptions"
                  trigger-class="h-8"
                  :disabled="savingRuleId === rule.id"
                  @update:model-value="v => setRuleAccount(rule, slot.key, v)"
                />
              </div>
            </div>
          </div>
        </div>
      </div>
    </Dialog>

    <!-- 打印区。两个坑：
         ① 不能用 display:none 藏——printElement 靠 getComputedStyle 把样式内联进克隆，会连 none 一起内联，打出空白页；
         ② 「移出屏幕」的定位必须放在**外层**：克隆的是里层节点，定位类若在它身上会被一起复制，
            克隆到打印容器后照样跑到 -10000px，打印同样是空白（踩过）。
         宽度按 A4 正文宽（96dpi≈794px）撑开，排版所见即所得。 -->
    <div class="fixed top-0 -left-[10000px] w-[794px]">
      <div ref="printAreaRef">
        <ErpVoucherPrintSheet
          v-for="sheet in printSheets"
          :key="sheet.id"
          :voucher="sheet"
        />
      </div>
    </div>

    <Dialog
      ref="confirmRef"
      type="alert"
      width="sm"
      confirm-button-color="ruby"
      title="删除凭证"
      :description="
        deleting?.status === 'POSTED'
          ? `确定删除**已记账**凭证「${deleting?.voucherNo || ''}」？删掉之后这笔分录从账簿和报表里直接消失，凭证号也会断号。更常用的更正方式是红冲（留痕、号不断）。`
          : `确定删除凭证「${deleting?.voucherNo || ''}」？`
      "
      confirm-label="删除"
      @confirm="doDelete"
    />

    <Dialog
      ref="bulkPostRef"
      type="alert"
      width="sm"
      confirm-button-color="blue"
      title="批量过账"
      :description="`确定把选中的 ${selectedDraftIds.length} 张待过账凭证全部记账？记账后不能再改，错账只能红冲。借贷不平的会被跳过并逐张报出来。`"
      confirm-label="全部过账"
      @confirm="doBulkPost"
    />
    <Dialog
      ref="bulkVoidRef"
      type="alert"
      width="sm"
      title="批量作废"
      :description="`确定把选中的 ${selectedDraftIds.length} 张待过账凭证全部作废？作废后凭证号留着、内容可查，但不再进账。已记账的不在其中，错账请用红冲。`"
      confirm-label="全部作废"
      @confirm="doBulkVoid"
    />
  </div>
</template>
