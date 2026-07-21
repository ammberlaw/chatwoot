<script setup>
import { h, ref, computed, onMounted, onBeforeUnmount, watch } from 'vue';
import { provideSidebarContext, useSidebarResize } from './provider';
import { useRoute } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useKbd } from 'dashboard/composables/utils/useKbd';
import { useMapGetter } from 'dashboard/composables/store';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useSidebarKeyboardShortcuts } from './useSidebarKeyboardShortcuts';
import { vOnClickOutside } from '@vueuse/components';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import DocSectionsAPI from 'dashboard/api/crm/docSections';
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
import wintouchIcon from 'dashboard/assets/images/wintouch/icon.png';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
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
const isAdmin = computed(() => currentUser.value?.role === 'administrator');
// 超级管理员或管理员（deputy_admin）：账号级管理入口（成员/邀请/员工档案/薪资/审批人/公海规则）。
const isAdminLike = computed(
  () => isAdmin.value || currentUser.value?.crm_role === 'deputy_admin'
);
const isCrmManager = computed(() => currentUser.value?.crm_role === 'manager');
// 人事角色：组织架构/成员管理/绩效/员工档案入口（无 CRM 销售数据）。
const isCrmHr = computed(() => currentUser.value?.crm_role === 'hr');
// 普通业务（非管理员/副管理员/部门负责人）：隐藏公司级看板等团队之外的数据入口。
const isCrmSales = computed(
  () =>
    !isAdmin.value &&
    !['deputy_admin', 'manager'].includes(currentUser.value?.crm_role)
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
const CRM_DATA_MODULES = [
  'CRM Dashboards',
  'CRM Customers Group',
  'CRM Sales Flow',
  'CRM Mail Center',
  'CRM Knowledge',
];
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

const hasCaptainEnabled = computed(() => {
  return isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.CAPTAIN
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
const conversationCustomViews = useMapGetter(
  'customViews/getConversationCustomViews'
);
const getSidebarSectionSort = useMapGetter(
  'sidebarSortPreferences/getSectionSort'
);

onMounted(() => {
  store.dispatch('labels/get');
  store.dispatch('inboxes/get');
  store.dispatch('notifications/unReadCount');
  store.dispatch('teams/get');
  store.dispatch('attributes/get');
  store.dispatch('customViews/get', 'conversation');
  store.dispatch('customViews/get', 'contact');
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

const sortedFolders = computed(() =>
  sortSidebarItems(conversationCustomViews.value, {
    sortBy: getSortForSection(SIDEBAR_SORT_SECTIONS.FOLDERS),
    labelKey: view => view.name,
  })
);

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
        name: 'Conversation',
        label: t('SIDEBAR.CONVERSATIONS'),
        icon: 'i-lucide-message-circle',
        children: [
          {
            name: 'All',
            label: t('SIDEBAR.ALL_CONVERSATIONS'),
            icon: 'i-lucide-inbox',
            badgeCount: allUnreadCount.value,
            activeOn: ['inbox_conversation'],
            to: accountScopedRoute('home'),
          },
          {
            name: 'Mentions',
            label: t('SIDEBAR.MENTIONED_CONVERSATIONS'),
            icon: 'i-lucide-at-sign',
            activeOn: ['conversation_through_mentions'],
            to: accountScopedRoute('conversation_mentions'),
          },
          {
            name: 'Participating',
            label: t('SIDEBAR.PARTICIPATING_CONVERSATIONS'),
            icon: 'i-lucide-user-round-check',
            activeOn: ['conversation_through_participating'],
            to: accountScopedRoute('conversation_participating'),
          },
          {
            name: 'Unattended',
            activeOn: ['conversation_through_unattended'],
            label: t('SIDEBAR.UNATTENDED_CONVERSATIONS'),
            icon: 'i-lucide-clock-alert',
            to: accountScopedRoute('conversation_unattended'),
          },
          {
            name: 'Folders',
            label: t('SIDEBAR.CUSTOM_VIEWS_FOLDER'),
            icon: 'i-lucide-folder',
            activeOn: ['conversations_through_folders'],
            ...buildSortConfig(SIDEBAR_SORT_SECTIONS.FOLDERS),
            collapsible: true,
            showTreeLine: true,
            children: sortedFolders.value.map(view => ({
              name: `${view.name}-${view.id}`,
              label: view.name,
              to: accountScopedRoute('folder_conversations', { id: view.id }),
            })),
          },
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
            children: sortedInboxes.value.map(inbox => ({
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
      // ── Wintouch-CRM 五分区（对齐 Twenty 侧栏结构）──
      {
        name: 'CRM Dashboards',
        label: t('SIDEBAR.CRM_G_DASHBOARDS'),
        icon: 'i-lucide-layout-dashboard',
        activeOn: [
          'crm_dashboard_index',
          'crm_team_dashboard_index',
          'crm_my_target_index',
        ],
        children: [
          ...(isCrmSales.value
            ? []
            : [
                {
                  name: 'CRM Company Dashboard',
                  label: t('SIDEBAR.CRM_DASH_COMPANY'),
                  to: accountScopedRoute('crm_dashboard_index'),
                  activeOn: ['crm_dashboard_index'],
                },
              ]),
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
            name: 'CRM Team Dashboard',
            label: t('SIDEBAR.CRM_DASH_TEAM'),
            to: accountScopedRoute('crm_team_dashboard_index'),
            activeOn: ['crm_team_dashboard_index'],
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
        name: 'CRM Customers Group',
        label: t('SIDEBAR.CRM_G_CUSTOMERS'),
        icon: 'i-lucide-users',
        activeOn: [
          'crm_customers_index',
          'crm_customer_intake_index',
          'crm_public_pool_settings_index',
        ],
        children: [
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
          ...(isAdminLike.value
            ? [
                {
                  name: 'CRM Pool Settings',
                  label: t('SIDEBAR.CRM_POOL_SETTINGS'),
                  to: accountScopedRoute('crm_public_pool_settings_index'),
                  activeOn: ['crm_public_pool_settings_index'],
                },
              ]
            : []),
        ],
      },
      {
        name: 'CRM Sales Flow',
        label: t('SIDEBAR.CRM_G_SALES_FLOW'),
        icon: 'i-lucide-funnel',
        activeOn: [
          'crm_funnel_index',
          'crm_sales_orders_index',
          'crm_opportunities_index',
        ],
        children: [
          {
            name: 'CRM Funnel',
            label: t('SIDEBAR.CRM_FUNNEL'),
            to: accountScopedRoute('crm_funnel_index'),
            activeOn: ['crm_funnel_index'],
          },
          {
            name: 'CRM Opportunities',
            label: t('SIDEBAR.CRM_OPPORTUNITIES'),
            to: accountScopedRoute('crm_opportunities_index'),
            activeOn: ['crm_opportunities_index'],
          },
          {
            name: 'CRM Sales Orders',
            label: t('SIDEBAR.CRM_SALES_ORDERS'),
            to: accountScopedRoute('crm_sales_orders_index'),
            activeOn: ['crm_sales_orders_index'],
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
        name: 'MES Production',
        label: t('SIDEBAR.MES_G_PRODUCTION'),
        icon: 'i-lucide-factory',
        activeOn: [
          'mes_dashboard_index',
          'mes_production_orders_index',
          'mes_boms_index',
          'mes_purchase_orders_index',
          'mes_stock_entries_index',
          'mes_material_issues_index',
          'mes_production_records_index',
          'mes_fg_inbound_index',
          'mes_shipments_index',
          'mes_stock_balances_index',
          'mes_materials_index',
          'mes_suppliers_index',
          'mes_warehouses_index',
        ],
        children: [
          {
            name: 'MES Dashboard',
            label: t('SIDEBAR.MES_DASHBOARD'),
            to: accountScopedRoute('mes_dashboard_index'),
            activeOn: ['mes_dashboard_index'],
          },
          {
            name: 'MES Production Orders',
            label: t('SIDEBAR.MES_PRODUCTION_ORDERS'),
            to: accountScopedRoute('mes_production_orders_index'),
            activeOn: ['mes_production_orders_index'],
          },
          {
            name: 'MES BOMs',
            label: t('SIDEBAR.MES_BOMS'),
            to: accountScopedRoute('mes_boms_index'),
            activeOn: ['mes_boms_index'],
          },
          {
            name: 'MES Purchase Orders',
            label: t('SIDEBAR.MES_PURCHASE_ORDERS'),
            to: accountScopedRoute('mes_purchase_orders_index'),
            activeOn: ['mes_purchase_orders_index'],
          },
          {
            name: 'MES Stock Entries',
            label: t('SIDEBAR.MES_STOCK_ENTRIES'),
            to: accountScopedRoute('mes_stock_entries_index'),
            activeOn: ['mes_stock_entries_index'],
          },
          {
            name: 'MES Material Issues',
            label: t('SIDEBAR.MES_MATERIAL_ISSUES'),
            to: accountScopedRoute('mes_material_issues_index'),
            activeOn: ['mes_material_issues_index'],
          },
          {
            name: 'MES Production Records',
            label: t('SIDEBAR.MES_PRODUCTION_RECORDS'),
            to: accountScopedRoute('mes_production_records_index'),
            activeOn: ['mes_production_records_index'],
          },
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
            name: 'MES Stock Balances',
            label: t('SIDEBAR.MES_STOCK_BALANCES'),
            to: accountScopedRoute('mes_stock_balances_index'),
            activeOn: ['mes_stock_balances_index'],
          },
          {
            name: 'MES Materials',
            label: t('SIDEBAR.MES_MATERIALS'),
            to: accountScopedRoute('mes_materials_index'),
            activeOn: ['mes_materials_index'],
          },
          {
            name: 'MES Suppliers',
            label: t('SIDEBAR.MES_SUPPLIERS'),
            to: accountScopedRoute('mes_suppliers_index'),
            activeOn: ['mes_suppliers_index'],
          },
          {
            name: 'MES Warehouses',
            label: t('SIDEBAR.MES_WAREHOUSES'),
            to: accountScopedRoute('mes_warehouses_index'),
            activeOn: ['mes_warehouses_index'],
          },
        ],
      },
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
        name: 'CRM Knowledge',
        label: t('SIDEBAR.CRM_G_KNOWLEDGE'),
        icon: 'i-lucide-book-open',
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
      {
        name: 'CRM Doc Center',
        label: t('SIDEBAR.CRM_G_DOC_CENTER'),
        icon: 'i-lucide-library',
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
          // 资料板块（仅列出当前用户可见的；可见性按部门在文档中心配置）
          ...docSections.value.map(section => ({
            name: `CRM Doc Section ${section.id}`,
            label: section.name,
            to: accountScopedRoute(
              'crm_doc_center_index',
              {},
              { filter: 'company', section_id: String(section.id) }
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
                  to: accountScopedRoute('crm_kpi_sheets_index'),
                  activeOn: ['crm_kpi_sheets_index', 'crm_kpi_sheet_detail'],
                },
              ]
            : []),
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
      {
        name: 'CRM Approvals',
        label: t('SIDEBAR.CRM_G_OA'),
        icon: 'i-lucide-file-check',
        activeOn: ['crm_approvals_index'],
        children: [
          {
            name: 'CRM My Approvals',
            label: t('SIDEBAR.CRM_APPROVALS'),
            to: accountScopedRoute('crm_approvals_index'),
            activeOn: ['crm_approvals_index'],
          },
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
            to: accountScopedRoute('crm_team_chat_index'),
            activeOn: ['crm_team_chat_index'],
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
      // CRM 定位下默认隐藏 Captain（AI 坐席）——开启 captain_integration flag 即恢复。
    ]
      .filter(item => item.name !== 'Captain' || hasCaptainEnabled.value)
      // 外贸 CRM 定位下隐藏原生客服模块：联系人 / 报告 / 活动 / 帮助中心。
      .filter(item => !HIDDEN_NATIVE_MODULES.includes(item.name))
      // 非 CRM 人员隐藏 CRM 销售数据分组。
      .filter(
        item => canAccessCrm.value || !CRM_DATA_MODULES.includes(item.name)
      )
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
  'CRM Team Chat': 'chat',
  'CRM Approvals': 'oa',
  'CRM Org': 'hr',
  'CRM HR Perf': 'hr',
  'CRM Attendance': 'hr',
  'CRM Employees': 'hr',
  'CRM Employee Comps': 'hr',
  'CRM Doc Center': 'doc',
  'MES Production': 'mes',
};
const itemModule = name => ITEM_MODULE[name] || 'crm';
// 当前路由属于哪个系统（默认 CRM，含工作台/销售各页/会话）。
const ROUTE_MODULE = {
  crm_team_chat_index: 'chat',
  crm_approvals_index: 'oa',
  crm_approval_templates_index: 'oa',
  crm_org_structure_index: 'hr',
  crm_org_chart_index: 'hr',
  crm_teams_index: 'hr',
  crm_members_index: 'hr',
  crm_member_invites_index: 'hr',
  crm_kpi_schemes_index: 'hr',
  crm_kpi_scheme_editor: 'hr',
  crm_kpi_sheets_index: 'hr',
  crm_kpi_sheet_detail: 'hr',
  crm_performance_settings_index: 'hr',
  crm_employee_comps_index: 'hr',
  crm_attendance_index: 'hr',
  crm_employees_index: 'hr',
  crm_doc_center_index: 'doc',
  mes_dashboard_index: 'mes',
  mes_production_orders_index: 'mes',
  mes_boms_index: 'mes',
  mes_purchase_orders_index: 'mes',
  mes_stock_entries_index: 'mes',
  mes_material_issues_index: 'mes',
  mes_production_records_index: 'mes',
  mes_fg_inbound_index: 'mes',
  mes_shipments_index: 'mes',
  mes_stock_balances_index: 'mes',
  mes_materials_index: 'mes',
  mes_suppliers_index: 'mes',
  mes_warehouses_index: 'mes',
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
    class="bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 flex flex-col text-sm pb-px fixed top-0 ltr:left-0 rtl:right-0 h-full z-40 w-[200px] border border-white/60 md:w-auto md:relative md:flex-shrink-0 md:ltr:translate-x-0 md:rtl:translate-x-0 md:my-3 md:ltr:ml-3 md:rtl:mr-3 md:h-[calc(100%_-_1.5rem)] md:rounded-3xl md:shadow-[0_10px_40px_-8px_rgb(80_80_160/0.18),inset_0_1px_0_rgb(255_255_255/0.7)]"
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
      class="grid"
      :class="isEffectivelyCollapsed ? 'mt-3 mb-6 gap-4' : 'mt-1 mb-4 gap-2'"
    >
      <div
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
            class="flex-shrink-0 size-8 rounded-lg shadow-sm shadow-n-iris-9/20"
          />
          <SidebarAccountSwitcher
            class="flex-grow -mx-1 min-w-0 self-center"
            @show-create-account-modal="emit('showCreateAccountModal')"
          />
        </template>
      </div>
      <div
        class="flex gap-2"
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
      class="flex relative flex-col flex-shrink-0 gap-1 justify-between items-center"
    >
      <div
        class="pointer-events-none absolute inset-x-0 -top-[1.938rem] h-8 bg-gradient-to-t from-n-background to-transparent"
      />
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
