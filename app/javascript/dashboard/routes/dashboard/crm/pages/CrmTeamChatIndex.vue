<script setup>
import { ref, computed, onMounted, onBeforeUnmount, nextTick } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import ChatAPI from 'dashboard/api/chat/conversations';
import AgentAPI from 'dashboard/api/agents';
import DepartmentsAPI from 'dashboard/api/org/departments';
import MembershipsAPI from 'dashboard/api/org/memberships';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

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
  attach: '添加附件',
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
  pickerSearchPlaceholder: '搜索姓名 / 职位',
  noDeptGroup: '未分部门',
  pickerEmpty: '未找到匹配成员',
  groupName: '群名称',
  groupMembers: '选择群成员',
  create: '创建',
  members: n => `${n} 人`,
  error: '操作失败',
  announcement: '群公告',
  announcementPlaceholder: '填写群公告（必填）',
  noAnnouncement: '暂无群公告',
  ownerOnlyHint: '仅群主可编辑群公告',
  save: '发布公告',
  saved: '群公告已发布',
  detailTitle: '群聊详情',
  memberList: '群成员',
  ownerBadge: '群主',
  transfer: '转让群主',
  confirmTransfer: '确认转让',
  transferred: '群主已转让',
  leaveGroup: '退出群聊',
  confirmLeave: '确认退出',
  left: '已退出群聊',
  ownerLeaveHint: '群主需先转让群主才能退群',
  remove: '移除',
  confirmRemove: '确认移除',
  removed: '已移除该成员',
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
const groupForm = ref({ name: '', announcement: '', memberIds: [] });
const detailDialog = ref(null);
const announcementDraft = ref('');
const pendingRemoveId = ref(null);

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

// ── 选人弹窗：按组织架构分组 + 搜索（姓名/邮箱/职位）──
const departments = ref([]);
const memberships = ref([]);
const pickerQuery = ref('');
const loadOrgData = async () => {
  try {
    const [{ data: depts }, { data: mems }] = await Promise.all([
      DepartmentsAPI.get(),
      MembershipsAPI.get(),
    ]);
    departments.value = depts.payload || [];
    memberships.value = mems.payload || [];
  } catch {
    departments.value = [];
    memberships.value = [];
  }
};

