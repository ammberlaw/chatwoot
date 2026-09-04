<script setup>
import { ref, computed, onMounted, onBeforeUnmount, nextTick } from 'vue';
import { useRouter, useRoute } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import ChatAPI from 'dashboard/api/chat/conversations';
import AgentAPI from 'dashboard/api/agents';
import DepartmentsAPI from 'dashboard/api/org/departments';
import MembershipsAPI from 'dashboard/api/org/memberships';
import CustomerAPI from 'dashboard/api/crm/customers';
import SalesOrderAPI from 'dashboard/api/crm/salesOrders';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import EmojiPicker from 'shared/components/emoji/EmojiPicker.vue';

const currentUserId = useMapGetter('getCurrentUserID');
const accountId = useMapGetter('getCurrentAccountId');
const router = useRouter();
const route = useRoute();

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
  mentionMe: '@我',
  kindCustomer: '客户',
  kindOrder: '订单',
  refColon: '：',
  sendCard: '发送客户 / 订单卡片',
  pickRefTitle: '选择业务对象',
  searchCustomer: '搜索客户名称',
  searchOrder: '搜索订单号',
  loadingText: '加载中…',
  noResult: '无匹配结果',
  reply: '引用回复',
  forward: '转发',
  multiSelect: '多选',
  cancelSelect: '取消',
  selectedN: n => `已选 ${n} 条`,
  forwardTitle: '转发到',
  forwardEmpty: '没有可转发的会话',
  forwarded: '已转发',
  pickToForward: '请选择要转发的消息',
  emoji: '表情',
  zoomOut: '缩小',
  zoomIn: '放大',
  resetZoom: '还原',
  closeImage: '关闭',
  replyingPrefix: '回复',
  imageLabel: '[图片]',
  fileLabel: '[文件]',
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

// 消息里的 http(s) 链接转成可点击 <a>（如提成表/绩效表转发过来的回跳链接）。
// 先转义 HTML 再替换，防 XSS；只处理 URL，不做 markdown，保留 whitespace-pre-wrap 的换行。
const escapeHtml = s =>
  (s || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
const linkifyContent = content =>
  escapeHtml(content).replace(
    /(https?:\/\/[^\s<]+)/g,
    url =>
      `<a href="${url}" target="_blank" rel="noopener noreferrer" class="underline font-medium">${url}</a>`
  );

// 正文渲染：链接化 + 高亮被 @ 到的成员名（按消息 mentioned_ids 精确匹配，避免误伤）。
// 提及做成小胶囊，且按气泡深浅取色——自己(浅底)深紫，别人(深底)亮紫白字，两种底都清晰。
const renderContent = msg => {
  const own = msg.sender_id === currentUserId.value;
  const cls = own
    ? 'rounded px-0.5 font-semibold text-n-iris-11 bg-n-iris-3'
    : 'rounded px-0.5 font-semibold text-white bg-n-iris-9';
  let html = linkifyContent(msg.content);
  (msg.mentioned_ids || []).forEach(uid => {
    const name = agentMap.value[uid]?.name;
    if (!name) return;
    const token = escapeHtml(`@${name}`);
    html = html.split(token).join(`<span class="${cls}">${token}</span>`);
  });
  return html;
};
const isMentionedMe = msg =>
  (msg.mentioned_ids || []).includes(currentUserId.value) &&
  msg.sender_id !== currentUserId.value;

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

// 用最大 id 作为增量拉取游标（防乱序）。
const lastMessageId = computed(() =>
  messages.value.reduce((max, m) => Math.max(max, m.id), 0)
);

// 追加消息并按 id 去重：本地发送 push 与实时/轮询拉取可能带来同一条，
// 数组出现重复 id 会让 :key 冲突、界面「一条变两条又变回一条」。
const appendMessages = list => {
  if (!list?.length) return false;
  const seen = new Set(messages.value.map(m => m.id));
  let added = false;
  list.forEach(m => {
    if (!seen.has(m.id)) {
      messages.value.push(m);
      seen.add(m.id);
      added = true;
    }
  });
  return added;
};

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
    if (appendMessages(msgs.payload)) {
      scrollToBottom();
      ChatAPI.markRead(activeConv.value.id);
      emitter.emit('CHAT_UNREAD_CHANGED');
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
    emitter.emit('CHAT_UNREAD_CHANGED');
  } catch {
    /* ignore */
  }
};

// 待发附件
const pendingFiles = ref([]);
const chatFileInput = ref(null);
// 图片待发项的缩略图预览（像微信一样先看到图再发）。
const previewCache = new Map();
const previewUrl = f => {
  if (!f?.type?.startsWith('image/')) return '';
  if (!previewCache.has(f)) previewCache.set(f, URL.createObjectURL(f));
  return previewCache.get(f);
};
const revokePreview = f => {
  if (previewCache.has(f)) {
    URL.revokeObjectURL(previewCache.get(f));
    previewCache.delete(f);
  }
};
const onFilesPicked = e => {
  pendingFiles.value.push(...Array.from(e.target.files || []));
  e.target.value = '';
};
const removePending = i => {
  const [f] = pendingFiles.value.splice(i, 1);
  revokePreview(f);
};

