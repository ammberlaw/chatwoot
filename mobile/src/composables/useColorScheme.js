import { ref } from 'vue';
import { Capacitor } from '@capacitor/core';

// 跟随系统深浅色。主仓的色板是用 .dark 类切换的（不是 prefers-color-scheme 媒体查询），
// 所以这里只负责把类挂到 <html> 上，配色本身完全复用主仓那一份，不在 App 里另造。
const isDark = ref(false);

export function useColorScheme() {
  const apply = async matches => {
    isDark.value = matches;
    document.documentElement.classList.toggle('dark', matches);
    if (!Capacitor.isNativePlatform()) return;
    // 状态栏文字要跟着反色，否则深色下黑字压在深色背景上看不见
    const { StatusBar, Style } = await import('@capacitor/status-bar');
    await StatusBar.setStyle({ style: matches ? Style.Dark : Style.Light }).catch(() => {});
  };

  const init = () => {
    // 经典灰：与网页版同一套主题（index.html 里已经先挂过一次防白闪，这里兜底）
    document.documentElement.classList.add('theme-classic');
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    apply(mq.matches);
    mq.addEventListener('change', e => apply(e.matches));
  };

  return { isDark, init };
}
