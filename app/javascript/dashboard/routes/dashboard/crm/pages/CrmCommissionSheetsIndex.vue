<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import camelcaseKeys from 'camelcase-keys';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCrmRole } from 'dashboard/composables/useCrmRole';
import CommissionSheetsAPI from 'dashboard/api/crm/commissionSheets';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import MonthPicker from 'dashboard/components-next/monthpicker/MonthPicker.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';

const { t } = useI18n();
const router = useRouter();
const { accountId } = useAccount();
const { currentUser, isAdmin, isCrmDeputyAdmin, isCrmManager, isCrmFinance } =
  useCrmRole();

// 能看多人提成表的角色（管理员/副管/主管/财务）才显示搜索与业务员列。
const showTeamView = computed(
  () =>
    isAdmin.value ||
    isCrmDeputyAdmin.value ||
    isCrmManager.value ||
    isCrmFinance.value
);

const records = ref([]);
const isFetching = ref(false);
const isCreating = ref(false);

const pad = n => String(n).padStart(2, '0');
const now = new Date();
const currentMonth = `${now.getFullYear()}-${pad(now.getMonth() + 1)}`;
const newMonth = ref(currentMonth);

const fetchRecords = async () => {
  isFetching.value = true;
  try {
    const { data } = await CommissionSheetsAPI.list(accountId.value);
    records.value = camelcaseKeys(data.payload || [], { deep: true });
  } catch (e) {
    useAlert(e?.response?.data?.error || t('CRM.COMMISSION.LOAD_ERROR'));
  } finally {
    isFetching.value = false;
  }
};
onMounted(fetchRecords);

const open = sheet =>
  router.push({
    name: 'crm_commission_sheet_detail',
    params: { accountId: accountId.value },
    query: { id: sheet.id },
  });

// 新建（或打开已存在的）本月提成表 → 直接进详情页填报。
const createSheet = async () => {
  if (isCreating.value) return;
  isCreating.value = true;
  try {
    const { data } = await CommissionSheetsAPI.create(
      accountId.value,
      `${newMonth.value}-01`
    );
    open(camelcaseKeys(data, { deep: true }));
  } catch (e) {
    useAlert(e?.response?.data?.error || t('CRM.COMMISSION.CREATE_ERROR'));
  } finally {
    isCreating.value = false;
  }
};

const removeSheet = async sheet => {
  if (!window.confirm(t('CRM.COMMISSION.CONFIRM_DELETE'))) return;
  try {
    await CommissionSheetsAPI.remove(accountId.value, sheet.id);
    useAlert(t('CRM.COMMISSION.DELETED'));
    fetchRecords();
  } catch (e) {
    useAlert(e?.response?.data?.error || t('CRM.COMMISSION.DELETE_ERROR'));
  }
};

// ── 客户端筛选（提成表量级小）──
const monthFilter = ref('');
const statusFilter = ref('');
const paidFilter = ref(''); // 财务专用：'' 全部 / 'unpaid' 待发放 / 'paid' 已发放
const q = ref('');
const STATUS_CLASS = {
  DRAFT: 'bg-n-slate-3 text-n-slate-11',
  SUBMITTED: 'bg-n-amber-3 text-n-amber-11',
  APPROVED: 'bg-n-teal-3 text-n-teal-11',
  RETURNED: 'bg-n-ruby-3 text-n-ruby-11',
};
const STATUS_KEYS = Object.keys(STATUS_CLASS);
// 原生 select → 紫玻璃 SelectCard 的筛选选项（含「全部」空值项）。
const statusFilterOptions = computed(() => [
  { value: '', label: t('CRM.COMMISSION.ALL_STATUS') },
  ...STATUS_KEYS.map(k => ({
    value: k,
    label: t(`CRM.COMMISSION.STATUS.${k}`),
  })),
]);
const paidFilterOptions = computed(() => [
  { value: '', label: t('CRM.COMMISSION.PAYOUT.FILTER_ALL') },
  { value: 'unpaid', label: t('CRM.COMMISSION.PAYOUT.UNPAID') },
  { value: 'paid', label: t('CRM.COMMISSION.PAYOUT.PAID') },
]);

