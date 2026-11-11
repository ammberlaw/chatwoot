<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useAlert } from 'dashboard/composables';
import WhatsappWebAPI from 'dashboard/api/crm/whatsappWeb';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { isClassicTheme } from 'dashboard/components-next/CRM/charts/chartColors';
import { useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';

const router = useRouter();
const store = useStore();
// 经典灰下主行动用 amber(金黄)，与其它 CRM 页面一致。
const isClassic = ref(isClassicTheme());
const goColor = computed(() => (isClassic.value ? 'amber' : 'teal'));

const L = {
  add: '添加号码',
  reconnect: '重新连接',
  logout: '解绑',
  remove: '移除这个号',
  removeConfirm: '这个号还没扫码连上，移除它？以后要用再点「添加号码」重新扫。',
  removeDone: '已移除',
  removeError: '移除失败，请稍后重试',
  scanHint: '用手机 WhatsApp → 设置 → 已关联的设备 → 关联新设备,扫描二维码',
  waiting: '正在生成二维码…',
  connecting: '连接中…',
  awaitingScan: '等待扫码',
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
  startChat: '发起会话',
  startChatTitle: '输入手机号开聊',
  startChatHint:
    '和手机 WhatsApp 一样,对方不需要先加你好友。号码要带国家码,例如 8613800138000。',
  startChatPhone: '手机号(含国家码)',
  startChatName: '备注名(可留空)',
  startChatGo: '开始聊天',
  startChatFail: '发起失败,请稍后重试',
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
      return L.connecting;
    // 等待扫码和「正在连接」要分开：都写「连接中」的话，二维码明明在那儿摆着，
    // 看的人会以为卡住了在等系统（实际发生过，排查绕了一大圈）。
    case 'qr':
      return L.awaitingScan;
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

// 还没扫码连上的卡片也得有个退出口。
// 之前只有「已连接」的卡片有「解绑」，卡在「等待扫码」的那张既扫不了也关不掉，
// 侧栏就一直显示 WhatsApp (2)，其中一个点进去什么都没有（用户 2026-11-10）。
// 移除使用独立接口；解绑接口刻意保留收件箱和会话，不能用来移除空号。
const removeCard = async card => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(L.removeConfirm)) return;
  card.busy = true;
  try {
    await WhatsappWebAPI.remove(card.inbox_id);
    numbers.value = numbers.value.filter(n => n.inbox_id !== card.inbox_id);
    await store.dispatch('inboxes/get');
    useAlert(L.removeDone);
  } catch (error) {
    useAlert(error?.response?.data?.error || L.removeError);
  } finally {
    card.busy = false;
  }
};

// ---- 输入手机号直接开聊 ----
// 手机 WhatsApp 不需要「加好友」,知道号码就能聊。系统里以前只能等对方先发消息过来,
// 业务主动联系新客户只能先去手机上发一条,聊天记录就断在系统外面了。
const chatDialog = ref(null);
const chatCard = ref(null);
const chatPhone = ref('');
const chatName = ref('');
const chatBusy = ref(false);

const openStartChat = card => {
  chatCard.value = card;
  chatPhone.value = '';
  chatName.value = '';
  chatDialog.value?.open();
};

const submitStartChat = async () => {
  const phone = chatPhone.value.replace(/\D/g, '');
  if (!phone) {
    useAlert(L.startChatPhone);
    return;
  }
  chatBusy.value = true;
  try {
    const { data } = await WhatsappWebAPI.startChat(
      chatCard.value.inbox_id,
      phone,
      chatName.value.trim()
    );
    chatDialog.value?.close();
    router.push({
      name: 'inbox_conversation',
      params: { conversation_id: data.conversation_id },
    });
  } catch (error) {
    useAlert(error?.response?.data?.error || L.startChatFail);
  } finally {
    chatBusy.value = false;
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
        :color="goColor"
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
        <div class="flex w-full items-center gap-2">
          <span
            class="inline-block rounded-full size-2.5 shrink-0"
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
          <!-- 没连上的卡片给个关闭口。已连接的不给——那个要走下面的「解绑」，
               带确认文案，免得手滑点掉一个正在收发消息的号。 -->
          <button
            v-if="card.status !== 'open' && !card.phone_number"
            type="button"
            class="reset-base ml-auto inline-flex size-7 shrink-0 items-center justify-center rounded-full border border-n-weak text-n-slate-11 hover:border-n-ruby-8 hover:bg-n-ruby-3 hover:text-n-ruby-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-slate-8"
            :title="L.remove"
            :aria-label="L.remove"
            :disabled="card.busy"
            @click="removeCard(card)"
          >
            <Icon icon="i-lucide-x" class="size-4" />
          </button>
        </div>

        <!-- Connected -->
        <template v-if="card.status === 'open'">
          <div class="flex flex-col items-center gap-1.5 py-2">
            <Icon icon="i-lucide-badge-check" class="text-n-teal-10 size-9" />
            <p class="text-sm font-medium text-n-slate-12">
              {{ card.phone_number ? `+${card.phone_number}` : card.name }}
            </p>
          </div>
          <div class="flex w-full gap-2">
            <Button
              :label="L.startChat"
              icon="i-lucide-message-square-plus"
              :color="goColor"
              size="sm"
              class="flex-1"
              @click="openStartChat(card)"
            />
            <Button
              :label="L.logout"
              color="ruby"
              variant="outline"
              size="sm"
              :is-loading="card.busy"
              @click="logout(card)"
            />
          </div>
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

    <Dialog
      ref="chatDialog"
      :title="L.startChatTitle"
      :description="L.startChatHint"
      :confirm-button-label="L.startChatGo"
      :confirm-button-color="goColor"
      :is-loading="chatBusy"
      @confirm="submitStartChat"
    >
      <div class="flex flex-col gap-3">
        <label class="flex flex-col gap-1">
          <span class="text-sm text-n-slate-11">{{ L.startChatPhone }}</span>
          <input
            v-model="chatPhone"
            type="tel"
            inputmode="numeric"
            placeholder="8613800138000"
            class="w-full h-10 px-3 text-sm border rounded-lg reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-9"
            @keyup.enter="submitStartChat"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-sm text-n-slate-11">{{ L.startChatName }}</span>
          <input
            v-model="chatName"
            type="text"
            class="w-full h-10 px-3 text-sm border rounded-lg reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-9"
            @keyup.enter="submitStartChat"
          />
        </label>
      </div>
    </Dialog>
  </div>
</template>
