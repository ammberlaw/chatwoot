<script setup>
// CRM AI 助手的对话面板。侧栏独立页和客户详情面板共用这一个组件。
//
// 为什么要轮询：agent 一轮要连调几次工具、十几秒到一分钟，后端是丢进后台任务跑的，
// 这里按会话 status 轮询，RUNNING 就接着等（见 Crm::AgentRunJob）。
import {
  ref,
  computed,
  nextTick,
  onMounted,
  onBeforeUnmount,
  watch,
} from 'vue';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import CrmAgentAPI from 'dashboard/api/crm/agent';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  // 从客户详情面板进来时带上，对话默认就在谈这个客户
  crmCustomerId: { type: [Number, String], default: null },
  // 独立页会把高度撑满；面板里嵌用传 false
  fullHeight: { type: Boolean, default: true },
});

// 新开一轮、或一轮跑完，都要告诉外面的「历史对话」列表去重拉一次：
// 不然发完第一条消息，这轮对话在左边列表里根本不出现，得刷新整页才看得到。
const emit = defineEmits(['conversationChanged']);

const route = useRoute();

const conversation = ref(null);
const messages = computed(() => conversation.value?.messages || []);
const input = ref('');
const starting = ref(false);
const scroller = ref(null);
const inputRef = ref(null);
let timer = null;

const running = computed(() => conversation.value?.status === 'RUNNING');
const busy = computed(() => running.value || starting.value);

const scrollToEnd = async () => {
  await nextTick();
  const el = scroller.value;
  if (el) el.scrollTop = el.scrollHeight;
};

const stopPolling = () => {
  if (timer) clearInterval(timer);
  timer = null;
};

// 2 秒一次：再快纯属浪费，再慢用户会以为卡住了。
const startPolling = () => {
  stopPolling();
  timer = setInterval(async () => {
    if (!conversation.value) return;
    try {
      const { data } = await CrmAgentAPI.show(conversation.value.id);
      conversation.value = data.payload;
      // 跑完了再报一次：标题和排序（按 updated_at）这时才定下来。
      if (!running.value) {
        stopPolling();
        emit('conversationChanged');
      }
      scrollToEnd();
    } catch {
      stopPolling();
    }
  }, 2000);
};

const ensureConversation = async () => {
  if (conversation.value) return conversation.value;
  starting.value = true;
  try {
    const { data } = await CrmAgentAPI.create(props.crmCustomerId);
    conversation.value = data.payload;
    return conversation.value;
  } finally {
    starting.value = false;
  }
};

const send = async () => {
  const text = input.value.trim();
  if (!text || busy.value) return;
  try {
    const conv = await ensureConversation();
    input.value = '';
    const { data } = await CrmAgentAPI.sendMessage(conv.id, text);
    conversation.value = data.payload;
    // 等第一条问话落库之后才报：标题取的是首个问题，空会话报上去只会多一行没字的。
    emit('conversationChanged');
    scrollToEnd();
    startPolling();
  } catch (error) {
    useAlert(error?.response?.data?.error || '发送失败');
  }
};

// 换客户（客户详情面板里切到别的客户）就重开一轮对话，免得上下文串台。
watch(
  () => props.crmCustomerId,
  () => {
    stopPolling();
    conversation.value = null;
  }
);

const reset = () => {
  stopPolling();
  conversation.value = null;
  input.value = '';
};

onMounted(scrollToEnd);
onBeforeUnmount(stopPolling);

defineExpose({ reset });

// 快捷问法：新用户不知道能问什么，给几条踩得准的。
//
// 分两套是必须的：客户详情面板里有客户上下文，「这个客户」问得通；
// 独立页和悬浮球没有上下文，同一句话会让它反问「哪个客户」——点一下就卡住。
// needsInput 的那条只填进输入框不发送，等用户把邮箱粘上来。
const CUSTOMER_SHORTCUTS = [
  {
    text: '把这个客户最近的往来邮件总结一下，谈到哪一步了',
    icon: 'i-lucide-mails',
  },
  { text: '这个客户以前报过什么价、成交过什么价？', icon: 'i-lucide-tag' },
  // 别写成「根据最近邮件…」：这个客户没有可见邮件时，模型会停下来反问「你要哪个方向」，
  // 而这是个一键按钮，点下去就该拿到草稿。写成直接指令，没邮件它就拿档案和订单写。
  {
    text: '起草一封跟进邮件，直接存草稿',
    icon: 'i-lucide-file-pen-line',
  },
];
const GENERAL_SHORTCUTS = [
  {
    text: '我这个月做了多少？还有哪几个客户该跟进',
    icon: 'i-lucide-chart-no-axes-combined',
  },
  { text: '列一下还没收完款的，按未收金额从大到小', icon: 'i-lucide-wallet' },
  {
    text: '帮我背调一下这个询盘邮箱：',
    icon: 'i-lucide-search-check',
    needsInput: true,
  },
];
const shortcuts = computed(() =>
  props.crmCustomerId ? CUSTOMER_SHORTCUTS : GENERAL_SHORTCUTS
);

