<script setup>
// 空态：一枚灰色插画 + 一点品牌黄做点缀 + 标题 + 两行说明（可选）+ 一个主行动。
// 比一行「暂无数据」占面积，但空屏本来就有空间，而且它能顺手告诉用户「接下来能干嘛」。
defineProps({
  // 主体图形，传 icon class（i-ri-* / i-lucide-*）
  icon: { type: String, required: true },
  // 右上角那枚黄色徽标里的图标；不传就不画徽标
  badge: { type: String, default: '' },
  title: { type: String, required: true },
  desc: { type: [String, Array], default: () => [] },
  action: { type: String, default: '' },
});

defineEmits(['action']);
</script>

<template>
  <div class="flex flex-col items-center px-8 py-12 text-center">
    <div class="relative">
      <!-- 主体：大号灰色字形，压得很淡，不跟内容抢 -->
      <span class="block size-24 text-[color:var(--pb-ink-3)] opacity-40" :class="icon" />
      <!-- 徽标：唯一的一点颜色，落在右下角 -->
      <span
        v-if="badge"
        class="absolute grid rounded-full -right-1 bottom-1 size-9 place-items-center brand-fill shadow-[0_6px_16px_-8px_rgb(24_24_40/0.5)]"
      >
        <span class="size-5 text-black" :class="badge" />
      </span>
    </div>

    <p class="mt-6 text-[17px] font-semibold tracking-[-0.43px] text-[color:var(--pb-ink)]">
      {{ title }}
    </p>

    <template v-if="desc?.length">
      <p
        v-for="line in Array.isArray(desc) ? desc : [desc]"
        :key="line"
        class="mt-1 text-[14px] leading-5 text-[color:var(--pb-ink-3)]"
      >
        {{ line }}
      </p>
    </template>

    <button
      v-if="action"
      type="button"
      class="px-6 mt-6 rounded-full h-11 text-[15px] font-semibold bg-[color:var(--pb-ink)] text-[color:var(--pb-on-ink)] wt-press"
      @click="$emit('action')"
    >
      {{ action }}
    </button>
  </div>
</template>
