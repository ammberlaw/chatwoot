<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesNotificationsStore } from 'dashboard/stores/mes/notifications';
import Button from 'dashboard/components-next/button/Button.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import MesTodoPanel from 'dashboard/components-next/mes/MesTodoPanel.vue';

const { accountScopedRoute } = useAccount();
const route = useRoute();
const router = useRouter();
const store = useMesNotificationsStore();

// 同一个页面服务两个板块：MES 看生产流转通知，ERP 看财务（应收分期/应付账期/费用打款）。
// ERP 复用的是同一张通知表，不分开的话生产端打开站内通知会被一屏「应付已逾期」淹掉。
const notifyModule = computed(() => route.meta?.notificationModule || 'mes');
const scopeParams = computed(() =>
  notifyModule.value === 'erp' ? { module: 'erp' } : {}
);
const pageTitle = computed(() =>
  notifyModule.value === 'erp' ? '财务通知' : '站内通知'
);

// 分类：todo 待处理（需我行动）/ progress 进展（知会）/ rejected 退回·驳回（异常）。
// MES：「待我处理」是实时按单据状态算的（原「我的工作台」并进来了），办完自动消失；
// 「进展 / 退回·驳回」才是消息记录。ERP（财务通知）没有待办面，维持原来四个分类。
const MES_GROUPS = [
  { key: 'todo', label: '待我处理' },
  { key: 'progress', label: '进展' },
  { key: 'rejected', label: '退回·驳回' },
];
const ERP_GROUPS = [
  { key: 'all', label: '全部' },
  { key: 'todo', label: '待处理' },
  { key: 'progress', label: '进展' },
  { key: 'rejected', label: '退回·驳回' },
];
// 通知类型 → 中文标签 + 圆点色 + 所属分类。
// ⚠️ 这里的 group **必须与后端 `Mes::Notification::GROUP_BY_KIND` 一致**：tab 的过滤与角标
// 都由后端按全部记录算，这份只负责上色取标签，对不上就会「角标说 5 条、点进去 3 条」。
const KIND_META = {
  approval_pending: { label: '待审批', dot: 'bg-n-amber-9', group: 'todo' },
  approval_approved: {
    label: '审批通过',
    dot: 'bg-n-teal-9',
    group: 'progress',
  },
  approval_rejected: { label: '被驳回', dot: 'bg-n-ruby-9', group: 'rejected' },
  bom_reconfirm: { label: '待确认任务单', dot: 'bg-n-amber-9', group: 'todo' },
  bom_confirmed: {
    label: '任务单已确认',
    dot: 'bg-n-teal-9',
    group: 'progress',
  },
  purchase_release_pending: {
    label: '待下发采购',
    dot: 'bg-n-amber-9',
    group: 'todo',
  },
  po_approval_pending: {
    label: '待审批采购',
    dot: 'bg-n-amber-9',
    group: 'todo',
  },
  po_approval_approved: {
    label: '采购已通过',
    dot: 'bg-n-teal-9',
    group: 'progress',
  },
  po_approval_rejected: {
    label: '采购被驳回',
    dot: 'bg-n-ruby-9',
    group: 'rejected',
  },
  stage_assigned: { label: '待接单', dot: 'bg-n-violet-9', group: 'todo' },
  stage_returned: { label: '被退回', dot: 'bg-n-ruby-9', group: 'rejected' },
  production_reported: {
    label: '待成品入库',
    dot: 'bg-n-violet-9',
    group: 'todo',
  },
  fg_count_pending: { label: '待清点', dot: 'bg-n-violet-9', group: 'todo' },
  shipment_approval_pending: {
    label: '待审核出库',
    dot: 'bg-n-amber-9',
    group: 'todo',
  },
  shipment_approved: { label: '待出库', dot: 'bg-n-teal-9', group: 'todo' },
  shipment_rejected: {
    label: '出库被驳回',
    dot: 'bg-n-ruby-9',
    group: 'rejected',
  },
  document_returned: {
    label: '单据被退回',
    dot: 'bg-n-amber-9',
    group: 'rejected',
  },
  forwarded: { label: '被知会', dot: 'bg-n-violet-9', group: 'progress' },
  // ERP（财务）：只在「财务通知」页出现，MES 站内通知已按模块过滤掉。
  erp_installment_due: {
    label: '应收到期',
    dot: 'bg-n-amber-9',
    group: 'todo',
  },
  erp_payable_due: { label: '应付到期', dot: 'bg-n-amber-9', group: 'todo' },
  erp_expense_paid: {
    label: '费用已打款',
    dot: 'bg-n-teal-9',
    group: 'progress',
  },
};

