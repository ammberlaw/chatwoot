<script setup>
import { h, ref, computed, onMounted, onBeforeUnmount, watch } from 'vue';
import { provideSidebarContext, useSidebarResize } from './provider';
import { useRoute } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useKbd } from 'dashboard/composables/utils/useKbd';
import { useMapGetter } from 'dashboard/composables/store';
import { useCrmFinanceOnly } from 'dashboard/composables/useCrmFinanceOnly';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useSidebarKeyboardShortcuts } from './useSidebarKeyboardShortcuts';
import { vOnClickOutside } from '@vueuse/components';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import DocSectionsAPI from 'dashboard/api/crm/docSections';
import CrmCustomerAPI from 'dashboard/api/crm/customers';
import CrmQuoteRequestAPI from 'dashboard/api/crm/quoteRequests';
import CrmSalesOrderAPI from 'dashboard/api/crm/salesOrders';
import CrmKpiSheetAPI from 'dashboard/api/crm/kpiSheets';
import ConversationSourceTagsAPI from 'dashboard/api/crm/conversationSourceTags';
import { useCrmOptions } from 'dashboard/composables/useCrmOptions';
import ScheduleAPI from 'dashboard/api/crm/scheduleEvents';
import ChatConversationAPI from 'dashboard/api/chat/conversations';
import { useMesNotificationsStore } from 'dashboard/stores/mes/notifications';
import MesProductionOrderAPI from 'dashboard/api/mes/productionOrders';
import { emitter } from 'shared/helpers/mitt';
import { useWindowSize, useEventListener } from '@vueuse/core';

import Button from 'dashboard/components-next/button/Button.vue';
import SidebarGroup from './SidebarGroup.vue';
import SidebarProfileMenu from './SidebarProfileMenu.vue';
import SidebarChangelogCard from './SidebarChangelogCard.vue';
import SidebarChangelogButton from './SidebarChangelogButton.vue';
import ChannelLeaf from './ChannelLeaf.vue';
import ChannelIcon from 'next/icon/ChannelIcon.vue';
import SidebarAccountSwitcher from './SidebarAccountSwitcher.vue';
import MesProductLineSwitcher from './MesProductLineSwitcher.vue';
import wintouchIcon from 'dashboard/assets/images/wintouch/icon.png';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import ConversationAPI from 'dashboard/api/conversations';
import {
  SIDEBAR_SORT_SECTIONS,
  getSidebarSortOptions,
  resolveSidebarSort,
  sortSidebarItems,
} from 'dashboard/helper/sidebarSort';

const props = defineProps({
  isMobileSidebarOpen: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'closeKeyShortcutModal',
  'openKeyShortcutModal',
  'showCreateAccountModal',
  'closeMobileSidebar',
]);

const { accountScopedRoute, isOnChatwootCloud } = useAccount();
const store = useStore();
const searchShortcut = useKbd([`$mod`, 'k']);
const { t } = useI18n();

const isACustomBrandedInstance = useMapGetter(
  'globalConfig/isACustomBrandedInstance'
);
const isRTL = useMapGetter('accounts/isRTL');

const { width: windowWidth } = useWindowSize();
const isMobile = computed(() => windowWidth.value < 768);

const accountId = useMapGetter('getCurrentAccountId');
const currentUserId = useMapGetter('getCurrentUserID');
const currentUser = useMapGetter('getCurrentUser');
// 非 CRM 人员隐藏 CRM 销售数据分组（工作台/文档中心/HR/OA/协同等共享模块保留）。
const canAccessCrm = computed(
  () => currentUser.value?.can_access_crm !== false
);
// ERP 财务板块仅财务角色/管理员可见（后端 Erp::BaseController 403 兜底）。
const canAccessErp = computed(() => currentUser.value?.can_access_erp === true);
// TikTok 板块：管理员/副管理员/财务，或 TK 部门负责人/成员（后端派生 can_access_tiktok）。
const canAccessTiktok = computed(
  () => currentUser.value?.can_access_tiktok === true
);
// TK 板块管理（店铺设置/部门管理）仅管理员/副管理员。
const tiktokCanManage = computed(
  () => currentUser.value?.tiktok_can_manage === true
);
// TK 店铺设置：管理层 + 部门负责人（负责人只能新增，改名/删除后端仍拦）。
const tiktokCanCreateShop = computed(
  () => currentUser.value?.tiktok_can_create_shop === true
);
// TK 利润表（含成本/毛利/净利）仅部门负责人与财务/管理层可见（后端 403 兜底）。
const tiktokCanViewProfit = computed(
  () => currentUser.value?.tiktok_can_view_profit === true
);
const isAdmin = computed(() => currentUser.value?.role === 'administrator');
// 超级管理员或管理员（deputy_admin）：账号级管理入口（成员/邀请/员工档案/薪资/审批人/公海规则）。
const isAdminLike = computed(
  () => isAdmin.value || currentUser.value?.crm_role === 'deputy_admin'
);
// 有效主管身份用后端派生的 crm_manager（覆盖副管理员/管理员兼任部门负责人）。
const isCrmManager = computed(
  () =>
    currentUser.value?.crm_manager === true ||
    currentUser.value?.crm_role === 'manager'
);
// 人事角色：组织架构/成员管理/绩效/员工档案入口（无 CRM 销售数据）。
const isCrmHr = computed(() => currentUser.value?.crm_role === 'hr');
const isMesStaff = computed(
  () => isAdminLike.value || (currentUser.value?.mes_roles || []).length > 0
);
// 采购审批人（按产品线配在采购单页）：不兼 MES 岗也要进得去采购单，否则批不了单。
const isMesPurchaseApprover = computed(
  () => currentUser.value?.mes_purchase_approver === true
);
// 财务：对账要看采购单和入库单（花了多少、货什么时候到的），但不进生产/BOM/供应商那些。
// 判的是 crm_finance 布尔列，不是 crm_role === 'finance'——生产上两位财务的 crm_role 是空的。
const isFinanceViewer = computed(() => currentUser.value?.crm_finance === true);
// MES 侧栏的分组壳（2026-10-23，用户：菜单太长太乱）。分组本身不是路由，只是个壳。
// 权限条件留在各自的叶子上，这里只负责两件事：
//   ① 被权限滤空的组整个丢掉——否则采购岗会看到一个点开是空的「仓库」；
//   ② activeOn 由子项自动汇总，不手写——手写一份迟早漏登记，进了页面整组不高亮。
const mesGroup = (name, label, children) =>
  children.length
    ? {
        name,
        label,
        icon: '',
        collapsible: true,
        defaultCollapsed: true,
        showTreeLine: true,
        activeOn: children.flatMap(c => c.activeOn || []),
        children,
      }
    : null;

// AI 助手是否对这个人开放（名单在「AI 设置」里配，见 Crm::AiSetting.agent_allowed?）
const canUseCrmAgent = computed(() => currentUser.value?.crm_agent === true);
// 能不能看物料成本（物料单价表、任务单上的单价、成本导出）。
// 口径在后端 AccountUser#can_view_material_cost?，这里只读它算好的标志，
// 别在前端重拼「财务 or 管理员 or 采购」——两边迟早对不上。
const canViewMaterialCost = computed(
  () => currentUser.value?.can_view_material_cost === true
);
// 备用金台账：财务/管理员管全部，部门负责人管本部门那本。
// 口径必须与后端一致——用组织架构的部门负责人（org_dept_leader），不能用 CRM 条线的
// crm_manager，否则会出现「侧栏看得到入口、点进去 403」。
const canSeePettyCash = computed(
  () =>
    isAdminLike.value ||
    currentUser.value?.crm_finance === true ||
    currentUser.value?.org_dept_leader === true
);
// 绩效板块按角色可见性（服务端按当前用户角色算好；管理员始终 true）。
const kpiSchemeVisible = computed(
  () => currentUser.value?.kpi_scheme_visible !== false
);
const kpiSheetVisible = computed(
  () => currentUser.value?.kpi_sheet_visible !== false
);
// 文档中心资料板块（仅当前用户可见的），进入文档系统时按需拉取一次。
const docSections = ref([]);
const fetchDocSections = async () => {
  try {
    const { data } = await DocSectionsAPI.get();
    docSections.value = data.payload || [];
  } catch {
    docSections.value = [];
  }
};
const { isCrmFinanceOnly } = useCrmFinanceOnly();

const CRM_DATA_MODULES = [
  'CRM Dashboards',
  'CRM Customers Group',
  'CRM Sales Flow',
  'CRM Mail Center',
  'CRM Knowledge',
];
// 「纯财务」（有 crm_finance、没有 crm_role）对账要看单，但客户资源/邮件/报价不该给。
// 只放行销售流程分组下的这两项，且后端是只读的（block_crm_finance_writes!）。
const FINANCE_ONLY_CRM_ITEMS = ['CRM Sales Orders', 'CRM PIs'];
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const hasAdvancedAssignment = computed(() => {
  return isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.ADVANCED_ASSIGNMENT
  );
});

const hasConversationUnreadCounts = computed(() => {
  return isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.CONVERSATION_UNREAD_COUNTS
  );
});

const fetchConversationUnreadCounts = ([currentAccountId, isEnabled]) => {
  if (!currentAccountId) return;

  if (!isEnabled) {
    store.dispatch('conversationUnreadCounts/clear');
    return;
  }

  store.dispatch('conversationUnreadCounts/get');
};

const fetchSidebarSortPreferences = ([currentAccountId, userId]) => {
  if (!currentAccountId || !userId) return;
  store.dispatch('sidebarSortPreferences/initialize');
};

const toggleShortcutModalFn = show => {
  if (show) {
    emit('openKeyShortcutModal');
  } else {
    emit('closeKeyShortcutModal');
  }
};

useSidebarKeyboardShortcuts(toggleShortcutModalFn);

const expandedItem = ref(null);

const setExpandedItem = name => {
  expandedItem.value = expandedItem.value === name ? null : name;
};

const {
  sidebarWidth,
  isCollapsed,
  setSidebarWidth,
  saveWidth,
  snapToCollapsed,
  snapToExpanded,
  COLLAPSED_THRESHOLD,
} = useSidebarResize();

// On mobile, sidebar is always expanded (flyout mode)
const isEffectivelyCollapsed = computed(
  () => !isMobile.value && isCollapsed.value
);

// Resize handle logic
const isResizing = ref(false);
const startX = ref(0);
const startWidth = ref(0);

provideSidebarContext({
  expandedItem,
  setExpandedItem,
  isCollapsed: isEffectivelyCollapsed,
  sidebarWidth,
  isResizing,
});

// Get clientX from mouse or touch event
const getClientX = event =>
  event.touches ? event.touches[0].clientX : event.clientX;

const onResizeStart = event => {
  isResizing.value = true;
  startX.value = getClientX(event);
  startWidth.value = sidebarWidth.value;
  Object.assign(document.body.style, {
    cursor: 'col-resize',
    userSelect: 'none',
  });
  // Prevent default to avoid scrolling on touch
  event.preventDefault();
};

const onResizeMove = event => {
  if (!isResizing.value) return;

  const delta = isRTL.value
    ? startX.value - getClientX(event)
    : getClientX(event) - startX.value;
  setSidebarWidth(startWidth.value + delta);
};

const onResizeEnd = () => {
  if (!isResizing.value) return;

  isResizing.value = false;
  Object.assign(document.body.style, { cursor: '', userSelect: '' });

  // Snap to collapsed state if below threshold
  if (sidebarWidth.value < COLLAPSED_THRESHOLD) {
    snapToCollapsed();
  } else {
    saveWidth();
  }
};

const onResizeHandleDoubleClick = () => {
  if (isCollapsed.value) snapToExpanded();
  else snapToCollapsed();
};

// Support both mouse and touch events
useEventListener(document, 'mousemove', onResizeMove);
useEventListener(document, 'mouseup', onResizeEnd);
useEventListener(document, 'touchmove', onResizeMove, { passive: false });
useEventListener(document, 'touchend', onResizeEnd);

const inboxes = useMapGetter('inboxes/getInboxes');
const labels = useMapGetter('labels/getLabelsOnSidebar');

// 侧栏「客户来源」分组：来源选项来自「客户设置」，角标是各来源下的会话数。
const { sourceOptions, load: loadCrmOptions } = useCrmOptions();
const sourceTagCounts = ref({});
const fetchSourceTagCounts = async () => {
  try {
    const { data } = await ConversationSourceTagsAPI.counts();
    sourceTagCounts.value = data.payload || {};
  } catch {
    sourceTagCounts.value = {};
  }
};
const allUnreadCount = useMapGetter(
  'conversationUnreadCounts/getAllUnreadCount'
);
const getInboxUnreadCount = useMapGetter(
  'conversationUnreadCounts/getInboxUnreadCount'
);
const getLabelUnreadCount = useMapGetter(
  'conversationUnreadCounts/getLabelUnreadCount'
);
const getTeamUnreadCount = useMapGetter(
  'conversationUnreadCounts/getTeamUnreadCount'
);
const teams = useMapGetter('teams/getMyTeams');
const contactCustomViews = useMapGetter('customViews/getContactCustomViews');
// 会话文件夹分组已隐藏（见下方注释），这个 getter 暂时没人读。
// const conversationCustomViews = useMapGetter(
//   'customViews/getConversationCustomViews'
// );
const getSidebarSectionSort = useMapGetter(
  'sidebarSortPreferences/getSectionSort'
);

