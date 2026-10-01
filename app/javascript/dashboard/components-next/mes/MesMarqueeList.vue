<script setup>
import { computed } from 'vue';

/**
 * 看板告警列表的纵向轮播窗口。
 *
 * 条数超过一屏就只留固定高度的窗口自动滚，不然七八条就把下面的图表顶出屏幕。
 * 内容复制两份首尾相接实现无缝循环——所以插槽里的行必须**等高且列表不留 gap**，
 * 否则 -50% 的落点会差半个间距，循环处会跳一下。
 */
const props = defineProps({
  /** 条数。≤ rows 时不滚，原样铺开。 */
  count: { type: Number, default: 0 },
  /** 窗口显示几行（每行 1.75rem）。 */
  rows: { type: Number, default: 3 },
});

const scrolls = computed(() => props.count > props.rows);

// 条数越多走得越慢，否则刷得人看不清。
// 类名必须是静态字符串——Tailwind 的 JIT 扫不到拼接出来的类名。
const speed = computed(() => {
  if (props.count > 12) return 'animate-marquee-y-slow';
  if (props.count > 6) return 'animate-marquee-y';
  return 'animate-marquee-y-fast';
});

// 窗口高度同样要静态类名。
const HEIGHTS = {
  2: 'h-[3.5rem]',
  3: 'h-[5.25rem]',
  4: 'h-[7rem]',
  5: 'h-[8.75rem]',
};
const windowHeight = computed(() => HEIGHTS[props.rows] || HEIGHTS[3]);
</script>

<template>
  <!-- 上下渐隐：不加的话滚动时文字被硬切成半行，看着像渲染坏了。 -->
  <div
    class="overflow-hidden"
    :class="
      scrolls
        ? `${windowHeight} [mask-image:linear-gradient(to_bottom,transparent,black_14%,black_86%,transparent)]`
        : ''
    "
  >
    <div
      :class="
        scrolls
          ? `${speed} hover:[animation-play-state:paused] motion-reduce:animate-none`
          : ''
      "
    >
      <div v-for="pass in scrolls ? 2 : 1" :key="`pass-${pass}`">
        <slot />
      </div>
    </div>
  </div>
</template>
