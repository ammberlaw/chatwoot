<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import camelcaseKeys from 'camelcase-keys';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import PisAPI from 'dashboard/api/crm/pis';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import CrmPiFormDialog from 'dashboard/components-next/CRM/CrmPiFormDialog.vue';
import CrmPiSellerProfileDialog from 'dashboard/components-next/CRM/CrmPiSellerProfileDialog.vue';
import { isClassicTheme } from 'dashboard/components-next/CRM/charts/chartColors';

// 经典灰专属：状态/KPI 环形/tab 改黄黑绿灰；其它主题保持原样。切主题需刷新。
const isClassic = ref(isClassicTheme());

const ITEMS_PER_PAGE = 15;

const { t } = useI18n();
const { accountId } = useAccount();

const records = ref([]);
const totalCount = ref(0);
const currentPage = ref(1);
const isFetching = ref(false);
const activeStatus = ref('');
const activeOwner = ref(''); // 创建人筛选（owner_id，空=全部）
const searchQuery = ref('');
const summary = ref(null);
const formRef = ref(null);
const sellerProfileRef = ref(null);

const STATUSES = computed(() =>
  isClassic.value
    ? {
        DRAFT: {
          label: t('CRM.PI.STATUS.DRAFT'),
          class: 'bg-n-slate-3 text-n-slate-11',
        },
        PAID: {
          label: t('CRM.PI.STATUS.PAID'),
          class: 'bg-[#e5f2ec] text-[#2e7a5b]',
        },
        VOID: {
          label: t('CRM.PI.STATUS.VOID'),
          class: 'bg-n-slate-3 text-n-slate-10 line-through',
        },
      }
    : {
        DRAFT: {
          label: t('CRM.PI.STATUS.DRAFT'),
          class: 'bg-n-slate-3 text-n-slate-11',
        },
        PAID: {
          label: t('CRM.PI.STATUS.PAID'),
          class: 'bg-n-teal-3 text-n-teal-11',
        },
        VOID: {
          label: t('CRM.PI.STATUS.VOID'),
          class: 'bg-n-ruby-3 text-n-ruby-11',
        },
      }
);

// 状态下划线 tab（含计数，取自汇总接口，独立于状态本身）。
// 页顶 KPI 环形卡：环形填充=该状态占比，中心显张数，右侧标签+张数+各币种金额。
// track=环底色，ring=进度色(stroke-current 取 text 色)，text=文字/金额强调色。
// 「已付款」用 emerald（#10b981/#059669）——设计系统只有 teal，任意值给这抹更亮的绿。
const KPI_META_DEFAULT = [
  {
    key: 'all',
    track: 'text-n-iris-3',
    ring: 'text-n-iris-9',
    text: 'text-n-iris-11',
  },
  {
    key: 'DRAFT',
    track: 'text-n-slate-4',
    ring: 'text-n-slate-8',
    text: 'text-n-slate-11',
  },
  {
    key: 'PAID',
    track: 'text-[#d1fae5]',
    ring: 'text-[#10b981]',
    text: 'text-[#059669]',
  },
  {
    key: 'VOID',
    track: 'text-n-ruby-3',
    ring: 'text-n-ruby-9',
    text: 'text-n-ruby-11',
  },
];
// 经典灰：全部=黄 / 草稿=灰 / 已付款=鼠尾草绿 / 作废=黑
const KPI_META_CLASSIC = [
  {
    key: 'all',
    track: 'text-[#fbeec0]',
    ring: 'text-[#f5c451]',
    text: 'text-[#a97e0c]',
  },
  {
    key: 'DRAFT',
    track: 'text-n-slate-4',
    ring: 'text-n-slate-8',
    text: 'text-n-slate-11',
  },
  {
    key: 'PAID',
    track: 'text-[#e5f2ec]',
    ring: 'text-[#4a9d7a]',
    text: 'text-[#2e7a5b]',
  },
  {
    key: 'VOID',
    track: 'text-n-slate-4',
    ring: 'text-[#1c1f26]',
    text: 'text-n-slate-12',
  },
];
const KPI_LABELS = {
  all: t('CRM.PI.KPI.ALL'),
  DRAFT: t('CRM.PI.STATUS.DRAFT'),
  PAID: t('CRM.PI.STATUS.PAID'),
  VOID: t('CRM.PI.STATUS.VOID'),
};
const kpiMeta = computed(() =>
  (isClassic.value ? KPI_META_CLASSIC : KPI_META_DEFAULT).map(m => ({
    ...m,
    label: KPI_LABELS[m.key],
  }))
);
const CURRENCY_SYMBOL = { USD: 'US$', CNY: '¥', EUR: '€' };
const fmtMoney = (micros, currency) =>
  micros == null
    ? '—'
    : `${CURRENCY_SYMBOL[currency] || ''}${(micros / 1_000_000).toLocaleString(
        'en-US',
        { minimumFractionDigits: 2, maximumFractionDigits: 2 }
      )}`;
