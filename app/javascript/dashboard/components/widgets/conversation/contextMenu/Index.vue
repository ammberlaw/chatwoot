<script>
import { mapGetters } from 'vuex';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import {
  getSortedAgentsByAvailability,
  getAgentsByUpdatedPresence,
} from 'dashboard/helper/agentHelper.js';
import wootConstants from 'dashboard/constants/globals';
import MenuItem from './menuItem.vue';
import MenuItemWithSubmenu from './menuItemWithSubmenu.vue';
import AgentLoadingPlaceholder from './agentLoadingPlaceholder.vue';

// 菜单只留业务用得上的：会话状态（跟进中/待回复/已成交/暂缓）+ 分配 + 链接类。
// 标记已读未读、优先级、分配标签这三项在本系统里用不上，不放出来。
const MENU = {
  STATUS: 'status',
  SNOOZE: 'snooze',
  AGENT: 'agent',
  TEAM: 'team',
  DELETE: 'delete',
  OPEN_NEW_TAB: 'open-new-tab',
  COPY_LINK: 'copy-link',
};

export default {
  components: {
    MenuItem,
    MenuItemWithSubmenu,
    AgentLoadingPlaceholder,
  },
  props: {
    chatId: {
      type: Number,
      default: null,
    },
    status: {
      type: String,
      default: '',
    },
    inboxId: {
      type: Number,
      default: null,
    },
    conversationUrl: {
      type: String,
      default: '',
    },
    allowedOptions: {
      type: Array,
      default: () => [],
    },
  },
  emits: [
    'updateConversation',
    'assignAgent',
    'assignTeam',
    'deleteConversation',
    'close',
  ],
  setup() {
    const { isAdmin } = useAdmin();
    return {
      isAdmin,
    };
  },
  data() {
    return {
      MENU,
      STATUS_TYPE: wootConstants.STATUS_TYPE,
      statusMenuConfig: [
        {
          key: wootConstants.STATUS_TYPE.RESOLVED,
          label: this.$t('CONVERSATION.CARD_CONTEXT_MENU.RESOLVED'),
          icon: 'checkmark',
        },
        {
          key: wootConstants.STATUS_TYPE.OPEN,
          label: this.$t('CONVERSATION.CARD_CONTEXT_MENU.REOPEN'),
          icon: 'arrow-redo',
        },
        {
          key: wootConstants.STATUS_TYPE.PENDING,
          label: this.$t('CONVERSATION.CARD_CONTEXT_MENU.PENDING'),
          icon: 'book-clock',
        },
      ],
      snoozeOption: {
        key: wootConstants.STATUS_TYPE.SNOOZED,
        label: this.$t('CONVERSATION.CARD_CONTEXT_MENU.SNOOZE.TITLE'),
        icon: 'snooze',
      },
      agentMenuConfig: {
        key: MENU.AGENT,
        icon: 'person-add',
        label: this.$t('CONVERSATION.CARD_CONTEXT_MENU.ASSIGN_AGENT'),
      },
      teamMenuConfig: {
        key: MENU.TEAM,
        icon: 'people-team-add',
        label: this.$t('CONVERSATION.CARD_CONTEXT_MENU.ASSIGN_TEAM'),
      },
      deleteOption: {
        key: MENU.DELETE,
        icon: 'delete',
        label: this.$t('CONVERSATION.CARD_CONTEXT_MENU.DELETE'),
      },
      openInNewTabOption: {
        key: MENU.OPEN_NEW_TAB,
        icon: 'open',
        label: this.$t('CONVERSATION.CARD_CONTEXT_MENU.OPEN_IN_NEW_TAB'),
      },
      copyLinkOption: {
        key: MENU.COPY_LINK,
        icon: 'copy',
        label: this.$t('CONVERSATION.CARD_CONTEXT_MENU.COPY_LINK'),
      },
    };
  },
  computed: {
    // 已经在跟进中的才给「暂缓」，其余状态给了也没意义。
    showSnooze() {
      return this.status === wootConstants.STATUS_TYPE.OPEN;
    },
    ...mapGetters({
      teams: 'teams/getTeams',
      assignableAgentsUiFlags: 'inboxAssignableAgents/getUIFlags',
      currentUser: 'getCurrentUser',
      currentAccountId: 'getCurrentAccountId',
    }),
    // 分配（业务/团队）仅管理员可用：超级管理员或副管理员(crm_role=deputy_admin)。
    isAdminLike() {
      return (
        this.currentUser?.role === 'administrator' ||
        this.currentUser?.crm_role === 'deputy_admin'
      );
    },
    filteredAgentOnAvailability() {
      const agents = this.$store.getters[
        'inboxAssignableAgents/getAssignableAgents'
      ](this.inboxId);
      const agentsByUpdatedPresence = getAgentsByUpdatedPresence(
        agents,
        this.currentUser,
        this.currentAccountId
      );
      const filteredAgents = getSortedAgentsByAvailability(
        agentsByUpdatedPresence
      );
      return filteredAgents;
    },
    assignableAgents() {
      return [
        {
          confirmed: true,
          name: 'None',
          id: null,
          role: 'agent',
          account_id: 0,
          email: 'None',
        },
        ...this.filteredAgentOnAvailability,
      ];
    },
  },
  mounted() {
    this.$store.dispatch('inboxAssignableAgents/fetch', [this.inboxId]);
  },
  methods: {
    // 当前已是这个状态就不再列出来（已成交的不用再给「标记已成交」）。
    show(key) {
      return this.status !== key;
    },
    toggleStatus(status, snoozedUntil) {
      this.$emit('updateConversation', status, snoozedUntil);
    },
    // 暂缓走命令面板选时间（明天/下周/自定义），与会话头部同一套。
    async snoozeConversation() {
      await this.$store.dispatch('setContextMenuChatId', this.chatId);
      document
        .querySelector('ninja-keys')
        ?.open({ parent: 'snooze_conversation' });
    },
    isAllowed(keys) {
      if (!this.allowedOptions.length) return true;
      return keys.some(key => this.allowedOptions.includes(key));
    },
    deleteConversation() {
      this.$emit('deleteConversation', this.chatId);
    },
    openInNewTab() {
      if (!this.conversationUrl) return;

      const url = `${window.chatwootConfig.hostURL}${this.conversationUrl}`;
      window.open(url, '_blank', 'noopener,noreferrer');
      this.$emit('close');
    },
    async copyConversationLink() {
      if (!this.conversationUrl) return;
      try {
        const url = `${window.chatwootConfig.hostURL}${this.conversationUrl}`;
        await copyTextToClipboard(url);
        useAlert(this.$t('CONVERSATION.CARD_CONTEXT_MENU.COPY_LINK_SUCCESS'));
        this.$emit('close');
      } catch (error) {
        // error
      }
    },
    generateMenuLabelConfig(option, type) {
      return {
        key: option.id,
        label: option.name,
        ...(type === 'agent' && { thumbnail: option.thumbnail }),
        ...(type === 'agent' && { status: option.availability_status }),
      };
    },
  },
};
</script>

