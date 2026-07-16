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
      class="px-4 py-2 text-center rounded-xl whitespace-nowrap transition-shadow"
      :class="[boxClass, node.children.length ? 'text-[13px]' : 'text-xs']"
    >
      <template v-if="isPerson && personParts">
        <p class="text-[13px] font-semibold leading-tight">
          {{ personParts.role }}
        </p>
        <p class="mt-0.5 text-[11px] leading-tight opacity-80">
          {{ personParts.person }}
        </p>
      </template>
      <template v-else>
        {{ node.name }}
        <span
          v-if="node.memberCount"
          class="inline-flex items-center px-1.5 py-px ml-1 text-[10px] leading-none rounded-full align-middle"
          :class="
            isCenter
              ? 'bg-n-iris-5 text-n-iris-12'
              : 'bg-n-alpha-2 text-n-slate-11'
          "
        >
          {{ node.memberCount }}
        </span>
      </template>
    </div>

    <template v-if="node.children.length">
      <div aria-hidden="true" class="w-px h-5 bg-n-slate-6" />
      <div class="flex items-start">
        <div
          v-for="(child, index) in node.children"
          :key="child.id"
          class="flex flex-col items-center"
        >
          <div aria-hidden="true" class="flex self-stretch">
            <div class="flex-1 h-px" :class="index > 0 ? 'bg-n-slate-6' : ''" />
            <div
              class="flex-1 h-px"
              :class="index < node.children.length - 1 ? 'bg-n-slate-6' : ''"
            />
          </div>
          <div aria-hidden="true" class="w-px h-5 bg-n-slate-6" />
          <div class="px-2">
            <OrgChartNode :node="child" />
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