// 流失预警角标：可见范围内超期未互动的成交客户数（实时计算，无存储）。
const mesNotificationsStore = useMesNotificationsStore();
const mesTodoCount = ref(0);
// 角标口径走后端的 todo_count，不再自己把四个 inbox 的**长度**加起来。
//
// 原来那种加法把 inbox 的全部条数都算成「待我处理」，可 inbox 里还包含
// 已下完采购、正在等料的单（面板上它们归「进行中」）——于是订单明明已经流转到
// 下发采购，角标还一直挂着「待我处理」，点多少次都不掉（反馈点名）。
// todo_count 里 actionable_inbox_count 按三态只算「待下单 / 逾期催货」，
// 口径和待办面板一致，顺带也把出库与采购审批算进去，少发三个请求。
const fetchMesTodoCount = async () => {
  try {
    const { data } = await MesProductionOrderAPI.todoCount();
    mesTodoCount.value = data?.total || 0;
  } catch {
    mesTodoCount.value = 0;
  }
};

// 「我的工作台」并进站内通知后，这个角标代表「要我动手的事」：
// 实时待办 + 未读的退回/驳回；纯知会（进展）不计，否则角标虚高、看久了就不信它了。
const REJECTED_KINDS = [
  'approval_rejected',
  'po_approval_rejected',
  'shipment_rejected',
  'document_returned',
  'stage_returned',
];
// ⚠️ 'sales_return_pending' 不能放进上面这个表。
// 10.19 加过一次（当时统一待办还不认这类，不加角标就不跳）；后来 Mes::TodoList
// 补上了 sales_return_confirm，同一张单于是被数两遍——todo_count 里一遍、
// 未读通知里再一遍。2026-10-26 实例：Vivien Yu 名下 3 张退回待确认，
// 角标显示 6，三张单两边各算一次。
// 这类待办现在由 todo_count 负责，角标照样会跳。
const mesUnreadCount = computed(() =>
  Number(mesNotificationsStore.getUnreadCount || 0)
);
const mesActionCount = computed(
  () =>
    mesTodoCount.value +
    (mesNotificationsStore.getRecords || []).filter(
      n => !n.readAt && REJECTED_KINDS.includes(n.kind)
    ).length
);
// 定制报价角标：待我报价的单数。业务员把单子交上来，主管不进这个页面就不知道，
// 单子能挂好几天——和会话那个点一个道理，要在侧栏就能看见。
const quoteRequestTodoCount = ref(0);
const fetchQuoteRequestTodoCount = async () => {
  try {
    const { data } = await CrmQuoteRequestAPI.pendingCount();
    quoteRequestTodoCount.value = data.count || 0;
  } catch {
    quoteRequestTodoCount.value = 0;
  }
};

// 绩效考核角标：等我动手的考核表数。考核是月度节奏，人不会天天进那个页面看，
// 不摆角标就只能靠每周催办——实查有张表在「待填报」挂了 81 天。
const kpiSheetTodoCount = ref(0);
const fetchKpiSheetTodoCount = async () => {
  try {
    const { data } = await CrmKpiSheetAPI.pendingCount();
    kpiSheetTodoCount.value = data.count || 0;
  } catch {
    kpiSheetTodoCount.value = 0;
  }
};

// 销售订单审核角标：待我审的单数。和定制报价那个同一个道理——单子开出来主管
// 不进页面就不知道，只能等业务员来问（用户 2026-10-22 原话：「不是业务问我我根本不知道」）。
const salesOrderTodoCount = ref(0);
const fetchSalesOrderTodoCount = async () => {
  try {
    const { data } = await CrmSalesOrderAPI.pendingCount();
    salesOrderTodoCount.value = data.count || 0;
  } catch {
    salesOrderTodoCount.value = 0;
  }
};

const churnRiskCount = ref(0);
const fetchChurnRiskCount = async () => {
  try {
    const { data } = await CrmCustomerAPI.churnRiskCount();
    churnRiskCount.value = data.count || 0;
  } catch {
    churnRiskCount.value = 0;
  }
};
// 日程角标：今日到期 + 已逾期未完成的日程数（含客户跟进提醒）。
const scheduleTodoCount = ref(0);
const fetchScheduleTodoCount = async () => {
  if (!accountId.value) return;
  try {
    const { data } = await ScheduleAPI.pendingCount(accountId.value);
    scheduleTodoCount.value = data.count || 0;
  } catch {
    scheduleTodoCount.value = 0;
  }
};

// 团队协同角标：内部 IM 全局未读消息数；实时事件到达时增量刷新。
const teamChatUnread = ref(0);
const fetchTeamChatUnread = async () => {
  if (!accountId.value) return;
  try {
    const { data } = await ChatConversationAPI.unreadTotal();
    teamChatUnread.value = data.count || 0;
  } catch {
    teamChatUnread.value = 0;
  }
};
// 会话角标：未处理数挂在「未处理」上，「该动手」的总数挂在「会话」分组上——
// 分组收起来时也看得见有事要办（和 MES 站内通知那个黄角标一个样）。
const unattendedCount = ref(0);
const conversationAttentionCount = ref(0);
const fetchConversationAttention = async () => {
  try {
    const { data } = await ConversationAPI.getAttentionCounts();
    unattendedCount.value = data?.unattended || 0;
    conversationAttentionCount.value = data?.needs_attention || 0;
  } catch {
    unattendedCount.value = 0;
    conversationAttentionCount.value = 0;
  }
};

// 团队协同（内部 IM）的新消息：非当前用户发的才计数。
// 这里原来还顺手重取了会话角标，但 CHAT_MESSAGE_CREATED 是内部 IM 的事件，
// 跟客户会话没关系——回复客户时它根本不触发，角标要刷新页面才变。
// 会话角标改挂 CONVERSATION_ATTENTION_MAY_CHANGE（见下）。
const onChatRealtime = data => {
  if (data?.sender_id === currentUserId.value) return;
  fetchTeamChatUnread();
};

// 会话一有动静就重算角标。消息是逐条推的，连着来十条没必要请求十次，收口到 1.5 秒一次。
let attentionTimer = null;
const refreshConversationAttention = () => {
  clearTimeout(attentionTimer);
  attentionTimer = setTimeout(fetchConversationAttention, 1500);
};

// CRM 角标/筛选项只对有 CRM 权限的人拉。
//
// 侧栏是全局的，原来对所有人无条件调这三个 CRM 接口（客户来源选项 /
// 来源会话计数 / 流失预警角标）。仓管、车间、采购这些没有 crm_role 的岗位
// 每次进系统都被 403，全局拦截器弹出「无权访问 CRM」——仓管因此以为
// 自己权限被收了（其实 MES 一直是好的）。
//
// 这里用严格判定而不是上面的 canAccessCrm：后者是「!== false」，
// currentUser 还没加载完时算 true，会赶在用户信息到位前把请求发出去、照样 403。
// 所以只认明确的 true，并用 watch 等它到位（immediate 覆盖「进来就已登录」）。
const crmSidebarDataAllowed = computed(
  () => currentUser.value?.can_access_crm === true
);

watch(
  crmSidebarDataAllowed,
  allowed => {
    if (!allowed) return;
    loadCrmOptions('customer_source');
    fetchSourceTagCounts();
    fetchChurnRiskCount();
    fetchQuoteRequestTodoCount();
    fetchSalesOrderTodoCount();
    fetchKpiSheetTodoCount();
  },
  { immediate: true }
);

onMounted(() => {
  store.dispatch('labels/get');
  store.dispatch('inboxes/get');
  store.dispatch('notifications/unReadCount');
  store.dispatch('teams/get');
  store.dispatch('attributes/get');
  // 会话文件夹分组已隐藏，侧栏不再需要这份数据（客户那边的 contact 视图照旧拉）。
  // store.dispatch('customViews/get', 'conversation');
  store.dispatch('customViews/get', 'contact');
  mesNotificationsStore.fetchUnreadCount();
  fetchMesTodoCount();
  fetchConversationAttention();
  fetchScheduleTodoCount();
  fetchTeamChatUnread();
  emitter.on('CHAT_MESSAGE_CREATED', onChatRealtime);
  // 协同页读完消息后广播，用于即时清角标。
  emitter.on('CHAT_UNREAD_CHANGED', fetchTeamChatUnread);
  // 订单页审完/驳回后广播，不用等下次进系统才掉角标。
  emitter.on('SALES_ORDER_APPROVAL_CHANGED', fetchSalesOrderTodoCount);
  // 新消息（含自己发出的回复）
  emitter.on('CONVERSATION_ATTENTION_MAY_CHANGE', refreshConversationAttention);
  // 会话新建/状态变更/转派——actionCable 已有的广播，顺带用上
  emitter.on('fetch_conversation_stats', refreshConversationAttention);
});
onBeforeUnmount(() => {
  clearTimeout(attentionTimer);
  emitter.off('CHAT_MESSAGE_CREATED', onChatRealtime);
  emitter.off('CHAT_UNREAD_CHANGED', fetchTeamChatUnread);
  emitter.off('SALES_ORDER_APPROVAL_CHANGED', fetchSalesOrderTodoCount);
  emitter.off(
    'CONVERSATION_ATTENTION_MAY_CHANGE',
    refreshConversationAttention
  );
  emitter.off('fetch_conversation_stats', refreshConversationAttention);
});

watch([accountId, hasConversationUnreadCounts], fetchConversationUnreadCounts, {
  immediate: true,
});

watch([accountId, currentUserId], fetchSidebarSortPreferences, {
  immediate: true,
});

const getSortOptionsForSection = section =>
  getSidebarSortOptions(section, {
    hasUnreadCounts: hasConversationUnreadCounts.value,
  });

const getSortForSection = section =>
  resolveSidebarSort(section, getSidebarSectionSort.value(section), {
    hasUnreadCounts: hasConversationUnreadCounts.value,
  });

const updateSortPreference = (section, sortBy) => {
  store.dispatch('sidebarSortPreferences/setSectionSort', {
    section,
    sortBy,
  });
};

const buildSortConfig = section => ({
  sortOptions: getSortOptionsForSection(section),
  activeSort: getSortForSection(section),
  onSortChange: sortBy => updateSortPreference(section, sortBy),
});

// 文件夹分组同日隐藏（见下方注释），这份排序暂时没人用；分组放回来时一起解注释。
// const sortedFolders = computed(() =>
//   sortSidebarItems(conversationCustomViews.value, {
//     sortBy: getSortForSection(SIDEBAR_SORT_SECTIONS.FOLDERS),
//     labelKey: view => view.name,
//   })
// );

const sortedTeams = computed(() =>
  sortSidebarItems(teams.value, {
    sortBy: getSortForSection(SIDEBAR_SORT_SECTIONS.TEAMS),
    labelKey: team => team.name,
    unreadCountKey: team => getTeamUnreadCount.value(team.id),
  })
);

const sortedInboxes = computed(() =>
  sortSidebarItems(inboxes.value, {
    sortBy: getSortForSection(SIDEBAR_SORT_SECTIONS.CHANNELS),
    labelKey: inbox => inbox.name,
    unreadCountKey: inbox => getInboxUnreadCount.value(inbox.id),
  })
);

const sortedLabels = computed(() =>
  sortSidebarItems(labels.value, {
    sortBy: getSortForSection(SIDEBAR_SORT_SECTIONS.LABELS),
    labelKey: label => label.title,
    unreadCountKey: label => getLabelUnreadCount.value(label.id),
  })
);

// 频道叶子节点(单个收件箱)。
const buildInboxLeaf = inbox => ({
  name: `${inbox.name}-${inbox.id}`,
  label: inbox.name,
  badgeCount: getInboxUnreadCount.value(inbox.id),
  icon: h(ChannelIcon, { inbox, class: 'size-[16px]' }),
  to: accountScopedRoute('inbox_dashboard', { inbox_id: inbox.id }),
  component: leafProps =>
    h(ChannelLeaf, {
      label: leafProps.label,
      active: leafProps.active,
      inbox,
      badgeCount: leafProps.badgeCount,
    }),
});

// 「频道」子节点:普通渠道平铺。业务员个人 WhatsApp 号多且杂,单独拆成与「频道」平级的
// 可折叠分组(见下 whatsappMenuItems)避免刷屏——不能作为「频道」的子分组嵌套,
// 因为侧栏 SidebarSubGroup 不支持三层嵌套(会把子分组当无路由叶子,点了没反应)。
const channelChildren = computed(() =>
  sortedInboxes.value
    .filter(inbox => inbox.channel_type !== 'Channel::WhatsappWeb')
    .map(buildInboxLeaf)
);