<template>
  <div
    class="p-1 rounded-md shadow-xl bg-n-alpha-3/50 backdrop-blur-[100px] outline-1 outline outline-n-weak/50"
  >
    <template v-if="isAllowed([MENU.STATUS, MENU.SNOOZE])">
      <template v-for="option in statusMenuConfig">
        <MenuItem
          v-if="show(option.key) && isAllowed([MENU.STATUS])"
          :key="option.key"
          :option="option"
          variant="icon"
          @click.stop="toggleStatus(option.key, null)"
        />
      </template>
      <MenuItem
        v-if="showSnooze && isAllowed([MENU.SNOOZE])"
        :option="snoozeOption"
        variant="icon"
        @click.stop="snoozeConversation()"
      />
      <hr class="m-1 rounded border-b border-n-weak dark:border-n-weak" />
    </template>
    <template v-if="isAdminLike && isAllowed([MENU.AGENT, MENU.TEAM])">
      <MenuItemWithSubmenu
        v-if="isAllowed([MENU.AGENT])"
        :option="agentMenuConfig"
        :sub-menu-available="!!assignableAgents.length"
      >
        <AgentLoadingPlaceholder v-if="assignableAgentsUiFlags.isFetching" />
        <template v-else>
          <MenuItem
            v-for="agent in assignableAgents"
            :key="agent.id"
            :option="generateMenuLabelConfig(agent, 'agent')"
            variant="agent"
            @click.stop="$emit('assignAgent', agent)"
          />
        </template>
      </MenuItemWithSubmenu>
      <MenuItemWithSubmenu
        v-if="isAllowed([MENU.TEAM])"
        :option="teamMenuConfig"
        :sub-menu-available="!!teams.length"
      >
        <MenuItem
          v-for="team in teams"
          :key="team.id"
          :option="generateMenuLabelConfig(team, 'team')"
          @click.stop="$emit('assignTeam', team)"
        />
      </MenuItemWithSubmenu>
      <hr class="m-1 rounded border-b border-n-weak dark:border-n-weak" />
    </template>
    <template v-if="isAllowed([MENU.OPEN_NEW_TAB, MENU.COPY_LINK])">
      <MenuItem
        v-if="isAllowed([MENU.OPEN_NEW_TAB])"
        :option="openInNewTabOption"
        variant="icon"
        @click.stop="openInNewTab"
      />
      <MenuItem
        v-if="isAllowed([MENU.COPY_LINK])"
        :option="copyLinkOption"
        variant="icon"
        @click.stop="copyConversationLink"
      />
    </template>
    <template v-if="isAdmin && isAllowed([MENU.DELETE])">
      <hr class="m-1 rounded border-b border-n-weak dark:border-n-weak" />
      <MenuItem
        :option="deleteOption"
        variant="icon"
        @click.stop="deleteConversation"
      />
    </template>
  </div>
</template>