// 直接粘贴截图（Ctrl/⌘+V）：抓剪贴板里的图片塞进待发列表，和微信一致。
const onComposerPaste = e => {
  const items = Array.from(e.clipboardData?.items || []);
  const imgs = items
    .filter(it => it.type?.startsWith('image/'))
    .map(it => it.getAsFile())
    .filter(Boolean);
  if (!imgs.length) return;
  e.preventDefault(); // 阻止把图片的文件名等塞进文本框
  imgs.forEach((f, i) => {
    // 剪贴板图片常统一叫 image.png，补个带时间戳的名字避免同名。
    const named =
      f.name && f.name !== 'image.png'
        ? f
        : new File([f], `screenshot-${Date.now()}-${i}.png`, {
            type: f.type || 'image/png',
          });
    pendingFiles.value.push(named);
  });
};
const fmtSize = b =>
  b < 1024
    ? `${b}B`
    : b < 1048576
      ? `${Math.round(b / 1024)}KB`
      : `${(b / 1048576).toFixed(1)}MB`;

// ── @提及（仅群聊）──────────────────────────────────────────
// 群成员（除自己），供 @ 下拉。
const mentionMembers = computed(() =>
  activeConv.value?.kind === 'group'
    ? activeParticipants.value.filter(p => p.user_id !== currentUserId.value)
    : []
);
const mentionOpen = ref(false);
const mentionQuery = ref('');
// 已插入的 @ 记录：{ name, userId }，发送时据文本是否仍含 @name 判定生效。
const mentionedList = ref([]);
const composerRef = ref(null);

const mentionCandidates = computed(() => {
  const q = mentionQuery.value.toLowerCase();
  return mentionMembers.value.filter(
    m => !q || (m.name || '').toLowerCase().includes(q)
  );
});

// 输入时检测末尾的「@关键词」，弹出候选（群聊）。
const onComposerInput = () => {
  if (activeConv.value?.kind !== 'group') return;
  const m = newText.value.match(/@([^\s@]*)$/);
  if (m) {
    mentionQuery.value = m[1];
    mentionOpen.value = true;
  } else {
    mentionOpen.value = false;
  }
};

const pickMention = member => {
  newText.value = newText.value.replace(/@([^\s@]*)$/, `@${member.name} `);
  if (!mentionedList.value.some(x => x.userId === member.user_id)) {
    mentionedList.value.push({ name: member.name, userId: member.user_id });
  }
  mentionOpen.value = false;
  nextTick(() => composerRef.value?.focus?.());
};

// ── 业务对象进群（客户 / 订单卡片）────────────────────────
const REF_TYPE_LABEL = { customer: '客户', sales_order: '订单' };
const pendingRef = ref(null); // { ref_type, ref_id, snapshot:{title,subtitle,code} }
const refDialog = ref(null);
const refKind = ref('customer');
const refQuery = ref('');
const refResults = ref([]);
const refLoading = ref(false);

const searchRef = async () => {
  refLoading.value = true;
  try {
    if (refKind.value === 'customer') {
      const { data } = await CustomerAPI.get({
        q: refQuery.value,
        per_page: 20,
      });
      refResults.value = (data.payload || []).map(c => ({
        ref_type: 'customer',
        ref_id: c.id,
        snapshot: { title: c.name, subtitle: '', code: '' },
      }));
    } else {
      const { data } = await SalesOrderAPI.get({ q: refQuery.value });
      refResults.value = (data.payload || []).map(o => ({
        ref_type: 'sales_order',
        ref_id: o.id,
        snapshot: {
          title: o.order_no,
          subtitle: o.customer_name || '',
          code: o.order_no,
        },
      }));
    }
  } catch {
    refResults.value = [];
  } finally {
    refLoading.value = false;
  }
};

const openRefPicker = () => {
  refKind.value = 'customer';
  refQuery.value = '';
  refResults.value = [];
  refDialog.value?.open();
  searchRef();
};

const chooseRef = item => {
  pendingRef.value = item;
  refDialog.value?.close();
};
const clearPendingRef = () => {
  pendingRef.value = null;
};

// 点击消息里的业务卡片 → 跳转对象详情。
const openRef = target => {
  if (target.type === 'customer') {
    router.push({
      name: 'crm_customer_detail_index',
      params: { accountId: accountId.value, id: target.id },
    });
  } else if (target.type === 'sales_order') {
    router.push({
      name: 'crm_sales_orders_index',
      params: { accountId: accountId.value },
    });
  }
};

