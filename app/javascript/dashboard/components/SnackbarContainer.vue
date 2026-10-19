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
// ⚠️ `dialog:modal` 是较新的选择器（Chrome 105+）。老内核不认会直接抛 SyntaxError——
// 公司电脑上的 360/QQ 浏览器兼容模式就是这种。退回 `dialog[open]`：
// showModal() 开的对话框同样带 open 属性，找出来的是同一个。
const toastHost = () => {
  let modals = [];
  try {
    modals = document.querySelectorAll('dialog:modal');
  } catch (e) {
    modals = document.querySelectorAll('dialog[open]');
  }
  return modals[modals.length - 1] || document.body;
};

const showPopover = () => {
  const el = snackbarContainer.value;
  if (!el) return;

  // ① 挪进最上面那个对话框。对话框本身在顶层，挪进去才不会被它 ::backdrop 的
  //    4px 模糊糊到。这一步必须独立于下面的 Popover API——原来两段共用一个 try，
  //    老内核在 `dialog:modal` 上一抛，连这个 appendChild 都没走到，toast 就留在
  //    普通文档层被遮罩糊成一团，字一个都看不清（10.19 反馈：转单报错看不清）。
  try {
    const host = toastHost();
    if (el.parentNode !== host) host.appendChild(el);
  } catch (e) {
    // ignore
  }

  // ② 顶层显示。不支持 Popover API 的浏览器会抛，忽略即可：那种浏览器
  //    popover 属性本身也不生效，元素是常规可见的，①已经把它放对地方了。
  try {
    if (el.matches(':popover-open')) {
      el.hidePopover();
    }
  } catch (e) {
    // ignore
  }
  try {
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
