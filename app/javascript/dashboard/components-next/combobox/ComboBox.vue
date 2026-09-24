<script setup>
import { ref, computed, watch, nextTick } from 'vue';
import { OnClickOutside } from '@vueuse/components';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import ComboBoxDropdown from 'dashboard/components-next/combobox/ComboBoxDropdown.vue';

const props = defineProps({
  options: {
    type: Array,
    required: true,
    validator: value =>
      value.every(option => 'value' in option && 'label' in option),
  },
  placeholder: { type: String, default: '' },
  // Fallback label shown when the selected value is not in `options` yet
  // (e.g. API-backed lists that load lazily on open).
  displayLabel: { type: String, default: '' },
  modelValue: { type: [String, Number], default: '' },
  disabled: { type: Boolean, default: false },
  searchPlaceholder: { type: String, default: '' },
  emptyState: { type: String, default: '' },
  message: { type: String, default: '' },
  hasError: { type: Boolean, default: false },
  useApiResults: { type: Boolean, default: false }, // useApiResults prop to determine if search is handled by API
  // 选填字段用：选中后在触发器上显示「×」把值清回空。API 搜索型列表选中项常不在当前
  // options 里（懒加载/换关键词后列表已变），靠再点一次同一项取消清不掉，必须给显式出口。
  clearable: { type: Boolean, default: false },
});

const emit = defineEmits(['update:modelValue', 'search', 'open']);

const { t } = useI18n();

const selectedValue = ref(props.modelValue);
const open = ref(false);
const search = ref('');
const dropdownRef = ref(null);
const comboboxRef = ref(null);

const filteredOptions = computed(() => {
  // For API search, don't filter options locally
  if (props.useApiResults && search.value) {
    return props.options;
  }

  // For local search, filter by label + optional searchText (e.g. 关联联系人).
  const searchTerm = search.value.toLowerCase();
  return props.options.filter(option =>
    `${option.label} ${option.searchText || ''}`
      .toLowerCase()
      .includes(searchTerm)
  );
});
const selectPlaceholder = computed(() => {
  return props.placeholder || t('COMBOBOX.PLACEHOLDER');
});
const selectedLabel = computed(() => {
  const selected = props.options.find(
    option => option.value === selectedValue.value
  );
  return selected?.label ?? (props.displayLabel || selectPlaceholder.value);
});

const selectOption = option => {
  if (selectedValue.value === option.value) {
    selectedValue.value = '';
    emit('update:modelValue', '');
  } else {
    selectedValue.value = option.value;
    emit('update:modelValue', option.value);
  }
  open.value = false;
  search.value = '';
};

const showClear = computed(
  () =>
    props.clearable &&
    !props.disabled &&
    selectedValue.value !== '' &&
    selectedValue.value !== null &&
    selectedValue.value !== undefined
);

const clearSelection = () => {
  selectedValue.value = '';
  emit('update:modelValue', '');
  open.value = false;
  search.value = '';
};

const toggleDropdown = () => {
  if (props.disabled) return;
  open.value = !open.value;
  if (open.value) {
    search.value = '';
    emit('open');
    nextTick(() => dropdownRef.value?.focus());
  }
};

watch(
  () => props.modelValue,
  newValue => {
    selectedValue.value = newValue;
  }
);
</script>

<template>
  <div
    ref="comboboxRef"
    class="relative w-full min-w-0"
    :class="{
      'cursor-not-allowed': disabled,
      'group/combobox': !disabled,
    }"
    @click.prevent
  >
    <OnClickOutside @trigger="open = false">
      <Button
        variant="outline"
        :color="hasError && !open ? 'ruby' : open ? 'blue' : 'slate'"
        :label="selectedLabel"
        :title="selectedLabel"
        trailing-icon
        :disabled="disabled"
        no-animation
        class="justify-between w-full !px-3 !py-2.5 text-n-slate-12 font-normal group-hover/combobox:border-n-slate-6 focus:outline-n-brand"
        :class="{
          focused: open,
          '[&:not(.focused)]:dark:outline-n-weak [&:not(.focused)]:hover:enabled:outline-n-slate-6 [&:not(.focused)]:dark:hover:enabled:outline-n-slate-6':
            !hasError,
        }"
        :icon="open ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        @click="toggleDropdown"
      >
        <!-- clearable 时接管默认插槽，在标签与箭头之间插「×」；非 clearable 不传插槽，
             其余调用方渲染路径与外观保持原样。span 而非 button：button 不能嵌套。 -->
        <template v-if="clearable" #default>
          <span class="flex items-center flex-1 min-w-0 gap-2">
            <span
              class="flex-1 min-w-0 text-left truncate"
              :title="selectedLabel"
            >
              {{ selectedLabel }}
            </span>
            <span
              v-if="showClear"
              role="button"
              tabindex="0"
              :aria-label="t('COMBOBOX.CLEAR')"
              class="shrink-0 i-lucide-x size-3.5 text-n-slate-10 hover:text-n-slate-12"
              @click.stop="clearSelection"
              @keydown.enter.stop.prevent="clearSelection"
            />
          </span>
        </template>
      </Button>

      <ComboBoxDropdown
        ref="dropdownRef"
        v-model:search-value="search"
        :open="open"
        :options="filteredOptions"
        :search-placeholder="searchPlaceholder"
        :empty-state="emptyState"
        :selected-values="selectedValue"
        @search="emit('search', $event)"
        @select="selectOption"
      />

      <p
        v-if="message"
        class="mt-2 mb-0 text-xs truncate transition-all duration-500 ease-in-out"
        :class="{
          'text-n-ruby-9': hasError,
          'text-n-slate-11': !hasError,
        }"
      >
        {{ message }}
      </p>
    </OnClickOutside>
  </div>
</template>
