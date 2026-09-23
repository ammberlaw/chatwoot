<script setup>
// iOS inset grouped 列表的一行。分隔线画在内容区上（缩进到标题起点），
// 由 .ios-group 统一把最后一行的线去掉。
defineProps({
  title: { type: String, default: '' },
  subtitle: { type: String, default: '' },
  value: { type: String, default: '' },
  chevron: { type: Boolean, default: false },
  tappable: { type: Boolean, default: false },
});
</script>

<template>
  <component
    :is="tappable ? 'button' : 'div'"
    :type="tappable ? 'button' : undefined"
    class="flex items-center w-full pl-4 text-left"
    :class="tappable ? 'active:bg-[color:var(--pb-fill)]' : ''"
  >
    <slot name="leading" />
    <div class="flex items-center flex-1 min-w-0 gap-3 py-2.5 pr-4 ios-sep">
      <div class="flex-1 min-w-0">
        <slot>
          <div class="truncate ios-body text-[color:var(--pb-ink)]">{{ title }}</div>
          <div v-if="subtitle" class="mt-0.5 truncate ios-subhead text-[color:var(--pb-ink-2)]">
            {{ subtitle }}
          </div>
        </slot>
      </div>
      <slot name="trailing">
        <span v-if="value" class="flex-none ios-body text-[color:var(--pb-ink-2)]">{{ value }}</span>
      </slot>
      <span
        v-if="chevron"
        class="flex-none size-[18px] text-[color:var(--pb-ink-3)] i-lucide-chevron-right"
      />
    </div>
  </component>
</template>
