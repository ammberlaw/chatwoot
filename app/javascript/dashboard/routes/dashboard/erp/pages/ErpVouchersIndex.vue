<script setup>
import { ref, reactive, computed, watch, nextTick, onMounted } from 'vue';
import { STATUS_TONE, STATUS_VOID } from 'dashboard/helper/statusTone';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useErpVouchersStore } from 'dashboard/stores/erp/vouchers';
import { useErpLedgerAccountsStore } from 'dashboard/stores/erp/ledgerAccounts';
import { useErpRole } from 'dashboard/composables/useErpRole';
import ErpVoucherAPI from 'dashboard/api/erp/vouchers';
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
import ErpVoucherPrintSheet from 'dashboard/components-next/erp/ErpVoucherPrintSheet.vue';
import { printElement } from 'dashboard/helper/printHelper';
import { downloadBlob } from 'dashboard/helper/erpDownload';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';

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

const fetchList = () =>
  store.get({
    page: currentPage.value,
    period: period.value,
    status: statusFilter.value,
    q: keyword.value.trim(),
  });

watch(currentPage, fetchList);
const resetAndFetch = () => {
  currentPage.value = 1;
  fetchList();
};

// 科目下拉：只给启用中的末级科目（分类科目不能记账，后端也会拦）。
const leafAccounts = computed(() =>
  accountStore.getRecords.filter(a => !a.isGroup && a.isActive)
);
const accountOptions = computed(() =>
  leafAccounts.value.map(a => ({ value: a.id, label: `${a.code} ${a.name}` }))
);
const accountById = id => leafAccounts.value.find(a => a.id === id);

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
  lines: [blankLine(), blankLine()],
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
// 选到外币科目时自动跟随科目币种（后端会校验币种须一致）。
const onAccountChange = line => {
  const account = accountById(line.ledgerAccountId);
  if (account?.currency) line.currency = account.currency;
  else line.currency = 'CNY';
  if (line.currency === 'CNY') line.exchangeRate = 1;
};

