<script setup>
/* global axios */
import { computed, onMounted, ref } from 'vue';
import ProductionOrdersAPI from 'dashboard/api/mes/productionOrders';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import Icon from 'dashboard/components-next/icon/Icon.vue';
const emit = defineEmits(['open', 'overview']);
const { accountId } = useAccount();
const currentUser = useMapGetter('getCurrentUser');
const productionView = computed(() => currentUser.value?.can_access_crm === false || currentUser.value?.mes_roles?.length > 0);
const overview = ref(null);
const showOverview = computed(() => productionView.value || (!loading.value && !error.value && !orders.value.length));
const productionRows = computed(() => {
  const counts = overview.value?.stage_distribution || {};
  return [
    { label: '工程准备', stages: ['SALES_CONFIRMED', 'BOM_READY'] },
    { label: '备料领料', stages: ['PURCHASING', 'MATERIAL_INBOUND', 'PICKING'] },
    { label: '生产入库', stages: ['PRODUCTION', 'FG_INBOUND'] },
  ].map(row => ({ ...row, count: row.stages.reduce((sum, stage) => sum + (counts[stage] || 0), 0) }));
});
const orders = ref([]);
const activeIndex = ref(0);
const order = computed(() => orders.value[activeIndex.value]);
const loading = ref(true);
const error = ref('');
const stages = ['SALES_CONFIRMED', 'BOM_READY', 'PURCHASING', 'MATERIAL_INBOUND', 'PICKING', 'PRODUCTION', 'FG_INBOUND', 'SHIPPED'];
const labels = ['待工程接单', '工程 / PMC', '采购原料', '原料入库', '生产领料', '生产中', '成品入库', '已出库'];
const stageLabel = order => {
  if (order.status === 'CANCELLED') return '已取消';
  if (order.status === 'STOPPED') return '已终止';
  if (order.approval_status === 'DRAFT') return '草稿';
  if (['SUBMITTED', 'MANAGER_APPROVED'].includes(order.approval_status)) return '待审批';
  if (order.approval_status === 'REJECTED') return '已驳回';
  return labels[stages.indexOf(order.stage)] || '阶段待确认';
};
const flow = computed(() => order.value?.is_outsourced
  ? stages.filter(stage => ['SALES_CONFIRMED', 'PURCHASING', 'FG_INBOUND', 'SHIPPED'].includes(stage))
  : stages);
const currentStage = computed(() => flow.value.indexOf(order.value?.stage));
const notLive = computed(() => !!order.value?.approval_status && order.value.approval_status !== 'APPROVED');
const progressText = computed(() => notLive.value ? '未开始' : currentStage.value < 0 ? '阶段待确认' : `已走 ${currentStage.value + 1}/${flow.value.length}`);
const stageNotice = computed(() => {
  const po = order.value;
  if (!po || po.stage === 'SHIPPED' || notLive.value) return null;
  if (po.awaiting_bom_confirm) return { text: `等业务确认用料 · ${po.owner_name || '业务'}`, tone: 'text-amber-700' };
  if (po.awaiting_sales_confirm) return { text: po.sales_return_by_name ? `已退回业务 · ${po.sales_return_by_name} 退回` : '已退回业务 · 等业务确认', tone: 'text-rose-600' };
  if (po.stage_ack_at) return { text: po.stage_ack_by_name ? `${po.stage_ack_by_name} 已接单` : '已接单', tone: 'text-teal-700' };
  if (po.ack_overdue) return { text: '超时未接单', tone: 'text-rose-600' };
  if (po.awaiting_ack) return { text: '待接单', tone: 'text-amber-700' };
  return null;
});
const stalledDays = computed(() => {
  const po = order.value;
  if (!po || po.stage === 'SHIPPED' || po.status === 'COMPLETED') return 0;
  const event = (po.stage_events || []).find(e => e.stage === po.stage);
  return event?.entered_at ? Math.round((Date.now() - new Date(event.entered_at)) / 86400000) : 0;
});
onMounted(async () => {
  try {
    if (!productionView.value) {
      const { data } = await ProductionOrdersAPI.get({ list_scope: 'mine', page: 1, per_page: 3 });
      orders.value = data.payload;
    }
    if (!orders.value.length) {
      const { data } = await axios.get(`/api/v1/accounts/${accountId.value}/mes/dashboard`);
      overview.value = data;
    }
  } catch {
    error.value = productionView.value || !orders.value.length ? '暂时无法加载生产数据' : '暂时无法加载订单';
  } finally {
    loading.value = false;
  }
});
</script>

