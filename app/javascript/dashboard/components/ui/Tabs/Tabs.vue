<script setup>
import { ref, useTemplateRef, provide, computed, watch } from 'vue';
import { useElementSize } from '@vueuse/core';

const props = defineProps({
  index: {
    type: Number,
    default: 0,
  },
  border: {
    type: Boolean,
    default: true,
  },
});

const emit = defineEmits(['change']);

const tabsContainer = useTemplateRef('tabsContainer');
const tabsList = useTemplateRef('tabsList');

const { width: containerWidth } = useElementSize(tabsContainer);
const { width: listWidth } = useElementSize(tabsList);

const hasScroll = ref(false);

const activeIndex = computed({
  get: () => props.index,
  set: newValue => {
    emit('change', newValue);
  },
});

provide('activeIndex', activeIndex);
provide('updateActiveIndex', index => {
  activeIndex.value = index;
});

const computeScrollWidth = () => {
  if (tabsContainer.value && tabsList.value) {
    // 拿容器宽度判，别拿列表自己的 clientWidth：一旦溢出，列表会被 max-w-[calc(100%-64px)]
    // 砍掉 64px 给箭头腾位，再用这个缩水后的宽度去比，内容明明放得下也会一直判成溢出——
    // 箭头冒出来就再也收不回去，页签被挡掉一半（会话列表加到 4 个页签时实测踩到）。
    hasScroll.value =
      tabsList.value.scrollWidth > tabsContainer.value.clientWidth;
  }
};

const onScrollClick = direction => {
  if (tabsContainer.value && tabsList.value) {
    let scrollPosition = tabsList.value.scrollLeft;
    scrollPosition += direction === 'left' ? -100 : 100;
    tabsList.value.scrollTo({
      top: 0,
      left: scrollPosition,
      behavior: 'smooth',
    });
  }
};

// Watch for changes in element sizes with immediate execution
watch(
  [containerWidth, listWidth],
  () => {
    computeScrollWidth();
  },
  { immediate: true }
);
</script>

<template>
  <div
    ref="tabsContainer"
    class="flex"
    :class="[border && 'border-b border-b-n-weak']"
  >
    <button
      v-if="hasScroll"
      class="items-center rounded-none cursor-pointer flex h-auto justify-center min-w-8"
      @click="onScrollClick('left')"
    >
      <fluent-icon icon="chevron-left" :size="16" />
    </button>
    <ul
      ref="tabsList"
      class="border-r-0 border-l-0 border-t-0 flex min-w-[6.25rem] py-0 px-4 list-none mb-0"
      :class="
        hasScroll ? 'overflow-hidden py-0 px-1 max-w-[calc(100%-64px)]' : ''
      "
    >
      <slot />
    </ul>
    <button
      v-if="hasScroll"
      class="items-center rounded-none cursor-pointer flex h-auto justify-center min-w-8"
      @click="onScrollClick('right')"
    >
      <fluent-icon icon="chevron-right" :size="16" />
    </button>
  </div>
</template>
