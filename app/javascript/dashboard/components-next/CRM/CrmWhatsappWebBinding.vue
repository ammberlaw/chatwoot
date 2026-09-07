<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useAlert } from 'dashboard/composables';
import WhatsappWebAPI from 'dashboard/api/crm/whatsappWeb';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const L = {
  add: '添加号码',
  reconnect: '重新连接',
  logout: '解绑',
  scanHint: '用手机 WhatsApp → 设置 → 已关联的设备 → 关联新设备,扫描二维码',
  waiting: '正在生成二维码…',
  connecting: '连接中…',
  connected: '已连接',
  disconnected: '未连接',
  reconnecting: '连接断开,正在自动重连…',
  empty:
    '还没有绑定 WhatsApp 号,点「添加号码」扫码绑定。可绑定多个号,各自独立收发。',
  logoutConfirm:
    '确定解绑该 WhatsApp 号?历史会话与客户记录会保留,但将停止收发消息。',
  addError: '添加失败,请稍后重试',
  connectError: '连接失败,请稍后重试',
  logoutDone: '已解绑',
};

// 每个号一张卡:{ inbox_id, name, phone_number, status, qr, busy }
const numbers = ref([]);
const adding = ref(false);
let pollTimer = null;

const isPending = s => ['connecting', 'qr', 'close'].includes(s);
const hasPending = computed(() => numbers.value.some(n => isPending(n.status)));

const statusLabel = s => {
  switch (s) {
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
};

const applyState = (card, data) => {
  card.status = data.status || 'disconnected';
  card.qr = data.qr || null;
  if (data.phone_number) card.phone_number = data.phone_number;
  if (data.name) card.name = data.name;
};

const stopPolling = () => {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
};

const startPolling = () => {
  if (pollTimer) return;
  pollTimer = setInterval(async () => {
    const pending = numbers.value.filter(n => isPending(n.status));
    if (!pending.length) {
      stopPolling();
      return;
    }
    await Promise.all(
      pending.map(async card => {
        try {
          const { data } = await WhatsappWebAPI.status(card.inbox_id);
          applyState(card, data);
        } catch (e) {
          // keep card as-is; will retry next tick
        }
      })
    );
    if (!hasPending.value) stopPolling();
  }, 2500);
};

const addNumber = async () => {
  adding.value = true;
  try {
    const { data } = await WhatsappWebAPI.create();
    numbers.value.push({ ...data, qr: data.qr || null });
    startPolling();
  } catch (e) {
    useAlert(L.addError);
  } finally {
    adding.value = false;
  }
};

const reconnect = async card => {
  card.busy = true;
  try {
    const { data } = await WhatsappWebAPI.connect(card.inbox_id);
    applyState(card, data);
    startPolling();
  } catch (e) {
    useAlert(L.connectError);
  } finally {
    card.busy = false;
  }
};

const logout = async card => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(L.logoutConfirm)) return;
  card.busy = true;
  try {
    const { data } = await WhatsappWebAPI.disconnect(card.inbox_id);
    applyState(card, data);
    useAlert(L.logoutDone);
  } finally {
    card.busy = false;
  }
};

onMounted(async () => {
  try {
    const { data } = await WhatsappWebAPI.list();
    numbers.value = (data || []).map(n => ({ ...n, qr: null, busy: false }));
    if (hasPending.value) startPolling();
  } catch (e) {
    // no inboxes yet — stays empty
  }
});

onBeforeUnmount(stopPolling);
</script>

<template>
  <div class="flex flex-col w-full gap-3">
    <div class="flex justify-start">
      <Button
        :label="L.add"
        icon="i-lucide-plus"
        color="teal"
        size="sm"
        :is-loading="adding"
        @click="addNumber"
      />
    </div>

    <p v-if="!numbers.length" class="text-sm text-n-slate-11">{{ L.empty }}</p>

    <div v-else class="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3">
      <div
        v-for="card in numbers"
        :key="card.inbox_id"
        class="flex flex-col items-center gap-3 p-4 border rounded-2xl bg-n-solid-1 border-n-weak"
      >
        <div class="flex items-center self-start gap-2">
          <span
            class="inline-block rounded-full size-2.5"
            :class="
              card.status === 'open'
                ? 'bg-n-teal-9'
                : isPending(card.status)
                  ? 'bg-n-amber-9'
                  : 'bg-n-slate-8'
            "
          />
          <span class="text-sm font-medium text-n-slate-12">
            {{ statusLabel(card.status) }}
          </span>
        </div>

        <!-- Connected -->
        <template v-if="card.status === 'open'">
          <div class="flex flex-col items-center gap-1.5 py-2">
            <Icon icon="i-lucide-badge-check" class="text-n-teal-10 size-9" />
            <p class="text-sm font-medium text-n-slate-12">
              {{ card.phone_number ? `+${card.phone_number}` : card.name }}
            </p>
          </div>
          <Button
            :label="L.logout"
            color="ruby"
            variant="outline"
            size="sm"
            :is-loading="card.busy"
            @click="logout(card)"
          />
        </template>

        <!-- QR pending scan -->
        <template v-else-if="card.status === 'qr' && card.qr">
          <img
            :src="card.qr"
            alt="WhatsApp QR"
            class="border rounded-lg size-52 border-n-weak"
          />
          <p class="text-xs text-center text-n-slate-11">{{ L.scanHint }}</p>
        </template>

        <!-- Connecting / reconnecting -->
        <template v-else-if="isPending(card.status)">
          <div class="flex flex-col items-center gap-2 py-6">
            <span
              class="i-lucide-loader-circle size-7 animate-spin text-n-slate-10"
            />
            <p class="text-sm text-n-slate-11">
              {{ card.status === 'close' ? L.reconnecting : L.waiting }}
            </p>
          </div>
        </template>

        <!-- Disconnected -->
        <template v-else>
          <div class="flex flex-col items-center gap-3 py-3">
            <span class="i-lucide-message-circle size-9 text-n-slate-9" />
            <Button
              :label="L.reconnect"
              color="teal"
              variant="outline"
              size="sm"
              :is-loading="card.busy"
              @click="reconnect(card)"
            />
          </div>
        </template>
      </div>
    </div>
  </div>
</template>
