<script setup>
import { computed } from 'vue';

const props = defineProps({
  node: { type: Object, required: true },
});

// 人员节点（总经理/副总/董事长/总裁）与「××中心」节点用不同视觉层级。
const isPerson = computed(() =>
  /总经理|副总|董事长|总裁/.test(props.node.name)
);
const isCenter = computed(() => /中心$/.test(props.node.name));

// 「总经理（陈云钢）」拆成职位 + 姓名两行。
const personParts = computed(() => {
  const match = props.node.name.match(/^(.+?)（(.+)）$/);
  return match ? { role: match[1], person: match[2] } : null;
});

const boxClass = computed(() => {
  if (isPerson.value)
    return 'bg-n-iris-9 text-white shadow-md shadow-n-iris-9/25';
  if (isCenter.value)
    return 'bg-n-iris-3 border border-n-iris-6 text-n-iris-12 font-medium';
  if (props.node.children.length)
    return 'bg-n-solid-1 border border-n-weak text-n-slate-12 shadow-sm';
  return 'bg-n-alpha-1 border border-n-weak text-n-slate-11';
});
</script>

<template>
  <div class="flex flex-col items-center">
    <div
      class="px-4 py-2 text-center rounded-xl whitespace-nowrap transition-shadow [.theme-classic_&]:relative [.theme-classic_&]:min-w-[148px] [.theme-classic_&]:px-5 [.theme-classic_&]:py-4 [.theme-classic_&]:rounded-2xl [.theme-classic_&]:text-left [.theme-classic_&]:border [.theme-classic_&]:transition-all [.theme-classic_&]:duration-200 [.theme-classic_&]:hover:-translate-y-0.5 [.theme-classic_&]:hover:shadow-lg"
      :class="[boxClass, node.children.length ? 'text-[13px]' : 'text-xs',
        isPerson
          ? '[.theme-classic_&]:bg-[#303238] [.theme-classic_&]:border-[#41444b] [.theme-classic_&]:text-white [.theme-classic_&]:shadow-[0_8px_20px_-8px_rgba(27,30,36,0.5)]'
          : isCenter
            ? '[.theme-classic_&]:bg-[#fff3c6] [.theme-classic_&]:border-[#ead490] [.theme-classic_&]:text-[#53461f] [.theme-classic_&]:shadow-[0_6px_18px_-8px_rgba(129,106,43,0.25)]'
            : '[.theme-classic_&]:bg-white [.theme-classic_&]:border-[#e1e4e8] [.theme-classic_&]:text-[#41464e] [.theme-classic_&]:shadow-[0_6px_18px_-8px_rgba(40,50,65,0.18)]']"
    >
      <template v-if="isPerson && personParts">
        <p class="text-[13px] font-semibold leading-tight [.theme-classic_&]:text-heading-3">
          {{ personParts.role }}
        </p>
        <p class="mt-0.5 text-[11px] leading-tight opacity-80 [.theme-classic_&]:mt-2 [.theme-classic_&]:text-label-small">
          {{ personParts.person }}
        </p>
      </template>
      <template v-else>
        {{ node.name }}
        <span
          v-if="node.memberCount"
          class="inline-flex items-center px-1.5 py-px ml-1 text-[10px] leading-none rounded-full align-middle [.theme-classic_&]:ml-3 [.theme-classic_&]:min-w-6 [.theme-classic_&]:h-6 [.theme-classic_&]:justify-center [.theme-classic_&]:text-label-small"
          :class="
            isCenter
              ? 'bg-n-iris-5 text-n-iris-12'
              : isPerson ? 'bg-n-alpha-2 text-n-slate-11 [.theme-classic_&]:bg-white/15 [.theme-classic_&]:text-white/80' : 'bg-n-alpha-2 text-n-slate-11 [.theme-classic_&]:bg-[#f0f2f5] [.theme-classic_&]:text-[#747d8a]'
          "
        >
          {{ node.memberCount }}
        </span>
      </template>
    </div>

    <template v-if="node.children.length">
      <div aria-hidden="true" class="w-px h-5 bg-n-slate-6 [.theme-classic_&]:h-8 [.theme-classic_&]:bg-[#cbd1d9]" />
      <div class="flex items-start">
        <div
          v-for="(child, index) in node.children"
          :key="child.id"
          class="flex flex-col items-center"
        >
          <div aria-hidden="true" class="flex self-stretch">
            <div class="flex-1 h-px" :class="index > 0 ? 'bg-n-slate-6 [.theme-classic_&]:bg-[#cbd1d9]' : ''" />
            <div
              class="flex-1 h-px"
              :class="index < node.children.length - 1 ? 'bg-n-slate-6 [.theme-classic_&]:bg-[#cbd1d9]' : ''"
            />
          </div>
          <div aria-hidden="true" class="w-px h-5 bg-n-slate-6 [.theme-classic_&]:h-8 [.theme-classic_&]:bg-[#cbd1d9]" />
          <div class="px-2 [.theme-classic_&]:px-3">
            <OrgChartNode :node="child" />
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