// 能力说明同样分两套。客户详情里这块只有半屏宽，标题又已经写过一遍
// 「直接问这个客户的事」，再铺三行全量能力纯属把快捷问法挤下去。
const INTRO_FULL =
  '可查询客户资料、往来邮件与线下跟进记录，历史报价与报价单状态，实时库存、订单生产进度与出货情况，统计业绩目标达成与提成考核，梳理待跟进客户与未收款项，查产品价格表与销售资料，对陌生询盘进行背景调查，并代拟邮件与 PI 草稿。';
const INTRO_CUSTOMER =
  '往来邮件与跟进记录、历史报价、订单进度与出货、库存，问就行；也能直接起草邮件和 PI。';
const intro = computed(() =>
  props.crmCustomerId ? INTRO_CUSTOMER : INTRO_FULL
);
const useShortcut = async item => {
  input.value = item.text;
  if (!item.needsInput) {
    send();
    return;
  }
  // 要补内容的那条：光填进框里不给焦点，用户会以为按钮坏了。
  await nextTick();
  inputRef.value?.focus();
};

// AI 答的是 Markdown（粗体、清单，问数字时还会摆表格）。直接插值出去就是满屏 ** 和竖线，
// 所以复用客户消息那套 MessageFormatter（markdown-it，html:false 不吃原始 HTML）渲染。
const renderAnswer = text => new MessageFormatter(text || '').formattedMessage;

// 结论经常要贴进邮件或表格里。带表格的回答靠手选根本选不干净，给个复制。
const copyAnswer = async text => {
  await copyTextToClipboard(text || '');
  useAlert('已复制');
};

// 这一轮真建出来的草稿（后端挂在 assistant 消息的 meta 上，见 Runner#assistant_meta）。
const artifactsOf = m => m?.meta?.artifacts || [];

// 还在吐字的那条：后端边生成边把半截正文落库（meta.streaming），定稿时这个标记被抹掉。
const isStreaming = m => !!m?.meta?.streaming;

// kind → 落地页。新增一种 artifact 就得在这儿补一行，漏了会默默跳去 PI 列表
// （看着像建错了东西）。customer / opportunity / 跟进记录都落客户详情页：
// 商机和跟进记录都在那一页上看得到，比丢去列表页再搜一遍省事。
const ARTIFACT_ROUTES = {
  email_draft: 'crm_emails_index',
  pi_draft: 'crm_pis_index',
  quote_draft: 'crm_quotes_index',
  customer: 'crm_customer_detail_index',
  opportunity: 'crm_customer_detail_index',
};

// 图标跟着 kind 走：草稿类是「要你去改去发」的笔，客户/商机是「点进去看」的，
// 全用同一支笔会让「打开客户」看着像又建了个什么东西。
const ARTIFACT_ICONS = {
  email_draft: 'i-lucide-mail-plus',
  pi_draft: 'i-lucide-file-pen-line',
  quote_draft: 'i-lucide-file-pen-line',
  customer: 'i-lucide-building-2',
  opportunity: 'i-lucide-target',
};

const artifactIcon = a => ARTIFACT_ICONS[a.kind] || 'i-lucide-file-pen-line';

const artifactRoute = a => {
  const accountId = route.params.accountId;
  const name = ARTIFACT_ROUTES[a.kind] || 'crm_pis_index';
  if (name === 'crm_customer_detail_index')
    return { name, params: { accountId, id: String(a.customer_id) } };
  if (name !== 'crm_emails_index') return { name, params: { accountId } };
  // 两个参数都得给：邮件页的深链判的是 email_id && customer_id，少一个就只是打开收件箱。
  return {
    name,
    params: { accountId },
    query: { email_id: String(a.id), customer_id: String(a.customer_id) },
  };
};
</script>