<template>
  <section class="w-full min-w-0 self-stretch rounded-[22px] border border-white/70 bg-white/95 p-4 shadow-sm">
    <div class="flex items-center justify-between gap-3">
      <h2 class="m-0 flex items-center gap-2 text-heading-3 text-[#20241f]"><Icon icon="i-lucide-factory" class="size-5 shrink-0" />{{ showOverview ? 'MES 生产制造' : '我的订单' }}</h2>
      <div v-if="orders.length" class="flex shrink-0 items-center gap-2">
        <span class="text-label-small tabular-nums text-[#73796f]">{{ activeIndex + 1 }} / {{ orders.length }}</span>
        <button type="button" aria-label="上一笔订单" :disabled="activeIndex === 0" class="grid size-7 place-items-center rounded-full border border-black/10 text-[#30382c] hover:bg-black/5 disabled:cursor-default disabled:opacity-30" @click="activeIndex -= 1"><Icon icon="i-lucide-chevron-left" class="size-4" /></button>
        <button type="button" aria-label="下一笔订单" :disabled="activeIndex === orders.length - 1" class="grid size-7 place-items-center rounded-full border border-black/10 text-[#30382c] hover:bg-black/5 disabled:cursor-default disabled:opacity-30" @click="activeIndex += 1"><Icon icon="i-lucide-chevron-right" class="size-4" /></button>
      </div>
    </div>
    <div v-if="loading || error" class="grid min-h-20 place-items-center text-label-small text-[#73796f]" role="status">{{ loading ? '正在加载…' : error }}</div>
    <div v-else-if="showOverview && overview" class="mt-3" aria-label="在产订单阶段分布">
      <div class="mb-3 flex items-baseline gap-1.5"><strong class="text-[28px] font-medium leading-none tabular-nums text-[#20241f]">{{ overview.in_production }}</strong><span class="text-label-small text-[#73796f]">张在产订单</span></div>
      <div class="space-y-2">
        <div v-for="row in productionRows" :key="row.label" class="flex items-center gap-3 text-label-small">
          <span class="w-14 shrink-0 text-[#73796f]">{{ row.label }}</span>
          <svg viewBox="0 0 100 8" preserveAspectRatio="none" class="h-2 min-w-0 flex-1 overflow-hidden rounded-full" role="progressbar" :aria-label="row.label" :aria-valuenow="row.count" :aria-valuemax="overview.in_production || 1" aria-valuemin="0">
            <rect width="100" height="8" rx="4" fill="#eff0ed" />
            <rect :width="overview.in_production ? row.count / overview.in_production * 100 : 0" height="8" rx="4" fill="#c4f246" />
          </svg>
          <span class="w-12 shrink-0 text-right tabular-nums text-[#73796f]">{{ row.count }} / {{ overview.in_production }}</span>
        </div>
      </div>
    </div>
    <div v-else class="mt-3" aria-live="polite" aria-atomic="true">
      <button :key="order.id" type="button" class="block w-full rounded-lg py-1 text-left hover:bg-black/[0.025]" @click="emit('open', order.order_no)">
        <div class="flex items-center justify-between gap-3"><span class="truncate text-heading-3 text-[#20241f]">{{ order.order_no }}</span><span class="shrink-0 rounded-full bg-[#eff6dc] px-2 py-0.5 text-label-small text-[#526333]">{{ stageLabel(order) }}</span></div>
        <div class="mt-1 truncate text-label-small text-[#8a9086]">{{ order.product_name }}</div>
        <div class="my-3 flex items-center gap-3" :aria-label="`订单阶段：${progressText}`">
          <svg viewBox="0 0 100 8" preserveAspectRatio="none" class="h-2.5 min-w-0 flex-1 overflow-hidden rounded-full" role="progressbar" aria-label="订单阶段进度" :aria-valuenow="notLive || currentStage < 0 ? 0 : currentStage + 1" :aria-valuemax="flow.length" aria-valuemin="0">
            <rect width="100" height="8" rx="4" fill="#eff0f1" />
            <rect :width="notLive || currentStage < 0 ? 0 : (currentStage + 1) / flow.length * 100" height="8" rx="4" fill="#c4f246" />
          </svg>
          <span class="text-label-small tabular-nums text-[#858995]">{{ notLive ? '未开始' : currentStage < 0 ? '待确认' : `${currentStage + 1} / ${flow.length}` }}</span>
        </div>
        <div class="flex items-center justify-between gap-3 text-label-small text-[#8a9086]">
          <span>{{ order.delivery_date ? `交期 ${order.delivery_date.slice(0, 10)}` : '交期待定' }}</span>
          <span v-if="stageNotice" class="truncate" :title="`${stageNotice.text}${stalledDays > 0 ? ` · 停留 ${stalledDays} 天` : ''}`">{{ stageNotice.text.split(' · ')[0] }}<template v-if="stalledDays > 0"> · {{ stalledDays }} 天</template></span>
        </div>
      </button>
    </div>
    <button v-if="!showOverview" type="button" class="mt-2 flex items-center gap-1 text-label-small text-[#687064] hover:text-black" @click="emit('open')">全部订单<Icon icon="i-lucide-arrow-up-right" class="size-3.5" /></button>
  </section>
</template>
