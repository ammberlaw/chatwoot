<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { frontendURL } from 'dashboard/helper/URLHelper';
import { fmtMoney } from 'dashboard/helper/erpMoney';
import ErpDashboardAPI from 'dashboard/api/erp/dashboard';

// 财务看板：全部真实数据，没数据就是 0（不放假数字）。
// 口径：回款/付款＝本月正常单据；余额＝台账未结；资金＝账户余额；利润＝利润表口径。
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');

const KPIS = [
  {
    key: 'month_receipt',
    label: '本月回款',
    icon: 'i-lucide-hand-coins',
    route: 'erp/receivables',
  },
  {
    key: 'receivable_balance',
    label: '应收余额',
    icon: 'i-lucide-file-input',
    route: 'erp/receivables',
  },
  {
    key: 'overdue_receivable',
    label: '逾期应收',
    icon: 'i-lucide-alarm-clock',
    route: 'erp/receivables',
    alert: true,
  },
  {
    key: 'month_payment',
    label: '本月付款',
    icon: 'i-lucide-banknote',
    route: 'erp/payables',
  },
  {
    key: 'payable_balance',
    label: '应付余额',
    icon: 'i-lucide-file-output',
    route: 'erp/payables',
  },
  {
    key: 'cash_balance',
    label: '资金余额',
    icon: 'i-lucide-wallet',
    route: 'erp/cash',
  },
  {
    key: 'month_profit',
    label: '本月净利润',
    icon: 'i-lucide-trending-up',
    route: 'erp/reports',
  },
];

const data = ref({ kpis: {}, overdue_installments: [], pending_vouchers: [] });
const loading = ref(true);

const money = micros => fmtMoney(micros || 0);
const go = path =>
  router.push(frontendURL(`accounts/${accountId.value}/${path}`));

const draftCount = computed(() => data.value.kpis?.draft_voucher_count || 0);
const foreignCash = computed(() => data.value.kpis?.cash_foreign || []);

onMounted(async () => {
  try {
    const response = await ErpDashboardAPI.show();
    data.value = response.data;
  } finally {
    loading.value = false;
  }
});
</script>

<template>
  <div class="flex flex-col w-full h-full gap-4 p-6 overflow-auto">
    <div class="flex items-center gap-2">
      <div class="i-lucide-landmark size-5 text-n-iris-9" />
      <h1 class="text-lg font-semibold text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8">财务看板</h1>
      <span class="text-sm text-n-slate-11">单位：元 · 本位币口径</span>
    </div>

    <div v-if="loading" class="py-10 text-center text-n-slate-11">加载中…</div>

    <template v-else>
      <div class="grid grid-cols-2 gap-4 md:grid-cols-4">
        <button
          v-for="kpi in KPIS"
          :key="kpi.key"
          class="flex flex-col gap-2 p-4 text-left transition-colors border shadow-sm rounded-xl border-n-weak bg-n-solid-1 hover:border-n-iris-8"
          @click="go(kpi.route)"
        >
          <div class="flex items-center justify-between">
            <span class="text-sm text-n-slate-11">{{ kpi.label }}</span>
            <div :class="kpi.icon" class="size-4 text-n-iris-9" />
          </div>
          <div
            class="font-mono text-2xl font-semibold"
            :class="
              kpi.alert && data.kpis[kpi.key]
                ? 'text-n-ruby-11'
                : 'text-n-slate-12'
            "
          >
            {{ money(data.kpis[kpi.key]) }}
          </div>
          <!-- 外币账户不折进人民币数（没有可用汇率快照），按币种单列 -->
          <div
            v-if="kpi.key === 'cash_balance' && foreignCash.length"
            class="text-xs text-n-slate-11"
          >
            <span v-for="row in foreignCash" :key="row.currency" class="mr-2">
              {{ row.currency }} {{ money(row.amount_micros) }}
            </span>
          </div>
        </button>
      </div>

      <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <!-- 待审凭证队列 -->
        <div
          class="flex flex-col gap-2 p-4 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <div class="flex items-center justify-between">
            <span class="font-medium text-n-slate-12">
              待过账凭证
              <span v-if="draftCount" class="text-n-amber-11">{{
                draftCount
              }}</span>
            </span>
            <button
              class="text-xs text-n-iris-11 hover:underline"
              @click="go('erp/vouchers')"
            >
              去凭证中心
            </button>
          </div>
          <div
            v-for="voucher in data.pending_vouchers"
            :key="voucher.id"
            class="flex items-center justify-between py-1.5 text-sm border-b border-n-weak last:border-0"
          >
            <div class="flex flex-col min-w-0">
              <span class="font-mono text-xs text-n-slate-11">
                {{ voucher.voucher_no }} · {{ voucher.voucher_date }}
              </span>
              <span class="truncate text-n-slate-12">{{
                voucher.summary || '—'
              }}</span>
            </div>
            <span class="font-mono text-n-slate-12">
              {{ money(voucher.total_debit_micros) }}
            </span>
          </div>
          <div
            v-if="!data.pending_vouchers.length"
            class="py-6 text-sm text-center text-n-slate-11"
          >
            没有待过账凭证，账是清的。
          </div>
        </div>

        <!-- 逾期应收 -->
        <div
          class="flex flex-col gap-2 p-4 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <div class="flex items-center justify-between">
            <span class="font-medium text-n-slate-12">逾期应收</span>
            <button
              class="text-xs text-n-iris-11 hover:underline"
              @click="go('erp/receivables')"
            >
              去应收台账
            </button>
          </div>
          <div
            v-for="row in data.overdue_installments"
            :key="row.id"
            class="flex items-center justify-between py-1.5 text-sm border-b border-n-weak last:border-0"
          >
            <div class="flex flex-col min-w-0">
              <span class="truncate text-n-slate-12">{{
                row.customer_name
              }}</span>
              <span class="text-xs text-n-slate-11">
                {{ row.receivable_no }} · {{ row.kind_label }} · 到期
                {{ row.due_date }} · 逾期
                <span class="text-n-ruby-11">{{ row.overdue_days }}</span> 天
                <span v-if="row.owner_name">· {{ row.owner_name }}</span>
              </span>
            </div>
            <span class="font-mono text-n-ruby-11">{{
              money(row.amount_micros)
            }}</span>
          </div>
          <div
            v-if="!data.overdue_installments.length"
            class="py-6 text-sm text-center text-n-slate-11"
          >
            没有逾期未收的分期。
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
