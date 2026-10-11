<script setup>
import { isVNode, computed } from 'vue';
import Icon from 'next/icon/Icon.vue';
import Policy from 'dashboard/components/policy.vue';
import { useSidebarContext } from './provider';
import SidebarUnreadBadge from './SidebarUnreadBadge.vue';

const props = defineProps({
  label: { type: String, required: true },
  to: { type: [String, Object], required: true },
  icon: { type: [String, Object], default: null },
  active: { type: Boolean, default: false },
  component: { type: Function, default: null },
  badgeCount: { type: [Number, String], default: 0 },
  // 悬浮说明：判定规则不直观的入口（如流失预警）挂一段解释，省得业务猜。
  hint: { type: String, default: '' },
  hideTreeLine: { type: Boolean, default: false },
  thinTreeLine: { type: Boolean, default: false },
});

const { resolvePermissions, resolveFeatureFlag } = useSidebarContext();

const shouldRenderComponent = computed(() => {
  return typeof props.component === 'function' || isVNode(props.component);
});

// 悬浮说明：默认的单行 tooltip 会拉成横穿页面的一条，这里限宽换行。
// html 由 floating-vue 渲染，用 Tailwind class（与客户星级悬浮同款做法）。
const hintTooltip = computed(() =>
  props.hint
    ? {
        content: `<div class="w-72 text-left leading-relaxed"><div class="font-semibold mb-1">${props.label}</div>${props.hint}</div>`,
        html: true,
      }
    : undefined
);

// Tree-line connector per leaf: vertical line (::before) + rounded elbow on the
// last child (::after). Logical props (start / border-s / rounded-es)
const TREE_CONNECTOR =
  "child-item before:content-[''] before:absolute before:start-0 before:w-0.5 before:h-full before:bg-n-slate-4 first:before:rounded-t last:before:h-1/5 last:after:content-[''] last:after:absolute last:after:start-0 last:after:bottom-[calc(50%_-_2px)] last:after:h-3 last:after:w-2.5 last:after:border-b-2 last:after:border-s-2 last:after:rounded-es last:after:border-n-slate-4";
</script>

<template>
  <Policy
    :permissions="resolvePermissions(to)"
    :feature-flag="resolveFeatureFlag(to)"
    as="li"
    data-sidebar-leaf
    class="py-0.5 ps-2 ms-3 relative text-n-slate-11 min-w-0"
    :class="{
      [TREE_CONNECTOR]: !hideTreeLine,
      'before:!w-px last:after:!border-b last:after:!border-s':
        !hideTreeLine && thinTreeLine,
    }"
  >
    <component
      :is="to ? 'router-link' : 'div'"
      :to="to"
      v-tooltip.right="hintTooltip"
      :data-sidebar-active="active"
      :title="hint ? undefined : label"
      class="flex h-9 items-center gap-3 px-3 py-1.5 rounded-xl ltr:hover:bg-gradient-to-r rtl:hover:bg-gradient-to-l from-transparent via-n-slate-3/70 to-n-slate-3/70 group min-w-0"
      :class="{
        'text-white bg-n-iris-9 shadow-sm shadow-n-iris-9/30 hover:bg-none active':
          active,
      }"
    >
      <component
        :is="component"
        v-if="shouldRenderComponent"
        v-bind="{ label, icon, active, badgeCount }"
      />
      <template v-else>
        <span v-if="icon" class="size-4 grid place-content-center rounded-full">
          <Icon :icon="icon" class="size-4 inline-block" />
        </span>
        <div class="flex-1 truncate min-w-0 text-sm">{{ label }}</div>
        <SidebarUnreadBadge :count="badgeCount" />
      </template>
    </component>
  </Policy>
</template>
