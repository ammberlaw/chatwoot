<script setup>
import { ref, computed, onMounted, onBeforeUnmount, nextTick } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import ChatAPI from 'dashboard/api/chat/conversations';
import AgentAPI from 'dashboard/api/agents';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const currentUserId = useMapGetter('getCurrentUserID');

const L = {
  messages: '消息',
  searchPlaceholder: '搜索会话',
  newChat: '发起单聊',
  newGroup: '建群',
  empty: '还没有会话',
  emptyHint: '点右上 + 发起单聊或建群',
  selectHint: '选择左侧会话开始聊天',
  selectTitle: '团队沟通',
  placeholder: '输入消息，回车发送',
  online: '在线',
  offline: '离线',
  noMatch: '没有匹配的会话',
  read: '已读',
  delivered: '已送达',
  allRead: '全部已读',
  readTitle: '消息已读情况',
  readList: '已读',
  unreadList: '未读',
  none: '暂无',
  pickUser: '选择联系人',
  groupName: '群名称',
  groupMembers: '选择群成员',
  create: '创建',
  members: n => `${n} 人`,
  error: '操作失败',
};

const conversations = ref([]);
const activeConv = ref(null);
const activeParticipants = ref([]);
const messages = ref([]);
const newText = ref('');
const agents = ref([]);
const threadRef = ref(null);
const search = ref('');

const userDialog = ref(null);
const groupDialog = ref(null);
const groupForm = ref({ name: '', memberIds: [] });

let listTimer = null;
let msgTimer = null;

const fmtTime = v => {
  if (!v) return '';
  const d = new Date(v);
  const diff = (Date.now() - d.getTime()) / 1000;
  if (diff < 86400)
    return d.toLocaleTimeString('zh-CN', {
      hour: '2-digit',
      minute: '2-digit',
    });
  return d.toLocaleDateString('zh-CN', { month: '2-digit', day: '2-digit' });
};

// id → agent，供头像与在线状态查询。
const agentMap = computed(() => {
  const m = {};
  agents.value.forEach(a => {
    m[a.id] = a;
  });
  return m;
});
const convSrc = conv =>
  conv.kind === 'group' ? '' : agentMap.value[conv.peer_id]?.thumbnail || '';
const convStatus = conv =>
  conv.kind === 'group'
    ? null
    : agentMap.value[conv.peer_id]?.availability_status || null;
const senderSrc = msg => agentMap.value[msg.sender_id]?.thumbnail || '';

const otherAgents = computed(() =>
  agents.value.filter(a => a.id !== currentUserId.value)
);
const filteredConversations = computed(() => {
  const q = search.value.trim().toLowerCase();
  if (!q) return conversations.value;
  return conversations.value.filter(
    c =>
      (c.name || '').toLowerCase().includes(q) ||
      (c.last_message?.content || '').toLowerCase().includes(q)
  );
});

// 单聊对方在线态（会话头部展示）。
const activePeerOnline = computed(
  () =>
    activeConv.value?.kind === 'direct' &&
    agentMap.value[activeConv.value.peer_id]?.availability_status === 'online'
);
// 列表尾随状态：我发的末条消息给出对勾。
const mineLastMessage = conv =>
  conv.last_message && conv.last_message.sender_id === currentUserId.value;

const lastMessageId = computed(() =>
  messages.value.length ? messages.value[messages.value.length - 1].id : 0
);

const scrollToBottom = () => {
  nextTick(() => {
    if (threadRef.value)
      threadRef.value.scrollTop = threadRef.value.scrollHeight;
  });
};

const fetchConversations = async () => {
  try {
    const { data } = await ChatAPI.list();
    conversations.value = data.payload || [];
  } catch {
    /* ignore */
  }
};

// 拉取当前会话的新消息 + 成员已读进度（已读回执据此计算）。
const pollActive = async () => {
  if (!activeConv.value) return;
  try {
    const [{ data: msgs }, { data: conv }] = await Promise.all([
      ChatAPI.messages(activeConv.value.id, lastMessageId.value),
      ChatAPI.show(activeConv.value.id),
    ]);
    if (msgs.payload?.length) {
      messages.value.push(...msgs.payload);
      scrollToBottom();
      ChatAPI.markRead(activeConv.value.id);
    }
    activeParticipants.value = conv.participants || [];
  } catch {
    /* ignore */
  }
};

