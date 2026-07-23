<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import MesProductionOrderAPI from 'dashboard/api/mes/productionOrders';

const { accountScopedRoute } = useAccount();
const router = useRouter();

const STAGE_LABELS = {
  SALES_CONFIRMED: '销售订单确定',
  BOM_READY: '工程/PMC BOM',
  PURCHASING: '采购原料',
  MATERIAL_INBOUND: '原料入库',
  PICKING: '生产领料',
  PRODUCTION: '生产',
  FG_INBOUND: '成品入库',
  SHIPPED: '销售出库',
};
const stageLabel = s => STAGE_LABELS[s] || s;

const loading = ref(true);

// 待我审批：停在我这一级（部门主管/总经理）的生产订单。
const APPROVAL_STEP = {
  SUBMITTED: '待你（部门主管）审',
  MANAGER_APPROVED: '待你（总经理）审',
};
const approvalInbox = ref([]);
// 待我接单：停在我负责阶段的在产订单（到岗通知拉取面）。
const inbox = ref([]);

const load = async () => {
  loading.value = true;
  try {
    const [approvalRes, inboxRes] = await Promise.all([
      MesProductionOrderAPI.approvalInbox(),
      MesProductionOrderAPI.inbox(),
    ]);
    approvalInbox.value = approvalRes?.data?.payload || [];
    inbox.value = inboxRes?.data?.payload || [];
  } catch {
    approvalInbox.value = [];
    inbox.value = [];
  } finally {
    loading.value = false;
  }
};

const total = computed(() => approvalInbox.value.length + inbox.value.length);

// 点条目 → 订单页「待我审批」视图并定位该单。
const goApproval = orderNo =>
  router.push(
    accountScopedRoute(
      'mes_production_orders_index',
      {},
      { q: orderNo, view: 'approval' }
    )
  );
// 点条目 → 订单页并按订单号搜索、自动打开详情面板。
const goOrder = orderNo =>
  router.push(
    accountScopedRoute('mes_production_orders_index', {}, { q: orderNo })
  );

onMounted(load);
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto">
    <div class="flex flex-wrap items-center justify-between gap-3 px-6 py-4">
      <h1 class="text-xl font-semibold text-n-slate-12">
        我的待办
        <span v-if="total" class="text-n-amber-11">({{ total }})</span>
      </h1>
      <button
        type="button"
        class="px-3 py-1 text-xs font-medium rounded-md outline outline-1 outline-n-weak text-n-slate-11 hover:text-n-slate-12"
        @click="load"
      >
        刷新
      </button>
    </div>

    <div v-if="loading" class="py-10 text-center text-n-slate-11">加载中…</div>

    <div v-else class="flex flex-col gap-4 px-6 pb-6">
      <!-- 待我审批：停在我这一级的生产订单 -->
      <div class="p-5 rounded-xl bg-n-amber-2 border border-n-amber-6">
        <div class="mb-3 font-medium text-n-slate-12">
          待我审批
          <span class="text-n-amber-11">({{ approvalInbox.length }})</span>
        </div>
        <div
          v-if="!approvalInbox.length"
          class="text-sm text-n-slate-11"
        >
          暂无待你审批的生产订单。
        </div>
        <ul v-else class="flex flex-col gap-2">
          <li
            v-for="o in approvalInbox"
            :key="o.id"
            class="flex items-center justify-between text-sm cursor-pointer group"
            @click="goApproval(o.order_no)"
          >
            <span class="text-n-slate-12 group-hover:underline">
              {{ o.order_no }} · {{ o.product_name }}
              <template v-if="o.pi_no"> · PI {{ o.pi_no }}</template>
              · {{ o.owner_name }}
            </span>
            <span class="shrink-0 text-n-amber-11">
              {{ APPROVAL_STEP[o.approval_status] || '待审' }}
            </span>
          </li>
        </ul>
      </div>

      <!-- 待我接单：到岗通知拉取面 -->
      <div class="p-5 rounded-xl bg-n-alpha-black1 border border-n-weak">
        <div class="mb-3 font-medium text-n-slate-12">
          待我接单
          <span class="text-n-iris-11">({{ inbox.length }})</span>
        </div>
        <div v-if="!inbox.length" class="text-sm text-n-slate-11">
          暂无待你接单的在产订单。
        </div>
        <ul v-else class="flex flex-col gap-2">
          <li
            v-for="o in inbox"
            :key="o.id"
            class="flex items-center justify-between text-sm cursor-pointer group"
            @click="goOrder(o.order_no)"
          >
            <span class="text-n-slate-12 group-hover:underline">
              {{ o.order_no }} · {{ o.product_name }} ·
              {{ stageLabel(o.stage) }}
            </span>
            <span v-if="o.ack_overdue" class="shrink-0 text-n-ruby-11">
              🔴 超时未接单
            </span>
            <span v-else-if="o.awaiting_ack" class="shrink-0 text-n-amber-11">
              ⏳ 待接单
            </span>
            <span v-else class="shrink-0 text-n-teal-11">已接单 · 处理中</span>
          </li>
        </ul>
      </div>
    </div>
  </div>
</template>
