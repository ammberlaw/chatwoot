import { onMounted, onBeforeUnmount } from 'vue';
import Auth from 'dashboard/api/auth';

// 空闲自动登出:连续 8 小时无操作(鼠标/键盘/触摸/滚动)即调登出接口(服务端销毁会话)并跳登录页。
// 最后活动时间存 localStorage,跨标签页共享;笔记本休眠/切走后回来也会立即判定。
const IDLE_LIMIT_MS = 8 * 60 * 60 * 1000; // 8 小时
const ACTIVITY_KEY = 'cw_last_activity_at';
const WRITE_THROTTLE_MS = 30 * 1000; // 活动写入节流,避免 mousemove 高频写
const CHECK_INTERVAL_MS = 60 * 1000; // 每分钟检查一次
const ACTIVITY_EVENTS = [
  'mousedown',
  'keydown',
  'touchstart',
  'scroll',
  'mousemove',
];

export function useIdleLogout() {
  let checkTimer = null;
  let nextWriteAt = 0;
  let loggingOut = false;

  function readLastActivity() {
    const v = Number(window.localStorage.getItem(ACTIVITY_KEY) || 0);
    return v > 0 ? v : Date.now();
  }

  function markActivity() {
    const t = Date.now();
    if (t < nextWriteAt) return;
    nextWriteAt = t + WRITE_THROTTLE_MS;
    try {
      window.localStorage.setItem(ACTIVITY_KEY, String(t));
    } catch (e) {
      // localStorage 不可用时忽略
    }
  }

  function doLogout() {
    if (loggingOut) return;
    loggingOut = true;
    if (checkTimer) {
      clearInterval(checkTimer);
      checkTimer = null;
    }
    try {
      window.localStorage.removeItem(ACTIVITY_KEY);
    } catch (e) {
      // ignore
    }
    // Auth.logout 会删服务端会话 + 清缓存 + 跳登录页(window.location 重定向,页面随即卸载)
    Auth.logout().catch(() => {
      window.location = '/';
    });
  }

  function check() {
    if (Date.now() - readLastActivity() >= IDLE_LIMIT_MS) doLogout();
  }

  function onVisible() {
    if (!document.hidden) check();
  }

  function stop() {
    ACTIVITY_EVENTS.forEach(e => window.removeEventListener(e, markActivity));
    document.removeEventListener('visibilitychange', onVisible);
    window.removeEventListener('focus', onVisible);
    if (checkTimer) {
      clearInterval(checkTimer);
      checkTimer = null;
    }
  }

  onMounted(() => {
    markActivity(); // 进入即刷新一次,避免用上一次残留时间误判
    ACTIVITY_EVENTS.forEach(e =>
      window.addEventListener(e, markActivity, { passive: true })
    );
    document.addEventListener('visibilitychange', onVisible);
    window.addEventListener('focus', onVisible);
    checkTimer = window.setInterval(check, CHECK_INTERVAL_MS);
  });

  onBeforeUnmount(stop);
}