// 个人 WhatsApp 号:每个号一个收件箱叶子。
// 管理员看得到全公司的号,所以按「当前用户是不是该收件箱成员」(后端给的 is_member)
// 拆成「我的」和「业务员的」两组——老板自己的号别埋在十几个业务员的号里。
// 业务员只看得到自己的号,拆出来另一组是空的,这时按老样子只出一组。
// 待扫码的号不列进来：那是还没绑成的空壳，点进去什么都没有，还会把
// 「WhatsApp (1)」显示成「(2)」（2026-11-08 用户反馈，绑第二个号时撞上的）。
//
// ⚠️ **只藏 qr，不藏 disconnected。** 掉线的号（手机关机、临时断网）是绑过的，
// 底下压着历史会话——一并藏掉的话，业务员的聊天记录会凭空消失。
// 状态由后端单独给（见 _inbox.json.jbuilder），不读 provider_config——那个只给管理员，
// 业务员读不到就过滤不了。
const whatsappInboxes = computed(() =>
  sortedInboxes.value.filter(
    inbox =>
      inbox.channel_type === 'Channel::WhatsappWeb' &&
      inbox.connection_status !== 'qr'
  )
);
const myWhatsappLeaves = computed(() =>
  whatsappInboxes.value.filter(inbox => inbox.is_member).map(buildInboxLeaf)
);
const othersWhatsappLeaves = computed(() =>
  whatsappInboxes.value.filter(inbox => !inbox.is_member).map(buildInboxLeaf)
);

const whatsappGroup = (name, label, leaves) => ({
  name,
  label: `${label} (${leaves.length})`,
  icon: 'i-ri-whatsapp-fill',
  activeOn: ['conversation_through_inbox'],
  collapsible: true,
  showTreeLine: true,
  children: leaves,
});

// 侧栏里的 WhatsApp 条目:只有自己的号时沿用原样(一个号直接平铺,套一层折叠纯属多余);
// 同时看得到别人的号(管理员)才分成「我的 WhatsApp」「业务员 WhatsApp」两组。
const whatsappMenuItems = computed(() => {
  const mine = myWhatsappLeaves.value;
  const others = othersWhatsappLeaves.value;
  if (!mine.length && !others.length) return [];

  if (!others.length) {
    if (mine.length === 1) return [mine[0]];
    return [whatsappGroup('WhatsAppChannels', 'WhatsApp', mine)];
  }
  if (!mine.length) {
    if (others.length === 1) return [others[0]];
    return [whatsappGroup('WhatsAppChannels', 'WhatsApp', others)];
  }
  return [
    whatsappGroup('MyWhatsAppChannels', '我的 WhatsApp', mine),
    whatsappGroup('TeamWhatsAppChannels', '业务员 WhatsApp', others),
  ];
});

const closeMobileSidebar = () => {
  if (!props.isMobileSidebarOpen) return;
  emit('closeMobileSidebar');
};

const newReportRoutes = () => [
  {
    name: 'Reports Agent',
    label: t('SIDEBAR.REPORTS_AGENT'),
    to: accountScopedRoute('agent_reports_index'),
    activeOn: ['agent_reports_show'],
  },
  {
    name: 'Reports Label',
    label: t('SIDEBAR.REPORTS_LABEL'),
    to: accountScopedRoute('label_reports_index'),
  },
  {
    name: 'Reports Inbox',
    label: t('SIDEBAR.REPORTS_INBOX'),
    to: accountScopedRoute('inbox_reports_index'),
    activeOn: ['inbox_reports_show'],
  },
  {
    name: 'Reports Team',
    label: t('SIDEBAR.REPORTS_TEAM'),
    to: accountScopedRoute('team_reports_index'),
    activeOn: ['team_reports_show'],
  },
];

const reportRoutes = computed(() => newReportRoutes());

// 隐藏的原生客服模块：我的收件箱 / 联系人 / 报告 / 活动 / 帮助中心 / 公司。
// 「会话」（Conversation）已恢复显示，归 CRM 模块（2026-07-16 用户要求）。
const HIDDEN_NATIVE_MODULES = [
  'Inbox',
  'Contacts',
  'Companies',
  'Reports',
  'Campaigns',
  'Portals',
];

