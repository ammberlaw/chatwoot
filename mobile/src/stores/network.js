import { defineStore } from 'pinia';
import { ref } from 'vue';
import { Network } from '@capacitor/network';
import { App as CapApp } from '@capacitor/app';

// 离线判定不只依赖 networkStatusChange 事件——该事件在部分机型/场景下不触发。
// 三重信号：插件状态 + App 回前台时复查 + 请求层的网络错误。
export const useNetworkStore = defineStore('network', () => {
  const online = ref(true);

  const refresh = async () => {
    try {
      const s = await Network.getStatus();
      online.value = s.connected;
    } catch {
      /* 插件不可用（浏览器）时保持当前值 */
    }
  };

  // 请求层是最可信的信号：拿不到响应就是不可用，拿到了就是可用。
  // 不在这里调 refresh()——插件状态会把刚设的值覆盖掉（navigator.onLine 常年为 true）。
  const reportRequestFailure = () => {
    online.value = false;
  };
  const reportRequestSuccess = () => {
    online.value = true;
  };

  const init = async () => {
    await refresh();
    await Network.addListener('networkStatusChange', s => {
      online.value = s.connected;
    }).catch(() => {});
    // 从后台切回前台时复查（切飞行模式常发生在 App 不在前台时）
    await CapApp.addListener('appStateChange', ({ isActive }) => {
      if (isActive) refresh();
    }).catch(() => {});
  };

  return { online, init, refresh, reportRequestFailure, reportRequestSuccess };
});
