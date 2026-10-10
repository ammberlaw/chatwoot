<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';

// 单据附图的看图层：点缩略图在页内放大，不另开浏览器标签页。
//
// ⚠️ 为什么不用 Teleport 到 body：这玩意儿多数时候开在 <dialog>.showModal() 里，
// 原生 dialog 在**顶层**（top layer），teleport 到 body 的浮层会被它整个盖住
// （点了像没反应，见 [[wintouch-dialog-popover-teleport-toplayer]]）。
// 就地渲染 + position:fixed 则跟着 dialog 一起在顶层，既不会被盖、又照样铺满视口。
// 代价是祖先若有 transform/filter 会变成定位基准——这几个单据弹窗没有，已实测。
const images = ref([]);
const index = ref(0);
const isOpen = ref(false);

const current = computed(() => images.value[index.value] || null);
const hasMany = computed(() => images.value.length > 1);

const open = (list, i = 0) => {
  images.value = Array.isArray(list) ? list : [list];
  index.value = Math.max(0, Math.min(i, images.value.length - 1));
  isOpen.value = true;
};
const close = () => {
  isOpen.value = false;
};
const step = n => {
  if (!images.value.length) return;
  index.value = (index.value + n + images.value.length) % images.value.length;
};

// Esc 关看图层而不是关掉整张单：捕获阶段拦下，别让它冒到 <dialog> 的默认行为。
// 左右方向键翻图（一行挂好几张时比来回点快）。
const onKeydown = e => {
  if (!isOpen.value) return;
  if (e.key === 'Escape') {
    e.preventDefault();
    e.stopPropagation();
    close();
  } else if (e.key === 'ArrowLeft') {
    step(-1);
  } else if (e.key === 'ArrowRight') {
    step(1);
  }
};
onMounted(() => document.addEventListener('keydown', onKeydown, true));
onBeforeUnmount(() => document.removeEventListener('keydown', onKeydown, true));

defineExpose({ open, close });
</script>

<template>
  <!-- 根上用 v-show 不用 v-if：组件只有这一个根，v-if 会让它在关闭时没有根节点
       （vue/no-root-v-if）。display:none 期间也不吃点击，效果一样。 -->
  <div
    v-show="isOpen && current"
    class="fixed inset-0 z-[9999] flex flex-col items-center justify-center gap-3 p-6 bg-black/80"
    @click.self="close"
  >
    <img
      :src="current?.url"
      :alt="current?.name || current?.filename || ''"
      class="object-contain max-w-full rounded-lg shadow-2xl max-h-[78vh]"
    />
    <div class="flex items-center gap-3 text-sm text-white/90">
      <button
        v-if="hasMany"
        type="button"
        class="flex items-center justify-center rounded-full size-8 bg-white/15 hover:bg-white/25"
        @click.stop="step(-1)"
      >
        <span class="i-lucide-chevron-left size-4" />
      </button>
      <span class="max-w-[50vw] truncate">
        {{ current?.name || current?.filename || '附图' }}
        <template v-if="hasMany">
          （{{ index + 1 }}/{{ images.length }}）
        </template>
      </span>
      <button
        v-if="hasMany"
        type="button"
        class="flex items-center justify-center rounded-full size-8 bg-white/15 hover:bg-white/25"
        @click.stop="step(1)"
      >
        <span class="i-lucide-chevron-right size-4" />
      </button>
    </div>
    <!-- 关闭钮放**左**上角：这层是盖在 <dialog> 上的（fixed 的定位基准被弹窗的
         backdrop-filter 接管了，所以只铺满弹窗而不是整屏），右上角正好压着弹窗自己的 ✕，
         两个叉叠在一起分不清点哪个。 -->
    <button
      type="button"
      class="absolute flex items-center justify-center text-white rounded-full top-4 left-4 size-9 bg-white/15 hover:bg-white/25"
      title="关闭（Esc）"
      @click.stop="close"
    >
      <span class="i-lucide-x size-5" />
    </button>
  </div>
</template>