const menuItems = computed(() => {
  return (
    [
      {
        name: 'CRM Workspace',
        label: t('SIDEBAR.CRM_WORKSPACE'),
        icon: 'i-lucide-layout-dashboard',
        to: accountScopedRoute('crm_workspace_index'),
        activeOn: ['crm_workspace_index'],
      },
      // AI 助手：天天用的工具，放主功能区第二位，不埋进设置里。
      // 只对放开了名单的人显示（后端 Crm::AiSetting.agent_allowed? 再判一次）。
      ...(canUseCrmAgent.value
        ? [
            {
              name: 'CRM Agent',
              label: 'AI 助手',
              icon: 'i-lucide-sparkles',
              to: accountScopedRoute('crm_agent_index'),
              activeOn: ['crm_agent_index'],
            },
          ]
        : []),
      {
        name: 'Inbox',
        label: t('SIDEBAR.INBOX'),
        icon: 'i-lucide-inbox',
        to: accountScopedRoute('inbox_view'),
        activeOn: ['inbox_view', 'inbox_view_conversation'],
        getterKeys: {
          count: 'notifications/getUnreadCount',
        },
      },
      {
        name: 'CRM Dashboards',
        label: t('SIDEBAR.CRM_G_DASHBOARDS'),
        icon: h('span', { 'data-sidebar-icon': 'crm-dashboards' }, [
          h('span', { class: 'i-lucide-layout-dashboard block size-full' }),
          h('span', {
            class: 'i-lucide-chart-no-axes-combined hidden size-full',
          }),
        ]),
        activeOn: [
          'crm_dashboard_index',
          'crm_team_dashboard_index',
          'crm_my_target_index',
        ],
        children: [
          // 外贸销售部数据看板对所有 CRM 成员开放（用户 2026-10-29 定）。
          // 原先对业务员隐藏，后端 StatsController#company_scope_allowed? 也一并放开了——
          // 只改侧栏不改后端的话，菜单出来了、数据还是个人口径。
          {
            name: 'CRM Company Dashboard',
            label: t('SIDEBAR.CRM_DASH_COMPANY'),
            to: accountScopedRoute('crm_dashboard_index'),
            activeOn: ['crm_dashboard_index'],
          },
          {
            name: 'CRM Team Dashboard',
            label: t('SIDEBAR.CRM_DASH_TEAM'),
            to: accountScopedRoute('crm_team_dashboard_index'),
            activeOn: ['crm_team_dashboard_index'],
          },
          {
            name: 'CRM Personal Dashboard',
            label: t('SIDEBAR.CRM_DASH_MINE'),
            to: accountScopedRoute(
              'crm_dashboard_index',
              {},
              { scope: 'mine' }
            ),
          },
          {
            name: 'CRM My Targets',
            label: t('SIDEBAR.CRM_MY_TARGETS'),
            to: accountScopedRoute('crm_my_target_index'),
            activeOn: ['crm_my_target_index'],
          },
        ],
      },
      {
        name: 'Conversation',
        // CRM WhatsApp 入口，保留原有会话分组和未读数量。
        label: t('SIDEBAR.CRM_G_MESSAGES'),
        icon: 'i-ri-whatsapp-line',
        badgeCount: conversationAttentionCount.value,
        children: [
          {
            name: 'All',
            label: t('SIDEBAR.CRM_ALL_MESSAGES'),
            icon: 'i-lucide-inbox',
            badgeCount: allUnreadCount.value,
            activeOn: ['inbox_conversation'],
            to: accountScopedRoute('home'),
          },
          // 2026-10-02 隐藏「我的客户」与「更多视图」整组（提及/参与者/待跟进/高意向/未建档）。
          // 生产实测 178 条会话里 177 条的联系人没挂客户档案,而这几个视图全是顺着
          // 联系人→客户档案→归属人 这条链筛的,链断着所以常年是空的:
          // 我的客户 1 条、待跟进 0、高意向 0、提及 0。不是没人用,是没东西可显示。
          // 「未处理」留着——38 条确实没人回过的询盘,是这里唯一还在干活的分诊入口。
          // 等会话和客户档案打通(比如 WhatsApp 来的号自动建档),把下面这段放回来即可。
          // {
          //   name: 'CRM Mine',
          //   label: '我的客户',
          //   icon: 'i-lucide-user-round-cog',
          //   activeOn: ['conversation_through_crm_mine'],
          //   to: accountScopedRoute('conversation_crm_mine'),
          // },
          {
            name: 'Unattended',
            activeOn: ['conversation_through_unattended'],
            label: t('SIDEBAR.UNATTENDED_CONVERSATIONS'),
            icon: 'i-lucide-clock-alert',
            badgeCount: unattendedCount.value,
            to: accountScopedRoute('conversation_unattended'),
          },
          // {
          //   name: 'MoreViews',
          //   label: '更多视图',
          //   icon: 'i-lucide-list-filter',
          //   collapsible: true,
          //   defaultCollapsed: true,
          //   showTreeLine: true,
          //   children: [
          //     { name: 'Mentions', label: t('SIDEBAR.MENTIONED_CONVERSATIONS'),
          //       icon: 'i-lucide-at-sign', activeOn: ['conversation_through_mentions'],
          //       to: accountScopedRoute('conversation_mentions') },
          //     { name: 'Participating', label: t('SIDEBAR.PARTICIPATING_CONVERSATIONS'),
          //       icon: 'i-lucide-user-round-check', activeOn: ['conversation_through_participating'],
          //       to: accountScopedRoute('conversation_participating') },
          //     { name: 'CRM Overdue', label: '待跟进', icon: 'i-lucide-alarm-clock',
          //       activeOn: ['conversation_through_crm_overdue'],
          //       to: accountScopedRoute('conversation_crm_overdue') },
          //     { name: 'CRM Hot', label: '高意向', icon: 'i-lucide-flame',
          //       activeOn: ['conversation_through_crm_hot'],
          //       to: accountScopedRoute('conversation_crm_hot') },
          //     { name: 'CRM Unfiled', label: '未建档', icon: 'i-lucide-user-round-plus',
          //       activeOn: ['conversation_through_crm_unfiled'],
          //       to: accountScopedRoute('conversation_crm_unfiled') },
          //   ],
          // },
          // 2026-10-03 隐藏「文件夹」。它装的就是「高级过滤存下来的结果」，
          // 而高级过滤同日已隐藏（生产保存过的筛选 0 条），这组永远是空的，
          // 点进去只会扑空。过滤恢复时把这段一起放回来。
          // {
          //   name: 'Folders',
          //   label: t('SIDEBAR.CUSTOM_VIEWS_FOLDER'),
          //   icon: 'i-lucide-folder',
          //   activeOn: ['conversations_through_folders'],
          //   ...buildSortConfig(SIDEBAR_SORT_SECTIONS.FOLDERS),
          //   collapsible: true,
          //   showTreeLine: true,
          //   children: sortedFolders.value.map(view => ({
          //     name: `${view.name}-${view.id}`,
          //     label: view.name,
          //     to: accountScopedRoute('folder_conversations', { id: view.id }),
          //   })),
          // },
          {
            name: 'Teams',
            label: t('SIDEBAR.TEAMS'),
            icon: 'i-lucide-users',
            activeOn: ['conversations_through_team'],
            ...buildSortConfig(SIDEBAR_SORT_SECTIONS.TEAMS),
            collapsible: true,
            showTreeLine: true,
            children: sortedTeams.value.map(team => ({
              name: `${team.name}-${team.id}`,
              label: team.name,
              badgeCount: getTeamUnreadCount.value(team.id),
              to: accountScopedRoute('team_conversations', { teamId: team.id }),
            })),
          },
          {
            name: 'Channels',
            label: t('SIDEBAR.CHANNELS'),
            icon: 'i-lucide-mailbox',
            activeOn: ['conversation_through_inbox'],
            ...buildSortConfig(SIDEBAR_SORT_SECTIONS.CHANNELS),
            collapsible: true,
            showTreeLine: true,
            children: channelChildren.value,
          },
          // 与「频道」平级的独立 WhatsApp 条目(见 whatsappMenuItems)。
          ...whatsappMenuItems.value,
          {
            name: 'CrmSource',
            label: '客户来源',
            icon: 'i-lucide-git-branch',
            activeOn: ['conversation_through_crm_source'],
            collapsible: true,
            showTreeLine: true,
            children: sourceOptions.value.map(opt => ({
              name: `crm-source-${opt.value}`,
              // 二级项在下拉里带「  └ 」缩进前缀，侧栏不需要。
              label: opt.label.replace(/^\s*└\s*/, ''),
              badgeCount: sourceTagCounts.value[opt.value] || 0,
              icon: 'i-lucide-tag',
              to: accountScopedRoute('conversation_crm_source', {
                sourceCode: opt.value,
              }),
            })),
          },
          {
            name: 'Labels',
            label: t('SIDEBAR.LABELS'),
            icon: 'i-lucide-tag',
            activeOn: ['conversations_through_label'],
            ...buildSortConfig(SIDEBAR_SORT_SECTIONS.LABELS),
            collapsible: true,
            showTreeLine: true,
            children: sortedLabels.value.map(label => ({
              name: `${label.title}-${label.id}`,
              label: label.title,
              badgeCount: getLabelUnreadCount.value(label.id),
              icon: h('span', {
                class: `size-[8px] rounded-sm`,
                style: { backgroundColor: label.color },
              }),
              to: accountScopedRoute('label_conversations', {
                label: label.title,
              }),
            })),
          },
        ],
      },
      {
        name: 'Captain',
        icon: 'i-woot-captain',
        label: t('SIDEBAR.CAPTAIN'),
        activeOn: ['captain_assistants_create_index'],
        children: [
          {
            name: 'FAQs',
            label: t('SIDEBAR.CAPTAIN_RESPONSES'),
            activeOn: [
              'captain_assistants_responses_index',
              'captain_assistants_responses_pending',
            ],
            to: accountScopedRoute('captain_assistants_index', {
              navigationPath: 'captain_assistants_responses_index',
            }),
          },
          {
            name: 'Documents',
            label: t('SIDEBAR.CAPTAIN_DOCUMENTS'),
            activeOn: ['captain_assistants_documents_index'],
            to: accountScopedRoute('captain_assistants_index', {
              navigationPath: 'captain_assistants_documents_index',
            }),
          },
          {
            name: 'Scenarios',
            label: t('SIDEBAR.CAPTAIN_SCENARIOS'),
            activeOn: ['captain_assistants_scenarios_index'],
            to: accountScopedRoute('captain_assistants_index', {
              navigationPath: 'captain_assistants_scenarios_index',
            }),
          },
          {
            name: 'Playground',
            label: t('SIDEBAR.CAPTAIN_PLAYGROUND'),
            activeOn: ['captain_assistants_playground_index'],
            to: accountScopedRoute('captain_assistants_index', {
              navigationPath: 'captain_assistants_playground_index',
            }),
          },
          {
            name: 'Inboxes',
            label: t('SIDEBAR.CAPTAIN_INBOXES'),
            activeOn: ['captain_assistants_inboxes_index'],
            to: accountScopedRoute('captain_assistants_index', {
              navigationPath: 'captain_assistants_inboxes_index',
            }),
          },
          {
            name: 'Tools',
            label: t('SIDEBAR.CAPTAIN_TOOLS'),
            activeOn: ['captain_tools_index'],
            to: accountScopedRoute('captain_assistants_index', {
              navigationPath: 'captain_tools_index',
            }),
          },
          {
            name: 'Settings',
            label: t('SIDEBAR.CAPTAIN_SETTINGS'),
            activeOn: [
              'captain_assistants_settings_index',
              'captain_assistants_guidelines_index',
              'captain_assistants_guardrails_index',
            ],
            to: accountScopedRoute('captain_assistants_index', {
              navigationPath: 'captain_assistants_settings_index',
            }),
          },
        ],
      },
      {
        name: 'Contacts',
        label: t('SIDEBAR.CONTACTS'),
        icon: 'i-lucide-contact',
        children: [
          {
            name: 'All Contacts',
            label: t('SIDEBAR.ALL_CONTACTS'),
            to: accountScopedRoute(
              'contacts_dashboard_index',
              {},
              { page: 1, search: undefined }
            ),
            activeOn: ['contacts_dashboard_index', 'contacts_edit'],
          },
          {
            name: 'Active',
            label: t('SIDEBAR.ACTIVE'),
            to: accountScopedRoute('contacts_dashboard_active'),
            activeOn: ['contacts_dashboard_active'],
          },
          {
            name: 'Segments',
            icon: 'i-lucide-group',
            label: t('SIDEBAR.CUSTOM_VIEWS_SEGMENTS'),
            collapsible: true,
            showTreeLine: true,
            children: contactCustomViews.value.map(view => ({
              name: `${view.name}-${view.id}`,
              label: view.name,
              to: accountScopedRoute(
                'contacts_dashboard_segments_index',
                { segmentId: view.id },
                { page: 1 }
              ),
              activeOn: [
                'contacts_dashboard_segments_index',
                'contacts_edit_segment',
              ],
            })),
          },
          {
            name: 'Tagged With',
            icon: 'i-lucide-tag',
            label: t('SIDEBAR.TAGGED_WITH'),
            collapsible: true,
            showTreeLine: true,
            children: labels.value.map(label => ({
              name: `${label.title}-${label.id}`,
              label: label.title,
              icon: h('span', {
                class: `size-[8px] rounded-sm`,
                style: { backgroundColor: label.color },
              }),
              to: accountScopedRoute(
                'contacts_dashboard_labels_index',
                { label: label.title },
                { page: 1, search: undefined }
              ),
              activeOn: [
                'contacts_dashboard_labels_index',
                'contacts_edit_label',
              ],
            })),
          },
        ],
      },
      {
        name: 'Companies',
        label: t('SIDEBAR.COMPANIES'),
        icon: 'i-lucide-building-2',
        children: [
          {
            name: 'All Companies',
            label: t('SIDEBAR.ALL_COMPANIES'),
            to: accountScopedRoute(
              'companies_dashboard_index',
              {},
              { page: 1, search: undefined }
            ),
            activeOn: ['companies_dashboard_index', 'companies_dashboard_show'],
          },
        ],
      },
      // ── TikTok 板块（店铺经营，独立模块）。看板/日报/利润=有权成员可见（后端按部门收口）；
      //    店铺设置/部门管理=仅管理员/副管理员。整组可见性走 canAccessTiktok。──
      {
        name: 'TikTok',
        label: t('SIDEBAR.TIKTOK'),
        icon: 'i-lucide-shopping-bag',
        activeOn: [
          'tiktok_today_index',
          'tiktok_dashboard_index',
          'tiktok_sales_records_index',
          'tiktok_profit_index',
          'tiktok_shop_settings_index',
          'tiktok_departments_index',
        ],
        children: [
          {
            name: 'TikTok Today',
            label: t('SIDEBAR.TIKTOK_TODAY'),
            to: accountScopedRoute('tiktok_today_index'),
            activeOn: ['tiktok_today_index'],
          },
          {
            name: 'TikTok Dashboard',
            label: t('SIDEBAR.TIKTOK_DASHBOARD'),
            to: accountScopedRoute('tiktok_dashboard_index'),
            activeOn: ['tiktok_dashboard_index'],
          },
          {
            name: 'TikTok Sales Records',
            label: t('SIDEBAR.TIKTOK_SALES_RECORDS'),
            to: accountScopedRoute('tiktok_sales_records_index'),
            activeOn: ['tiktok_sales_records_index'],
          },
          ...(tiktokCanViewProfit.value
            ? [
                {
                  name: 'TikTok Profit',
                  label: t('SIDEBAR.TIKTOK_PROFIT'),
                  to: accountScopedRoute('tiktok_profit_index'),
                  activeOn: ['tiktok_profit_index'],
                },
                {
                  name: 'TikTok Expenses',
                  label: t('SIDEBAR.TIKTOK_EXPENSES'),
                  to: accountScopedRoute('tiktok_expenses_index'),
                  activeOn: ['tiktok_expenses_index'],
                },
                {
                  name: 'TikTok Assets',
                  label: t('SIDEBAR.TIKTOK_ASSETS'),
                  to: accountScopedRoute('tiktok_assets_index'),
                  activeOn: ['tiktok_assets_index'],
                },
              ]
            : []),
          ...(tiktokCanCreateShop.value
            ? [
                {
                  name: 'TikTok Shop Settings',
                  label: t('SIDEBAR.TIKTOK_SHOP_SETTINGS'),
                  to: accountScopedRoute('tiktok_shop_settings_index'),
                  activeOn: ['tiktok_shop_settings_index'],
                },
              ]
            : []),
          ...(tiktokCanManage.value
            ? [
                {
                  name: 'TikTok Departments',
                  label: t('SIDEBAR.TIKTOK_DEPARTMENTS'),
                  to: accountScopedRoute('tiktok_departments_index'),
                  activeOn: ['tiktok_departments_index'],
                },
              ]
            : []),
        ],
      },
      // ── Wintouch-CRM 五分区（对齐 Twenty 侧栏结构）──
      {
        name: 'CRM Mail Center',
        label: t('SIDEBAR.CRM_G_MAIL'),
        icon: 'i-lucide-mail',
        activeOn: [
          'crm_emails_index',
          'crm_mail_accounts_index',
          'crm_email_templates_index',
        ],
        children: [
          {
            name: 'CRM Read Emails',
            label: t('SIDEBAR.CRM_READ_EMAILS'),
            to: accountScopedRoute('crm_emails_index'),
            activeOn: ['crm_emails_index'],
          },
          {
            name: 'CRM Email Templates',
            label: t('SIDEBAR.CRM_EMAIL_TEMPLATES'),
            to: accountScopedRoute('crm_email_templates_index'),
            activeOn: ['crm_email_templates_index'],
          },
          {
            name: 'CRM Mail Accounts',
            label: t('SIDEBAR.CRM_MAIL_ACCOUNTS'),
            to: accountScopedRoute('crm_mail_accounts_index'),
            activeOn: ['crm_mail_accounts_index'],
          },
        ],
      },
      {
        name: 'CRM Customers Group',
        label: t('SIDEBAR.CRM_G_CUSTOMERS'),
        icon: 'i-lucide-users',
        activeOn: [
          'crm_lead_center_index',
          'crm_customers_index',
          'crm_customer_intake_index',
          'crm_customer_dupes_index',
          // 展会名片（crm_business_cards_index）**故意不在侧栏挂入口**：
          // 拍名片是展会现场站着用手机干的事，网页端摆个入口只会让人以为电脑上也能拍。
          // 按产品决定只从 App 进（App 是独立前端，走同一套 /crm/business_cards 接口）。
          // 路由和页面都还在，直接敲 URL 可进——核对数据时用得上。
          'crm_ai_background_check_index',
        ],
        children: [
          // 放在组内第一个：获客是上游——先找到人，再建档，再跟进。
          {
            name: 'CRM Lead Center',
            label: t('SIDEBAR.CRM_LEAD_CENTER'),
            to: accountScopedRoute('crm_lead_center_index'),
            activeOn: ['crm_lead_center_index'],
          },
          {
            name: 'CRM Customer New',
            label: t('SIDEBAR.CRM_CUSTOMER_NEW'),
            to: accountScopedRoute('crm_customer_intake_index'),
            activeOn: ['crm_customer_intake_index'],
          },
          {
            name: 'CRM Private Customers',
            label: t('SIDEBAR.CRM_PRIVATE_CUSTOMERS'),
            to: accountScopedRoute(
              'crm_customers_index',
              {},
              { filter: 'private' }
            ),
            activeOn: ['crm_customers_index'],
          },
          {
            name: 'CRM Public Pool',
            label: t('SIDEBAR.CRM_PUBLIC_POOL'),
            to: accountScopedRoute(
              'crm_customers_index',
              {},
              { filter: 'public_pool' }
            ),
          },
          {
            name: 'CRM Churn Risk',
            label: t('SIDEBAR.CRM_CHURN_RISK'),
            badgeCount: churnRiskCount.value,
            // 判定口径不直观（业务常以为微信聊过就算互动），直接写在悬浮里。
            hint: '已成交的私海客户，超过「公海设置」里该客户分组的回收天数没有任何互动时在此提醒。互动算五样：跟进记录、往来邮件、下单、客户会话、商机动态。微信等系统外的沟通系统看不到，这类客户顺手记一条跟进即可消除提醒。这套天数同时也是公海自动回收的判据。',
            to: accountScopedRoute(
              'crm_customers_index',
              {},
              { filter: 'churn_risk' }
            ),
          },
          {
            name: 'CRM Customer Dupes',
            label: t('SIDEBAR.CRM_CUSTOMER_DUPES'),
            to: accountScopedRoute('crm_customer_dupes_index'),
            activeOn: ['crm_customer_dupes_index'],
          },
          {
            name: 'CRM AI Background Check',
            label: t('SIDEBAR.CRM_AI_BACKGROUND_CHECK'),
            to: accountScopedRoute('crm_ai_background_check_index'),
            activeOn: ['crm_ai_background_check_index'],
          },
        ],
      },
      {
        name: 'CRM Sales Flow',
        label: t('SIDEBAR.CRM_G_SALES_FLOW'),
        icon: 'i-lucide-funnel',
        activeOn: [
          'crm_funnel_index',
          'crm_price_lists_index',
          'crm_quotes_index',
          'crm_quote_requests_index',
          'crm_pis_index',
          'crm_sales_orders_index',
          'crm_opportunities_index',
        ],
        children: [
          {
            name: 'CRM Funnel',
            label: t('SIDEBAR.CRM_FUNNEL'),
            to: accountScopedRoute('crm_funnel_index'),
            // 商机列表已并入看板页（页内「列表」视图），直接访问列表 URL 也高亮此项。
            activeOn: ['crm_funnel_index', 'crm_opportunities_index'],
          },
          {
            name: 'CRM Price Lists',
            label: t('SIDEBAR.CRM_PRICE_LISTS'),
            to: accountScopedRoute('crm_price_lists_index'),
            activeOn: ['crm_price_lists_index'],
          },
          {
            // 定制报价：标准价目里没有的定制件，业务员填参数交给主管定价。
            // 排在报价单之前——先把定制件的价问出来，再开报价单给客户。
            name: 'CRM Quote Requests',
            label: '定制报价',
            badgeCount: quoteRequestTodoCount.value,
            hint: '有业务员提交的定制件等你报价时在此提醒；报完价角标自动消。',
            to: accountScopedRoute('crm_quote_requests_index'),
            activeOn: ['crm_quote_requests_index'],
          },
          {
            name: 'CRM Quotes',
            label: t('SIDEBAR.CRM_QUOTES'),
            to: accountScopedRoute('crm_quotes_index'),
            activeOn: ['crm_quotes_index'],
          },
          {
            name: 'CRM PIs',
            label: t('SIDEBAR.CRM_PIS'),
            to: accountScopedRoute('crm_pis_index'),
            activeOn: ['crm_pis_index'],
          },
          {
            name: 'CRM Sales Orders',
            label: t('SIDEBAR.CRM_SALES_ORDERS'),
            badgeCount: salesOrderTodoCount.value,
            hint: '有等你审核的销售订单时在此提醒；审完角标自动消。',
            // 角标有数时带上审批筛选：角标算的是「该我审的」，不带参数点进去是全部
            // 577 张单的列表，那 3 张在哪儿根本看不出来（和 MES 那个待办面板同病）。
            to: accountScopedRoute(
              'crm_sales_orders_index',
              {},
              salesOrderTodoCount.value > 0 ? { approval: 'PENDING' } : {}
            ),
            activeOn: ['crm_sales_orders_index'],
          },
          // 历史 PI 补录：把早年只传在客户「文件」页、没建销售订单的 PI 盘出来补建。
          // 全员可见——后端 pi_attachment_candidates 走 restrict_by_org，业务员只看得到
          // 自己名下客户的附件；补出来的订单和他自己手工建单是一回事，没绕开任何管控。
          {
            name: 'CRM PI Backfill',
            label: t('SIDEBAR.CRM_PI_BACKFILL'),
            to: accountScopedRoute('crm_pi_backfill_index'),
            activeOn: ['crm_pi_backfill_index'],
          },
          {
            name: 'CRM Orders No Customer',
            label: t('SIDEBAR.CRM_ORDERS_NO_CUSTOMER'),
            to: accountScopedRoute(
              'crm_sales_orders_index',
              {},
              { filter: 'no_customer' }
            ),
          },
        ],
      },
      {
        name: 'Finance ERP',
        label: '财务管理',
        icon: 'i-lucide-landmark',
        activeOn: [
          'erp_dashboard_index',
          'erp_accounts_index',
          'erp_vouchers_index',
          'erp_ledgers_index',
          'erp_reports_index',
          'erp_receivables_index',
          'erp_shipment_approvals_index',
          'erp_payables_index',
          'erp_cash_index',
          'erp_periods_index',
          'erp_fixed_assets_index',
          'erp_margin_index',
          'erp_bom_costs_index',
          'erp_expenses_index',
          'erp_notifications_index',
          'erp_settings_index',
        ],
        children: [
          {
            name: 'ERP Dashboard',
            label: '财务看板',
            to: accountScopedRoute('erp_dashboard_index'),
            activeOn: ['erp_dashboard_index'],
          },
          {
            name: 'ERP Accounts',
            label: '会计科目表',
            to: accountScopedRoute('erp_accounts_index'),
            activeOn: ['erp_accounts_index'],
          },
          {
            name: 'ERP Vouchers',
            label: '记账凭证',
            to: accountScopedRoute('erp_vouchers_index'),
            activeOn: ['erp_vouchers_index'],
          },
          {
            name: 'ERP Ledgers',
            label: '账簿',
            to: accountScopedRoute('erp_ledgers_index'),
            activeOn: ['erp_ledgers_index'],
          },
          {
            name: 'ERP Reports',
            label: '财务报表',
            to: accountScopedRoute('erp_reports_index'),
            activeOn: ['erp_reports_index'],
          },
          {
            name: 'ERP Receivables',
            label: '应收台账',
            to: accountScopedRoute('erp_receivables_index'),
            activeOn: ['erp_receivables_index'],
          },
          {
            name: 'ERP Shipment Approvals',
            label: '出库审核',
            to: accountScopedRoute('erp_shipment_approvals_index'),
            activeOn: ['erp_shipment_approvals_index'],
          },
          {
            name: 'ERP Payables',
            label: '应付台账',
            to: accountScopedRoute('erp_payables_index'),
            activeOn: ['erp_payables_index'],
          },
          {
            name: 'ERP Cash',
            label: '资金账户',
            to: accountScopedRoute('erp_cash_index'),
            activeOn: ['erp_cash_index'],
          },
          {
            name: 'ERP Margin',
            label: '成本毛利',
            to: accountScopedRoute('erp_margin_index'),
            activeOn: ['erp_margin_index'],
          },
          {
            name: 'ERP BOM Costs',
            label: 'BOM 成本表',
            to: accountScopedRoute('erp_bom_costs_index'),
            activeOn: ['erp_bom_costs_index'],
          },
          {
            name: 'ERP Expenses',
            label: '费用报销',
            to: accountScopedRoute('erp_expenses_index'),
            activeOn: ['erp_expenses_index'],
          },
          {
            name: 'ERP Fixed Assets',
            label: '固定资产',
            to: accountScopedRoute('erp_fixed_assets_index'),
            activeOn: ['erp_fixed_assets_index'],
          },
          {
            name: 'ERP Periods',
            label: '期末结账',
            to: accountScopedRoute('erp_periods_index'),
            activeOn: ['erp_periods_index'],
          },
          {
            name: 'ERP Notifications',
            label: '财务通知',
            to: accountScopedRoute('erp_notifications_index'),
            activeOn: ['erp_notifications_index'],
          },
          {
            name: 'ERP Settings',
            label: '财务设置',
            to: accountScopedRoute('erp_settings_index'),
            activeOn: ['erp_settings_index'],
          },
        ],
      },
      {
        name: 'MES Production',
        label: t('SIDEBAR.MES_G_PRODUCTION'),
        icon: 'i-lucide-factory',
        activeOn: [
          'mes_dashboard_index',
          'mes_pipeline_index',
          'mes_production_orders_index',
          'mes_boms_index',
          'mes_products_index',
          'mes_material_prices_index',
          'mes_purchase_orders_index',
          'mes_purchase_requisitions_index',
          'mes_suppliers_index',
          'mes_stock_entries_index',
          'mes_supplier_returns_index',
          'mes_stock_balances_index',
          'mes_stock_conversions_index',
          'mes_warehouses_index',
          'mes_serial_numbers_index',
          'mes_material_issues_index',
          'mes_material_returns_index',
          'mes_production_records_index',
          'mes_inspections_index',
          'mes_fg_inbound_index',
          'mes_shipments_index',
          'mes_notifications_index',
        ],
        children: [
          {
            name: 'MES Dashboard',
            label: t('SIDEBAR.MES_DASHBOARD'),
            to: accountScopedRoute('mes_dashboard_index'),
            activeOn: ['mes_dashboard_index'],
          },
          {
            name: 'MES Pipeline',
            label: t('SIDEBAR.MES_PIPELINE'),
            to: accountScopedRoute('mes_pipeline_index'),
            activeOn: ['mes_pipeline_index'],
          },
          // MES 站内通知是生产流转待办（接单/审批/报工），只给 MES 岗和采购审批人。
          // 财务有自己的「财务通知」，这一条对她是噪音（用户 2026-10-13 定）。
          // 不收进分组：它带未读角标，收起来就看不见了。
          ...(isMesStaff.value ||
          isMesPurchaseApprover.value ||
          mesUnreadCount.value > 0
            ? [
                {
                  name: 'MES Notifications',
                  label: t('SIDEBAR.MES_NOTIFICATIONS'),
                  badgeCount: mesActionCount.value,
                  to: accountScopedRoute('mes_notifications_index'),
                  activeOn: ['mes_notifications_index'],
                },
              ]
            : []),
          // 销售订单是 MES 的入口单据，点得最多，不收进分组。
          {
            name: 'MES Production Orders',
            label: t('SIDEBAR.MES_PRODUCTION_ORDERS'),
            to: accountScopedRoute('mes_production_orders_index'),
            activeOn: ['mes_production_orders_index'],
          },
          // ── 以下按一张单子从头走到尾的顺序分组（2026-10-23，用户：菜单太长太乱）──
          // 常用的四个留在外面；其余 15 项收进 5 个组，一级从 19 行降到 9 行。
          // 分组本身不是路由，只是壳：权限条件原样留在各自的叶子上，
          // 并在组装时丢掉被滤空的组（mesGroup），免得留一个点开是空的壳。
          // 生产任务单与产品档案不分组：只有两项，收起来省不下几行，反而多一层点击；
          // 而且开单前常要查 BOM / 查产品，属于常用项（用户 2026-10-23 定）。
          {
            name: 'MES BOMs',
            label: t('SIDEBAR.MES_BOMS'),
            to: accountScopedRoute('mes_boms_index'),
            activeOn: ['mes_boms_index'],
          },
          {
            name: 'MES Products',
            label: t('SIDEBAR.MES_PRODUCTS'),
            to: accountScopedRoute('mes_products_index'),
            activeOn: ['mes_products_index'],
          },
          mesGroup('MES Purchasing', t('SIDEBAR.MES_G_PURCHASING'), [
            ...(isMesStaff.value
              ? [
                  {
                    name: 'MES Purchase Requisitions',
                    label: t('SIDEBAR.MES_PURCHASE_REQUISITIONS'),
                    to: accountScopedRoute('mes_purchase_requisitions_index'),
                    activeOn: ['mes_purchase_requisitions_index'],
                  },
                ]
              : []),
            ...(isMesStaff.value || isMesPurchaseApprover.value
              ? [
                  {
                    name: 'MES Purchase Orders',
                    label: t('SIDEBAR.MES_PURCHASE_ORDERS'),
                    to: accountScopedRoute('mes_purchase_orders_index'),
                    activeOn: ['mes_purchase_orders_index'],
                  },
                ]
              : []),
            ...(isMesStaff.value || isFinanceViewer.value
              ? [
                  {
                    name: 'MES Suppliers',
                    label: t('SIDEBAR.MES_SUPPLIERS'),
                    to: accountScopedRoute('mes_suppliers_index'),
                    activeOn: ['mes_suppliers_index'],
                  },
                ]
              : []),
            // 物料单价表归采购：财务/采购维护的标准价，而任务单的三级定价里
            // 「本单采购价 / 最近采购价」两级也都来自采购单——整条链都是采购口径。
            // （放「生产准备」里是错的，那组是工程档案：任务单、产品档案。）
            ...(canViewMaterialCost.value
              ? [
                  {
                    name: 'MES Material Prices',
                    label: t('SIDEBAR.MES_MATERIAL_PRICES'),
                    to: accountScopedRoute('mes_material_prices_index'),
                    activeOn: ['mes_material_prices_index'],
                  },
                ]
              : []),
          ]),
          mesGroup('MES Warehouse', t('SIDEBAR.MES_G_WAREHOUSE'), [
            {
              name: 'MES Stock Entries',
              label: t('SIDEBAR.MES_STOCK_ENTRIES'),
              to: accountScopedRoute('mes_stock_entries_index'),
              activeOn: ['mes_stock_entries_index'],
            },
            {
              name: 'MES Stock Balances',
              label: t('SIDEBAR.MES_STOCK_BALANCES'),
              to: accountScopedRoute('mes_stock_balances_index'),
              activeOn: ['mes_stock_balances_index'],
            },
            // 原料↔成品转换：紧挨着结存放，看到哪本账没货就在旁边转。
            {
              name: 'MES Stock Conversions',
              label: t('SIDEBAR.MES_STOCK_CONVERSIONS'),
              to: accountScopedRoute('mes_stock_conversions_index'),
              activeOn: ['mes_stock_conversions_index'],
            },
            // 采购退料：退回给供应商的料（返修或换货），紧挨着入库/库存放（都是料的进出）。
            // ⚠️ 和原料入库页上那个「采购退货」(PURPOSE=PURCHASE_RETURN) 不是一回事：
            // 那个会冲回采购单的到货量、走应付红字；这个只记台账，不动库存不动账。
            {
              name: 'MES Supplier Returns',
              label: t('SIDEBAR.MES_SUPPLIER_RETURNS'),
              to: accountScopedRoute('mes_supplier_returns_index'),
              activeOn: ['mes_supplier_returns_index'],
            },
            // 委外加工：料还是我们的，只是换个地方加工，所以跟着仓库这一组放。
            {
              name: 'MES Outsource Orders',
              label: t('SIDEBAR.MES_OUTSOURCE_ORDERS'),
              to: accountScopedRoute('mes_outsource_orders_index'),
              activeOn: ['mes_outsource_orders_index'],
            },
            ...(isMesStaff.value || isFinanceViewer.value
              ? [
                  {
                    name: 'MES Warehouses',
                    label: t('SIDEBAR.MES_WAREHOUSES'),
                    to: accountScopedRoute('mes_warehouses_index'),
                    activeOn: ['mes_warehouses_index'],
                  },
                ]
              : []),
          ]),
          mesGroup('MES Shopfloor', t('SIDEBAR.MES_G_SHOPFLOOR'), [
            {
              name: 'MES Material Issues',
              label: t('SIDEBAR.MES_MATERIAL_ISSUES'),
              to: accountScopedRoute('mes_material_issues_index'),
              activeOn: ['mes_material_issues_index'],
            },
            // 生产退料：领多了/改单了，车间把料退回仓库。紧跟着领料放——
            // 同一拨人、同一个阶段负责人板块（mes_material_issues_index）。
            {
              name: 'MES Material Returns',
              label: t('SIDEBAR.MES_MATERIAL_RETURNS'),
              to: accountScopedRoute('mes_material_returns_index'),
              activeOn: ['mes_material_returns_index'],
            },
            {
              name: 'MES Production Records',
              label: t('SIDEBAR.MES_PRODUCTION_RECORDS'),
              to: accountScopedRoute('mes_production_records_index'),
              activeOn: ['mes_production_records_index'],
            },
            {
              name: 'MES Inspections',
              label: t('SIDEBAR.MES_INSPECTIONS'),
              to: accountScopedRoute('mes_inspections_index'),
              activeOn: ['mes_inspections_index'],
            },
          ]),
          mesGroup('MES Outbound', t('SIDEBAR.MES_G_OUTBOUND'), [
            {
              name: 'MES FG Inbound',
              label: t('SIDEBAR.MES_FG_INBOUND'),
              to: accountScopedRoute('mes_fg_inbound_index'),
              activeOn: ['mes_fg_inbound_index'],
            },
            {
              name: 'MES Shipments',
              label: t('SIDEBAR.MES_SHIPMENTS'),
              to: accountScopedRoute('mes_shipments_index'),
              activeOn: ['mes_shipments_index'],
            },
            {
              name: 'MES Serial Numbers',
              label: t('SIDEBAR.MES_SERIAL_NUMBERS'),
              to: accountScopedRoute('mes_serial_numbers_index'),
              activeOn: ['mes_serial_numbers_index'],
            },
          ]),
        ].filter(Boolean),
      },
      {
        name: 'CRM Knowledge',
        label: t('SIDEBAR.CRM_G_KNOWLEDGE'),
        icon: 'i-lucide-folder-open',
        activeOn: ['crm_knowledge_docs_index'],
        children: [
          {
            name: 'CRM Company Docs',
            label: t('SIDEBAR.CRM_COMPANY_DOCS'),
            to: accountScopedRoute(
              'crm_knowledge_docs_index',
              {},
              { filter: 'company' }
            ),
            activeOn: ['crm_knowledge_docs_index'],
          },
          {
            name: 'CRM My Docs',
            label: t('SIDEBAR.CRM_MY_DOCS'),
            to: accountScopedRoute(
              'crm_knowledge_docs_index',
              {},
              { filter: 'mine' }
            ),
          },
        ],
      },
      // 设置：管理员/副管理员的账号级 CRM 配置归档（客户设置/公海设置/AI 设置），置于 CRM 模块底部。
      ...(isAdminLike.value
        ? [
            {
              name: 'CRM Settings',
              label: t('SIDEBAR.CRM_G_SETTINGS'),
              icon: 'i-lucide-settings',
              activeOn: [
                'crm_customer_settings_index',
                'crm_dashboard_settings_index',
                'crm_public_pool_settings_index',
                'crm_quote_request_templates_index',
                'crm_ai_settings_index',
                'crm_inbox_collaborators_index',
                'crm_issue_reports_index',
              ],
              children: [
                {
                  name: 'CRM Customer Settings',
                  label: t('SIDEBAR.CRM_CUSTOMER_SETTINGS'),
                  to: accountScopedRoute('crm_customer_settings_index'),
                  activeOn: ['crm_customer_settings_index'],
                },
                {
                  name: 'CRM Dashboard Settings',
                  label: t('SIDEBAR.CRM_DASHBOARD_SETTINGS'),
                  to: accountScopedRoute('crm_dashboard_settings_index'),
                  activeOn: ['crm_dashboard_settings_index'],
                },
                {
                  name: 'CRM Pool Settings',
                  label: t('SIDEBAR.CRM_POOL_SETTINGS'),
                  to: accountScopedRoute('crm_public_pool_settings_index'),
                  activeOn: ['crm_public_pool_settings_index'],
                },
                {
                  // 定制报价的参数模板：每条产品线配一套字段，属账号级配置，与其它设置同列。
                  name: 'CRM Quote Request Templates',
                  label: '定制报价模板',
                  to: accountScopedRoute('crm_quote_request_templates_index'),
                  activeOn: ['crm_quote_request_templates_index'],
                },
                {
                  name: 'CRM AI Settings',
                  label: t('SIDEBAR.CRM_AI_SETTINGS'),
                  to: accountScopedRoute('crm_ai_settings_index'),
                  activeOn: ['crm_ai_settings_index'],
                },
                {
                  name: 'CRM Inbox Collaborators',
                  label: '业务分配',
                  to: accountScopedRoute('crm_inbox_collaborators_index'),
                  activeOn: ['crm_inbox_collaborators_index'],
                },
                {
                  // AI 助手里报上来的 bug / 需求，带提交当时的现场。
                  name: 'CRM Issue Reports',
                  label: '问题反馈',
                  to: accountScopedRoute('crm_issue_reports_index'),
                  activeOn: ['crm_issue_reports_index'],
                },
              ],
            },
          ]
        : []),
      {
        name: 'CRM Doc Center',
        label: t('SIDEBAR.CRM_G_DOC_CENTER'),
        icon: 'i-lucide-folder-open',
        activeOn: ['crm_doc_center_index'],
        children: [
          {
            name: 'CRM Doc Center Company',
            label: t('SIDEBAR.CRM_DOC_CENTER_COMPANY'),
            to: accountScopedRoute(
              'crm_doc_center_index',
              {},
              { filter: 'company' }
            ),
            activeOn: ['crm_doc_center_index'],
          },
          // 资料板块：点进去只看该板块的文件夹/文件（可见性由后端按部门配置）。
          ...docSections.value.map(s => ({
            name: `CRM Doc Section ${s.id}`,
            label: s.name,
            to: accountScopedRoute(
              'crm_doc_center_index',
              {},
              { section: String(s.id) }
            ),
          })),
          // 文档回收站：超级管理员与管理员可见可清理
          ...(isAdminLike.value
            ? [
                {
                  name: 'CRM Doc Center Recycle',
                  label: t('SIDEBAR.CRM_DOC_CENTER_RECYCLE'),
                  to: accountScopedRoute(
                    'crm_doc_center_index',
                    {},
                    { filter: 'recycle' }
                  ),
                },
              ]
            : []),
        ],
      },
      {
        name: 'CRM Org',
        label: t('SIDEBAR.CRM_G_ORG'),
        icon: 'i-lucide-network',
        activeOn: [
          'crm_org_structure_index',
          'crm_org_chart_index',
          'crm_teams_index',
          'crm_members_index',
          'crm_member_invites_index',
        ],
        children: [
          {
            name: 'CRM Org Structure',
            label: t('SIDEBAR.CRM_ORG_STRUCTURE'),
            to: accountScopedRoute('crm_org_structure_index'),
            activeOn: ['crm_org_structure_index'],
          },
          {
            name: 'CRM Org Chart',
            label: t('SIDEBAR.CRM_ORG_CHART'),
            to: accountScopedRoute('crm_org_chart_index'),
            activeOn: ['crm_org_chart_index'],
          },
          // CRM 团队管理：仅超管/管理员（主管/业务员经团队看板只读自己团队）。
          ...(isAdminLike.value
            ? [
                {
                  name: 'CRM Teams',
                  label: t('SIDEBAR.CRM_TEAMS'),
                  to: accountScopedRoute('crm_teams_index'),
                  activeOn: ['crm_teams_index'],
                },
              ]
            : []),
          // CRM 成员权限：超管/管理员/人事全量（人事不可动管理层）；部门负责人只见下属（仅可重置密码）。
          ...(isAdminLike.value || isCrmHr.value || isCrmManager.value
            ? [
                {
                  name: 'CRM Members',
                  label: t('SIDEBAR.CRM_MEMBERS'),
                  to: accountScopedRoute('crm_members_index'),
                  activeOn: ['crm_members_index'],
                },
              ]
            : []),
          // 成员邀请：超管/管理员/人事。
          ...(isAdminLike.value || isCrmHr.value
            ? [
                {
                  name: 'CRM Member Invites',
                  label: t('SIDEBAR.CRM_MEMBER_INVITES'),
                  to: accountScopedRoute('crm_member_invites_index'),
                  activeOn: ['crm_member_invites_index'],
                },
              ]
            : []),
        ],
      },
      {
        name: 'CRM HR Perf',
        label: t('SIDEBAR.CRM_G_HR_PERF'),
        icon: 'i-lucide-award',
        activeOn: [
          'crm_kpi_schemes_index',
          'crm_kpi_sheets_index',
          'crm_performance_settings_index',
          'crm_commission_sheets_index',
          'crm_commission_sheet_detail',
        ],
        children: [
          // 考核方案 / 考核表：按角色可见性开关（管理员始终可见）。
          ...(kpiSchemeVisible.value
            ? [
                {
                  name: 'CRM KPI Schemes',
                  label: t('SIDEBAR.CRM_KPI_SCHEMES'),
                  to: accountScopedRoute('crm_kpi_schemes_index'),
                  activeOn: ['crm_kpi_schemes_index'],
                },
              ]
            : []),
          ...(kpiSheetVisible.value
            ? [
                {
                  name: 'CRM KPI Sheets',
                  label: t('SIDEBAR.CRM_KPI_SHEETS'),
                  badgeCount: kpiSheetTodoCount.value,
                  hint: '有等你填报/打分/确认的考核表时在此提醒；办完角标自动消。',
                  to: accountScopedRoute('crm_kpi_sheets_index'),
                  activeOn: ['crm_kpi_sheets_index', 'crm_kpi_sheet_detail'],
                },
              ]
            : []),
          // 提成表：业务员按月填报订单明细 → 主管审批 → 财务查看/导出。CRM 成员均可入（页内按角色控权）。
          {
            name: 'CRM Commission Sheets',
            label: t('SIDEBAR.CRM_COMMISSION_SHEETS'),
            to: accountScopedRoute('crm_commission_sheets_index'),
            activeOn: [
              'crm_commission_sheets_index',
              'crm_commission_sheet_detail',
            ],
          },
          // 审批人设置：超级管理员与管理员可见。
          ...(isAdminLike.value
            ? [
                {
                  name: 'CRM Perf Settings',
                  label: t('SIDEBAR.CRM_PERF_SETTINGS'),
                  to: accountScopedRoute('crm_performance_settings_index'),
                  activeOn: ['crm_performance_settings_index'],
                },
              ]
            : []),
        ],
      },
      // 考勤：独立板块，全员可用（打卡/我的考勤；汇总与规则页内按角色显隐）。
      {
        name: 'CRM Attendance',
        label: t('SIDEBAR.CRM_ATTENDANCE'),
        icon: 'i-lucide-alarm-clock-check',
        to: accountScopedRoute('crm_attendance_index'),
        activeOn: ['crm_attendance_index'],
      },
      // 员工档案 / 员工薪资配置：独立板块（超级管理员/管理员/人事）。
      ...(isAdminLike.value || isCrmHr.value
        ? [
            {
              name: 'CRM Employees',
              label: t('SIDEBAR.CRM_EMPLOYEES'),
              icon: 'i-lucide-contact',
              to: accountScopedRoute('crm_employees_index'),
              activeOn: ['crm_employees_index'],
            },
            {
              name: 'CRM Employee Comps',
              label: t('SIDEBAR.CRM_EMPLOYEE_COMPS'),
              icon: 'i-lucide-wallet',
              to: accountScopedRoute('crm_employee_comps_index'),
              activeOn: ['crm_employee_comps_index'],
            },
          ]
        : []),
      // 工资表：核算是财务的活，所以比上面那组多放行财务。
      ...(isAdminLike.value || isCrmHr.value || isFinanceViewer.value
        ? [
            {
              name: 'CRM Payroll',
              label: t('SIDEBAR.CRM_PAYROLL'),
              icon: 'i-lucide-banknote',
              to: accountScopedRoute('crm_payroll_sheets_index'),
              activeOn: [
                'crm_payroll_sheets_index',
                'crm_payroll_sheet_detail',
              ],
            },
          ]
        : []),
      {
        name: 'CRM Approvals',
        label: t('SIDEBAR.CRM_G_OA'),
        icon: 'i-lucide-file-check',
        activeOn: ['crm_approvals_index', 'crm_petty_cash_index'],
        children: [
          {
            name: 'CRM My Approvals',
            label: t('SIDEBAR.CRM_APPROVALS'),
            to: accountScopedRoute('crm_approvals_index'),
            activeOn: ['crm_approvals_index'],
          },
          ...(canSeePettyCash.value
            ? [
                {
                  name: 'CRM Petty Cash',
                  label: t('SIDEBAR.CRM_PETTY_CASH'),
                  to: accountScopedRoute('crm_petty_cash_index'),
                  activeOn: ['crm_petty_cash_index'],
                },
              ]
            : []),
          // 审批模板：仅管理员与人事部门成员可见可维护
          ...(currentUser.value?.oa_template_maintainer
            ? [
                {
                  name: 'CRM Approval Templates',
                  label: t('SIDEBAR.CRM_APPROVAL_TEMPLATES'),
                  to: accountScopedRoute('crm_approval_templates_index'),
                  activeOn: ['crm_approval_templates_index'],
                },
              ]
            : []),
        ],
      },
      {
        name: 'CRM Team Chat',
        label: t('SIDEBAR.CRM_G_CHAT'),
        icon: 'i-lucide-messages-square',
        activeOn: ['crm_team_chat_index'],
        children: [
          {
            name: 'CRM Team Chat Messages',
            label: t('SIDEBAR.CRM_TEAM_CHAT'),
            badgeCount: teamChatUnread.value,
            to: accountScopedRoute('crm_team_chat_index'),
            activeOn: ['crm_team_chat_index'],
          },
        ],
      },
      {
        name: 'CRM Schedule',
        label: t('SIDEBAR.CRM_G_SCHEDULE'),
        icon: 'i-lucide-calendar-days',
        activeOn: ['crm_schedule_index'],
        children: [
          {
            name: 'CRM Schedule Index',
            label: t('SIDEBAR.CRM_SCHEDULE'),
            badgeCount: scheduleTodoCount.value,
            to: accountScopedRoute('crm_schedule_index'),
            activeOn: ['crm_schedule_index'],
          },
        ],
      },
      {
        name: 'Reports',
        label: t('SIDEBAR.REPORTS'),
        icon: 'i-lucide-chart-spline',
        children: [
          {
            name: 'Report Overview',
            label: t('SIDEBAR.REPORTS_OVERVIEW'),
            to: accountScopedRoute('account_overview_reports'),
          },
          {
            name: 'Report Conversation',
            label: t('SIDEBAR.REPORTS_CONVERSATION'),
            to: accountScopedRoute('conversation_reports'),
          },
          ...reportRoutes.value,
          {
            name: 'Reports CSAT',
            label: t('SIDEBAR.CSAT'),
            to: accountScopedRoute('csat_reports'),
          },
          {
            name: 'Reports SLA',
            label: t('SIDEBAR.REPORTS_SLA'),
            to: accountScopedRoute('sla_reports'),
          },
          {
            name: 'Reports Bot',
            label: t('SIDEBAR.REPORTS_BOT'),
            to: accountScopedRoute('bot_reports'),
          },
        ],
      },
      {
        name: 'Campaigns',
        label: t('SIDEBAR.CAMPAIGNS'),
        icon: 'i-lucide-megaphone',
        children: [
          {
            name: 'Live chat',
            label: t('SIDEBAR.LIVE_CHAT'),
            to: accountScopedRoute('campaigns_livechat_index'),
          },
          {
            name: 'SMS',
            label: t('SIDEBAR.SMS'),
            to: accountScopedRoute('campaigns_sms_index'),
          },
          {
            name: 'WhatsApp',
            label: t('SIDEBAR.WHATSAPP'),
            to: accountScopedRoute('campaigns_whatsapp_index'),
          },
        ],
      },
      {
        name: 'Portals',
        label: t('SIDEBAR.HELP_CENTER.TITLE'),
        icon: 'i-lucide-library-big',
        children: [
          {
            name: 'Articles',
            label: t('SIDEBAR.HELP_CENTER.ARTICLES'),
            activeOn: [
              'portals_articles_index',
              'portals_articles_new',
              'portals_articles_edit',
            ],
            to: accountScopedRoute('portals_index', {
              navigationPath: 'portals_articles_index',
            }),
          },
          {
            name: 'Categories',
            label: t('SIDEBAR.HELP_CENTER.CATEGORIES'),
            activeOn: [
              'portals_categories_index',
              'portals_categories_articles_index',
              'portals_categories_articles_edit',
            ],
            to: accountScopedRoute('portals_index', {
              navigationPath: 'portals_categories_index',
            }),
          },
          {
            name: 'Locales',
            label: t('SIDEBAR.HELP_CENTER.LOCALES'),
            activeOn: ['portals_locales_index'],
            to: accountScopedRoute('portals_index', {
              navigationPath: 'portals_locales_index',
            }),
          },
          {
            name: 'Settings',
            label: t('SIDEBAR.HELP_CENTER.SETTINGS'),
            activeOn: ['portals_settings_index'],
            to: accountScopedRoute('portals_index', {
              navigationPath: 'portals_settings_index',
            }),
          },
        ],
      },
      {
        name: 'Settings',
        label: t('SIDEBAR.SETTINGS'),
        icon: 'i-lucide-bolt',
        children: [
          {
            name: 'Settings Account Settings',
            label: t('SIDEBAR.ACCOUNT_SETTINGS'),
            icon: 'i-lucide-briefcase',
            to: accountScopedRoute('general_settings_index'),
          },
          // {
          //   name: 'Settings Captain',
          //   label: t('SIDEBAR.CAPTAIN_AI'),
          //   icon: 'i-woot-captain',
          //   to: accountScopedRoute('captain_settings_index'),
          // },
          {
            name: 'Settings Agents',
            label: t('SIDEBAR.AGENTS'),
            icon: 'i-lucide-square-user',
            to: accountScopedRoute('agent_list'),
          },
          {
            name: 'Settings Teams',
            label: t('SIDEBAR.TEAMS'),
            icon: 'i-lucide-users',
            activeOn: [
              'settings_teams_list',
              'settings_teams_new',
              'settings_teams_finish',
              'settings_teams_add_agents',
              'settings_teams_show',
              'settings_teams_edit',
              'settings_teams_edit_members',
              'settings_teams_edit_finish',
            ],
            to: accountScopedRoute('settings_teams_list'),
          },
          ...(hasAdvancedAssignment.value
            ? [
                {
                  name: 'Settings Agent Assignment',
                  label: t('SIDEBAR.AGENT_ASSIGNMENT'),
                  icon: 'i-lucide-user-cog',
                  activeOn: [
                    'assignment_policy_index',
                    'agent_assignment_policy_index',
                    'agent_assignment_policy_create',
                    'agent_assignment_policy_edit',
                    'agent_capacity_policy_index',
                    'agent_capacity_policy_create',
                    'agent_capacity_policy_edit',
                  ],
                  to: accountScopedRoute('assignment_policy_index'),
                },
              ]
            : []),
          {
            name: 'Settings Inboxes',
            label: t('SIDEBAR.INBOXES'),
            icon: 'i-lucide-inbox',
            activeOn: [
              'settings_inbox_list',
              'settings_inbox_show',
              'settings_inbox_new',
              'settings_inbox_finish',
              'settings_inboxes_page_channel',
              'settings_inboxes_add_agents',
            ],
            to: accountScopedRoute('settings_inbox_list'),
          },
          {
            name: 'Settings Labels',
            label: t('SIDEBAR.LABELS'),
            icon: 'i-lucide-tags',
            to: accountScopedRoute('labels_list'),
          },
          {
            name: 'Settings Custom Attributes',
            label: t('SIDEBAR.CUSTOM_ATTRIBUTES'),
            icon: 'i-lucide-code',
            to: accountScopedRoute('attributes_list'),
          },
          {
            name: 'Settings Automation',
            label: t('SIDEBAR.AUTOMATION'),
            icon: 'i-lucide-repeat',
            to: accountScopedRoute('automation_list'),
          },
          {
            name: 'Settings Agent Bots',
            label: t('SIDEBAR.AGENT_BOTS'),
            icon: 'i-lucide-bot',
            to: accountScopedRoute('agent_bots'),
          },
          {
            name: 'Settings Macros',
            label: t('SIDEBAR.MACROS'),
            icon: 'i-lucide-toy-brick',
            to: accountScopedRoute('macros_wrapper'),
          },
          {
            name: 'Settings Canned Responses',
            label: t('SIDEBAR.CANNED_RESPONSES'),
            icon: 'i-lucide-message-square-quote',
            to: accountScopedRoute('canned_list'),
          },
          {
            name: 'Settings Integrations',
            label: t('SIDEBAR.INTEGRATIONS'),
            icon: 'i-lucide-blocks',
            to: accountScopedRoute('settings_applications'),
          },
          {
            name: 'Settings Audit Logs',
            label: t('SIDEBAR.AUDIT_LOGS'),
            icon: 'i-lucide-briefcase',
            to: accountScopedRoute('auditlogs_list'),
          },
          {
            name: 'Settings Custom Roles',
            label: t('SIDEBAR.CUSTOM_ROLES'),
            icon: 'i-lucide-shield-plus',
            to: accountScopedRoute('custom_roles_list'),
          },
          {
            name: 'Settings Sla',
            label: t('SIDEBAR.SLA'),
            icon: 'i-lucide-clock-alert',
            to: accountScopedRoute('sla_list'),
          },
          {
            name: 'Conversation Workflow',
            label: t('SIDEBAR.CONVERSATION_WORKFLOW'),
            icon: 'i-lucide-workflow',
            to: accountScopedRoute('conversation_workflow_index'),
          },
          {
            name: 'Settings Security',
            label: t('SIDEBAR.SECURITY'),
            icon: 'i-lucide-shield',
            to: accountScopedRoute('security_settings_index'),
          },
          {
            name: 'Settings Billing',
            label: t('SIDEBAR.BILLING'),
            icon: 'i-lucide-credit-card',
            to: accountScopedRoute('billing_settings_index'),
          },
        ],
      },
      // CRM 定位下始终隐藏 Captain 管理入口（AI 用「AI 设置」页统一管）。
      // 注意：会话「问 AI 助手」Copilot 面板走 showCopilotTab（同一 captain_integration flag），不受此影响。
    ]
      .filter(item => item.name !== 'Captain')
      // 外贸 CRM 定位下隐藏原生客服模块：联系人 / 报告 / 活动 / 帮助中心。
      .filter(item => !HIDDEN_NATIVE_MODULES.includes(item.name))
      // 非 CRM 人员隐藏 CRM 销售数据分组；纯财务例外，只留销售流程分组。
      .filter(
        item =>
          canAccessCrm.value ||
          !CRM_DATA_MODULES.includes(item.name) ||
          (isCrmFinanceOnly.value && item.name === 'CRM Sales Flow')
      )
      // 纯财务的销售流程分组里只留销售订单 / PI，其余（商机、价目表、报价…）不给。
      .map(item =>
        isCrmFinanceOnly.value && item.name === 'CRM Sales Flow'
          ? {
              ...item,
              children: (item.children || []).filter(child =>
                FINANCE_ONLY_CRM_ITEMS.includes(child.name)
              ),
            }
          : item
      )
      // ERP 财务板块仅财务角色/管理员可见。
      .filter(item => item.name !== 'Finance ERP' || canAccessErp.value)
      // TikTok 板块可见性：管理层/财务/TK 部门负责人成员（后端派生）。
      .filter(item => item.name !== 'TikTok' || canAccessTiktok.value)
      // 「设置」（账号管理后台）仅系统管理员可见；个人资料走左下角头像菜单。
      .filter(item => item.name !== 'Settings' || isAdmin.value)
  );
});

