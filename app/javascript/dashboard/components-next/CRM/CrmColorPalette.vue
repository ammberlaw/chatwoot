<script setup>
import { ref, computed, watch, onMounted } from 'vue';

// 写信文字颜色的颜料盘：预设色板 + 最近使用 + 渐变取色区（饱和度/明度）+ 色相条 + hex 输入。
// 所有按钮 mousedown.prevent，避免夺走编辑器选区焦点。
const props = defineProps({
  modelValue: { type: String, default: '#e53935' },
});
const emit = defineEmits(['select', 'clear']);

const PRESET_COLORS = [
  ['#000000', '#444444', '#888888', '#bbbbbb', '#dddddd', '#ffffff', '#8b572a'],
  ['#e53935', '#f57c00', '#fbc02d', '#43a047', '#00897b', '#1e88e5', '#8e24aa'],
  ['#b71c1c', '#e65100', '#f9a825', '#1b5e20', '#004d40', '#0d47a1', '#4a148c'],
  ['#ef9a9a', '#ffcc80', '#fff59d', '#a5d6a7', '#80cbc4', '#90caf9', '#ce93d8'],
];
const RECENT_KEY = 'crm_email_recent_colors';
const HEX_RE = /^#[0-9a-f]{6}$/i;

// ── HSV ↔ hex 转换 ──
const hsvToHex = (h, s, v) => {
  const f = n => {
    const k = (n + h / 60) % 6;
    const c = v - v * s * Math.max(Math.min(k, 4 - k, 1), 0);
    return Math.round(c * 255)
      .toString(16)
      .padStart(2, '0');
  };
  return `#${f(5)}${f(3)}${f(1)}`;
};
const hexToHsv = hex => {
  const r = parseInt(hex.slice(1, 3), 16) / 255;
  const g = parseInt(hex.slice(3, 5), 16) / 255;
  const b = parseInt(hex.slice(5, 7), 16) / 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const d = max - min;
  let h = 0;
  if (d) {
    if (max === r) h = 60 * (((g - b) / d) % 6);
    else if (max === g) h = 60 * ((b - r) / d + 2);
    else h = 60 * ((r - g) / d + 4);
  }
  return { h: (h + 360) % 360, s: max ? d / max : 0, v: max };
};

const hue = ref(0);
const sat = ref(1);
const val = ref(1);
const hexInput = ref(props.modelValue);
const recent = ref([]);

const currentHex = computed(() => hsvToHex(hue.value, sat.value, val.value));
const hueColor = computed(() => hsvToHex(hue.value, 1, 1));

const syncFromHex = hex => {
  const { h, s, v } = hexToHsv(hex);
  hue.value = h;
  sat.value = s;
  val.value = v;
  hexInput.value = hex;
};

onMounted(() => {
  if (HEX_RE.test(props.modelValue)) syncFromHex(props.modelValue);
  try {
    recent.value = JSON.parse(localStorage.getItem(RECENT_KEY) || '[]');
  } catch {
    recent.value = [];
  }
});

watch(currentHex, hex => {
  hexInput.value = hex;
});

const pushRecent = color => {
  recent.value = [color, ...recent.value.filter(c => c !== color)].slice(0, 7);
  try {
    localStorage.setItem(RECENT_KEY, JSON.stringify(recent.value));
  } catch {
    // localStorage 不可用时最近颜色仅在本次会话生效
  }
};

const pick = color => {
  pushRecent(color);
  emit('select', color);
};

// ── 渐变取色区（饱和度 x / 明度 y）──
const svRef = ref(null);
const dragging = ref(false);

const updateSv = event => {
  const rect = svRef.value.getBoundingClientRect();
  sat.value = Math.min(
    1,
    Math.max(0, (event.clientX - rect.left) / rect.width)
  );
  val.value = Math.min(
    1,
    Math.max(0, 1 - (event.clientY - rect.top) / rect.height)
  );
};
const onSvDown = event => {
  dragging.value = true;
  svRef.value.setPointerCapture(event.pointerId);
  updateSv(event);
};
const onSvMove = event => {
  if (dragging.value) updateSv(event);
};
const onSvUp = () => {
  dragging.value = false;
};

