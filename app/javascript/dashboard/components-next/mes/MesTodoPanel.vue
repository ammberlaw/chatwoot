<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import MesProductionOrderAPI from 'dashboard/api/mes/productionOrders';
import MesShipmentAPI from 'dashboard/api/mes/shipments';
import MesPurchaseOrderAPI from 'dashboard/api/mes/purchaseOrders';

// 「待我处理」：按单据状态实时算出来的待办（原「我的工作台」），办完自动消失。
// 行的样式跟站内通知的消息行一致——同一个页面里两种列表长得不一样最难看。
const emit = defineEmits(['update:count']);

const { accountScopedRoute } = useAccount();
const router = useRouter();

const STAGE_LABELS = {
  SALES_CONFIRMED: '待工程接单',
  BOM_READY: '工程/PMC 生产任务单',
  PURCHASING: '采购原料',
  MATERIAL_INBOUND: '原料入库',
  PICKING: '生产领料',
  PRODUCTION: '生产',
  FG_INBOUND: '成品入库',
  SHIPPED: '销售出库',
};
const stageLabel = s => STAGE_LABELS[s] || s;

// 本阶段停留天数（进入阶段至今）。
const stallDays = enteredAt =>
  enteredAt ? Math.round((Date.now() - new Date(enteredAt)) / 86400000) : null;
// 接单截止（工作时间口径，后端已算好）。
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
const approvalInbox = ref([]); // 停在我这一级的审批单
const inbox = ref([]); // 停在我负责阶段的在产订单
const shipmentInbox = ref([]); // 停在我这一级的现货出库单
// 停在我这一级的采购单。原先这个面板只拉生产订单/接单/出库三类，**采购审批漏了**——
// 总经理那边 13 张待批采购单一张都不出现，站内通知虽然发了却只躺在「进展」里，
// 人只看到「待我处理 1 条」，以为没事。
const purchaseInbox = ref([]);

const load = async () => {
  loading.value = true;
  try {
    const empty = { data: { payload: [] } };
    const [approvalRes, inboxRes, shipmentRes, purchaseRes] = await Promise.all(
      [
        MesProductionOrderAPI.approvalInbox(),
        MesProductionOrderAPI.inbox(),
        MesShipmentAPI.approvalInbox().catch(() => empty),
        // 无采购权限的人调这个会 403，吞掉即可——不该让整个待办面板空掉。
        MesPurchaseOrderAPI.approvalInbox().catch(() => empty),
      ]
    );
    approvalInbox.value = approvalRes?.data?.payload || [];
    inbox.value = inboxRes?.data?.payload || [];
    shipmentInbox.value = shipmentRes?.data?.payload || [];
    purchaseInbox.value = purchaseRes?.data?.payload || [];
  } catch {
    approvalInbox.value = [];
    inbox.value = [];
    shipmentInbox.value = [];
    purchaseInbox.value = [];
  } finally {
    loading.value = false;
  }
};

// 接单态 → 右侧小字 + 配色（超时最刺眼，其次待接单，处理中最淡）。
const ACK_STATE = {
  overdue: { tag: '超时未接单', cls: 'text-n-ruby-11' },
  waiting: { tag: '待接单', cls: 'text-n-amber-11' },
  working: { tag: '处理中', cls: 'text-n-teal-11' },
};
const ackStateOf = o => {
  if (o.ack_overdue) return ACK_STATE.overdue;
  return o.awaiting_ack ? ACK_STATE.waiting : ACK_STATE.working;
};

// 生产订单走固定的两级链（部门主管 → 总经理），这里的头衔是对的；
// 采购单的审批人是按产线配的，不能套用这套说法。
const APPROVAL_STEP = {
  SUBMITTED: '待你（部门主管）审',
  MANAGER_APPROVED: '待你（总经理）审',
};

// 跳转：审批单 → 订单页「待我审批」视图；出库 → 出库页按现货筛；其余 → 订单详情。
const goApproval = orderNo =>
  router.push(
    accountScopedRoute(
      'mes_production_orders_index',
      {},
      { q: orderNo, view: 'approval' }
    )
  );