// ── 模块化侧边栏：进哪个系统只显示该系统的项（无切换标签，切换走工作台）──
const route = useRoute();
// 工作台/设置为通用项，任何系统下都显示。
const PINNED_ITEMS = ['CRM Workspace'];
// 各顶级项归属的业务系统。未列出的（含原生会话/收件箱、CRM 销售各组）默认归 CRM。
const ITEM_MODULE = {
  TikTok: 'tiktok',
  'CRM Team Chat': 'chat',
  'CRM Approvals': 'oa',
  'CRM Org': 'hr',
  'CRM HR Perf': 'hr',
  'CRM Attendance': 'hr',
  'CRM Employees': 'hr',
  'CRM Employee Comps': 'hr',
  'CRM Payroll': 'hr',
  'CRM Doc Center': 'doc',
  'CRM Schedule': 'schedule',
  'MES Production': 'mes',
  'Finance ERP': 'erp',
};
const itemModule = name => ITEM_MODULE[name] || 'crm';
// 当前路由属于哪个系统（默认 CRM，含工作台/销售各页/会话）。
const ROUTE_MODULE = {
  erp_dashboard_index: 'erp',
  erp_accounts_index: 'erp',
  erp_vouchers_index: 'erp',
  erp_ledgers_index: 'erp',
  erp_reports_index: 'erp',
  erp_receivables_index: 'erp',
  erp_shipment_approvals_index: 'erp',
  erp_payables_index: 'erp',
  erp_cash_index: 'erp',
  erp_periods_index: 'erp',
  erp_notifications_index: 'erp',
  erp_fixed_assets_index: 'erp',
  erp_margin_index: 'erp',
  erp_bom_costs_index: 'erp',
  erp_expenses_index: 'erp',
  erp_settings_index: 'erp',
  tiktok_today_index: 'tiktok',
  tiktok_dashboard_index: 'tiktok',
  tiktok_sales_records_index: 'tiktok',
  tiktok_profit_index: 'tiktok',
  tiktok_expenses_index: 'tiktok',
  tiktok_assets_index: 'tiktok',
  tiktok_shop_settings_index: 'tiktok',
  tiktok_departments_index: 'tiktok',
  crm_team_chat_index: 'chat',
  crm_schedule_index: 'schedule',
  crm_approvals_index: 'oa',
  crm_approval_templates_index: 'oa',
  crm_petty_cash_index: 'oa',
  crm_org_structure_index: 'hr',
  crm_org_chart_index: 'hr',
  crm_teams_index: 'hr',
  crm_members_index: 'hr',
  crm_member_invites_index: 'hr',
  crm_kpi_schemes_index: 'hr',
  crm_kpi_scheme_editor: 'hr',
  crm_kpi_sheets_index: 'hr',
  crm_kpi_sheet_detail: 'hr',
  crm_commission_sheets_index: 'hr',
  crm_commission_sheet_detail: 'hr',
  crm_performance_settings_index: 'hr',
  crm_employee_comps_index: 'hr',
  crm_payroll_sheets_index: 'hr',
  crm_payroll_sheet_detail: 'hr',
  crm_attendance_index: 'hr',
  crm_employees_index: 'hr',
  crm_doc_center_index: 'doc',
  mes_dashboard_index: 'mes',
  mes_pipeline_index: 'mes',
  mes_production_orders_index: 'mes',
  mes_production_order_intake_index: 'mes',
  mes_boms_index: 'mes',
  mes_bom_intake_index: 'mes',
  mes_products_index: 'mes',
  mes_material_prices_index: 'mes',
  mes_purchase_orders_index: 'mes',
  mes_purchase_order_intake_index: 'mes',
  mes_purchase_requisitions_index: 'mes',
  mes_suppliers_index: 'mes',
  mes_stock_entries_index: 'mes',
  mes_supplier_returns_index: 'mes',
  mes_outsource_orders_index: 'mes',
  mes_material_issues_index: 'mes',
  mes_material_returns_index: 'mes',
  mes_production_records_index: 'mes',
  mes_inspections_index: 'mes',
  mes_fg_inbound_index: 'mes',
  mes_shipments_index: 'mes',
  mes_notifications_index: 'mes',
  mes_serial_numbers_index: 'mes',
  mes_materials_index: 'mes',
  mes_warehouses_index: 'mes',
  mes_stock_balances_index: 'mes',
  mes_stock_conversions_index: 'mes',
};
const activeModule = computed(() => ROUTE_MODULE[route.name] || 'crm');

