<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import {
  useDocumentVisibility,
  useIntersectionObserver,
  usePreferredReducedMotion,
} from '@vueuse/core';

const props = defineProps({
  image: { type: String, required: true },
  animated: { type: Boolean, default: false },
});
const root = ref(null);
const flowers = ref(null);
const stars = ref([]);
const visible = ref(false);
const reducedMotion = usePreferredReducedMotion();
const documentVisibility = useDocumentVisibility();
const shouldPlay = computed(
  () =>
    props.animated &&
    visible.value &&
    reducedMotion.value !== 'reduce' &&
    documentVisibility.value === 'visible'
);
useIntersectionObserver(root, ([entry]) => {
  visible.value = entry.isIntersecting;
});

let animations = [];
const stop = () => {
  animations.forEach(animation => animation.cancel());
  animations = [];
};
const play = () => {
  stop();
  if (!shouldPlay.value || !flowers.value) return;
  animations.push(
    flowers.value.animate(
      [
        { transform: 'translateX(-0.3%) rotate(-0.65deg)' },
        { transform: 'translateX(0.3%) rotate(0.65deg)' },
        { transform: 'translateX(-0.3%) rotate(-0.65deg)' },
      ],
      {
        duration: 5200,
        iterations: Infinity,
        easing: 'cubic-bezier(0.77, 0, 0.175, 1)',
      }
    )
  );
  stars.value.forEach((star, index) => {
    animations.push(
      star.animate([{ opacity: 0 }, { opacity: 0.7 }, { opacity: 0 }], {
        duration: 3200 + index * 600,
        delay: index * 900,
        iterations: Infinity,
        easing: 'ease',
      })
    );
  });
};
watch([shouldPlay, () => props.image], play, { flush: 'post' });
onBeforeUnmount(stop);
</script>

<template>
  <span ref="root" class="relative block" aria-hidden="true">
    <img
      :src="image"
      alt=""
      draggable="false"
      class="block h-full w-full object-contain"
      :class="animated ? '[clip-path:inset(39%_0_0_0)]' : ''"
    />
    <template v-if="animated">
      <img
        ref="flowers"
        :src="image"
        alt=""
        draggable="false"
        class="pointer-events-none absolute inset-0 h-full w-full origin-[50%_39%] object-contain [clip-path:inset(0_0_61%_0)]"
        @load="play"
      />
      <span
        v-for="position in [
          'left-[23%] top-[20%]',
          'right-[13%] top-[37%]',
          'left-[47%] top-[12%]',
        ]"
        :key="position"
        ref="stars"
        class="pointer-events-none absolute size-0.5 rounded-full bg-amber-100 opacity-0"
        :class="position"
      />
    </template>
  </span>
</template>
