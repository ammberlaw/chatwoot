<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import MesProductionOrderAPI from 'dashboard/api/mes/productionOrders';
import MesShipmentAPI from 'dashboard/api/mes/shipments';

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

// 本阶段停留天数（进入阶段至今）。
const stallDays = enteredAt => {
  if (!enteredAt) return null;
  return Math.round((Date.now() - new Date(enteredAt)) / 86400000);
};
// 接单截止时间（工作时间口径，后端已算好）：短日期时间。
const deadlineText = at =>
  at
    ? new Date(at).toLocaleString('zh-CN', {
        month: 'numeric',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '';

const loading = ref(true);

// 待我确认：停在我这一级的审批单（部门主管/总经理）+ 待我二次确认 BOM 的单（业务员）。
const APPROVAL_STEP = {
  SUBMITTED: '待你（部门主管）审',
  MANAGER_APPROVED: '待你（总经理）审',
};
// 非审批态的行即「待确认 BOM」（approval_inbox 的业务员分支）。
const pendingTag = o => APPROVAL_STEP[o.approval_status] || '待你确认BOM';
const approvalInbox = ref([]);
// 待我接单：停在我负责阶段的在产订单（到岗通知拉取面）。
const inbox = ref([]);
// 待我审核：停在我这一级的现货出库单。
const shipmentInbox = ref([]);

const load = async () => {
  loading.value = true;
  try {
    const [approvalRes, inboxRes, shipmentRes] = await Promise.all([
      MesProductionOrderAPI.approvalInbox(),
      MesProductionOrderAPI.inbox(),
      MesShipmentAPI.approvalInbox().catch(() => ({ data: { payload: [] } })),
    ]);
    approvalInbox.value = approvalRes?.data?.payload || [];
    inbox.value = inboxRes?.data?.payload || [];
    shipmentInbox.value = shipmentRes?.data?.payload || [];
  } catch {
    approvalInbox.value = [];
    inbox.value = [];
    shipmentInbox.value = [];
  } finally {
    loading.value = false;
  }
};

const total = computed(
  () =>
    approvalInbox.value.length + inbox.value.length + shipmentInbox.value.length
);

// 点条目 → 出库页并按现货出库筛选。
const goShipment = () =>
  router.push(accountScopedRoute('mes_shipments_index', {}, { kind: 'STOCK' }));

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
      <!-- 待我确认：停在我这一级的审批单 + 待我二次确认 BOM 的单 -->
      <div class="p-5 rounded-xl bg-n-amber-2 border border-n-amber-6">
        <div class="mb-3 font-medium text-n-slate-12">
          待我确认
          <span class="text-n-amber-11">({{ approvalInbox.length }})</span>
        </div>
        <div v-if="!approvalInbox.length" class="text-sm text-n-slate-11">
          暂无待你处理的生产订单（审批 / BOM 确认）。
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
              {{ pendingTag(o) }}
            </span>
          </li>
        </ul>
      </div>

      <!-- 待我审核：现货出库单 -->
      <div
        v-if="shipmentInbox.length"
        class="p-5 rounded-xl bg-n-teal-2 border border-n-teal-6"
      >
        <div class="mb-3 font-medium text-n-slate-12">
          待我审核（现货出库）
          <span class="text-n-teal-11">({{ shipmentInbox.length }})</span>
        </div>
        <ul class="flex flex-col gap-2">
          <li
            v-for="s in shipmentInbox"
            :key="s.id"
            class="flex items-center justify-between text-sm cursor-pointer group"
            @click="goShipment"
          >
            <span class="text-n-slate-12 group-hover:underline">
              {{ s.shipment_no }} · {{ s.customer_name || '—' }} ·
              {{ s.owner_name }}
            </span>
            <span class="shrink-0 text-n-teal-11">待你（部门主管）审</span>
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
            class="flex items-start justify-between gap-2 text-sm cursor-pointer group"
            @click="goOrder(o.order_no)"
          >
            <div class="min-w-0">
              <span class="text-n-slate-12 group-hover:underline">
                {{ o.order_no }} · {{ o.product_name }} ·
                {{ stageLabel(o.stage) }}
              </span>
              <div class="text-[11px] text-n-slate-10">
                <span v-if="stallDays(o.entered_at) !== null">
                  停留 {{ stallDays(o.entered_at) }} 天
                </span>
                <span v-if="o.ack_deadline">
                  · 接单截止 {{ deadlineText(o.ack_deadline) }}
                </span>
              </div>
            </div>
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
