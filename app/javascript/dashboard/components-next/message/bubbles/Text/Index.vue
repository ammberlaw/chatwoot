<script setup>
import { computed } from 'vue';
import BaseBubble from 'next/message/bubbles/Base.vue';
import FormattedContent from './FormattedContent.vue';
import AttachmentChips from 'next/message/chips/AttachmentChips.vue';
import { MESSAGE_TYPES } from '../../constants';
import { useMessageContext } from '../../provider.js';
import { useTranslations } from 'dashboard/composables/useTranslations';

const { content, attachments, contentAttributes, messageType } =
  useMessageContext();

// 自动翻译：原文照常显示，译文（对方语言消息→中文；本方消息→中文原文）在下方同屏显示。
const { translationContent } = useTranslations(contentAttributes);

const isTemplate = computed(() => {
  return messageType.value === MESSAGE_TYPES.TEMPLATE;
});

const isEmpty = computed(() => {
  return !content.value && !attachments.value?.length;
});

// 译文与原文完全一致时（例如本就是中文的消息）不重复显示。
const showTranslation = computed(
  () =>
    translationContent.value &&
    translationContent.value.trim() !== (content.value || '').trim()
);
</script>

<template>
  <BaseBubble class="px-4 py-3" data-bubble-name="text">
    <div class="gap-3 flex flex-col">
      <span v-if="isEmpty" class="text-n-slate-11">
        {{ $t('CONVERSATION.NO_CONTENT') }}
      </span>
      <FormattedContent v-if="content" :content="content" />
      <div
        v-if="showTranslation"
        class="pt-2 mt-0.5 text-sm italic border-t whitespace-pre-wrap text-n-slate-11 border-n-alpha-2"
      >
        {{ translationContent }}
      </div>
      <AttachmentChips :attachments="attachments" class="gap-2" />
      <template v-if="isTemplate">
        <div
          v-if="contentAttributes.submittedEmail"
          class="px-2 py-1 rounded-lg bg-n-alpha-3"
        >
          {{ contentAttributes.submittedEmail }}
        </div>
      </template>
    </div>
  </BaseBubble>
</template>

<style>
p:last-child {
  margin-bottom: 0;
}
</style>
