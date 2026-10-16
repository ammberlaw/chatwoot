<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  open: {
    type: Boolean,
    required: true,
  },
  options: {
    type: Array,
    required: true,
  },
  searchPlaceholder: {
    type: String,
    default: '',
  },
  emptyState: {
    type: String,
    default: '',
  },
  multiple: {
    type: Boolean,
    default: false,
  },
  selectedValues: {
    type: [String, Number, Array],
    default: () => [],
  },
});

const emit = defineEmits(['select', 'search']);

const { t } = useI18n();

const searchValue = defineModel('searchValue', {
  type: String,
  default: '',
});

const searchInput = ref(null);

// 键盘选中：打完字直接回车，不用再拿鼠标点一下。
// ↑/↓ 移动高亮，回车选中高亮项；选项变了（重新搜索）就回到第一条。
const highlighted = ref(0);
watch(
  () => props.options,
  () => {
    highlighted.value = 0;
  }
);

const move = step => {
  const total = props.options.length;
  if (!total) return;
  highlighted.value = (highlighted.value + step + total) % total;
};

const confirmHighlighted = () => {
  const option = props.options[highlighted.value];
  if (option) emit('select', option);
};

const isSelected = option => {
  if (Array.isArray(props.selectedValues)) {
    return props.selectedValues.includes(option.value);
  }
  return option.value === props.selectedValues;
};

const onInputSearch = event => {
  searchValue.value = event.target.value;
  emit('search', event.target.value);
};

// 自己画清空按钮，不用 type="search" 自带的那颗——浏览器原生的那颗点下去
// 只擦掉框里的字，不走 input 事件，列表还停在「未找到结果」（用户点名：这个按键是无效的）。
const clearSearch = () => {
  searchValue.value = '';
  emit('search', '');
  searchInput.value?.focus();
};

defineExpose({
  focus: () => searchInput.value?.focus(),
});
</script>

<template>
  <!-- 定位交给父组件（Teleport 出去 + fixed），这里只管长相。
       combobox-dropdown：给 ComboBox 自己的「点外部关闭」排除用。
       data-glass-popover：Dialog 的点外部判断按它忽略（@vueuse 走 capture 阶段，
       光在这里 @click.stop 拦不住），否则点一下选项会把整个对话框关掉。 -->
  <div
    v-show="open"
    data-glass-popover
    class="combobox-dropdown z-50 overflow-hidden transition-opacity duration-200 border rounded-md shadow-lg bg-n-solid-1 border-n-strong"
  >
    <div class="relative border-b border-n-strong">
      <span class="absolute i-lucide-search top-2.5 size-4 left-3" />
      <input
        ref="searchInput"
        :value="searchValue"
        type="text"
        :placeholder="searchPlaceholder || t('COMBOBOX.SEARCH_PLACEHOLDER')"
        class="reset-base w-full py-2 pl-10 pr-9 text-sm focus:outline-none border-none rounded-t-md bg-n-solid-1 text-n-slate-12"
        @input="onInputSearch"
        @keydown.down.prevent="move(1)"
        @keydown.up.prevent="move(-1)"
        @keydown.esc.prevent.stop="clearSearch"
        @keydown.enter.prevent.stop="confirmHighlighted"
      />
      <button
        v-if="searchValue"
        type="button"
        class="absolute grid rounded top-1.5 right-2 size-6 place-items-center text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12"
        :title="t('COMBOBOX.CLEAR_SEARCH')"
        @click.stop="clearSearch"
      >
        <span class="i-lucide-x size-3.5 shrink-0" />
      </button>
    </div>
    <ul
      class="py-1 mb-0 overflow-auto max-h-60"
      role="listbox"
      :aria-multiselectable="multiple"
    >
      <li
        v-for="(option, index) in options"
        :key="`${option.value}-${index}`"
        class="flex items-center justify-between w-full gap-2 px-3 py-2 text-sm transition-colors duration-150 cursor-pointer"
        :class="
          isSelected(option)
            ? 'bg-n-iris-9 text-white font-medium'
            : index === highlighted
              ? 'bg-n-alpha-2'
              : 'hover:bg-n-alpha-2'
        "
        role="option"
        :aria-selected="isSelected(option)"
        @click.stop="emit('select', option)"
        @mouseenter="highlighted = index"
      >
        <span
          :class="isSelected(option) ? 'text-white' : 'text-n-slate-12'"
          :title="option.label"
        >
          {{ option.label }}
        </span>
        <span
          v-if="isSelected(option)"
          class="flex-shrink-0 i-lucide-check size-4"
        />
      </li>
      <li v-if="options.length === 0" class="px-3 py-2 text-sm text-n-slate-11">
        {{ emptyState || t('COMBOBOX.EMPTY_STATE') }}
      </li>
    </ul>
  </div>
</template>
