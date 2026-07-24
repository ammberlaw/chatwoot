<script setup>
import { ref, onMounted, onBeforeUnmount, watch } from 'vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const emit = defineEmits(['update:text']);
// 富文本签名编辑器：原生 contenteditable + execCommand 工具栏，输出内联样式 HTML，
// 直接拼进邮件发送（字体/字号/颜色/加粗/对齐/链接/插图）。图片以 data URL 内嵌，限 500K。
const html = defineModel({ type: String, default: '' });
const editorRef = ref(null);
const fileRef = ref(null);
let savedRange = null;

const L = {
  bold: '加粗',
  italic: '斜体',
  underline: '下划线',
  color: '文字颜色',
  alignLeft: '左对齐',
  alignCenter: '居中',
  alignRight: '右对齐',
  link: '插入链接',
  image: '插入图片',
  clear: '清除格式',
  undo: '撤销',
  redo: '重做',
  linkPrompt: '请输入链接地址（含 http:// 或 https://）',
  imageTooBig: '签名图片不能大于 500K',
  placeholder: '在此排版签名：姓名、职位、公司、邮箱、电话、网址…',
};

const FONTS = [
  { label: '默认字体', value: '' },
  { label: 'Arial', value: 'Arial, Helvetica, sans-serif' },
  { label: 'Times New Roman', value: '"Times New Roman", Georgia, serif' },
  { label: 'Georgia', value: 'Georgia, serif' },
  { label: 'Courier New', value: '"Courier New", monospace' },
  { label: '微软雅黑', value: '"Microsoft YaHei", "PingFang SC", sans-serif' },
  { label: '宋体', value: '"Songti SC", SimSun, serif' },
  { label: '黑体', value: '"Heiti SC", SimHei, sans-serif' },
];
const SIZES = [
  { label: '字号', value: '' },
  { label: '10pt', value: '10pt' },
  { label: '12pt', value: '12pt' },
  { label: '14pt', value: '14pt' },
  { label: '16pt', value: '16pt' },
  { label: '18pt', value: '18pt' },
  { label: '24pt', value: '24pt' },
];

// 持续记录编辑区内的选区，供从工具栏（select/按钮）执行命令时恢复。
const onSelectionChange = () => {
  const sel = window.getSelection();
  if (sel?.rangeCount && editorRef.value?.contains(sel.anchorNode)) {
    savedRange = sel.getRangeAt(0).cloneRange();
  }
};

const restoreSelection = () => {
  editorRef.value?.focus();
  if (!savedRange) return;
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(savedRange);
};

const sync = () => {
  if (!editorRef.value) return;
  html.value = editorRef.value.innerHTML;
  emit('update:text', editorRef.value.innerText);
};

const exec = (command, value = null) => {
  restoreSelection();
  document.execCommand('styleWithCSS', false, true);
  document.execCommand(command, false, value);
  sync();
};

const applyFont = event => {
  const value = event.target.value;
  event.target.value = '';
  if (value) exec('fontName', value);
};

// execCommand 的 fontSize 只认 1–7，用占位 7 再把 <font size=7> 换成内联 pt。
const applySize = event => {
  const value = event.target.value;
  event.target.value = '';
  if (!value) return;
  restoreSelection();
  document.execCommand('fontSize', false, '7');
  editorRef.value?.querySelectorAll('font[size="7"]').forEach(node => {
    node.removeAttribute('size');
    node.style.fontSize = value;
  });
  sync();
};

const applyColor = event => exec('foreColor', event.target.value);

const insertLink = () => {
  // eslint-disable-next-line no-alert
  const url = window.prompt(L.linkPrompt, 'https://');
  if (url) exec('createLink', url);
};

const pickImage = () => fileRef.value?.click();
const onImage = event => {
  const file = event.target.files?.[0];
  event.target.value = '';
  if (!file) return;
  if (file.size > 500 * 1024) {
    // eslint-disable-next-line no-alert
    window.alert(L.imageTooBig);
    return;
  }
  const reader = new FileReader();
  reader.onload = () => exec('insertImage', reader.result);
  reader.readAsDataURL(file);
};

const onInput = () => sync();

watch(html, val => {
  if (editorRef.value && val !== editorRef.value.innerHTML) {
    editorRef.value.innerHTML = val || '';
  }
});

onMounted(() => {
  if (editorRef.value) editorRef.value.innerHTML = html.value || '';
  document.addEventListener('selectionchange', onSelectionChange);
});
onBeforeUnmount(() =>
  document.removeEventListener('selectionchange', onSelectionChange)
);
</script>

