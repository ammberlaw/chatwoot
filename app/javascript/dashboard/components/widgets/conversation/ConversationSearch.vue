<script setup>
// 会话内搜聊天记录：在当前这一张会话里找那句话，点结果直接跳过去。
//
// 与左上角的全局搜索分开：那个搜的是全账号、只回溯 3 个月、结果是「跳到某个会话」；
// 这个限定在当前会话、不卡时间窗（要找的常常就是几个月前那句），结果是「跳到某条消息」。
// 后端同一个 /search/messages 接口，多传一个 conversation_id（见 SearchService）。
import {
  ref,
  computed,
  watch,
  nextTick,
  onMounted,
  onBeforeUnmount,
} from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import SearchAPI from 'dashboard/api/search';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});
const emit = defineEmits(['close']);

const store = useStore();
const { t } = useI18n();

const query = ref('');
const results = ref([]);
const isSearching = ref(false);
const hasSearched = ref(false);
let debounceId = null;
let reqSeq = 0;

const currentChat = computed(() => store.getters.getSelectedChat);

// 纯文本摘要：搜索结果里不渲染富文本/附件，只要能认出是哪一句。
const plainText = content =>
  String(content || '')
    .replace(/!\[[^\]]*\]\([^)]*\)/g, '')
    .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/[*_`>#]/g, '')
    .replace(/\s+/g, ' ')
    .trim();

const senderName = m => m.sender?.name || '';
const isOutgoing = m => m.message_type === 1;

const runSearch = async () => {
  const q = query.value.trim();
  if (!q) {
    results.value = [];
    hasSearched.value = false;
    return;
  }
  reqSeq += 1;
  const seq = reqSeq;
  isSearching.value = true;
  try {
    const { data } = await SearchAPI.messages({
      q,
      conversationId: props.conversationId,
    });
    // 打字快时请求会乱序回来，只认最后一次发出的那个。
    if (seq !== reqSeq) return;
    results.value = data?.payload?.messages || [];
    hasSearched.value = true;
  } catch (error) {
    if (seq === reqSeq) {
      results.value = [];
      hasSearched.value = true;
    }
  } finally {
    if (seq === reqSeq) isSearching.value = false;
  }
};

watch(query, () => {
  clearTimeout(debounceId);
  debounceId = setTimeout(runSearch, 350);
});

// 跳到那条消息：已经在列表里就直接滚过去；是更早的历史就先把它那一段拉回来再滚。
const goToMessage = async message => {
  const id = message.id;
  if (document.getElementById(`message${id}`)) {
    emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, { messageId: id });
    emit('close');
    return;
  }
  const chat = currentChat.value;
  if (chat?.id) {
    await store.dispatch('fetchPreviousMessages', {
      after: id,
      before: chat.messages?.[0]?.id,
      conversationId: chat.id,
    });
    await nextTick();
  }
  emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, { messageId: id });
  emit('close');
};

const onKeydown = e => {
  if (e.key === 'Escape') emit('close');
};

onMounted(() => {
  document.addEventListener('keydown', onKeydown);
});
onBeforeUnmount(() => {
  clearTimeout(debounceId);
  document.removeEventListener('keydown', onKeydown);
});
</script>

<template>
  <div
    class="absolute inset-x-0 z-30 flex flex-col border-b shadow-lg top-full bg-n-solid-1 border-n-weak max-h-96"
  >
    <div class="flex items-center gap-2 px-3 py-2">
      <Input
        v-model="query"
        autofocus
        size="sm"
        class="flex-1"
        :placeholder="t('CONVERSATION.HEADER.SEARCH.PLACEHOLDER')"
      />
      <button
        type="button"
        class="flex items-center justify-center rounded-lg size-8 shrink-0 text-n-slate-11 hover:bg-n-alpha-2"
        @click="emit('close')"
      >
        <span class="i-lucide-x size-4 shrink-0" />
      </button>
    </div>

    <div class="overflow-y-auto">
      <div v-if="isSearching" class="flex justify-center py-6">
        <Spinner />
      </div>

      <p
        v-else-if="hasSearched && !results.length"
        class="py-6 text-sm text-center text-n-slate-10"
      >
        {{ t('CONVERSATION.HEADER.SEARCH.EMPTY') }}
      </p>

      <template v-else>
        <button
          v-for="m in results"
          :key="m.id"
          type="button"
          class="flex flex-col w-full gap-1 px-3 py-2 text-left border-t border-n-weak hover:bg-n-alpha-1"
          @click="goToMessage(m)"
        >
          <div class="flex items-center gap-2 text-xs text-n-slate-10">
            <span class="font-medium truncate text-n-slate-11">
              {{ senderName(m) }}
            </span>
            <span
              v-if="isOutgoing(m)"
              class="px-1 rounded shrink-0 bg-n-alpha-2 text-n-slate-11"
            >
              {{ t('CONVERSATION.HEADER.SEARCH.OUTGOING') }}
            </span>
            <span class="ml-auto shrink-0">
              {{ messageTimestamp(m.created_at, 'LLL d, yyyy h:mm a') }}
            </span>
          </div>
          <p class="text-sm line-clamp-2 text-n-slate-12">
            {{ plainText(m.content) }}
          </p>
        </button>
      </template>
    </div>
  </div>
</template>
