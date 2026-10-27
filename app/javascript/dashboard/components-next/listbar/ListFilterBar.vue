<script setup>
import { ref, watch, onBeforeUnmount } from 'vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

// 列表页统一筛选条：左边关键字搜索，右边插槽放各页自己的下拉。
// 以前每页手搓一条，高度、间距、占位文案全不一样；收口到这里，全站长一个样。
// 搜索停手 400ms 自动查，回车也查——不另外放「查询」按钮，少一次点击。
const props = defineProps({
  placeholder: { type: String, default: '搜索…' },
  // 有筛选条件正在生效时才显示「重置」，由各页判断（关键字之外还有下拉）。
  dirty: { type: Boolean, default: false },
});

const emit = defineEmits(['search', 'reset']);
const keyword = defineModel({ type: String, default: '' });

const L = { reset: '重置' };

const DEBOUNCE_MS = 400;
let timer = null;
const composing = ref(false);

const fire = () => emit('search');
const schedule = () => {
  clearTimeout(timer);
  timer = setTimeout(fire, DEBOUNCE_MS);
};
// 中文输入法打字途中不查：拼音半成品搜出来是空的，还白跑一轮请求。
watch(keyword, () => {
  if (!composing.value) schedule();
});
const onCompositionEnd = () => {
  composing.value = false;
  schedule();
};
const onEnter = () => {
  clearTimeout(timer);
  fire();
};
const clearKeyword = () => {
  keyword.value = '';
  onEnter();
};
const reset = () => {
  keyword.value = '';
  clearTimeout(timer);
  emit('reset');
};
onBeforeUnmount(() => clearTimeout(timer));
</script>

<template>
  <div class="flex flex-wrap items-center gap-2">
    <div class="relative">
      <Icon
        icon="i-lucide-search"
        class="absolute -translate-y-1/2 pointer-events-none size-3.5 left-2.5 top-1/2 text-n-slate-10"
      />
      <Input
        v-model="keyword"
        size="sm"
        :placeholder="props.placeholder"
        custom-input-class="w-56 !pl-8 !pr-7"
        @compositionstart="composing = true"
        @compositionend="onCompositionEnd"
        @keyup.enter="onEnter"
      />
      <button
        v-if="keyword"
        class="absolute -translate-y-1/2 right-2 top-1/2 text-n-slate-10 hover:text-n-slate-12"
        @click="clearKeyword"
      >
        <Icon icon="i-lucide-x" class="size-3.5" />
      </button>
    </div>
    <slot />
    <button
      v-if="props.dirty"
      class="text-xs text-n-slate-11 hover:text-n-slate-12 hover:underline"
      @click="reset"
    >
      {{ L.reset }}
    </button>
  </div>
</template>