const buildSendExtra = content => {
  const mentionedIds = mentionedList.value
    .filter(x => content.includes(`@${x.name}`))
    .map(x => x.userId);
  const r = pendingRef.value;
  return {
    mentioned_ids: mentionedIds,
    ref_type: r?.ref_type,
    ref_id: r?.ref_id,
    ref_snapshot: r?.snapshot,
  };
};

// ── 引用回复 ───────────────────────────────────────────────
const replyingTo = ref(null); // 正在引用回复的消息
const startReply = msg => {
  replyingTo.value = msg;
  nextTick(() => composerRef.value?.focus?.());
};
const clearReply = () => {
  replyingTo.value = null;
};
// 消息摘要（引用预览/转发标签用）：优先正文，否则图片/文件占位。
const msgSummary = msg => {
  if (msg.content) return msg.content;
  if ((msg.files || []).some(f => f.is_image)) return L.imageLabel;
  if ((msg.files || []).length) return L.fileLabel;
  return '';
};

// ── 表情 ───────────────────────────────────────────────────
const emojiOpen = ref(false);
const onEmojiSelect = payload => {
  newText.value += payload.value || payload.emoji || '';
  emojiOpen.value = false;
  nextTick(() => composerRef.value?.focus?.());
};

// ── 图片 lightbox（本层浮层预览 + 缩放，不再新开网页）─────────
const lightbox = ref({ open: false, images: [], index: 0, scale: 1 });
// 收集当前会话里所有图片 url（供左右翻页）。
const openLightbox = clickedUrl => {
  const imgs = [];
  messages.value.forEach(m =>
    (m.files || []).forEach(f => {
      if (f.is_image) imgs.push(f.url);
    })
  );
  const index = Math.max(0, imgs.indexOf(clickedUrl));
  lightbox.value = { open: true, images: imgs, index, scale: 1 };
};
const closeLightbox = () => {
  lightbox.value.open = false;
};
const zoomLightbox = delta => {
  const next = Math.round((lightbox.value.scale + delta) * 10) / 10;
  lightbox.value.scale = Math.min(4, Math.max(0.3, next));
};
const resetZoom = () => {
  lightbox.value.scale = 1;
};
const stepLightbox = delta => {
  const n = lightbox.value.images.length;
  if (!n) return;
  lightbox.value.index = (lightbox.value.index + delta + n) % n;
  lightbox.value.scale = 1;
};
const currentLightboxImage = computed(
  () => lightbox.value.images[lightbox.value.index] || ''
);

// ── 多选 + 转发 ─────────────────────────────────────────────
const selectMode = ref(false);
const selectedIds = ref([]);
const forwardDialog = ref(null);
const forwardSourceIds = ref([]); // 待转发的消息 id（多选批量或单条）
const enterSelect = msg => {
  selectMode.value = true;
  selectedIds.value = msg ? [msg.id] : [];
};
const exitSelect = () => {
  selectMode.value = false;
  selectedIds.value = [];
};
const toggleSelect = msg => {
  const i = selectedIds.value.indexOf(msg.id);
  if (i >= 0) selectedIds.value.splice(i, 1);
  else selectedIds.value.push(msg.id);
};
// 打开转发目标选择：ids 为空时用多选结果。
const openForward = ids => {
  const list = ids && ids.length ? ids : selectedIds.value;
  if (!list.length) {
    useAlert(L.pickToForward);
    return;
  }
  forwardSourceIds.value = [...list];
  forwardDialog.value?.open();
};
const doForward = async targetConvId => {
  try {
    await ChatAPI.forward(
      activeConv.value.id,
      forwardSourceIds.value,
      targetConvId
    );
    forwardDialog.value?.close();
    exitSelect();
    useAlert(L.forwarded);
    fetchConversations();
  } catch (e) {
    useAlert(e?.response?.data?.error || L.error);
  }
};
// 转发目标：除当前会话外的全部会话。
const forwardTargets = computed(() =>
  conversations.value.filter(c => c.id !== activeConv.value?.id)
);

const sendMessage = async () => {
  if (mentionOpen.value) return; // @ 面板打开时回车用于选人，不发送
  let content = newText.value.trim();
  const files = pendingFiles.value;
  const heldRef = pendingRef.value;
  if ((!content && !files.length && !heldRef) || !activeConv.value) return;
  // 仅带业务卡片、无正文无附件时，用卡片标题兜底正文（后端要求正文/附件二选一）。
  if (!content && !files.length && heldRef) {
    content = `[${REF_TYPE_LABEL[heldRef.ref_type]}] ${heldRef.snapshot?.title || ''}`;
  }
  const extra = buildSendExtra(content);
  if (replyingTo.value) extra.reply_to_id = replyingTo.value.id;
  const heldReply = replyingTo.value;
  newText.value = '';
  pendingFiles.value = [];
  pendingRef.value = null;
  mentionedList.value = [];
  replyingTo.value = null;
  emojiOpen.value = false;
  try {
    const { data } = await ChatAPI.send(
      activeConv.value.id,
      content,
      files,
      extra
    );
    appendMessages([data]);
    scrollToBottom();
    fetchConversations();
    files.forEach(revokePreview);
  } catch {
    useAlert(L.error);
    pendingRef.value = heldRef;
    replyingTo.value = heldReply;
  }
};