// 财务通知点进去落到对应的 ERP 页。
const ERP_TARGET = {
  erp_installment_due: 'erp_receivables_index',
  erp_payable_due: 'erp_payables_index',
  erp_expense_paid: 'erp_expenses_index',
};
const kindMeta = kind =>
  KIND_META[kind] || { label: '通知', dot: 'bg-n-slate-9', group: 'progress' };
const groupOf = kind => kindMeta(kind).group;

// 待办类通知一旦已读＝对应动作已办结（审批通过/确认BOM/接单等由后端 resolve 置已读）。
// 「全部」页签会连历史一起列出，此时把「待审批/待接单…」这类待办标签换成「已处理」，
// 避免已审批的单在历史里仍显示「待审批」让人误以为没处理。
// 徽标只在「待办已办结」时出现。其余情况标题里已经写着「待接单：MO…」「审批通过：…」，
// 再并排一个同词徽标纯属重复——类型差异交给左侧圆点的颜色表达。
const isDone = n => Boolean(n.readAt) && groupOf(n.kind) === 'todo';

const isMes = computed(() => notifyModule.value !== 'erp');
const GROUPS = computed(() => (isMes.value ? MES_GROUPS : ERP_GROUPS));
const activeGroup = ref(notifyModule.value === 'erp' ? 'all' : 'todo');
// 「待我处理」面板自己拉数据，条数回传上来做 tab 角标。
const todoPanelRef = ref(null);
const liveTodoCount = ref(0);
// MES 的「待我处理」走实时面板，不走通知记录。
const showTodoPanel = computed(
  () => isMes.value && activeGroup.value === 'todo'
);
// 分类过滤在后端做（接口 group 参数），这里不再二次筛——原先前端只在「当前这 15 条」里筛，
// 于是分页器写着「共 118 项 / 8 页」、列表却只有 2 条，翻页还会再冒出来几条。
const allRecords = computed(() => store.getRecords);
const records = computed(() =>
  // 待处理只显未办结（未读）：办结动作（审批/确认BOM/接单）会由后端把对应待办置已读；
  // 「点开查看」不置已读（见 openNotification），所以看一眼不会误消失。
  activeGroup.value === 'todo'
    ? allRecords.value.filter(n => !n.readAt)
    : allRecords.value
);
// 各分类未读数（tab 角标）：取后端按**全部记录**统计的 group_unread，不是数当前页。
const groupUnread = computed(() => {
  const g = store.getMeta?.groupUnread || {};
  const counts = {
    all: Number(store.getUnreadCount || 0),
    todo: Number(g.todo || 0),
    progress: Number(g.progress || 0),
    rejected: Number(g.rejected || 0),
  };
  // MES 的「待我处理」按实时待办数显示，不是未读消息数。
  if (isMes.value) counts.todo = liveTodoCount.value;
  return counts;
});
const unreadCount = computed(() => store.getUnreadCount);
const fetching = computed(() => store.getUIFlags.fetchingList);