const openConversation = async conv => {
  activeConv.value = conv;
  messages.value = [];
  activeParticipants.value = [];
  try {
    const [{ data: msgs }, { data: full }] = await Promise.all([
      ChatAPI.messages(conv.id, 0),
      ChatAPI.show(conv.id),
    ]);
    messages.value = msgs.payload || [];
    activeParticipants.value = full.participants || [];
    scrollToBottom();
    conv.unread_count = 0;
  } catch {
    /* ignore */
  }
};

const sendMessage = async () => {
  const content = newText.value.trim();
  if (!content || !activeConv.value) return;
  newText.value = '';
  try {
    const { data } = await ChatAPI.send(activeConv.value.id, content);
    messages.value.push(data);
    scrollToBottom();
    fetchConversations();
  } catch {
    useAlert(L.error);
  }
};

// 某条消息的已读/未读成员（除发送者外）。
const readSplit = msg => {
  const others = activeParticipants.value.filter(
    p => p.user_id !== currentUserId.value
  );
  return {
    read: others.filter(p => (p.last_read_message_id || 0) >= msg.id),
    unread: others.filter(p => (p.last_read_message_id || 0) < msg.id),
  };
};

// 单聊：已读/已送达。
const directReadLabel = msg => {
  if (msg.sender_id !== currentUserId.value) return '';
  const { read } = readSplit(msg);
  return read.length ? L.read : L.delivered;
};

// 群聊：已读 X（可点开看名单）。
const groupReadLabel = msg => {
  const { read, unread } = readSplit(msg);
  const total = read.length + unread.length;
  if (!total) return '';
  return read.length === total ? L.allRead : `${L.read} ${read.length}`;
};

const readDialogRef = ref(null);
const readDetail = ref({ read: [], unread: [] });
const openReadDetail = msg => {
  const { read, unread } = readSplit(msg);
  readDetail.value = {
    read: read.map(p => p.name),
    unread: unread.map(p => p.name),
  };
  readDialogRef.value?.open();
};

// ---- 发起会话 ----
const openUserPicker = () => userDialog.value?.open();
const startDirect = async userId => {
  userDialog.value?.close();
  try {
    const { data } = await ChatAPI.create({ kind: 'direct', user_id: userId });
    await fetchConversations();
    const conv = conversations.value.find(c => c.id === data.id) || data;
    openConversation(conv);
  } catch {
    useAlert(L.error);
  }
};

const openGroupDialog = () => {
  groupForm.value = { name: '', memberIds: [] };
  groupDialog.value?.open();
};
const createGroup = async () => {
  if (!groupForm.value.name.trim() || !groupForm.value.memberIds.length) return;
  try {
    const { data } = await ChatAPI.create({
      kind: 'group',
      name: groupForm.value.name.trim(),
      user_ids: groupForm.value.memberIds,
    });
    groupDialog.value?.close();
    await fetchConversations();
    openConversation(conversations.value.find(c => c.id === data.id) || data);
  } catch {
    useAlert(L.error);
  }
};

const loadAgents = async () => {
  try {
    const { data } = await AgentAPI.get();
    agents.value = data || [];
  } catch {
    agents.value = [];
  }
};

onMounted(async () => {
  fetchConversations();
  loadAgents();
  listTimer = setInterval(() => {
    fetchConversations();
    loadAgents(); // 顺带刷新在线状态
  }, 6000);
  msgTimer = setInterval(pollActive, 3000);
});
onBeforeUnmount(() => {
  clearInterval(listTimer);
  clearInterval(msgTimer);
});
</script>

