<script setup>
import { ref } from 'vue';
import { Capacitor } from '@capacitor/core';
import { Haptics, NotificationType } from '@capacitor/haptics';
import {
  CapacitorBarcodeScanner,
  CapacitorBarcodeScannerTypeHint,
  CapacitorBarcodeScannerCameraDirection,
  CapacitorBarcodeScannerScanOrientation,
} from '@capacitor/barcode-scanner';

defineOptions({ name: 'ScanPage' });

const native = Capacitor.isNativePlatform();
const history = ref([]);
const manual = ref('');
const error = ref('');

const record = code => {
  const value = String(code || '').trim();
  if (!value) return;
  history.value.unshift({ value, at: new Date() });
  history.value = history.value.slice(0, 20);
};

const scan = async () => {
  error.value = '';
  try {
    const res = await CapacitorBarcodeScanner.scanBarcode({
      hint: CapacitorBarcodeScannerTypeHint.ALL,
      scanInstructions: '将条码/二维码对准取景框',
      cameraDirection: CapacitorBarcodeScannerCameraDirection.BACK,
      scanOrientation: CapacitorBarcodeScannerScanOrientation.PORTRAIT,
    });
    if (res?.ScanResult) {
      record(res.ScanResult);
      await Haptics.notification({ type: NotificationType.Success }).catch(
        () => {}
      );
    }
  } catch (e) {
    // 用户取消不算错误
    if (!/cancel/i.test(e?.message || '')) error.value = '扫码失败，请检查相机权限';
  }
};

const submitManual = () => {
  record(manual.value);
  manual.value = '';
};

const fmt = d =>
  `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
</script>

<template>
  <div class="flex flex-col px-4 pt-safeTop">
    <header class="pt-3 pb-4">
      <h1 class="text-2xl font-bold text-n-slate-12">扫码</h1>
      <p class="mt-0.5 text-sm text-n-slate-11">扫产品条码 / 工单二维码</p>
    </header>

    <button
      v-if="native"
      type="button"
      class="flex flex-col items-center justify-center gap-2 py-10 text-white shadow-sm rounded-3xl bg-gradient-to-br from-n-iris-9 to-n-iris-10 active:opacity-90"
      @click="scan"
    >
      <span class="size-10 i-lucide-scan-line" />
      <span class="text-base font-semibold">开始扫码</span>
    </button>

    <!-- 浏览器里没有相机原生能力，降级为手动输入，便于开发调试 -->
    <div
      v-else
      class="p-4 border rounded-2xl border-n-weak bg-n-solid-1"
    >
      <p class="mb-2 text-sm text-n-slate-11">
        当前在浏览器中运行，相机扫码仅在 App 内可用。可手动输入编码调试：
      </p>
      <div class="flex gap-2">
        <input
          v-model="manual"
          type="text"
          placeholder="输入条码"
          class="flex-1 px-3 text-base border rounded-xl h-11 border-n-weak bg-n-solid-1 text-n-slate-12"
          @keyup.enter="submitManual"
        />
        <button
          type="button"
          class="px-4 text-sm font-medium text-white rounded-xl h-11 bg-n-iris-9"
          @click="submitManual"
        >
          记录
        </button>
      </div>
    </div>

    <p v-if="error" class="mt-3 text-sm text-center text-n-ruby-9">
      {{ error }}
    </p>

    <section v-if="history.length" class="mt-6">
      <h2 class="mb-2 text-sm font-semibold text-n-slate-11">本次扫描记录</h2>
      <ul class="flex flex-col gap-2 pb-4">
        <li
          v-for="(item, i) in history"
          :key="i"
          class="flex items-center justify-between gap-3 p-3 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <span class="font-mono text-sm truncate text-n-slate-12">
            {{ item.value }}
          </span>
          <span class="flex-none text-xs text-n-slate-10">
            {{ fmt(item.at) }}
          </span>
        </li>
      </ul>
    </section>
  </div>
</template>
