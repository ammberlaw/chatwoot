<script setup>
import { ref, onMounted, onBeforeUnmount } from 'vue';
import { Capacitor } from '@capacitor/core';

// 下拉刷新。要点（按 Apple 的手势规范）：
//  · 拖动期间 1:1 跟手，不是等松手才动
//  · 越往下拉阻力越大（rubber-band），不是线性拉到天上
//  · 松手用弹簧回弹，且中途可以再抓住（重新按下时从当前实际位移接管）
const props = defineProps({
  disabled: { type: Boolean, default: false },
  contentClass: { type: String, default: '' },
});
const emit = defineEmits(['refresh']);

const THRESHOLD = 72; // 触发刷新的下拉距离
const REST = 56; // 刷新中指示器停留的位置

const scroller = ref(null);
const y = ref(0);
const refreshing = ref(false);
const animating = ref(false);

let startY = 0;
let pulling = false;
let reduceMotion = false;

// 越过边界后阻力递增：同样的手指位移，元素跟得越来越少
const rubberband = (overshoot, dimension, c = 0.55) =>
  (overshoot * dimension * c) / (dimension + c * Math.abs(overshoot));

const settle = to => {
  animating.value = true;
  y.value = to;
};

const onTouchStart = e => {
  if (props.disabled || refreshing.value) return;
  // 只有已经在顶部才接管，否则交给正常滚动
  if ((scroller.value?.scrollTop || 0) > 0) return;
  // 中断进行中的回弹：从当前真实位移接管，避免跳一下
  animating.value = false;
  startY = e.touches[0].clientY - y.value;
  pulling = true;
};

const onTouchMove = e => {
  if (!pulling) return;
  const raw = e.touches[0].clientY - startY;
  if (raw <= 0) {
    // 往上推就交还给滚动
    y.value = 0;
    pulling = false;
    return;
  }
  if ((scroller.value?.scrollTop || 0) > 0) {
    pulling = false;
    return;
  }
  // 阻止 webview 自己的橡皮筋，否则两套位移会打架
  if (e.cancelable) e.preventDefault();
  y.value = rubberband(raw, window.innerHeight);
};

const onTouchEnd = async () => {
  if (!pulling) return;
  pulling = false;
  if (y.value < THRESHOLD) {
    settle(0);
    return;
  }
  settle(REST);
  refreshing.value = true;
  if (Capacitor.isNativePlatform()) {
    const { Haptics, ImpactStyle } = await import('@capacitor/haptics');
    await Haptics.impact({ style: ImpactStyle.Light }).catch(() => {});
  }
  try {
    await Promise.resolve(emit('refresh'));
  } finally {
    // 给一点最短停留，否则秒回弹会让人以为没刷新
    setTimeout(() => {
      refreshing.value = false;
      settle(0);
    }, 320);
  }
};

onMounted(() => {
  reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const el = scroller.value;
  // touchmove 必须非 passive，否则 preventDefault 无效
  el.addEventListener('touchstart', onTouchStart, { passive: true });
  el.addEventListener('touchmove', onTouchMove, { passive: false });
  el.addEventListener('touchend', onTouchEnd, { passive: true });
  el.addEventListener('touchcancel', onTouchEnd, { passive: true });
});

onBeforeUnmount(() => {
  const el = scroller.value;
  if (!el) return;
  el.removeEventListener('touchstart', onTouchStart);
  el.removeEventListener('touchmove', onTouchMove);
  el.removeEventListener('touchend', onTouchEnd);
  el.removeEventListener('touchcancel', onTouchEnd);
});

defineExpose({ scroller });
</script>

<template>
  <div
    ref="scroller"
    class="relative flex-1 min-h-0 overflow-y-auto overscroll-contain"
  >
    <div
      :style="{
        transform: `translate3d(0, ${y}px, 0)`,
        transition: animating && !reduceMotion
          ? 'transform 0.4s cubic-bezier(0.32, 0.72, 0, 1)'
          : 'none',
      }"
      @transitionend="animating = false"
    >
      <!-- 指示器挂在内容上方，跟着一起位移，所以下拉时是「从顶上被拽出来」 -->
      <div
        class="absolute inset-x-0 grid pointer-events-none -top-11 h-11 place-items-center"
      >
        <span
          class="size-5 text-[color:var(--pb-ink-3)] i-lucide-refresh-cw"
          :class="refreshing ? 'animate-spin' : ''"
          :style="
            refreshing
              ? undefined
              : {
                  opacity: Math.min(1, y / THRESHOLD),
                  transform: `rotate(${(y / THRESHOLD) * 270}deg)`,
                }
          "
        />
      </div>
      <div :class="contentClass">
        <slot />
      </div>
    </div>
  </div>
</template>