// 回车：@ 面板开着时选中首个候选，否则发送。
const onEnter = () => {
  if (mentionOpen.value && mentionCandidates.value.length) {
    pickMention(mentionCandidates.value[0]);
    return;
  }
  sendMessage();
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
  const pick = p => ({ user_id: p.user_id, name: p.name });
  readDetail.value = { read: read.map(pick), unread: unread.map(pick) };
  readDialogRef.value?.open();
};

// 钉钉式：消息旁展示已读者的前几个头像（点开看完整名单）。
const readAvatars = msg => readSplit(msg).read.slice(0, 3);

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

// 实时新消息：活跃会话即时拉取，列表即时刷新未读/排序。
const onRealtimeMessage = async data => {
  if (!data || data.conversation_id == null) return;
  const isActive =
    activeConv.value && activeConv.value.id === data.conversation_id;
  if (isActive) await pollActive();
  await fetchConversations();
  if (isActive) {
    const c = conversations.value.find(x => x.id === data.conversation_id);
    if (c) c.unread_count = 0;
  }
};

// 图片浮层：Esc 关闭。
const onKeydown = e => {
  if (e.key === 'Escape' && lightbox.value.open) closeLightbox();
};

onMounted(async () => {
  fetchConversations();
  loadAgents();
  loadOrgData();
  window.addEventListener('keydown', onKeydown);
  // 从别处（如 MES 订单点阶段负责人）带 ?peer= 进来：直接打开与该同事的私聊。
  if (route.query.peer) startDirect(Number(route.query.peer));
  emitter.on('CHAT_MESSAGE_CREATED', onRealtimeMessage);
  // 实时优先；轮询降级为兜底（刷新在线状态 + 断线自愈）。
  listTimer = setInterval(() => {
    fetchConversations();
    loadAgents();
  }, 15000);
  msgTimer = setInterval(pollActive, 12000);
});
onBeforeUnmount(() => {
  clearInterval(listTimer);
  clearInterval(msgTimer);
  emitter.off('CHAT_MESSAGE_CREATED', onRealtimeMessage);
  window.removeEventListener('keydown', onKeydown);
});
</script>

