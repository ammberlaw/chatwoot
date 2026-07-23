<script setup>
import { computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesNotificationsStore } from 'dashboard/stores/mes/notifications';
import Button from 'dashboard/components-next/button/Button.vue';

const { accountScopedRoute } = useAccount();
const router = useRouter();
const store = useMesNotificationsStore();

// 通知类型 → 中文标签 + 圆点色。
const KIND_META = {
  approval_pending: { label: '待审批', dot: 'bg-n-amber-9' },
  approval_approved: { label: '审批通过', dot: 'bg-n-teal-9' },
  approval_rejected: { label: '被驳回', dot: 'bg-n-ruby-9' },
  bom_reconfirm: { label: '待确认BOM', dot: 'bg-n-amber-9' },
  bom_confirmed: { label: 'BOM已确认', dot: 'bg-n-teal-9' },
  stage_assigned: { label: '待接单', dot: 'bg-n-iris-9' },
  stage_returned: { label: '被退回', dot: 'bg-n-ruby-9' },
  production_reported: { label: '待成品入库', dot: 'bg-n-iris-9' },
  shipment_approval_pending: { label: '待审核出库', dot: 'bg-n-amber-9' },
  shipment_approved: { label: '待出库', dot: 'bg-n-teal-9' },
  shipment_rejected: { label: '出库被驳回', dot: 'bg-n-ruby-9' },
};
const kindMeta = kind =>
  KIND_META[kind] || { label: '通知', dot: 'bg-n-slate-9' };

const records = computed(() => store.getRecords);
const unreadCount = computed(() => store.getUnreadCount);
const fetching = computed(() => store.getUIFlags.fetchingList);

const fmt = ts =>
  ts ? new Date(ts).toLocaleString('zh-CN', { hour12: false }) : '';

const load = () => store.get();

const openNotification = async n => {
  if (!n.readAt) await store.markRead(n.id);
  if (n.kind && n.kind.startsWith('shipment_')) {
    router.push(
      accountScopedRoute('mes_shipments_index', {}, { kind: 'STOCK' })
    );
  } else if (n.orderNo) {
    router.push(
      accountScopedRoute('mes_production_orders_index', {}, { q: n.orderNo })
    );
  }
};

const markAllRead = () => store.markAllRead();

onMounted(load);
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-background">
    <div
      class="flex items-center justify-between px-6 py-4 border-b border-n-weak"
    >
      <div class="flex items-center gap-2">
        <h1 class="text-xl font-semibold text-n-slate-12">站内通知</h1>
        <span
          v-if="unreadCount > 0"
          class="px-2 py-0.5 text-xs font-medium rounded-full bg-n-ruby-9 text-white"
        >
          {{ unreadCount }} 未读
        </span>
      </div>
      <div class="flex items-center gap-2">
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

    <div class="flex-1 px-6 py-4">
      <div
        v-if="!fetching && records.length === 0"
        class="flex items-center justify-center py-20 text-n-slate-11"
      >
        暂无通知
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
                class="px-1.5 py-0.5 text-2xs font-medium rounded bg-n-alpha-2 text-n-slate-11"
              >
                {{ kindMeta(n.kind).label }}
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
