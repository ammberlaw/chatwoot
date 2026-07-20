<script setup>
import { ref, nextTick } from 'vue';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import SignatureAPI from 'dashboard/api/crm/signature';

const emit = defineEmits(['saved']);

const L = {
  title: '我的签名',
  hint: '存一次，之后考核表填报 / 打分 / 审批各环节一键盖章即可。',
  tabDraw: '手写',
  tabUpload: '上传图片',
  drawHint: '在下方区域用鼠标或手指签名',
  clear: '清除重写',
  pick: '选择图片',
  current: '当前签名',
  remove: '删除签名',
  removed: '签名已删除',
  saved: '签名已保存',
  empty: '请先手写或上传签名',
  error: '操作失败',
  save: '保存',
};

const dialogRef = ref(null);
const canvasRef = ref(null);

const mode = ref('draw'); // draw | upload
const loading = ref(false);
const saving = ref(false);
const existing = ref({ exists: false, imageUrl: null });

const hasDrawn = ref(false);
const uploadFile = ref(null);
const uploadPreview = ref('');

let ctx = null;
let drawing = false;

const load = async () => {
  loading.value = true;
  try {
    const { data } = await SignatureAPI.get();
    existing.value = {
      exists: !!data.exists,
      imageUrl: data.image_url || null,
    };
  } catch {
    existing.value = { exists: false, imageUrl: null };
  } finally {
    loading.value = false;
  }
};

const initCanvas = () => {
  const c = canvasRef.value;
  if (!c) return;
  ctx = c.getContext('2d');
  ctx.clearRect(0, 0, c.width, c.height);
  ctx.strokeStyle = '#1f2233';
  ctx.lineWidth = 2.5;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  hasDrawn.value = false;
};

const open = async () => {
  mode.value = 'draw';
  uploadFile.value = null;
  uploadPreview.value = '';
  dialogRef.value?.open();
  await load();
  await nextTick();
  initCanvas();
};

defineExpose({ open });

// ── 手写 ──
const pointFromEvent = e => {
  const c = canvasRef.value;
  const r = c.getBoundingClientRect();
  return {
    x: (e.clientX - r.left) * (c.width / r.width),
    y: (e.clientY - r.top) * (c.height / r.height),
  };
};

const startDraw = e => {
  if (!ctx) initCanvas();
  drawing = true;
  const p = pointFromEvent(e);
  ctx.beginPath();
  ctx.moveTo(p.x, p.y);
  canvasRef.value.setPointerCapture?.(e.pointerId);
};

const moveDraw = e => {
  if (!drawing) return;
  const p = pointFromEvent(e);
  ctx.lineTo(p.x, p.y);
  ctx.stroke();
  hasDrawn.value = true;
};

const endDraw = () => {
  drawing = false;
};

const clearCanvas = () => initCanvas();

// ── 上传 ──
const onPickFile = e => {
  const file = e.target.files?.[0];
  if (!file) return;
  uploadFile.value = file;
  uploadPreview.value = URL.createObjectURL(file);
};

// ── 保存 / 删除 ──
const submitFile = async file => {
  saving.value = true;
  try {
    await SignatureAPI.save(file);
    useAlert(L.saved);
    emit('saved');
    dialogRef.value?.close();
  } catch {
    useAlert(L.error);
  } finally {
    saving.value = false;
  }
};

const save = () => {
  if (mode.value === 'upload') {
    if (!uploadFile.value) {
      useAlert(L.empty);
      return;
    }
    submitFile(uploadFile.value);
    return;
  }
  if (!hasDrawn.value) {
    useAlert(L.empty);
    return;
  }
  canvasRef.value.toBlob(blob => {
    submitFile(new File([blob], 'signature.png', { type: 'image/png' }));
  }, 'image/png');
};

const removeSignature = async () => {
  saving.value = true;
  try {
    await SignatureAPI.remove();
    existing.value = { exists: false, imageUrl: null };
    useAlert(L.removed);
    emit('saved');
  } catch {
    useAlert(L.error);
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="L.title"
    :description="L.hint"
    :confirm-button-label="L.save"
    confirm-button-color="iris"
    :is-loading="saving"
    @confirm="save"
  >
    <div class="flex flex-col gap-3">
      <!-- 当前签名 -->
      <div
        v-if="existing.exists"
        class="flex items-center gap-3 p-2 border rounded-lg border-n-weak bg-n-alpha-1"
      >
        <img
          :src="existing.imageUrl"
          alt="signature"
          class="object-contain h-12 bg-white rounded max-w-40"
        />
        <span class="text-xs text-n-slate-11">{{ L.current }}</span>
        <button
          type="button"
          class="ml-auto px-2 py-1 text-xs rounded-md text-n-ruby-11 hover:bg-n-ruby-3"
          @click="removeSignature"
        >
          {{ L.remove }}
        </button>
      </div>

      <!-- 模式切换 -->
      <div class="flex gap-1 p-1 rounded-lg bg-n-alpha-1 w-fit">
        <button
          type="button"
          class="px-3 py-1 text-xs font-medium rounded-md"
          :class="
            mode === 'draw'
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11'
          "
          @click="mode = 'draw'"
        >
          {{ L.tabDraw }}
        </button>
        <button
          type="button"
          class="px-3 py-1 text-xs font-medium rounded-md"
          :class="
            mode === 'upload'
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11'
          "
          @click="mode = 'upload'"
        >
          {{ L.tabUpload }}
        </button>
      </div>

      <!-- 手写 -->
      <div v-show="mode === 'draw'" class="flex flex-col gap-2">
        <p class="text-xs text-n-slate-10">{{ L.drawHint }}</p>
        <canvas
          ref="canvasRef"
          width="500"
          height="180"
          class="w-full bg-white border rounded-lg cursor-crosshair touch-none border-n-weak"
          @pointerdown="startDraw"
          @pointermove="moveDraw"
          @pointerup="endDraw"
          @pointerleave="endDraw"
        />
        <button
          type="button"
          class="px-2 py-1 text-xs rounded-md w-fit text-n-slate-11 hover:bg-n-alpha-2"
          @click="clearCanvas"
        >
          {{ L.clear }}
        </button>
      </div>

      <!-- 上传 -->
      <div v-show="mode === 'upload'" class="flex flex-col gap-2">
        <label
          class="flex items-center justify-center h-12 gap-2 text-sm border border-dashed rounded-lg cursor-pointer w-fit px-4 border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
        >
          <span class="i-lucide-upload size-4" />
          {{ L.pick }}
          <input
            type="file"
            accept="image/*"
            class="hidden"
            @change="onPickFile"
          />
        </label>
        <img
          v-if="uploadPreview"
          :src="uploadPreview"
          alt="preview"
          class="object-contain h-16 bg-white border rounded max-w-48 border-n-weak"
        />
      </div>
    </div>
  </Dialog>
</template>
