<script setup>
import { ref, computed, onMounted } from 'vue';
import camelcaseKeys from 'camelcase-keys';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import QuotesAPI from 'dashboard/api/crm/quotes';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import MonthPicker from 'dashboard/components-next/monthpicker/MonthPicker.vue';
import CrmQuoteFormDialog from 'dashboard/components-next/CRM/CrmQuoteFormDialog.vue';
import CrmQuotePreviewDialog from 'dashboard/components-next/CRM/CrmQuotePreviewDialog.vue';
import CrmPiSellerProfileDialog from 'dashboard/components-next/CRM/CrmPiSellerProfileDialog.vue';
import { fmtYuan } from 'dashboard/helper/crmMoney';

const ITEMS_PER_PAGE = 15;

const { accountId } = useAccount();

const records = ref([]);
const totalCount = ref(0);
const currentPage = ref(1);
const isFetching = ref(false);
const activeStatus = ref('');
const activeOwner = ref(''); // 创建人筛选（owner_id，空=全部）
const activeMonth = ref(''); // 报价月份筛选（YYYY-MM，空=全部）
const dateDir = ref(''); // 报价日期排序方向：'' 默认(更新倒序) / 'desc' / 'asc'
const searchQuery = ref('');
const summary = ref(null);
const formRef = ref(null);

const STATUSES = {
  DRAFT: { label: '草稿', class: 'bg-n-slate-3 text-n-slate-11' },
  SENT: { label: '已发送', class: 'bg-n-blue-3 text-n-blue-11' },
  CONFIRMED: { label: '已确认', class: 'bg-n-teal-3 text-n-teal-11' },
  EXPIRED: { label: '已过期', class: 'bg-n-amber-3 text-n-amber-11' },
};

// 页顶 KPI 环形卡：环形填充=该状态占比，中心显数量，右侧标签+数量+各币种金额。
const KPI_META = [
  {
    key: 'all',
    label: '全部',
    track: 'text-n-iris-3',
    ring: 'text-n-iris-9',
    text: 'text-n-iris-11',
  },
  {
    key: 'DRAFT',
    label: '草稿',
    track: 'text-n-slate-4',
    ring: 'text-n-slate-8',
    text: 'text-n-slate-11',
  },
  {
    key: 'SENT',
    label: '已发送',
    track: 'text-n-blue-3',
    ring: 'text-n-blue-9',
    text: 'text-n-blue-11',
  },
  {
    key: 'CONFIRMED',
    label: '已确认',
    track: 'text-n-teal-3',
    ring: 'text-n-teal-9',
    text: 'text-n-teal-11',
  },
  {
    key: 'EXPIRED',
    label: '已过期',
    track: 'text-n-amber-3',
    ring: 'text-n-amber-9',
    text: 'text-n-amber-11',
  },
];

const CURRENCY_SYMBOL = { USD: 'US$', CNY: '¥', EUR: '€' };
const fmtMoney = (micros, currency) =>
  micros == null
    ? '—'
    : `${CURRENCY_SYMBOL[currency] || ''}${(micros / 1_000_000).toLocaleString(
        'en-US',
        { minimumFractionDigits: 2, maximumFractionDigits: 2 }
      )}`;
const fmtDate = v => (v ? String(v).slice(0, 10) : '—');

// 快到期提示：未成交(DRAFT/SENT)、有有效期、7 天内到期 → 返回剩余天数（0=今天）；
// 已过期由后台定时任务置 EXPIRED，这里只提醒临近的。
const expiringDays = record => {
  if (!['DRAFT', 'SENT'].includes(record.status) || !record.validUntil)
    return null;
  const days = Math.ceil((new Date(record.validUntil) - Date.now()) / 86400000);
  return days >= 0 && days <= 7 ? days : null;
};