// 时间给人看，不是给日志看：今天只给时:分，昨天标「昨天」，更早给月-日。
const fmt = ts => {
  if (!ts) return '';
  const d = new Date(ts);
  const p = n => String(n).padStart(2, '0');
  const hm = `${p(d.getHours())}:${p(d.getMinutes())}`;
  const today = new Date();
  const dayDiff = Math.round(
    (new Date(today.getFullYear(), today.getMonth(), today.getDate()) -
      new Date(d.getFullYear(), d.getMonth(), d.getDate())) /
      86400000
  );
  if (dayDiff === 0) return hm;
  if (dayDiff === 1) return `昨天 ${hm}`;
  return `${p(d.getMonth() + 1)}-${p(d.getDate())} ${hm}`;
};

// 后端每页 15 条。原来这里不传页码、页面也没有翻页器，生产上 458 条通知
// 只看得到最新 15 条，老的永远翻不到。
const ITEMS_PER_PAGE = 15;
const currentPage = ref(1);
const totalCount = computed(() => store.getMeta?.count || 0);
const load = () =>
  store.get({
    ...scopeParams.value,
    page: currentPage.value,
    // 'all'（财务通知的「全部」）不传，后端不过滤。
    ...(activeGroup.value === 'all' ? {} : { group: activeGroup.value }),
  });
watch(currentPage, load);
// 切分类回到第 1 页：换了分类总条数和页数都变了，停在第 3 页切过去会看着像没有数据。
watch(activeGroup, () => {
  if (currentPage.value === 1) load();
  else currentPage.value = 1;
});

// 落到「待我审批」inbox 的通知（审批/待确认BOM）——该 inbox 跨产品线取「待我处理」的单，
// 不受全局产品线选择器过滤；其余订单通知走普通列表按单号定位。
const APPROVAL_INBOX_KINDS = ['approval_pending', 'bom_reconfirm'];

const openNotification = async n => {
  // 待办类不因「点开查看」置已读——只有真正办结（审批/确认等动作）才由后端销掉，避免误清。
  // 进展/退回类是知会信息，点开即已读。
  if (!n.readAt && groupOf(n.kind) !== 'todo') await store.markRead(n.id);
  if (ERP_TARGET[n.kind]) {
    router.push(accountScopedRoute(ERP_TARGET[n.kind]));
  } else if (n.kind && n.kind.startsWith('shipment_')) {
    router.push(
      accountScopedRoute('mes_shipments_index', {}, { kind: 'STOCK' })
    );
  } else if (n.kind && n.kind.startsWith('po_approval')) {
    // 采购审批：进「采购单」板块（总经理在此通过/驳回），有单号则按生产订单号定位。
    router.push(
      accountScopedRoute(
        'mes_purchase_orders_index',
        {},
        n.orderNo ? { q: n.orderNo } : {}
      )
    );
  } else if (n.orderNo) {
    // 待审批/待确认BOM：进「待我审批」inbox（含该单，跨产品线）并按单号自动打开审批详情；
    // 否则进普通列表按单号搜索定位。
    const query = APPROVAL_INBOX_KINDS.includes(n.kind)
      ? { view: 'approval', q: n.orderNo }
      : { q: n.orderNo };
    router.push(accountScopedRoute('mes_production_orders_index', {}, query));
  }
};

const markAllRead = () => store.markAllRead(scopeParams.value);
// 「待我处理」是实时面板，刷新要刷它；其余页签刷通知列表。
const refresh = () => {
  if (showTodoPanel.value) todoPanelRef.value?.reload();
  else load();
};