const fmtMonth = v => {
  if (!v) return '—';
  const d = new Date(v);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}`;
};
const fmtDateTime = v => (v ? new Date(v).toLocaleString() : '—');
const yuan = m =>
  m == null ? '—' : `¥${Math.round(m / 1_000_000).toLocaleString()}`;
const usd = m =>
  !m ? '—' : `US$${Math.round(m / 1_000_000).toLocaleString()}`;

const filteredRecords = computed(() => {
  const kw = q.value.trim().toLowerCase();
  return records.value.filter(
    s =>
      (!monthFilter.value || fmtMonth(s.periodMonth) === monthFilter.value) &&
      (!statusFilter.value || s.status === statusFilter.value) &&
      (!paidFilter.value ||
        (paidFilter.value === 'paid' ? !!s.paidAt : !s.paidAt)) &&
      (!kw || `${s.ownerName || ''}`.toLowerCase().includes(kw))
  );
});

// 自己的草稿/退回表可删。
const canRemove = s =>
  s.ownerId === currentUser.value?.id &&
  (s.status === 'DRAFT' || s.status === 'RETURNED');

const fmtDate = v => (v ? new Date(v).toLocaleDateString() : '');

// ── 提成点设置（品类→点位%）：管理员/副管/财务可维护 ──
const canManageRates = computed(
  () => isAdmin.value || isCrmDeputyAdmin.value || isCrmFinance.value
);
// 产品品类统一两类，提成点按这两类固定配置。
const STANDARD_CATEGORIES = ['平板电脑', '商显工控'];
const showRateDialog = ref(false);
const rateRows = ref([]);
const rateBusy = ref(false);

const openRateDialog = async () => {
  rateBusy.value = true;
  showRateDialog.value = true;
  try {
    const { data } = await CommissionSheetsAPI.rates(accountId.value);
    const existing = Object.fromEntries(
      (data.rates || []).map(r => [r.product_category, Number(r.rate)])
    );
    rateRows.value = STANDARD_CATEGORIES.map(cat => ({
      productCategory: cat,
      rate: existing[cat] ?? null,
    }));
  } catch (e) {
    useAlert(e?.response?.data?.error || t('CRM.COMMISSION.LOAD_ERROR'));
  } finally {
    rateBusy.value = false;
  }
};

const saveRates = async () => {
  rateBusy.value = true;
  try {
    const rows = rateRows.value.map(r => ({
      product_category: r.productCategory,
      rate: Number(r.rate) || 0,
    }));
    await CommissionSheetsAPI.saveRates(accountId.value, rows);
    useAlert('提成点已保存');
    showRateDialog.value = false;
  } catch (e) {
    useAlert(e?.response?.data?.error || '保存失败');
  } finally {
    rateBusy.value = false;
  }
};

// ── 财务发放（仅 crm_finance）：勾选「已通过且未发放」的提成表，逐张填实发金额后批量标记 ──
const selected = ref([]);
const isSelectable = s => s.status === 'APPROVED' && !s.paidAt;
const selectableIds = computed(() =>
  filteredRecords.value.filter(isSelectable).map(s => s.id)
);
const allSelected = computed(
  () =>
    selectableIds.value.length > 0 &&
    selectableIds.value.every(id => selected.value.includes(id))
);
const toggleSelect = id => {
  selected.value = selected.value.includes(id)
    ? selected.value.filter(x => x !== id)
    : [...selected.value, id];
};
const toggleAll = () => {
  selected.value = allSelected.value ? [] : [...selectableIds.value];
};

// 发放弹窗：逐张填实发提成金额（元），可加一条共用备注。
const payout = ref({ open: false, ids: [], note: '' });
const payoutAmounts = ref({});
const payoutSheets = computed(() =>
  payout.value.ids
    .map(id => records.value.find(r => r.id === id))
    .filter(Boolean)
);
const openPayout = ids => {
  payout.value = { open: true, ids: [...ids], note: '' };
  payoutAmounts.value = {};
  ids.forEach(id => {
    const s = records.value.find(r => r.id === id);
    payoutAmounts.value[id] =
      s?.paidAmountMicros != null
        ? String(Math.round(s.paidAmountMicros / 1_000_000))
        : '';
  });
};
const confirmPayout = async () => {
  const items = payout.value.ids.map(id => {
    const v = String(payoutAmounts.value[id] ?? '').trim();
    return {
      id,
      paid_amount_micros: v === '' ? null : Math.round(Number(v) * 1_000_000),
      paid_note: payout.value.note.trim(),
    };
  });
  try {
    const { data } = await CommissionSheetsAPI.markPaid(accountId.value, items);
    payout.value.open = false;
    selected.value = [];
    await fetchRecords();
    useAlert(t('CRM.COMMISSION.PAYOUT.MARKED', { n: data?.count ?? 0 }));
  } catch (e) {
    useAlert(e?.response?.data?.error || t('CRM.COMMISSION.PAYOUT.ERROR'));
  }
};
const unmarkPaid = async s => {
  if (!window.confirm(t('CRM.COMMISSION.PAYOUT.UNMARK_CONFIRM'))) return;
  try {
    await CommissionSheetsAPI.unmarkPaid(accountId.value, [s.id]);
    await fetchRecords();
    useAlert(t('CRM.COMMISSION.PAYOUT.UNMARKED'));
  } catch (e) {
    useAlert(e?.response?.data?.error || t('CRM.COMMISSION.PAYOUT.ERROR'));
  }
};
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div
      class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak"
    >
      <div>
        <h1 class="text-xl font-medium text-n-slate-12">
          {{ t('CRM.COMMISSION.HEADER') }}
        </h1>
        <p class="mt-0.5 text-xs text-n-slate-11">
          {{
            showTeamView
              ? t('CRM.COMMISSION.SUBTITLE_TEAM')
              : t('CRM.COMMISSION.SUBTITLE_SELF')
          }}
        </p>
      </div>
      <div class="flex items-center gap-2">
        <button
          v-if="canManageRates"
          class="h-9 px-3 text-sm rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-2"
          @click="openRateDialog"
        >
          提成点设置
        </button>
        <MonthPicker
          v-model="newMonth"
          align="right"
          trigger-class="w-36 h-9"
          :clearable="false"
        />
        <button
          class="h-9 px-4 text-sm font-medium text-white rounded-lg bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-50"
          :disabled="isCreating"
          @click="createSheet"
        >
          {{ t('CRM.COMMISSION.NEW') }}
        </button>
      </div>
    </div>

    <!-- 提成点设置弹窗：品类 → 点位% -->
    <div
      v-if="showRateDialog"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40"
      @click.self="showRateDialog = false"
    >
      <div
        class="flex flex-col w-full max-w-lg overflow-hidden bg-n-solid-1 rounded-2xl shadow-xl max-h-[80vh]"
      >
        <div
          class="flex items-center justify-between px-5 py-4 border-b border-n-weak"
        >
          <h2 class="text-base font-medium text-n-slate-12">提成点设置</h2>
          <button
            class="text-n-slate-10 hover:text-n-slate-12"
            @click="showRateDialog = false"
          >
            <Icon icon="i-lucide-x" class="size-5" />
          </button>
        </div>
        <div class="flex-1 px-5 py-4 overflow-y-auto">
          <p class="mb-3 text-xs text-n-slate-10">
            产品品类统一为「平板电脑 /
            商显工控」两类。提成表按每行品类匹配点位，算提成工资。
          </p>
          <div class="space-y-2">
            <div
              v-for="r in rateRows"
              :key="r.productCategory"
              class="flex items-center gap-3"
            >
              <span class="flex-1 text-sm text-n-slate-12">{{
                r.productCategory
              }}</span>
              <div class="flex items-center gap-1">
                <input
                  v-model.number="r.rate"
                  type="number"
                  step="0.01"
                  min="0"
                  class="h-8 px-2 text-sm text-right border rounded-lg reset-base w-24 border-n-weak bg-n-solid-1 text-n-slate-12"
                />
                <span class="text-sm text-n-slate-10">%</span>
              </div>
            </div>
          </div>
        </div>
        <div
          class="flex items-center justify-end gap-2 px-5 py-3 border-t border-n-weak"
        >
          <button
            class="h-8 px-3 text-sm rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
            @click="showRateDialog = false"
          >
            取消
          </button>
          <button
            class="h-8 px-4 text-sm font-medium text-white rounded-lg bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-50"
            :disabled="rateBusy"
            @click="saveRates"
          >
            保存
          </button>
        </div>
      </div>
    </div>
    <div class="flex-1 px-6 py-4">
      <div class="flex flex-wrap items-center gap-2 mb-3">
        <input
          v-if="showTeamView"
          v-model="q"
          class="h-9 px-3 text-sm border rounded-lg reset-base w-52 border-n-weak bg-n-solid-1 text-n-slate-12"
          :placeholder="t('CRM.COMMISSION.SEARCH_OWNER')"
        />
        <MonthPicker v-model="monthFilter" trigger-class="w-44 h-9" />
        <SelectCard
          v-model="statusFilter"
          :options="statusFilterOptions"
          trigger-class="w-36"
        />
        <SelectCard
          v-if="isCrmFinance"
          v-model="paidFilter"
          :options="paidFilterOptions"
          trigger-class="w-32"
        />
        <button
          v-if="q || monthFilter || statusFilter || paidFilter"
          class="h-9 px-2 text-xs rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
          @click="
            q = '';
            monthFilter = '';
            statusFilter = '';
            paidFilter = '';
          "
        >
          {{ t('CRM.COMMISSION.CLEAR_FILTER') }}
        </button>
        <span class="text-xs text-n-slate-10">
          {{ t('CRM.COMMISSION.COUNT', { n: filteredRecords.length }) }}
        </span>
        <button
          v-if="isCrmFinance && selected.length"
          class="h-8 px-3 ml-auto text-xs font-medium text-white rounded-lg bg-n-teal-9 hover:bg-n-teal-10"
          @click="openPayout(selected)"
        >
          {{ t('CRM.COMMISSION.PAYOUT.MARK_BATCH', { n: selected.length }) }}
        </button>
      </div>
      <div
        v-if="isFetching"
        class="flex items-center justify-center p-8 text-n-slate-11"
      >
        {{ t('CRM.COMMISSION.LOADING') }}
      </div>
      <div
        v-else-if="!filteredRecords.length"
        class="flex items-center justify-center p-8 text-n-slate-11"
      >
        {{
          showTeamView
            ? t('CRM.COMMISSION.EMPTY_TEAM')
            : t('CRM.COMMISSION.EMPTY_SELF')
        }}
      </div>
      <table v-else class="w-full text-sm text-left border-collapse">
        <thead class="text-n-slate-11">
          <tr class="border-b border-n-weak">
            <th v-if="isCrmFinance" class="w-8 px-3 py-2">
              <input
                type="checkbox"
                class="accent-n-teal-9"
                :checked="allSelected"
                :disabled="!selectableIds.length"
                @change="toggleAll"
              />
            </th>
            <th v-if="showTeamView" class="px-3 py-2 font-medium">
              {{ t('CRM.COMMISSION.COL.OWNER') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.COMMISSION.COL.MONTH') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.COMMISSION.COL.STATUS') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.COMMISSION.COL.COUNT') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.COMMISSION.COL.SALES_RMB') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.COMMISSION.COL.SALES_USD') }}
            </th>
            <th v-if="isCrmFinance" class="px-3 py-2 font-medium">
              {{ t('CRM.COMMISSION.PAYOUT.COL_PAID') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.COMMISSION.COL.UPDATED') }}
            </th>
            <th class="px-3 py-2 font-medium text-right">
              {{ t('CRM.COMMISSION.COL.ACTION') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="s in filteredRecords"
            :key="s.id"
            class="border-b border-n-weak cursor-pointer hover:bg-n-alpha-1"
            @click="open(s)"
          >
            <td v-if="isCrmFinance" class="px-3 py-2" @click.stop>
              <input
                v-if="isSelectable(s)"
                type="checkbox"
                class="accent-n-teal-9"
                :checked="selected.includes(s.id)"
                @change="toggleSelect(s.id)"
              />
            </td>
            <td
              v-if="showTeamView"
              class="px-3 py-2 font-medium text-n-slate-12"
            >
              {{ s.ownerName || '—' }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ fmtMonth(s.periodMonth) }}
            </td>
            <td class="px-3 py-2">
              <div class="flex items-center gap-1.5">
                <span
                  class="inline-flex px-2 py-0.5 rounded-full text-xs"
                  :class="STATUS_CLASS[s.status]"
                >
                  {{ t(`CRM.COMMISSION.STATUS.${s.status}`) }}
                </span>
                <span
                  v-if="s.paidAt"
                  class="inline-flex px-2 py-0.5 rounded-full text-xs bg-n-teal-3 text-n-teal-11"
                  :title="`${s.paidByName || ''} · ${fmtDate(s.paidAt)}`"
                >
                  {{ t('CRM.COMMISSION.PAYOUT.PAID') }}
                </span>
              </div>
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ s.totals?.count ?? 0 }}
            </td>
            <td class="px-3 py-2 font-medium text-n-slate-12">
              {{ yuan(s.totals?.salesRmbMicros) }}
            </td>
            <td class="px-3 py-2 font-medium text-n-slate-12">
              {{ usd(s.totals?.salesUsdMicros) }}
            </td>
            <td
              v-if="isCrmFinance"
              class="px-3 py-2 font-medium text-n-teal-11"
            >
              {{ s.paidAt ? yuan(s.paidAmountMicros) : '—' }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ fmtDateTime(s.updatedAt) }}
            </td>
            <td class="px-3 py-2 text-right" @click.stop>
              <button
                v-if="canRemove(s)"
                class="px-2 py-1 text-xs rounded-lg text-n-ruby-11 hover:bg-n-ruby-3"
                @click="removeSheet(s)"
              >
                {{ t('CRM.COMMISSION.DELETE') }}
              </button>
              <button
                v-if="isCrmFinance && s.status === 'APPROVED' && !s.paidAt"
                class="px-2 py-1 text-xs rounded-lg text-n-teal-11 hover:bg-n-teal-3"
                @click="openPayout([s.id])"
              >
                {{ t('CRM.COMMISSION.PAYOUT.MARK_ONE') }}
              </button>
              <button
                v-if="isCrmFinance && s.paidAt"
                class="px-2 py-1 text-xs rounded-lg text-n-slate-10 hover:bg-n-alpha-2"
                @click="unmarkPaid(s)"
              >
                {{ t('CRM.COMMISSION.PAYOUT.UNMARK') }}
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>

  <!-- 财务发放弹窗：逐张填实发提成金额（元），可加一条共用备注 -->
  <div
    v-if="payout.open"
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-black2"
    @click.self="payout.open = false"
  >
    <div
      class="flex flex-col w-full max-w-lg overflow-hidden bg-n-solid-1 rounded-2xl shadow-xl"
    >
      <div
        class="flex items-center justify-between px-5 py-3 border-b border-n-weak"
      >
        <h3 class="text-base font-medium text-n-slate-12">
          {{ t('CRM.COMMISSION.PAYOUT.DIALOG_TITLE') }}
        </h3>
        <button
          class="text-n-slate-10 hover:text-n-slate-12"
          @click="payout.open = false"
        >
          <span class="i-lucide-x size-5" />
        </button>
      </div>
      <div class="flex flex-col gap-2 px-5 py-4 overflow-auto max-h-[50vh]">
        <div
          v-for="s in payoutSheets"
          :key="s.id"
          class="flex items-center gap-3"
        >
          <div class="flex-1 min-w-0 text-sm truncate text-n-slate-12">
            {{ s.ownerName || '—' }}
            <span class="text-xs text-n-slate-10"
              >· {{ fmtMonth(s.periodMonth) }}</span
            >
          </div>
          <div class="flex items-center gap-1">
            <span class="text-xs text-n-slate-10">¥</span>
            <input
              v-model="payoutAmounts[s.id]"
              type="number"
              min="0"
              step="0.01"
              :placeholder="t('CRM.COMMISSION.PAYOUT.AMOUNT_PLACEHOLDER')"
              class="h-8 px-2 text-sm text-right border rounded-lg reset-base w-32 border-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </div>
        </div>
        <textarea
          v-model="payout.note"
          rows="2"
          :placeholder="t('CRM.COMMISSION.PAYOUT.NOTE_PLACEHOLDER')"
          class="w-full p-2 mt-1 text-sm border rounded-lg outline-none resize-none reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-teal-8"
        />
      </div>
      <div
        class="flex items-center justify-end gap-2 px-5 py-3 border-t border-n-weak"
      >
        <button
          class="h-8 px-3 text-sm rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
          @click="payout.open = false"
        >
          {{ t('CRM.COMMISSION.PAYOUT.CANCEL') }}
        </button>
        <button
          class="h-8 px-4 text-sm font-medium text-white rounded-lg bg-n-teal-9 hover:bg-n-teal-10"
          @click="confirmPayout"
        >
          {{ t('CRM.COMMISSION.PAYOUT.CONFIRM') }}
        </button>
      </div>
    </div>
  </div>
</template>
