<script setup>
// 表头漏斗筛选（对标金蝶）：点列头的漏斗，选条件 + 填值 → 服务端按这一列筛。
// 筛选在服务端做：列表是分页的，只筛当前这 50 行等于骗人——翻到第二页又出现了。
//
// 浮层 teleport 进最近的 <dialog>（原生 dialog 在顶层，挂 body 会被盖住，
// 见 DatePicker 里同一套写法）。
import { ref, computed, nextTick, onBeforeUnmount } from 'vue';

const props = defineProps({
  // { op, value }；op 为空＝这一列没筛
  modelValue: { type: Object, default: () => ({}) },
  // 'text' 文本列（八种条件）| 'enum' 取值固定的列（只给「等于/不等于/为空/不为空」+ 下拉）
  kind: { type: String, default: 'text' },
  // kind='enum' 时的候选：[{ value, label }]
  options: { type: Array, default: () => [] },
});
const emit = defineEmits(['update:modelValue', 'change']);

const TEXT_OPS = [
  { value: 'contains', label: '包含' },
  { value: 'not_contains', label: '不包含' },
  { value: 'eq', label: '等于' },
  { value: 'ne', label: '不等于' },
  { value: 'starts', label: '以……开始' },
  { value: 'ends', label: '以……结束' },
  { value: 'blank', label: '为空' },
  { value: 'present', label: '不为空' },
];
const ENUM_OPS = TEXT_OPS.filter(o =>
  ['eq', 'ne', 'blank', 'present'].includes(o.value)
);
const ops = computed(() => (props.kind === 'enum' ? ENUM_OPS : TEXT_OPS));
// 「为空 / 不为空」不需要填值
const NEEDS_VALUE = op => op && !['blank', 'present'].includes(op);

const active = computed(() => !!props.modelValue?.op);
const open = ref(false);
const triggerEl = ref(null);
const popEl = ref(null);
const popStyle = ref({});
const teleportTarget = ref('body');
const draftOp = ref('contains');
const draftValue = ref('');

const position = () => {
  const r = triggerEl.value?.getBoundingClientRect();
  if (!r) return;
  const w = 240;
  const h = popEl.value?.offsetHeight || 300;
  const below = r.bottom + 6;
  const top =
    below + h > window.innerHeight && r.top - h - 6 > 0 ? r.top - h - 6 : below;
  const left = Math.max(8, Math.min(r.left, window.innerWidth - w - 8));
  popStyle.value = { position: 'fixed', top: `${top}px`, left: `${left}px` };
};

const close = () => {
  open.value = false;
  window.removeEventListener('scroll', position, true);
  window.removeEventListener('resize', position);
};

const toggle = async () => {
  if (open.value) return close();
  draftOp.value = props.modelValue?.op || ops.value[0].value;
  draftValue.value = props.modelValue?.value ?? '';
  teleportTarget.value = triggerEl.value?.closest('dialog') || 'body';
  open.value = true;
  await nextTick();
  position();
  // 表格是横向滚动的，列头跟着走，浮层得贴着它
  window.addEventListener('scroll', position, true);
  window.addEventListener('resize', position);
};

const apply = () => {
  const next = NEEDS_VALUE(draftOp.value)
    ? { op: draftOp.value, value: String(draftValue.value).trim() }
    : { op: draftOp.value, value: '' };
  // 选了「包含」却没填值＝什么都没筛，当作清空，不然列头亮着漏斗却筛不出东西
  const payload = NEEDS_VALUE(next.op) && !next.value ? {} : next;
  emit('update:modelValue', payload);
  emit('change', payload);
  close();
};

const reset = () => {
  emit('update:modelValue', {});
  emit('change', {});
  close();
};

onBeforeUnmount(close);
</script>

<template>
  <span class="relative inline-flex">
    <button
      ref="triggerEl"
      type="button"
      class="inline-flex items-center justify-center rounded size-5 transition-colors hover:bg-n-alpha-2 hover:text-n-slate-12"
      :class="active ? 'text-n-iris-11' : 'text-n-slate-11'"
      :aria-label="active ? '已筛选，点击修改' : '筛选这一列'"
      @click.stop="toggle"
    >
      <span class="i-lucide-chevron-down size-4" />
    </button>

    <teleport :to="teleportTarget">
      <div v-if="open" class="fixed inset-0 z-10" @click="close" />
      <div
        v-if="open"
        ref="popEl"
        class="z-20 w-60 p-2 rounded-lg border shadow-lg border-n-weak bg-n-solid-1"
        :style="popStyle"
        @click.stop
      >
        <ul>
          <li v-for="op in ops" :key="op.value">
            <button
              type="button"
              class="flex items-center justify-between w-full px-2 py-1.5 text-sm text-left rounded hover:bg-n-alpha-1 text-n-slate-12"
              @click="draftOp = op.value"
            >
              <span>{{ op.label }}</span>
              <span
                v-if="draftOp === op.value"
                class="i-lucide-check size-4 text-n-iris-11"
              />
            </button>
          </li>
        </ul>

        <select
          v-if="NEEDS_VALUE(draftOp) && kind === 'enum'"
          v-model="draftValue"
          class="reset-base w-full h-9 px-2 mt-2 text-sm border rounded border-n-weak bg-n-alpha-1 text-n-slate-12"
        >
          <option value="">请选择</option>
          <option v-for="o in options" :key="o.value" :value="o.value">
            {{ o.label }}
          </option>
        </select>
        <input
          v-else-if="NEEDS_VALUE(draftOp)"
          v-model="draftValue"
          type="text"
          class="reset-base w-full h-9 px-2 mt-2 text-sm border rounded border-n-weak bg-n-alpha-1 text-n-slate-12"
          @keyup.enter="apply"
        />

        <div class="flex items-center gap-2 mt-2">
          <button
            type="button"
            class="flex-1 h-8 text-sm rounded border border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
            @click="reset"
          >
            重置
          </button>
          <button
            type="button"
            class="flex-1 h-8 text-sm text-white rounded bg-n-iris-9 hover:bg-n-iris-10"
            @click="apply"
          >
            确定
          </button>
        </div>
      </div>
    </teleport>
  </span>
</template>
