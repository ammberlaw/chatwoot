import camelcaseKeys from 'camelcase-keys';
import MesNotificationAPI from 'dashboard/api/mes/notifications';
import { createStore } from 'dashboard/store/storeFactory';
import { throwErrorMessage } from 'dashboard/store/utils/api';

const camelize = data => camelcaseKeys(data || {}, { deep: true });

export const useMesNotificationsStore = createStore({
  name: 'mesNotifications',
  type: 'pinia',
  API: MesNotificationAPI,
  state: () => ({ unreadCount: 0 }),
  getters: {
    getRecords: state => state.records,
    getUnreadCount: state => state.unreadCount,
  },
  actions: () => ({
    async get(params = {}) {
      this.setUIFlag({ fetchingList: true });
      try {
        const { data } = await MesNotificationAPI.get(params);
        this.records = camelize(data.payload);
        this.meta = camelize(data.meta);
        this.unreadCount = Number(data.meta?.unread_count || 0);
        return this.records;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ fetchingList: false });
      }
    },

    // 仅拉未读数（侧栏角标 + ActionCable 实时刷新）。
    async fetchUnreadCount() {
      try {
        const { data } = await MesNotificationAPI.unreadCount();
        this.unreadCount = Number(data.payload?.unread_count || 0);
        return this.unreadCount;
      } catch {
        return this.unreadCount;
      }
    },

    async markRead(id) {
      try {
        await MesNotificationAPI.markRead(id);
        const record = this.records.find(r => r.id === id);
        if (record && !record.readAt) {
          record.readAt = new Date().toISOString();
          this.unreadCount = Math.max(0, this.unreadCount - 1);
        }
      } catch (error) {
        throwErrorMessage(error);
      }
    },

    async markAllRead() {
      try {
        await MesNotificationAPI.markAllRead();
        const now = new Date().toISOString();
        this.records = this.records.map(r => ({ ...r, readAt: r.readAt || now }));
        this.unreadCount = 0;
      } catch (error) {
        throwErrorMessage(error);
      }
    },
  }),
});
