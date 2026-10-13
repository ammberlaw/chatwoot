<script setup>
import { ref, onMounted, onUnmounted, nextTick } from 'vue';
import WootSnackbar from './Snackbar.vue';
import { emitter } from 'shared/helpers/mitt';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  duration: {
    type: Number,
    default: 2500,
  },
});

const { t } = useI18n();

const snackMessages = ref([]);
const snackbarContainer = ref(null);

// 原生 <dialog>.showModal() 和 popover 同在顶层，但实测对话框会压住 toast
// （elementFromPoint 在 toast 正中取到的是对话框头部）——弹窗里报的错就永远看不见，
// 用户得把弹窗全关掉才读得到，然后刚填的东西白填。有模态对话框开着就把 toast
// 挂进最上面那个对话框里；容器是 position:fixed，挪进去照样按视口居中。
const toastHost = () => {
  const modals = document.querySelectorAll('dialog:modal');
  return modals[modals.length - 1] || document.body;
};

const showPopover = () => {
  try {
    const el = snackbarContainer.value;
    if (!el) return;
    const host = toastHost();
    if (el.parentNode !== host) host.appendChild(el);
    if (el.matches(':popover-open')) {
      el.hidePopover();
    }
    el.showPopover();
  } catch (e) {
    // ignore
  }
};

const onNewToastMessage = ({ message: originalMessage, action }) => {
  const message = action?.usei18n ? t(originalMessage) : originalMessage;
  const duration = action?.duration || props.duration;

  snackMessages.value.push({
    key: Date.now(),
    message,
    action,
  });

  nextTick(showPopover);

  setTimeout(() => {
    snackMessages.value.shift();
  }, duration);
};

onMounted(() => {
  emitter.on('newToastMessage', onNewToastMessage);
});

onUnmounted(() => {
  emitter.off('newToastMessage', onNewToastMessage);
});
</script>

<template>
  <div
    ref="snackbarContainer"
    popover="manual"
    class="fixed top-4 left-1/2 -translate-x-1/2 max-w-[25rem] w-[calc(100%-2rem)] text-center bg-transparent border-0 p-0 m-0 outline-none overflow-visible"
  >
    <transition-group name="toast-fade" tag="div">
      <WootSnackbar
        v-for="snackMessage in snackMessages"
        :key="snackMessage.key"
        :message="snackMessage.message"
        :action="snackMessage.action"
      />
    </transition-group>
  </div>
</template>
