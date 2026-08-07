<script setup>
import { ref, computed, onMounted, reactive } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import camelcaseKeys from 'camelcase-keys';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCrmRole } from 'dashboard/composables/useCrmRole';
import { toPng } from 'html-to-image';
import CommissionSheetsAPI from 'dashboard/api/crm/commissionSheets';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { accountId } = useAccount();
const { currentUser, isAdmin, isCrmDeputyAdmin, isCrmManager, isCrmFinance } =
  useCrmRole();

const sheet = ref(null);
const items = ref([]);
const deleted = ref([]); // 已删除的既有行 id
const isLoading = ref(true);
const isBusy = ref(false);
const captureRef = ref(null); // 只读表容器，导出图片时截取

const COMMON_CATEGORIES = ['平板', '显示器', '广告机', '一体机', '其它'];
const CURRENCIES = ['USD', 'CNY', 'EUR'];
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
  receivedAmount: yuanFromMicros(it.receivedAmountMicros),
  exchangeRate: it.exchangeRate != null ? Number(it.exchangeRate) : null,
  receivedRmb: yuanFromMicros(it.receivedRmbMicros),
  salesRmb: yuanFromMicros(it.salesRmbMicros),
  paymentChannel: it.paymentChannel || '',
  paymentDate: dateOnly(it.paymentDate),
  product: it.product || '',
  remark: it.remark || '',
});

