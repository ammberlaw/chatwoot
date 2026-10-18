<script setup>
import { ref, computed, watch, nextTick, onBeforeUnmount } from 'vue';
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

// 下拉面板 Teleport 出去 + fixed 定位。原来是挂在触发器里的 absolute，
// 只要祖先上有 overflow（表格的横向滚动容器、卡片的 overflow-auto）就会被裁掉半截
// ——记账凭证分录表改成可横滚的表格后，科目下拉就只剩一行（用户反馈「筛选只显示一半」）。
// 同 SelectCard：在原生 <dialog> 里就 Teleport 进那个 dialog（顶层），否则回 body。
const POPOVER_MAX_H = 288; // 与面板上的 max-h-72 一致
const GAP = 4;
const OFFSCREEN = { position: 'fixed', top: '-10000px', left: '0px' };
const popStyle = ref({ ...OFFSCREEN });
const teleportTarget = ref('body');
// 打开时挂、关闭时摘：fixed 面板不会跟着容器滚，一滚就关掉最省事（同 SelectCard）。
// 存成变量而不是具名函数，免得它和 closeDropdown 互相引用。
let viewportHandler = null;

const closeDropdown = () => {
  open.value = false;
  popStyle.value = { ...OFFSCREEN };
  if (!viewportHandler) return;

  window.removeEventListener('scroll', viewportHandler, true);
  window.removeEventListener('resize', viewportHandler);
  viewportHandler = null;
};

const positionDropdown = () => {
  const el = comboboxRef.value;
  if (!el) return;

  const r = el.getBoundingClientRect();
  const below = window.innerHeight - r.bottom - GAP - 8;
  const above = r.top - GAP - 8;
  // 下面塞不下、且上面更宽裕才往上翻；钉住一侧再压 maxHeight，
  // 不去量面板高度（量不准会直接盖住触发框，矮屏必现）。
  const flipUp = below < POPOVER_MAX_H && above > below;
  popStyle.value = {
    position: 'fixed',
    ...(flipUp
      ? { bottom: `${window.innerHeight - r.top + GAP}px` }
      : { top: `${r.bottom + GAP}px` }),
    left: `${Math.max(8, Math.min(r.left, window.innerWidth - r.width - 8))}px`,
    width: `${r.width}px`,
    maxHeight: `${Math.max(140, Math.min(POPOVER_MAX_H, flipUp ? above : below))}px`,
  };
};

const selectOption = option => {
  if (selectedValue.value === option.value) {
    selectedValue.value = '';
    emit('update:modelValue', '');
  } else {
    selectedValue.value = option.value;
    emit('update:modelValue', option.value);
  }
  closeDropdown();
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
  closeDropdown();
  search.value = '';
};

const toggleDropdown = () => {
  if (props.disabled) return;
  if (open.value) {
    closeDropdown();
    return;
  }
  teleportTarget.value = comboboxRef.value?.closest('dialog') || 'body';
  open.value = true;
  search.value = '';
  emit('open');
  nextTick(() => {
    positionDropdown();
    dropdownRef.value?.focus();
    // ⚠️ 面板**内部**的滚动不能关下拉：捕获阶段监听的是所有 scroll，选项多时用户在
    // 列表里滚鼠标也会被捕获，一滚就关——看起来就是「下拉滑不动，点箭头也没用」
    // （10.17 反馈 B1，新建采购单的「关联生产工单」）。
    // 只有面板外面的滚动（页面、表格横滚容器）才关：fixed 面板不跟着那些容器走，留着会错位。
    viewportHandler = event => {
      // 认 .combobox-dropdown（面板根节点自带的类，本来就给「点外部关闭」排除用）。
      // 不走 dropdownRef：那是组件实例，$el 在多根节点时可能是注释节点，contains 不可靠。
      const target = event?.target;
      if (target?.closest?.('.combobox-dropdown')) return;

      closeDropdown();
    };
    window.addEventListener('scroll', viewportHandler, true);
    window.addEventListener('resize', viewportHandler);
  });
};

onBeforeUnmount(closeDropdown);

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
    <OnClickOutside
      :options="{ ignore: ['.combobox-dropdown'] }"
      @trigger="closeDropdown"
    >
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

      <teleport :to="teleportTarget">
        <ComboBoxDropdown
          ref="dropdownRef"
          v-model:search-value="search"
          :open="open"
          :options="filteredOptions"
          :search-placeholder="searchPlaceholder"
          :empty-state="emptyState"
          :selected-values="selectedValue"
          :style="popStyle"
          @search="emit('search', $event)"
          @select="selectOption"
        />
      </teleport>

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