const goPurchase = poNo =>
  router.push(
    accountScopedRoute(
      'mes_purchase_orders_index',
      {},
      { q: poNo, view: 'approval' }
    )
  );
const goShipment = () =>
  router.push(accountScopedRoute('mes_shipments_index', {}, { kind: 'STOCK' }));
const goOrder = orderNo =>
  router.push(
    accountScopedRoute('mes_production_orders_index', {}, { q: orderNo })
  );

// 每个阶段对应一步具体操作 + 落到哪个操作页（携订单号预筛）。
const STAGE_ACTION = {
  SALES_CONFIRMED: { label: '去挂生产任务单', route: 'mes_boms_index' },
  BOM_READY: { label: '去做生产任务单', route: 'mes_boms_index' },
  PURCHASING: { label: '去下采购单', route: 'mes_purchase_orders_index' },
  MATERIAL_INBOUND: { label: '去收货入库', route: 'mes_stock_entries_index' },
  PICKING: { label: '去领料', route: 'mes_material_issues_index' },
  PRODUCTION: { label: '去报工', route: 'mes_production_records_index' },
  FG_INBOUND: { label: '去成品入库', route: 'mes_fg_inbound_index' },
};

// 采购原料阶段的三态（后端 purchase_state）。别的阶段干完活订单就往下走、待办自然消失，
// 只有采购下完单后要等料到齐才推进，所以要把「该下单」「等货」「货迟了」分开：
//   TODO    还没下采购单        → 催下单，留在「待我处理」
//   WAITING 下了单、没到交期     → 正常等货，归「进行中」、不进角标、不再提示「去下采购单」
//   URGING  下了单、过了交期没到 → 该催供应商了，回到「待我处理」并标红
const PURCHASE_VIEW = {
  TODO: {
    working: false,
    bar: 'bg-n-iris-9',
    prefix: '待处理',
    tag: '待下采购单',
    cls: 'text-n-amber-11',
  },
  WAITING: {
    working: true,
    bar: 'bg-n-slate-6',
    prefix: '等料中',
    tag: '等料中',
    cls: 'text-n-slate-11',
    hideAction: true,
  },
  URGING: {
    working: false,
    bar: 'bg-n-ruby-9',
    prefix: '催货',
    tag: '逾期未到料',
    cls: 'text-n-ruby-11',
  },
};
const fmtDue = d => {
  if (!d) return null;
  const t = new Date(d);
  return `${t.getMonth() + 1}/${t.getDate()}`;
};
// 右侧小字：已下几张单、最早交期、逾期几天。
const purchaseView = o => {
  const base = PURCHASE_VIEW[o.purchase_state];
  if (!base) return null;
  const s = o.purchase_summary || {};
  const detail = [
    s.count ? `已下 ${s.count} 张采购单` : null,
    s.overdue_days
      ? `逾期 ${s.overdue_days} 天`
      : (s.earliest_due && `最早交期 ${fmtDue(s.earliest_due)}`) || null,
  ]
    .filter(Boolean)
    .join(' · ');
  return { ...base, detail: detail || null };
};

