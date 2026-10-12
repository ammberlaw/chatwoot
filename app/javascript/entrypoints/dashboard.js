import { createApp } from 'vue';
import { createI18n } from 'vue-i18n';

import axios from 'axios';
// Global Components
import hljsVuePlugin from '@highlightjs/vue-plugin';

import { plugin, defaultConfig } from '@formkit/vue';
import WootWizard from 'components/ui/Wizard.vue';
import FloatingVue from 'floating-vue';
import WootUiKit from 'dashboard/components';
import App from 'dashboard/App.vue';
import i18nMessages from 'dashboard/i18n';
import createAxios from 'dashboard/helper/APIHelper';
import { installGlobalErrorToast } from 'dashboard/helper/globalErrorToast';

import commonHelpers, { isJSONValid } from 'dashboard/helper/commons';
import { sync } from 'vuex-router-sync';
import { createPinia } from 'pinia';
import router, { initalizeRouter } from 'dashboard/routes';
import store from 'dashboard/store';
import constants from 'dashboard/constants/globals';
import * as Sentry from '@sentry/vue';
import {
  initializeAnalyticsEvents,
  initializeChatwootEvents,
} from 'dashboard/helper/scriptHelpers.js';
import FluentIcon from 'shared/components/FluentIcon/DashboardIcon.vue';
import VueDOMPurifyHTML from 'vue-dompurify-html';
import { domPurifyConfig } from 'shared/helpers/HTMLSanitizer.js';

import { vResizeObserver } from '@vueuse/components';
import { installCellTooltip } from '../dashboard/helper/cellTooltip';
import { directive as onClickaway } from 'vue3-click-away';

import 'floating-vue/dist/style.css';

// 部署后自愈：构建产物文件名带内容哈希，新版本一上线旧 chunk 就被删掉。
// 用户页面开着没刷新时，点到懒加载的功能会去请求已经不存在的文件 → 404 →
// 动态 import 失败 → 那块功能静默消失（2026-09-23 表情选择器就是这么"没了"的，
// nginx 日志里是 EmojiIconPicker-<旧哈希>.js 404，而附件/语音在主包里所以不受影响）。
// Vite 这种情况会抛 vite:preloadError，收到就自动刷一次页面换新资源。
// 用时间戳兜底：刚刷过一分钟内又失败，说明不是版本问题（比如真的离线），不再刷，避免死循环。
window.addEventListener('vite:preloadError', event => {
  const KEY = 'vite-preload-reload-at';
  let last = 0;
  try {
    last = Number(window.sessionStorage.getItem(KEY) || 0);
  } catch {
    /* 隐私模式下 sessionStorage 不可用，当作没刷过 */
  }
  if (Date.now() - last < 60000) return;
  try {
    window.sessionStorage.setItem(KEY, String(Date.now()));
  } catch {
    /* 存不下就算了，最多多刷一次 */
  }
  event.preventDefault();
  window.location.reload();
});

const i18n = createI18n({
  legacy: false, // https://github.com/intlify/vue-i18n/issues/1902
  locale: 'en',
  messages: i18nMessages,
});

sync(store, router);

const pinia = createPinia();

const app = createApp(App);
app.use(i18n);
app.use(store);
app.use(pinia);
app.use(router);

// [VITE] Disabled this, need to renable later
if (window.errorLoggingConfig) {
  Sentry.init({
    app,
    dsn: window.errorLoggingConfig,
    denyUrls: [
      // Chrome extensions
      /^chrome:\/\//i,
      /chrome-extension:/i,
      /extensions\//i,

      // Locally saved copies
      /file:\/\//i,

      // Safari extensions.
      /safari-web-extension:/i,
      /safari-extension:/i,
    ],
    integrations: [Sentry.browserTracingIntegration({ router })],
    ignoreErrors: [
      'ResizeObserver loop completed with undelivered notifications',
    ],
  });
}

app.use(VueDOMPurifyHTML, domPurifyConfig);
app.use(WootUiKit);
app.use(
  plugin,
  defaultConfig({
    rules: {
      JSON: ({ value }) => isJSONValid(value),
    },
  })
);
app.use(FloatingVue, {
  instantMove: true,
  arrowOverflow: false,
  disposeTimeout: 5000000,
});
app.use(hljsVuePlugin);

app.component('woot-wizard', WootWizard);
app.component('fluent-icon', FluentIcon);

app.directive('resize', vResizeObserver);
// 表格格子悬停浮出完整内容（事件委托，一处生效全站，见 helper/cellTooltip）
installCellTooltip();
app.directive('on-clickaway', onClickaway);

// 兜底错误提示：页面没 catch 的失败统一弹提示，杜绝「点了没反应」。
installGlobalErrorToast(app);

// load common helpers into js
commonHelpers();
window.WootConstants = constants;
window.axios = createAxios(axios);
// [VITE] Disabled this we don't need it, we can use `useEmitter` directly
// app.prototype.$emitter = emitter;

initializeChatwootEvents();
initializeAnalyticsEvents();
initalizeRouter();

window.onload = () => {
  app.mount('#app');
};
