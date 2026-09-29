import { useAlert } from 'dashboard/composables';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';

// 兜底错误提示：页面里没被 catch 的失败（store action 会 throw、按钮回调常忘了包 try）
// 原本是「点了完全没反应」，用户只能干等或反复重试。这里统一捞起来弹一条提示，
// 保证任何一步出错都有反馈；页面自己写了 catch 的仍走它自己的文案，不受影响。
const FALLBACK = '操作失败，请重试';

// 权限不足后端统一回这句英文（Pundit），直接弹给用户看没人懂，换成中文。
const NOT_AUTHORIZED = 'You are not authorized to do this action';

// 取用户看得懂的那句：后端 { error: '...' } / { message: '...' } 优先，其次 Error.message。
const messageOf = reason => {
  if (!reason) return FALLBACK;
  if (reason.response?.status === 403) return '你没有权限做这个操作';
  if (reason.response) {
    // 注意：parseAPIErrorResponse 取不到消息时会把 error 对象原样返回，只认字符串。
    const parsed = parseAPIErrorResponse(reason);
    if (parsed === NOT_AUTHORIZED) return '你没有权限做这个操作';
    return typeof parsed === 'string' && parsed.trim() ? parsed : FALLBACK;
  }
  // 代码 bug 类的原生异常（TypeError 等）只给通用文案——原文是英文技术细节，
  // 甩给用户没意义。store 里 throwErrorMessage 抛的是 `new Error(后端消息)`，
  // name 正是 'Error'，那种要原样透出去。
  const JS_ERRORS = [
    'TypeError',
    'ReferenceError',
    'RangeError',
    'SyntaxError',
    'EvalError',
  ];
  if (JS_ERRORS.includes(reason.name)) return FALLBACK;

  const text = String(reason.message || reason).trim();
  if (!text || text === '[object Object]') return FALLBACK;
  return text.slice(0, 120);
};

// 同一条消息短时间内只弹一次：一次操作常触发多个并发请求同时失败，避免刷屏。
let lastMessage = '';
let lastAt = 0;
const shouldSkip = message => {
  const now = Date.now();
  if (message === lastMessage && now - lastAt < 3000) return true;
  lastMessage = message;
  lastAt = now;
  return false;
};

// 取消类的中断不是错误，不该弹提示。
const isIgnorable = reason =>
  reason?.code === 'ERR_CANCELED' ||
  reason?.name === 'CanceledError' ||
  reason?.name === 'AbortError' ||
  // 401 由登录态/权限处理，再弹一条只会干扰。
  // 有的 401 传到这里时 .response 已经丢了（中途被重新抛出/序列化），只剩一句
  // "Request failed with status code 401"，照原样弹出去用户完全看不懂，一并挡掉。
  reason?.response?.status === 401 ||
  /status code 401/i.test(String(reason?.message || reason || ''));

export const installGlobalErrorToast = app => {
  window.addEventListener('unhandledrejection', event => {
    const reason = event.reason;
    if (isIgnorable(reason)) return;

    const message = messageOf(reason);
    if (shouldSkip(message)) return;
    useAlert(message);
  });

  // 组件内同步异常（渲染/事件处理里抛出的）同样给提示，别只留白屏或空点击。
  const prevHandler = app.config.errorHandler;
  app.config.errorHandler = (err, instance, info) => {
    if (!isIgnorable(err)) {
      const message = messageOf(err);
      if (!shouldSkip(message)) useAlert(message);
    }
    if (prevHandler) prevHandler(err, instance, info);
    // eslint-disable-next-line no-console
    console.error('[app error]', err, info);
  };
};