// 三类待办拍平成同一种行结构，渲染时不用再分三块。
const items = computed(() => [
  ...approvalInbox.value.map(o => ({
    key: `ap-${o.id}`,
    // sig 不能少：isAcked 比的是 acked[key] === it.sig，没有 sig 就是
    // undefined === undefined 恒真，这类待办会被当成「已点过知道了」全部过滤掉——
    // 审批待办因此从来没在这一屏出现过（角标却照数，于是「有未读、点开空白」）。
    // 审批往前走一级（SUBMITTED→MANAGER_APPROVED）指纹就变，条目会重新冒出来。
    sig: `ap|${o.approval_status}`,
    bar: 'bg-n-amber-9',
    title: `待审批：${o.order_no}`,
    body: [o.product_name, o.pi_no ? `PI ${o.pi_no}` : null, o.owner_name]
      .filter(Boolean)
      .join(' · '),
    tag: APPROVAL_STEP[o.approval_status] || '待你处理',
    tagClass: 'text-n-amber-11',
    open: () => goApproval(o.order_no),
  })),
  ...purchaseInbox.value.map(p => ({
    key: `po-${p.id}`,
    sig: `po|${p.po_no}`,
    bar: 'bg-n-iris-9',
    title: `待审批采购单：${p.po_no}`,
    body: [p.supplier_names?.join('、'), p.production_order_no, p.owner_name]
      .filter(Boolean)
      .join(' · '),
    // 采购审批人按产品线配，可能是副总经理等任何人，别写死头衔（见采购单页「采购审批人」）
    tag: '待你审批',
    tagClass: 'text-n-iris-11',
    open: () => goPurchase(p.po_no),
  })),
  ...shipmentInbox.value.map(s => ({
    key: `sh-${s.id}`,
    sig: `sh|${s.shipment_no}`,
    bar: 'bg-n-teal-9',
    title: `待审核：${s.shipment_no}`,
    body: [s.customer_name || '—', s.owner_name].filter(Boolean).join(' · '),
    tag: '待你（部门主管）审',
    tagClass: 'text-n-teal-11',
    open: goShipment,
  })),
  ...inbox.value.map(o => {
    const act = STAGE_ACTION[o.stage];
    const days = stallDays(o.entered_at);
    const ack = ackStateOf(o);
    const pur = purchaseView(o);
    return {
      key: `in-${o.id}`,
      // 指纹只放会变的状态位，不放「停留 N 天」——那个每天都变，按掉的提示第二天又冒出来。
      sig: `in|${o.stage}|${o.awaiting_ack ? 1 : 0}|${pur ? pur.prefix : ''}`,
      // 已接单＝正在做，不算「待我处理」；采购阶段另按三态定（等料中归「进行中」）。
      working: pur ? pur.working : !o.awaiting_ack,
      bar: pur ? pur.bar : (o.ack_overdue && 'bg-n-ruby-9') || 'bg-n-iris-9',
      title: `${pur ? pur.prefix : (o.awaiting_ack && '待接单') || '待处理'}：${o.order_no}`,
      body: [
        o.product_name,
        stageLabel(o.stage),
        pur ? pur.detail : null,
        days === null ? null : `停留 ${days} 天`,
        o.ack_deadline ? `接单截止 ${deadlineText(o.ack_deadline)}` : null,
      ]
        .filter(Boolean)
        .join(' · '),
      tag: pur ? pur.tag : ack.tag,
      tagClass: pur ? pur.cls : ack.cls,
      open: () => goOrder(o.order_no),
      action:
        act && !(pur && pur.hideAction)
          ? {
              label: act.label,
              run: () =>
                router.push(
                  accountScopedRoute(act.route, {}, { q: o.order_no })
                ),
            }
          : null,
    };
  }),
]);

// 「待我处理」= 真正等我动手的：审批、出库审核、**还没接单**的订单。
// 已接单的单子只要还停在我这个阶段就会一直被算进来，接了单也不消、点几次都还在
// （用户原话）。这类归到「进行中」单独一组，且不进角标——角标虚高，看久了就没人信。
// 「知道了」：这一屏的待办是按单据实时算出来的（不是 mes_notifications 里的记录），
// 单子状态不变就会一直挂在这儿——采购的原话「不需要处理的事情，也要点进去看，
// 点进去后还是显示未读」。所以给每条一个「知道了」，按人记在本机。
//
// 记的是 key + 状态指纹：单子一动（阶段变了、接单了、采购下单了）指纹就变，这条会重新冒出来，
// 不至于把真要处理的单永久藏掉。只记在本机是有意的——这是「提示噪音」，不是业务数据，
// 为它建表、起接口不划算（换台电脑重新冒出来反而是安全的一侧）。
const ACK_KEY = 'mes.todo.acked.v1';
const readAcked = () => {
  try {
    return JSON.parse(localStorage.getItem(ACK_KEY) || '{}');
  } catch {
    return {};
  }
};
const acked = ref(readAcked());
const ackOne = it => {
  const next = { ...acked.value, [it.key]: it.sig };
  acked.value = next;
  try {
    localStorage.setItem(ACK_KEY, JSON.stringify(next));
  } catch {
    // 隐私模式下写不进去：这轮内存里仍然生效，刷新后重新出现，不影响用单
  }
};
const isAcked = it => acked.value[it.key] === it.sig;

