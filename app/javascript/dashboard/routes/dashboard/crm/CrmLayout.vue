<script setup>
// CRM 常驻布局：包住所有 CRM 页面，写信窗挂在这层 → 在 CRM 各模块间切换不卸载、常驻不消失（仿 Gmail）。
import { ref, watch } from 'vue';
import { useCrmComposeStore } from 'dashboard/stores/crm/compose';
import CrmEmailComposeDialog from 'dashboard/components-next/CRM/CrmEmailComposeDialog.vue';

const composeStore = useCrmComposeStore();
const composeRef = ref(null);

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
    <!-- 手机端不再整体留出 96px 悬浮钮高度：那样每个页面的白框都提前结束，底下一条死灰带
         （41 个页面都短了一截）。改为页面占满，谁有底部控件谁自己让开左下角侧栏 ☰（max-md:pl-16）。
         右下角 AI 球可拖动，不作为布局约束。 -->
    <div class="w-full h-full">
      <router-view />
    </div>
    <CrmEmailComposeDialog
      ref="composeRef"
      @refresh="composeStore.notifyRefresh()"
    />
  </div>
</template>
