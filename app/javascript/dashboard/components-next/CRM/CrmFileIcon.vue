<script setup>
import { computed, useId } from 'vue';

/**
 * 文档中心的文件图标：圆角方卡 + 右上折角 + 居中字形。
 * 形与配色跟手机端 `mobile/src/components/FileTile.vue` 同源，两端保持一致。
 *
 * ⚠️ 字形必须是**纯字形**：Office 类用字母（绿 X / 蓝 W / 橙 P），
 *    用 i-ri-file-excel-2-fill 那种自带文档外框的图标会变成「卡中卡」。
 * 颜色取各家软件的约定色（Excel 绿、PDF 红、PPT 橙…），不是随便配的。
 */
const props = defineProps({
  filename: { type: String, default: '' },
});

const TYPES = [
  {
    re: /\.(xlsx?|csv|numbers)$/i,
    tone: '#1F7A47',
    soft: '#EAF6EF',
    letter: 'X',
  },
  {
    re: /\.(docx?|pages|rtf|odt)$/i,
    tone: '#2B579A',
    soft: '#EAF0FA',
    letter: 'W',
  },
  { re: /\.(pptx?|key)$/i, tone: '#C43E1C', soft: '#FCECE7', letter: 'P' },
  { re: /\.pdf$/i, tone: '#D93025', soft: '#FDEBE9', letter: 'PDF' },
  {
    re: /\.(png|jpe?g|gif|webp|heic|bmp|svg)$/i,
    tone: '#1A73E8',
    soft: '#E9F1FD',
    icon: 'i-ri-image-fill',
  },
  {
    re: /\.(mp4|mov|avi|mkv|webm)$/i,
    tone: '#6D4AFF',
    soft: '#EEEAFE',
    icon: 'i-ri-play-fill',
  },
  {
    re: /\.(mp3|wav|m4a|aac)$/i,
    tone: '#E8710A',
    soft: '#FDF0E4',
    icon: 'i-ri-music-2-fill',
  },
  {
    re: /\.(zip|rar|7z|tar|gz)$/i,
    tone: '#6B6B78',
    soft: '#F0F0F2',
    icon: 'i-ri-archive-fill',
  },
];

// 认不出扩展名的走灰色纸页，不留空白。
const FALLBACK = {
  tone: '#6B7280',
  soft: '#F1F2F4',
  icon: 'i-ri-file-text-fill',
};

const type = computed(
  () => TYPES.find(t => t.re.test(props.filename || '')) || FALLBACK
);

// 渐变/滤镜的 id 必须全局唯一：一屏几十个文件图标，id 撞了浏览器只认第一处定义，
// 后面的图标会全被染成同一种颜色。
const uid = useId();
</script>

<template>
  <div class="relative">
    <svg viewBox="0 0 96 96" class="size-full" fill="none">
      <defs>
        <linearGradient :id="`${uid}g`" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#FFFFFF" />
          <stop offset="100%" :stop-color="type.soft" />
        </linearGradient>
        <filter :id="`${uid}d`" x="-25%" y="-20%" width="150%" height="155%">
          <feDropShadow
            dx="0"
            dy="5"
            stdDeviation="4.5"
            flood-color="#1B1B28"
            flood-opacity="0.14"
          />
        </filter>
      </defs>
      <g :filter="`url(#${uid}d)`">
        <path
          d="M16 25a11 11 0 0 1 11-11h35l18 18v43a11 11 0 0 1-11 11H27a11 11 0 0 1-11-11V25Z"
          :fill="`url(#${uid}g)`"
        />
        <path d="M62 14l18 18H62V14Z" :fill="type.tone" />
      </g>
      <!-- 字母画进 SVG，跟着 viewBox 缩放；图标类字形用绝对定位的 span 叠上去 -->
      <text
        v-if="type.letter"
        x="48"
        y="59"
        text-anchor="middle"
        dominant-baseline="central"
        class="font-extrabold"
        :font-size="type.letter.length > 1 ? 22 : 42"
        :letter-spacing="type.letter.length > 1 ? -1 : 0"
        :fill="type.tone"
      >
        {{ type.letter }}
      </text>
    </svg>
    <span
      v-if="!type.letter"
      class="absolute inset-0 grid place-items-center pt-[8%]"
      aria-hidden="true"
    >
      <span
        class="size-[38%]"
        :class="type.icon"
        :style="{ color: type.tone }"
      />
    </span>
  </div>
</template>
