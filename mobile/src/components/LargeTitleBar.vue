<script setup>
import { ref, computed, watch, nextTick, onMounted, onActivated, onBeforeUnmount } from 'vue';

// iOS 的大标题栏：页面顶部是超大标题，往上滚时标题缩进一条半透磨砂条里，
// 内容从磨砂条下面透过去。这是 iOS 辨识度最高的一个行为——没有它，
// 再怎么调颜色都还是"网页套了个壳"。
//
// 实现上不用监听 window：Capacitor 里滚动发生在页面自己的容器上，
// 所以由父组件把容器 ref 传进来。
const props = defineProps({
  title: { type: String, required: true },
  // 滚动容器（.overflow-y-auto 那个元素）
  scroller: { type: Object, default: null },
  // 大标题滚过多少像素后完全收起
  range: { type: Number, default: 52 },
});

const y = ref(0);
let el = null;

// 0 = 大标题完全展开，1 = 完全收进顶栏
const t = computed(() => Math.min(1, Math.max(0, y.value / props.range)));

const onScroll = () => {
  y.value = el ? el.scrollTop : 0;
};

const attach = () => {
  const next = props.scroller?.value || props.scroller;
  if (next === el) return;
  el?.removeEventListener('scroll', onScroll);
  el = next;
  el?.addEventListener('scroll', onScroll, { passive: true });
  onScroll();
};

// 子组件的 onMounted 早于父组件模板 ref 赋值，所以不能只在挂载时取一次，
// 要盯着 prop 变化。
watch(() => props.scroller, attach, { flush: 'post' });
onMounted(() => nextTick(attach));
onActivated(() => nextTick(attach));
onBeforeUnmount(() => el?.removeEventListener('scroll', onScroll));

defineExpose({ attach });
</script>

<template>
  <!-- 磨砂条：不占布局高度，内容从它下面滚过去 -->
  <div
    class="absolute inset-x-0 top-0 z-20 pointer-events-none"
    :style="{
      opacity: t,
      backdropFilter: `blur(${(18 * t).toFixed(1)}px) saturate(180%)`,
      WebkitBackdropFilter: `blur(${(18 * t).toFixed(1)}px) saturate(180%)`,
      backgroundColor: `rgb(var(--pb-bar-rgb) / ${0.72 * t})`,
    }"
  >
    <div class="pt-safeTop">
      <div class="flex items-center justify-center h-11 px-4">
        <span
          class="text-[17px] font-semibold leading-[22px] tracking-[-0.43px] truncate text-[color:var(--pb-ink)]"
          :style="{ opacity: t }"
        >
          {{ title }}
        </span>
      </div>
      <!-- 顶栏底部那道发丝线，只在收起后出现 -->
      <div
        class="h-[0.5px] bg-[color:var(--pb-sep)]"
        :style="{ opacity: t }"
      />
    </div>
  </div>
</template>
