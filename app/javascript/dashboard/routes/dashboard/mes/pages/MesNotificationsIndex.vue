<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesNotificationsStore } from 'dashboard/stores/mes/notifications';
import Button from 'dashboard/components-next/button/Button.vue';

const { accountScopedRoute } = useAccount();
const router = useRouter();
const store = useMesNotificationsStore();

// 分类：todo 待处理（需我行动）/ progress 进展（知会）/ rejected 退回·驳回（异常）。
const GROUPS = [
  { key: 'all', label: '全部' },
  { key: 'todo', label: '待处理' },
  { key: 'progress', label: '进展' },
  { key: 'rejected', label: '退回·驳回' },
];
// 通知类型 → 中文标签 + 圆点色 + 所属分类。
const KIND_META = {
  approval_pending: { label: '待审批', dot: 'bg-n-amber-9', group: 'todo' },
  approval_approved: {
    label: '审批通过',
    dot: 'bg-n-teal-9',
    group: 'progress',
  },
  approval_rejected: { label: '被驳回', dot: 'bg-n-ruby-9', group: 'rejected' },
  bom_reconfirm: { label: '待确认BOM', dot: 'bg-n-amber-9', group: 'todo' },
  bom_confirmed: { label: 'BOM已确认', dot: 'bg-n-teal-9', group: 'progress' },
  purchase_release_pending: {
    label: '待下发采购',
    dot: 'bg-n-amber-9',
    group: 'todo',
  },
  stage_assigned: { label: '待接单', dot: 'bg-n-iris-9', group: 'todo' },
  stage_returned: { label: '被退回', dot: 'bg-n-ruby-9', group: 'rejected' },
  production_reported: {
    label: '待成品入库',
    dot: 'bg-n-iris-9',
    group: 'todo',
  },
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
  forwarded: { label: '被知会', dot: 'bg-n-iris-9', group: 'progress' },
};
const kindMeta = kind =>
  KIND_META[kind] || { label: '通知', dot: 'bg-n-slate-9', group: 'progress' };
const groupOf = kind => kindMeta(kind).group;

// 待办类通知一旦已读＝对应动作已办结（审批通过/确认BOM/接单等由后端 resolve 置已读）。
// 「全部」页签会连历史一起列出，此时把「待审批/待接单…」这类待办标签换成「已处理」，
// 避免已审批的单在历史里仍显示「待审批」让人误以为没处理。
const chipLabel = n =>
  n.readAt && groupOf(n.kind) === 'todo' ? '已处理' : kindMeta(n.kind).label;
const chipClass = n =>
  n.readAt && groupOf(n.kind) === 'todo'
    ? 'bg-n-teal-3 text-n-teal-11'
    : 'bg-n-alpha-2 text-n-slate-11';

const activeGroup = ref('all');
const allRecords = computed(() => store.getRecords);
const records = computed(() => {
  if (activeGroup.value === 'all') return allRecords.value;
  const inGroup = allRecords.value.filter(
    n => groupOf(n.kind) === activeGroup.value
  );
  // 待处理只显未办结（未读）：办结动作（审批/确认BOM/接单）会由后端把对应待办置已读；
  // 「点开查看」不置已读（见 openNotification），所以看一眼不会误消失。
  return activeGroup.value === 'todo'
    ? inGroup.filter(n => !n.readAt)
    : inGroup;
});
// 各分类未读数（tab 角标）。
const groupUnread = computed(() => {
  const counts = { all: 0, todo: 0, progress: 0, rejected: 0 };
  allRecords.value.forEach(n => {
    if (n.readAt) return;
    counts.all += 1;
    counts[groupOf(n.kind)] += 1;
  });
  return counts;
});
const unreadCount = computed(() => store.getUnreadCount);
const fetching = computed(() => store.getUIFlags.fetchingList);

const fmt = ts =>
  ts ? new Date(ts).toLocaleString('zh-CN', { hour12: false }) : '';

const load = () => store.get();

// 落到「待我审批」inbox 的通知（审批/待确认BOM）——该 inbox 跨产品线取「待我处理」的单，
// 不受全局产品线选择器过滤；其余订单通知走普通列表按单号定位。
const APPROVAL_INBOX_KINDS = ['approval_pending', 'bom_reconfirm'];