const pending = computed(() =>
  items.value.filter(it => !it.working && !isAcked(it))
);
const working = computed(() => items.value.filter(it => it.working));
// 渲染顺序：待处理在前，中间插一行分组标题，进行中在后。
const rows = computed(() => [
  ...pending.value,
  ...(working.value.length
    ? [{ key: 'divider', divider: true, count: working.value.length }]
    : []),
  ...working.value,
]);

const total = computed(() => items.value.length);
watch(
  () => pending.value.length,
  n => emit('update:count', n),
  {
    immediate: true,
  }
);
onMounted(load);
// 父级（站内通知页）点「刷新」时重拉——办完的事要即时消失。
defineExpose({ reload: load });
</script>

<template>
  <div v-if="loading" class="py-10 text-center text-n-slate-11">加载中…</div>
  <div
    v-else-if="!total"
    class="flex items-center justify-center py-20 text-n-slate-11"
  >
    暂无待你处理的事
  </div>
  <ul v-else class="flex flex-col gap-1.5">
    <li
      v-for="it in rows"
      :key="it.key"
      :class="
        it.divider
          ? 'flex items-center gap-2 pt-3 pb-1'
          : 'relative flex items-start gap-2.5 py-2 pr-3 pl-3.5 overflow-hidden transition-colors border rounded-lg cursor-pointer border-n-strong bg-n-solid-1 hover:bg-n-alpha-2'
      "
      @click="it.divider ? null : it.open()"
    >
      <!-- 分组标题：已接单、正在做的单子，不算待办 -->
      <template v-if="it.divider">
        <span class="text-xs font-medium text-n-slate-11">
          进行中（已接单，等你推进）
        </span>
        <span class="text-xs text-n-slate-10">{{ it.count }}</span>
      </template>
      <template v-else>
        <!-- 左侧竖条按类型上色，跟消息行同一套视觉 -->
        <span class="absolute inset-y-0 left-0 w-1" :class="it.bar" />
        <div class="flex flex-col flex-1 min-w-0 gap-0.5">
          <div class="flex items-baseline gap-2">
            <span class="text-sm font-semibold truncate text-n-slate-12">
              {{ it.title }}
            </span>
            <span class="ml-auto text-xs shrink-0" :class="it.tagClass">
              {{ it.tag }}
            </span>
          </div>
          <p class="text-xs truncate text-n-slate-11">{{ it.body }}</p>
        </div>
        <!-- 「知道了」：这条不用我管，别再占着待办。单子状态一变会重新冒出来。
             只对还没接单的待办给，进行中的单本来就不在角标里。 -->
        <button
          v-if="!it.working"
          type="button"
          title="这条我知道了，先从待办里收起（单子状态一变会重新出现）"
          class="self-center px-2 py-1 text-xs border rounded-md shrink-0 reset-base border-n-weak text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
          @click.stop="ackOne(it)"
        >
          知道了
        </button>
        <button
          v-if="it.action"
          type="button"
          class="flex items-center self-center gap-1 px-2.5 py-1 text-xs font-medium text-white rounded-md shrink-0 bg-n-iris-9 hover:bg-n-iris-10"
          @click.stop="it.action.run()"
        >
          {{ it.action.label }}
          <span class="i-lucide-arrow-right size-3" />
        </button>
      </template>
    </li>
  </ul>
</template>
