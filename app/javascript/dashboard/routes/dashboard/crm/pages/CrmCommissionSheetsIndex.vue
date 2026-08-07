<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import camelcaseKeys from 'camelcase-keys';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCrmRole } from 'dashboard/composables/useCrmRole';
import CommissionSheetsAPI from 'dashboard/api/crm/commissionSheets';

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
const q = ref('');
const STATUS_CLASS = {
  DRAFT: 'bg-n-slate-3 text-n-slate-11',
  SUBMITTED: 'bg-n-amber-3 text-n-amber-11',
  APPROVED: 'bg-n-teal-3 text-n-teal-11',
  RETURNED: 'bg-n-ruby-3 text-n-ruby-11',
};
const STATUS_KEYS = Object.keys(STATUS_CLASS);

const fmtMonth = v => {
  if (!v) return '—';
  const d = new Date(v);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}`;
};
const fmtDateTime = v => (v ? new Date(v).toLocaleString() : '—');
const yuan = m =>
  m == null ? '—' : `¥${Math.round(m / 1_000_000).toLocaleString()}`;

const filteredRecords = computed(() => {
  const kw = q.value.trim().toLowerCase();
  return records.value.filter(
    s =>
      (!monthFilter.value || fmtMonth(s.periodMonth) === monthFilter.value) &&
      (!statusFilter.value || s.status === statusFilter.value) &&
      (!kw || `${s.ownerName || ''}`.toLowerCase().includes(kw))
  );
});

// 自己的草稿/退回表可删。
const canRemove = s =>
  s.ownerId === currentUser.value?.id &&
  (s.status === 'DRAFT' || s.status === 'RETURNED');
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
        <input
          v-model="newMonth"
          type="month"
          class="h-9 px-2 text-sm border rounded-lg reset-base w-36 border-n-weak bg-n-solid-1 text-n-slate-12"
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
    <div class="flex-1 px-6 py-4">
      <div class="flex flex-wrap items-center gap-2 mb-3">
        <input
          v-if="showTeamView"
          v-model="q"
          class="h-8 px-3 text-sm border rounded-lg reset-base w-52 border-n-weak bg-n-solid-1 text-n-slate-12"
          :placeholder="t('CRM.COMMISSION.SEARCH_OWNER')"
        />
        <input
          v-model="monthFilter"
          type="month"
          class="h-8 px-2 text-sm border rounded-lg reset-base w-44 border-n-weak bg-n-solid-1 text-n-slate-12"
        />
        <select
          v-model="statusFilter"
          class="h-8 px-2 mb-0 text-sm border rounded-lg reset-base w-36 border-n-weak bg-n-solid-1 text-n-slate-12"
        >
          <option value="">{{ t('CRM.COMMISSION.ALL_STATUS') }}</option>
          <option v-for="k in STATUS_KEYS" :key="k" :value="k">
            {{ t(`CRM.COMMISSION.STATUS.${k}`) }}
          </option>
        </select>
        <button
          v-if="q || monthFilter || statusFilter"
          class="h-8 px-2 text-xs rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
          @click="
            q = '';
            monthFilter = '';
            statusFilter = '';
          "
        >
          {{ t('CRM.COMMISSION.CLEAR_FILTER') }}
        </button>
        <span class="text-xs text-n-slate-10">
          {{ t('CRM.COMMISSION.COUNT', { n: filteredRecords.length }) }}
        </span>
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
              <span
                class="inline-flex px-2 py-0.5 rounded-full text-xs"
                :class="STATUS_CLASS[s.status]"
              >
                {{ t(`CRM.COMMISSION.STATUS.${s.status}`) }}
              </span>
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ s.totals?.count ?? 0 }}
            </td>
            <td class="px-3 py-2 font-medium text-n-slate-12">
              {{ yuan(s.totals?.salesRmbMicros) }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ fmtDateTime(s.updatedAt) }}
            </td>
            <td class="px-3 py-2 text-right">
              <button
                v-if="canRemove(s)"
                class="px-2 py-1 text-xs rounded-lg text-n-ruby-11 hover:bg-n-ruby-3"
                @click.stop="removeSheet(s)"
              >
                {{ t('CRM.COMMISSION.DELETE') }}
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