const applySheet = data => {
  const s = camelcaseKeys(data, { deep: true });
  sheet.value = s;
  items.value = (s.items || []).map(toLocal);
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
const editable = computed(
  () =>
    ['DRAFT', 'RETURNED'].includes(status.value) &&
    (isOwner.value || isAdmin.value || isCrmDeputyAdmin.value)
);
const canSubmit = computed(
  () => editable.value && (isOwner.value || isAdmin.value)
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
      receivedAmount: null,
      exchangeRate: null,
      receivedRmb: null,
      salesRmb: null,
      paymentChannel: '',
      paymentDate: '',
      product: '',
      remark: '',
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
    r.salesRmb = Math.round((recv - ship) * rate * 100) / 100;
  });
};

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
    received_amount_micros: microsFromYuan(r.receivedAmount),
    exchange_rate: r.exchangeRate === '' ? null : r.exchangeRate,
    received_rmb_micros: microsFromYuan(r.receivedRmb),
    sales_rmb_micros: microsFromYuan(r.salesRmb),
    payment_channel: r.paymentChannel || null,
    payment_date: r.paymentDate || null,
    product: r.product || null,
    remark: r.remark || null,
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
    useAlert(t('CRM.COMMISSION.DETAIL.SAVED'));
  } catch (e) {
    useAlert(e?.response?.data?.error || t('CRM.COMMISSION.DETAIL.SAVE_ERROR'));
  } finally {
    isBusy.value = false;
  }
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
  receivedRmb: sum(items.value, 'receivedRmb'),
  salesRmb: sum(items.value, 'salesRmb'),
}));
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div
      class="flex items-center justify-between flex-shrink-0 gap-3 px-6 py-4 border-b border-n-weak"
    >
      <div class="flex items-center gap-3 min-w-0">
        <button
          class="h-8 px-3 text-sm rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
          @click="back"
        >
          {{ t('CRM.COMMISSION.DETAIL.BACK') }}
        </button>
        <h1 class="text-lg font-medium truncate text-n-slate-12">
          {{ title }}
        </h1>
        <span
          v-if="sheet"
          class="inline-flex px-2 py-0.5 rounded-full text-xs shrink-0 bg-n-iris-3 text-n-iris-11"
        >
          {{ t(`CRM.COMMISSION.STATUS.${status}`) }}
        </span>
      </div>
      <div class="flex items-center gap-2 shrink-0">
        <template v-if="editable">
          <button
            class="h-8 px-3 text-sm rounded-lg text-n-slate-11 hover:bg-n-alpha-2 disabled:opacity-50"
            :disabled="isBusy"
            @click="pull"
          >
            {{ t('CRM.COMMISSION.DETAIL.PULL') }}
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
            v-if="canSubmit"
            class="h-8 px-4 text-sm font-medium text-white rounded-lg bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-50"
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
          v-if="canExport"
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
    <div v-else-if="sheet" class="flex-1 px-6 py-4">
      <!-- 退回原因提示 -->
      <div
        v-if="status === 'RETURNED' && sheet.returnReason"
        class="px-3 py-2 mb-3 text-sm rounded-lg bg-n-ruby-3 text-n-ruby-11"
      >
        {{ t('CRM.COMMISSION.DETAIL.RETURNED_PREFIX') }}{{ sheet.returnReason }}
      </div>

      <!-- 编辑态：可编辑网格 -->
      <div v-if="editable" class="overflow-x-auto">
        <datalist id="commission-categories">
          <option v-for="c in COMMON_CATEGORIES" :key="c" :value="c" />
        </datalist>
        <table class="text-xs border-collapse table-fixed w-max">
          <colgroup>
            <col class="w-8" />
            <col class="w-24" />
            <col class="w-16" />
            <col class="w-40" />
            <col class="w-36" />
            <col class="w-24" />
            <col class="w-16" />
            <col class="w-16" />
            <col class="w-24" />
            <col class="w-20" />
            <col class="w-28" />
            <col class="w-28" />
            <col class="w-28" />
            <col class="w-36" />
            <col class="w-40" />
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
              <th class="px-1 py-2 font-medium text-right">
                {{ t('CRM.COMMISSION.COLS.ORDER_AMOUNT') }}
              </th>
              <th class="px-1 py-2 font-medium text-left">
                {{ t('CRM.COMMISSION.COLS.CURRENCY') }}
              </th>
              <th class="px-1 py-2 font-medium text-right">
                {{ t('CRM.COMMISSION.COLS.SHIPPING') }}
              </th>
              <th class="px-1 py-2 font-medium text-right">
                {{ t('CRM.COMMISSION.COLS.RECEIVED') }}
              </th>
              <th class="px-1 py-2 font-medium text-right">
                {{ t('CRM.COMMISSION.COLS.RATE') }}
              </th>
              <th class="px-1 py-2 font-medium text-right">
                {{ t('CRM.COMMISSION.COLS.RECEIVED_RMB') }}
              </th>
              <th class="px-1 py-2 font-medium text-right">
                {{ t('CRM.COMMISSION.COLS.SALES_RMB') }}
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
              <th class="px-1 py-2 w-8" />
            </tr>
          </thead>
          <tbody>
            <tr v-for="(r, i) in items" :key="i" class="border-b border-n-weak">
              <td class="px-1 py-1 text-n-slate-10">{{ i + 1 }}</td>
              <td class="px-1 py-1">
                <input
                  v-model="r.productCategory"
                  list="commission-categories"
                  class="w-full h-7 px-1 text-xs border rounded reset-base border-n-weak bg-n-solid-1"
                />
              </td>
              <td class="px-1 py-1">
                <input
                  v-model="r.country"
                  class="w-full h-7 px-1 text-xs border rounded reset-base border-n-weak bg-n-solid-1"
                />
              </td>
              <td class="px-1 py-1">
                <input
                  v-model="r.customerName"
                  class="w-full h-7 px-1 text-xs border rounded reset-base border-n-weak bg-n-solid-1"
                />
              </td>
              <td class="px-1 py-1">
                <input
                  v-model="r.orderNo"
                  class="w-full h-7 px-1 text-xs border rounded reset-base border-n-weak bg-n-solid-1"
                />
              </td>
              <td class="px-1 py-1">
                <input
                  v-model.number="r.orderAmount"
                  type="number"
                  step="0.01"
                  class="w-full h-7 px-1 text-xs text-right border rounded reset-base border-n-weak bg-n-solid-1"
                />
              </td>
              <td class="px-1 py-1">
                <select
                  v-model="r.currency"
                  class="w-full h-7 px-1 mb-0 text-xs border rounded reset-base border-n-weak bg-n-solid-1"
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
                  class="w-full h-7 px-1 text-xs text-right border rounded reset-base border-n-weak bg-n-solid-1"
                />
              </td>
              <td class="px-1 py-1">
                <input
                  v-model.number="r.receivedAmount"
                  type="number"
                  step="0.01"
                  class="w-full h-7 px-1 text-xs text-right border rounded reset-base border-n-weak bg-n-solid-1"
                />
              </td>
              <td class="px-1 py-1">
                <input
                  v-model.number="r.exchangeRate"
                  type="number"
                  step="0.0001"
                  class="w-full h-7 px-1 text-xs text-right border rounded reset-base border-n-weak bg-n-solid-1"
                />
              </td>
              <td class="px-1 py-1">
                <input
                  v-model.number="r.receivedRmb"
                  type="number"
                  step="0.01"
                  class="w-full h-7 px-1 text-xs text-right border rounded reset-base border-n-weak bg-n-solid-1"
                />
              </td>
              <td class="px-1 py-1">
                <input
                  v-model.number="r.salesRmb"
                  type="number"
                  step="0.01"
                  class="w-full h-7 px-1 text-xs text-right border rounded reset-base border-n-weak bg-n-solid-1"
                />
              </td>
              <td class="px-1 py-1">
                <input
                  v-model="r.paymentChannel"
                  class="w-full h-7 px-1 text-xs border rounded reset-base border-n-weak bg-n-solid-1"
                />
              </td>
              <td class="px-1 py-1">
                <input
                  v-model="r.paymentDate"
                  type="date"
                  class="w-full h-7 px-1 text-xs border rounded reset-base border-n-weak bg-n-solid-1"
                />
              </td>
              <td class="px-1 py-1">
                <input
                  v-model="r.product"
                  class="w-full h-7 px-1 text-xs border rounded reset-base border-n-weak bg-n-solid-1"
                />
              </td>
              <td class="px-1 py-1">
                <input
                  v-model="r.remark"
                  class="w-full h-7 px-1 text-xs border rounded reset-base border-n-weak bg-n-solid-1"
                />
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
              <td colspan="17" class="px-3 py-6 text-center text-n-slate-10">
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

      <!-- 只读态：按产品品类分组 + 小计 + 总计（captureRef 供导出图片截取）-->
      <div v-else class="overflow-x-auto">
        <div
          ref="captureRef"
          class="inline-block min-w-full p-4 bg-n-background"
        >
          <div class="mb-2 text-sm font-semibold text-n-slate-12">
            {{ title }}
          </div>
          <table class="min-w-full text-xs border-collapse">
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
                  <td class="px-2 py-1.5 text-right tabular-nums">
                    {{ fmtYuan2(r.orderAmount) }}
                  </td>
                  <td class="px-2 py-1.5">{{ r.currency || '—' }}</td>
                  <td class="px-2 py-1.5 text-right tabular-nums">
                    {{ fmtYuan2(r.shipping) }}
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
                  <td class="px-2 py-1.5">{{ r.paymentChannel || '—' }}</td>
                  <td class="px-2 py-1.5">{{ r.paymentDate || '—' }}</td>
                  <td class="px-2 py-1.5">{{ r.product || '—' }}</td>
                  <td class="px-2 py-1.5">{{ r.remark || '—' }}</td>
                </tr>
                <tr class="border-b border-n-weak bg-n-alpha-1 font-medium">
                  <td class="px-2 py-1.5" colspan="2">
                    {{ g.category }}
                    {{ t('CRM.COMMISSION.DETAIL.SUBTOTAL_SUFFIX') }}
                  </td>
                  <td colspan="5" />
                  <td class="px-2 py-1.5 text-right tabular-nums">
                    {{ fmtYuan2(sum(g.rows, 'shipping')) }}
                  </td>
                  <td colspan="2" />
                  <td class="px-2 py-1.5 text-right tabular-nums">
                    {{ fmtYuan2(sum(g.rows, 'receivedRmb')) }}
                  </td>
                  <td class="px-2 py-1.5 text-right tabular-nums">
                    {{ fmtYuan2(sum(g.rows, 'salesRmb')) }}
                  </td>
                  <td colspan="4" />
                </tr>
              </template>
              <tr v-if="!items.length">
                <td colspan="16" class="px-3 py-6 text-center text-n-slate-10">
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
                <td colspan="5" />
                <td class="px-2 py-2 text-right tabular-nums">
                  {{ fmtYuan2(grand.shipping) }}
                </td>
                <td colspan="2" />
                <td class="px-2 py-2 text-right tabular-nums">
                  {{ fmtYuan2(grand.receivedRmb) }}
                </td>
                <td class="px-2 py-2 text-right tabular-nums">
                  {{ fmtYuan2(grand.salesRmb) }}
                </td>
                <td colspan="4" />
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </div>
</template>
