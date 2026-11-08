<script setup>
import { computed, onBeforeUnmount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import WallpaperAPI from 'dashboard/api/workspaceWallpaper';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({ url: { type: String, default: '' } });
const emit = defineEmits(['update']);
const { t } = useI18n();
const dialog = ref(null);
const input = ref(null);
const file = ref(null);
const preview = ref('');
const objectUrl = ref('');
const saving = ref(false);
const changed = computed(() => !!file.value || preview.value !== props.url);
const copy = key => t(`CRM.WORKSPACE_WALLPAPER.${key}`);

const releasePreview = () => {
  if (objectUrl.value) URL.revokeObjectURL(objectUrl.value);
  objectUrl.value = '';
};
const reset = () => {
  releasePreview();
  file.value = null;
  preview.value = '';
};
const open = () => {
  reset();
  preview.value = props.url;
  dialog.value.open();
};
const selectFile = async event => {
  const selected = event.target.files?.[0];
  event.target.value = '';
  if (!selected) return;
  if (
    !['image/jpeg', 'image/png', 'image/webp'].includes(selected.type) ||
    !selected.size ||
    selected.size > 10 * 1024 * 1024
  ) {
    useAlert(copy('INVALID'));
    return;
  }
  const candidateUrl = URL.createObjectURL(selected);
  try {
    const image = new Image();
    image.src = candidateUrl;
    await image.decode();
    releasePreview();
    objectUrl.value = candidateUrl;
    file.value = selected;
    preview.value = candidateUrl;
  } catch {
    URL.revokeObjectURL(candidateUrl);
    useAlert(copy('INVALID'));
  }
};
const save = async () => {
  if (saving.value || !changed.value) return;
  saving.value = true;
  try {
    const { data } = file.value
      ? await WallpaperAPI.update(file.value)
      : await WallpaperAPI.delete();
    emit('update', data.url || '');
    dialog.value.close();
  } catch {
    useAlert(copy('ERROR'));
  } finally {
    saving.value = false;
  }
};
onBeforeUnmount(releasePreview);
defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialog"
    :title="copy('TITLE')"
    :description="copy('DESCRIPTION')"
    :confirm-button-label="copy('APPLY')"
    :disable-confirm-button="saving || !changed"
    :is-loading="saving"
    :dismissible="!saving"
    :show-close-button="!saving"
    :show-cancel-button="!saving"
    @confirm="save"
    @close="reset"
  >
    <div
      class="relative aspect-video overflow-hidden rounded-2xl border border-n-weak bg-[#f6f7f8]"
    >
      <img
        v-if="preview"
        :src="preview"
        :alt="copy('PREVIEW')"
        class="absolute inset-0 size-full object-cover"
      />
      <div class="absolute inset-0 bg-white/25" />
      <div
        class="relative grid h-full grid-cols-3 gap-3 p-6"
        aria-hidden="true"
      >
        <div class="rounded-xl bg-white/90 shadow-sm" />
        <div class="grid grid-rows-2 gap-3">
          <div class="rounded-xl bg-white/90 shadow-sm" />
          <div class="rounded-xl bg-white/90 shadow-sm" />
        </div>
        <div class="rounded-xl bg-white/90 shadow-sm" />
      </div>
    </div>
    <div class="flex flex-wrap items-center gap-3">
      <button
        type="button"
        :disabled="saving"
        class="flex items-center gap-2 rounded-xl bg-n-slate-12 px-4 py-2 text-label text-n-solid-1 disabled:opacity-50"
        @click="input.click()"
      >
        <span class="i-lucide-image-plus size-4" aria-hidden="true" />
        {{ copy('UPLOAD') }}
      </button>
      <button
        type="button"
        :disabled="saving || !preview"
        class="rounded-xl px-3 py-2 text-label text-n-slate-11 hover:bg-n-alpha-2 disabled:opacity-50"
        @click="reset"
      >
        {{ copy('RESET') }}
      </button>
      <input
        ref="input"
        type="file"
        accept="image/jpeg,image/png,image/webp"
        class="hidden"
        :aria-label="copy('UPLOAD')"
        @change="selectFile"
      />
    </div>
    <p class="mb-0 text-label-small text-n-slate-11">{{ copy('HINT') }}</p>
  </Dialog>
</template>
