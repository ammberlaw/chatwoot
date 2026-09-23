<script setup>
import { ref } from 'vue';

// 用原生 <input type="file"> 而不是 Camera 插件：iOS 点它弹出的系统面板本身就含
// 「拍照 / 照片图库 / 浏览」三项，一个控件覆盖三种来源，也不用额外申请权限。
const props = defineProps({
  modelValue: { type: Array, default: () => [] },
  label: { type: String, default: '附件' },
});
const emit = defineEmits(['update:modelValue']);

const inputRef = ref(null);

const onPick = event => {
  const picked = Array.from(event.target.files || []);
  if (picked.length) emit('update:modelValue', [...props.modelValue, ...picked]);
  // 清空原生 input，否则连续选同一个文件不触发 change
  event.target.value = '';
};

const remove = index =>
  emit(
    'update:modelValue',
    props.modelValue.filter((_, i) => i !== index)
  );

const size = bytes =>
  bytes >= 1048576
    ? `${(bytes / 1048576).toFixed(1)} MB`
    : `${Math.max(1, Math.round(bytes / 1024))} KB`;
</script>

<template>
  <div class="flex flex-col gap-1.5">
    <span class="text-xs font-medium text-[color:var(--pb-ink-2)]">{{ label }}</span>

    <ul v-if="modelValue.length" class="flex flex-col gap-2">
      <li
        v-for="(f, i) in modelValue"
        :key="`${f.name}-${i}`"
        class="flex items-center gap-3 p-3 wt-card"
      >
        <span class="flex-none size-4 text-[color:var(--pb-ink-3)] i-lucide-paperclip" />
        <span class="flex-1 text-sm truncate text-[color:var(--pb-ink)]">{{ f.name }}</span>
        <span class="flex-none text-xs text-[color:var(--pb-ink-3)]">{{ size(f.size) }}</span>
        <button
          type="button"
          :aria-label="`移除 ${f.name}`"
          class="grid flex-none rounded-full size-7 place-items-center text-[color:var(--pb-ink-3)] active:bg-[color:var(--pb-fill)]"
          @click="remove(i)"
        >
          <span class="size-4 i-lucide-x" />
        </button>
      </li>
    </ul>

    <input ref="inputRef" type="file" multiple class="hidden" @change="onPick" />
    <button type="button" class="self-start wt-btn-ghost" @click="inputRef.click()">
      <span class="mr-1.5 size-4 i-lucide-plus" />
      添加附件
    </button>
  </div>
</template>
