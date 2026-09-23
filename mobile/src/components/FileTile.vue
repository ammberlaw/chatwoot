<script setup>
import { computed } from 'vue';

// 知识库网格用的大号文件图标，SVG 画的（不用位图，好跟深浅色，也免得备一堆图）。
// 两个形：
//  · 文件夹＝橙色窄标签 + 奶白渐变主体，整体接近正方（早先做成扁长条，和参考差很远）
//  · 文件  ＝圆角方卡 + 右上小折角 + 居中字形
// ⚠️ 字形必须是**纯字形**：Office 类用字母（绿 X / 蓝 W / 橙 P），
//    用 i-ri-file-excel-2-fill 那种自带文档外框的图标会变成「卡中卡」。
const props = defineProps({
  filename: { type: String, default: '' },
  // 多附件视为文件夹
  count: { type: Number, default: 0 },
});

const TYPES = [
  { re: /\.(xlsx?|csv|numbers)$/i, tone: '#1F7A47', soft: '#EAF6EF', letter: 'X' },
  { re: /\.(docx?|pages)$/i, tone: '#2B579A', soft: '#EAF0FA', letter: 'W' },
  { re: /\.(pptx?|key)$/i, tone: '#C43E1C', soft: '#FCECE7', letter: 'P' },
  { re: /\.pdf$/i, tone: '#D93025', soft: '#FDEBE9', letter: 'PDF' },
  { re: /\.(png|jpe?g|gif|webp|heic|bmp|svg)$/i, tone: '#1A73E8', soft: '#E9F1FD', icon: 'i-ri-image-fill' },
  { re: /\.(mp4|mov|avi|mkv|webm)$/i, tone: '#6D4AFF', soft: '#EEEAFE', icon: 'i-ri-play-fill' },
  { re: /\.(mp3|wav|m4a|aac)$/i, tone: '#E8710A', soft: '#FDF0E4', icon: 'i-ri-music-2-fill' },
  { re: /\.(zip|rar|7z|tar|gz)$/i, tone: '#6B6B78', soft: '#F0F0F2', icon: 'i-ri-archive-fill' },
];

const type = computed(() => TYPES.find(t => t.re.test(props.filename || '')));
const isFolder = computed(() => !type.value);
const uid = computed(() => `ft${props.count}`);
</script>

<template>
  <!-- 文件夹 -->
  <svg v-if="isFolder" viewBox="0 0 96 96" class="size-full" fill="none">
    <defs>
      <linearGradient :id="`${uid}b`" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0%" stop-color="#FFF6E2" />
        <stop offset="62%" stop-color="#FFFDF8" />
        <stop offset="100%" stop-color="#FFFFFF" />
      </linearGradient>
      <linearGradient :id="`${uid}t`" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0%" stop-color="#FFC93D" />
        <stop offset="100%" stop-color="#F3A51E" />
      </linearGradient>
      <filter :id="`${uid}s`" x="-25%" y="-20%" width="150%" height="155%">
        <feDropShadow dx="0" dy="5" stdDeviation="4.5" flood-color="#B8913C" flood-opacity="0.24" />
      </filter>
    </defs>
    <g :filter="`url(#${uid}s)`">
      <!-- 窄标签：只占左侧约 45%，右端一道斜边 -->
      <path
        d="M11 30a8 8 0 0 1 8-8h19a6 6 0 0 1 4.4 1.9L47 28h30a8 8 0 0 1 8 8v8H11V30Z"
        :fill="`url(#${uid}t)`"
      />
      <!-- 主体：和标签一起接近正方 -->
      <rect x="11" y="34" width="74" height="52" rx="11" :fill="`url(#${uid}b)`" />
    </g>
  </svg>

  <!-- 文件：圆角方卡 + 右上小折角 + 居中字形 -->
  <div v-else class="relative size-full">
    <svg viewBox="0 0 96 96" class="size-full" fill="none">
      <defs>
        <linearGradient :id="`${uid}g`" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#FFFFFF" />
          <stop offset="100%" :stop-color="type.soft" />
        </linearGradient>
        <filter :id="`${uid}d`" x="-25%" y="-20%" width="150%" height="155%">
          <feDropShadow dx="0" dy="5" stdDeviation="4.5" flood-color="#1B1B28" flood-opacity="0.14" />
        </filter>
      </defs>
      <g :filter="`url(#${uid}d)`">
        <path
          d="M16 25a11 11 0 0 1 11-11h35l18 18v43a11 11 0 0 1-11 11H27a11 11 0 0 1-11-11V25Z"
          :fill="`url(#${uid}g)`"
        />
        <path d="M62 14l18 18H62V14Z" :fill="type.tone" />
      </g>
    </svg>
    <span class="absolute inset-0 grid place-items-center pt-2" aria-hidden="true">
      <span
        v-if="type.letter"
        class="font-extrabold leading-none"
        :class="type.letter.length > 1 ? 'text-[19px] tracking-[-0.5px]' : 'text-[34px]'"
        :style="{ color: type.tone }"
      >
        {{ type.letter }}
      </span>
      <span v-else class="size-9" :class="type.icon" :style="{ color: type.tone }" />
    </span>
  </div>
</template>