const openCreate = () => {
  editing.value = null;
  selectedTemplateId.value = '';
  Object.assign(form, {
    voucherDate: new Date().toISOString().slice(0, 10),
    summary: '',
    attachmentCount: 0,
    remark: '',
    lines: [blankLine(), blankLine()],
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
    <div class="flex items-center justify-between gap-3 px-6 py-4">
      <div class="flex items-center gap-2">
        <div class="i-lucide-book-text size-5 text-n-iris-9" />
        <h1 class="text-xl font-semibold text-n-slate-12">记账凭证</h1>
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
        <Button label="查询" color="slate" size="sm" @click="resetAndFetch" />
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

    <div class="flex items-center gap-2 px-6 pb-3">
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

    <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto">
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <template v-else>
        <!-- 除摘要外各列都是 nowrap，窗口一窄就只能挤摘要（挤成几行窄条）。
             给表格设最小宽度并单独包一层横向滚动：宽度不够就往右拉，摘要不再被压。
             滚动只包表格、不包分页条，否则往右拉时分页也跟着跑出去。 -->
        <div class="overflow-x-auto">
          <table class="w-full min-w-[1200px] text-sm">
            <thead>
              <tr class="text-left text-n-slate-11 border-b border-n-weak">
                <th class="px-3 py-3 font-medium w-9">
                  <input
                    type="checkbox"
                    class="w-4 h-4"
                    :checked="allSelected"
                    @change="toggleSelectAll"
                  />
                </th>
                <th class="px-3 py-3 font-medium">凭证字号</th>
                <th class="px-3 py-3 font-medium">日期</th>
                <th class="px-3 py-3 font-medium">摘要</th>
                <th class="px-3 py-3 font-medium text-right">借方合计</th>
                <th class="px-3 py-3 font-medium text-right">贷方合计</th>
                <th class="px-3 py-3 font-medium">状态</th>
                <th class="px-3 py-3 font-medium">制单 / 记账</th>
                <th class="px-3 py-3 font-medium text-right">操作</th>
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
                    <Button
                      v-else-if="
                        canWrite && v.status === 'POSTED' && !v.reversedByNo
                      "
                      label="红冲"
                      color="ruby"
                      variant="ghost"
                      size="xs"
                      @click="reverseVoucher(v)"
                    />
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

        <PaginationFooter
          v-if="totalCount > ITEMS_PER_PAGE"
          :current-page="currentPage"
          :total-items="totalCount"
          :items-per-page="ITEMS_PER_PAGE"
          class="!bg-transparent before:!hidden"
          @update:current-page="currentPage = $event"
        />
      </template>
    </div>

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
              placeholder="如：确认8月货款收入"
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

        <div class="flex flex-col gap-2">
          <div
            v-for="(line, index) in form.lines"
            :key="index"
            class="flex flex-col gap-2 p-2 border rounded-lg border-n-weak"
          >
            <div class="grid items-center grid-cols-12 gap-2">
              <div class="col-span-3">
                <Input
                  v-model="line.summary"
                  size="sm"
                  placeholder="摘要"
                  list="erp-summary-options"
                />
              </div>
              <div class="col-span-4">
                <ComboBox
                  v-model="line.ledgerAccountId"
                  :options="accountOptions"
                  placeholder="选会计科目"
                  @update:model-value="onAccountChange(line)"
                />
              </div>
              <div class="col-span-2">
                <Input
                  v-model="line.debit"
                  size="sm"
                  type="number"
                  placeholder="借方金额"
                  @input="onDebitInput(line)"
                />
              </div>
              <div class="col-span-2">
                <Input
                  v-model="line.credit"
                  size="sm"
                  type="number"
                  placeholder="贷方金额"
                  @input="onCreditInput(line)"
                />
              </div>
              <button
                class="flex items-center justify-center col-span-1 size-8 text-n-slate-11 hover:text-n-ruby-11"
                :disabled="form.lines.length <= 2"
                @click="removeLine(index)"
              >
                <div class="i-lucide-trash-2 size-4" />
              </button>
            </div>

            <div
              v-if="line.currency !== 'CNY'"
              class="flex items-center gap-2 text-xs text-n-slate-11"
            >
              <span>币种</span>
              <div class="w-36">
                <SelectCard
                  v-model="line.currency"
                  :options="CURRENCIES"
                  block
                />
              </div>
              <span>汇率</span>
              <div class="w-24">
                <Input v-model="line.exchangeRate" size="sm" type="number" />
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
              :dimensions="accountById(line.ledgerAccountId)?.dimensions || []"
              :required-dimension="
                { RECEIVABLE: 'customer', PAYABLE: 'supplier' }[
                  accountById(line.ledgerAccountId)?.accountType
                ] || ''
              "
            />

            <!-- 货币资金分录才出现：留空由现金流量表按对方科目自动判定 -->
            <div v-if="isCashLine(line)" class="flex items-center gap-1.5">
              <span class="text-xs whitespace-nowrap text-n-slate-11">
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
              <span class="text-n-slate-11">
                借方合计
                <span class="font-mono text-n-slate-12">{{
                  money(toMicros(totalDebit))
                }}</span>
              </span>
              <span class="text-n-slate-11">
                贷方合计
                <span class="font-mono text-n-slate-12">{{
                  money(toMicros(totalCredit))
                }}</span>
              </span>
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
              <th class="px-2 py-2 font-medium">摘要</th>
              <th class="px-2 py-2 font-medium">会计科目</th>
              <th class="px-2 py-2 font-medium">核算维度</th>
              <th class="px-2 py-2 font-medium text-right">借方</th>
              <th class="px-2 py-2 font-medium text-right">贷方</th>
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
              <td class="px-2 py-2 text-xs text-n-slate-11">
                <span v-if="line.crm_customer_name">
                  客户 {{ line.crm_customer_name }}
                </span>
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
          class="flex items-center justify-between px-3 py-2 border rounded-lg border-n-weak"
        >
          <div class="flex flex-col">
            <span class="text-sm text-n-slate-12">{{ rule.name }}</span>
            <span class="font-mono text-xs text-n-slate-10">{{
              rule.event_key
            }}</span>
          </div>
          <label class="flex items-center gap-2 text-sm text-n-slate-11">
            <input
              type="checkbox"
              class="w-4 h-4"
              :checked="rule.is_active"
              @change="toggleRule(rule)"
            />
            启用
          </label>
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
      :description="`确定删除待过账凭证「${deleting?.voucherNo || ''}」？已记账的凭证不能删除，只能红冲。`"
      confirm-label="删除"
      @confirm="doDelete"
    />
  </div>
</template>
