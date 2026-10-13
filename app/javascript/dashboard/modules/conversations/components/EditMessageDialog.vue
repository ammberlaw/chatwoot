<script setup>
// 编辑一条已发出的 WhatsApp 消息（个人号那条线）。
//
// 保存成功后不用自己回写列表：后端 update! 会触发 message.updated 实时推送，
// 气泡的正文和「已编辑」标记跟着就变了。
//
// 失败原因（超过 15 分钟、不是自己发的、桥掉线）由后端原话返回，直接摆给用户看——
// 自己编一句「编辑失败」等于让人再试一次，而再试一次也不会成功。
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import MessageAPI from 'dashboard/api/inbox/message';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  messageId: { type: [Number, String], required: true },
});

const { t } = useI18n();
const dialogRef = ref(null);
const isLoading = ref(false);
const content = ref('');

const open = original => {
  content.value = original || '';
  dialogRef.value?.open();
};

const close = () => dialogRef.value?.close();

const handleConfirm = async () => {
  const text = content.value.trim();
  if (!text) return;

  isLoading.value = true;
  try {
    await MessageAPI.editText(props.conversationId, props.messageId, text);
    useAlert(t('CONVERSATION.SUCCESS_EDIT_MESSAGE'));
    close();
  } catch (error) {
    useAlert(parseAPIErrorResponse(error));
  } finally {
    isLoading.value = false;
  }
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('CONVERSATION.CONTEXT_MENU.EDIT_DIALOG.TITLE')"
    :description="t('CONVERSATION.CONTEXT_MENU.EDIT_DIALOG.HINT')"
    :confirm-button-label="t('CONVERSATION.CONTEXT_MENU.EDIT_DIALOG.SAVE')"
    :is-loading="isLoading"
    :disable-confirm-button="!content.trim()"
    @confirm="handleConfirm"
  >
    <!-- 标题已经说了是在编辑消息，再加一行「消息内容」是多余的。 -->
    <TextArea
      v-model="content"
      class="w-full"
      :placeholder="t('CONVERSATION.CONTEXT_MENU.EDIT_DIALOG.PLACEHOLDER')"
      auto-height
    />
  </Dialog>
</template>