// KPI 卡金额：跨币种不折算，按币种分列，显示完整金额（千分位）。
const fullMoney = micros => fmtYuan(micros, 'en-US');
const amountText = amounts => {
  const entries = Object.entries(amounts || {}).filter(([, m]) => m > 0);
  if (!entries.length) return '—';
  return entries
    .map(([cur, m]) => `${CURRENCY_SYMBOL[cur] || ''}${fullMoney(m)}`)
    .join(' · ');
};

const kpiCards = computed(() => {
  const total = summary.value?.all?.count || 0;
  return KPI_META.map(m => {
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
    const { data } = await QuotesAPI.list(accountId.value, {
      page: currentPage.value,
      status: activeStatus.value || undefined,
      owner_id: activeOwner.value || undefined,
      month: activeMonth.value || undefined,
      date_dir: dateDir.value || undefined,
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
    const { data } = await QuotesAPI.summary(accountId.value);
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
const setMonth = value => {
  activeMonth.value = value || '';
  currentPage.value = 1;
  fetchRecords();
};
// 报价日期表头排序：降序 → 升序 → 取消（回默认更新倒序）。
const toggleDateSort = () => {
  if (dateDir.value === '') dateDir.value = 'desc';
  else if (dateDir.value === 'desc') dateDir.value = 'asc';
  else dateDir.value = '';
  currentPage.value = 1;
  fetchRecords();
};
const dateSortIcon = computed(() => {
  if (dateDir.value === 'asc') return 'i-lucide-arrow-up';
  if (dateDir.value === 'desc') return 'i-lucide-arrow-down';
  return 'i-lucide-chevrons-up-down opacity-40';
});
// 创建人筛选选项（含「全部」），来自 summary 接口可见范围内的实际创建人。
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

// 查看：按导出的报价单样式只读预览；预览里点「编辑」再切到编辑弹窗。
const previewRef = ref(null);
const openPreview = record => previewRef.value?.open(record.id);
const editFromPreview = quote => {
  const record = records.value.find(r => r.id === quote?.id);
  if (record) openEdit(record);
};

// 我的卖方信息（与 PI 共用同一份预录）：报价单导出的联系人/手机/邮箱/落款按此填。
const sellerProfileRef = ref(null);
const openSellerProfile = () => sellerProfileRef.value?.open();
const onSaved = () => {
  fetchRecords();
  fetchSummary();
};

const convertingId = ref(null);
const convertToSalesOrder = async record => {
  if (!window.confirm(`确定将报价单 ${record.quoteNo} 转为销售订单？`)) return;
  convertingId.value = record.id;
  try {
    await QuotesAPI.convertToSalesOrder(accountId.value, record.id);
    useAlert('已转为销售订单');
    fetchRecords();
    fetchSummary();
  } catch (error) {
    useAlert(error?.response?.data?.error || '转销售订单失败');
  } finally {
    convertingId.value = null;
  }
};

const removeRecord = async record => {
  if (!window.confirm(`确定删除报价单 ${record.quoteNo}？`)) return;
  try {
    await QuotesAPI.remove(accountId.value, record.id);
    useAlert('报价已删除');
    fetchRecords();
    fetchSummary();
  } catch {
    useAlert('删除失败，请重试');
  }
};

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
    <!-- 头部：标题 + 副标题 + 新建 -->
    <div
      class="flex flex-col items-start justify-between flex-shrink-0 gap-2 px-4 pt-4 pb-1.5 sm:flex-row sm:items-start sm:gap-0 sm:px-[26px] sm:pt-[18px]"
    >
      <div class="min-w-0">
        <h1 class="text-[22px] font-bold tracking-[-0.01em] text-n-slate-12">
          报价单管理
        </h1>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <button
          type="button"
          class="inline-flex items-center gap-1.5 h-[34px] px-3.5 text-[13px] font-medium border rounded-[9px] border-n-weak bg-n-solid-1/70 text-n-slate-11 hover:bg-n-alpha-2"
          @click="openSellerProfile"
        >
          <span class="i-lucide-user size-[15px]" />
          我的卖方信息
        </button>
        <button
          type="button"
          class="inline-flex items-center gap-1.5 h-[34px] px-3.5 text-[13px] font-medium text-white rounded-[9px] bg-gradient-to-br from-n-iris-9 to-n-accent-grad shadow-lg shadow-n-iris-9/30 hover:brightness-105"
          @click="openCreate"
        >
          <span class="i-lucide-plus size-4" />
          新建报价
        </button>
      </div>
    </div>

    <!-- 顶部 KPI 环形卡 -->
    <div
      class="flex md:grid overflow-x-auto flex-shrink-0 grid-cols-2 gap-3 px-4 pt-3.5 pb-1 sm:px-[26px] md:grid-cols-3 xl:grid-cols-5"
    >
      <div
        v-for="card in kpiCards"
        :key="card.key"
        role="button"
        tabindex="0"
        class="flex items-center gap-3.5 p-[15px] shrink-0 w-[44%] md:w-auto border rounded-2xl bg-n-solid-1/60 cursor-pointer transition-all hover:shadow-md"
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

    <!-- 创建人筛选 + 搜索 -->
    <div
      class="flex flex-wrap items-center justify-between flex-shrink-0 gap-3 px-4 pt-1 pb-2 border-b sm:px-[26px] sm:pb-2 border-n-weak"
    >
      <div
        class="flex flex-wrap items-center w-full gap-2 sm:w-auto sm:ml-auto"
      >
        <MonthPicker
          :model-value="activeMonth"
          placeholder="全部月份"
          align="right"
          trigger-class="w-36 h-9 !text-[13px]"
          @update:model-value="setMonth"
        />
        <SelectCard
          :model-value="activeOwner"
          :options="creatorOptions"
          placeholder="全部创建人"
          align="right"
          trigger-class="!h-9 !text-[13px]"
          @update:model-value="setOwner"
        />
        <div
          class="flex items-center h-9 gap-2 px-3 text-[13px] border rounded-[10px] w-full sm:w-auto sm:min-w-[240px] border-n-weak bg-n-solid-1/60 focus-within:ring-2 focus-within:ring-n-iris-9"
        >
          <span class="i-lucide-search size-4 shrink-0 text-n-slate-9" />
          <input
            v-model="searchQuery"
            type="text"
            placeholder="搜索报价单号 / 客户 / 名称"
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
      加载中…
    </div>
    <div
      v-else-if="!records.length"
      class="flex flex-col items-center justify-center flex-1 gap-2 text-n-slate-10"
    >
      <span class="i-lucide-file-text size-8 opacity-40" />
      <p class="text-sm">暂无报价单</p>
    </div>

    <div v-else class="flex-1 px-3.5 py-0.5 overflow-y-auto">
      <!-- 手机卡片列表 -->
      <div class="flex flex-col gap-2 px-0.5 py-2 md:hidden">
        <div
          v-for="record in records"
          :key="record.id"
          class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl active:bg-n-alpha-1"
          @click="openEdit(record)"
        >
          <div class="flex items-center gap-2">
            <span
              class="font-mono text-[12.5px] font-semibold truncate text-n-slate-12"
            >
              {{ record.quoteNo }}
            </span>
            <span
              class="inline-flex items-center gap-[5px] px-2.5 py-[3px] text-[11px] font-medium rounded-full shrink-0"
              :class="STATUSES[record.status]?.class"
            >
              <span class="rounded-full size-1.5 bg-current opacity-90" />
              {{ STATUSES[record.status]?.label || record.status }}
            </span>
            <span class="flex-1" />
            <div
              class="flex items-center gap-2.5 shrink-0 text-n-slate-9"
              @click.stop
            >
              <button
                type="button"
                class="hover:text-n-iris-11"
                title="查看"
                @click="openPreview(record)"
              >
                <span class="i-lucide-eye size-4" />
              </button>
              <button
                type="button"
                class="hover:text-n-iris-11 disabled:opacity-50"
                title="转销售订单"
                :disabled="convertingId === record.id"
                @click="convertToSalesOrder(record)"
              >
                <span
                  class="size-4"
                  :class="
                    convertingId === record.id
                      ? 'i-lucide-loader-circle animate-spin'
                      : 'i-lucide-file-output'
                  "
                />
              </button>
              <button
                type="button"
                class="hover:text-n-ruby-11"
                title="删除"
                @click="removeRecord(record)"
              >
                <span class="i-lucide-trash-2 size-4" />
              </button>
            </div>
          </div>
          <div class="mt-1.5 text-[13px] font-medium truncate text-n-slate-12">
            {{ record.customerName || '—' }}
          </div>
          <div class="flex flex-wrap items-center gap-x-3 gap-y-1 mt-1.5">
            <span class="text-xs font-semibold tabular-nums text-n-slate-12">
              {{ fmtMoney(record.totalAmountMicros, record.quoteCurrency) }}
            </span>
            <span class="text-xs tabular-nums text-n-slate-11">
              报价日期：{{ fmtDate(record.quoteDate) }}
            </span>
            <span
              v-if="expiringDays(record) !== null"
              class="inline-flex items-center gap-1 px-2 py-[3px] text-[11px] font-medium rounded-full bg-n-amber-3 text-n-amber-11"
            >
              <span class="i-lucide-clock size-3" />
              {{
                expiringDays(record) === 0
                  ? '今天到期'
                  : `${expiringDays(record)} 天后到期`
              }}
            </span>
          </div>
          <div
            v-if="record.ownerName"
            class="flex items-center gap-2 mt-1.5 text-xs text-n-slate-11"
          >
            <Avatar
              :name="record.ownerName"
              :src="record.ownerAvatarUrl || ''"
              :size="20"
              rounded-full
            />
            <span class="truncate">{{ record.ownerName }}</span>
            <span
              v-if="
                record.handledByName && record.handledById !== record.ownerId
              "
              class="text-[11px] text-n-slate-10 truncate"
            >
              经办：{{ record.handledByName }}
            </span>
          </div>
        </div>
      </div>

      <table class="hidden w-full text-[13px] border-collapse md:table">
        <thead>
          <tr>
            <th
              class="px-3 py-2.5 text-left text-[11.5px] font-semibold text-n-slate-10 whitespace-nowrap"
            >
              报价单号
            </th>
            <th
              class="px-3 py-2.5 text-left text-[11.5px] font-semibold text-n-slate-10 whitespace-nowrap"
            >
              客户
            </th>
            <th
              class="px-3 py-2.5 text-right text-[11.5px] font-semibold text-n-slate-10 whitespace-nowrap"
            >
              金额
            </th>
            <th
              class="px-3 py-2.5 text-left text-[11.5px] font-semibold text-n-slate-10 whitespace-nowrap"
            >
              状态
            </th>
            <th
              class="px-3 py-2.5 text-left text-[11.5px] font-semibold text-n-slate-10 whitespace-nowrap"
            >
              <button
                class="inline-flex items-center gap-1 text-[11.5px] font-semibold transition-colors hover:text-n-slate-12"
                :class="dateDir ? 'text-n-slate-12' : ''"
                @click="toggleDateSort"
              >
                报价日期
                <span class="size-3.5" :class="dateSortIcon" />
              </button>
            </th>
            <th
              class="px-3 py-2.5 text-left text-[11.5px] font-semibold text-n-slate-10 whitespace-nowrap"
            >
              创建人
            </th>
            <th
              class="px-3 py-2.5 text-right text-[11.5px] font-semibold text-n-slate-10 whitespace-nowrap"
            >
              操作
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
              {{ record.quoteNo }}
            </td>
            <td class="px-3 py-3">
              <span class="block truncate max-w-56 text-n-slate-12">
                {{ record.customerName || '—' }}
              </span>
            </td>
            <td
              class="px-3 py-3 font-semibold text-right tabular-nums text-n-slate-12 whitespace-nowrap"
            >
              {{ fmtMoney(record.totalAmountMicros, record.quoteCurrency) }}
            </td>
            <td class="px-3 py-3 whitespace-nowrap">
              <span
                class="inline-flex items-center gap-[5px] px-2.5 py-[3px] text-[12px] font-medium rounded-full"
                :class="STATUSES[record.status]?.class"
              >
                <span class="rounded-full size-1.5 bg-current opacity-90" />
                {{ STATUSES[record.status]?.label || record.status }}
              </span>
              <span
                v-if="expiringDays(record) !== null"
                v-tooltip.top="`有效期至 ${fmtDate(record.validUntil)}`"
                class="ml-1.5 inline-flex items-center gap-1 px-2 py-[3px] text-[11px] font-medium rounded-full bg-n-amber-3 text-n-amber-11 align-middle"
              >
                <span class="i-lucide-clock size-3" />
                {{
                  expiringDays(record) === 0
                    ? '今天到期'
                    : `${expiringDays(record)} 天后到期`
                }}
              </span>
            </td>
            <td
              class="px-3 py-3 tabular-nums text-n-slate-10 whitespace-nowrap"
            >
              {{ fmtDate(record.quoteDate) }}
            </td>
            <td class="px-3 py-3 whitespace-nowrap">
              <div v-if="record.ownerName" class="flex flex-col gap-0.5">
                <span class="inline-flex items-center gap-2 text-n-slate-11">
                  <Avatar
                    :name="record.ownerName"
                    :src="record.ownerAvatarUrl || ''"
                    :size="26"
                    rounded-full
                  />
                  {{ record.ownerName }}
                </span>
                <span
                  v-if="
                    record.handledByName &&
                    record.handledById !== record.ownerId
                  "
                  class="pl-[34px] text-[11px] text-n-slate-10"
                >
                  经办：{{ record.handledByName }}
                </span>
              </div>
              <span v-else class="text-n-slate-10">—</span>
            </td>
            <td class="px-3 py-3">
              <div class="flex items-center justify-end gap-2.5 text-n-slate-9">
                <button
                  type="button"
                  class="hover:text-n-iris-11"
                  title="查看"
                  @click="openPreview(record)"
                >
                  <span class="i-lucide-eye size-4" />
                </button>
                <button
                  type="button"
                  class="hover:text-n-iris-11 disabled:opacity-50"
                  title="转销售订单"
                  :disabled="convertingId === record.id"
                  @click="convertToSalesOrder(record)"
                >
                  <span
                    class="size-4"
                    :class="
                      convertingId === record.id
                        ? 'i-lucide-loader-circle animate-spin'
                        : 'i-lucide-file-output'
                    "
                  />
                </button>
                <button
                  type="button"
                  class="hover:text-n-iris-11"
                  title="编辑"
                  @click="openEdit(record)"
                >
                  <span class="i-lucide-pencil size-4" />
                </button>
                <button
                  type="button"
                  class="hover:text-n-ruby-11"
                  title="删除"
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

    <!-- 页脚：共 N 条 + 页码 -->
    <div
      v-if="totalCount"
      class="flex flex-wrap items-center justify-between flex-shrink-0 gap-2 px-4 max-md:!pl-16 py-3 border-t sm:px-[26px] border-n-weak text-[12.5px] text-n-slate-10"
    >
      <span> 共 {{ totalCount }} 条 · 每页 {{ ITEMS_PER_PAGE }} 条 </span>
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

    <CrmQuoteFormDialog ref="formRef" @saved="onSaved" />
    <CrmQuotePreviewDialog ref="previewRef" @edit="editFromPreview" />
    <CrmPiSellerProfileDialog ref="sellerProfileRef" />
  </div>
</template>
