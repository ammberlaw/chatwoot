<script setup>
import CrmFolderArtwork from 'dashboard/components-next/CRM/CrmFolderArtwork.vue';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import {
  DOC_FOLDER_STYLES,
  useDocFolderStyle,
} from 'dashboard/composables/useDocFolderStyle';
import authAPI from 'dashboard/api/auth';
import types from 'dashboard/store/mutation-types';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const { t } = useI18n();
const store = useStore();
const { uiSettings, folderStyle } = useDocFolderStyle();
const dialog = ref(null);
const selected = ref('default');
const saving = ref(false);
const targetKey = ref('');
const targetName = ref('');
const currentSelection = computed(() =>
  targetKey.value
    ? uiSettings.value.doc_folder_styles?.[targetKey.value] || 'inherit'
    : folderStyle.value.id
);
const choices = DOC_FOLDER_STYLES.filter(style => style.image);
const copy = key => t(`CRM.KNOWLEDGE_DOCS.FOLDER_STYLE.${key}`);
const open = ({ key = '', name = '' } = {}) => {
  targetKey.value = key;
  targetName.value = name;
  selected.value = currentSelection.value;
  dialog.value.open();
};
const save = async () => {
  saving.value = true;
  const updates = targetKey.value
    ? { doc_folder_styles: { ...uiSettings.value.doc_folder_styles } }
    : { doc_folder_style: selected.value };
  if (targetKey.value) {
    if (selected.value === 'inherit') {
      delete updates.doc_folder_styles[targetKey.value];
    } else {
      updates.doc_folder_styles[targetKey.value] = selected.value;
    }
  }
  try {
    await authAPI.updateUISettings({
      uiSettings: { ...uiSettings.value, ...updates },
    });
    store.commit(types.SET_CURRENT_USER_UI_SETTINGS, {
      uiSettings: updates,
    });
    dialog.value.close();
  } catch {
    useAlert(copy('SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
};
defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialog"
    width="xl"
    overflow-y-auto
    :title="
      targetKey
        ? t('CRM.KNOWLEDGE_DOCS.FOLDER_STYLE.FOLDER_TITLE', {
            name: targetName,
          })
        : copy('TITLE')
    "
    :description="copy(targetKey ? 'FOLDER_DESCRIPTION' : 'DESCRIPTION')"
    :confirm-button-label="copy('APPLY')"
    :is-loading="saving"
    :disable-confirm-button="saving || selected === currentSelection"
    :dismissible="!saving"
    :show-close-button="!saving"
    :show-cancel-button="!saving"
    confirm-button-color="iris"
    @confirm="save"
  >
    <div
      class="grid grid-cols-2 gap-3 sm:grid-cols-3"
      :aria-label="copy('TITLE')"
    >
      <button
        v-for="choice in choices"
        :key="choice.id"
        type="button"
        :disabled="saving"
        :aria-pressed="selected === choice.id"
        :aria-label="copy(choice.label)"
        class="relative flex min-w-0 flex-col items-center gap-2 rounded-2xl border p-2 transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-iris-8"
        :class="
          selected === choice.id
            ? 'border-n-iris-8 bg-n-iris-2 ring-1 ring-n-iris-8'
            : 'border-n-weak bg-n-solid-1 hover:border-n-iris-6'
        "
        @click="selected = choice.id"
      >
        <CrmFolderArtwork
          :image="choice.image"
          :animated="choice.animated"
          class="aspect-square w-full rounded-xl bg-white"
        />
        <span class="pb-1 text-label-small text-n-slate-12">{{
          copy(choice.label)
        }}</span>
        <span
          v-if="selected === choice.id"
          class="absolute right-2 top-2 grid size-5 place-items-center rounded-full bg-n-iris-9 text-white"
          aria-hidden="true"
          ><span class="i-lucide-check size-3"
        /></span>
      </button>
    </div>
    <button
      v-if="targetKey"
      type="button"
      :disabled="saving"
      :aria-pressed="selected === 'inherit'"
      class="mt-4 flex w-full items-center gap-3 rounded-xl border px-4 py-3 text-label text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-iris-8"
      :class="
        selected === 'inherit'
          ? 'border-n-iris-8 bg-n-iris-2'
          : 'border-n-weak bg-n-solid-1 hover:border-n-iris-6'
      "
      @click="selected = 'inherit'"
    >
      <span class="i-lucide-undo-2 size-5 text-n-slate-11" aria-hidden="true" />
      <span class="flex-1 text-left">{{ copy('INHERIT') }}</span>
      <span
        v-if="selected === 'inherit'"
        class="i-lucide-check size-4 text-n-iris-11"
        aria-hidden="true"
      />
    </button>
    <button
      type="button"
      :disabled="saving"
      :aria-pressed="selected === 'default'"
      class="mt-4 flex w-full items-center gap-3 rounded-xl border px-4 py-3 text-label text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-iris-8"
      :class="
        selected === 'default'
          ? 'border-n-iris-8 bg-n-iris-2'
          : 'border-n-weak bg-n-solid-1 hover:border-n-iris-6'
      "
      @click="selected = 'default'"
    >
      <span class="i-lucide-folder size-5 text-n-iris-11" aria-hidden="true" />
      <span class="flex-1 text-left">{{ copy('DEFAULT') }}</span>
      <span
        v-if="selected === 'default'"
        class="i-lucide-check size-4 text-n-iris-11"
        aria-hidden="true"
      />
    </button>
  </Dialog>
</template>
