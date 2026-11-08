<script setup>
import { computed, useTemplateRef } from 'vue';
import { useWindowSize, useElementBounding } from '@vueuse/core';

defineProps({
  option: {
    type: Object,
    default: () => {},
  },
  subMenuAvailable: {
    type: Boolean,
    default: true,
  },
});

const menuRef = useTemplateRef('menuRef');
const { width: windowWidth, height: windowHeight } = useWindowSize();
const { bottom, right } = useElementBounding(menuRef);

// Vertical position
const verticalPosition = computed(() => {
  const SUBMENU_HEIGHT = 240; // 15rem in pixels
  const spaceBelow = windowHeight.value - bottom.value;
  return spaceBelow < SUBMENU_HEIGHT ? 'bottom-0' : 'top-0';
});

// Horizontal position
const horizontalPosition = computed(() => {
  const SUBMENU_WIDTH = 240;
  const spaceRight = windowWidth.value - right.value;
  return spaceRight < SUBMENU_WIDTH ? 'right-full' : 'left-full';
});

const submenuPosition = computed(() => [
  verticalPosition.value,
  horizontalPosition.value,
]);
</script>

<template>
  <div
    ref="menuRef"
    class="text-white/90 menu-with-submenu min-width-calc w-full px-2 flex items-center h-8 rounded-xl relative justify-between hover:bg-white/10 cursor-pointer"
    :class="!subMenuAvailable ? 'opacity-50 cursor-not-allowed' : ''"
  >
    <div class="flex items-center h-4">
      <fluent-icon :icon="option.icon" size="14" class="menu-icon" />
      <p class="my-0 mx-2 text-label-small">{{ option.label }}</p>
    </div>
    <fluent-icon icon="chevron-right" size="12" />
    <div
      v-if="subMenuAvailable"
      class="submenu border shadow-xl rounded-2xl border-white/15 bg-[#212226]/95 backdrop-blur-2xl backdrop-saturate-150 shadow-black/25 p-1.5 absolute hidden max-h-[15rem] overflow-y-auto overflow-x-hidden cursor-pointer"
      :class="submenuPosition"
    >
      <slot />
    </div>
  </div>
</template>

<style scoped lang="scss">
.menu-with-submenu {
  min-width: calc(6.25rem * 2);

  &:hover {
    .submenu {
      @apply block;
    }
  }
}
</style>
