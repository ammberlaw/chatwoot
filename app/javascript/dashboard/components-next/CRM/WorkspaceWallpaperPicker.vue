<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import WallpaperAPI from 'dashboard/api/workspaceWallpaper';
import {
  WORKSPACE_CARDS,
  copyWorkspaceCardOpacity,
  defaultWorkspaceCardOpacity,
  workspaceCardBackground,
  workspaceCardOpacity,
} from 'dashboard/helper/workspaceCardOpacity';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import WorkspaceWordmark from './WorkspaceWordmark.vue';
import {
  WORKSPACE_HEADER_COLORS,
  workspaceHeaderColor,
} from 'dashboard/helper/workspaceHeaderColor';

const props = defineProps({
  url: { type: String, default: '' },
  cardOpacity: { type: Object, default: defaultWorkspaceCardOpacity },
  headerColor: { type: String, default: 'dark' },
  cardIds: {
    type: Array,
    default: () => WORKSPACE_CARDS.map(card => card.id),
  },
});
const emit = defineEmits(['update', 'preview']);
const { t } = useI18n();
const dialog = ref(null);
const input = ref(null);
const file = ref(null);
const removeWallpaper = ref(false);
const preview = ref('');
const objectUrl = ref('');
const saving = ref(false);
const opened = ref(false);
const target = ref('all');
const draftOpacity = ref(defaultWorkspaceCardOpacity());
const draftHeaderColor = ref('dark');
const headerAppearance = computed(() =>
  workspaceHeaderColor(draftHeaderColor.value)
);
const cards = computed(() =>
  WORKSPACE_CARDS.filter(card => props.cardIds.includes(card.id))
);
const wallpaperChanged = computed(() => !!file.value || removeWallpaper.value);
const changed = computed(
  () =>
    wallpaperChanged.value ||
    draftHeaderColor.value !== props.headerColor ||
    JSON.stringify(draftOpacity.value) !== JSON.stringify(props.cardOpacity)
);
const copy = (key, values) => t(`CRM.WORKSPACE_WALLPAPER.${key}`, values || {});
const transparency = computed({
  get: () => 100 - workspaceCardOpacity(draftOpacity.value, target.value),
  set: value => {
    const opacity = 100 - Number(value);
    draftOpacity.value =
      target.value === 'all'
        ? { all: opacity, overrides: {} }
        : {
            ...draftOpacity.value,
            overrides: {
              ...draftOpacity.value.overrides,
              [target.value]: opacity,
            },
          };
  },
});
const previewPositions = {
  crm: 'col-start-1 row-start-1 row-span-3',
  oa: 'col-start-1 row-start-4',
  hr: 'col-start-1 row-start-5 row-span-2',
  orders: 'col-start-2 row-start-1 row-span-3',
  erp: 'col-start-2 row-start-4 row-span-3',
  team: 'col-start-3 row-start-1 row-span-2',
  tiktok: 'col-start-3 row-start-3',
  docs: 'col-start-3 row-start-4 row-span-3',
  calendar: 'col-start-4 row-start-1 row-span-6',
};
watch(
  [preview, draftOpacity, draftHeaderColor],
  () => {
    if (opened.value) {
      emit('preview', {
        url: preview.value,
        cardOpacity: copyWorkspaceCardOpacity(draftOpacity.value),
        headerColor: draftHeaderColor.value,
      });
    }
  },
  { deep: true }
);