const fmtDate = v => (v ? String(v).slice(0, 10) : '—');

// KPI 卡金额：跨币种不折算，按币种分列，显示完整金额（千分位，不压缩 K/M）。
const fullMoney = micros =>
  Math.round(micros / 1_000_000).toLocaleString('en-US');
const amountText = amounts => {
  const entries = Object.entries(amounts || {}).filter(([, m]) => m > 0);
  if (!entries.length) return '—';
  return entries
    .map(([cur, m]) => `${CURRENCY_SYMBOL[cur] || ''}${fullMoney(m)}`)
    .join(' · ');
};

const kpiCards = computed(() => {
  const total = summary.value?.all?.count || 0;
  return kpiMeta.value.map(m => {
    const bucket = summary.value?.[m.key] || { count: 0, amounts: {} };
    const count = bucket.count || 0;
    // 「全部」卡填满整环；其余按占全部比例；有值但占比极小也留一小段可见弧。
    let pct = 0;
    if (m.key === 'all') pct = count > 0 ? 100 : 0;
    else if (total > 0 && count > 0)
      pct = Math.max(4, Math.round((count / total) * 100));
    return {
      ...m,
      count,
      pct,
      amount: amountText(bucket.amounts),
      value: m.key === 'all' ? '' : m.key,
    };
  });
});

const fetchRecords = async () => {
  isFetching.value = true;
  try {
    const { data } = await PisAPI.list(accountId.value, {
      page: currentPage.value,
      status: activeStatus.value || undefined,
      owner_id: activeOwner.value || undefined,
      q: searchQuery.value.trim() || undefined,
    });
    records.value = camelcaseKeys(data.payload || [], { deep: true });
    totalCount.value = data.meta?.count || 0;
  } catch {
    records.value = [];
  } finally {
    isFetching.value = false;
  }
};

const fetchSummary = async () => {
  try {
    const { data } = await PisAPI.summary(accountId.value);
    summary.value = data;
  } catch {
    summary.value = null;
  }
};

let searchTimer = null;
const onSearchInput = () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => {
    currentPage.value = 1;
    fetchRecords();
  }, 300);
};
const setStatus = value => {
  activeStatus.value = value;
  currentPage.value = 1;
  fetchRecords();
};
// 创建人筛选选项（含「全部」），来自 summary 接口回传的可见范围内实际创建人。
const creatorOptions = computed(() => [
  { value: '', label: '全部创建人' },
  ...(summary.value?.creators || []).map(c => ({
    value: String(c.id),
    label: c.name,
  })),
]);
const setOwner = value => {
  activeOwner.value = value;
  currentPage.value = 1;
  fetchRecords();
};
const onPageChange = page => {
  currentPage.value = page;
  fetchRecords();
};

const openCreate = () => formRef.value?.open();
const openEdit = record => formRef.value?.open(record);
const openSellerProfile = () => sellerProfileRef.value?.open();
const onSaved = () => {
  fetchRecords();
  fetchSummary();
};

