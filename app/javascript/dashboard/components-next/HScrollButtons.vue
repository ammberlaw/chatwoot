<script setup>
import { ref, reactive, computed, onMounted, onBeforeUnmount } from 'vue';

/**
 * 表格横向翻页的左右箭头，点一下翻一屏。
 *
 * 列多的表在屏幕上放不下，只能横着滚。但 macOS 的悬浮滚动条不滚不显示，
 * 鼠标用户也没有触控板的双指横滑——右边还有几列这件事，界面上一点线索都没有。
 * 底下那根细横条用鼠标又很难拖准（Amber 反馈过），所以给按钮。
 * 与 MesViewDialog 明细表里那对箭头是同一套交互。
 *
 * 用法：贴着滚动容器的**前面**放一个，它自己认后面那个兄弟节点：
 *
 *   <HScrollButtons />
 *   <div class="overflow-auto"><table …></table></div>
 *
 * 容器不在紧后面（或要指定别的元素）就传 target。
 * 按钮是绝对定位、不占布局空间，滚到头的那一侧自动隐藏；没有横向溢出时两个都不出现。
 */
const props = defineProps({
  target: { type: Object, default: null },
});

const rootRef = ref(null);
const canLeft = ref(false);
const canRight = ref(false);
// 按钮贴着容器可视区的左右内缘、竖直居中。位置按容器在定位父级里的偏移算，
// 这样同一个组件在整页表格和弹窗明细里都不用各写一套。
const geom = reactive({ top: 0, left: 0, right: 0 });

let scroller = null;
let resizeObserver = null;
let mutationObserver = null;

const measure = () => {
  if (!scroller) return;
  canLeft.value = scroller.scrollLeft > 1;
  // 留 1px 容差：缩放比例不是整数时 scrollLeft + clientWidth 到不了精确的 scrollWidth，
  // 严格相等会让「已经到底了」的右箭头一直亮着。
  canRight.value =
    scroller.scrollLeft + scroller.clientWidth < scroller.scrollWidth - 1;
  const style = getComputedStyle(scroller);
  const padLeft = parseFloat(style.paddingLeft) || 0;
  const padRight = parseFloat(style.paddingRight) || 0;
  // 竖直位置：矮容器（弹窗明细）取正中；整页表格很高，取正中会把按钮推到屏幕外，
  // 所以封顶在离顶部 96px——大致与表头齐平，一进页面就看得见。
  geom.top = scroller.offsetTop + Math.min(scroller.clientHeight / 2, 96);
  geom.left = scroller.offsetLeft + padLeft;
  geom.right = scroller.offsetLeft + scroller.clientWidth - padRight;
};

const leftStyle = computed(() => ({
  top: `${geom.top}px`,
  left: `${geom.left}px`,
}));
const rightStyle = computed(() => ({
  top: `${geom.top}px`,
  left: `${geom.right - 32}px`,
}));

// 翻一屏留一点重叠（0.8），不然翻过去完全看不到上一屏的列，对不上是哪一行。
const scrollPage = direction => {
  if (!scroller) return;
  scroller.scrollBy({
    left: direction * scroller.clientWidth * 0.8,
    behavior: 'smooth',
  });
};

onMounted(() => {
  scroller = props.target || rootRef.value?.nextElementSibling;
  if (!scroller) return;

  // 按钮要以容器的父级为定位参照；父级是 static 的话 offsetTop/offsetLeft 算出来
  // 就不是相对它的，按钮会飞到页面别处。
  const parent = scroller.parentElement;
  if (parent && getComputedStyle(parent).position === 'static') {
    parent.style.position = 'relative';
  }

  scroller.addEventListener('scroll', measure, { passive: true });
  resizeObserver = new ResizeObserver(measure);
  resizeObserver.observe(scroller);
  // 容器尺寸没变、里面的东西换了（「加载中…」换成表格、切页签、拖列宽）时
  // ResizeObserver 一声不响。挂载那一刻盯住某个子节点也没用——它会被整个换掉。
  // 所以盯整棵子树的结构变化，变了就重新量。
  mutationObserver = new MutationObserver(measure);
  mutationObserver.observe(scroller, { childList: true, subtree: true });
  measure();
});

onBeforeUnmount(() => {
  scroller?.removeEventListener('scroll', measure);
  resizeObserver?.disconnect();
  mutationObserver?.disconnect();
});
</script>

<template>
  <div ref="rootRef" class="contents">
    <button
      v-show="canLeft"
      type="button"
      class="absolute z-20 flex items-center justify-center border rounded-full shadow-md size-8 -translate-y-1/2 border-n-weak bg-n-solid-1 text-n-slate-11 hover:text-n-slate-12"
      :style="leftStyle"
      title="向左翻一屏"
      @click="scrollPage(-1)"
    >
      <span class="i-lucide-chevron-left size-4" />
    </button>
    <button
      v-show="canRight"
      type="button"
      class="absolute z-20 flex items-center justify-center border rounded-full shadow-md size-8 -translate-y-1/2 border-n-weak bg-n-solid-1 text-n-slate-11 hover:text-n-slate-12"
      :style="rightStyle"
      title="向右翻一屏"
      @click="scrollPage(1)"
    >
      <span class="i-lucide-chevron-right size-4" />
    </button>
  </div>
</template>