const releasePreview = () => {
  if (objectUrl.value) URL.revokeObjectURL(objectUrl.value);
  objectUrl.value = '';
};
const reset = () => {
  opened.value = false;
  emit('preview', null);
  releasePreview();
  file.value = null;
  removeWallpaper.value = false;
  preview.value = '';
};
const open = () => {
  reset();
  preview.value = props.url;
  target.value = 'all';
  draftOpacity.value = copyWorkspaceCardOpacity(props.cardOpacity);
  draftHeaderColor.value = props.headerColor;
  opened.value = true;
  dialog.value.open();
};
const restoreWallpaper = () => {
  releasePreview();
  file.value = null;
  removeWallpaper.value = !!props.url;
  preview.value = '';
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
    removeWallpaper.value = false;
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
    const { data } = await WallpaperAPI.update(file.value, {
      removeWallpaper: removeWallpaper.value,
      cardOpacity: draftOpacity.value,
      headerColor: draftHeaderColor.value,
    });
    emit('update', data);
    dialog.value.close();
  } catch {
    useAlert(copy('ERROR'));
  } finally {
    saving.value = false;
  }
};
onBeforeUnmount(reset);
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
    overflow-y-auto
    @confirm="save"
    @close="reset"
  >
    <div
      class="relative aspect-video overflow-hidden rounded-2xl border border-n-weak bg-[#f6f7f8] sm:aspect-[16/7]"
    >
      <img
        v-if="preview"
        :src="preview"
        :alt="copy('PREVIEW')"
        class="absolute inset-0 size-full object-cover"
      />
      <div
        class="relative flex h-full flex-col gap-2 p-3 sm:p-4"
        aria-hidden="true"
      >
        <div
          class="flex shrink-0 items-center gap-3"
          :class="headerAppearance.text"
        >
          <WorkspaceWordmark class="h-auto w-12 shrink-0" />
          <span class="truncate text-label-small">{{
            copy('HEADER_PREVIEW')
          }}</span>
        </div>
        <div
          class="grid min-h-0 flex-1 grid-cols-[1.25fr_1fr_1fr_1.15fr] grid-rows-6 gap-1.5 sm:gap-2"
        >
          <div
            v-for="card in cards"
            :key="card.id"
            class="flex min-h-0 items-start overflow-hidden rounded-lg p-1.5 shadow-sm"
            :class="[
              previewPositions[card.id],
              workspaceCardBackground(draftOpacity, card.id),
              target === card.id ? 'ring-2 ring-[#ffca35]' : '',
            ]"
          >
            <span class="truncate text-label-small text-[#202427]">{{
              copy(`CARDS.${card.label}`)
            }}</span>
          </div>
        </div>
      </div>
    </div>
    <fieldset class="m-0 min-w-0 border-0 p-0" :disabled="saving">
      <legend class="mb-2 text-label text-n-slate-12">
        {{ copy('HEADER_COLOR') }}
      </legend>
      <div
        class="flex flex-wrap gap-2"
        role="group"
        :aria-label="copy('HEADER_COLOR')"
      >
        <button
          v-for="color in WORKSPACE_HEADER_COLORS"
          :key="color.id"
          type="button"
          :aria-pressed="draftHeaderColor === color.id"
          :aria-label="copy(`HEADER_COLORS.${color.label}`)"
          :disabled="saving"
          class="flex items-center gap-2 rounded-xl border px-3 py-2 text-label-small text-[#202427] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#202427]"
          :class="
            draftHeaderColor === color.id
              ? 'border-[#ffca35] bg-[#fff7db] ring-1 ring-[#ffca35]'
              : 'border-n-weak bg-white hover:bg-n-alpha-2'
          "
          @click="draftHeaderColor = color.id"
        >
          <span
            class="grid size-5 shrink-0 place-items-center rounded-full border border-black/15"
            :class="color.swatch"
            aria-hidden="true"
          >
            <span
              v-if="draftHeaderColor === color.id"
              class="i-lucide-check size-3"
              :class="color.id === 'dark' ? 'text-white' : 'text-[#202427]'"
            />
          </span>
          {{ copy(`HEADER_COLORS.${color.label}`) }}
        </button>
      </div>
      <p class="mb-0 mt-2 text-label-small text-n-slate-11">
        {{ copy('HEADER_COLOR_HINT') }}
      </p>
    </fieldset>
    <div
      class="grid gap-3 sm:grid-cols-[minmax(0,1fr)_minmax(0,1.4fr)] sm:gap-5"
    >
      <div class="min-w-0">
        <label
          for="workspace-card-target"
          class="mb-2 block text-label text-n-slate-12"
        >
          {{ copy('TARGET') }}
        </label>
        <select
          id="workspace-card-target"
          v-model="target"
          :disabled="saving"
          class="h-9 w-full rounded-xl border border-n-weak bg-white px-3 py-1 text-label text-[#202427] focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#ffca35]"
        >
          <option value="all">{{ copy('ALL_CARDS') }}</option>
          <option v-for="card in cards" :key="card.id" :value="card.id">
            {{ copy(`CARDS.${card.label}`) }}
          </option>
        </select>
      </div>
      <div class="min-w-0">
        <div class="mb-2 flex items-center justify-between gap-2">
          <label
            for="workspace-card-transparency"
            class="text-label text-n-slate-12"
          >
            {{ copy('TRANSPARENCY') }}
          </label>
          <output
            for="workspace-card-transparency"
            class="text-label-small tabular-nums text-n-slate-11"
          >
            {{ copy('TRANSPARENCY_VALUE', { value: transparency }) }}
          </output>
        </div>
        <input
          id="workspace-card-transparency"
          v-model.number="transparency"
          type="range"
          min="0"
          max="100"
          step="5"
          :disabled="saving"
          :aria-valuetext="copy('TRANSPARENCY_VALUE', { value: transparency })"
          class="m-0 h-5 w-full cursor-pointer border-0 bg-transparent p-0 accent-[#ffca35] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#202427] disabled:cursor-wait"
        />
        <div
          class="flex items-center justify-between text-label-small text-n-slate-11"
        >
          <span>{{ copy('OPAQUE') }}</span>
          <span>{{ copy('TRANSPARENT') }}</span>
        </div>
      </div>
    </div>
    <div class="flex items-start gap-3">
      <p class="mb-0 flex-1 text-label-small text-n-slate-11">
        {{ copy('OPACITY_HINT') }}
      </p>
      <button
        type="button"
        :disabled="saving"
        class="shrink-0 rounded-lg px-2 py-1 text-label-small text-n-slate-11 hover:bg-n-alpha-2 disabled:opacity-50"
        @click="draftOpacity = defaultWorkspaceCardOpacity()"
      >
        {{ copy('RESET_OPACITY') }}
      </button>
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
        @click="restoreWallpaper"
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
