<script setup>
import { ref, onMounted, onBeforeUnmount } from 'vue';
import { useEventListener } from '@vueuse/core';
import Button from 'dashboard/components-next/button/Button.vue';

// 部署了新版本但页面一直开着的人，跑的仍是旧代码——他看到的「改了没生效」其实是旧版。
// 2026-10-09 一天里就有好几个反馈属于这种（审批文案还是旧的、下拉该隐藏的单还在），
// 排查半天才发现代码早在生产上了。这里轮询 /health 的版本号，变了就提示刷新。
//
// /health 跳过了全部中间件与认证，是全站最轻的端点；5 分钟一次、页面不可见时不轮询。
const CHECK_INTERVAL = 5 * 60 * 1000;

const showNotification = ref(false);
const currentVersion = window.globalConfig?.GIT_SHA;
let timer = null;

const checkVersion = async () => {
  // 没有基准版本号（本地开发没有 .git_sha）就不做这件事，免得误报。
  if (!currentVersion || currentVersion === 'unknown' || showNotification.value)
    return;
  if (document.visibilityState === 'hidden') return;

  try {
    const res = await fetch('/health', { cache: 'no-store' });
    const data = await res.json();
    if (data?.version && data.version !== 'unknown') {
      showNotification.value = data.version !== currentVersion;
    }
  } catch {
    // 网络抖动不提示：断网有 NetworkNotification 管，这里静默跳过等下一轮
  }
};

const refreshPage = () => window.location.reload();
const closeNotification = () => {
  showNotification.value = false;
};

// 切回这个标签页时立刻查一次：人离开一上午回来，不用再等满 5 分钟。
useEventListener(document, 'visibilitychange', () => {
  if (document.visibilityState === 'visible') checkVersion();
});

onMounted(() => {
  timer = setInterval(checkVersion, CHECK_INTERVAL);
});
onBeforeUnmount(() => clearInterval(timer));
</script>

<template>
  <transition name="network-notification-fade" tag="div">
    <!-- z-[60]：工作台首页是 Teleport 到 body 的 z-index:50 覆盖层，同级会把提示盖住 -->
    <div v-show="showNotification" class="fixed z-[60] top-2 left-2 group">
      <div
        class="relative flex items-center justify-between w-full px-2 py-1 rounded-lg shadow-lg bg-n-iris-4 dark:bg-n-iris-8"
      >
        <span class="i-lucide-sparkles size-4 text-n-iris-12" />
        <span class="px-2 text-xs font-medium tracking-wide text-n-iris-12">
          系统已更新到新版本
        </span>
        <Button
          ghost
          sm
          icon="i-lucide-refresh-ccw"
          label="刷新"
          class="!text-n-iris-12"
          @click="refreshPage"
        />
        <Button
          ghost
          sm
          icon="i-lucide-x"
          class="!text-n-iris-12"
          @click="closeNotification"
        />
      </div>
    </div>
  </transition>
</template>
