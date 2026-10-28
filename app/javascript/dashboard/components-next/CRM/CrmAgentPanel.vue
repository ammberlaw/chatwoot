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
import { useMapGetter } from 'dashboard/composables/store';
import CrmAgentAPI from 'dashboard/api/crm/agent';
import Button from 'dashboard/components-next/button/Button.vue';
import CrmAiMascot from 'dashboard/components-next/CRM/CrmAiMascot.vue';

const props = defineProps({
  // Presentation only: the global floating assistant uses a compact welcome layout.
  floatingLayout: { type: Boolean, default: false },
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

// 等待期的那一行文案。实测一轮 3~17 秒，其中 96~99% 是模型在想和在写——
// 工具本身每个只要 6~150 毫秒，前端 2 秒轮询一次根本抓不到中间态，
// 所以这里不做「一步步点亮」的假动画（那是演出来的），只报两件真事：
// 已经查完几项、已经等了多久。秒数在走，人就知道没卡死。
const waitTick = ref(0);
let waitTimer = null;
const waitStartedAt = ref(0);
watch(running, on => {
  clearInterval(waitTimer);
  if (!on) return;

  waitStartedAt.value = Date.now();
  waitTick.value = 0;
  waitTimer = setInterval(() => {
    waitTick.value = Math.floor((Date.now() - waitStartedAt.value) / 1000);
  }, 1000);
});
onBeforeUnmount(() => clearInterval(waitTimer));

const waitText = computed(() => {
  const done = messages.value.filter(m => m.role === 'tool').length;
  const secs = waitTick.value ? ` ${waitTick.value}s` : '';
  return done ? `已查 ${done} 项 · 正在写回答${secs}` : `正在查…${secs}`;
});

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

// 用户提问时正开着哪一页。AI 球挂在全局外壳上，这里读到的就是他眼前那一页，
// 不用去各个页面埋点。subject 取地址栏里的筛选词/单号（列表页点开一条时就是它），
// 后端只收路由名和这一个词，不照单全收。
const pageContext = () => {
  const name = route?.name;
  if (!name) return undefined;
  const q = route.query || {};
  const subject = q.q || q.no || q.order_no || route.params?.id || '';
  return { route: String(name), subject: String(subject).slice(0, 60) };
};

// 发图：展会上拍的规格表、手写询价、客户发来的实物照。
// 以前只有邮件附件能读图，手机上拍的照片没有入口。
const fileRef = ref(null);
const pendingImage = ref(null);
const MAX_IMAGE_MB = 8; // 与后端 VisionReader 的上限一致，先在前端拦住省一次往返

const pickImage = () => fileRef.value?.click();

const onImagePicked = event => {
  const file = event.target.files?.[0];
  event.target.value = '';
  if (!file) return;
  if (!file.type.startsWith('image/')) {
    useAlert('只能发图片');
    return;
  }
  if (file.size > MAX_IMAGE_MB * 1024 * 1024) {
    useAlert(`图太大了（上限 ${MAX_IMAGE_MB}MB）`);
    return;
  }
  pendingImage.value = file;
};

const dropImage = () => {
  pendingImage.value = null;
};

// 语音输入：直接用浏览器自带的识别，不走后端也不额外花钱。
// 展会上、路上单手打字麻烦，说一句比打一句快得多。
const recognition = ref(null);
const listening = ref(false);
const speechSupported =
  typeof window !== 'undefined' &&
  !!(window.SpeechRecognition || window.webkitSpeechRecognition);

const toggleVoice = () => {
  if (!speechSupported) {
    useAlert('这个浏览器不支持语音输入，换 Chrome 试试');
    return;
  }
  if (listening.value) {
    recognition.value?.stop();
    return;
  }
  const Engine = window.SpeechRecognition || window.webkitSpeechRecognition;
  const rec = new Engine();
  rec.lang = 'zh-CN';
  rec.interimResults = false;
  rec.continuous = false;
  rec.onresult = event => {
    const said = Array.from(event.results)
      .map(r => r[0]?.transcript || '')
      .join('');
    // 接在已有文字后面，别把人家打了一半的字覆盖掉
    input.value = input.value ? `${input.value}${said}` : said;
  };
  rec.onerror = () => {
    listening.value = false;
  };
  rec.onend = () => {
    listening.value = false;
  };
  recognition.value = rec;
  listening.value = true;
  rec.start();
};

const send = async () => {
  const text = input.value.trim();
  // 只发图不打字是常见用法（拍一张规格表甩给它），所以有图时空文字也放行
  if ((!text && !pendingImage.value) || busy.value) return;
  try {
    const conv = await ensureConversation();
    const image = pendingImage.value;
    input.value = '';
    pendingImage.value = null;
    const { data } = await CrmAgentAPI.sendMessage(
      conv.id,
      text,
      pageContext(),
      image
    );
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
// 快捷项按岗位给。
//
// 这是全公司的助手（采购、仓管、车间、工程、质检、财务都在名单里），三个入口原本
// 全是业务口径（业绩/未收款/询盘背景），别的岗位点开第一眼就觉得「这工具不是给我的」。
// 用户原话：「这是全公司的 AI agent」。
//
// 身份取 currentUser 上已有的 crm_role / mes_roles / crm_finance，不另开接口。
const SHORTCUT = {
  perf: {
    text: '我这个月做了多少？还有哪几个客户该跟进',
    label: '查看本月业绩',
    icon: 'i-lucide-chart-no-axes-combined',
  },
  unpaid: {
    text: '列一下还没收完款的，按未收金额从大到小',
    label: '梳理未收款',
    icon: 'i-lucide-wallet',
  },
  lead: {
    text: '帮我背调一下这个询盘邮箱：',
    label: '调查询盘背景',
    icon: 'i-lucide-search-check',
    needsInput: true,
  },
  // 全岗位通用的两个：卡单诊断和「功能在哪」，谁都用得上。
  stuck: {
    text: '这张单卡在哪一步、该谁动？单号：',
    label: '这张单卡在哪',
    icon: 'i-lucide-circle-help',
    needsInput: true,
  },
  whereIs: {
    text: '这个功能在系统哪个菜单下？',
    label: '功能在哪',
    icon: 'i-lucide-compass',
    needsInput: true,
  },
  stock: {
    text: '这个物料还有多少现货、够不够做？物料：',
    label: '查库存缺料',
    icon: 'i-lucide-package-search',
    needsInput: true,
  },
};

const currentUser = useMapGetter('getCurrentUser');
const mesRoles = computed(() => currentUser.value?.mes_roles || []);
const hasMes = role => mesRoles.value.includes(role);

// 先判岗位特征，最后才落到默认。管理员/副管走默认那条——他们看全公司，
// 三个里给一个业务、一个生产、一个全局，比三个全是业务贴近实际。
const GENERAL_SHORTCUTS = computed(() => {
  if (hasMes('buyer'))
    return [SHORTCUT.stock, SHORTCUT.stuck, SHORTCUT.whereIs];
  if (
    hasMes('warehouse') ||
    hasMes('production') ||
    hasMes('qc') ||
    hasMes('pmc') ||
    hasMes('engineer')
  ) {
    return [SHORTCUT.stuck, SHORTCUT.stock, SHORTCUT.whereIs];
  }
  // 纯财务（有 crm_finance、不是业务员）：钱的事在前，单据诊断次之。
  if (
    currentUser.value?.crm_finance &&
    currentUser.value?.crm_role !== 'sales'
  ) {
    return [SHORTCUT.unpaid, SHORTCUT.stuck, SHORTCUT.whereIs];
  }
  if (currentUser.value?.crm_role === 'sales') {
    return [SHORTCUT.perf, SHORTCUT.unpaid, SHORTCUT.lead];
  }
  return [SHORTCUT.perf, SHORTCUT.stuck, SHORTCUT.whereIs];
});

const shortcuts = computed(() =>
  props.crmCustomerId ? CUSTOMER_SHORTCUTS : GENERAL_SHORTCUTS.value
);

// 能力说明同样分两套。客户详情里这块只有半屏宽，标题又已经写过一遍
// 「直接问这个客户的事」，再铺三行全量能力纯属把快捷问法挤下去。
// 全公司都用这个助手，开场白不能只报业务口径的能力（用户：「这是全公司的 AI agent」）。
// 一句话覆盖三条线：业务、生产、以及谁都会问的「这单卡在哪 / 功能在哪」。
const INTRO_FULL =
  '客户、订单、库存与业绩都能查，也能看单据卡在哪一步、某个功能在哪，还能起草邮件和 PI。';
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
// 步骤状态（Crm::Agent::StepRecorder 写进 meta）。老消息没有 status 字段，
// 一律当「无状态」——不能回落成 running，否则翻历史对话会看到一屏转个不停的圈。
const stepRunning = m => m.meta?.status === 'running';
const stepDone = m => m.meta?.status === 'done';
// 这一步在查哪一个东西。「查客户」和「查客户 · Alina.Petrova」差着一个量级。
const stepSubject = m => (m.meta?.subject ? `· ${m.meta.subject}` : '');

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
    :class="[fullHeight ? 'h-full' : 'h-[32rem]', floatingLayout && 'relative pb-9 font-sans antialiased font-normal tracking-normal text-[#292b2d]', floatingLayout && !messages.length && 'justify-center']"
  >
    <div
      ref="scroller"
      v-show="!floatingLayout || messages.length"
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
            class="mb-4 flex size-16 items-center justify-center"
          >
            <CrmAiMascot aria-hidden="true" class="size-16 shrink-0" />
          </div>
          <h2 class="text-heading-1 !text-[26px] !font-semibold text-[#252a32]">
            今天有什么可以帮你？
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
          邮件与 PI 仅生成草稿，由你确认后发送。
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
            {{ item.label || item.text }}
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
        <!-- 一步一行，三态：进行中转圈 / 做完实心勾加删除线 / 老记录无状态。
             不报百分比、也不报「共 N 步」——模型是每一步才决定下一步调什么，
             开跑时不知道要几步，编个分母出来迟早对不上（见 Crm::Agent::StepRecorder）。 -->
        <div
          v-if="m.role === 'tool'"
          class="inline-flex items-center gap-1.5 px-2 py-1 text-xs rounded-md bg-n-alpha-1"
          :class="stepDone(m) ? 'text-n-slate-10' : 'text-n-slate-11'"
        >
          <span
            v-if="stepRunning(m)"
            class="i-lucide-loader-circle size-3 shrink-0 animate-spin"
          />
          <span
            v-else-if="stepDone(m)"
            class="i-lucide-circle-check size-3 shrink-0 !text-[#171717]"
          />
          <span v-else class="i-lucide-search size-3 shrink-0" />
          <span :class="stepDone(m) ? 'line-through decoration-n-slate-8' : ''">
            {{ m.content }}
          </span>
          <span
            v-if="m.meta?.subject"
            class="truncate max-w-[12rem] opacity-70"
          >
            {{ stepSubject(m) }}
          </span>
        </div>
        <div
          v-else-if="m.role === 'user'"
          class="max-w-[85%] px-3 py-2 text-sm whitespace-pre-wrap rounded-xl rounded-br-sm"
          :class="floatingLayout ? 'bg-[#171717] text-white text-label !text-[14px] !font-normal !leading-[1.7] !tracking-normal' : 'bg-[#f6e3a0] text-[#29271f]'"
        >
          {{ m.content }}
        </div>
        <div v-else class="group" :class="floatingLayout ? 'w-full' : 'max-w-[92%]'">
          <!-- 还在吐字的那条（后端每 1.2 秒落一次库，见 Runner#flush_partial）：
               给个呼吸光标，让人看出是在写而不是卡住了。 -->
          <!-- 表格单独可横滚（display:block + overflow-x），不然一张七列的表把整个气泡撑爆。 -->
          <div
            v-dompurify-html="renderAnswer(m.content)"
            :class="floatingLayout ? '!bg-transparent !px-0 !rounded-none !ring-0 !font-sans !text-[14px] !font-normal !leading-[1.7] !tracking-normal [&_p]:!text-[14px] [&_p]:!font-normal [&_p]:!leading-[1.7] [&_p]:!tracking-normal [&_li]:!text-[14px] [&_li]:!leading-[1.7] [&_strong]:!font-semibold text-[#292b2d] [&_p]:!text-[#292b2d] [&_strong]:!text-[#171717] [&_li]:!text-[#292b2d] [&_a]:!text-[#3872b0] [&_th]:!text-[#171717] [&_td]:!text-[#292b2d]' : 'bg-white text-[#292b2d] ring-black/5'"
            class="px-3 py-2 rounded-xl rounded-bl-sm ring-1 ring-inset prose prose-bubble !max-w-none [&_table]:block [&_table]:overflow-x-auto [&_table]:text-xs [&_th]:!px-2 [&_th]:!py-1.5 [&_td]:!px-2 [&_td]:!py-1.5 [&_thead_tr]:border-b [&_thead_tr]:border-black/10 [&_tbody_tr]:border-b [&_tbody_tr]:border-black/5"
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
               :class="floatingLayout && '!font-sans !text-[14px] !font-normal !tracking-normal'"
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
        {{ waitText }}
      </div>
    </div>

    <div v-if="floatingLayout && !messages.length" class="mb-6 flex flex-col items-center gap-4">
      <CrmAiMascot class="size-16 shrink-0" aria-hidden="true" />
      <h2 class="m-0 text-center text-heading-1 !font-sans !text-[18px] !font-medium !tracking-normal text-[#171717]">今天有什么可以帮你？</h2>
    </div>

    <!-- 待发的图。必须让人看见选了什么、能撤回——选错图直接发出去要再等十几秒才知道。 -->
    <div
      v-if="pendingImage"
      class="flex items-center gap-2 px-3 py-2 mx-1 mb-1 text-xs border rounded-xl border-n-weak bg-n-alpha-1 text-n-slate-11"
    >
      <span class="i-lucide-image size-4 shrink-0 text-n-iris-11" />
      <span class="flex-1 min-w-0 truncate">{{ pendingImage.name }}</span>
      <span class="shrink-0">{{ Math.round(pendingImage.size / 1024) }} KB</span>
      <button
        type="button"
        class="shrink-0 text-n-slate-10 hover:text-n-slate-12"
        title="不发了"
        @click="dropImage"
      >
        <span class="i-lucide-x size-4" />
      </button>
    </div>

    <div
      :class="floatingLayout && '!relative !block !rounded-3xl !border !border-[#dedede] !bg-white !p-3 !shadow-sm focus-within:!border-[#aaa]'"
      class="[.theme-classic_.crm-agent-workspace_&]:focus-within:!border-[#b6b6b6] flex items-end gap-2 px-1 pt-2 border-t border-n-weak [.theme-classic_.crm-agent-workspace_&]:mx-auto [.theme-classic_.crm-agent-workspace_&]:w-full [.theme-classic_.crm-agent-workspace_&]:max-w-[860px] [.theme-classic_.crm-agent-workspace_&]:gap-3 [.theme-classic_.crm-agent-workspace_&]:rounded-2xl [.theme-classic_.crm-agent-workspace_&]:border [.theme-classic_.crm-agent-workspace_&]:border-[#dfe3e9] [.theme-classic_.crm-agent-workspace_&]:bg-white [.theme-classic_.crm-agent-workspace_&]:p-3 [.theme-classic_.crm-agent-workspace_&]:shadow-[0_8px_26px_-12px_rgba(40,50,70,0.16)]"
    >
      <textarea
        ref="inputRef"
        v-model="input"
        rows="2"
        :placeholder="floatingLayout ? '向 AI 助手提问' : '问点什么…（回车发送，Shift+回车换行）'"
        :class="floatingLayout && '!w-full !min-h-[100px] !border-0 !rounded-none !bg-transparent !shadow-none !pb-10 !text-label !font-sans !text-[14px] !font-normal !leading-[1.7] !tracking-normal placeholder:!font-normal !text-[#292b2d] placeholder:!text-[#858a92] !outline-none !ring-0 focus:!outline-none focus:!ring-0 focus:!shadow-none focus-visible:!outline-none'"
        class="!outline-none !ring-0 focus:!outline-none focus:!ring-0 focus:!shadow-none focus-visible:!outline-none focus:!border-[#b6b6b6] flex-1 px-3 py-2 text-sm border rounded-xl outline-none resize-none reset-base border-n-weak bg-n-solid-1 text-n-slate-12 [.theme-classic_.crm-agent-workspace_&]:border-0 [.theme-classic_.crm-agent-workspace_&]:shadow-none [.theme-classic_.crm-agent-workspace_&]:min-h-[76px] [.theme-classic_.crm-agent-workspace_&]:text-label [.theme-classic_.crm-agent-workspace_&]:placeholder:text-[#a2a8b2]"
        :disabled="busy"
        @keydown.enter.exact.prevent="send"
      />
      <input
        ref="fileRef"
        type="file"
        accept="image/*"
        capture="environment"
        class="hidden"
        @change="onImagePicked"
      />
      <button
        type="button"
        title="发图片（规格表、手写询价、实物照都行）"
        aria-label="发图片"
        :class="floatingLayout ? '!absolute bottom-3 left-3' : ''"
        class="flex items-center justify-center rounded-full size-8 shrink-0 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 disabled:opacity-35"
        :disabled="busy"
        @click="pickImage"
      >
        <span class="i-lucide-image size-4" />
      </button>
      <button
        v-if="speechSupported"
        type="button"
        :title="listening ? '停止' : '语音输入'"
        :aria-label="listening ? '停止语音输入' : '语音输入'"
        :class="[
          floatingLayout ? '!absolute bottom-3 left-12' : '',
          listening ? 'text-n-ruby-11 bg-n-ruby-3' : 'text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12',
        ]"
        class="flex items-center justify-center rounded-full size-8 shrink-0 disabled:opacity-35"
        :disabled="busy"
        @click="toggleVoice"
      >
        <span :class="listening ? 'i-lucide-mic animate-pulse' : 'i-lucide-mic'" class="size-4" />
      </button>
      <Button
        v-if="!floatingLayout"
        label="发送"
        color="iris"
        size="sm"
        :is-loading="busy"
        :disabled="!input.trim() && !pendingImage"
        @click="send"
      />
      <button
        v-else
        type="button"
        title="发送"
        aria-label="发送"
        class="!absolute bottom-3 right-3 !flex !size-8 !items-center !justify-center !rounded-full !border-0 !bg-[#171717] !p-0 !text-white hover:!bg-[#333] disabled:opacity-35"
        :disabled="busy || (!input.trim() && !pendingImage)"
        @click="send"
      >
        <span :class="busy ? 'i-lucide-loader-circle animate-spin' : 'i-lucide-arrow-up'" class="size-4" />
      </button>
    </div>
    <div v-if="floatingLayout && !messages.length" class="mt-4 flex flex-wrap justify-center gap-2">
      <button
        v-for="item in shortcuts"
        :key="item.text"
        type="button"
        :title="item.text"
        class="!inline-flex !items-center !gap-1.5 !rounded-full !border !border-solid !border-[#dedede] !bg-white !px-3 !py-2 text-label !font-sans !text-[14px] !font-normal !tracking-normal !text-[#333] hover:!bg-[#f5f5f5]"
        @click="useShortcut(item)"
      >
        <span class="size-3.5 shrink-0" :class="item.icon" />
        {{ item.label || item.text }}
      </button>
    </div>
    <p v-if="floatingLayout" class="absolute inset-x-0 bottom-0 m-0 text-center text-label-small !font-sans !text-[12px] !font-normal !tracking-normal text-[#999]">
      邮件与 PI 仅生成草稿，由你确认后发送
    </p>
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