onMounted(load);
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div
      class="flex items-center justify-between gap-2 px-4 py-3 border-b sm:px-6 sm:py-4 border-n-weak [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:sm:!px-8"
    >
      <div class="flex items-center min-w-0 gap-2">
        <h1 class="text-xl font-semibold truncate text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8">
          {{ pageTitle }}
        </h1>
        <span
          v-if="unreadCount > 0"
          class="px-2 py-0.5 text-xs font-medium rounded-full bg-n-amber-9 text-[#1a1c20]"
        >
          {{ unreadCount }} 未读
        </span>
      </div>
      <div class="flex items-center gap-2 shrink-0">
        <Button
          label="刷新"
          variant="outline"
          color="slate"
          size="sm"
          :is-loading="fetching"
          @click="refresh"
        />
        <Button
          v-if="!showTodoPanel"
          label="全部已读"
          color="slate"
          size="sm"
          :disabled="unreadCount === 0"
          @click="markAllRead"
        />
      </div>
    </div>

    <!-- 分类筛选：全站统一的页面级 Tab（灰槽 + 深色选中块），样式见 _next-colors.scss，
         这里只挂 data-tabbar 与 aria-selected，不要再写边框/底色。 -->
    <div class="px-4 pt-3 sm:px-6 [.theme-classic_&]:sm:!px-8">
      <div data-tabbar="page">
        <button
          v-for="g in GROUPS"
          :key="g.key"
          :aria-selected="activeGroup === g.key"
          @click="activeGroup = g.key"
        >
          {{ g.label }}
          <span
            v-if="groupUnread[g.key] > 0"
            class="ml-1 px-1.5 py-0.5 text-2xs font-semibold rounded-full bg-n-amber-9 text-[#1a1c20]"
          >
            {{ groupUnread[g.key] }}
          </span>
        </button>
      </div>
    </div>

    <div class="flex-1 px-4 py-3 sm:px-6 sm:py-4 [.theme-classic_&]:sm:!px-8">
      <MesTodoPanel
        v-if="showTodoPanel"
        ref="todoPanelRef"
        @update:count="n => (liveTodoCount = n)"
      />
      <div
        v-else-if="!fetching && records.length === 0"
        class="flex items-center justify-center py-20 text-n-slate-11"
      >
        {{ activeGroup === 'all' ? '暂无通知' : '该分类暂无通知' }}
      </div>

      <ul v-else class="flex flex-col gap-1.5">
        <li
          v-for="n in records"
          :key="n.id"
          class="relative flex items-start gap-2.5 py-2 pr-3 pl-3.5 overflow-hidden transition-colors border rounded-lg cursor-pointer"
          :class="
            n.readAt
              ? 'border-n-weak bg-n-solid-1 hover:bg-n-alpha-2'
              : 'border-n-strong bg-n-solid-1 hover:bg-n-alpha-2'
          "
          @click="openNotification(n)"
        >
          <!-- 未读：左侧按类型上色的竖条。原来整行淡紫底，已读未读几乎看不出差别，
               类型也全靠一个 8px 的小圆点，待审批和被退回长得一模一样。 -->
          <span
            v-if="!n.readAt"
            class="absolute inset-y-0 left-0 w-1"
            :class="kindMeta(n.kind).dot"
          />
          <div class="flex flex-col flex-1 min-w-0 gap-0.5">
            <div class="flex items-baseline gap-2">
              <span
                class="text-sm truncate"
                :class="
                  n.readAt ? 'text-n-slate-11' : 'font-semibold text-n-slate-12'
                "
              >
                {{ n.title }}
              </span>
              <!-- 只在待办已办结时出现：标题还写着「待审批」，得标出来它已经处理过了 -->
              <span
                v-if="isDone(n)"
                class="px-1.5 py-0.5 rounded text-2xs font-medium shrink-0 bg-n-teal-3 text-n-teal-11"
              >
                已处理
              </span>
              <span
                class="ml-auto text-xs tabular-nums shrink-0 text-n-slate-10"
              >
                {{ fmt(n.createdAt) }}
              </span>
            </div>
            <p v-if="n.body" class="text-xs truncate text-n-slate-11">
              {{ n.body }}
            </p>
          </div>
        </li>
      </ul>

      <PaginationFooter
        v-if="!showTodoPanel && totalCount > ITEMS_PER_PAGE"
        :current-page="currentPage"
        :total-items="totalCount"
        :items-per-page="ITEMS_PER_PAGE"
        class="!bg-transparent before:!hidden"
        @update:current-page="currentPage = $event"
      />
    </div>
  </div>
</template>
