<script setup>
import { ref, computed, nextTick } from 'vue';
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
  // 表单有未保存改动。为 true 时，用户发起的关闭（X / 取消 / 点外部 / Esc）
  // 不直接关，先弹三选一；程序化的 close()（保存成功后调用）不受影响。
  dirty: {
    type: Boolean,
    default: false,
  },
  // 未保存提醒里「保存」按钮的文案。传空串则只给「继续编辑 / 不保存」两项，
  // 适合保存动作不在本弹窗内、或必填项没齐就存不了的场景。
  dirtySaveLabel: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['confirm', 'close', 'save']);

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

// 关闭 X 排在内容最前面（sticky 要钉在顶部就必须在流的开头），而原生 dialog
// 打开时会把初始焦点给第一个可聚焦元素——落在 X 上回车就变成「关闭」而不是「保存」。
// 所以打开后手动把焦点交还给第一个输入控件（没有输入控件的提示类对话框给主按钮）。
const FOCUSABLE_FIELD_SELECTOR =
  'input:not([type="hidden"]):not([disabled]), textarea:not([disabled]), select:not([disabled]), [contenteditable="true"], button[type="submit"]';

const focusFirstField = () => {
  const root = dialogContentRef.value;
  if (!root) return;
  // 只认真正看得见的控件：隐藏的（如折叠区里的输入框）focus() 不会生效，
  // 焦点就留在 X 上了，回车还是会变成「关闭」。
  const target = [...root.querySelectorAll(FOCUSABLE_FIELD_SELECTOR)].find(
    el => el.offsetParent !== null
  );
  target?.focus();
};

const open = () => {
  isOpen.value = true;
  dialogRef.value?.showModal();
  // 内容是 <slot v-if="isOpen">，翻转后还要一帧才真正挂上，所以等渲染完再交焦点。
  nextTick(() => requestAnimationFrame(focusFirstField));
};

// 未保存提醒的显示状态。盖在表单上层，不另开一个 <dialog>——
// 原生 dialog 已经在顶层，再叠一个只会多一层焦点/Esc 的纠缠。
const isConfirmingDiscard = ref(false);

// 程序化关闭：保存成功后由页面调用，永远直接关，不拦。
const close = () => {
  isConfirmingDiscard.value = false;
  emit('close');
  dialogRef.value?.close();
  isOpen.value = false;
};

// 长表单（overflowYAuto）里滚动容器是 <dialog> 本身，提醒层按整个表单高度定位。
// 不先滚回顶部的话，人滚到第 30 行明细点关闭，提醒框会落在屏幕外＝像点了没反应。
const showDiscardConfirm = () => {
  dialogRef.value?.scrollTo?.({ top: 0 });
  isConfirmingDiscard.value = true;
};

// 用户发起的关闭（X / 取消 / 点外部 / Esc）都走这里：脏了先问。
const requestClose = () => {
  if (props.dirty) {
    showDiscardConfirm();
    return;
  }
  close();
};

// 「不保存」：丢弃改动直接关。基线的重置统一挂在 @close 上——
// 那条路同时覆盖「放弃」和「保存成功后关闭」，不然存完 isDirty 还挂着，
// 刷新页面会被浏览器再拦一道。
const discardAndClose = () => close();

// Only close if the close event originated from this dialog,
// not from a child dialog (e.g. ProseMirror prompt) bubbling up.
const handleDialogClose = e => e.target === dialogRef.value && close();

// Only close on click-outside if this dialog is the topmost one.
// If another dialog (e.g. ProseMirror prompt) is open on top, ignore.
// dismissible=false（表单类）时点外部不关，防误点丢失未保存内容。
const handleClickOutside = () => {
  if (!props.dismissible) return;
  const dialogs = document.querySelectorAll('dialog[open]');
  if (dialogs[dialogs.length - 1] === dialogRef.value) requestClose();
};

// 原生 <dialog> 的 Esc 触发 cancel→close；dismissible=false 时拦截 Esc，同样不关。
const handleCancel = e => {
  if (!props.dismissible) {
    e.preventDefault();
    return;
  }
  // 可关闭但有未保存改动：拦下 Esc，改成弹提醒。
  if (props.dirty) {
    e.preventDefault();
    showDiscardConfirm();
  }
};

const confirm = () => {
  emit('confirm');
};

// 表单提交：对话框内容包在 <form> 里，而原生 <button> 不写 type 就是 submit——
// 弹窗里随手一个「添加附件 / 加一行」按钮都会连带把表单交掉（点附件自动交单就是这么来的）。
// 只认「显式写了 type=submit」的按钮（对话框自己的确认键、页面自定的提交键），
// 以及回车提交（submitter 为空）；没标记的按钮一律当普通按钮放过。
const onSubmit = event => {
  const submitter = event.submitter;
  if (submitter && submitter.getAttribute('type') !== 'submit') return;
  confirm();
};