// 导出失败时取后端返回的具体提示（xlsx 走 blob，422 的 JSON 在 Blob 里）。
const extractError = async error => {
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

const exportingXlsxId = ref(null);
const exportXlsx = async record => {
  exportingXlsxId.value = record.id;
  try {
    const { data } = await PisAPI.xlsx(accountId.value, record.id);
    const url = URL.createObjectURL(data);
    const a = document.createElement('a');
    a.href = url;
    a.download = `PI-${record.piNo || 'export'}.xlsx`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  } catch (error) {
    const msg = await extractError(error);
    useAlert(msg || t('CRM.PI.EXPORT.XLSX_ERROR'));
  } finally {
    exportingXlsxId.value = null;
  }
};

const removeRecord = async record => {
  if (!window.confirm(t('CRM.PI.DELETE.CONFIRM', { no: record.piNo }))) return;
  try {
    await PisAPI.remove(accountId.value, record.id);
    useAlert(t('CRM.PI.DELETE.SUCCESS'));
    fetchRecords();
    fetchSummary();
  } catch {
    useAlert(t('CRM.PI.DELETE.ERROR'));
  }
};

const buyerLabel = r => r.buyerCompany || r.customerName || '—';
const attnLabel = name => `attn: ${name}`;
const totalPages = computed(() =>
  Math.max(1, Math.ceil(totalCount.value / ITEMS_PER_PAGE))
);
// 页码窗口化：页多时首页 … 当前±1 … 末页，避免一长排按钮。
const pageList = computed(() => {
  const total = totalPages.value;
  const cur = currentPage.value;
  if (total <= 7) return Array.from({ length: total }, (_, i) => i + 1);
  const wanted = [1, total, cur, cur - 1, cur + 1].filter(
    p => p >= 1 && p <= total
  );
  const sorted = [...new Set(wanted)].sort((a, b) => a - b);
  const result = [];
  let prev = 0;
  sorted.forEach(p => {
    if (p - prev > 1) result.push('…');
    result.push(p);
    prev = p;
  });
  return result;
});

onMounted(() => {
  fetchRecords();
  fetchSummary();
});
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-hidden bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <!-- 头部：标题 + 副标题 + 卖方信息/新建 -->
    <div
      class="flex items-start justify-between flex-shrink-0 px-[26px] pt-[18px] pb-1.5"
    >
      <div>
        <h1 class="text-[22px] font-bold tracking-[-0.01em] text-n-slate-12">
          {{ t('CRM.PI.HEADER') }}
        </h1>
        <p
          class="mt-1 text-[12.5px] leading-relaxed text-n-slate-10 max-w-[440px]"
        >
          {{ t('CRM.PI.SUBTITLE') }}
        </p>
      </div>
      <div class="flex items-center gap-2">
        <button
          type="button"
          class="inline-flex items-center gap-1.5 h-[34px] px-3.5 text-[13px] font-medium border rounded-[9px] border-n-weak bg-n-solid-1/70 text-n-slate-11 hover:bg-n-alpha-2"
          @click="openSellerProfile"
        >
          <span class="i-lucide-user size-[15px]" />
          {{ t('CRM.PI.SELLER_PROFILE.BUTTON') }}
        </button>
        <button
          type="button"
          class="inline-flex items-center gap-1.5 h-[34px] px-3.5 text-[13px] font-medium text-white rounded-[9px] bg-gradient-to-br from-n-iris-9 to-n-accent-grad shadow-lg shadow-n-iris-9/30 hover:brightness-105"
          @click="openCreate"
        >
          <span class="i-lucide-plus size-4" />
          {{ t('CRM.PI.NEW') }}
        </button>
      </div>
    </div>

    <!-- 顶部 KPI 环形卡 -->
    <div
      class="grid flex-shrink-0 grid-cols-2 gap-3 px-[26px] pt-3.5 pb-1 xl:grid-cols-4"
    >
      <div
        v-for="card in kpiCards"
        :key="card.key"
        role="button"
        tabindex="0"
        class="flex items-center gap-3.5 p-[15px] border rounded-2xl bg-n-solid-1/60 cursor-pointer transition-all hover:shadow-md"
        :class="
          activeStatus === card.value
            ? 'border-n-slate-12/40 ring-2 ring-n-slate-12/10 shadow-md'
            : 'border-white/70 shadow-sm'
        "
        @click="setStatus(card.value)"
      >
        <div class="relative shrink-0 size-[52px]">
          <svg viewBox="0 0 36 36" class="-rotate-90 size-[52px]">
            <circle
              cx="18"
              cy="18"
              r="16"
              fill="none"
              stroke-width="4"
              class="stroke-current"
              :class="card.track"
            />
            <circle
              cx="18"
              cy="18"
              r="16"
              fill="none"
              stroke-width="4"
              stroke-linecap="round"
              path-length="100"
              :stroke-dasharray="`${card.pct} 100`"
              class="stroke-current"
              :class="card.ring"
            />
          </svg>
          <span
            class="absolute inset-0 flex items-center justify-center text-[12px] font-bold"
            :class="card.text"
          >
            {{ card.count }}
          </span>
        </div>
        <div class="min-w-0">
          <div class="text-[12px] font-medium text-n-slate-10">
            {{ card.label }}
          </div>
          <div class="text-[20px] font-bold leading-tight text-n-slate-12">
            {{ card.count }}
          </div>
          <div class="text-[11px] font-semibold truncate" :class="card.text">
            {{ card.amount }}
          </div>
        </div>
      </div>
    </div>

    <!-- 状态下划线 tab + 搜索 -->
    <div
      class="flex flex-wrap items-center justify-between flex-shrink-0 gap-3 px-[26px] pt-1 border-b border-n-weak"
    >
      <div class="flex items-center gap-2 ml-auto">
        <SelectCard
          :model-value="activeOwner"
          :options="creatorOptions"
          placeholder="全部创建人"
          align="right"
          trigger-class="!h-9 !text-[13px]"
          @update:model-value="setOwner"
        />
        <div
          class="flex items-center h-9 gap-2 px-3 text-[13px] border rounded-[10px] min-w-[240px] border-n-weak bg-n-solid-1/60 focus-within:ring-2 focus-within:ring-n-iris-9"
        >
          <span class="i-lucide-search size-4 shrink-0 text-n-slate-9" />
          <input
            v-model="searchQuery"
            type="text"
            :placeholder="t('CRM.PI.SEARCH_PLACEHOLDER')"
            class="flex-1 h-full bg-transparent reset-base text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none"
            @input="onSearchInput"
          />
        </div>
      </div>
    </div>

    <div
      v-if="isFetching"
      class="flex items-center justify-center flex-1 text-sm text-n-slate-11"
    >
      {{ t('CRM.PI.LOADING') }}
    </div>
    <div
      v-else-if="!records.length"
      class="flex flex-col items-center justify-center flex-1 gap-2 text-n-slate-10"
    >
      <span class="i-lucide-file-text size-8 opacity-40" />
      <p class="text-sm">{{ t('CRM.PI.EMPTY') }}</p>
    </div>

    <div v-else class="flex-1 px-3.5 py-0.5 overflow-y-auto">
      <table class="w-full text-[13px] border-collapse">
        <thead>
          <tr>
            <th
              class="px-3 py-2.5 text-left text-[11.5px] font-semibold text-n-slate-10 whitespace-nowrap"
            >
              {{ t('CRM.PI.COL.PI_NO') }}
            </th>
            <th
              class="px-3 py-2.5 text-left text-[11.5px] font-semibold text-n-slate-10 whitespace-nowrap"
            >
              {{ t('CRM.PI.COL.BUYER') }}
            </th>
            <th
              class="px-3 py-2.5 text-right text-[11.5px] font-semibold text-n-slate-10 whitespace-nowrap"
            >
              {{ t('CRM.PI.COL.AMOUNT') }}
            </th>
            <th
              class="px-3 py-2.5 text-left text-[11.5px] font-semibold text-n-slate-10 whitespace-nowrap"
            >
              {{ t('CRM.PI.COL.STATUS') }}
            </th>
            <th
              class="px-3 py-2.5 text-left text-[11.5px] font-semibold text-n-slate-10 whitespace-nowrap"
            >
              {{ t('CRM.PI.COL.DATE') }}
            </th>
            <th
              class="px-3 py-2.5 text-left text-[11.5px] font-semibold text-n-slate-10 whitespace-nowrap"
            >
              {{ t('CRM.PI.COL.CREATOR') }}
            </th>
            <th
              class="px-3 py-2.5 text-right text-[11.5px] font-semibold text-n-slate-10 whitespace-nowrap"
            >
              {{ t('CRM.PI.COL.ACTION') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="record in records"
            :key="record.id"
            class="border-t border-n-weak hover:bg-n-iris-9/[0.04]"
          >
            <td
              class="px-3 py-3 font-mono text-[12.5px] font-semibold text-n-slate-12 whitespace-nowrap"
            >
              {{ record.piNo }}
            </td>
            <td class="px-3 py-3">
              <span class="block truncate max-w-56 text-n-slate-12">
                {{ buyerLabel(record) }}
              </span>
              <span
                v-if="record.attention"
                class="block text-[11px] truncate max-w-56 text-n-slate-10"
              >
                {{ attnLabel(record.attention) }}
              </span>
            </td>
            <td
              class="px-3 py-3 font-semibold text-right tabular-nums text-n-slate-12 whitespace-nowrap"
            >
              {{ fmtMoney(record.totalAmountMicros, record.currency) }}
            </td>
            <td class="px-3 py-3 whitespace-nowrap">
              <span
                class="inline-flex items-center gap-[5px] px-2.5 py-[3px] text-[12px] font-medium rounded-full"
                :class="STATUSES[record.status]?.class"
              >
                <span class="rounded-full size-1.5 bg-current opacity-90" />
                {{ STATUSES[record.status]?.label || record.status }}
              </span>
            </td>
            <td
              class="px-3 py-3 tabular-nums text-n-slate-10 whitespace-nowrap"
            >
              {{ fmtDate(record.piDate) }}
            </td>
            <td class="px-3 py-3 whitespace-nowrap">
              <span
                v-if="record.ownerName"
                class="inline-flex items-center gap-2 text-n-slate-11"
              >
                <Avatar
                  :name="record.ownerName"
                  :src="record.ownerAvatarUrl || ''"
                  :size="26"
                  rounded-full
                />
                {{ record.ownerName }}
              </span>
              <span v-else class="text-n-slate-10">—</span>
            </td>
            <td class="px-3 py-3">
              <div class="flex items-center justify-end gap-2.5 text-n-slate-9">
                <button
                  type="button"
                  class="hover:text-n-iris-11 disabled:opacity-50"
                  :title="t('CRM.PI.ACTION.XLSX')"
                  :disabled="exportingXlsxId === record.id"
                  @click="exportXlsx(record)"
                >
                  <span
                    class="size-4"
                    :class="
                      exportingXlsxId === record.id
                        ? 'i-lucide-loader-circle animate-spin'
                        : 'i-lucide-table'
                    "
                  />
                </button>
                <button
                  type="button"
                  class="hover:text-n-iris-11"
                  :title="t('CRM.PI.ACTION.EDIT')"
                  @click="openEdit(record)"
                >
                  <span class="i-lucide-pencil size-4" />
                </button>
                <button
                  type="button"
                  class="hover:text-n-ruby-11"
                  :title="t('CRM.PI.ACTION.DELETE')"
                  @click="removeRecord(record)"
                >
                  <span class="i-lucide-trash-2 size-4" />
                </button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- 页脚：共 N 条 · 每页 15 条 + 页码 -->
    <div
      v-if="totalCount"
      class="flex items-center justify-between flex-shrink-0 px-[26px] py-3 border-t border-n-weak text-[12.5px] text-n-slate-10"
    >
      <span>
        {{
          t('CRM.PI.FOOTER_COUNT', {
            total: totalCount,
            per: ITEMS_PER_PAGE,
          })
        }}
      </span>
      <div v-if="totalPages > 1" class="flex items-center gap-1">
        <button
          type="button"
          class="flex items-center justify-center min-w-[28px] h-7 px-1.5 border rounded-lg border-n-weak bg-n-solid-1/60 text-n-slate-11 disabled:opacity-40"
          :disabled="currentPage === 1"
          @click="onPageChange(currentPage - 1)"
        >
          <span class="i-lucide-chevron-left size-4" />
        </button>
        <template v-for="(p, i) in pageList" :key="i">
          <span
            v-if="p === '…'"
            class="flex items-center justify-center min-w-[28px] h-7 text-n-slate-9"
          >
            {{ p }}
          </span>
          <button
            v-else
            type="button"
            class="flex items-center justify-center min-w-[28px] h-7 px-2 rounded-lg tabular-nums"
            :class="
              p === currentPage
                ? 'bg-n-iris-9 text-white font-semibold'
                : 'text-n-slate-11 hover:bg-n-alpha-2'
            "
            @click="onPageChange(p)"
          >
            {{ p }}
          </button>
        </template>
        <button
          type="button"
          class="flex items-center justify-center min-w-[28px] h-7 px-1.5 border rounded-lg border-n-weak bg-n-solid-1/60 text-n-slate-11 disabled:opacity-40"
          :disabled="currentPage === totalPages"
          @click="onPageChange(currentPage + 1)"
        >
          <span class="i-lucide-chevron-right size-4" />
        </button>
      </div>
    </div>

    <CrmPiFormDialog ref="formRef" @saved="onSaved" />
    <CrmPiSellerProfileDialog ref="sellerProfileRef" />
  </div>
</template>
