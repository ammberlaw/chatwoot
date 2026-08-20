<script setup>
/* global axios */
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesProductLine } from 'dashboard/composables/useMesProductLine';

const { accountId, accountScopedRoute } = useAccount();
const router = useRouter();
// 产品线切换后自动重拉（axios 拦截已注入 product_line；这里只需触发重载）。
const { activeProductLine, label: productLineLabel } = useMesProductLine();

const stages = ref([]);
const loading = ref(true);
// 搜索：按订单号 / 产品 / 业务员即时过滤（不发请求，前端筛）。
const keyword = ref('');

const load = async () => {
  loading.value = true;
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/dashboard/pipeline`
    );
    stages.value = (data.stages || []).map(s => ({
      stage: s.stage,
      label: s.label,
      count: s.count,
      cards: (s.cards || []).map(c => ({
        id: c.id,
        orderNo: c.order_no,
        productName: c.product_name,
        customerName: c.customer_name,
        orderKind: c.order_kind,
        ownerName: c.owner_name,
        waitingNames: c.waiting_names || [],
        stallDays: c.stall_days,
        ackState: c.ack_state,
        alert: c.alert,
      })),
    }));
  } finally {
    loading.value = false;
  }
};

// 关键词过滤后的泳道（列结构不变，仅卡片收敛，计数随之更新）。
const filteredStages = computed(() => {
  const kw = keyword.value.trim().toLowerCase();
  if (!kw) return stages.value;
  return stages.value.map(s => {
    const cards = s.cards.filter(c =>
      [c.orderNo, c.productName, c.customerName, c.ownerName]
        .filter(Boolean)
        .some(v => v.toLowerCase().includes(kw))
    );
    return { ...s, cards, count: cards.length };
  });
});

const totalInProduction = computed(() =>
  stages.value.reduce((sum, s) => sum + s.count, 0)
);

// 接单态徽标样式。
const ACK_BADGE = {
  waiting: { text: '⏳ 待接单', cls: 'text-n-amber-11 bg-n-amber-3' },
  overdue: { text: '🔴 超时未接单', cls: 'text-n-ruby-11 bg-n-ruby-3' },
  processing: { text: '✓ 处理中', cls: 'text-n-teal-11 bg-n-teal-3' },
};
const ackBadge = state => ACK_BADGE[state] || null;

// 卡片左侧色条：逾期红 / 临期橙 / 正常无。
const cardAccent = alert => {
  if (alert === 'overdue') return 'border-l-2 border-l-n-ruby-9';
  if (alert === 'due_soon') return 'border-l-2 border-l-n-amber-9';
  return 'border-l-2 border-l-transparent';
};

const stallText = days => {
  if (days === null || days === undefined) return '';
  return days <= 0 ? '今日进入' : `停留 ${days} 天`;
};
const stallCls = days => (days >= 3 ? 'text-n-ruby-11 font-medium' : 'text-n-slate-10');

// 点卡 → 生产订单页并按订单号搜索、自动打开详情面板（复用看板既有跳转口径）。
const goOrder = orderNo =>
  router.push(
    accountScopedRoute('mes_production_orders_index', {}, { q: orderNo })
  );

// 产品线切换由 MesLayout 壳的 keyed router-view 触发页面重挂（onMounted 重拉），无需在此 watch。
onMounted(load);
</script>

<template>
  <div
    class="flex flex-col w-full h-full gap-4 p-6 overflow-hidden bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <!-- 顶栏 -->
    <div class="flex flex-wrap items-center justify-between gap-3 shrink-0">
      <div>
        <h1 class="text-2xl font-semibold tracking-tight text-n-slate-12">
          流水看板
        </h1>
        <p class="mt-0.5 text-sm text-n-slate-11">
          {{ productLineLabel }} · 在产 {{ totalInProduction }} 单 ·
          每单落在当前阶段列，一眼看全「卡在哪、等谁、卡多久」
        </p>
      </div>
      <div class="flex items-center gap-2">
        <div class="relative">
          <span
            class="absolute -translate-y-1/2 i-lucide-search size-4 text-n-slate-10 left-2.5 top-1/2"
          />
          <input
            v-model="keyword"
            type="text"
            placeholder="订单号 / 产品 / 业务员"
            class="h-8 w-56 pl-8 pr-2 text-sm rounded-lg outline outline-1 outline-n-weak bg-n-alpha-black1 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-n-iris-8"
          />
        </div>
        <button
          type="button"
          class="flex items-center h-8 gap-1 px-2.5 text-sm rounded-lg outline outline-1 outline-n-weak text-n-slate-11 hover:text-n-slate-12"
          @click="load"
        >
          <span class="i-lucide-refresh-cw size-3.5" />刷新
        </button>
      </div>
    </div>

    <!-- 泳道：横向滚动，每阶段一列 -->
    <div
      v-if="loading"
      class="flex items-center justify-center flex-1 text-sm text-n-slate-10"
    >
      加载中…
    </div>
    <div v-else class="flex flex-1 gap-3 overflow-x-auto pb-2">
      <div
        v-for="col in filteredStages"
        :key="col.stage"
        class="flex flex-col w-64 shrink-0 rounded-2xl bg-n-alpha-black1/50 border border-white/40"
      >
        <!-- 列头 -->
        <div
          class="flex items-center justify-between px-3 py-2.5 border-b border-n-weak/60 shrink-0"
        >
          <span class="text-sm font-medium text-n-slate-12">{{ col.label }}</span>
          <span
            class="px-1.5 min-w-5 text-center text-xs font-medium rounded-full text-n-slate-11 bg-n-alpha-black2"
          >
            {{ col.count }}
          </span>
        </div>
        <!-- 卡片列 -->
        <div class="flex flex-col gap-2 p-2 overflow-y-auto">
          <p
            v-if="!col.cards.length"
            class="py-6 text-xs text-center text-n-slate-10"
          >
            —
          </p>
          <button
            v-for="card in col.cards"
            :key="card.id"
            type="button"
            class="w-full p-2.5 text-left transition-shadow bg-n-solid-1/70 rounded-xl shadow-sm hover:shadow-md"
            :class="cardAccent(card.alert)"
            @click="goOrder(card.orderNo)"
          >
            <!-- 订单号 + 备货标签 -->
            <div class="flex items-center gap-1.5">
              <span class="text-xs font-semibold text-n-slate-12 truncate">
                {{ card.orderNo }}
              </span>
              <span
                v-if="card.orderKind === 'STOCK'"
                class="px-1 text-[10px] rounded text-n-violet-11 bg-n-violet-3 shrink-0"
              >
                备货
              </span>
            </div>
            <!-- 产品 · 客户 -->
            <p class="mt-0.5 text-xs text-n-slate-11 truncate">
              {{ card.productName }}
            </p>
            <p
              v-if="card.customerName"
              class="text-[11px] text-n-slate-10 truncate"
            >
              {{ card.customerName }}
            </p>
            <!-- 业务员 · 等谁 -->
            <div class="mt-1.5 space-y-0.5 text-[11px] text-n-slate-10">
              <p class="truncate">业务：{{ card.ownerName || '—' }}</p>
              <p class="truncate">
                等：{{ card.waitingNames.length ? card.waitingNames.join('、') : '未指派' }}
              </p>
            </div>
            <!-- 接单态 · 停留 -->
            <div class="flex items-center justify-between mt-1.5 gap-1">
              <span
                v-if="ackBadge(card.ackState)"
                class="px-1.5 py-0.5 text-[10px] rounded"
                :class="ackBadge(card.ackState).cls"
              >
                {{ ackBadge(card.ackState).text }}
              </span>
              <span v-else />
              <span class="text-[11px] shrink-0" :class="stallCls(card.stallDays)">
                {{ stallText(card.stallDays) }}
              </span>
            </div>
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