// 进入文档系统时拉取资料板块（一次），供侧栏渲染板块子项。
watch(
  activeModule,
  module => {
    if (module === 'doc' && !docSections.value.length) fetchDocSections();
  },
  { immediate: true }
);
// 管理员在文档中心增删板块后即时刷新侧栏子项。
onMounted(() => emitter.on('crmDocSectionsUpdated', fetchDocSections));
onBeforeUnmount(() => emitter.off('crmDocSectionsUpdated', fetchDocSections));

// MES「待我处理」角标原来只在侧栏挂载时算一次，而侧栏不随路由重建：
// 单子办完（下发采购 / 接单 / 审批）角标还挂着，点多少次都不掉——反馈点名的就是这个。
// 两条路补上：① 路由一变重算（接口只回几个数字，很便宜，去抖 300ms）；
//            ② 页内办完事当场广播，不用等切页。
let mesTodoTimer = null;
const refreshMesTodo = () => {
  clearTimeout(mesTodoTimer);
  mesTodoTimer = setTimeout(() => {
    fetchMesTodoCount();
    mesNotificationsStore.fetchUnreadCount();
  }, 300);
};
watch(() => route.name, refreshMesTodo);
onMounted(() => emitter.on('MES_TODO_MAY_CHANGE', refreshMesTodo));
onBeforeUnmount(() => {
  clearTimeout(mesTodoTimer);
  emitter.off('MES_TODO_MAY_CHANGE', refreshMesTodo);
});