<template>
  <div
    class="w-full h-full p-4 overflow-hidden sm:p-6 bg-gradient-to-br from-n-amber-3 via-n-teal-3 to-n-teal-5"
  >
    <div
      class="flex w-full h-full overflow-hidden border shadow-sm bg-n-solid-1 border-n-weak rounded-[28px]"
    >
      <!-- 左：会话列表 -->
      <aside
        class="flex flex-col shrink-0 w-[300px] border-r border-n-weak"
      >
        <!-- 搜索 -->
        <div class="p-4 pb-3">
          <div class="relative">
            <Icon
              icon="i-lucide-search"
              class="absolute -translate-y-1/2 pointer-events-none size-4 left-3.5 top-1/2 text-n-slate-10"
            />
            <input
              v-model="search"
              type="text"
              :placeholder="L.searchPlaceholder"
              class="w-full py-2.5 pl-10 pr-3 text-sm border rounded-full reset-base border-transparent bg-n-alpha-1 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-amber-7 focus-visible:bg-n-solid-1"
            />
          </div>
        </div>

        <!-- 标题 + 新建 -->
        <div class="flex items-center justify-between px-5 pb-2">
          <h1 class="text-xl font-semibold tracking-tight text-n-slate-12">
            {{ L.messages }}
          </h1>
          <div class="flex gap-0.5">
            <button
              type="button"
              :title="L.newChat"
              class="grid transition-colors rounded-full size-8 place-items-center text-n-slate-11 hover:bg-n-alpha-2"
              @click="openUserPicker"
            >
              <Icon icon="i-lucide-message-square-plus" class="size-[18px]" />
            </button>
            <button
              type="button"
              :title="L.newGroup"
              class="grid transition-colors rounded-full size-8 place-items-center text-n-slate-11 hover:bg-n-alpha-2"
              @click="openGroupDialog"
            >
              <Icon icon="i-lucide-users-round" class="size-[18px]" />
            </button>
          </div>
        </div>

        <!-- 列表 -->
        <div class="flex-1 px-2 pb-2 overflow-y-auto">
          <div
            v-if="!conversations.length"
            class="flex flex-col items-center gap-1 px-6 mt-16 text-center"
          >
            <Icon
              icon="i-lucide-messages-square"
              class="mb-2 opacity-30 size-8 text-n-slate-10"
            />
            <p class="text-sm font-medium text-n-slate-11">{{ L.empty }}</p>
            <p class="text-xs text-n-slate-10">{{ L.emptyHint }}</p>
          </div>
          <p
            v-else-if="!filteredConversations.length"
            class="px-6 mt-10 text-sm text-center text-n-slate-10"
          >
            {{ L.noMatch }}
          </p>

          <button
            v-for="conv in filteredConversations"
            :key="conv.id"
            type="button"
            class="flex items-center w-full gap-3 px-3 py-2.5 mb-0.5 text-left transition-colors rounded-2xl outline-none focus-visible:ring-2 focus-visible:ring-n-amber-7"
            :class="
              activeConv && activeConv.id === conv.id
                ? 'bg-n-amber-3'
                : 'hover:bg-n-alpha-1'
            "
            @click="openConversation(conv)"
          >
            <Avatar
              :name="conv.name"
              :src="convSrc(conv)"
              :status="convStatus(conv)"
              :size="44"
              rounded-full
              hide-offline-status
            />
            <div class="flex-1 min-w-0">
              <div class="flex items-center justify-between gap-2">
                <span class="text-sm font-semibold truncate text-n-slate-12">
                  {{ conv.name }}
                </span>
                <span class="shrink-0 text-[11px] tabular-nums text-n-slate-10">
                  {{ fmtTime(conv.last_message_at) }}
                </span>
              </div>
              <div class="flex items-center justify-between gap-2 mt-0.5">
                <span
                  class="text-xs truncate"
                  :class="
                    conv.unread_count ? 'text-n-slate-12 font-medium' : 'text-n-slate-10'
                  "
                >
                  {{ conv.last_message?.content || '—' }}
                </span>
                <span
                  v-if="conv.unread_count"
                  class="grid shrink-0 min-w-[18px] h-[18px] px-1 rounded-full text-[10px] font-semibold text-white place-items-center bg-n-amber-9"
                >
                  {{ conv.unread_count }}
                </span>
                <Icon
                  v-else-if="mineLastMessage(conv)"
                  icon="i-lucide-check-check"
                  class="shrink-0 size-4 text-n-teal-10"
                />
              </div>
            </div>
          </button>
        </div>
      </aside>

      <!-- 右：消息（薄荷底色，头部/输入框保持白色浮于其上） -->
      <section
        class="flex flex-col flex-1 min-w-0 bg-gradient-to-b from-n-teal-1 to-n-teal-3"
      >
        <!-- 空状态 -->
        <div
          v-if="!activeConv"
          class="flex flex-col items-center justify-center flex-1 gap-3 text-n-slate-10"
        >
          <div
            class="grid rounded-full size-16 place-items-center bg-n-amber-3 text-n-amber-11"
          >
            <Icon icon="i-lucide-messages-square" class="size-7" />
          </div>
          <p class="text-sm font-medium text-n-slate-11">{{ L.selectTitle }}</p>
          <p class="text-xs text-n-slate-10">{{ L.selectHint }}</p>
        </div>

        <template v-else>
          <!-- 会话头部 -->
          <header
            class="flex items-center gap-3 px-6 py-4 shrink-0 border-b border-n-weak bg-n-solid-1"
          >
            <Avatar
              :name="activeConv.name"
              :src="convSrc(activeConv)"
              :status="convStatus(activeConv)"
              :size="40"
              rounded-full
              hide-offline-status
            />
            <div class="min-w-0">
              <h2 class="text-[15px] font-semibold truncate text-n-slate-12">
                {{ activeConv.name }}
              </h2>
              <div class="flex items-center gap-1.5 mt-0.5">
                <template v-if="activeConv.kind === 'group'">
                  <span class="text-xs text-n-slate-10">
                    {{ L.members(activeConv.participant_count) }}
                  </span>
                </template>
                <template v-else>
                  <span
                    class="rounded-full size-1.5"
                    :class="activePeerOnline ? 'bg-n-teal-9' : 'bg-n-slate-8'"
                  />
                  <span class="text-xs text-n-slate-10">
                    {{ activePeerOnline ? L.online : L.offline }}
                  </span>
                </template>
              </div>
            </div>
          </header>

          <!-- 消息流 -->
          <div ref="threadRef" class="flex-1 px-6 py-5 overflow-y-auto">
            <div
              v-for="msg in messages"
              :key="msg.id"
              class="flex gap-2.5 mb-4"
              :class="
                msg.sender_id === currentUserId
                  ? 'flex-row-reverse'
                  : 'flex-row'
              "
            >
              <Avatar
                v-if="msg.sender_id !== currentUserId"
                :name="msg.sender_name"
                :src="senderSrc(msg)"
                :size="32"
                rounded-full
                class="mt-0.5"
              />
              <div
                class="flex flex-col max-w-[72%]"
                :class="
                  msg.sender_id === currentUserId ? 'items-end' : 'items-start'
                "
              >
                <span
                  v-if="
                    activeConv.kind === 'group' &&
                    msg.sender_id !== currentUserId
                  "
                  class="mb-1 ml-1 text-[11px] font-medium text-n-slate-10"
                >
                  {{ msg.sender_name }}
                </span>
                <div
                  class="px-4 py-2.5 text-sm leading-relaxed break-words whitespace-pre-wrap shadow-sm rounded-[20px]"
                  :class="
                    msg.sender_id === currentUserId
                      ? 'bg-n-solid-1 text-n-slate-12 ring-1 ring-inset ring-n-weak rounded-br-md'
                      : 'bg-n-slate-12 text-n-slate-1 rounded-bl-md'
                  "
                >
                  {{ msg.content }}
                </div>
                <div class="flex items-center gap-1.5 mt-1 px-1">
                  <span class="text-[10px] tabular-nums text-n-slate-9">
                    {{ fmtTime(msg.created_at) }}
                  </span>
                  <template v-if="msg.sender_id === currentUserId">
                    <button
                      v-if="activeConv.kind === 'group' && groupReadLabel(msg)"
                      type="button"
                      class="text-[10px] text-n-teal-11 hover:underline"
                      @click="openReadDetail(msg)"
                    >
                      {{ groupReadLabel(msg) }}
                    </button>
                    <span
                      v-else-if="
                        activeConv.kind === 'direct' && directReadLabel(msg)
                      "
                      class="text-[10px]"
                      :class="
                        directReadLabel(msg) === L.delivered
                          ? 'text-n-slate-9'
                          : 'text-n-teal-11'
                      "
                    >
                      {{ directReadLabel(msg) }}
                    </span>
                  </template>
                </div>
              </div>
            </div>
          </div>

          <!-- 输入区 -->
          <div
            class="flex items-end gap-2.5 px-4 py-3.5 shrink-0 border-t border-n-weak bg-n-solid-1"
          >
            <div
              class="flex items-center flex-1 px-4 py-2.5 transition-shadow rounded-full bg-n-alpha-1 ring-1 ring-inset ring-n-weak focus-within:ring-2 focus-within:ring-n-amber-7"
            >
              <textarea
                v-model="newText"
                rows="1"
                :placeholder="L.placeholder"
                class="flex-1 h-6 text-sm leading-6 bg-transparent resize-none reset-base text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none"
                @keydown.enter.exact.prevent="sendMessage"
              />
            </div>
            <button
              type="button"
              :disabled="!newText.trim()"
              class="grid transition-colors rounded-full shrink-0 size-11 place-items-center bg-n-amber-9 text-white hover:bg-n-amber-10 disabled:opacity-40 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-amber-7 focus-visible:ring-offset-2 focus-visible:ring-offset-n-solid-1"
              @click="sendMessage"
            >
              <Icon icon="i-lucide-send-horizontal" class="size-[18px]" />
            </button>
          </div>
        </template>
      </section>
    </div>

    <!-- 发起单聊 -->
    <Dialog ref="userDialog" :title="L.pickUser" :show-confirm-button="false">
      <div class="flex flex-col gap-1 max-h-[50vh] overflow-y-auto">
        <button
          v-for="a in otherAgents"
          :key="a.id"
          class="flex items-center gap-3 p-2 text-left rounded-lg hover:bg-n-alpha-1"
          @click="startDirect(a.id)"
        >
          <Avatar
            :name="a.name"
            :src="a.thumbnail || ''"
            :status="a.availability_status || null"
            :size="36"
            rounded-full
            hide-offline-status
          />
          <div class="min-w-0">
            <div class="text-sm truncate text-n-slate-12">{{ a.name }}</div>
            <div class="text-xs truncate text-n-slate-10">{{ a.email }}</div>
          </div>
        </button>
      </div>
    </Dialog>

    <!-- 建群 -->
    <Dialog
      ref="groupDialog"
      :title="L.newGroup"
      :confirm-button-label="L.create"
      confirm-button-color="amber"
      @confirm="createGroup"
    >
      <div class="flex flex-col gap-4">
        <Input v-model="groupForm.name" :label="L.groupName" autofocus />
        <div>
          <label class="block mb-1 text-heading-3 text-n-slate-12">
            {{ L.groupMembers }}
          </label>
          <div class="flex flex-col gap-1 max-h-[40vh] overflow-y-auto">
            <label
              v-for="a in otherAgents"
              :key="a.id"
              class="flex items-center gap-2 p-2 text-sm rounded-lg cursor-pointer hover:bg-n-alpha-1"
            >
              <input
                v-model="groupForm.memberIds"
                type="checkbox"
                :value="a.id"
                class="accent-n-amber-9"
              />
              <Avatar
                :name="a.name"
                :src="a.thumbnail || ''"
                :size="28"
                rounded-full
              />
              {{ a.name }}
            </label>
          </div>
        </div>
      </div>
    </Dialog>

    <!-- 群消息已读名单 -->
    <Dialog
      ref="readDialogRef"
      :title="L.readTitle"
      :show-confirm-button="false"
    >
      <div class="flex flex-col gap-4">
        <div>
          <p class="mb-2 text-xs font-medium text-n-teal-11">
            {{ `${L.readList} ${readDetail.read.length}` }}
          </p>
          <div class="flex flex-wrap gap-1.5">
            <span
              v-for="name in readDetail.read"
              :key="`r-${name}`"
              class="inline-flex items-center gap-1.5 py-1 pl-1 pr-2.5 text-xs rounded-full bg-n-alpha-1 text-n-slate-12"
            >
              <Avatar :name="name" :size="20" rounded-full />
              {{ name }}
            </span>
            <span
              v-if="!readDetail.read.length"
              class="text-xs text-n-slate-10"
            >
              {{ L.none }}
            </span>
          </div>
        </div>
        <div>
          <p class="mb-2 text-xs font-medium text-n-slate-10">
            {{ `${L.unreadList} ${readDetail.unread.length}` }}
          </p>
          <div class="flex flex-wrap gap-1.5">
            <span
              v-for="name in readDetail.unread"
              :key="`u-${name}`"
              class="inline-flex items-center gap-1.5 py-1 pl-1 pr-2.5 text-xs rounded-full bg-n-alpha-1 text-n-slate-11"
            >
              <Avatar :name="name" :size="20" rounded-full />
              {{ name }}
            </span>
            <span
              v-if="!readDetail.unread.length"
              class="text-xs text-n-slate-10"
            >
              {{ L.none }}
            </span>
          </div>
        </div>
      </div>
    </Dialog>
  </div>
</template>
