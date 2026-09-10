<script setup>
import { computed } from 'vue';

// 附件在线预览：图片直接看，PDF 内嵌看，其它类型给下载入口。
// 票据/截图这类场景够用；Excel/Word 转 HTML 的重预览在文档中心，不在这里重复造。
const props = defineProps({
  // { id, filename, url } —— 为 null 时不显示。
  file: { type: Object, default: null },
});
const emit = defineEmits(['close']);

const IMAGE_EXTS = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'];

const ext = computed(() => {
  const parts = (props.file?.filename || '').toLowerCase().split('.');
  return parts.length > 1 ? parts.pop() : '';
});
const kind = computed(() => {
  if (IMAGE_EXTS.includes(ext.value)) return 'image';
  return ext.value === 'pdf' ? 'pdf' : 'other';
});
</script>

<template>
  <!-- Teleport 到 body：祖先若带 backdrop-blur/filter 会给 fixed 建立包含块，
       浮层就只盖住那张卡片而不是整屏（遮罩盖不住侧栏）。 -->
  <Teleport to="body">
    <!-- 遮罩用设计系统的 n-alpha-black1（Dialog 的 ::backdrop 同款）：
         主题里 black 只有色阶没有单色，bg-black/40 这种写法编译不出规则、点开不变暗。 -->
    <div
      v-if="file"
      class="fixed inset-0 z-[60] flex items-center justify-center p-4 bg-n-alpha-black1 backdrop-blur-[4px]"
      @click.self="emit('close')"
    >
      <div
        class="flex flex-col w-full max-w-4xl overflow-hidden shadow-xl max-h-[90vh] rounded-2xl bg-n-solid-1"
      >
        <div
          class="flex items-center gap-3 px-4 py-3 border-b border-n-weak shrink-0"
        >
          <span class="flex-1 text-sm truncate text-n-slate-12">
            {{ file.filename }}
          </span>
          <a
            :href="file.url"
            target="_blank"
            rel="noopener noreferrer"
            download
            class="text-sm text-n-iris-11"
          >
            下载
          </a>
          <button
            type="button"
            class="text-n-slate-11 hover:text-n-slate-12"
            @click="emit('close')"
          >
            <span class="i-lucide-x text-lg" />
          </button>
        </div>

        <div
          class="flex items-center justify-center flex-1 min-h-0 p-4 bg-n-alpha-1"
        >
          <img
            v-if="kind === 'image'"
            :src="file.url"
            :alt="file.filename"
            class="object-contain max-w-full max-h-[75vh]"
          />
          <iframe
            v-else-if="kind === 'pdf'"
            :src="file.url"
            :title="file.filename"
            class="w-full h-[75vh] border-0 bg-n-solid-1"
          />
          <div v-else class="py-10 text-sm text-center text-n-slate-11">
            该文件类型不支持在线预览，请点右上角「下载」查看。
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>