const onHexEnter = () => {
  const v = hexInput.value.trim().toLowerCase();
  const full = v.startsWith('#') ? v : `#${v}`;
  if (HEX_RE.test(full)) {
    syncFromHex(full);
    pick(full);
  }
};
</script>

<template>
  <div class="flex flex-col w-56 gap-2 select-none" @mousedown.prevent>
    <!-- 预设色板 -->
    <div class="flex flex-col gap-1">
      <div
        v-for="(row, rowIdx) in PRESET_COLORS"
        :key="rowIdx"
        class="flex gap-1"
      >
        <button
          v-for="c in row"
          :key="c"
          class="flex-1 h-5 transition-transform border rounded-sm border-n-alpha-2 hover:scale-110"
          :style="{ backgroundColor: c }"
          :title="c"
          @click="pick(c)"
        />
      </div>
    </div>

    <!-- 最近使用 -->
    <div
      v-if="recent.length"
      class="flex flex-col gap-1 pt-1 border-t border-n-weak"
    >
      <!-- eslint-disable-next-line @intlify/vue-i18n/no-raw-text -->
      <div class="text-[11px] text-n-slate-10">最近使用</div>
      <div class="flex gap-1">
        <button
          v-for="c in recent"
          :key="c"
          class="w-6 h-5 transition-transform border rounded-sm border-n-alpha-2 hover:scale-110"
          :style="{ backgroundColor: c }"
          :title="c"
          @click="pick(c)"
        />
      </div>
    </div>

    <!-- 渐变取色区 -->
    <div class="flex flex-col gap-2 pt-1 border-t border-n-weak">
      <div
        ref="svRef"
        class="relative w-full h-24 rounded cursor-crosshair touch-none"
        :style="{
          backgroundImage: `linear-gradient(to top, #000, rgba(0,0,0,0)), linear-gradient(to right, #fff, ${hueColor})`,
        }"
        @pointerdown="onSvDown"
        @pointermove="onSvMove"
        @pointerup="onSvUp"
      >
        <span
          class="absolute w-3 h-3 -translate-x-1/2 -translate-y-1/2 bg-transparent border-2 border-white rounded-full pointer-events-none shadow-[0_0_2px_rgba(0,0,0,.6)]"
          :style="{ left: `${sat * 100}%`, top: `${(1 - val) * 100}%` }"
        />
      </div>
      <input
        v-model.number="hue"
        type="range"
        min="0"
        max="360"
        step="1"
        class="w-full h-2 rounded appearance-none cursor-pointer crm-hue-slider"
      />
      <div class="flex items-center gap-2">
        <span
          class="w-6 h-6 border rounded shrink-0 border-n-alpha-2"
          :style="{ backgroundColor: currentHex }"
        />
        <input
          v-model="hexInput"
          type="text"
          spellcheck="false"
          class="flex-1 h-6 min-w-0 px-1.5 font-mono text-xs border rounded outline-none border-n-weak bg-n-background text-n-slate-12 focus:border-n-brand"
          @mousedown.stop
          @keyup.enter="onHexEnter"
        />
        <!-- eslint-disable-next-line @intlify/vue-i18n/no-raw-text -->
        <button
          class="h-6 px-2 text-xs text-white rounded shrink-0 bg-n-brand hover:brightness-110"
          @click="pick(currentHex)"
        >
          应用
        </button>
        <button
          class="flex items-center justify-center w-6 h-6 border rounded shrink-0 border-n-alpha-2 hover:bg-n-alpha-2"
          title="恢复默认颜色"
          @click="emit('clear')"
        >
          <span class="block w-3.5 h-[2px] rotate-45 bg-n-ruby-9 rounded" />
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* 色相条彩虹轨道；Tailwind-only 约定的例外——原生 range 轨道样式只能用 CSS 覆写 */
.crm-hue-slider {
  background: linear-gradient(
    to right,
    #f00 0%,
    #ff0 17%,
    #0f0 33%,
    #0ff 50%,
    #00f 67%,
    #f0f 83%,
    #f00 100%
  );
}
.crm-hue-slider::-webkit-slider-thumb {
  appearance: none;
  width: 12px;
  height: 12px;
  border-radius: 9999px;
  background: #fff;
  border: 1px solid rgba(0, 0, 0, 0.3);
  box-shadow: 0 0 2px rgba(0, 0, 0, 0.4);
}
</style>
