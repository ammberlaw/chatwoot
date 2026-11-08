export const AVAILABLE_CUSTOM_ROLE_PERMISSIONS = [
  'conversation_manage',
  'conversation_unassigned_manage',
  'conversation_participating_manage',
  'contact_manage',
  'report_manage',
  'knowledge_base_manage',
];

export const ROLES = ['agent', 'administrator'];

export const CONVERSATION_PERMISSIONS = [
  'conversation_manage',
  'conversation_unassigned_manage',
  'conversation_participating_manage',
];

export const MANAGE_ALL_CONVERSATION_PERMISSIONS = 'conversation_manage';

export const CONVERSATION_UNASSIGNED_PERMISSIONS =
  'conversation_unassigned_manage';

export const CONVERSATION_PARTICIPATING_PERMISSIONS =
  'conversation_participating_manage';

export const CONTACT_PERMISSIONS = 'contact_manage';

export const REPORTS_PERMISSIONS = 'report_manage';

export const PORTAL_PERMISSIONS = 'knowledge_base_manage';

export const ASSIGNEE_TYPE_TAB_PERMISSIONS = {
  // 「待回复」＝分给我、最后一句是客户说的。全员可见——这是业务员每天最该先看的一屏，
  // 也是唯一一个不用自己翻、系统能替他挑出来的清单。口径见 ConversationFinder。
  waiting: {
    count: 'waitingCount',
    permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
  },
  me: {
    count: 'mineCount',
    permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
  },
  unassigned: {
    count: 'unAssignedCount',
    // 业务员看不到「未分配的」:会话按客户归属走,未分配是管理员分派前的中转态,
    // 摆在业务员面前只会让人去捡不属于自己的客户。故这里不铺 ...ROLES,只留管理员。
    permissions: [
      'administrator',
      MANAGE_ALL_CONVERSATION_PERMISSIONS,
      CONVERSATION_UNASSIGNED_PERMISSIONS,
    ],
  },
  // 「已分配」＝我派给别人的。只给管理员：业务员不派活，这个页签对他们永远是 0，
  // 摆出来只会占位置。口径见 ConversationFinder#filter_by_assignee_type。
  assigned_out: {
    count: 'assignedOutCount',
    permissions: [
      'administrator',
      MANAGE_ALL_CONVERSATION_PERMISSIONS,
      CONVERSATION_UNASSIGNED_PERMISSIONS,
    ],
  },
  all: {
    count: 'allCount',
    permissions: [
      ...ROLES,
      MANAGE_ALL_CONVERSATION_PERMISSIONS,
      CONVERSATION_PARTICIPATING_PERMISSIONS,
    ],
  },
};
