<script setup>
// 列头右缘那条看不见的缝，按住左右拖改列宽、双击恢复自适应。
// 配 useOrderableColumns 的 startResize / autoFitColumn 用。
//
// 列头本身是 draggable（拖动改列序），所以把手上要 @dragstart.prevent：
// 不拦的话一按下去浏览器就当成在拖列，改宽度变成了换位置。
defineProps({
  columnKey: { type: String, required: true },
  active: { type: Boolean, default: false },
});
const emit = defineEmits(['resizeStart', 'autoFit']);

const onDown = event => {
  // 把手所在的那个 th —— 起始宽度从它量
  emit('resizeStart', event, event.target.closest('th'));
};
</script>

<template>
  <span
    class="absolute inset-y-0 right-0 z-10 w-2 -mr-1 cursor-col-resize select-none"
    title="拖动调整列宽，双击恢复自适应"
    draggable="false"
    @mousedown.stop.prevent="onDown"
    @dblclick.stop.prevent="emit('autoFit', columnKey)"
    @dragstart.prevent
    @click.stop
  >
    <span
      class="absolute inset-y-1 left-1/2 w-px -translate-x-1/2 transition-colors"
      :class="active ? 'bg-n-iris-9' : 'bg-transparent hover:bg-n-slate-6'"
    />
  </span>
</template>