<template>
  <div
    class="flex flex-col min-h-0"
    :class="fullHeight ? 'h-full' : 'h-[32rem]'"
  >
    <div
      ref="scroller"
      class="flex-1 min-h-0 px-1 overflow-y-auto [.theme-classic_.crm-agent-workspace_&]:flex [.theme-classic_.crm-agent-workspace_&]:flex-col"
    >
      <div
        v-if="!messages.length"
        class="flex flex-col gap-2 px-3 py-6 text-sm text-n-slate-11 [.theme-classic_.crm-agent-workspace_&]:m-auto [.theme-classic_.crm-agent-workspace_&]:w-full [.theme-classic_.crm-agent-workspace_&]:max-w-[740px] [.theme-classic_.crm-agent-workspace_&]:py-12"
      >
        <div
          class="hidden [.theme-classic_.crm-agent-workspace_&]:flex flex-col items-center mb-6"
        >
          <div
            class="mb-4 flex size-12 items-center justify-center text-[#ffc53d]"
          >
            <span aria-hidden="true" class="i-lucide-sparkles size-10 shrink-0" />
          </div>
          <h2 class="text-heading-1 !text-[26px] !font-semibold text-[#252a32]">
            今天，想推进哪一项工作？
          </h2>
        </div>
        <p
          class="[.theme-classic_.crm-agent-workspace_&]:text-center [.theme-classic_.crm-agent-workspace_&]:text-label [.theme-classic_.crm-agent-workspace_&]:leading-6 [.theme-classic_.crm-agent-workspace_&]:text-[#868d98]"
        >
          {{ intro }}
        </p>
        <p
          class="text-xs [.theme-classic_.crm-agent-workspace_&]:text-center [.theme-classic_.crm-agent-workspace_&]:text-label-small [.theme-classic_.crm-agent-workspace_&]:text-[#a1a7b0]"
        >
          草稿均不会自动发送，生成后存入草稿箱与 PI 列表，经确认后由您手动发出。
        </p>
        <div
          class="flex flex-col gap-1 mt-2 [.theme-classic_.crm-agent-workspace_&]:grid [.theme-classic_.crm-agent-workspace_&]:grid-cols-1 [.theme-classic_.crm-agent-workspace_&]:xl:grid-cols-3 [.theme-classic_.crm-agent-workspace_&]:gap-3 [.theme-classic_.crm-agent-workspace_&]:mt-8"
        >
          <button
            v-for="item in shortcuts"
            :key="item.text"
            type="button"
            class="px-3 py-2 text-xs text-left border rounded-lg reset-base border-n-weak text-n-slate-12 hover:bg-n-alpha-1 [.theme-classic_.crm-agent-workspace_&]:flex [.theme-classic_.crm-agent-workspace_&]:flex-col [.theme-classic_.crm-agent-workspace_&]:items-start [.theme-classic_.crm-agent-workspace_&]:gap-4 [.theme-classic_.crm-agent-workspace_&]:rounded-2xl [.theme-classic_.crm-agent-workspace_&]:border-[#e7e9ee] [.theme-classic_.crm-agent-workspace_&]:bg-[#fafbfc] [.theme-classic_.crm-agent-workspace_&]:p-5 [.theme-classic_.crm-agent-workspace_&]:text-label-small [.theme-classic_.crm-agent-workspace_&]:leading-6 [.theme-classic_.crm-agent-workspace_&]:transition-all [.theme-classic_.crm-agent-workspace_&]:hover:border-[#dec778] [.theme-classic_.crm-agent-workspace_&]:hover:bg-[#fffdf5]"
            @click="useShortcut(item)"
          >
            <span
              aria-hidden="true"
              class="hidden [.theme-classic_.crm-agent-workspace_&]:flex size-9 items-center justify-center rounded-xl bg-white text-[#777f8d] border border-[#e9ebef]"
            >
              <span class="size-4" :class="item.icon" />
            </span>
            {{ item.text }}
          </button>
        </div>
      </div>

      <div
        v-for="m in messages"
        :key="m.id"
        class="px-1 py-1.5"
        :class="m.role === 'user' ? 'flex justify-end' : ''"
      >
        <!-- 气泡配色跟客户消息一个口径：我问的奶黄、AI 答的白。色号别写成主题 token，
             经典灰主题会把 iris 映射成近黑/近灰，黄白就没了。 -->
        <!-- 它中间查了什么，摆出来。不摆的话 AI 说什么就是什么，没人判断得出结论从哪来。 -->
        <div
          v-if="m.role === 'tool'"
          class="inline-flex items-center gap-1.5 px-2 py-1 text-xs rounded-md text-n-slate-11 bg-n-alpha-1"
        >
          <span class="i-lucide-search size-3 shrink-0" />
          {{ m.content }}
        </div>
        <div
          v-else-if="m.role === 'user'"
          class="max-w-[85%] px-3 py-2 text-sm whitespace-pre-wrap rounded-xl rounded-br-sm bg-[#f6e3a0] text-[#29271f]"
        >
          {{ m.content }}
        </div>
        <div v-else class="max-w-[92%] group">
          <!-- 还在吐字的那条（后端每 1.2 秒落一次库，见 Runner#flush_partial）：
               给个呼吸光标，让人看出是在写而不是卡住了。 -->
          <!-- 表格单独可横滚（display:block + overflow-x），不然一张七列的表把整个气泡撑爆。 -->
          <div
            v-dompurify-html="renderAnswer(m.content)"
            class="px-3 py-2 rounded-xl rounded-bl-sm bg-white text-[#292b2d] ring-1 ring-inset ring-black/5 prose prose-bubble !max-w-none [&_table]:block [&_table]:overflow-x-auto [&_table]:text-xs [&_th]:!px-2 [&_th]:!py-1.5 [&_td]:!px-2 [&_td]:!py-1.5 [&_thead_tr]:border-b [&_thead_tr]:border-black/10 [&_tbody_tr]:border-b [&_tbody_tr]:border-black/5"
          />
          <div
            v-if="isStreaming(m)"
            class="flex items-center gap-1.5 mt-1.5 text-xs text-n-slate-10"
          >
            <span class="crm-agent-caret" aria-hidden="true" />
            正在写…
          </div>
          <div v-else class="flex flex-wrap items-center gap-2 mt-1.5">
            <button
              type="button"
              class="inline-flex items-center gap-1 text-xs transition-opacity opacity-0 reset-base text-n-slate-11 hover:text-n-slate-12 group-hover:opacity-100 focus:opacity-100"
              @click="copyAnswer(m.content)"
            >
              <span aria-hidden="true" class="i-lucide-copy size-3 shrink-0" />
              复制
            </button>
            <!-- 建了草稿就给个直达入口：只在文字里写「去草稿箱找一下」，用户还得自己翻。 -->
            <router-link
              v-for="a in artifactsOf(m)"
              :key="`${a.kind}-${a.id}`"
              :to="artifactRoute(a)"
              class="inline-flex items-center gap-1 px-2 py-1 text-xs border rounded-md border-n-weak text-n-slate-12 hover:bg-n-alpha-1"
            >
              <span
                aria-hidden="true"
                class="size-3 shrink-0"
                :class="artifactIcon(a)"
              />
              {{ a.label }}
            </router-link>
          </div>
        </div>
      </div>

      <div
        v-if="running && !messages.some(isStreaming)"
        class="flex items-center gap-2 px-3 py-2 text-xs text-n-slate-11"
      >
        <span class="i-lucide-loader-circle size-3.5 shrink-0 animate-spin" />
        正在查…（要几十秒，可以先去忙别的）
      </div>
    </div>

    <div
      class="flex items-end gap-2 px-1 pt-2 border-t border-n-weak [.theme-classic_.crm-agent-workspace_&]:mx-auto [.theme-classic_.crm-agent-workspace_&]:w-full [.theme-classic_.crm-agent-workspace_&]:max-w-[860px] [.theme-classic_.crm-agent-workspace_&]:gap-3 [.theme-classic_.crm-agent-workspace_&]:rounded-2xl [.theme-classic_.crm-agent-workspace_&]:border [.theme-classic_.crm-agent-workspace_&]:border-[#dfe3e9] [.theme-classic_.crm-agent-workspace_&]:bg-white [.theme-classic_.crm-agent-workspace_&]:p-3 [.theme-classic_.crm-agent-workspace_&]:shadow-[0_8px_26px_-12px_rgba(40,50,70,0.16)]"
    >
      <textarea
        ref="inputRef"
        v-model="input"
        rows="2"
        placeholder="问点什么…（回车发送，Shift+回车换行）"
        class="flex-1 px-3 py-2 text-sm border rounded-xl outline-none resize-none reset-base border-n-weak bg-n-solid-1 text-n-slate-12 [.theme-classic_.crm-agent-workspace_&]:border-0 [.theme-classic_.crm-agent-workspace_&]:shadow-none [.theme-classic_.crm-agent-workspace_&]:min-h-[76px] [.theme-classic_.crm-agent-workspace_&]:text-label [.theme-classic_.crm-agent-workspace_&]:placeholder:text-[#a2a8b2]"
        :disabled="busy"
        @keydown.enter.exact.prevent="send"
      />
      <Button
        label="发送"
        color="iris"
        size="sm"
        :is-loading="busy"
        :disabled="!input.trim()"
        @click="send"
      />
    </div>
  </div>
</template>

<style scoped>
/* 吐字中的光标。用 CSS 动画而不是 Tailwind 的 animate-pulse：
   这里要的是「打字机竖线」的节奏（闪一下停一下），pulse 是整体淡入淡出，看着像加载失败。 */
.crm-agent-caret {
  display: inline-block;
  width: 2px;
  height: 0.9em;
  background: currentColor;
  animation: crm-agent-blink 1s steps(2, start) infinite;
}

@keyframes crm-agent-blink {
  to {
    visibility: hidden;
  }
}

@media (prefers-reduced-motion: reduce) {
  .crm-agent-caret {
    animation: none;
  }
}
</style>