<template>
  <div class="border rounded-lg border-n-weak overflow-hidden bg-n-solid-1">
    <!-- 工具栏 -->
    <div
      class="flex flex-wrap items-center gap-0.5 px-2 py-1.5 border-b border-n-weak bg-n-alpha-1"
    >
      <button
        type="button"
        class="p-1.5 rounded hover:bg-n-alpha-2 text-n-slate-11"
        :title="L.undo"
        @click="exec('undo')"
      >
        <Icon icon="i-lucide-undo-2" class="size-4" />
      </button>
      <button
        type="button"
        class="p-1.5 rounded hover:bg-n-alpha-2 text-n-slate-11"
        :title="L.redo"
        @click="exec('redo')"
      >
        <Icon icon="i-lucide-redo-2" class="size-4" />
      </button>
      <button
        type="button"
        class="p-1.5 rounded hover:bg-n-alpha-2 text-n-slate-11"
        :title="L.clear"
        @click="exec('removeFormat')"
      >
        <Icon icon="i-lucide-remove-formatting" class="size-4" />
      </button>
      <span class="w-px h-5 mx-1 bg-n-weak" />
      <select
        class="h-7 px-1 text-xs rounded reset-base border border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-0 w-[132px]"
        @change="applyFont"
      >
        <option v-for="f in FONTS" :key="f.label" :value="f.value">
          {{ f.label }}
        </option>
      </select>
      <select
        class="h-7 px-1 text-xs rounded reset-base border border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-0 w-[76px]"
        @change="applySize"
      >
        <option v-for="s in SIZES" :key="s.label" :value="s.value">
          {{ s.label }}
        </option>
      </select>
      <span class="w-px h-5 mx-1 bg-n-weak" />
      <button
        type="button"
        class="p-1.5 rounded hover:bg-n-alpha-2 text-n-slate-11"
        :title="L.bold"
        @click="exec('bold')"
      >
        <Icon icon="i-lucide-bold" class="size-4" />
      </button>
      <button
        type="button"
        class="p-1.5 rounded hover:bg-n-alpha-2 text-n-slate-11"
        :title="L.italic"
        @click="exec('italic')"
      >
        <Icon icon="i-lucide-italic" class="size-4" />
      </button>
      <button
        type="button"
        class="p-1.5 rounded hover:bg-n-alpha-2 text-n-slate-11"
        :title="L.underline"
        @click="exec('underline')"
      >
        <Icon icon="i-lucide-underline" class="size-4" />
      </button>
      <label
        class="relative p-1.5 rounded hover:bg-n-alpha-2 text-n-slate-11 cursor-pointer"
        :title="L.color"
      >
        <Icon icon="i-lucide-baseline" class="size-4" />
        <input
          type="color"
          class="absolute inset-0 opacity-0 cursor-pointer"
          @input="applyColor"
        />
      </label>
      <span class="w-px h-5 mx-1 bg-n-weak" />
      <button
        type="button"
        class="p-1.5 rounded hover:bg-n-alpha-2 text-n-slate-11"
        :title="L.alignLeft"
        @click="exec('justifyLeft')"
      >
        <Icon icon="i-lucide-align-left" class="size-4" />
      </button>
      <button
        type="button"
        class="p-1.5 rounded hover:bg-n-alpha-2 text-n-slate-11"
        :title="L.alignCenter"
        @click="exec('justifyCenter')"
      >
        <Icon icon="i-lucide-align-center" class="size-4" />
      </button>
      <button
        type="button"
        class="p-1.5 rounded hover:bg-n-alpha-2 text-n-slate-11"
        :title="L.alignRight"
        @click="exec('justifyRight')"
      >
        <Icon icon="i-lucide-align-right" class="size-4" />
      </button>
      <span class="w-px h-5 mx-1 bg-n-weak" />
      <button
        type="button"
        class="p-1.5 rounded hover:bg-n-alpha-2 text-n-slate-11"
        :title="L.link"
        @click="insertLink"
      >
        <Icon icon="i-lucide-link" class="size-4" />
      </button>
      <button
        type="button"
        class="p-1.5 rounded hover:bg-n-alpha-2 text-n-slate-11"
        :title="L.image"
        @click="pickImage"
      >
        <Icon icon="i-lucide-image" class="size-4" />
      </button>
      <input
        ref="fileRef"
        type="file"
        accept="image/*"
        class="hidden"
        @change="onImage"
      />
    </div>

    <!-- 可编辑区 -->
    <div
      ref="editorRef"
      contenteditable="true"
      data-placeholder=""
      class="crm-sig-editable min-h-[180px] max-h-[360px] overflow-y-auto px-3 py-2 text-sm leading-relaxed text-n-slate-12 focus:outline-none"
      :data-empty-text="L.placeholder"
      @input="onInput"
      @blur="sync"
    />
  </div>
</template>

<style scoped>
.crm-sig-editable:empty::before {
  content: attr(data-empty-text);
  color: var(--n-slate-9, #9ca3af);
  pointer-events: none;
}
.crm-sig-editable :deep(a) {
  color: #2563eb;
  text-decoration: underline;
}
.crm-sig-editable :deep(img) {
  max-width: 100%;
}
</style>