<template>
  <div
    class="w-full h-full overflow-hidden bg-transparent max-md:min-h-[100dvh] max-md:-mb-24"
  >
    <div
      class="flex w-full h-full overflow-hidden border shadow-lg bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 border-white/50 rounded-3xl shadow-n-iris-9/5"
    >
      <!-- 左：会话列表（手机端：有选中会话时隐藏，让消息区占满） -->
      <aside
        class="flex-col shrink-0 w-full md:w-[300px] border-r border-n-weak"
        :class="activeConv ? 'hidden md:flex' : 'flex'"
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

      <!-- 右：消息（薄荷底色，头部/输入框保持白色浮于其上）
           手机端：无选中会话时隐藏，让列表占满 -->
      <section
        class="flex-col flex-1 min-w-0 bg-gradient-to-b from-n-iris-1/60 to-n-iris-2/60"
        :class="activeConv ? 'flex' : 'hidden md:flex'"
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
            class="flex items-center gap-3 px-4 py-3 sm:px-6 sm:py-4 shrink-0 border-b border-n-weak bg-n-solid-1"
          >
            <button
              type="button"
              class="grid transition-colors rounded-full shrink-0 size-8 -ml-1 place-items-center md:hidden text-n-slate-11 hover:bg-n-alpha-2"
              @click="activeConv = null"
            >
              <Icon icon="i-lucide-chevron-left" class="size-5" />
            </button>
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
            class="flex items-start gap-2.5 mx-4 sm:mx-6 mt-3 px-4 py-2.5 text-left transition-colors rounded-2xl bg-n-solid-1/80 ring-1 ring-inset ring-n-weak shadow-sm hover:bg-n-solid-1"
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
          <div
            ref="threadRef"
            class="flex-1 px-4 py-4 sm:px-6 sm:py-5 overflow-y-auto"
          >
            <div
              v-for="msg in messages"
              :key="msg.id"
              class="flex gap-2.5 mb-4 group"
              :class="[
                msg.sender_id === currentUserId
                  ? 'flex-row-reverse'
                  : 'flex-row',
                selectMode ? 'cursor-pointer' : '',
              ]"
              @click="selectMode ? toggleSelect(msg) : null"
            >
              <label
                v-if="selectMode"
                class="flex items-center self-center shrink-0"
                @click.stop
              >
                <input
                  type="checkbox"
                  class="size-4 accent-n-iris-9"
                  :checked="selectedIds.includes(msg.id)"
                  @change="toggleSelect(msg)"
                />
              </label>
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
                <!-- 引用的原消息（点击可看，简版只展示摘要）-->
                <div
                  v-if="msg.reply_to"
                  class="mb-1 max-w-full px-2.5 py-1.5 rounded-xl bg-n-alpha-2 ring-1 ring-inset ring-n-weak border-l-2 border-n-iris-8"
                >
                  <span class="block text-[11px] font-medium text-n-iris-11">
                    {{ msg.reply_to.sender_name }}
                  </span>
                  <span class="block text-[11px] text-n-slate-10 line-clamp-2">
                    {{
                      msg.reply_to.is_image
                        ? L.imageLabel
                        : msg.reply_to.content
                    }}
                  </span>
                </div>
                <div
                  v-if="msg.content"
                  class="px-4 py-2.5 text-sm leading-relaxed break-words whitespace-pre-wrap shadow-sm rounded-[20px]"
                  :class="[
                    msg.sender_id === currentUserId
                      ? 'bg-n-solid-1 text-n-slate-12 ring-1 ring-inset ring-n-weak rounded-br-md'
                      : 'bg-n-slate-12 text-n-slate-1 rounded-bl-md',
                    isMentionedMe(msg) ? 'ring-2 ring-n-iris-8' : '',
                  ]"
                >
                  <span
                    v-if="isMentionedMe(msg)"
                    class="inline-block mr-1 px-1.5 rounded text-[10px] font-semibold bg-n-iris-9 text-white align-[2px]"
                  >
                    {{ L.mentionMe }}
                  </span>
                  <!-- eslint-disable-next-line vue/no-v-html -->
                  <span v-html="renderContent(msg)" />
                </div>
                <!-- 业务对象卡片：点击跳转客户/订单 -->
                <button
                  v-if="msg.ref"
                  type="button"
                  class="flex items-center gap-2.5 mt-1.5 px-3 py-2 max-w-[260px] text-left rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak shadow-sm hover:bg-n-alpha-1 transition-colors"
                  @click="openRef(msg.ref)"
                >
                  <span
                    class="grid rounded-lg shrink-0 size-9 place-items-center bg-n-teal-3 text-n-teal-11"
                  >
                    <Icon
                      :icon="
                        msg.ref.type === 'customer'
                          ? 'i-lucide-building-2'
                          : 'i-lucide-file-text'
                      "
                      class="size-[18px]"
                    />
                  </span>
                  <span class="min-w-0">
                    <span class="block text-xs text-n-slate-10">
                      {{
                        msg.ref.type === 'customer'
                          ? L.kindCustomer
                          : L.kindOrder
                      }}
                    </span>
                    <span
                      class="block text-sm font-medium truncate text-n-slate-12"
                    >
                      {{ msg.ref.snapshot?.title }}
                    </span>
                    <span
                      v-if="msg.ref.snapshot?.subtitle"
                      class="block text-[11px] truncate text-n-slate-10"
                    >
                      {{ msg.ref.snapshot.subtitle }}
                    </span>
                  </span>
                </button>
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
                    <button
                      v-if="f.is_image"
                      type="button"
                      @click.stop="
                        selectMode ? toggleSelect(msg) : openLightbox(f.url)
                      "
                    >
                      <img
                        :src="f.url"
                        :alt="f.filename"
                        class="max-w-[220px] max-h-[220px] rounded-2xl shadow-sm object-cover cursor-zoom-in"
                      />
                    </button>
                    <a
                      v-else
                      :href="f.url"
                      target="_blank"
                      rel="noopener noreferrer"
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
                      class="flex items-center gap-1 group/read"
                      @click="openReadDetail(msg)"
                    >
                      <span
                        v-if="readAvatars(msg).length"
                        class="flex items-center -space-x-1.5"
                      >
                        <Avatar
                          v-for="p in readAvatars(msg)"
                          :key="p.user_id"
                          :name="p.name"
                          :src="agentMap[p.user_id]?.thumbnail || ''"
                          :size="16"
                          rounded-full
                          class="ring-1 ring-n-solid-1"
                        />
                      </span>
                      <span
                        class="text-[10px] text-n-teal-11 group-hover/read:underline"
                      >
                        {{ groupReadLabel(msg) }}
                      </span>
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
              <!-- 悬浮操作：引用回复 / 转发 / 多选 -->
              <div
                v-if="!selectMode"
                class="flex items-center self-center gap-0.5 transition-opacity opacity-0 group-hover:opacity-100"
              >
                <button
                  type="button"
                  :title="L.reply"
                  class="grid rounded-full size-7 place-items-center text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12"
                  @click.stop="startReply(msg)"
                >
                  <Icon icon="i-lucide-reply" class="size-4" />
                </button>
                <button
                  type="button"
                  :title="L.forward"
                  class="grid rounded-full size-7 place-items-center text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12"
                  @click.stop="openForward([msg.id])"
                >
                  <Icon icon="i-lucide-forward" class="size-4" />
                </button>
                <button
                  type="button"
                  :title="L.multiSelect"
                  class="grid rounded-full size-7 place-items-center text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12"
                  @click.stop="enterSelect(msg)"
                >
                  <Icon icon="i-lucide-list-checks" class="size-4" />
                </button>
              </div>
            </div>
          </div>

          <!-- 输入区 -->
          <div
            v-if="!selectMode"
            class="flex flex-col gap-2 px-4 py-3.5 shrink-0 border-t border-n-weak bg-n-solid-1"
          >
            <!-- 待发附件（图片显示缩略图，可粘贴截图直接进来）-->
            <div v-if="pendingFiles.length" class="flex flex-wrap gap-2">
              <template v-for="(f, i) in pendingFiles" :key="i">
                <!-- 图片：缩略图 + 悬浮删除 -->
                <div
                  v-if="previewUrl(f)"
                  class="relative rounded-lg overflow-hidden ring-1 ring-inset ring-n-weak size-16 group"
                >
                  <img
                    :src="previewUrl(f)"
                    :alt="f.name"
                    class="object-cover size-full"
                  />
                  <button
                    type="button"
                    class="absolute top-0.5 right-0.5 grid rounded-full size-4 place-items-center bg-black/50 text-white opacity-0 group-hover:opacity-100 transition-opacity"
                    @click="removePending(i)"
                  >
                    <Icon icon="i-lucide-x" class="size-3" />
                  </button>
                </div>
                <!-- 非图片：文件名胶囊 -->
                <div
                  v-else
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
              </template>
            </div>
            <!-- 待发业务卡片 -->
            <div
              v-if="pendingRef"
              class="flex items-center gap-2 py-1.5 pl-2.5 pr-1.5 max-w-max text-xs rounded-lg bg-n-teal-3 ring-1 ring-inset ring-n-teal-6 text-n-teal-11"
            >
              <Icon
                :icon="
                  pendingRef.ref_type === 'customer'
                    ? 'i-lucide-building-2'
                    : 'i-lucide-file-text'
                "
                class="size-3.5 shrink-0"
              />
              <span class="max-w-[200px] truncate">
                {{
                  pendingRef.ref_type === 'customer'
                    ? L.kindCustomer
                    : L.kindOrder
                }}{{ L.refColon }}{{ pendingRef.snapshot?.title }}
              </span>
              <button
                type="button"
                class="grid rounded size-4 place-items-center hover:bg-n-teal-5"
                @click="clearPendingRef"
              >
                <Icon icon="i-lucide-x" class="size-3" />
              </button>
            </div>
            <!-- 正在引用回复的原消息 -->
            <div
              v-if="replyingTo"
              class="flex items-center gap-2 py-1.5 pl-2.5 pr-1.5 max-w-full text-xs rounded-lg bg-n-alpha-1 ring-1 ring-inset ring-n-weak"
            >
              <Icon
                icon="i-lucide-reply"
                class="size-3.5 shrink-0 text-n-iris-10"
              />
              <span class="min-w-0 truncate text-n-slate-11">
                {{ L.replyingPrefix }} {{ replyingTo.sender_name }}：{{
                  msgSummary(replyingTo)
                }}
              </span>
              <button
                type="button"
                class="grid ml-auto rounded size-4 place-items-center shrink-0 hover:bg-n-alpha-2"
                @click="clearReply"
              >
                <Icon icon="i-lucide-x" class="size-3" />
              </button>
            </div>
            <!-- 一体化输入条：图标 + 文本 + 发送同处一栏，紧凑对齐 -->
            <div
              class="relative flex items-center gap-1 pl-2 pr-1.5 py-1.5 transition-shadow rounded-2xl bg-n-alpha-1 ring-1 ring-inset ring-n-weak focus-within:ring-2 focus-within:ring-n-iris-7"
            >
              <!-- @提及候选（群聊，输入 @ 触发）-->
              <div
                v-if="mentionOpen && mentionCandidates.length"
                class="absolute left-2 bottom-full mb-2 z-20 w-56 max-h-52 overflow-y-auto p-1 rounded-xl bg-n-solid-1 ring-1 ring-inset ring-n-weak shadow-xl"
              >
                <button
                  v-for="m in mentionCandidates"
                  :key="m.user_id"
                  type="button"
                  class="flex items-center w-full gap-2 px-2 py-1.5 text-left text-sm rounded-lg hover:bg-n-alpha-1 text-n-slate-12"
                  @click="pickMention(m)"
                >
                  <Avatar
                    :name="m.name"
                    :src="agentMap[m.user_id]?.thumbnail || ''"
                    :size="24"
                    rounded-full
                  />
                  {{ m.name }}
                </button>
              </div>
              <button
                type="button"
                :title="L.attach"
                class="grid transition-colors rounded-lg shrink-0 size-8 place-items-center text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12"
                @click="chatFileInput?.click()"
              >
                <Icon icon="i-lucide-paperclip" class="size-[18px]" />
              </button>
              <input
                ref="chatFileInput"
                type="file"
                multiple
                class="hidden"
                @change="onFilesPicked"
              />
              <button
                type="button"
                :title="L.sendCard"
                class="grid transition-colors rounded-lg shrink-0 size-8 place-items-center text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-teal-11"
                @click="openRefPicker"
              >
                <Icon icon="i-lucide-link" class="size-[18px]" />
              </button>
              <!-- 表情 -->
              <button
                type="button"
                :title="L.emoji"
                class="grid transition-colors rounded-lg shrink-0 size-8 place-items-center text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-iris-11"
                @click="emojiOpen = !emojiOpen"
              >
                <Icon icon="i-lucide-smile" class="size-[18px]" />
              </button>
              <div
                v-if="emojiOpen"
                class="absolute z-30 left-2 bottom-full mb-2"
              >
                <EmojiPicker class="!static" @select="onEmojiSelect" />
              </div>
              <textarea
                ref="composerRef"
                v-model="newText"
                rows="1"
                :placeholder="L.placeholder"
                class="flex-1 self-center h-6 m-0 px-1.5 text-sm leading-6 bg-transparent border-0 outline-none resize-none reset-base text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-0"
                @input="onComposerInput"
                @paste="onComposerPaste"
                @keydown.enter.exact.prevent="onEnter"
                @keydown.esc="mentionOpen = false"
              />
              <button
                type="button"
                :disabled="
                  !newText.trim() && !pendingFiles.length && !pendingRef
                "
                class="grid transition-colors rounded-full shrink-0 size-9 place-items-center bg-n-iris-9 text-white hover:bg-n-iris-10 disabled:opacity-40 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-7"
                @click="sendMessage"
              >
                <Icon icon="i-lucide-send-horizontal" class="size-[18px]" />
              </button>
            </div>
          </div>

          <!-- 多选转发底栏 -->
          <div
            v-else
            class="flex items-center gap-3 px-4 py-3.5 shrink-0 border-t border-n-weak bg-n-solid-1"
          >
            <span class="text-sm text-n-slate-11">
              {{ L.selectedN(selectedIds.length) }}
            </span>
            <div class="flex items-center gap-2 ml-auto">
              <button
                type="button"
                class="h-9 px-4 text-sm rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
                @click="exitSelect"
              >
                {{ L.cancelSelect }}
              </button>
              <button
                type="button"
                :disabled="!selectedIds.length"
                class="inline-flex items-center gap-1.5 h-9 px-4 text-sm font-medium text-white rounded-lg bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-40 disabled:cursor-not-allowed"
                @click="openForward()"
              >
                <Icon icon="i-lucide-forward" class="size-4" />
                {{ L.forward }}
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
              v-for="p in readDetail.read"
              :key="`r-${p.user_id}`"
              class="inline-flex items-center gap-1.5 py-1 pl-1 pr-2.5 text-xs rounded-full bg-n-alpha-1 text-n-slate-12"
            >
              <Avatar
                :name="p.name"
                :src="agentMap[p.user_id]?.thumbnail || ''"
                :size="20"
                rounded-full
              />
              {{ p.name }}
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
              v-for="p in readDetail.unread"
              :key="`u-${p.user_id}`"
              class="inline-flex items-center gap-1.5 py-1 pl-1 pr-2.5 text-xs rounded-full bg-n-alpha-1 text-n-slate-11"
            >
              <Avatar
                :name="p.name"
                :src="agentMap[p.user_id]?.thumbnail || ''"
                :size="20"
                rounded-full
              />
              {{ p.name }}
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

    <!-- 业务对象选择：客户 / 订单 -->
    <Dialog
      ref="refDialog"
      :title="L.pickRefTitle"
      :show-confirm-button="false"
    >
      <div class="flex flex-col gap-3">
        <div class="flex gap-1 p-0.5 rounded-lg bg-n-alpha-1 max-w-max">
          <button
            v-for="k in ['customer', 'sales_order']"
            :key="k"
            type="button"
            class="px-3 py-1 text-sm rounded-md transition-colors"
            :class="
              refKind === k
                ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                : 'text-n-slate-10 hover:text-n-slate-12'
            "
            @click="
              refKind = k;
              searchRef();
            "
          >
            {{ k === 'customer' ? L.kindCustomer : L.kindOrder }}
          </button>
        </div>
        <Input
          v-model="refQuery"
          :placeholder="
            refKind === 'customer' ? L.searchCustomer : L.searchOrder
          "
          class="reset-base"
          @keyup.enter="searchRef"
        />
        <div class="flex flex-col gap-1 max-h-[46vh] overflow-y-auto">
          <p v-if="refLoading" class="p-6 text-sm text-center text-n-slate-10">
            {{ L.loadingText }}
          </p>
          <p
            v-else-if="!refResults.length"
            class="p-6 text-sm text-center text-n-slate-10"
          >
            {{ L.noResult }}
          </p>
          <button
            v-for="item in refResults"
            :key="`${item.ref_type}-${item.ref_id}`"
            type="button"
            class="flex items-center gap-3 p-2 text-left rounded-lg hover:bg-n-alpha-1"
            @click="chooseRef(item)"
          >
            <span
              class="grid rounded-lg shrink-0 size-9 place-items-center bg-n-teal-3 text-n-teal-11"
            >
              <Icon
                :icon="
                  item.ref_type === 'customer'
                    ? 'i-lucide-building-2'
                    : 'i-lucide-file-text'
                "
                class="size-[18px]"
              />
            </span>
            <span class="min-w-0">
              <span class="block text-sm font-medium truncate text-n-slate-12">
                {{ item.snapshot.title }}
              </span>
              <span
                v-if="item.snapshot.subtitle"
                class="block text-xs truncate text-n-slate-10"
              >
                {{ item.snapshot.subtitle }}
              </span>
            </span>
          </button>
        </div>
      </div>
    </Dialog>

    <!-- 转发目标：选择要转发到的会话 -->
    <Dialog
      ref="forwardDialog"
      :title="L.forwardTitle"
      :show-confirm-button="false"
    >
      <div class="flex flex-col gap-1 max-h-[50vh] overflow-y-auto">
        <p
          v-if="!forwardTargets.length"
          class="p-6 text-sm text-center text-n-slate-10"
        >
          {{ L.forwardEmpty }}
        </p>
        <button
          v-for="conv in forwardTargets"
          :key="conv.id"
          type="button"
          class="flex items-center gap-3 p-2 text-left rounded-lg hover:bg-n-alpha-1"
          @click="doForward(conv.id)"
        >
          <Avatar
            :name="conv.name"
            :src="convSrc(conv)"
            :size="36"
            rounded-full
            hide-offline-status
          />
          <span class="min-w-0 text-sm font-medium truncate text-n-slate-12">
            {{ conv.name }}
          </span>
        </button>
      </div>
    </Dialog>

    <!-- 图片浏览浮层：本层预览 + 缩放（不再新开网页）-->
    <Teleport to="body">
      <div
        v-if="lightbox.open"
        class="fixed inset-0 z-[100] flex items-center justify-center bg-black/80 backdrop-blur-sm"
        @click.self="closeLightbox"
      >
        <img
          :src="currentLightboxImage"
          class="max-w-[92vw] max-h-[86vh] object-contain transition-transform select-none"
          :style="{ transform: `scale(${lightbox.scale})` }"
          @click.stop
        />

        <!-- 左右翻页（多张图时）-->
        <button
          v-if="lightbox.images.length > 1"
          type="button"
          class="absolute grid -translate-y-1/2 rounded-full left-4 top-1/2 size-11 place-items-center bg-white/10 text-white hover:bg-white/20"
          @click.stop="stepLightbox(-1)"
        >
          <Icon icon="i-lucide-chevron-left" class="size-6" />
        </button>
        <button
          v-if="lightbox.images.length > 1"
          type="button"
          class="absolute grid -translate-y-1/2 rounded-full right-4 top-1/2 size-11 place-items-center bg-white/10 text-white hover:bg-white/20"
          @click.stop="stepLightbox(1)"
        >
          <Icon icon="i-lucide-chevron-right" class="size-6" />
        </button>

        <!-- 工具条：缩小 / 还原 / 放大 / 关闭 -->
        <div
          class="absolute flex items-center gap-1 px-2 py-1.5 -translate-x-1/2 rounded-full bottom-6 left-1/2 bg-white/10 backdrop-blur"
          @click.stop
        >
          <button
            type="button"
            :title="L.zoomOut"
            class="grid rounded-full size-9 place-items-center text-white hover:bg-white/20"
            @click="zoomLightbox(-0.3)"
          >
            <Icon icon="i-lucide-zoom-out" class="size-5" />
          </button>
          <button
            type="button"
            :title="L.resetZoom"
            class="px-2 text-xs text-white/90 tabular-nums hover:text-white"
            @click="resetZoom"
          >
            {{ Math.round(lightbox.scale * 100) }}%
          </button>
          <button
            type="button"
            :title="L.zoomIn"
            class="grid rounded-full size-9 place-items-center text-white hover:bg-white/20"
            @click="zoomLightbox(0.3)"
          >
            <Icon icon="i-lucide-zoom-in" class="size-5" />
          </button>
        </div>

        <!-- 关闭 -->
        <button
          type="button"
          :title="L.closeImage"
          class="absolute grid rounded-full top-4 right-4 size-10 place-items-center bg-white/10 text-white hover:bg-white/20"
          @click="closeLightbox"
        >
          <Icon icon="i-lucide-x" class="size-6" />
        </button>
      </div>
    </Teleport>
  </div>
</template>
