<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useElementSize } from '@vueuse/core';
import BackButton from '../BackButton.vue';
import InboxName from '../InboxName.vue';
import MoreActions from './MoreActions.vue';
// 会话状态（跟进中/待回复/已成交/暂缓）：原先 fork 里没挂出来，业务要用状态收口会话，重新放回头部。
import ResolveAction from 'dashboard/components/buttons/ResolveAction.vue';
import Avatar from 'next/avatar/Avatar.vue';
import SLACardLabel from './components/SLACardLabel.vue';
import ConversationCallButton from './ConversationCallButton.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import ConversationTranslationAPI from 'dashboard/api/crm/conversationTranslation';
import { TRANSLATE_LANGUAGES } from 'dashboard/helper/translationLanguages';
import wootConstants from 'dashboard/constants/globals';
import { conversationListPageURL } from 'dashboard/helper/URLHelper';
import { snoozedReopenTime } from 'dashboard/helper/snoozeHelpers';
import { useInbox } from 'dashboard/composables/useInbox';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

const props = defineProps({
  chat: {
    type: Object,
    default: () => ({}),
  },
  showBackButton: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const conversationHeader = ref(null);
const { width } = useElementSize(conversationHeader);
const { isAWebWidgetInbox } = useInbox();

const currentChat = computed(() => store.getters.getSelectedChat);
const accountId = computed(() => store.getters.getCurrentAccountId);

const chatMetadata = computed(() => props.chat.meta);

const backButtonUrl = computed(() => {
  const {
    params: { inbox_id: inboxId, label, teamId, id: customViewId },
    name,
  } = route;

  const conversationTypeMap = {
    conversation_through_mentions: 'mention',
    conversation_through_participating: 'participating',
    conversation_through_unattended: 'unattended',
  };
  return conversationListPageURL({
    accountId: accountId.value,
    inboxId,
    label,
    teamId,
    conversationType: conversationTypeMap[name],
    customViewId,
  });
});

const isHMACVerified = computed(() => {
  if (!isAWebWidgetInbox.value) {
    return true;
  }
  return chatMetadata.value.hmac_verified;
});

const currentContact = computed(() =>
  store.getters['contacts/getContact'](props.chat.meta.sender.id)
);

const isSnoozed = computed(
  () => currentChat.value.status === wootConstants.STATUS_TYPE.SNOOZED
);

const snoozedDisplayText = computed(() => {
  const { snoozed_until: snoozedUntil } = currentChat.value;
  if (snoozedUntil) {
    return `${t('CONVERSATION.HEADER.SNOOZED_UNTIL')} ${snoozedReopenTime(snoozedUntil)}`;
  }
  return t('CONVERSATION.HEADER.SNOOZED_UNTIL_NEXT_REPLY');
});

const inbox = computed(() => {
  const { inbox_id: inboxId } = props.chat;
  return store.getters['inboxes/getInbox'](inboxId);
});

const hasMultipleInboxes = computed(
  () => store.getters['inboxes/getInboxes'].length > 1
);

const hasSlaPolicyId = computed(() => props.chat?.sla_policy_id);

const copyConversationId = async () => {
  try {
    await copyTextToClipboard(String(props.chat.id));
    useAlert(t('CONVERSATION.HEADER.COPY_ID_SUCCESS'));
  } catch (error) {
    // error
  }
};

// ── 会话自动翻译：开关 + 对方语言（存 conversation.additional_attributes）──
const translateLanguages = TRANSLATE_LANGUAGES;
const autoTranslate = ref(true);
const targetLanguage = ref('英语');

const syncTranslateState = () => {
  const attrs = currentChat.value?.additional_attributes || {};
  autoTranslate.value = attrs.auto_translate !== false; // 未设置视为开
  targetLanguage.value = attrs.target_language || '英语';
};
watch(() => currentChat.value?.id, syncTranslateState, { immediate: true });

const persistTranslateSettings = async () => {
  try {
    await ConversationTranslationAPI.saveSettings(currentChat.value.id, {
      autoTranslate: autoTranslate.value,
      targetLanguage: targetLanguage.value,
    });
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('CONVERSATION.HEADER.TRANSLATE.SAVE_ERROR')
    );
  }
};

const toggleAutoTranslate = () => {
  autoTranslate.value = !autoTranslate.value;
  persistTranslateSettings();
};

const onTargetLanguageChange = () => {
  persistTranslateSettings();
};
</script>

<template>
  <div
    ref="conversationHeader"
    class="flex flex-col gap-3 items-center justify-between flex-1 w-full min-w-0 xl:flex-row px-3 pt-3 pb-2 h-24 xl:h-12"
  >
    <div
      class="flex items-center justify-start w-full xl:w-auto max-w-full min-w-0 xl:flex-1"
    >
      <BackButton
        v-if="showBackButton"
        :back-url="backButtonUrl"
        class="ltr:mr-2 rtl:ml-2"
      />
      <Avatar
        :name="currentContact.name"
        :src="currentContact.thumbnail"
        :size="32"
        :status="currentContact.availability_status"
        hide-offline-status
      />
      <div
        class="flex flex-col items-start min-w-0 ml-2 overflow-hidden rtl:ml-0 rtl:mr-2"
      >
        <div class="flex flex-row items-center max-w-full gap-1 p-0 m-0">
          <span
            class="text-sm font-medium truncate leading-tight text-n-slate-12"
          >
            {{ currentContact.name }}
          </span>
          <fluent-icon
            v-if="!isHMACVerified"
            v-tooltip="$t('CONVERSATION.UNVERIFIED_SESSION')"
            size="14"
            class="text-n-amber-10 my-0 mx-0 min-w-[14px] flex-shrink-0"
            icon="warning"
          />
        </div>

        <div
          class="flex items-center gap-1 overflow-hidden text-xs conversation--header--actions text-n-slate-11 text-ellipsis whitespace-nowrap"
        >
          <button
            type="button"
            class="truncate text-label-small text-n-slate-11 hover:text-n-slate-12 !p-0 cucursor-pointer"
            @click="copyConversationId"
          >
            {{ `#${chat.id}` }}
          </button>
          <span v-if="hasMultipleInboxes">•</span>
          <InboxName v-if="hasMultipleInboxes" :inbox="inbox" class="!mx-0" />
          <span v-if="isSnoozed">•</span>
          <span v-if="isSnoozed" class="font-medium text-n-amber-10">
            {{ snoozedDisplayText }}
          </span>
        </div>
      </div>
    </div>
    <div
      class="flex flex-row items-center justify-start xl:justify-end flex-shrink-0 gap-2 w-full xl:w-auto header-actions-wrap"
    >
      <SLACardLabel
        v-if="hasSlaPolicyId"
        :chat="chat"
        show-extended-info
        :parent-width="width"
        class="hidden md:flex"
      />
      <div class="flex items-center gap-1.5">
        <button
          v-tooltip.bottom="$t('CONVERSATION.HEADER.TRANSLATE.TOGGLE')"
          type="button"
          class="flex items-center justify-center h-8 gap-1 px-2 text-xs font-medium rounded-lg"
          :class="
            autoTranslate
              ? 'bg-n-iris-3 text-n-iris-11'
              : 'text-n-slate-11 hover:bg-n-alpha-2'
          "
          @click="toggleAutoTranslate"
        >
          <span class="i-lucide-languages size-4" />
          {{ $t('CONVERSATION.HEADER.TRANSLATE.LABEL') }}
        </button>
        <SelectCard
          v-if="autoTranslate"
          v-model="targetLanguage"
          align="right"
          trigger-class="!h-8 w-32 text-xs"
          :options="translateLanguages"
          :placeholder="$t('CONVERSATION.HEADER.TRANSLATE.LANG_PLACEHOLDER')"
          @update:model-value="onTargetLanguageChange"
        />
      </div>
      <ConversationCallButton :inbox="inbox" :chat="currentChat" />
      <ResolveAction v-if="currentChat.id" />
      <MoreActions :conversation-id="currentChat.id" />
    </div>
  </div>
</template>
