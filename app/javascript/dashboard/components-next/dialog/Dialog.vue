<script setup>
import { ref, computed } from 'vue';
import { OnClickOutside } from '@vueuse/components';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';

const props = defineProps({
  type: {
    type: String,
    default: 'edit',
    validator: value => ['alert', 'edit'].includes(value),
  },
  title: {
    type: String,
    default: '',
  },
  description: {
    type: String,
    default: '',
  },
  cancelButtonLabel: {
    type: String,
    default: '',
  },
  confirmButtonLabel: {
    type: String,
    default: '',
  },
  // 覆盖确认按钮颜色；留空时按 type 沿用默认(edit→blue / 其它→ruby)。
  confirmButtonColor: {
    type: String,
    default: '',
  },
  disableConfirmButton: {
    type: Boolean,
    default: false,
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
  showCancelButton: {
    type: Boolean,
    default: true,
  },
  showConfirmButton: {
    type: Boolean,
    default: true,
  },
  overflowYAuto: {
    type: Boolean,
    default: false,
  },
  width: {
    type: String,
    default: 'lg',
    validator: value =>
      ['6xl', '5xl', '4xl', '3xl', '2xl', 'xl', 'lg', 'md', 'sm'].includes(
        value
      ),
  },
  position: {
    type: String,
    default: 'center',
    validator: value => ['center', 'top'].includes(value),
  },
  // false=点弹窗外部 / 按 Esc 不关闭（防误点丢失未保存内容，表单类弹窗用）。
  dismissible: {
    type: Boolean,
    default: true,
  },
  // 右上角关闭 X。弹窗一律有它：内容比屏幕高时底部按钮点不到，没有 X 就出不去了。
  showCloseButton: {
    type: Boolean,
    default: true,
  },
});

const emit = defineEmits(['confirm', 'close']);

const { t } = useI18n();

const dialogRef = ref(null);
const dialogContentRef = ref(null);
const isOpen = ref(false);

const maxWidthClass = computed(() => {
  const classesMap = {
    '6xl': 'max-w-6xl',
    '5xl': 'max-w-5xl',
    '4xl': 'max-w-4xl',
    '3xl': 'max-w-3xl',
    '2xl': 'max-w-2xl',
    xl: 'max-w-xl',
    lg: 'max-w-lg',
    md: 'max-w-md',
    sm: 'max-w-sm',
  };

  return classesMap[props.width] ?? 'max-w-md';
});

const positionClass = computed(() =>
  props.position === 'top' ? 'dialog-position-top' : ''
);

const open = () => {
  isOpen.value = true;
  dialogRef.value?.showModal();
};

const close = () => {
  emit('close');
  dialogRef.value?.close();
  isOpen.value = false;
};

// Only close if the close event originated from this dialog,
// not from a child dialog (e.g. ProseMirror prompt) bubbling up.
const handleDialogClose = e => e.target === dialogRef.value && close();

// Only close on click-outside if this dialog is the topmost one.
// If another dialog (e.g. ProseMirror prompt) is open on top, ignore.
// dismissible=false（表单类）时点外部不关，防误点丢失未保存内容。
const handleClickOutside = () => {
  if (!props.dismissible) return;
  const dialogs = document.querySelectorAll('dialog[open]');
  if (dialogs[dialogs.length - 1] === dialogRef.value) close();
};

// 原生 <dialog> 的 Esc 触发 cancel→close；dismissible=false 时拦截 Esc，同样不关。
const handleCancel = e => {
  if (!props.dismissible) e.preventDefault();
};

const confirm = () => {
  emit('confirm');
};

defineExpose({ open, close });
</script>

<template>
  <TeleportWithDirection to="body">
    <dialog
      ref="dialogRef"
      class="w-full transition-all duration-300 ease-in-out shadow-xl rounded-xl"
      :class="[
        maxWidthClass,
        positionClass,
        overflowYAuto ? 'overflow-y-auto' : 'overflow-visible',
      ]"
      @close.prevent="handleDialogClose"
      @cancel="handleCancel"
    >
      <!-- 忽略 Teleport 出去的玻璃弹层（DatePicker/SelectCard/MonthPicker 等，标 data-glass-popover）：
           它们是对话框内容的兄弟节点，点选项不该被当「点外部」关掉整个对话框。@vueuse 走 capture 阶段，
           光靠弹层 @pointerdown.stop 拦不住，必须在此按 composedPath 忽略。 -->
      <OnClickOutside
        :options="{ ignore: ['[data-glass-popover]'] }"
        @trigger="handleClickOutside"
      >
        <form
          ref="dialogContentRef"
          class="relative flex flex-col w-full h-auto gap-6 p-6 overflow-visible text-start align-middle transition-all duration-300 ease-in-out transform bg-n-alpha-3 backdrop-blur-[100px] shadow-xl rounded-xl"
          @submit.prevent="confirm"
          @click.stop
        >
          <div
            v-if="title || description"
            class="flex flex-col gap-2"
            :class="showCloseButton ? 'pr-8' : ''"
          >
            <h3 class="text-base font-medium leading-6 text-n-slate-12">
              {{ title }}
            </h3>
            <slot name="description">
              <p v-if="description" class="mb-0 text-sm text-n-slate-11">
                {{ description }}
              </p>
            </slot>
          </div>
          <slot v-if="isOpen" />
          <!-- Dialog content will be injected here -->
          <slot name="footer">
            <!-- 长表单（overflowYAuto）里按钮粘在底部：BOM/采购单几十行明细时，
                 原来要一路滚到底才点得到保存。短对话框不滚动，sticky 不起作用、外观不变。 -->
            <!-- 底部只有一个「关闭/取消」、没有确认动作时不再渲染这条：退出统一走右上角 X
                 （弹窗比屏幕高时底部点不到，正是「预览采购单出不去」那个问题）。
                 有确认动作的表单照旧保留底部「取消 + 保存」。 -->
            <div
              v-if="showConfirmButton || (showCancelButton && !showCloseButton)"
              class="flex items-center justify-between w-full gap-3"
              :class="
                overflowYAuto
                  ? 'sticky bottom-0 z-10 -mx-6 -mb-6 px-6 py-4 bg-n-alpha-3 backdrop-blur-[100px] rounded-b-xl'
                  : ''
              "
            >
              <Button
                v-if="showCancelButton"
                variant="faded"
                color="slate"
                :label="cancelButtonLabel || t('DIALOG.BUTTONS.CANCEL')"
                class="w-full"
                type="button"
                @click="close"
              />
              <Button
                v-if="showConfirmButton"
                :color="
                  confirmButtonColor || (type === 'edit' ? 'blue' : 'ruby')
                "
                :label="confirmButtonLabel || t('DIALOG.BUTTONS.CONFIRM')"
                class="w-full"
                :is-loading="isLoading"
                :disabled="disableConfirmButton || isLoading"
                type="submit"
              />
            </div>
          </slot>
          <!-- 右上角关闭 X。放在最后而不是标题旁：原生 <dialog> 打开时自动聚焦第一个可聚焦元素，
               X 若排在前面会抢走输入框的初始焦点，回车也会变成「关闭」而不是「保存」。 -->
          <button
            v-if="showCloseButton"
            type="button"
            :aria-label="t('DIALOG.BUTTONS.CANCEL')"
            class="absolute z-20 flex items-center justify-center rounded-lg top-4 right-4 size-8 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
            @click="close"
          >
            <Icon icon="i-lucide-x" class="size-4" />
          </button>
        </form>
      </OnClickOutside>
    </dialog>
  </TeleportWithDirection>
</template>

<style scoped>
dialog::backdrop {
  @apply bg-n-alpha-black1 backdrop-blur-[4px];
}

.dialog-position-top {
  margin-top: clamp(2rem, 5vh, 5rem);
  margin-bottom: auto;
}

/* 手机端：弹窗改「底部抽屉」——全宽贴底、顶部圆角、内容自适应(超高可滚)，
   避免短内容居中/顶对齐时下方留一大片空白背景。 */
@media (max-width: 767px) {
  dialog {
    width: 100%;
    max-width: 100%;
    margin: auto 0 0 0;
    max-height: 92vh;
    border-bottom-left-radius: 0;
    border-bottom-right-radius: 0;
  }
  .dialog-position-top {
    margin-top: auto;
  }
  dialog form {
    border-bottom-left-radius: 0;
    border-bottom-right-radius: 0;
  }
}
</style>
