<script setup>
// CRM 常驻布局：包住所有 CRM 页面，写信窗挂在这层 → 在 CRM 各模块间切换不卸载、常驻不消失（仿 Gmail）。
import { ref, watch, computed } from 'vue';
import { useRoute } from 'vue-router';
import { useCrmComposeStore } from 'dashboard/stores/crm/compose';
import CrmEmailComposeDialog from 'dashboard/components-next/CRM/CrmEmailComposeDialog.vue';
import CrmAiAssistant from 'dashboard/components-next/CRM/CrmAiAssistant.vue';

const composeStore = useCrmComposeStore();
const composeRef = ref(null);

// 团队沟通页有自己的底部输入栏，AI 悬浮球会挡住发送键——该页隐藏 AI 球（其它页照常）。
const route = useRoute();
const showAiAssistant = computed(() => route.name !== 'crm_team_chat_index');

// 任意 CRM 页面调用 composeStore.open(prefill) → 触发这个常驻写信窗打开。
watch(
  () => composeStore.openSeq,
  seq => {
    if (seq > 0) composeRef.value?.open(composeStore.prefill);
  }
);
</script>

<template>
  <!-- transform-gpu 建立 fixed 定位的包含块 = 内容区（侧边栏之外）：
       放大态写信窗在内容区居中（不跑偏、不遮罩侧边栏），小窗停靠内容区右下。 -->
  <div class="relative w-full h-full transform-gpu">
    <!-- 手机端底部留出悬浮钮(AI 助手/侧栏入口)的高度，避免分页条/输入框等底部控件被压住点不到。
         padding 加在这层而非外层：外层是 fixed 的包含块，改它会让悬浮钮跟着上移。
         「白框铺满到底」的概览/看板页各自用 max-md:min-h + -mb-24 逐页处理（无底部控件才用）。 -->
    <div class="w-full h-full max-md:pb-24">
      <router-view />
    </div>
    <CrmEmailComposeDialog
      ref="composeRef"
      @refresh="composeStore.notifyRefresh()"
    />
    <CrmAiAssistant v-if="showAiAssistant" />
  </div>
</template>
