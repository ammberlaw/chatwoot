<script>
import { mapGetters } from 'vuex';
import { useTrack } from 'dashboard/composables';
import TableFooter from 'dashboard/components/widgets/TableFooter.vue';

import NotificationTable from './NotificationTable.vue';

import { ACCOUNT_EVENTS } from '../../../../helper/AnalyticsHelper/events';
export default {
  components: {
    NotificationTable,
    TableFooter,
  },
  computed: {
    ...mapGetters({
      accountId: 'getCurrentAccountId',
      meta: 'notifications/getMeta',
      records: 'notifications/getNotifications',
      uiFlags: 'notifications/getUIFlags',
    }),
  },
  mounted() {
    this.$store.dispatch('notifications/get', { page: 1 });
  },
  methods: {
    onPageChange(page) {
      window.history.pushState({}, null, `${this.$route.path}?page=${page}`);
      this.$store.dispatch('notifications/get', { page });
    },
    openConversation(notification) {
      const {
        primary_actor_id: primaryActorId,
        primary_actor_type: primaryActorType,
        primary_actor: { id: conversationId },
        notification_type: notificationType,
      } = notification;

      useTrack(ACCOUNT_EVENTS.OPEN_CONVERSATION_VIA_NOTIFICATION, {
        notificationType,
      });
      this.$store.dispatch('notifications/read', {
        id: notification.id,
        primaryActorId,
        primaryActorType,
        unreadCount: this.meta.unreadCount,
      });

      this.$router.push(
        `/app/accounts/${this.accountId}/conversations/${conversationId}`
      );
    },
    onMarkAllDoneClick() {
      useTrack(ACCOUNT_EVENTS.MARK_AS_READ_NOTIFICATIONS);
      this.$store.dispatch('notifications/readAll');
    },
  },
};
</script>

<template>
  <!-- 页码留在滚动区**外面**：原来整页一起滚，翻页得先划到通知列表最底下
       （2026-10-31 反馈「把所有有页码的地方都改成页码钉住」）。
       这里的 TableFooter 没有实色底，不能像 PaginationFooter 那样靠 sticky 浮着——
       浮起来会看见底下的通知行透出来。 -->
  <div class="flex flex-col h-full">
    <div class="flex-1 min-h-0 overflow-y-auto">
      <NotificationTable
        :notifications="records"
        :is-loading="uiFlags.isFetching"
        :is-updating="uiFlags.isUpdating"
        :on-click-notification="openConversation"
        :on-mark-all-done-click="onMarkAllDoneClick"
      />
    </div>
    <TableFooter
      class="border-t border-n-weak shrink-0"
      :current-page="Number(meta.currentPage)"
      :total-count="meta.count"
      :page-size="15"
      @page-change="onPageChange"
    />
  </div>
</template>