const openNotification = async n => {
  // 待办类不因「点开查看」置已读——只有真正办结（审批/确认等动作）才由后端销掉，避免误清。
  // 进展/退回类是知会信息，点开即已读。
  if (!n.readAt && groupOf(n.kind) !== 'todo') await store.markRead(n.id);
  if (n.kind && n.kind.startsWith('shipment_')) {
    router.push(
      accountScopedRoute('mes_shipments_index', {}, { kind: 'STOCK' })
    );
  } else if (n.orderNo) {
    // 待审批/待确认BOM：进「待我审批」inbox（含该单，跨产品线）并按单号自动打开审批详情；
    // 否则进普通列表按单号搜索定位。
    const query = APPROVAL_INBOX_KINDS.includes(n.kind)
      ? { view: 'approval', q: n.orderNo }
      : { q: n.orderNo };
    router.push(
      accountScopedRoute('mes_production_orders_index', {}, query)
    );
  }
};

const markAllRead = () => store.markAllRead();

onMounted(load);
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div
      class="flex items-center justify-between gap-2 px-4 py-3 border-b sm:px-6 sm:py-4 border-n-weak"
    >
      <div class="flex items-center min-w-0 gap-2">
        <h1 class="text-xl font-semibold truncate text-n-slate-12">站内通知</h1>
        <span
          v-if="unreadCount > 0"
          class="px-2 py-0.5 text-xs font-medium rounded-full bg-n-ruby-9 text-white"
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
          @click="load"
        />
        <Button
          label="全部已读"
          color="slate"
          size="sm"
          :disabled="unreadCount === 0"
          @click="markAllRead"
        />
      </div>
    </div>

    <!-- 分类筛选 -->
    <div class="flex flex-wrap items-center gap-2 px-4 pt-3 sm:px-6">
      <button
        v-for="g in GROUPS"
        :key="g.key"
        class="px-3 py-1.5 text-sm rounded-lg border"
        :class="
          activeGroup === g.key
            ? 'border-n-iris-8 bg-n-iris-3 text-n-iris-12'
            : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
        "
        @click="activeGroup = g.key"
      >
        {{ g.label }}
        <span
          v-if="groupUnread[g.key] > 0"
          class="ml-1 px-1.5 py-0.5 text-2xs rounded-full bg-n-ruby-9 text-white"
        >
          {{ groupUnread[g.key] }}
        </span>
      </button>
    </div>

    <div class="flex-1 px-4 py-3 sm:px-6 sm:py-4">
      <div
        v-if="!fetching && records.length === 0"
        class="flex items-center justify-center py-20 text-n-slate-11"
      >
        {{ activeGroup === 'all' ? '暂无通知' : '该分类暂无通知' }}
      </div>

      <ul v-else class="flex flex-col gap-2">
        <li
          v-for="n in records"
          :key="n.id"
          class="flex items-start gap-3 p-3 rounded-lg border cursor-pointer transition-colors"
          :class="
            n.readAt
              ? 'border-n-weak bg-n-solid-1 hover:bg-n-alpha-2'
              : 'border-n-iris-5 bg-n-iris-2 hover:bg-n-iris-3'
          "
          @click="openNotification(n)"
        >
          <span
            class="mt-1.5 size-2 rounded-full shrink-0"
            :class="n.readAt ? 'bg-n-slate-6' : kindMeta(n.kind).dot"
          />
          <div class="flex flex-col flex-1 min-w-0 gap-0.5">
            <div class="flex items-center gap-2">
              <span
                class="px-1.5 py-0.5 text-2xs font-medium rounded"
                :class="chipClass(n)"
              >
                {{ chipLabel(n) }}
              </span>
              <span class="text-sm font-medium truncate text-n-slate-12">
                {{ n.title }}
              </span>
            </div>
            <p class="text-sm text-n-slate-11 line-clamp-2">{{ n.body }}</p>
            <span class="text-xs text-n-slate-10">{{ fmt(n.createdAt) }}</span>
          </div>
        </li>
      </ul>
    </div>
  </div>
</template>
