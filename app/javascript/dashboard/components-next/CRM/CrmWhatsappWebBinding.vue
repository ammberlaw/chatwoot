<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useAlert } from 'dashboard/composables';
import WhatsappWebAPI from 'dashboard/api/crm/whatsappWeb';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const L = {
  connect: '连接 WhatsApp',
  logout: '解绑',
  scanHint: '用手机 WhatsApp → 设置 → 已关联的设备 → 关联新设备，扫描二维码',
  waiting: '正在生成二维码…',
  connecting: '连接中…',
  connected: '已连接',
  disconnected: '未连接',
  reconnecting: '连接断开，正在自动重连…',
  logoutConfirm:
    '确定解绑该 WhatsApp 号？历史会话与客户记录会保留，但将停止收发消息。',
  connectError: '连接失败，请稍后重试',
  logoutDone: '已解绑',
};

const state = ref({ status: 'disconnected', qr: null, phoneNumber: null });
const loading = ref(false);
let pollTimer = null;

const status = computed(() => state.value.status);
const isOpen = computed(() => status.value === 'open');
const isPending = computed(() =>
  ['connecting', 'qr', 'close'].includes(status.value)
);

const statusLabel = computed(() => {
  switch (status.value) {
    case 'open':
      return L.connected;
    case 'close':
      return L.reconnecting;
    case 'connecting':
    case 'qr':
      return L.connecting;
    default:
      return L.disconnected;
  }
});

const applyState = data => {
  state.value = {
    status: data.status || 'disconnected',
    qr: data.qr || null,
    phoneNumber: data.phone_number || null,
  };
};

const stopPolling = () => {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
};

const startPolling = () => {
  stopPolling();
  pollTimer = setInterval(async () => {
    try {
      const { data } = await WhatsappWebAPI.status();
      applyState(data);
      if (data.status === 'open' || data.status === 'disconnected')
        stopPolling();
    } catch (e) {
      stopPolling();
    }
  }, 2500);
};

const connect = async () => {
  loading.value = true;
  try {
    const { data } = await WhatsappWebAPI.connect();
    applyState(data);
    startPolling();
  } catch (e) {
    useAlert(L.connectError);
  } finally {
    loading.value = false;
  }
};

const logout = async () => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(L.logoutConfirm)) return;
  loading.value = true;
  try {
    const { data } = await WhatsappWebAPI.disconnect();
    applyState(data);
    stopPolling();
    useAlert(L.logoutDone);
  } finally {
    loading.value = false;
  }
};

onMounted(async () => {
  try {
    const { data } = await WhatsappWebAPI.show();
    applyState(data);
    if (isPending.value) startPolling();
  } catch (e) {
    // no inbox yet — stays disconnected
  }
});

onBeforeUnmount(stopPolling);
</script>

<template>
  <div
    class="flex flex-col items-center w-full max-w-md gap-4 p-5 border rounded-2xl bg-n-solid-1 border-n-weak"
  >
    <div class="flex items-center gap-2 self-start">
      <span
        class="inline-block rounded-full size-2.5"
        :class="
          isOpen ? 'bg-n-teal-9' : isPending ? 'bg-n-amber-9' : 'bg-n-slate-8'
        "
      />
      <span class="text-sm font-medium text-n-slate-12">{{ statusLabel }}</span>
    </div>

    <!-- Connected -->
    <template v-if="isOpen">
      <div class="flex flex-col items-center gap-1.5 py-2">
        <Icon icon="i-lucide-badge-check" class="text-n-teal-10 size-10" />
        <p class="text-base font-medium text-n-slate-12">
          {{ `+${state.phoneNumber}` }}
        </p>
      </div>
      <Button
        :label="L.logout"
        color="ruby"
        variant="outline"
        size="sm"
        :is-loading="loading"
        @click="logout"
      />
    </template>

    <!-- QR pending scan -->
    <template v-else-if="status === 'qr' && state.qr">
      <img
        :src="state.qr"
        alt="WhatsApp QR"
        class="border rounded-lg size-56 border-n-weak"
      />
      <p class="text-xs text-center text-n-slate-11">{{ L.scanHint }}</p>
    </template>

    <!-- Connecting / reconnecting -->
    <template v-else-if="isPending">
      <div class="flex flex-col items-center gap-3 py-6">
        <span
          class="i-lucide-loader-circle size-7 animate-spin text-n-slate-10"
        />
        <p class="text-sm text-n-slate-11">
          {{ status === 'close' ? L.reconnecting : L.waiting }}
        </p>
      </div>
    </template>

    <!-- Disconnected -->
    <template v-else>
      <div class="flex flex-col items-center gap-3 py-3">
        <span class="i-lucide-message-circle size-10 text-n-slate-9" />
        <Button
          :label="L.connect"
          color="teal"
          size="sm"
          :is-loading="loading"
          @click="connect"
        />
      </div>
    </template>
  </div>
</template>