const pickerGroups = computed(() => {
  const q = pickerQuery.value.trim().toLowerCase();
  const byUser = {};
  memberships.value.forEach(m => {
    (byUser[m.user_id] = byUser[m.user_id] || []).push(m);
  });
  const hit = (agent, title) =>
    !q ||
    (agent.name || '').toLowerCase().includes(q) ||
    (agent.email || '').toLowerCase().includes(q) ||
    (title || '').toLowerCase().includes(q);
  const groups = departments.value.map(dept => ({
    key: dept.id,
    name: dept.name,
    members: otherAgents.value
      .map(agent => ({
        agent,
        title: (byUser[agent.id] || []).find(m => m.department_id === dept.id)
          ?.title,
      }))
      .filter(
        entry =>
          (byUser[entry.agent.id] || []).some(
            m => m.department_id === dept.id
          ) && hit(entry.agent, entry.title)
      ),
  }));
  const unassigned = otherAgents.value
    .filter(agent => !(byUser[agent.id] || []).length)
    .map(agent => ({ agent, title: '' }))
    .filter(entry => hit(entry.agent, ''));
  if (unassigned.length) {
    groups.push({ key: 'none', name: L.noDeptGroup, members: unassigned });
  }
  return groups.filter(group => group.members.length);
});
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
    if (activeConv.value && activeConv.value.id === conv.id) {
      activeConv.value.announcement = conv.announcement;
      activeConv.value.creator_id = conv.creator_id;
      activeConv.value.participant_count = conv.participant_count;
    }
  } catch (e) {
    // 被移出群聊：会话对自己不可见（404），退出该会话并刷新列表。
    if (e?.response?.status === 404) {
      activeConv.value = null;
      messages.value = [];
      fetchConversations();
    }
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

// 待发附件
const pendingFiles = ref([]);
const chatFileInput = ref(null);
const onFilesPicked = e => {
  pendingFiles.value.push(...Array.from(e.target.files || []));
  e.target.value = '';
};
const removePending = i => pendingFiles.value.splice(i, 1);
const fmtSize = b =>
  b < 1024
    ? `${b}B`
    : b < 1048576
      ? `${Math.round(b / 1024)}KB`
      : `${(b / 1048576).toFixed(1)}MB`;

const sendMessage = async () => {
  const content = newText.value.trim();
  const files = pendingFiles.value;
  if ((!content && !files.length) || !activeConv.value) return;
  newText.value = '';
  pendingFiles.value = [];
  try {
    const { data } = await ChatAPI.send(activeConv.value.id, content, files);
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
  groupForm.value = { name: '', announcement: '', memberIds: [] };
  groupDialog.value?.open();
};
const createGroup = async () => {
  if (
    !groupForm.value.name.trim() ||
    !groupForm.value.announcement.trim() ||
    !groupForm.value.memberIds.length
  )
    return;
  try {
    const { data } = await ChatAPI.create({
      kind: 'group',
      name: groupForm.value.name.trim(),
      announcement: groupForm.value.announcement.trim(),
      user_ids: groupForm.value.memberIds,
    });
    groupDialog.value?.close();
    await fetchConversations();
    openConversation(conversations.value.find(c => c.id === data.id) || data);
  } catch {
    useAlert(L.error);
  }
};

// ---- 群聊详情：公告 + 成员管理（群主可编辑公告/踢人，像微信）----
const isGroupOwner = computed(
  () =>
    activeConv.value?.kind === 'group' &&
    activeConv.value?.creator_id === currentUserId.value
);
const pendingTransferId = ref(null);
const pendingLeave = ref(false);
const openGroupDetail = () => {
  announcementDraft.value = activeConv.value?.announcement || '';
  pendingRemoveId.value = null;
  pendingTransferId.value = null;
  pendingLeave.value = false;
  detailDialog.value?.open();
};
const saveAnnouncement = async () => {
  const text = announcementDraft.value.trim();
  if (!text || text === activeConv.value?.announcement) return;
  try {
    const { data } = await ChatAPI.update(activeConv.value.id, {
      announcement: text,
    });
    activeConv.value.announcement = data.announcement;
    useAlert(L.saved);
    pollActive();
    fetchConversations();
  } catch {
    useAlert(L.error);
  }
};
// 踢人两步确认：第一次点变「确认移除」，再点执行。
const removeMember = async userId => {
  if (pendingRemoveId.value !== userId) {
    pendingRemoveId.value = userId;
    return;
  }
  pendingRemoveId.value = null;
  try {
    const { data } = await ChatAPI.removeParticipant(
      activeConv.value.id,
      userId
    );
    activeParticipants.value = data.participants || [];
    activeConv.value.participant_count = data.participant_count;
    useAlert(L.removed);
    fetchConversations();
  } catch {
    useAlert(L.error);
  }
};

// 转让群主两步确认：转让后自己变普通成员。
const transferOwner = async userId => {
  if (pendingTransferId.value !== userId) {
    pendingTransferId.value = userId;
    pendingRemoveId.value = null;
    return;
  }
  pendingTransferId.value = null;
  try {
    const { data } = await ChatAPI.transferOwner(activeConv.value.id, userId);
    activeConv.value.creator_id = data.creator_id;
    useAlert(L.transferred);
    pollActive();
    fetchConversations();
  } catch (e) {
    useAlert(e?.response?.data?.error || L.error);
  }
};

// 退群两步确认；群主有其他成员时必须先转让（前端禁用 + 后端拦截）。
const ownerMustTransfer = computed(
  () => isGroupOwner.value && activeParticipants.value.length > 1
);
const leaveGroup = async () => {
  if (ownerMustTransfer.value) return;
  if (!pendingLeave.value) {
    pendingLeave.value = true;
    return;
  }
  pendingLeave.value = false;
  try {
    await ChatAPI.leave(activeConv.value.id);
    detailDialog.value?.close();
    activeConv.value = null;
    useAlert(L.left);
    fetchConversations();
  } catch (e) {
    useAlert(e?.response?.data?.error || L.error);
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
  loadOrgData();
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
  <div class="w-full h-full overflow-hidden bg-transparent">
    <div
      class="flex w-full h-full overflow-hidden border shadow-lg bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 border-white/50 rounded-3xl shadow-n-iris-9/5"
    >
      <!-- 左：会话列表 -->
      <aside class="flex flex-col shrink-0 w-[300px] border-r border-n-weak">
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
              class="w-full py-2.5 pl-10 pr-3 text-sm border rounded-full reset-base border-transparent bg-n-alpha-1 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-7 focus-visible:bg-n-solid-1"
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
            class="flex items-center w-full gap-3 px-3 py-2.5 mb-0.5 text-left transition-colors rounded-2xl outline-none focus-visible:ring-2 focus-visible:ring-n-iris-7"
            :class="
              activeConv && activeConv.id === conv.id
                ? 'bg-n-iris-3'
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
                    conv.unread_count
                      ? 'text-n-slate-12 font-medium'
                      : 'text-n-slate-10'
                  "
                >
                  {{ conv.last_message?.content || '—' }}
                </span>
                <span
                  v-if="conv.unread_count"
                  class="grid shrink-0 min-w-[18px] h-[18px] px-1 rounded-full text-[10px] font-semibold text-white place-items-center bg-n-iris-9"
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
        class="flex flex-col flex-1 min-w-0 bg-gradient-to-b from-n-iris-1/60 to-n-iris-2/60"
      >
        <!-- 空状态 -->
        <div
          v-if="!activeConv"
          class="flex flex-col items-center justify-center flex-1 gap-3 text-n-slate-10"
        >
          <div
            class="grid rounded-full size-16 place-items-center bg-n-iris-3 text-n-iris-11"
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
                  <button
                    type="button"
                    class="text-xs text-n-slate-10 hover:text-n-iris-11 hover:underline"
                    @click="openGroupDetail"
                  >
                    {{ L.members(activeConv.participant_count) }}
                  </button>
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
            <button
              v-if="activeConv.kind === 'group'"
              type="button"
              :title="L.detailTitle"
              class="grid ml-auto transition-colors rounded-full shrink-0 size-9 place-items-center text-n-slate-10 hover:bg-n-alpha-1 hover:text-n-slate-12"
              @click="openGroupDetail"
            >
              <Icon icon="i-lucide-ellipsis" class="size-5" />
            </button>
          </header>

          <!-- 群公告横幅（点开看详情/编辑） -->
          <button
            v-if="activeConv.kind === 'group' && activeConv.announcement"
            type="button"
            class="flex items-start gap-2.5 mx-6 mt-3 px-4 py-2.5 text-left transition-colors rounded-2xl bg-n-solid-1/80 ring-1 ring-inset ring-n-weak shadow-sm hover:bg-n-solid-1"
            @click="openGroupDetail"
          >
            <Icon
              icon="i-lucide-megaphone"
              class="size-4 mt-0.5 shrink-0 text-n-iris-10"
            />
            <span class="text-xs leading-relaxed text-n-slate-11 line-clamp-2">
              {{ activeConv.announcement }}
            </span>
          </button>

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
                  v-if="msg.content"
                  class="px-4 py-2.5 text-sm leading-relaxed break-words whitespace-pre-wrap shadow-sm rounded-[20px]"
                  :class="
                    msg.sender_id === currentUserId
                      ? 'bg-n-solid-1 text-n-slate-12 ring-1 ring-inset ring-n-weak rounded-br-md'
                      : 'bg-n-slate-12 text-n-slate-1 rounded-bl-md'
                  "
                >
                  {{ msg.content }}
                </div>
                <!-- 附件 -->
                <div
                  v-if="msg.files && msg.files.length"
                  class="flex flex-col gap-1.5"
                  :class="[
                    msg.content ? 'mt-1.5' : '',
                    msg.sender_id === currentUserId
                      ? 'items-end'
                      : 'items-start',
                  ]"
                >
                  <template v-for="f in msg.files" :key="f.id">
                    <a
                      v-if="f.is_image"
                      :href="f.url"
                      target="_blank"
                      rel="noopener"
                    >
                      <img
                        :src="f.url"
                        :alt="f.filename"
                        class="max-w-[220px] max-h-[220px] rounded-2xl shadow-sm object-cover"
                      />
                    </a>
                    <a
                      v-else
                      :href="f.url"
                      target="_blank"
                      rel="noopener"
                      download
                      class="flex items-center gap-2.5 px-3 py-2 max-w-[240px] rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak shadow-sm hover:bg-n-alpha-1 transition-colors"
                    >
                      <span
                        class="grid rounded-lg shrink-0 size-9 place-items-center bg-n-iris-3 text-n-iris-11"
                      >
                        <Icon icon="i-lucide-file" class="size-[18px]" />
                      </span>
                      <span class="min-w-0">
                        <span
                          class="block text-sm truncate text-n-slate-12"
                          :title="f.filename"
                        >
                          {{ f.filename }}
                        </span>
                        <span class="text-[11px] text-n-slate-10">
                          {{ fmtSize(f.byte_size) }}
                        </span>
                      </span>
                    </a>
                  </template>
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
            class="flex flex-col gap-2 px-4 py-3.5 shrink-0 border-t border-n-weak bg-n-solid-1"
          >
            <!-- 待发附件 -->
            <div v-if="pendingFiles.length" class="flex flex-wrap gap-2">
              <div
                v-for="(f, i) in pendingFiles"
                :key="i"
                class="flex items-center gap-1.5 py-1 pl-2.5 pr-1.5 text-xs rounded-lg bg-n-alpha-1 ring-1 ring-inset ring-n-weak text-n-slate-11"
              >
                <Icon icon="i-lucide-paperclip" class="size-3.5 shrink-0" />
                <span class="max-w-[140px] truncate">{{ f.name }}</span>
                <button
                  type="button"
                  class="grid rounded size-4 place-items-center hover:bg-n-alpha-2"
                  @click="removePending(i)"
                >
                  <Icon icon="i-lucide-x" class="size-3" />
                </button>
              </div>
            </div>
            <div class="flex items-end gap-2.5">
              <button
                type="button"
                :title="L.attach"
                class="grid transition-colors rounded-full shrink-0 size-11 place-items-center text-n-slate-10 hover:bg-n-alpha-1 hover:text-n-slate-12"
                @click="chatFileInput?.click()"
              >
                <Icon icon="i-lucide-paperclip" class="size-5" />
              </button>
              <input
                ref="chatFileInput"
                type="file"
                multiple
                class="hidden"
                @change="onFilesPicked"
              />
              <div
                class="flex items-center flex-1 px-4 py-2.5 transition-shadow rounded-full bg-n-alpha-1 ring-1 ring-inset ring-n-weak focus-within:ring-2 focus-within:ring-n-iris-7"
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
                :disabled="!newText.trim() && !pendingFiles.length"
                class="grid transition-colors rounded-full shrink-0 size-11 place-items-center bg-n-iris-9 text-white hover:bg-n-iris-10 disabled:opacity-40 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-7 focus-visible:ring-offset-2 focus-visible:ring-offset-n-solid-1"
                @click="sendMessage"
              >
                <Icon icon="i-lucide-send-horizontal" class="size-[18px]" />
              </button>
            </div>
          </div>
        </template>
      </section>
    </div>

    <!-- 发起单聊：按组织架构分组 + 搜索姓名/职位 -->
    <Dialog ref="userDialog" :title="L.pickUser" :show-confirm-button="false">
      <div class="flex flex-col gap-2">
        <Input
          v-model="pickerQuery"
          :placeholder="L.pickerSearchPlaceholder"
          class="reset-base"
        />
        <div class="flex flex-col gap-1 max-h-[50vh] overflow-y-auto">
          <div
            v-if="!pickerGroups.length"
            class="p-6 text-sm text-center text-n-slate-10"
          >
            {{ L.pickerEmpty }}
          </div>
          <template v-for="group in pickerGroups" :key="group.key">
            <div
              class="sticky top-0 z-10 px-2 py-1 text-xs font-medium bg-n-solid-1 text-n-slate-10"
            >
              {{ group.name }}
            </div>
            <button
              v-for="entry in group.members"
              :key="`${group.key}-${entry.agent.id}`"
              class="flex items-center gap-3 p-2 text-left rounded-lg hover:bg-n-alpha-1"
              @click="startDirect(entry.agent.id)"
            >
              <Avatar
                :name="entry.agent.name"
                :src="entry.agent.thumbnail || ''"
                :status="entry.agent.availability_status || null"
                :size="36"
                rounded-full
                hide-offline-status
              />
              <div class="min-w-0">
                <div
                  class="flex items-center gap-1.5 text-sm truncate text-n-slate-12"
                >
                  {{ entry.agent.name }}
                  <span
                    v-if="entry.title"
                    class="px-1.5 rounded-full text-[11px] bg-n-iris-3 text-n-iris-11"
                  >
                    {{ entry.title }}
                  </span>
                </div>
                <div class="text-xs truncate text-n-slate-10">
                  {{ entry.agent.email }}
                </div>
              </div>
            </button>
          </template>
        </div>
      </div>
    </Dialog>

    <!-- 建群 -->
    <Dialog
      ref="groupDialog"
      :title="L.newGroup"
      :confirm-button-label="L.create"
      confirm-button-color="iris"
      @confirm="createGroup"
    >
      <div class="flex flex-col gap-4">
        <Input v-model="groupForm.name" :label="L.groupName" autofocus />
        <TextArea
          v-model="groupForm.announcement"
          :label="L.announcement"
          :placeholder="L.announcementPlaceholder"
          :max-length="500"
        />
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
                class="accent-n-iris-9"
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

    <!-- 群聊详情：公告 + 成员 -->
    <Dialog
      ref="detailDialog"
      :title="L.detailTitle"
      :show-confirm-button="false"
    >
      <div class="flex flex-col gap-5">
        <!-- 群公告 -->
        <div>
          <div class="flex items-center gap-1.5 mb-2">
            <Icon icon="i-lucide-megaphone" class="size-4 text-n-iris-10" />
            <span class="text-heading-3 text-n-slate-12">
              {{ L.announcement }}
            </span>
          </div>
          <template v-if="isGroupOwner">
            <TextArea
              v-model="announcementDraft"
              :placeholder="L.announcementPlaceholder"
              :max-length="500"
            />
            <div class="flex justify-end mt-2">
              <Button
                :label="L.save"
                color="iris"
                size="sm"
                :disabled="
                  !announcementDraft.trim() ||
                  announcementDraft.trim() === (activeConv?.announcement || '')
                "
                @click="saveAnnouncement"
              />
            </div>
          </template>
          <template v-else>
            <p
              class="px-3.5 py-3 text-sm leading-relaxed whitespace-pre-wrap rounded-xl bg-n-alpha-1 text-n-slate-11"
            >
              {{ activeConv?.announcement || L.noAnnouncement }}
            </p>
            <p class="mt-1.5 text-xs text-n-slate-9">{{ L.ownerOnlyHint }}</p>
          </template>
        </div>

        <!-- 群成员 -->
        <div>
          <div class="flex items-center gap-1.5 mb-2">
            <Icon icon="i-lucide-users-round" class="size-4 text-n-slate-10" />
            <span class="text-heading-3 text-n-slate-12">
              {{ `${L.memberList} ${activeParticipants.length}` }}
            </span>
          </div>
          <div class="flex flex-col gap-0.5 max-h-[40vh] overflow-y-auto">
            <div
              v-for="p in activeParticipants"
              :key="p.user_id"
              class="flex items-center gap-2.5 px-2 py-1.5 rounded-lg hover:bg-n-alpha-1"
            >
              <Avatar
                :name="p.name"
                :src="agentMap[p.user_id]?.thumbnail || ''"
                :size="32"
                rounded-full
              />
              <span class="flex-1 min-w-0 text-sm truncate text-n-slate-12">
                {{ p.name }}
              </span>
              <span
                v-if="p.user_id === activeConv?.creator_id"
                class="px-2 py-0.5 text-[11px] font-medium rounded-full bg-n-iris-3 text-n-iris-11"
              >
                {{ L.ownerBadge }}
              </span>
              <template v-else-if="isGroupOwner">
                <button
                  type="button"
                  class="px-2.5 py-1 text-xs font-medium transition-colors rounded-full"
                  :class="
                    pendingTransferId === p.user_id
                      ? 'bg-n-iris-9 text-white hover:bg-n-iris-10'
                      : 'text-n-iris-11 hover:bg-n-iris-3'
                  "
                  @click="transferOwner(p.user_id)"
                >
                  {{
                    pendingTransferId === p.user_id
                      ? L.confirmTransfer
                      : L.transfer
                  }}
                </button>
                <button
                  type="button"
                  class="px-2.5 py-1 text-xs font-medium transition-colors rounded-full"
                  :class="
                    pendingRemoveId === p.user_id
                      ? 'bg-n-ruby-9 text-white hover:bg-n-ruby-10'
                      : 'text-n-ruby-11 hover:bg-n-ruby-3'
                  "
                  @click="removeMember(p.user_id)"
                >
                  {{
                    pendingRemoveId === p.user_id ? L.confirmRemove : L.remove
                  }}
                </button>
              </template>
            </div>
          </div>
        </div>

        <!-- 退出群聊：群主须先转让 -->
        <div
          class="flex items-center justify-between pt-1 border-t border-n-weak"
        >
          <span v-if="ownerMustTransfer" class="text-xs text-n-slate-9">
            {{ L.ownerLeaveHint }}
          </span>
          <span v-else class="text-xs text-n-slate-9" />
          <button
            type="button"
            class="px-3 py-1.5 text-xs font-medium transition-colors rounded-full"
            :class="
              ownerMustTransfer
                ? 'text-n-slate-9 cursor-not-allowed opacity-60'
                : pendingLeave
                  ? 'bg-n-ruby-9 text-white hover:bg-n-ruby-10'
                  : 'text-n-ruby-11 hover:bg-n-ruby-3'
            "
            :disabled="ownerMustTransfer"
            @click="leaveGroup"
          >
            {{ pendingLeave ? L.confirmLeave : L.leaveGroup }}
          </button>
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