// 原生 Chatwoot「设置」入口暂时全局隐藏（各系统均不显示）；需要恢复时把
// HIDDEN_ITEMS 清空即可，设置页仍可通过直链 /settings 访问。
const HIDDEN_ITEMS = ['Settings'];
const filteredMenuItems = computed(() =>
  menuItems.value.filter(
    item =>
      !HIDDEN_ITEMS.includes(item.name) &&
      (PINNED_ITEMS.includes(item.name) ||
        itemModule(item.name) === activeModule.value)
  )
);
</script>

<template>
  <aside
    v-on-click-outside="[
      closeMobileSidebar,
      {
        ignore: [
          '#mobile-sidebar-launcher',
          '[data-popover-content]',
          '[data-popover-backdrop]',
        ],
      },
    ]"
    :data-sidebar-collapsed="isEffectivelyCollapsed"
    class="bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 flex flex-col text-sm pb-px fixed top-0 ltr:left-0 rtl:right-0 h-full z-40 w-[200px] border border-white/60 md:w-auto md:relative md:flex-shrink-0 md:ltr:translate-x-0 md:rtl:translate-x-0 md:my-3 md:ltr:ml-3 md:rtl:mr-3 md:h-[calc(100%_-_1.5rem)] md:rounded-3xl md:shadow-[0_10px_40px_-8px_rgb(80_80_160/0.18),inset_0_1px_0_rgb(255_255_255/0.7)] [.theme-obsidian-flat_&]:!m-0 [.theme-obsidian-flat_&]:!h-dvh [.theme-obsidian-flat_&]:!max-h-none [.theme-obsidian-flat_&]:!rounded-none [.theme-obsidian-flat_&]:!border-0 [.theme-obsidian-flat_&]:!shadow-none"
    :class="[
      {
        'shadow-lg md:shadow-none': isMobileSidebarOpen,
        'ltr:-translate-x-full rtl:translate-x-full': !isMobileSidebarOpen,
        'transition-transform duration-200 ease-out md:transition-[width]':
          !isResizing,
      },
    ]"
    :style="isMobile ? undefined : { width: `${sidebarWidth}px` }"
  >
    <section
      data-sidebar-region="header"
      class="grid"
      :class="isEffectivelyCollapsed ? 'mt-3 mb-6 gap-4' : 'mt-1 mb-4 gap-2'"
    >
      <div
        data-sidebar-region="brand"
        class="flex gap-2 items-center min-w-0"
        :class="{
          'justify-center px-1': isEffectivelyCollapsed,
          'px-2': !isEffectivelyCollapsed,
        }"
      >
        <template v-if="isEffectivelyCollapsed">
          <SidebarAccountSwitcher
            is-collapsed
            @show-create-account-modal="emit('showCreateAccountModal')"
          />
        </template>
        <template v-else>
          <img
            :src="wintouchIcon"
            alt="Wintouch"
            class="flex-shrink-0 size-8 rounded-lg shadow-sm shadow-n-iris-9/20 [.theme-classic_&]:hidden"
          />
          <SidebarAccountSwitcher
            class="flex-grow -mx-1 min-w-0 self-center"
            @show-create-account-modal="emit('showCreateAccountModal')"
          />
        </template>
      </div>
      <div
        data-sidebar-region="search"
        class="flex gap-2 [.theme-obsidian-flat_&]:hidden"
        :class="isEffectivelyCollapsed ? 'flex-col items-center' : 'px-2'"
      >
        <RouterLink
          v-if="!isEffectivelyCollapsed"
          :to="{ name: 'search' }"
          class="flex gap-2 items-center px-2 py-1 w-full h-7 rounded-lg outline outline-1 outline-n-weak bg-n-button-color transition-all duration-100 ease-out"
        >
          <span class="flex-shrink-0 i-lucide-search size-4 text-n-slate-10" />
          <span class="flex-grow text-start text-n-slate-10">
            {{ t('COMBOBOX.SEARCH_PLACEHOLDER') }}
          </span>
          <span
            class="hidden tracking-wide pointer-events-none select-none text-n-slate-10"
          >
            {{ searchShortcut }}
          </span>
        </RouterLink>
        <RouterLink
          v-else
          :to="{ name: 'search' }"
          class="flex items-center justify-center size-8 rounded-lg outline outline-1 outline-n-weak bg-n-button-color transition-all duration-100 ease-out hover:bg-n-alpha-2 dark:hover:bg-n-slate-9/30"
          :title="t('COMBOBOX.SEARCH_PLACEHOLDER')"
        >
          <span class="i-lucide-search size-4 text-n-slate-11" />
        </RouterLink>
        <ComposeConversation align="start">
          <template #trigger="{ isOpen }">
            <Button
              icon="i-lucide-pen-line"
              color="slate"
              size="sm"
              class="dark:hover:!bg-n-slate-9/30"
              :class="[
                isEffectivelyCollapsed
                  ? '!size-8 !outline-n-weak !text-n-slate-11'
                  : '!h-7 !outline-n-weak !text-n-slate-11',
                { '!bg-n-alpha-2 dark:!bg-n-slate-9/30': isOpen },
              ]"
            />
          </template>
        </ComposeConversation>
      </div>
    </section>
    <MesProductLineSwitcher
      v-if="activeModule === 'mes' && !isEffectivelyCollapsed"
    />
    <nav
      class="grid overflow-y-scroll flex-grow gap-2 pb-5 no-scrollbar min-w-0"
      :class="isEffectivelyCollapsed ? 'px-1' : 'px-2'"
    >
      <ul
        class="flex flex-col gap-1.5 m-0 list-none min-w-0"
        :class="{ 'items-center': isEffectivelyCollapsed }"
      >
        <SidebarGroup
          v-for="item in filteredMenuItems"
          :key="item.name"
          v-bind="item"
        />
      </ul>
    </nav>
    <section
      data-sidebar-region="footer"
      class="flex relative flex-col flex-shrink-0 gap-1 justify-between items-center"
    >
      <SidebarChangelogCard
        v-if="
          isOnChatwootCloud &&
          !isACustomBrandedInstance &&
          !isEffectivelyCollapsed
        "
      />
      <SidebarChangelogButton
        v-if="
          isOnChatwootCloud &&
          !isACustomBrandedInstance &&
          isEffectivelyCollapsed
        "
      />
      <div
        class="px-1 py-1.5 flex-shrink-0 flex w-full z-50 gap-2 items-center border-t border-n-weak shadow-[0px_-2px_4px_0px_rgba(27,28,29,0.02)]"
        :class="isEffectivelyCollapsed ? 'justify-center' : 'justify-between'"
      >
        <SidebarProfileMenu
          :is-collapsed="isEffectivelyCollapsed"
          @open-key-shortcut-modal="emit('openKeyShortcutModal')"
        />
      </div>
    </section>
    <!-- Resize Handle (desktop only) -->
    <div
      class="hidden md:block absolute top-0 h-full w-1 cursor-col-resize z-40 ltr:right-0 rtl:left-0 group"
      @mousedown="onResizeStart"
      @touchstart="onResizeStart"
      @dblclick="onResizeHandleDoubleClick"
    >
      <div
        class="absolute top-0 h-full w-px ltr:right-0 rtl:left-0 bg-transparent group-hover:bg-n-brand transition-colors"
        :class="{ 'bg-n-brand': isResizing }"
      />
    </div>
  </aside>
</template>
