<script setup>
import { ref, computed, onMounted, onBeforeUnmount, nextTick } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import ChatAPI from 'dashboard/api/chat/conversations';
import AgentAPI from 'dashboard/api/agents';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const currentUserId = useMapGetter('getCurrentUserID');

const L = {
  header: '团队沟通',
  newChat: '发起单聊',
  newGroup: '建群',
  empty: '还没有会话，点右上发起单聊或建群',
  selectHint: '选择左侧会话开始聊天',
  placeholder: '输入消息，回车发送',
  send: '发送',
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

const userDialog = ref(null);
const groupDialog = ref(null);
const groupForm = ref({ name: '', memberIds: [] });

let listTimer = null;
let msgTimer = null;

const initial = n => (n || '?').trim().charAt(0).toUpperCase();
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
const otherAgents = computed(() =>
  agents.value.filter(a => a.id !== currentUserId.value)
);

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

onMounted(async () => {
  fetchConversations();
  try {
    const { data } = await AgentAPI.get();
    agents.value = data || [];
  } catch {
    agents.value = [];
  }
  listTimer = setInterval(fetchConversations, 6000);
  msgTimer = setInterval(pollActive, 3000);
});
onBeforeUnmount(() => {
  clearInterval(listTimer);
  clearInterval(msgTimer);
});
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-background">
    <div
      class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak"
    >
      <h1 class="text-xl font-medium text-n-slate-12">{{ L.header }}</h1>
      <div class="flex gap-2">
        <Button
          :label="L.newChat"
          icon="i-lucide-message-square-plus"
          size="sm"
          variant="faded"
          color="slate"
          @click="openUserPicker"
        />
        <Button
          :label="L.newGroup"
          icon="i-lucide-users"
          size="sm"
          color="amber"
          @click="openGroupDialog"
        />
      </div>
    </div>

    <div class="flex flex-1 min-h-0">
      <!-- 左：会话列表 -->
      <aside
        class="flex flex-col flex-shrink-0 border-r w-72 border-n-weak bg-n-solid-1"
      >
        <div class="flex-1 overflow-y-auto">
          <div
            v-if="!conversations.length"
            class="p-6 text-sm text-center text-n-slate-10"
          >
            {{ L.empty }}
          </div>
          <button
            v-for="conv in conversations"
            :key="conv.id"
            class="flex items-center w-full gap-3 px-4 py-3 text-left transition-colors border-b border-n-weak"
            :class="
              activeConv && activeConv.id === conv.id
                ? 'bg-n-amber-2'
                : 'hover:bg-n-alpha-1'
            "
            @click="openConversation(conv)"
          >
            <div
              class="relative flex items-center justify-center flex-shrink-0 rounded-full size-10 bg-n-amber-4 text-n-amber-11"
            >
              <Icon
                v-if="conv.kind === 'group'"
                icon="i-lucide-users"
                class="size-5"
              />
              <template v-else>{{ initial(conv.name) }}</template>
            </div>
            <div class="flex-1 min-w-0">
              <div class="flex items-center justify-between gap-2">
                <span class="text-sm font-medium truncate text-n-slate-12">
                  {{ conv.name }}
                </span>
                <span class="flex-shrink-0 text-[11px] text-n-slate-10">
                  {{ fmtTime(conv.last_message_at) }}
                </span>
              </div>
              <div class="flex items-center justify-between gap-2 mt-0.5">
                <span class="text-xs truncate text-n-slate-10">
                  {{ conv.last_message?.content || '' }}
                </span>
                <span
                  v-if="conv.unread_count"
                  class="flex items-center justify-center flex-shrink-0 min-w-4 h-4 px-1 rounded-full text-[10px] text-white bg-n-ruby-9"
                >
                  {{ conv.unread_count }}
                </span>
              </div>
            </div>
          </button>
        </div>
      </aside>

      <!-- 右：消息 -->
      <section class="flex flex-col flex-1 min-w-0">
        <div
          v-if="!activeConv"
          class="flex flex-col items-center justify-center flex-1 gap-3 text-n-slate-10"
        >
          <Icon icon="i-lucide-messages-square" class="size-12 opacity-40" />
          <p class="text-sm">{{ L.selectHint }}</p>
        </div>

        <template v-else>
          <div
            class="flex items-center gap-2 px-6 py-3 border-b border-n-weak flex-shrink-0"
          >
            <h2 class="text-base font-medium text-n-slate-12">
              {{ activeConv.name }}
            </h2>
            <span
              v-if="activeConv.kind === 'group'"
              class="text-xs text-n-slate-10"
            >
              {{ L.members(activeConv.participant_count) }}
            </span>
          </div>

          <div ref="threadRef" class="flex-1 px-6 py-4 overflow-y-auto">
            <div
              v-for="msg in messages"
              :key="msg.id"
              class="flex gap-2 mb-4"
              :class="
                msg.sender_id === currentUserId
                  ? 'flex-row-reverse'
                  : 'flex-row'
              "
            >
              <div
                class="flex items-center justify-center flex-shrink-0 text-xs rounded-full size-8 bg-n-amber-4 text-n-amber-11"
              >
                {{ initial(msg.sender_name) }}
              </div>
              <div
                class="flex flex-col max-w-[70%]"
                :class="
                  msg.sender_id === currentUserId ? 'items-end' : 'items-start'
                "
              >
                <span
                  v-if="
                    activeConv.kind === 'group' &&
                    msg.sender_id !== currentUserId
                  "
                  class="mb-0.5 text-[11px] text-n-slate-10"
                >
                  {{ msg.sender_name }}
                </span>
                <div
                  class="px-3 py-2 text-sm break-words whitespace-pre-wrap rounded-2xl"
                  :class="
                    msg.sender_id === currentUserId
                      ? 'bg-n-amber-9 text-white rounded-tr-sm'
                      : 'bg-n-alpha-2 text-n-slate-12 rounded-tl-sm'
                  "
                >
                  {{ msg.content }}
                </div>
                <div class="flex items-center gap-1.5 mt-0.5">
                  <span class="text-[10px] text-n-slate-9">
                    {{ fmtTime(msg.created_at) }}
                  </span>
                  <template v-if="msg.sender_id === currentUserId">
                    <button
                      v-if="activeConv.kind === 'group' && groupReadLabel(msg)"
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

          <div
            class="flex items-end gap-2 p-3 border-t border-n-weak flex-shrink-0"
          >
            <textarea
              v-model="newText"
              rows="1"
              :placeholder="L.placeholder"
              class="flex-1 px-3 py-2 text-sm border rounded-lg resize-none reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-amber-9"
              @keydown.enter.exact.prevent="sendMessage"
            />
            <Button
              :label="L.send"
              icon="i-lucide-send"
              color="amber"
              :disabled="!newText.trim()"
              @click="sendMessage"
            />
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
          <div
            class="flex items-center justify-center text-sm rounded-full size-9 bg-n-amber-4 text-n-amber-11"
          >
            {{ initial(a.name) }}
          </div>
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
              <div
                class="flex items-center justify-center text-xs rounded-full size-7 bg-n-amber-4 text-n-amber-11"
              >
                {{ initial(a.name) }}
              </div>
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
              class="inline-flex items-center gap-1 px-2 py-1 text-xs rounded-full bg-n-alpha-1 text-n-slate-12"
            >
              <span
                class="flex items-center justify-center rounded-full size-5 bg-n-amber-4 text-n-amber-11 text-[10px]"
              >
                {{ initial(name) }}
              </span>
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
              class="inline-flex items-center gap-1 px-2 py-1 text-xs rounded-full bg-n-alpha-1 text-n-slate-11"
            >
              <span
                class="flex items-center justify-center rounded-full size-5 bg-n-slate-4 text-n-slate-11 text-[10px]"
              >
                {{ initial(name) }}
              </span>
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