// 未保存提醒里的「保存」：先把提醒层收掉再交给页面存。
// 存成功页面自己会 close()；存失败（必填没齐等）就退回表单，
// 否则错误提示被压在提醒层底下，人只看见一个不动的弹窗。
const saveFromDiscardPrompt = () => {
  isConfirmingDiscard.value = false;
  emit('save');
};

defineExpose({ open, close, requestClose });
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
          @submit.prevent="onSubmit"
          @click.stop
        >
          <!-- 右上角关闭 X：零高度 sticky 壳。原来是 absolute 挂在内容上，长表单往下滚它
               就跟着跑了，得先滚回顶部才点得到（用户原话）。sticky 只能「不让元素滚出顶部」、
               不会把它提上来，所以必须排在内容最前面；h-0 + -mb-6 抵掉 flex gap，不占布局。
               初始焦点的问题在 open() 里用 focusFirstField 解决。 -->
          <div
            v-if="showCloseButton"
            class="sticky top-4 z-20 flex justify-end h-0 -mb-6 pointer-events-none"
          >
            <button
              type="button"
              :aria-label="t('DIALOG.BUTTONS.CANCEL')"
              class="flex items-center justify-center mr-4 rounded-lg pointer-events-auto size-8 text-n-slate-11 bg-n-alpha-3 backdrop-blur hover:bg-n-alpha-2 hover:text-n-slate-12"
              @click="requestClose"
            >
              <Icon icon="i-lucide-x" class="size-4" />
            </button>
          </div>

          <!-- 右侧留白要让开 X 按钮：它宽 size-8(2rem) + mr-4(1rem) = 3rem，
               再留半格缝 = pr-14。原来写 pr-8 少了 16px，标题右边的操作按钮
               （导出 Excel / 导出图片 / 打印）最后一个会被 X 压住半截。 -->
          <div
            v-if="title || description"
            class="flex flex-col gap-2"
            :class="showCloseButton ? 'pr-14' : ''"
          >
            <!-- 标题行：左边标题（可塞状态药丸），右边放操作按钮（导出/打印之类），
                 一行放得下就不要再单起一行，否则标题下面空一大片。 -->
            <div class="flex items-center justify-between gap-3">
              <h3 class="text-base font-medium leading-6 text-n-slate-12">
                <slot name="title">{{ title }}</slot>
              </h3>
              <slot name="headerActions" />
            </div>
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
                @click="requestClose"
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

          <!-- 未保存提醒。盖在表单上层而不是再开一个 <dialog>：
               原生 dialog 已在顶层，叠第二个只会多一层焦点和 Esc 的纠缠。
               做成「遮罩 + 居中小卡」而不是整片铺满：长表单弹窗能有一两千像素高，
               铺满会糊出一大片空白，看着像页面坏了。 -->
          <div
            v-if="isConfirmingDiscard"
            class="absolute inset-0 z-30 flex items-start justify-center p-6 pt-16 rounded-xl bg-n-alpha-black1 backdrop-blur-[4px]"
          >
            <div
              class="flex flex-col w-full gap-5 p-6 shadow-xl max-w-md rounded-xl bg-n-alpha-3 backdrop-blur-[100px]"
            >
              <div class="flex flex-col gap-2">
                <h3 class="text-base font-medium leading-6 text-n-slate-12">
                  {{ t('DIALOG.UNSAVED.TITLE') }}
                </h3>
                <p class="mb-0 text-sm text-n-slate-11">
                  {{ t('DIALOG.UNSAVED.DESCRIPTION') }}
                </p>
              </div>
              <div class="flex items-center justify-end gap-2">
                <Button
                  variant="faded"
                  color="slate"
                  :label="t('DIALOG.UNSAVED.KEEP_EDITING')"
                  type="button"
                  @click="isConfirmingDiscard = false"
                />
                <Button
                  variant="outline"
                  color="ruby"
                  :label="t('DIALOG.UNSAVED.DISCARD')"
                  type="button"
                  @click="discardAndClose"
                />
                <!-- 走独立的 save 事件而不是复用 confirm：confirm 同时绑着表单 submit，
                     复用会让长表单里随手敲个回车就变成「保存并关闭」。 -->
                <Button
                  v-if="dirtySaveLabel"
                  color="blue"
                  :label="dirtySaveLabel"
                  type="button"
                  :is-loading="isLoading"
                  :disabled="disableConfirmButton || isLoading"
                  @click="saveFromDiscardPrompt"
                />
              </div>
            </div>
          </div>
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
